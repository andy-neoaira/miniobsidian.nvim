-- ============================================================
-- 文件名：template.lua
-- 模块职责：从 vault 的 Templates 目录中选择一个模板文件，
--           替换其中的 {{date}}、{{time}}、{{title}} 等占位变量，
--           然后将内容插入到当前 buffer 的光标位置之后。
-- 依赖关系：miniobsidian（config）、snacks.nvim（picker.select，可选回退至 vim.ui.select）
-- 对外 API：M.new_template()、M.insert()
-- ============================================================
local M = {}

-- ──────────────────────────────────────────────
-- 私有工具函数
-- ──────────────────────────────────────────────

--- 将模板内容中的 Obsidian 风格占位变量替换为实际值。
-- 支持的变量（大小写不敏感，覆盖常见写法）：
--   {{date}} / {{Date}} / {{DATE}}         → 当前日期（格式由 config.daily_date_format 决定）
--   {{time}} / {{Time}} / {{TIME}}         → 当前时间 HH:MM
--   {{title}} / {{Title}} / {{TITLE}}      → 当前文件名（不含扩展名）
--   {{filename}} / {{Filename}} / {{FILENAME}} → 同 {{title}}
--   {{yesterday}} / {{Yesterday}} / {{YESTERDAY}} → 昨天日期
--   {{tomorrow}} / {{Tomorrow}} / {{TOMORROW}}    → 明天日期
--   {{date:FORMAT}}                        → 自定义格式日期（如 {{date:YYYY/MM/DD}}）
-- 替换策略：
--   Lua 的 gsub 不支持忽略大小写（无 /i 标志），
--   因此手动列出常见大小写组合（首字母大写、全大写、全小写）。
--   使用函数替换（gsub 第三参数为函数）而非字符串替换，
--   是为了避免替换值中含有 % 字符（如 "50% done"）被 gsub 误解为捕获引用（%1 等）。
---@param content string 模板原始文本
---@param title string   当前文件标题（用于替换 {{title}} / {{filename}}）
---@return string        替换完占位变量后的文本
local function substitute(content, title)
  local cfg  = require("miniobsidian").config
  local now  = os.time()

  -- 使用用户配置的日期格式（默认 "%Y-%m-%d"）
  local date_str = os.date(cfg.daily_date_format, now)
  local time_str = os.date("%H:%M", now)
  -- 昨天/明天：±86400 秒（忽略夏令时边界，笔记场景可接受）
  local yest_str = os.date(cfg.daily_date_format, now - 86400)
  local tmrw_str = os.date(cfg.daily_date_format, now + 86400)

  -- 处理 {{date:FORMAT}} 内联自定义格式（优先于普通 {{date}}）
  -- 支持 Obsidian 风格格式：YYYY → %Y，MM → %m，DD → %d，HH → %H，mm → %M，ss → %S
  -- 注意：mm 必须在 ss 之前处理，互不干扰；YYYY/MM 等长格式先处理，防止 DD 吞掉 D
  content = content:gsub("{{date:([^}]+)}}", function(fmt)
    local lua_fmt = fmt
      :gsub("YYYY", "%%Y")
      :gsub("MM",   "%%m")
      :gsub("DD",   "%%d")
      :gsub("HH",   "%%H")
      :gsub("mm",   "%%M")
      :gsub("ss",   "%%S")  -- 秒，必须在 mm→%M 之后添加，避免影响 mm 匹配
    return os.date(lua_fmt, now)
  end)

  -- 替换规则表：{ pattern, replacement_value }
  local replacements = {
    { "{{[Dd]ate}}",        date_str },   -- {{date}} / {{Date}}
    { "{{DATE}}",           date_str },   -- {{DATE}}
    { "{{[Tt]ime}}",        time_str },   -- {{time}} / {{Time}}
    { "{{TIME}}",           time_str },   -- {{TIME}}
    { "{{[Tt]itle}}",       title    },   -- {{title}} / {{Title}}
    { "{{TITLE}}",          title    },   -- {{TITLE}}
    { "{{[Ff]ilename}}",    title    },   -- {{filename}} / {{Filename}}（= title）
    { "{{FILENAME}}",       title    },   -- {{FILENAME}}
    { "{{[Yy]esterday}}",   yest_str },   -- {{yesterday}} / {{Yesterday}}
    { "{{YESTERDAY}}",      yest_str },   -- {{YESTERDAY}}
    { "{{[Tt]omorrow}}",    tmrw_str },   -- {{tomorrow}} / {{Tomorrow}}
    { "{{TOMORROW}}",       tmrw_str },   -- {{TOMORROW}}
  }

  for _, pair in ipairs(replacements) do
    local replacement = pair[2]
    -- 使用闭包返回替换字符串，规避 gsub 对 % 的特殊解释
    content = content:gsub(pair[1], function() return replacement end)
  end

  return content
end

-- ──────────────────────────────────────────────
-- 公开 API
-- ──────────────────────────────────────────────

--- 快速创建一个新模板文件并打开编辑。
-- 流程：
--   1. 若 name 非空直接使用；否则弹出输入框让用户输入模板名称。
--   2. 在 templates_dir/ 下创建同名 .md 文件，写入含常用占位变量的骨架内容。
--   3. 打开文件并将光标定位到正文起始行。
-- 副作用：创建新文件（若已存在则直接打开，不覆盖）。
---@param name? string 模板名称（不含扩展名；为 nil 时弹出交互输入框）
function M.new_template(name)
  local cfg           = require("miniobsidian").config
  local templates_dir = cfg.vault_path .. "/" .. cfg.templates_folder
  vim.fn.mkdir(templates_dir, "p")

  local function do_create(input_name)
    if not input_name or input_name == "" then return end

    -- 净化文件名：移除路径分隔符，防止目录穿越
    input_name = input_name:gsub("[/\\]", "-")

    local path = templates_dir .. "/" .. input_name .. ".md"

    -- 若文件已存在直接打开，不覆盖
    if vim.fn.filereadable(path) == 0 then
      -- 骨架内容：包含 frontmatter 和最常用的占位变量说明
      local skeleton = table.concat({
        "---",
        "title: {{title}}",
        "date: {{date}}",
        "tags: []",
        "---",
        "",
        "# {{title}}",
        "",
        "> 📅 {{date}}  ·  🕐 {{time}}",
        "",
        "---",
        "",
        "",
      }, "\n")

      local ok, err = pcall(function()
        local f = io.open(path, "w")
        if not f then error("无法创建文件: " .. path) end
        f:write(skeleton)
        f:close()
      end)

      if not ok then
        vim.notify("[miniobsidian] 创建模板失败: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
    end

    vim.schedule(function()
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      -- 光标定位到骨架末尾空行（正文起始处）
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      vim.api.nvim_win_set_cursor(0, { #lines, 0 })
    end)
  end

  if name and name ~= "" then
    do_create(name)
  else
    vim.ui.input({ prompt = "模板名称: " }, do_create)
  end
end

--- 弹出模板选择器，将用户选择的模板内容（变量替换后）插入到光标之后。
-- 完整流程：
--   1. 扫描 templates_dir（*.md）获取模板文件列表。
--   2. 弹出选择 UI（优先 Snacks.picker.select，回退 vim.ui.select）。
--   3. 读取所选模板文件，替换占位变量。
--   4. 通过 vim.schedule 在主循环中执行 buffer 插入操作。
-- 副作用：修改当前 buffer 内容，移动光标到插入内容末尾。
function M.insert()
  local cfg           = require("miniobsidian").config
  local templates_dir = cfg.vault_path .. "/" .. cfg.templates_folder

  -- 递归扫描模板目录下所有 .md 文件（**/*.md 支持子文件夹，第三参数 false 不包含点开头）
  -- 常见用法：Templates/Daily/*.md, Templates/Projects/*.md 等子目录结构
  local files = vim.fn.globpath(templates_dir, "**/*.md", false, true)

  if #files == 0 then
    vim.notify(
      "[miniobsidian] 模板目录为空或不存在: " .. templates_dir,
      vim.log.levels.WARN
    )
    return
  end

  -- 构建显示名称列表和名称→路径的映射表
  local names        = {}
  local name_to_path = {}
  for _, path in ipairs(files) do
    -- ":t:r" modifier：:t 取文件名部分，:r 去掉扩展名
    -- 示例："/vault/Templates/daily.md" → "daily"
    local name = vim.fn.fnamemodify(path, ":t:r")
    table.insert(names, name)
    name_to_path[name] = path
  end

  -- 获取当前 buffer 文件名（不含路径和扩展名）作为 {{title}} 的替换值
  -- "%:t:r" 等价于 fnamemodify 的 ":t:r"
  local buf_name = vim.fn.expand("%:t:r")
  -- 新建 buffer 还未保存时 buf_name 为空字符串，此时用 "Untitled" 兜底
  local title    = buf_name ~= "" and buf_name or "Untitled"

  -- 选择 UI：优先使用 Snacks.picker.select（支持模糊搜索，体验更好）
  -- 若 snacks 不可用，回退到 Neovim 内置 vim.ui.select（可被 telescope 等替换）
  local ok_snacks, snacks = pcall(require, "snacks")
  local select_fn
  if ok_snacks and snacks.picker and snacks.picker.select then
    -- 包装为统一接口（items, opts, on_choice），与 vim.ui.select 签名一致
    select_fn = function(items, opts, on_choice)
      snacks.picker.select(items, opts, on_choice)
    end
  else
    select_fn = vim.ui.select
  end

  select_fn(names, {
    prompt = "选择模板:",
  }, function(choice)
    -- choice 为 nil 表示用户取消选择（按 Esc 或关闭浮窗）
    if not choice then return end

    local path = name_to_path[choice]
    if not path then return end  -- 防御性检查，理论上不会触发

    -- pcall 保护文件读取：
    --   • io.open 失败时返回 nil 而非抛出错误，需手动 error() 转为异常
    --   • 确保文件句柄在异常情况下也能被正确关闭（f:close() 已在 pcall 内）
    local ok, lines = pcall(function()
      local f = io.open(path, "r")
      if not f then error("无法读取模板: " .. path) end
      local content = f:read("*a")  -- "*a" 一次性读取全部内容
      f:close()
      return content
    end)

    if not ok then
      -- lines 在失败时保存的是 pcall 捕获到的错误信息字符串
      vim.notify("[miniobsidian] 读取模板失败: " .. tostring(lines), vim.log.levels.ERROR)
      return
    end

    -- 执行占位变量替换
    local content = substitute(lines, title)

    -- vim.schedule 的必要性：
    --   select_fn（无论是 snacks 还是 vim.ui.select）的回调可能在 Neovim
    --   处于"textlock"状态时执行（某些 UI 实现会异步回调）。
    --   将 buffer 操作推迟到主事件循环的下一个安全时机，避免 E565 错误。
    vim.schedule(function()
      -- 将模板文本按 "\n" 分割为行列表（plain = true：不将 \n 视为 Lua pattern）
      local insert_lines = vim.split(content, "\n", { plain = true })

      -- 去掉末尾多余的空行：文件以 \n 结尾时，split 会产生一个空字符串作为最后元素
      if insert_lines[#insert_lines] == "" then
        table.remove(insert_lines, #insert_lines)
      end

      -- 获取当前光标行（1-indexed）；插入到该行之后（即 row 到 row 之间，不替换任何行）
      local row = vim.api.nvim_win_get_cursor(0)[1]
      -- nvim_buf_set_lines 的 start/end 均为 0-indexed：
      --   start = row（光标下方），end = row（不替换），插入效果
      vim.api.nvim_buf_set_lines(0, row, row, false, insert_lines)

      -- 将光标移动到插入内容最后一行的行首（列为 0）
      vim.api.nvim_win_set_cursor(0, { row + #insert_lines, 0 })
    end)
  end)
end

return M
