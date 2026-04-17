-- ============================================================
-- 文件名：note.lua
-- 模块职责：负责笔记的创建（含 YAML frontmatter 生成）、
--           vault 内笔记的快速切换（文件跳转），
--           以及基于 ripgrep 的全文搜索入口。
-- 依赖关系：miniobsidian（config、invalidate_cache）、snacks.nvim（picker）
-- 对外 API：M.new_note(title?)、M.new_note_here()、M.new_note_in_dir(dir)
--           M.quick_switch()、M.search(query)、M.follow_or_create(stem)
--           内部辅助：M._create_note(title, dir?)（供测试或外部调用）
-- ============================================================
local M = {}

-- ──────────────────────────────────────────────
-- 私有工具函数
-- ──────────────────────────────────────────────

--- 将任意字符串转义为合法的 YAML 双引号字符串值。
-- YAML 双引号字符串内，反斜杠和双引号需要转义，防止注入破坏 frontmatter 结构。
-- 示例：
--   'Hello "World"' → '"Hello \"World\""'
--   'C:\path'       → '"C:\\path"'
---@param title string 原始标题
---@return string yaml_value 被双引号包裹、已转义的 YAML 值
local function yaml_quote(title)
  -- 先转义反斜杠（必须先于双引号转义，否则新引入的 \\ 会被再次处理）
  -- 再转义双引号
  return '"' .. title:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

--- 根据笔记标题计算其目标文件路径，并确保父目录存在。
-- 路径规则：{target_dir}/{note_id_func(title)}.md
-- 若 target_dir 未指定，回退到 {vault_path}/{notes_subdir}。
---@param title string 笔记标题
---@param target_dir? string 目标目录绝对路径（nil 时使用 notes_subdir）
---@return string filepath 笔记文件的完整绝对路径
local function note_path(title, target_dir)
  local cfg = require("miniobsidian").config
  -- 使用用户配置的 ID 函数将标题转为文件名 slug
  local id  = cfg.note_id_func(title)
  local dir = target_dir or (cfg.vault_path .. "/" .. cfg.notes_subdir)

  -- "p" 参数：递归创建所有中间目录（等同于 mkdir -p）
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. id .. ".md"
end

-- ──────────────────────────────────────────────
-- 文件浏览器上下文检测
-- ──────────────────────────────────────────────

--- 检测当前窗口的文件浏览器类型，返回光标所在位置对应的目录路径。
-- 优先级：snacks explorer → neo-tree → nvim-tree → oil.nvim → netrw
-- 所有 require 均包裹在 pcall 中，任一插件未安装时静默跳过。
-- 规则：
--   • 光标在目录节点上 → 返回该目录
--   • 光标在文件节点上 → 返回该文件的父目录
---@return string|nil dir 目标目录绝对路径（nil 表示无法从文件浏览器检测）
local function get_dir_from_explorer()
  local current_win = vim.api.nvim_get_current_win()
  local ft          = vim.bo.filetype

  -- ── 1. Snacks Explorer ────────────────────────────────────────────────
  -- snacks explorer 是基于 picker 的文件树（source = "explorer"）。
  -- 通过 Snacks.picker.get() 获取活跃实例，校验当前窗口是否为其列表窗口，
  -- 再用 picker:selected({ fallback = true }) 获取光标下条目（无选中时回退到光标项）。
  do
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      local exps_ok, exps = pcall(function()
        return snacks.picker.get({ source = "explorer" })
      end)
      if exps_ok and exps then
        for _, exp in ipairs(exps) do
          local list_win = exp.list and exp.list.win and exp.list.win.win
          if list_win and list_win == current_win then
            local items_ok, items = pcall(function()
              return exp:selected({ fallback = true })
            end)
            if items_ok and items and #items > 0 then
              local path = items[1].file
              if path and path ~= "" then
                -- 去除 oil 风格的末尾斜杠后再判断（snacks explorer 一般无，但防御性处理）
                local clean = path:gsub("/+$", "")
                if vim.fn.isdirectory(path) == 1 then
                  return clean
                else
                  return vim.fn.fnamemodify(clean, ":h")
                end
              end
            end
          end
        end
      end
    end
  end

  -- ── 2. neo-tree ──────────────────────────────────────────────────────
  if ft == "neo-tree" then
    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if ok then
      local state = manager.get_state("filesystem")
      local node  = state and state.tree and state.tree:get_node()
      if node and node.path then
        if node.type == "directory" then
          return node.path
        else
          return vim.fn.fnamemodify(node.path, ":h")
        end
      end
    end
  end

  -- ── 3. nvim-tree ─────────────────────────────────────────────────────
  if ft == "NvimTree" then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      local node_ok, node = pcall(function()
        return api.tree.get_node_under_cursor()
      end)
      if node_ok and node and node.absolute_path then
        if node.type == "directory" then
          return node.absolute_path
        else
          return vim.fn.fnamemodify(node.absolute_path, ":h")
        end
      end
    end
  end

  -- ── 4. oil.nvim ──────────────────────────────────────────────────────
  -- oil 的 get_current_dir() 返回当前正在浏览的目录（含末尾斜杠）。
  -- get_cursor_entry() 返回光标下条目：type = "directory" 时进入子目录。
  if ft == "oil" then
    local ok, oil = pcall(require, "oil")
    if ok then
      local dir_ok, dir = pcall(function() return oil.get_current_dir() end)
      if dir_ok and dir then
        local entry_ok, entry = pcall(function() return oil.get_cursor_entry() end)
        if entry_ok and entry and entry.type == "directory" and entry.name then
          -- 光标在子目录条目上：拼接进入子目录
          return (dir .. entry.name):gsub("/+$", "")
        end
        -- 光标在文件条目，或无法获取条目：使用当前浏览目录
        return dir:gsub("/+$", "")
      end
    end
  end

  -- ── 5. 系统默认（netrw）──────────────────────────────────────────────
  -- b:netrw_curdir 记录 netrw 当前浏览目录。
  -- expand("<cfile>") 在 netrw 中返回光标下的文件/目录名。
  if ft == "netrw" then
    local curdir = vim.b.netrw_curdir
    if curdir and curdir ~= "" then
      local fname = vim.fn.expand("<cfile>")
      if fname and fname ~= "" and fname ~= "." and fname ~= ".." then
        local full = curdir .. "/" .. fname
        if vim.fn.isdirectory(full) == 1 then
          return full
        end
      end
      return curdir
    end
  end

  return nil
end

-- ──────────────────────────────────────────────
-- 公开 API
-- ──────────────────────────────────────────────

--- 新建笔记的对外入口（快捷创建）。
-- 若 title 非空，直接创建并跳转；
-- 若 title 为 nil 或空字符串，先弹出输入框让用户输入标题。
-- 笔记始终创建到 config.notes_subdir 目录（快捷创建，无需关心归档位置）。
-- 副作用：调用 vim.ui.input 时会短暂暂停等待用户输入。
---@param title? string 笔记标题（可选；为 nil 或 "" 时弹出交互输入框）
function M.new_note(title)
  if title and title ~= "" then
    -- 标题已知，直接创建
    M._create_note(title)
  else
    -- 调用 Neovim 内置 UI 输入框（可被 noice.nvim 等插件替换为更美观的实现）
    vim.ui.input({ prompt = "新笔记标题: " }, function(input)
      -- input 为 nil 表示用户按 Esc 取消，input == "" 表示输入为空，均跳过
      if input and input ~= "" then
        M._create_note(input)
      end
    end)
  end
end

--- 在指定目录创建笔记（公开 API，供自定义键映射调用）。
-- 弹出 vim.ui.input 让用户输入标题，在 dir 目录下创建笔记。
-- 适用场景：用户已通过其他方式获得目标目录路径，直接传入。
-- 前置条件：dir 必须为绝对路径且位于当前活跃 vault 内。
---@param dir string 目标目录绝对路径
function M.new_note_in_dir(dir)
  local core = require("miniobsidian")
  dir = dir:gsub("/+$", "")   -- 去除末尾多余斜杠，保持路径格式一致

  if not core.in_vault(dir) then
    vim.notify(
      "[miniobsidian] 目标目录不在当前 vault 内: " .. dir,
      vim.log.levels.WARN
    )
    return
  end

  vim.ui.input({ prompt = "新笔记标题: " }, function(input)
    if input and input ~= "" then
      M._create_note(input, dir)
    end
  end)
end

--- 检测当前文件浏览器上下文，在光标所在目录创建笔记。
-- 支持（按优先级）：snacks explorer → neo-tree → nvim-tree → oil.nvim → netrw
-- 降级策略：
--   • 检测到目录但不在 vault 内 → 发出 WARN 并中止（不静默回退，防止误操作）
--   • 未检测到任何文件浏览器  → 回退到 config.notes_subdir 并给出 INFO 提示
function M.new_note_here()
  local core = require("miniobsidian")
  local dir  = get_dir_from_explorer()

  if dir then
    dir = dir:gsub("/+$", "")
    if not core.in_vault(dir) then
      vim.notify(
        "[miniobsidian] 目标目录不在当前 vault 内: " .. dir,
        vim.log.levels.WARN
      )
      return
    end
  else
    -- 无法从文件浏览器检测，回退到默认 notes_subdir
    dir = core.config.vault_path .. "/" .. core.config.notes_subdir
    vim.notify(
      "[miniobsidian] 未检测到文件树焦点，将创建到默认目录: "
        .. core.config.notes_subdir,
      vim.log.levels.INFO
    )
  end

  vim.ui.input({ prompt = "新笔记标题: " }, function(input)
    if input and input ~= "" then
      M._create_note(input, dir)
    end
  end)
end


--- 执行笔记创建的核心逻辑（内部函数，也可供外部直接调用）。
-- 行为：
--   1. 生成目标路径和 frontmatter 内容。
--   2. 若文件不存在，写入 frontmatter 并刷新路径缓存。
--   3. 若文件已存在，直接跳转（等幂，不覆盖已有内容）。
-- 副作用：
--   • 可能创建新文件（io.open 写入）。
--   • 调用 invalidate_cache() 刷新笔记列表缓存。
--   • 通过 vim.cmd("edit ...") 打开/跳转到文件。
---@param title string 笔记标题（不能为空）
---@param dir?  string 目标目录绝对路径（nil 时使用 notes_subdir）
function M._create_note(title, dir)
  local path     = note_path(title, dir)
  -- 使用用户配置的日期格式，与 Obsidian 保持一致
  local cfg      = require("miniobsidian").config
  local date_str = os.date(cfg.daily_date_format)

  -- 构造标准 YAML frontmatter + 一级标题。
  -- table.concat 比多次字符串拼接效率更高（避免创建中间字符串）。
  -- yaml_quote 确保含特殊字符的标题不破坏 YAML 结构。
  local frontmatter = table.concat({
    "---",
    "title: " .. yaml_quote(title),
    "date: " .. date_str,
    "tags: []",
    "---",
    "",
    "# " .. title,
    "",
  }, "\n")

  -- filereadable 返回 0 表示文件不存在或不可读，此时才写入初始内容
  local is_new = vim.fn.filereadable(path) == 0
  if is_new then
    -- pcall 保护 io.open/write/close 链路：
    --   • 若目录突然被删除、磁盘满等情况，io.open 会返回 nil 而非抛出错误，
    --     需要手动 error() 转为异常，然后由 pcall 捕获。
    local ok, err = pcall(function()
      local f = io.open(path, "w")
      if not f then
        error("无法创建文件: " .. path)
      end
      f:write(frontmatter)
      f:close()
    end)

    if not ok then
      vim.notify("[miniobsidian] 创建笔记失败: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    -- 新文件写入后立即使缓存失效，确保补全列表能立刻看到新笔记
    require("miniobsidian").invalidate_cache()
  end

  -- vim.schedule 的必要性：
  --   当本函数从 vim.ui.input 的回调中被调用时，Neovim 处于 "textlock" 状态，
  --   此时直接调用 vim.cmd("edit ...") 会报 E565 错误。
  --   vim.schedule 将操作推迟到主事件循环的下一个安全时机执行，规避此问题。
  vim.schedule(function()
    -- fnameescape 处理路径中的空格、括号等对 :edit 命令有特殊含义的字符
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    -- 新建笔记时：找到一级标题行，将光标定位到标题下一行（正文起始处）。
    -- 打开已有笔记时不移动光标，保持用户上次的位置。
    if is_new then
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for i, line in ipairs(lines) do
        if line:match("^# ") then
          -- i 是 1-indexed；目标行 = 标题行 + 1，不超过 buffer 末尾
          vim.api.nvim_win_set_cursor(0, { math.min(i + 1, #lines), 0 })
          break
        end
      end
    end
  end)
end

--- 在 vault 内按 stem 查找笔记文件，找到则跳转；找不到则提示用户确认后创建。
-- 供 link.lua 的 follow_link_or_toggle() 调用。
--
-- 匹配策略（按优先级依次尝试，任一命中即跳转）：
--   1. 精确 stem 匹配          — [[my-note]]     → my-note.md
--   2. 大小写不敏感匹配        — [[My Note]]     → my note.md / My-Note.md
--   3. 路径末尾段匹配          — [[folder/note]] → note.md（剥离 Obsidian 路径前缀）
--
-- 创建时使用 bare stem（路径的最后一段），避免 [[folder/note]] 把 "/" 带入文件名。
---@param stem string 从 [[...]] 提取的笔记名（可能含路径前缀）
function M.follow_or_create(stem)
  local core  = require("miniobsidian")
  local notes = core.get_all_notes()

  -- 辅助：打开文件并跳转
  local function jump(path)
    vim.schedule(function()
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end)
  end

  -- ── 1. 精确匹配 ────────────────────────────────────────────────
  for _, path in ipairs(notes) do
    if core.note_stem(path) == stem then
      jump(path); return
    end
  end

  -- ── 2. 大小写不敏感匹配 ────────────────────────────────────────
  -- 处理 [[My Note]] → my-note.md，以及 Obsidian 自动补全生成的混合大小写链接
  local stem_lower = stem:lower()
  for _, path in ipairs(notes) do
    if core.note_stem(path):lower() == stem_lower then
      jump(path); return
    end
  end

  -- ── 3. 剥离路径前缀后再匹配 ────────────────────────────────────
  -- Obsidian 允许 [[folder/note]] 指向特定路径；提取最后一段作为 bare stem，
  -- 避免把 "/" 带入文件名（note_id_func 会将其剔除，导致笔记名拼接错误）
  local bare = stem:match("([^/\\]+)$") or stem

  -- 防御：stem 若全为路径分隔符（如 "/"），match 返回 nil，or 后仍为 "/"，
  -- note_id_func 剔除 "/" 后会生成空字符串 → ".md" 隐藏文件。此处直接拒绝。
  if not bare or bare == "" or bare:match("^[/\\]+$") then
    vim.notify("[miniobsidian] 无法解析链接目标: " .. stem, vim.log.levels.WARN)
    return
  end

  -- 只在 bare != stem 时做第三轮匹配（避免与前两轮重复）
  if bare ~= stem then
    local bare_lower = bare:lower()
    for _, path in ipairs(notes) do
      local s = core.note_stem(path)
      if s == bare or s:lower() == bare_lower then
        jump(path); return
      end
    end
  end

  -- ── 未找到：提示创建 ────────────────────────────────────────────
  -- 用 bare stem 作标题，防止路径字符污染文件名
  local create_title = bare
  vim.schedule(function()
    vim.ui.input(
      { prompt = "笔记 '" .. create_title .. "' 不存在，按 Enter 确认创建（Esc 取消）: " },
      function(input)
        if input ~= nil then
          M._create_note(create_title)
        end
      end
    )
  end)
end


-- 快速切换与全文搜索仅遍历 Markdown 笔记文件。
-- 搜索范围限定为 notes_subdir，避免把模板、附件等非笔记内容混入结果。
local MARKDOWN_EXTS = { "md" }

-- 以 vault_path 为工作目录，打开文件模糊搜索浮窗。
-- 前置条件：需要 snacks.nvim 插件（Snacks.picker.files）。
function M.quick_switch()
  local cfg = require("miniobsidian").config
  local notes_dir = cfg.vault_path .. "/" .. cfg.notes_subdir

  -- pcall 保护 require，避免 snacks.nvim 未安装时崩溃
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    vim.notify("[miniobsidian] 需要 snacks.nvim 插件", vim.log.levels.ERROR)
    return
  end

  snacks.picker.files({
    title  = "  Notes",
    cwd    = notes_dir,
    dirs   = { notes_dir },
    ft     = MARKDOWN_EXTS,
    hidden = false,
  })
end

--- 在 vault 内发起全文搜索（基于 ripgrep）。
-- 以 notes_subdir 为工作目录，通过 Snacks.picker.grep 打开搜索浮窗。
-- 若传入 query，将作为初始搜索词填入输入框。
-- 前置条件：需要 snacks.nvim 插件 + ripgrep（rg）可执行文件。
---@param query? string 初始搜索词（可选；传 nil 时浮窗为空输入状态）
function M.search(query)
  local cfg = require("miniobsidian").config
  local notes_dir = cfg.vault_path .. "/" .. cfg.notes_subdir

  local ok, snacks = pcall(require, "snacks")
  if not ok then
    vim.notify("[miniobsidian] 需要 snacks.nvim 插件", vim.log.levels.ERROR)
    return
  end

  snacks.picker.grep({
    title  = " Notes",
    cwd    = notes_dir,
    dirs   = { notes_dir },
    search = query,
    cmd    = "rg",
    hidden = false,  -- 不搜索隐藏目录中的文件
    glob   = "*.md",  -- 仅搜索 Markdown 笔记文件
  })
end

return M
