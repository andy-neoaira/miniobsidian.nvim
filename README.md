# miniobsidian.nvim

<div align="center">

**轻量、快速的 Obsidian 工作流 Neovim 插件**

[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.11.2-blueviolet?logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Made%20with-Lua-blue?logo=lua)](https://lua.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.en.md) · 中文

</div>

---

## 这是什么？

`miniobsidian.nvim` 是一个轻量、专注的 Neovim 插件，将 Obsidian 的核心工作流带入终端编辑器——没有多余的依赖，没有复杂的配置。它深度整合现代 Neovim 生态（[blink.cmp](https://github.com/Saghen/blink.cmp)、[snacks.nvim](https://github.com/folke/snacks.nvim)），提供流畅、键盘驱动的笔记体验。

**设计哲学：** 只提供每天真正用得到的功能——笔记创建、快速跳转、全文搜索、Wiki 链接导航、Checkbox 管理、图片粘贴、模板系统、每日笔记。不内置 Telescope 依赖，不预设任何快捷键（完全由用户掌控），懒加载友好，对启动性能几乎没有影响。

> **灵感来源：** [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) —— 一个功能完整的 Obsidian Neovim 客户端。`miniobsidian.nvim` 采用更轻量的设计哲学：无 Telescope 依赖、无复杂事件系统，只保留每天真正用到的功能。如需功能更全面、久经考验的方案，推荐使用该插件。

---

## 功能一览

### 核心功能

| 功能 | 详细说明 |
|------|---------|
| 🗂️ **多 Vault 支持** | 自动扫描 `vaults_parent` 下含 `.obsidian/` 子目录的文件夹作为有效 vault；一键切换，同步更新 Neovim 工作目录，兼容 neo-tree / snacks.nvim 等依赖 cwd 的工具 |
| 📝 **快速创建笔记** | 自动生成 YAML frontmatter（`title`、`date`、`tags`）；支持自定义文件名生成函数；内置 slug 规则兼容中文（CJK）字符；新建时光标自动定位到正文起始行 |
| 📁 **目录感知创建** | 焦点在文件浏览器时（snacks explorer / neo-tree / nvim-tree / oil.nvim / netrw），在光标所在目录下新建笔记；光标在文件上则在同级目录创建；目标必须在当前 vault 内 |
| 🔀 **快速切换笔记** | 通过 `snacks.nvim` picker 在 `notes_subdir` 中模糊搜索并跳转 Markdown 笔记；自动过滤 `.obsidian/`、`.git/` 等隐藏目录 |
| 🔍 **全文搜索** | 基于 ripgrep 的笔记全文搜索，附带实时预览；仅在 `notes_subdir` 范围内搜索，精准且快速 |
| 🔗 **Wiki 链接跳转** | `<CR>` 跳转 `[[链接]]`，支持 `[[note]]`、`[[note\|别名]]`、`[[note#章节]]`、`[[folder/note]]` 四种格式；三级查找（精确 → 忽略大小写 → 剥离路径前缀）；找不到时提示创建 |
| ✅ **Checkbox 多状态循环** | 循环切换 `[ ]` → `[/]` → `[x]` → `[-]`（完全可自定义）；普通列表项自动升级为 checkbox；`clear()` 一键还原为普通列表项 |
| 🔗 **Wiki 链接自动补全** | 输入 `[[` 时，blink.cmp 列出 vault 内所有笔记供模糊选择；同名笔记以 `父目录/名称` 区分；**悬停候选时显示笔记前 10 行预览** |
| ✅ **Checkbox 自动补全** | 输入 `- [`、`* [`、`+ [` 时，blink.cmp 弹出当前 `checkbox_states` 中配置的所有状态候选 |
| 🖼️ **图片粘贴** | 粘贴剪贴板图片到笔记（macOS 专用，内置 JXA 脚本，无需额外工具）；支持截图及 Finder 复制的文件；自动识别格式（PNG / JPG / GIF / WEBP / HEIC / HEIF / TIFF / BMP / SVG）；输入框预填时间戳默认文件名；插入**相对路径**图片链接，vault 迁移后依然有效 |
| 📄 **模板系统** | 从 `Templates/` 目录（支持子目录层级）选择并插入模板；支持 8 种内置变量（见下表）；`new_template()` 快速创建新模板（自动写入含变量示例的骨架） |
| 📅 **每日笔记** | 一键打开/创建今日笔记；文件名和 frontmatter 均使用 `daily_date_format`；自动写入带 `[daily]` 标签的 frontmatter |

---

### Checkbox 状态参考

以下是插件内置描述的 checkbox 状态（在自动补全候选中显示）。你可以在 `checkbox_states` 中自由组合任意子集：

| 状态字符 | 含义 | Markdown 示例 |
|---------|------|--------------|
| ` `（空格） | 待办 | `- [ ] 待处理事项` |
| `/` | 进行中 | `- [/] 正在进行` |
| `x` | 已完成 | `- [x] 已完成` |
| `-` | 已取消 | `- [-] 已取消` |
| `>` | 已转移 | `- [>] 已转移` |
| `!` | 重要 | `- [!] 重要任务` |
| `?` | 疑问 | `- [?] 待确认` |

---

### 模板变量参考

| 变量 | 说明 | 示例输出 |
|------|------|---------|
| `{{date}}` | 当前日期（格式由 `daily_date_format` 决定） | `2024-01-15` |
| `{{time}}` | 当前时间（HH:MM） | `14:30` |
| `{{title}}` | 当前文件名（不含扩展名） | `my-note` |
| `{{filename}}` | 同 `{{title}}` | `my-note` |
| `{{yesterday}}` | 昨天日期 | `2024-01-14` |
| `{{tomorrow}}` | 明天日期 | `2024-01-16` |
| `{{date:FORMAT}}` | 自定义格式日期 | `{{date:YYYY/MM/DD}}` → `2024/01/15` |

> 所有变量均**大小写不敏感**（`{{Date}}`、`{{DATE}}`、`{{date}}` 均有效）。

`{{date:FORMAT}}` 支持以下格式令牌（兼容 Obsidian 风格）：

| 令牌 | 含义 | 令牌 | 含义 |
|------|------|------|------|
| `YYYY` | 四位年份 | `HH` | 小时（00–23） |
| `MM` | 月份（01–12） | `mm` | 分钟（00–59） |
| `DD` | 日期（01–31） | `ss` | 秒（00–59） |

---

## 依赖要求

| 依赖 | 用途 | 安装方式 |
|------|------|---------|
| **Neovim ≥ 0.11.2** | 必需（使用 `vim.system`、`vim.uv` 等现代 API） | — |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Picker UI（快速切换、全文搜索、模板/vault 选择） | lazy.nvim |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | 自动补全（wiki 链接 + checkbox，**可选**） | lazy.nvim |
| `ripgrep` | 全文搜索后端 | `brew install ripgrep` |
| `osascript` | 图片粘贴（macOS 系统内置，仅 macOS 有效） | — |

---

## 安装

### lazy.nvim（最简配置）

```lua
{
  "andy-neoaira/miniobsidian.nvim",
  lazy = true,
  ft = "markdown",
  config = function()
    require("miniobsidian").setup({
      vaults_parent = "~/Documents/Obsidian",  -- vault 父目录（必填）
      default_vault = "MyVault",               -- 默认激活的 vault 名（可选）
    })
  end,
}
```

### lazy.nvim（完整配置，含 blink.cmp 自动补全）

```lua
-- miniobsidian 主插件
{
  "andy-neoaira/miniobsidian.nvim",
  lazy = true,
  ft = "markdown",
  keys = {
    -- 全局快捷键（任意文件类型均可触发，lazy 加载时也会生效）
    { "<leader>nn", function() require("miniobsidian.note").new_note() end,         desc = "Obsidian: 新建笔记" },
    { "<leader>na", function() require("miniobsidian.note").new_note_here() end,   desc = "Obsidian: 在文件树目录新建笔记" },
    { "<leader>no", function() require("miniobsidian.note").quick_switch() end,     desc = "Obsidian: 快速切换" },
    { "<leader>ns", function() require("miniobsidian.note").search() end,           desc = "Obsidian: 搜索笔记" },
    { "<leader>nS", function() require("miniobsidian.note").search(vim.fn.expand("<cword>")) end,
                                                                                    desc = "Obsidian: 搜索当前词" },
    { "<leader>nv", function() require("miniobsidian.vault").pick_and_switch() end, desc = "Obsidian: 切换 Vault" },
    { "<leader>nd", function() require("miniobsidian.daily").open_today() end,      desc = "Obsidian: 每日笔记" },
    { "<leader>nT", function() require("miniobsidian.template").new_template() end, desc = "Obsidian: 新建模板" },
    -- Markdown 专用快捷键（仅在 .md 文件生效）
    { "<leader>nt", function() require("miniobsidian.template").insert() end,            ft = "markdown", desc = "Obsidian: 插入模板" },
    { "<leader>np", function() require("miniobsidian.image").paste_img() end,            ft = "markdown", desc = "Obsidian: 粘贴图片" },
    { "<leader>nl", function() require("miniobsidian.checkbox").clear() end,             ft = "markdown", desc = "Obsidian: 恢复列表项" },
    { "<CR>",       function() require("miniobsidian.link").follow_link_or_toggle() end, ft = "markdown", desc = "Obsidian: 跟随链接 / 切换 Checkbox" },
  },
  config = function()
    require("miniobsidian").setup({
      vaults_parent = "~/Library/Mobile Documents/iCloud~md~obsidian/Documents",
      default_vault = "MyVault",
      notes_subdir  = "Notes",
      checkbox_states = { " ", "/", "x", "-" },
    })
  end,
},

-- 将 miniobsidian 注册为 blink.cmp 补全源
{
  "saghen/blink.cmp",
  optional = true,
  opts = function(_, opts)
    opts.sources = opts.sources or {}
    opts.sources.default = vim.list_extend(opts.sources.default or {}, { "miniobsidian" })
    opts.sources.providers = vim.tbl_deep_extend("force", opts.sources.providers or {}, {
      miniobsidian = {
        name = "MiniObsidian",
        module = "miniobsidian.completion",
        score_offset = 50,  -- 高于 buffer/snippets，保证 [[ 时笔记候选靠前
        -- 触发字符由 source 内的 get_trigger_characters() 方法声明，
        -- 此处无需重复设置 trigger_characters 字段
      },
    })
    return opts
  end,
},
```

---

## 配置项说明

```lua
require("miniobsidian").setup({
  -- ── 必填 ──────────────────────────────────────────────────────────────
  -- vault 父目录路径
  -- 插件自动扫描其下含 .obsidian/ 子目录的文件夹作为有效 vault
  -- 支持 ~ 展开；也适用于 iCloud Drive 同步路径
  vaults_parent = "~/Documents/Obsidian",

  -- ── 可选 ──────────────────────────────────────────────────────────────
  -- 默认激活的 vault 名称（省略时取扫描到的第一个 vault，按字母序排列）
  default_vault = "MyVault",

  -- 新建笔记存放的子目录（相对于活跃 vault 根）
  -- 留空 "" 时直接存放在 vault 根目录
  notes_subdir = "Notes",

  -- 每日笔记目录
  dailies_folder = "Dailies",

  -- 模板目录（:ObsidianTemplate 从此处读取 .md 文件，支持子目录）
  templates_folder = "Templates",

  -- 图片等附件目录
  attachments_folder = "Assets",

  -- 日期格式（用于每日笔记文件名及 frontmatter `date:` 字段）
  -- 采用 Lua 的 os.date 格式字符串
  daily_date_format = "%Y-%m-%d",

  -- Checkbox 循环状态序列（按配置顺序切换，可使用上方状态参考表中的任意字符）
  -- 极简双态：{ " ", "x" }
  -- 扩展版本：{ " ", "/", "x", "-", ">", "!", "?" }
  checkbox_states = { " ", "x" },

  -- 自定义笔记 ID（文件名）生成函数
  -- 默认规则：保留中文/英日韩文字、英文字母和数字，其余符号去除，空格转连字符，转小写
  -- 示例："Hello World"  → "hello-world"
  --       "我的笔记 2024" → "我的笔记-2024"
  note_id_func = function(title)
    local id = title:gsub("[^%w%s\u{2E80}-\u{9FFF}\u{AC00}-\u{D7AF}\u{F900}-\u{FAFF}]", "")
    id = id:gsub("%s+", "-")
    return id:lower()
  end,
})
```

---

## 用户命令

| 命令 | 参数 | 说明 |
|------|------|------|
| `:ObsidianNew [标题]` | 可选 | 快捷新建笔记到默认 `notes_subdir`；省略标题则弹出输入框 |
| `:ObsidianNewHere` | 无 | 在当前文件浏览器焦点目录下新建笔记（支持 snacks explorer / neo-tree / nvim-tree / oil.nvim / netrw） |
| `:ObsidianSwitch` | 无 | 打开笔记快速切换 picker |
| `:ObsidianSearch [关键词]` | 可选 | 全文搜索；省略则弹出输入框 |
| `:ObsidianSwitchVault` | 无 | 弹出 vault 选择器并切换 |
| `:ObsidianTemplate` | 无 | 选择并插入模板 |
| `:ObsidianNewTemplate [名称]` | 可选 | 新建模板文件；省略则弹出输入框 |
| `:ObsidianPasteImg [文件名]` | 可选 | 粘贴剪贴板图片（macOS）；省略则弹出输入框 |
| `:ObsidianToday` | 无 | 打开/创建今日每日笔记（`vault/dailies_folder/日期.md`） |
| `:ObsidianSetup` | 无 | 使用默认配置初始化插件（通常不需要手动调用） |

---

## Lua API

```lua
-- 笔记管理
require("miniobsidian.note").new_note(title?)         -- 快捷新建笔记（始终到 notes_subdir）
require("miniobsidian.note").new_note_here()           -- 在当前文件树目录下新建（snacks/neo-tree/nvim-tree/oil/netrw）
require("miniobsidian.note").new_note_in_dir(dir)      -- 在指定绝对路径目录下新建（dir 须在 vault 内）
require("miniobsidian.note").quick_switch()            -- 打开笔记 picker
require("miniobsidian.note").search(query?)            -- 全文搜索（可选初始搜索词）
require("miniobsidian.note").follow_or_create(stem)    -- 查找 stem 并跳转；不存在则提示创建

-- 每日笔记
require("miniobsidian.daily").open_today()             -- 打开/创建今日笔记

-- Wiki 链接
require("miniobsidian.link").follow_link_or_toggle()   -- 跳转 [[链接]] 或切换 checkbox
require("miniobsidian.link").link_at_cursor()          -- 返回光标处 [[链接]] 的笔记名（nil 表示不在链接上）

-- Checkbox
require("miniobsidian.checkbox").toggle()              -- 循环切换 checkbox 状态
require("miniobsidian.checkbox").clear()               -- 将 checkbox 还原为普通列表项

-- 模板
require("miniobsidian.template").new_template(name?)   -- 新建模板文件（无参则弹出输入框）
require("miniobsidian.template").insert()              -- 选择并插入模板

-- 图片
require("miniobsidian.image").paste_img(name?)         -- 粘贴剪贴板图片（macOS）

-- Vault 管理
require("miniobsidian.vault").pick_and_switch()        -- 弹出 vault 选择器
require("miniobsidian.vault").do_switch(entry)         -- 直接切换到指定 vault（entry = {name, path}）
require("miniobsidian.vault").list_vaults(parent)      -- 列出指定父目录下的所有有效 vault

-- 核心模块
require("miniobsidian").config                         -- 当前完整配置（含运行时 vault_path）
require("miniobsidian").active_vault_name              -- 当前活跃 vault 名称（可用于状态栏集成）
require("miniobsidian").get_all_notes(force?)          -- 获取 vault 内所有 .md 路径（带 5s 缓存）
require("miniobsidian").in_vault(path)                 -- 判断给定路径是否在当前 vault 内
require("miniobsidian").invalidate_cache()             -- 主动清空笔记路径缓存
```

---

## Wiki 链接格式

`<CR>`（`follow_link_or_toggle()`）支持以下所有 Obsidian Wiki 链接格式：

| 格式 | 示例 | 说明 |
|------|------|------|
| 简单链接 | `[[my-note]]` | 直接跳转到同名笔记 |
| 带显示别名 | `[[my-note\|显示文字]]` | 别名仅用于渲染显示，跳转目标仍是 `my-note` |
| 带章节锚点 | `[[my-note#章节标题]]` | 跳转到 `my-note`（锚点由 Markdown 渲染器处理） |
| 路径前缀 | `[[folder/my-note]]` | 提取最后一段 `my-note` 进行文件查找 |

**三级查找策略（按优先级依次尝试）：**

1. **精确匹配**：stem 完全相等（`my-note` → `my-note.md`）
2. **忽略大小写**：`[[My Note]]` 能找到 `my-note.md`
3. **剥离路径前缀**：`[[folder/note]]` 按 `note` 查找

任意一级命中即跳转；全部未命中时弹出输入框提示创建。

---

## 自动补全工作原理

只在**当前 vault 目录内**的 Markdown 文件中触发，不影响其他 Markdown 文件。

| 输入 | 触发效果 |
|------|---------|
| `[[` | 弹出 vault 内所有笔记名，支持模糊匹配；**悬停候选时显示笔记前 10 行预览** |
| `- [`、`* [`、`+ [` | 弹出当前 `checkbox_states` 配置的所有状态候选 |

**缓存与性能：** 首次补全时扫描全量笔记并建立内存缓存；在 vault 内保存 Markdown 文件时自动刷新缓存；5 秒 TTL 保护，避免频繁磁盘 I/O。

---

## 状态栏集成

切换 vault 后，当前活跃 vault 名会更新到 `require("miniobsidian").active_vault_name`，可直接用于 lualine 或其他状态栏：

```lua
-- lualine 示例
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function()
          local ok, core = pcall(require, "miniobsidian")
          if not ok then return "" end
          local name = core.active_vault_name
          return name ~= "" and ("󰠮 " .. name) or ""
        end,
      },
    },
  },
})
```

---

## 自定义事件

插件在完成初始化或切换 vault 时会触发 Neovim `User` 事件，供外部插件或用户配置响应：

| 事件 | 触发时机 | 携带数据 |
|------|---------|---------|
| `User MiniObsidianSetup` | `setup()` 完成后 | 无 |
| `User MiniObsidianVaultSwitch` | 切换 vault 后（包括 cwd 已更新） | `{ name: string, path: string }` |

```lua
-- 示例：vault 切换后刷新 neo-tree 根目录
vim.api.nvim_create_autocmd("User", {
  pattern = "MiniObsidianVaultSwitch",
  callback = function(ev)
    local name = ev.data.name
    local path = ev.data.path
    -- 可在此处刷新 neo-tree、更新 lualine 等
    vim.notify("已切换到 vault: " .. name .. "\n路径: " .. path)
  end,
})
```

---

## 文件结构

```
lua/miniobsidian/
├── init.lua          核心：setup()、vault 检测、笔记路径缓存、in_vault()
├── vault.lua         多 vault 扫描、切换（更新 cwd）、picker UI
├── note.lua          笔记创建、快速切换、全文搜索、follow_or_create
├── daily.lua         每日笔记（:ObsidianToday）
├── link.lua          Wiki 链接解析与跳转（link_at_cursor、follow_link_or_toggle）
├── checkbox.lua      多状态 checkbox 循环切换与清除
├── completion.lua    blink.cmp 补全源（wiki 链接 + checkbox + 悬停预览）
├── template.lua      模板选择、变量替换与插入（支持子目录）
├── image.lua         剪贴板图片粘贴（macOS）
└── scripts/
    └── paste_image.js  macOS JXA 脚本（图片保存核心逻辑，自动识别格式）
plugin/
└── miniobsidian.lua  用户命令注册 + autocmd（BufWritePost 缓存刷新、TextChangedI 补全触发）
```

---

## 鸣谢

- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) by [@epwalsh](https://github.com/epwalsh) —— 本插件的灵感来源。如需功能完整、久经考验的 Obsidian Neovim 客户端，推荐使用该插件。
- [snacks.nvim](https://github.com/folke/snacks.nvim) by [@folke](https://github.com/folke) —— 提供 Picker UI 支持。
- [blink.cmp](https://github.com/Saghen/blink.cmp) by [@Saghen](https://github.com/Saghen) —— 提供自动补全集成能力。

## License

MIT © [andy-neoaira](https://github.com/andy-neoaira)
