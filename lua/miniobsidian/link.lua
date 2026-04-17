-- ============================================================
-- 文件名：link.lua
-- 模块职责：检测光标是否位于 Obsidian Wiki 链接（[[...]]）内部，
--           并提供"跟随链接或切换 checkbox"的智能复合操作。
--           跳转策略：直接使用 vault 内文件查找（follow_or_create），
--           不依赖 LSP——LSP definition 可通过 gd 单独使用。
-- 依赖关系：miniobsidian.checkbox（toggle）、miniobsidian.note（follow_or_create）
-- 对外 API：M.link_at_cursor()、M.follow_link_or_toggle()
--           已废弃：M.follow_link()、M.follow_link_or_gf()
-- ============================================================
local M = {}

--- 检测光标当前是否位于一个 [[wiki link]] 内，若是则返回链接目标笔记名。
-- 算法：遍历当前行所有 [[...]] 区间，检查光标列是否落在某个区间内。
-- 返回值语义：
--   • 返回笔记名字符串 → 光标在 wiki link 内
--   • 返回 nil         → 光标不在任何 wiki link 上
-- 支持的 wiki link 格式：
--   [[笔记名]]                    → 简单链接
--   [[笔记名|显示文字]]           → 带别名链接（提取 | 之前的部分）
--   [[笔记名#标题]]               → 带章节锚点（提取 # 之前的部分）
--   [[笔记名#标题|显示文字]]      → 组合格式
---@return string|nil note_name 笔记名（已去除首尾空白），或 nil
function M.link_at_cursor()
  local line = vim.api.nvim_get_current_line()

  -- nvim_win_get_cursor 返回 {row, col}，col 为 0-indexed 字节偏移。
  -- 加 1 转为 1-indexed，与 Lua string 函数的约定保持一致。
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  -- 逐个扫描行内所有 [[...]] 区间（一行可能有多个 wiki link）
  local search_start = 1
  while true do
    -- pattern 说明：
    --   %[%[   → 字面 "[["（% 转义 [ 为普通字符）
    --   (.-)   → 惰性匹配捕获组，尽可能少地匹配（防止跨越多个 [[]] 对）
    --   %]%]   → 字面 "]]"
    -- s, e 分别是整个 [[...]] 的起始/结束 1-indexed 位置
    local s, e, inner = line:find("%[%[(.-)%]%]", search_start)
    if not s then break end   -- 行内无更多 wiki link，退出循环

    -- 判断光标列是否落在当前 [[...]] 的范围内（含两端）
    if col >= s and col <= e then
      -- 提取笔记名：依次去除别名部分（| 及之后）和锚点部分（# 及之后）
      -- 注意：这里的 pattern 使用非贪婪配合可选字符，逐步剥离后缀
      local name = inner:match("^([^|]+)|?") or inner  -- 取 | 之前
      name = name:match("^([^#]+)#?") or name           -- 取 # 之前
      -- 去除首尾空白（%s* 匹配零或多个空白，.- 惰性匹配中间内容）
      name = name:match("^%s*(.-)%s*$")
      -- 空字符串（如 [[]]）视为无效链接，返回 nil
      return name ~= "" and name or nil
    end

    -- 从当前链接结束位置之后继续搜索下一个
    search_start = e + 1
  end

  return nil
end

--- 智能复合操作：光标在 wiki link 上时跳转，否则切换 checkbox 状态。
-- 跳转策略：直接调用 follow_or_create()，在 vault 内按 stem 查找文件。
--   不走 LSP——LSP 的 definition 成功率依赖具体实现，且对 [[wikilink]] 的支持
--   因 LSP 而异。用户如需 LSP 跳转，请另行绑定 gd → vim.lsp.buf.definition()。
-- 行为：
--   • 光标在 [[wiki link]] 上 → follow_or_create(stem)（查找或提示创建）
--   • 光标在 checkbox 行      → toggle()（状态循环切换）
--   • 普通列表项               → toggle() 内部升级为 checkbox
--   • 其他行                   → 静默跳过
function M.follow_link_or_toggle()
  local stem = M.link_at_cursor()
  if stem then
    require("miniobsidian.note").follow_or_create(stem)
    return
  end
  require("miniobsidian.checkbox").toggle()
end

--- @deprecated 该函数已废弃，请改用 markdown-oxide LSP 的 gd 命令跳转链接。
-- 保留此声明是为了避免用户配置中的调用出现"attempt to call nil"错误。
function M.follow_link() end

--- @deprecated 该函数已废弃，请改用 markdown-oxide LSP 的 gd 命令。
-- 原行为：光标不在 wiki link 时回退到 Vim 内置 gf（goto file）命令。
-- 废弃原因：gf 无法处理 [[...]] 格式，容易产生误操作；LSP gd 已覆盖所有场景。
-- 保留为空 stub，防止旧配置中绑定该函数时产生意外跳转行为。
function M.follow_link_or_gf() end

return M
