-- ============================================================
-- 文件名：image.lua
-- 模块职责：将 macOS 剪贴板中的图片保存到 vault 的附件目录，
--           并在当前 buffer 的光标后插入对应的 Markdown 图片链接。
--           使用 macOS 内置的 osascript（JXA）实现，无需安装任何第三方工具。
--           • 自动检测剪贴板图片格式（PNG / JPEG / GIF），按原始格式保存。
--           • 非 macOS 系统调用 paste_img() 时发出友好提示，不报错不崩溃。
-- 依赖关系：miniobsidian（config）、macOS 内置 osascript（仅 macOS 有效）
--           lua/miniobsidian/scripts/paste_image.js（JXA 脚本）
--           Neovim >= 0.10（vim.system API）
-- 对外 API：M.paste_img(name)
-- ============================================================
local M = {}

-- ── 平台检测（模块加载时一次性完成，避免每次调用重复检测）────────
local IS_MACOS = vim.fn.has("mac") == 1

-- JXA 脚本的绝对路径：与本模块同目录下的 scripts/paste_image.js。
-- debug.getinfo(1, "S").source 返回 "@/absolute/path/to/image.lua"，
-- sub(2) 去掉 "@" 前缀，match 取出目录部分。
-- 这样无论插件被安装在哪个路径都能正确定位脚本。
local _M_DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])")
local PASTE_SCRIPT = _M_DIR .. "scripts/paste_image.js"

--- 计算从 from_dir 到 to_path 的相对路径（纯 Lua 实现，无外部依赖）。
-- 算法：找最长公共目录前缀，用 "../" 向上回退，拼接目标剩余路径。
-- 提升为模块级函数，避免在每次 do_paste 调用时重复创建函数对象。
---@param from_dir string 起始目录（绝对路径）
---@param to_path  string 目标文件（绝对路径）
---@return string
local function relative_path(from_dir, to_path)
  from_dir = from_dir:gsub("/$", "")
  local parts_from = vim.split(from_dir, "/", { plain = true })
  local parts_to   = vim.split(to_path,  "/", { plain = true })
  if parts_from[1] == "" then table.remove(parts_from, 1) end
  if parts_to[1]   == "" then table.remove(parts_to,   1) end
  local common = 0
  for i = 1, math.min(#parts_from, #parts_to) do
    if parts_from[i] == parts_to[i] then
      common = i
    else
      break
    end
  end
  local result = {}
  for _ = 1, #parts_from - common do
    table.insert(result, "..")
  end
  for i = common + 1, #parts_to do
    table.insert(result, parts_to[i])
  end
  return table.concat(result, "/")
end

--- 将剪贴板图片保存到 vault 附件目录，并在光标后插入 Markdown 图片链接。
--
-- 完整流程：
--   1. 平台检测：非 macOS 友好提示并退出。
--   2. 若 name 为 nil，弹出输入框让用户命名（留空则使用时间戳）。
--   3. 净化文件名（移除路径分隔符、防止路径遍历）。
--   4. 确保附件目录存在，调用 osascript JXA 脚本保存图片。
--   5. 从 stdout 读取实际使用的扩展名（png / jpg / gif）。
--   6. 计算相对路径，在光标下方插入 `![](relative/path.ext)` 链接。
--
-- 边界情况：
--   • 非 macOS：友好提示，不报错。
--   • 剪贴板无图片：osascript 返回非零退出码，发出 WARN 并退出。
--   • buffer 未保存（无路径）：使用 vault 相对路径作为回退。
--   • osascript 脚本缺失（安装损坏）：发出 ERROR 并退出。
---@param name? string 图片文件名（不含扩展名；为 nil 时弹出输入框）
function M.paste_img(name)
  -- 非 macOS 系统：功能不可用，友好提示后静默返回
  if not IS_MACOS then
    vim.notify("[miniobsidian] 图片粘贴功能仅支持 macOS", vim.log.levels.WARN)
    return
  end

  -- 防御性检查：脚本文件是否存在（安装损坏时的兜底）
  if vim.fn.filereadable(PASTE_SCRIPT) == 0 then
    vim.notify(
      "[miniobsidian] 内部错误：找不到 paste_image.js，请重新安装插件\n路径: " .. PASTE_SCRIPT,
      vim.log.levels.ERROR
    )
    return
  end

  local cfg = require("miniobsidian").config

  --- 执行图片保存与链接插入的核心逻辑。
  ---@param img_name string 用户输入的文件名（prompt 已预填时间戳，此处仅作空值兜底）
  local function do_paste(img_name)
    -- prompt 已预填时间戳默认值；此处仅在极少数空值情形下作最终兜底
    if not img_name or img_name == "" then
      img_name = os.date("image-%Y%m%d-%H%M%S")
    end

    -- 净化文件名：过滤路径分隔符、NUL 字节与路径遍历
    img_name = img_name:gsub("[/\\%z]", "-"):gsub("%.%.", "-")

    -- 用户若误带扩展名（如 "photo.png"），剔除以避免双后缀
    img_name = img_name:gsub("%.[a-zA-Z0-9]+$", "")

    local attach_dir = cfg.vault_path .. "/" .. cfg.attachments_folder
    vim.fn.mkdir(attach_dir, "p")

    -- base_path 不含扩展名：JXA 脚本检测格式后追加正确后缀并返回
    local base_path = attach_dir .. "/" .. img_name

    -- ── 调用 osascript JXA 脚本 ────────────────────────────
    -- 使用列表形式传参，路径中的空格等特殊字符由 OS 进程 API 处理，无需 shell 转义。
    -- :wait() 同步等待（~120ms），对用户主动触发的粘贴操作完全可接受。
    local proc = vim.system(
      { "osascript", "-l", "JavaScript", PASTE_SCRIPT, base_path },
      { text = true }   -- 确保 stdout/stderr 作为字符串返回
    ):wait()

    if proc.code ~= 0 then
      -- 解析 stderr 中的错误关键字，给出可读提示
      local err = proc.stderr or ""
      if err:find("NO_IMAGE") then
        vim.notify("[miniobsidian] 剪贴板中没有图片（或格式不支持）", vim.log.levels.WARN)
      elseif err:find("NOT_IMAGE_FILE") then
        vim.notify("[miniobsidian] 剪贴板中的文件不是图片格式", vim.log.levels.WARN)
      elseif err:find("WRITE_FAILED") then
        vim.notify(
          "[miniobsidian] 图片写入失败，请检查目录权限: " .. attach_dir,
          vim.log.levels.ERROR
        )
      elseif err:find("CONVERT_FAILED") or err:find("BITMAP_FAILED") or err:find("TIFF_FAILED") then
        vim.notify("[miniobsidian] 图片格式转换失败，剪贴板内容可能不是标准图片", vim.log.levels.ERROR)
      else
        -- 兜底：截取 stderr 第一行作为错误信息
        local first_line = err:match("[^\n]+") or "未知错误"
        vim.notify("[miniobsidian] 图片保存失败: " .. first_line, vim.log.levels.ERROR)
      end
      return
    end

    -- 从 stdout 读取实际扩展名（"png" / "jpg" / "gif"）
    -- 使用模式匹配去除首尾空白，默认 "png" 作为安全兜底；:lower() 防御意外大写
    local ext      = ((proc.stdout or ""):match("^%s*(%a+)%s*$") or "png"):lower()
    local img_file = img_name .. "." .. ext
    local abs_path = base_path .. "." .. ext

    -- ── 计算相对路径 ──────────────────────────────────────
    -- 相对路径可在 vault 移动位置后继续有效，与 Obsidian 桌面端行为一致。
    local buf_dir = vim.fn.expand("%:p:h")
    local rel_path

    if buf_dir and buf_dir ~= "" then
      rel_path = relative_path(buf_dir, abs_path)
    else
      -- buffer 未保存时回退：使用相对于 vault 根的路径
      rel_path = cfg.attachments_folder .. "/" .. img_file
    end

    -- 插入 Markdown 图片链接到光标下方，并将光标移到新行
    local md_link = string.format("![](%s)", rel_path)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row, row, false, { md_link })
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })

    vim.notify("[miniobsidian] 图片已保存: " .. abs_path, vim.log.levels.INFO)
  end

  -- 根据参数决定是否弹出交互输入框
  if name ~= nil then
    do_paste(name)
  else
    vim.ui.input(
      {
        prompt = "图片文件名（不含扩展名）: ",
        default = os.date("image-%Y%m%d-%H%M%S"),
      },
      function(input)
        -- input 为 nil 表示用户按 Esc 取消
        if input ~= nil then
          do_paste(input)
        end
      end
    )
  end
end

return M
