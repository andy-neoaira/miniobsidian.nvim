-- ============================================================
-- 文件名：miniobsidian.lua（plugin/）
-- 模块职责：Neovim 插件入口文件，由 Neovim 在 'runtimepath' 扫描时自动加载。
--           负责注册所有用户命令（:ObsidianXxx）和全局 autocmd，
--           将命令实现委托给 lua/miniobsidian/ 下的各子模块（延迟 require，
--           确保子模块在首次实际使用时才被加载，不影响启动速度）。
--           本文件不设置任何按键映射，用户需自行在配置中绑定快捷键。
-- 依赖关系：miniobsidian（init）、miniobsidian.note、miniobsidian.template、
--           miniobsidian.image、miniobsidian.daily（均为延迟 require）
-- 对外 API：用户命令 ObsidianNew / ObsidianSwitch / ObsidianSearch /
--           ObsidianTemplate / ObsidianPasteImg / ObsidianToday / ObsidianSetup
-- 自定义事件：User MiniObsidianSetup（setup 完成后触发）
--             User MiniObsidianVaultSwitch（切换 vault 后触发，data = {name, path}）
-- ============================================================

-- ── 防止重复加载 ───────────────────────────────────────────────
-- Neovim 在某些情况下（如 :source %、重新加载 runtimepath）会重复执行 plugin 目录下的文件。
-- vim.g.loaded_miniobsidian 作为全局标记，确保本文件的注册逻辑只执行一次。
if vim.g.loaded_miniobsidian then return end
vim.g.loaded_miniobsidian = true

-- ── 用户命令注册 ───────────────────────────────────────────────
-- 所有命令均使用延迟 require（在回调中 require，而非顶层 require），
-- 这样只有在实际执行命令时才加载对应模块，减少插件对启动时间的影响。

--- :ObsidianNew [title]
-- 新建一篇笔记（快捷创建，始终落到 notes_subdir 目录）。title 可选：
--   • 提供 title：直接在 notes_subdir 目录创建并跳转。
--   • 不提供（nargs="?"）：弹出 vim.ui.input 交互框让用户输入标题。
vim.api.nvim_create_user_command("ObsidianNew", function(opts)
  -- opts.args 为空字符串（用户未提供参数）时传 nil，触发交互输入框
  require("miniobsidian.note").new_note(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",                -- 接受 0 或 1 个参数
  desc  = "新建 Obsidian 笔记（到默认 notes_subdir 目录）",
})

--- :ObsidianNewHere
-- 检测当前文件浏览器焦点所在目录，在该目录下新建笔记。
-- 支持（按优先级）：snacks explorer → neo-tree → nvim-tree → oil.nvim → netrw
-- 目标目录必须在当前 vault 内；无法检测文件浏览器时回退到 notes_subdir。
-- 无参数。
vim.api.nvim_create_user_command("ObsidianNewHere", function()
  require("miniobsidian.note").new_note_here()
end, {
  desc = "在当前文件树目录下新建笔记",
})

--- :ObsidianSwitchVault
-- 弹出 vault 选择器，切换当前活跃 vault。
-- 无参数。
vim.api.nvim_create_user_command("ObsidianSwitchVault", function()
  require("miniobsidian.vault").pick_and_switch()
end, {
  desc = "切换当前活跃 vault",
})

--- :ObsidianSwitch
-- 通过 Snacks.picker 打开 vault 内文件的模糊搜索浮窗，快速跳转到任意笔记。
-- 无参数。
vim.api.nvim_create_user_command("ObsidianSwitch", function()
  require("miniobsidian.note").quick_switch()
end, {
  desc = "快速切换 vault 内的笔记（Snacks picker）",
})

--- :ObsidianSearch [query]
-- 通过 Snacks.picker + ripgrep 在 vault 内全文搜索。
-- query 可选：提供时作为初始搜索词填入浮窗输入框。
vim.api.nvim_create_user_command("ObsidianSearch", function(opts)
  require("miniobsidian.note").search(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  desc  = "全文搜索 vault（ripgrep）",
})

--- :ObsidianTemplate
-- 弹出模板选择器，将所选模板内容（变量替换后）插入到光标当前行之后。
-- 无参数。
vim.api.nvim_create_user_command("ObsidianTemplate", function()
  require("miniobsidian.template").insert()
end, {
  desc = "插入模板",
})

--- :ObsidianNewTemplate [name]
-- 快速创建新模板文件并打开编辑。name 可选：
--   • 提供 name：直接在 templates_folder 创建 {name}.md 并跳转。
--   • 不提供：弹出 vim.ui.input 让用户输入模板名称。
vim.api.nvim_create_user_command("ObsidianNewTemplate", function(opts)
  require("miniobsidian.template").new_template(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  desc  = "新建模板文件",
})

--- :ObsidianPasteImg [name]
-- 将 macOS 剪贴板中的图片保存到附件目录并插入 Markdown 图片链接。
-- 自动检测图片格式（PNG / JPEG / GIF），按原始格式保存，无需安装额外工具。
-- name 可选（不含扩展名）：
--   • 提供 name：直接保存为 {name}.{ext}。
--   • 不提供：弹出 vim.ui.input 让用户命名（留空则使用时间戳）。
-- 前置条件：仅 macOS 支持；非 macOS 系统调用会发出友好提示，不报错。
vim.api.nvim_create_user_command("ObsidianPasteImg", function(opts)
  require("miniobsidian.image").paste_img(opts.args ~= "" and opts.args or nil)
end, {
  nargs = "?",
  desc  = "粘贴剪贴板图片（macOS）",
})

--- :ObsidianToday
-- 打开（或创建）今日每日笔记。
--   • 文件路径：vault_path/dailies_folder/{daily_date_format}.md
--   • 文件不存在时自动写入带 frontmatter 的初始内容，并使补全 cache 失效。
--   • 无参数。
vim.api.nvim_create_user_command("ObsidianToday", function()
  require("miniobsidian.daily").open_today()
end, { desc = "打开今日每日笔记" })

--- :ObsidianSetup
-- 使用默认配置初始化插件（等价于 require("miniobsidian").setup()）。
-- 通常不需要直接调用此命令，在 lazy.nvim 的 config 回调中调用 setup() 即可。
-- 提供此命令主要用于测试或不使用插件管理器的场景。
vim.api.nvim_create_user_command("ObsidianSetup", function()
  require("miniobsidian").setup()
end, { desc = "初始化 miniobsidian（使用默认配置）" })

-- ── setup 完成后的延迟初始化 ───────────────────────────────────
-- 监听 miniobsidian.init.setup() 触发的自定义事件 "MiniObsidianSetup"，
-- 在事件回调中注册需要 config 已就绪的 autocmd（此时 vault_path 已被展开）。
-- 使用事件驱动而非直接调用的原因：
--   plugin/ 目录下的文件比 lua/miniobsidian/init.lua 更早被 Neovim 加载，
--   若在此处直接调用 setup()，config 尚未被用户覆盖，BufWritePost 会基于默认配置注册。
--   等待 "MiniObsidianSetup" 事件确保用户的 setup(opts) 已经执行完毕。
vim.api.nvim_create_autocmd("User", {
  pattern  = "MiniObsidianSetup",
  -- once = true 已移除：augroup clear = true 已保证幂等性，
  -- 移除后多次调用 setup() 时 autocmd 能正确重新注册，反映新配置。
  callback = function()
    local core = require("miniobsidian")

    -- 创建独立 augroup，clear = true 确保不重复注册（若 once = true 失效时的兜底）
    local augroup = vim.api.nvim_create_augroup("miniobsidian_buffers", { clear = true })

    -- 主动触发补全：只在「进入」[[ 或 - [ 上下文的瞬间调用 blink.show()。
    -- 关键优化：不对上下文内的每个字符都调用 blink.show()。
    --   每次 blink.show() 会创建新 context，使 blink.cmp 内部缓存失效，
    --   导致 get_completions 被反复调用。
    --   只在进入时触发一次，后续字符由 blink.cmp 客户端过滤（is_incomplete_forward=false），
    --   get_completions 不会再被调用。

    vim.api.nvim_create_autocmd("TextChangedI", {
      group   = augroup,
      pattern = "*.md",
      callback = function(ev)
        if not core.in_vault(vim.api.nvim_buf_get_name(ev.buf)) then return end

        local cursor = vim.api.nvim_win_get_cursor(0)
        local line   = vim.api.nvim_get_current_line()
        local before = line:sub(1, cursor[2])
        local after  = line:sub(cursor[2] + 1)

        -- [[ 进入点：before 以 "[[" 结尾，且 after 为空或仅为 "]]"
        local just_entered_wikilink = before:match("%[%[$") ~= nil
                                   and (after == "" or after == "]]")

        -- - [ 进入点：before 匹配 checkbox 触发，且 after 为空或仅为 "]"
        local just_entered_checkbox = (before:match("^%s*[-*+]%s+%[$") ~= nil
                                    or before:match("^%s*[-*+]%[$")    ~= nil)
                                   and (after == "" or after == "]")

        if just_entered_wikilink then
          local ok, blink = pcall(require, "blink.cmp")
          -- 限定 miniobsidian + buffer：笔记链接上下文里 buffer 词语有参考价值，
          -- 排除 copilot / LSP / snippets 避免无关候选干扰
          if ok and blink.show then blink.show({ providers = { "miniobsidian", "buffer" } }) end
        elseif just_entered_checkbox then
          local ok, blink = pcall(require, "blink.cmp")
          -- 限定仅 miniobsidian provider：
          --   checkbox 上下文语义极窄（用户仅需选择 [ ] [x] [/] 等状态字符），
          --   copilot / LSP / buffer 在此处不会提供有意义的候选，混入反而干扰体验。
          --   not is_menu_visible() 守卫防止菜单已开时重复触发 show()
          if ok and blink.show and not blink.is_menu_visible() then
            blink.show({ providers = { "miniobsidian" } })
          end
        end
      end,
    })

    -- 监听 vault 内 Markdown 文件的写入事件，自动刷新笔记路径缓存。
    -- 这确保新建/删除/重命名笔记后，补全候选列表能在 CACHE_TTL(5秒) 内更新。
    -- 使用 BufWritePost（写入完成后）而非 BufWritePre，确保文件已落盘后再刷新。
    vim.api.nvim_create_autocmd("BufWritePost", {
      group   = augroup,
      pattern = "*.md",  -- 仅监听 Markdown 文件（通配符，不限于 vault 内）
      callback = function(ev)
        -- 进一步过滤：只对 vault 内的文件刷新缓存（vault 外的 md 文件不影响补全列表）
        if core.in_vault(vim.api.nvim_buf_get_name(ev.buf)) then
          core.invalidate_cache()
        end
      end,
    })
  end,
})
