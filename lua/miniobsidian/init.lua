-- ============================================================
-- 文件名：init.lua
-- 模块职责：miniobsidian.nvim 的核心模块，负责保存插件全局配置、
--           维护 vault 内笔记路径的扫描缓存，并提供路径工具函数。
--           其他所有子模块均通过 require("miniobsidian").config 读取配置。
-- 依赖关系：无外部插件依赖；仅使用 Neovim 内置 API（vim.fn、vim.api）
-- 对外 API：M.setup(opts)、M.get_all_notes(force)、M.invalidate_cache()、
--           M.note_stem(path)、M.in_vault(path)
-- ============================================================
local M = {}

-- ──────────────────────────────────────────────
-- 类型声明（供 LuaLS/neodev 静态分析使用）
-- ──────────────────────────────────────────────

---@class MiniObsidian.Config
---@field vaults_parent string  vault 父目录路径（必填，支持 ~ 展开）
---@field default_vault? string 默认激活的 vault 目录名（省略时取扫描到的第一个）
---@field notes_subdir string   新建笔记存放的子目录（相对当前活跃 vault）
---@field dailies_folder string 每日笔记目录（相对当前活跃 vault）
---@field templates_folder string 模板文件所在目录（相对当前活跃 vault）
---@field attachments_folder string 图片等附件目录（相对当前活跃 vault）
---@field daily_date_format string os.date 格式字符串，用于每日笔记文件名及 frontmatter 日期
---@field note_id_func fun(title: string): string 将标题转为文件名 ID 的函数
---@field checkbox_states string[] checkbox 循环切换状态列表（如 { " ", "/", "x", "-" }）
---@field vault_path string 当前活跃 vault 的绝对路径（运行时内部字段，由 setup 自动派生，请勿手动设置）

-- ──────────────────────────────────────────────
-- 默认配置
-- ──────────────────────────────────────────────

--- 插件默认配置，用户通过 M.setup(opts) 覆盖其中的部分字段。
-- vault_path 为运行时内部字段，由 setup() 从 vaults_parent 扫描派生，无需手动设置。
M.config = {
  vaults_parent      = "",
  default_vault      = "",
  vault_path         = "",   -- 内部字段：当前活跃 vault 的绝对路径，由 setup() 自动设置
  notes_subdir       = "Notes",
  dailies_folder     = "Dailies",
  templates_folder   = "Templates",
  attachments_folder = "Assets",
  daily_date_format  = "%Y-%m-%d",

  --- Checkbox 循环切换状态列表（按顺序循环）。
  -- 默认覆盖 Obsidian 最常用的 4 种状态：未完成→进行中→已完成→已取消。
  -- 可自定义：设为 { " ", "x" } 即回退到经典双态切换。
  checkbox_states = { " ", "x"},

  --- 默认笔记 ID 函数：将标题转换为适合作文件名的小写 slug。
  -- 规则：保留中文、ASCII 字母数字、空格 → 空格变 "-" → 转小写。
  -- 示例：
  --   "Hello World"  → "hello-world"
  --   "我的笔记 2024" → "我的笔记-2024"
  --   "A & B!"       → "a-b"  （& 和 ! 被剔除后两侧空格合并为单个连字符）
  ---@param title string 笔记标题
  ---@return string id  用作文件名的 slug
  note_id_func = function(title)
    -- pattern 说明：
    --   %w                   → ASCII 字母和数字（[a-zA-Z0-9]）
    --   %s                   → 空白字符（空格、Tab 等）
    --   \u{2E80}-\u{9FFF}   → CJK 部首补充、笔画、汉字扩展A、康熙字典部首、
    --                          注音符号、平假名、片假名、基本 CJK 统一汉字
    --   \u{AC00}-\u{D7AF}   → 韩语谚文音节块
    --   \u{F900}-\u{FAFF}   → CJK 兼容汉字
    -- 取反（[^ ...]）意味着删掉以上范围以外的所有字符（标点、特殊符号等）
    local id = title:gsub("[^%w%s\u{2E80}-\u{9FFF}\u{AC00}-\u{D7AF}\u{F900}-\u{FAFF}]", "")

    -- 将一个或多个连续空白替换为单个连字符，生成 kebab-case 风格 slug
    id = id:gsub("%s+", "-")

    -- string.lower 仅影响 ASCII 范围，中文字符不受影响
    id = id:lower()
    return id
  end,
}

-- ──────────────────────────────────────────────
-- 笔记路径扫描缓存
-- ──────────────────────────────────────────────

--- 缓存：存储上一次 globpath 扫描的结果（string[] 或 nil）
local _cache = nil

--- 缓存时间戳：上次扫描时 os.time() 的值（秒级 Unix 时间戳）
local _cache_time = 0

--- 缓存有效期（秒）。设为 5 秒：
--   • 补全触发非常频繁，避免每次按键都调用 globpath（磁盘 I/O）。
--   • 5 秒足够短，不会让新建/删除的笔记长时间不可见。
--   • 写入文件时会主动调用 invalidate_cache()，正常情况几乎不会用到过期。
local CACHE_TTL = 5

-- ──────────────────────────────────────────────
-- 公开 API
-- ──────────────────────────────────────────────

--- 当前活跃 vault 的目录名（供 lualine 等状态栏插件读取）。
-- 由 setup() 初始化，切换 vault 后由 vault.do_switch() 更新。
M.active_vault_name = ""

--- 获取 vault 内所有 .md 文件的绝对路径列表。
-- 结果带 5 秒内存缓存，避免频繁调用 globpath 造成的 I/O 开销。
-- 副作用：若 vault_path 目录不存在，发出 WARN 级通知并返回空表。
---@param force? boolean 传 true 时跳过缓存，强制重新扫描（例如手动刷新场景）
---@return string[] paths 所有 .md 文件的绝对路径列表（可能为空表）
function M.get_all_notes(force)
  local now = os.time()

  -- 命中缓存的条件：未强制刷新 AND 缓存非空 AND 未过期
  if not force and _cache and (now - _cache_time) < CACHE_TTL then
    return _cache
  end

  local vault = M.config.vault_path

  -- 检查 vault 目录是否存在，isdirectory 返回 0 表示不存在或是文件
  if vim.fn.isdirectory(vault) == 0 then
    vim.notify("[miniobsidian] vault_path 不存在: " .. vault, vim.log.levels.WARN)
    return {}
  end

  -- globpath 第三参数 false：不忽略通配符特殊字符
  -- globpath 第四参数 true ：返回 table 而非换行分隔的字符串（Neovim 扩展）
  -- "**/*.md" 递归匹配所有子目录下的 .md 文件
  local raw = vim.fn.globpath(vault, "**/*.md", false, true)

  -- 过滤：排除路径中含有隐藏目录段（以 "." 开头）的文件，
  -- 避免 .obsidian/、.git/ 等目录下的 .md 文件混入笔记列表。
  local notes = {}
  local prefix_len = #vault + 2  -- 跳过 "vault/" 前缀，得到相对路径起始位置
  for _, p in ipairs(raw) do
    local rel = p:sub(prefix_len)
    local hidden = false
    for seg in rel:gmatch("[^/]+") do
      if seg:sub(1, 1) == "." then hidden = true; break end
    end
    if not hidden then notes[#notes + 1] = p end
  end

  _cache = notes
  _cache_time = now
  return _cache
end

--- 主动使笔记缓存失效。
-- 在新建、删除笔记后调用，确保下次 get_all_notes() 能看到最新文件列表。
-- 副作用：将 _cache 置 nil，_cache_time 归零。
function M.invalidate_cache()
  _cache = nil
  _cache_time = 0
end

--- 返回当前笔记路径缓存的时间戳（供 completion.lua 判断 items 缓存是否需要重建）。
-- 当 invalidate_cache() 被调用后返回 0；重新扫描后返回最新的 os.time() 值。
-- 通过公开方法暴露，而非让外部模块直接访问私有变量 _cache_time。
---@return number 缓存时间戳（秒级 Unix 时间戳，0 表示无缓存）
function M.get_cache_stamp()
  return _cache_time
end

--- 从笔记绝对路径中提取文件 stem（文件名去掉 .md 后缀）。
-- 示例："/vault/Notes/hello-world.md" → "hello-world"
-- 边界情况：若路径不包含 .md 后缀，原样返回整条路径（避免返回 nil）。
---@param path string 笔记的绝对路径
---@return string stem 文件名（不含 .md）
function M.note_stem(path)
  -- pattern 说明：
  --   [^/\\]+ → 匹配最后一段路径（文件名），贪婪匹配非斜杠字符
  --   %.md$   → 匹配字符串末尾的字面 ".md"（% 转义 . 为普通字符）
  return path:match("([^/\\]+)%.md$") or path
end

--- 判断给定路径是否位于 vault 内部。
-- 用于 completion、autocmd 等场景，只对 vault 内的 buffer 启用插件功能。
-- 边界情况：
--   • path 为 nil 或空字符串时返回 false（避免 nil 访问错误）
--   • path 恰好等于 vault_path 本身时返回 true（打开 vault 根目录的情况）
---@param path string 要检查的文件路径（通常来自 nvim_buf_get_name）
---@return boolean 是否在 vault 内
function M.in_vault(path)
  if not path or path == "" then return false end
  local vault = M.config.vault_path

  -- 确保比较前缀时 vault 末尾有 "/"，防止 "/vault-other/note.md" 被误判为在内
  -- 例如 vault = "/a/b"，则 vault_prefix = "/a/b/"，避免 "/a/b2/x.md" 误判
  local vault_prefix = vault:sub(-1) == "/" and vault or vault .. "/"
  return vim.startswith(path, vault_prefix) or path == vault
end

--- 插件入口函数：合并用户配置、扫描 vault 列表并完成初始化。
-- 必须在 Neovim 启动过程中调用（通常在 lazy.nvim 的 config 回调里）。
-- 副作用：
--   1. 使用 vim.tbl_deep_extend 深度合并，用户只需提供要覆盖的字段。
--   2. 展开 vaults_parent 中的 ~ 为实际 home 目录。
--   3. 扫描 vaults_parent 下含 .obsidian/ 的子目录，按 default_vault 或首个结果
--      设置内部字段 config.vault_path 和 active_vault_name。
--   4. 触发 User MiniObsidianSetup 事件，plugin/miniobsidian.lua 监听该事件
--      以注册 BufWritePost autocmd（延迟注册，确保 config 已就绪）。
---@param opts? MiniObsidian.Config 用户配置（部分字段覆盖默认值）
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- 展开 vaults_parent 中的 ~ 和环境变量
  M.config.vaults_parent = vim.fn.expand(M.config.vaults_parent)

  -- 扫描 vaults_parent，发现有效 vault 并设置初始活跃 vault
  local vault  = require("miniobsidian.vault")
  vault.refresh_vaults()   -- 清除旧缓存，确保本次 setup 使用最新扫描结果
  local vaults = vault.list_vaults(M.config.vaults_parent)

  if #vaults == 0 then
    vim.notify(
      "[miniobsidian] vaults_parent 下未找到有效的 vault（需含 .obsidian/ 目录）: "
        .. M.config.vaults_parent,
      vim.log.levels.ERROR
    )
  else
    -- 默认使用第一个 vault
    local target = vaults[1]

    -- 若用户指定了 default_vault，尝试匹配
    if M.config.default_vault ~= "" then
      local found = false
      for _, v in ipairs(vaults) do
        if v.name == M.config.default_vault then
          target = v
          found  = true
          break
        end
      end
      if not found then
        vim.notify(
          "[miniobsidian] default_vault '" .. M.config.default_vault
            .. "' 未找到，使用第一个 vault：" .. target.name,
          vim.log.levels.WARN
        )
      end
    end

    M.config.vault_path = target.path
    M.active_vault_name = target.name
  end

  -- 触发自定义 User 事件，通知 plugin/miniobsidian.lua 注册后续 autocmd。
  vim.api.nvim_exec_autocmds("User", { pattern = "MiniObsidianSetup" })
end

return M
