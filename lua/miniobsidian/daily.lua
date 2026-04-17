-- ============================================================
-- 文件名：daily.lua
-- 模块职责：每日笔记（Daily Note）功能。
--   • 按 config.daily_date_format 格式化今天的日期作为文件名
--   • 在 vault_path/dailies_folder/ 下创建或打开对应笔记
--   • 新文件自动写入 frontmatter（与 note.lua 风格一致）
-- 依赖关系：miniobsidian（config、invalidate_cache）
-- 对外 API：M.open_today()
-- ============================================================

local M = {}

-- 将日期字符串转义为合法的 YAML 双引号字符串，与 note.lua 的 yaml_quote 保持一致。
-- 避免用户自定义含冒号或引号的 daily_date_format 时破坏 frontmatter 结构。
local function yaml_quote(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

--- 打开（或创建）今日每日笔记。
-- 行为：
--   1. 计算今日日期文件名：os.date(cfg.daily_date_format)
--   2. 确保 vault_path/dailies_folder/ 目录存在（自动 mkdir -p）
--   3. 若文件不存在：写入带 frontmatter 的初始内容，并使 note cache 失效
--   4. 用 vim.cmd("edit ...") 打开文件（vim.schedule 确保不在锁定上下文中调用）
function M.open_today()
  local cfg      = require("miniobsidian").config
  local date_str = os.date(cfg.daily_date_format) --[[@as string]]
  local dir      = cfg.vault_path .. "/" .. cfg.dailies_folder

  -- 确保目录存在
  vim.fn.mkdir(dir, "p")

  local path = dir .. "/" .. date_str .. ".md"

  -- 新文件：写入 frontmatter 并使补全 cache 失效
  local is_new = vim.fn.filereadable(path) == 0
  if is_new then
    local lines = {
      "---",
      "title: " .. yaml_quote(date_str),
      "date: " .. date_str,
      "tags: [daily]",
      "---",
      "",
      "# " .. date_str,
      "",
    }
    -- pcall 保护：磁盘满、权限不足等情况下 io.open 返回 nil，需给用户明确反馈
    local ok, err = pcall(function()
      local f = io.open(path, "w")
      if not f then error("无法创建文件: " .. path) end
      f:write(table.concat(lines, "\n"))
      f:close()
    end)
    if not ok then
      vim.notify("[miniobsidian] 创建每日笔记失败: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    require("miniobsidian").invalidate_cache()
  end

  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    -- 新建时将光标定位到一级标题下一行（正文起始处）
    if is_new then
      local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for i, line in ipairs(buf_lines) do
        if line:match("^# ") then
          vim.api.nvim_win_set_cursor(0, { math.min(i + 1, #buf_lines), 0 })
          break
        end
      end
    end
  end)
end

return M
