-- ============================================================
-- 文件名：checkbox.lua
-- 模块职责：在 Markdown 文件中切换列表项的 checkbox 勾选状态。
--           支持循环切换多种 Obsidian checkbox 状态（可通过 config.checkbox_states 配置）。
--           普通列表项自动升级为 checkbox 首个状态。
--           仅处理标准列表标记（- * +）开头的行，不处理其他格式，
--           以避免误操作 [[wiki link]] 等包含方括号的内容。
-- 依赖关系：miniobsidian（config.checkbox_states）、Neovim 内置 API
-- 对外 API：M.toggle()、M.clear()
-- ============================================================
local M = {}

--- 切换光标所在行的 Markdown checkbox 状态（循环切换）。
-- 匹配规则（按优先级依次检测）：
--   1. 已有任意状态的 checkbox（`^%s*[-*+]%s+%[.-%]`）→ 在 config.checkbox_states 列表中
--      找到当前状态并切换到下一个（循环）；找不到时重置为第一个状态。
--   2. 普通列表项（内容不以 [ 开头）→ 在 marker 后插入第一个 checkbox 状态。
--   3. 其他格式（标题、普通段落、[[wiki link]] 行等）→ 不处理，静默返回。
-- 副作用：直接修改当前 buffer 对应行的内容（nvim_buf_set_lines）。
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()

  -- nvim_win_get_cursor 返回 {row, col}，row 为 1-indexed。
  -- nvim_buf_get_lines / nvim_buf_set_lines 使用 0-indexed 行号，因此减 1。
  local row  = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- 读取当前行内容（第三参数 false 表示不严格检查越界，超出范围时返回空表）
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]

  -- 安全检查：空 buffer 或光标越界时 line 可能为 nil
  if not line then return end

  -- 读取用户配置的状态列表；若配置未加载则回退到默认双态
  local ok, core = pcall(require, "miniobsidian")
  local states = (ok and core.config and core.config.checkbox_states)
    or { " ", "x" }

  -- ── 情况1：已有 checkbox（任意状态字符）→ 循环切换到下一个 ──
  -- pattern 分解：
  --   ^(%s*[-*+]%s+)    → 捕获「缩进 + marker + 空格」前缀
  --   %[([^%[%]]-)%]    → 惰性捕获括号内状态：[^%[%]] 排除 [ 和 ] 字符，
  --                        防止 [[wiki link]] 被误匹配为 checkbox 状态
  --   (.*)$             → 捕获 checkbox 之后的剩余内容
  local prefix, state, suffix = line:match("^(%s*[-*+]%s+)%[([^%[%]]-)%](.*)$")
  if prefix and state ~= nil then
    -- 在 states 列表中查找当前状态，取下一个；找不到时重置为第一个
    local next_state = states[1]
    for i, s in ipairs(states) do
      if s == state then
        next_state = states[(i % #states) + 1]
        break
      end
    end
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false,
      { prefix .. "[" .. next_state .. "]" .. suffix })
    return
  end

  -- ── 情况2：普通列表项（内容不以 [ 开头）→ 升级为 checkbox ──
  -- [^%[] 匹配非 "[" 字符，确保列表项内容不以 [ 开头，
  -- 从而排除 [[wiki link]] 行被误升级为 checkbox 的情况。
  local plain_prefix, rest = line:match("^(%s*[-*+]%s+)([^%[].*)")
  if plain_prefix then
    vim.api.nvim_buf_set_lines(buf, row, row + 1, false,
      { plain_prefix .. "[" .. states[1] .. "] " .. rest })
    return
  end

  -- ── 情况3：其他格式（标题行、空行、[[wiki]] 等），静默跳过 ──
end

--- 将光标所在行的 checkbox 还原为普通列表项（去除 checkbox 标记）。
-- 行为：
--   `- [ ] 任务`  → `- 任务`
--   `- [x] 任务`  → `- 任务`
--   `- [/] 任务`  → `- 任务`
-- 普通列表项、非列表行：静默跳过，不做修改。
-- 使用场景：将任务列表"降级"回普通列表，而不需要经过 toggle 循环一圈。
-- 副作用：直接修改当前 buffer 对应行的内容（nvim_buf_set_lines）。
function M.clear()
  local buf  = vim.api.nvim_get_current_buf()
  local row  = vim.api.nvim_win_get_cursor(0)[1] - 1
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line then return end

  -- 匹配含 checkbox 的列表行：捕获 marker 前缀和方括号之后的内容
  -- pattern：`^(%s*[-*+]%s+)%[[^%[%]]-%]%s?(.*)`
  --   %[[^%[%]]-%]  → 任意状态的 checkbox（排除 [ 和 ] 字符，防止误匹配 [[wiki]] 行）
  --   %s?           → 吃掉 checkbox 后紧跟的一个可选空格
  local prefix, rest = line:match("^(%s*[-*+]%s+)%[[^%[%]]-%]%s?(.*)")
  if not prefix then return end   -- 非 checkbox 行，静默跳过

  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { prefix .. rest })
end

return M
