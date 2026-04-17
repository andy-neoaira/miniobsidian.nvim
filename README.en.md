# miniobsidian.nvim

<div align="center">

**A lightweight, fast Obsidian workflow plugin for Neovim**

[![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.11.2-blueviolet?logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Made%20with-Lua-blue?logo=lua)](https://lua.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

English · [中文](README.md)

</div>

---

## What is this?

`miniobsidian.nvim` is a minimal, focused Neovim plugin that brings the core Obsidian workflow into your terminal editor — without the bloat. It integrates tightly with the modern Neovim ecosystem ([blink.cmp](https://github.com/Saghen/blink.cmp), [snacks.nvim](https://github.com/folke/snacks.nvim)) to give you a fast, keyboard-driven note-taking experience.

**Design philosophy:** Provide only what you actually use every day — note creation, quick navigation, full-text search, wiki link jumping, checkbox management, image pasting, a template system, and daily notes. No Telescope dependency, no predefined keymaps (you're in full control), lazy-load friendly with near-zero startup cost.

> **Inspired by** [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) — a full-featured Obsidian client for Neovim. `miniobsidian.nvim` takes a lighter approach: no Telescope dependency, no heavy event system, just the features you actually use every day. If you need a more complete, battle-tested solution, use that instead.

---

## Features

### Core features

| Feature | Description |
|---------|-------------|
| 🗂️ **Multi-Vault Support** | Auto-discovers vaults under `vaults_parent` by detecting `.obsidian/` subdirectories; one-keystroke switching updates Neovim's cwd, compatible with neo-tree / snacks.nvim and other cwd-aware tools |
| 📝 **Quick Note Creation** | Auto-generates YAML frontmatter (`title`, `date`, `tags`); supports a custom filename generator; built-in slug logic handles CJK (Chinese/Japanese/Korean) characters; cursor lands at the first body line |
| 📁 **Context-aware Creation** | When focused in a file explorer (snacks explorer / neo-tree / nvim-tree / oil.nvim / netrw), creates the note in the directory under the cursor; if the cursor is on a file, creates it in that file's parent directory; target must be inside the current vault |
| 🔀 **Quick Switch** | Fuzzy-find and jump between Markdown notes in `notes_subdir` via a `snacks.nvim` picker; hidden directories (`.obsidian/`, `.git/`) are automatically excluded |
| 🔍 **Full-text Search** | Ripgrep-powered note search with a live preview pane; scoped to `notes_subdir` only for accurate, fast results |
| 🔗 **Wiki Link Navigation** | `<CR>` follows `[[links]]`; supports `[[note]]`, `[[note\|alias]]`, `[[note#heading]]`, and `[[folder/note]]` formats; three-tier lookup (exact → case-insensitive → path-prefix strip); prompts to create if not found |
| ✅ **Multi-state Checkbox** | Cycle through `[ ]` → `[/]` → `[x]` → `[-]` (fully configurable); plain list items auto-upgrade to checkboxes; `clear()` strips the checkbox back to a plain list item in one shot |
| 🔗 **Wiki Link Autocomplete** | Type `[[` to fuzzy-complete any note name in the vault; duplicate-named notes shown as `parent/name` to disambiguate; **hovering an item shows a preview of the note's first 10 lines** |
| ✅ **Checkbox Autocomplete** | Type `- [`, `* [`, or `+ [` to get all states from your `checkbox_states` config as candidates |
| 🖼️ **Image Paste** | Paste clipboard images directly into notes (macOS only, built-in JXA script, no extra tools needed); handles both screenshots and files copied from Finder; auto-detects format (PNG / JPG / GIF / WEBP / HEIC / HEIF / TIFF / BMP / SVG); input prompt pre-fills a timestamp filename; inserts a **relative path** link that stays valid even when the vault is moved |
| 📄 **Template System** | Pick from `Templates/` (subdirectory organization supported) and insert with variable substitution; 8 built-in variables (see table below); `new_template()` creates a new template pre-filled with a skeleton |
| 📅 **Daily Note** | One keystroke opens or creates today's note; filename and frontmatter both use `daily_date_format`; auto-writes frontmatter with a `[daily]` tag |

---

### Checkbox state reference

The following states have built-in descriptions shown in autocomplete candidates. Mix and match any subset in `checkbox_states`:

| State char | Meaning | Markdown example |
|-----------|---------|-----------------|
| ` ` (space) | Todo | `- [ ] pending task` |
| `/` | In progress | `- [/] in progress` |
| `x` | Done | `- [x] completed` |
| `-` | Cancelled | `- [-] cancelled` |
| `>` | Forwarded | `- [>] forwarded` |
| `!` | Important | `- [!] critical` |
| `?` | Question | `- [?] to confirm` |

---

### Template variable reference

| Variable | Description | Example output |
|----------|-------------|----------------|
| `{{date}}` | Current date (format from `daily_date_format`) | `2024-01-15` |
| `{{time}}` | Current time (HH:MM) | `14:30` |
| `{{title}}` | Current filename without extension | `my-note` |
| `{{filename}}` | Same as `{{title}}` | `my-note` |
| `{{yesterday}}` | Yesterday's date | `2024-01-14` |
| `{{tomorrow}}` | Tomorrow's date | `2024-01-16` |
| `{{date:FORMAT}}` | Custom-formatted date | `{{date:YYYY/MM/DD}}` → `2024/01/15` |

> All variables are **case-insensitive** — `{{Date}}`, `{{DATE}}`, and `{{date}}` all work.

`{{date:FORMAT}}` supports these tokens (Obsidian-compatible):

| Token | Meaning | Token | Meaning |
|-------|---------|-------|---------|
| `YYYY` | 4-digit year | `HH` | Hour (00–23) |
| `MM` | Month (01–12) | `mm` | Minute (00–59) |
| `DD` | Day (01–31) | `ss` | Second (00–59) |

---

## Requirements

| Dependency | Purpose | Install |
|-----------|---------|---------|
| **Neovim ≥ 0.11.2** | Required (uses `vim.system`, `vim.uv`, and other modern APIs) | — |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Picker UI (quick switch, full-text search, template/vault selection) | lazy.nvim |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | Autocomplete (wiki links + checkboxes, **optional**) | lazy.nvim |
| `ripgrep` | Full-text search backend | `brew install ripgrep` |
| `osascript` | Image paste (macOS system built-in, macOS only) | — |

---

## Installation

### lazy.nvim (minimal)

```lua
{
  "andy-neoaira/miniobsidian.nvim",
  lazy = true,
  ft = "markdown",
  config = function()
    require("miniobsidian").setup({
      vaults_parent = "~/Documents/Obsidian",  -- parent directory of your vaults (required)
      default_vault = "MyVault",               -- default vault name (optional)
    })
  end,
}
```

### lazy.nvim (full setup with blink.cmp autocomplete)

```lua
-- miniobsidian main plugin
{
  "andy-neoaira/miniobsidian.nvim",
  lazy = true,
  ft = "markdown",
  keys = {
    -- Global keymaps (work from any filetype; lazy loading still triggers)
    { "<leader>nn", function() require("miniobsidian.note").new_note() end,         desc = "Obsidian: New note" },
    { "<leader>na", function() require("miniobsidian.note").new_note_here() end,   desc = "Obsidian: New note in file tree dir" },
    { "<leader>no", function() require("miniobsidian.note").quick_switch() end,     desc = "Obsidian: Quick switch" },
    { "<leader>ns", function() require("miniobsidian.note").search() end,           desc = "Obsidian: Search notes" },
    { "<leader>nS", function() require("miniobsidian.note").search(vim.fn.expand("<cword>")) end,
                                                                                    desc = "Obsidian: Search word under cursor" },
    { "<leader>nv", function() require("miniobsidian.vault").pick_and_switch() end, desc = "Obsidian: Switch vault" },
    { "<leader>nd", function() require("miniobsidian.daily").open_today() end,      desc = "Obsidian: Daily note" },
    { "<leader>nT", function() require("miniobsidian.template").new_template() end, desc = "Obsidian: New template" },
    -- Markdown-only keymaps (active only in .md files)
    { "<leader>nt", function() require("miniobsidian.template").insert() end,            ft = "markdown", desc = "Obsidian: Insert template" },
    { "<leader>np", function() require("miniobsidian.image").paste_img() end,            ft = "markdown", desc = "Obsidian: Paste image" },
    { "<leader>nl", function() require("miniobsidian.checkbox").clear() end,             ft = "markdown", desc = "Obsidian: Clear checkbox" },
    { "<CR>",       function() require("miniobsidian.link").follow_link_or_toggle() end, ft = "markdown", desc = "Obsidian: Follow link / toggle checkbox" },
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

-- Register miniobsidian as a blink.cmp source
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
        score_offset = 50,  -- rank above buffer/snippets so [[note]] candidates appear first
        -- trigger characters are declared by get_trigger_characters() inside the source;
        -- do not add trigger_characters here (blink.cmp will warn)
      },
    })
    return opts
  end,
},
```

---

## Configuration

All options with their defaults:

```lua
require("miniobsidian").setup({
  -- ── Required ──────────────────────────────────────────────────────────
  -- Parent directory containing your Obsidian vaults.
  -- The plugin scans for subdirectories that contain a .obsidian/ folder.
  -- Supports ~ expansion and iCloud Drive paths.
  vaults_parent = "~/Documents/Obsidian",

  -- ── Optional ──────────────────────────────────────────────────────────
  -- Name of the vault to activate on startup (first vault found if omitted, sorted alphabetically)
  default_vault = "MyVault",

  -- Subdirectory for new notes, relative to the active vault root.
  -- Set to "" to store notes directly in the vault root.
  notes_subdir = "Notes",

  -- Subdirectory for daily notes
  dailies_folder = "Dailies",

  -- Subdirectory for templates (:ObsidianTemplate reads .md files here; subdirectories supported)
  templates_folder = "Templates",

  -- Subdirectory for pasted images and other attachments
  attachments_folder = "Assets",

  -- Date format used in daily note filenames and frontmatter `date:` fields.
  -- Uses Lua's os.date format string.
  daily_date_format = "%Y-%m-%d",

  -- Checkbox cycle states (toggle cycles through these in order).
  -- Minimal two-state: { " ", "x" }
  -- Extended:          { " ", "/", "x", "-", ">", "!", "?" }
  checkbox_states = { " ", "x" },

  -- Custom note ID / filename generator.
  -- Default: keeps CJK characters, ASCII alphanumerics; converts spaces to hyphens; lowercases.
  -- Example: "Hello World"   → "hello-world"
  --          "我的笔记 2024"  → "我的笔记-2024"
  note_id_func = function(title)
    local id = title:gsub("[^%w%s\u{2E80}-\u{9FFF}\u{AC00}-\u{D7AF}\u{F900}-\u{FAFF}]", "")
    id = id:gsub("%s+", "-")
    return id:lower()
  end,
})
```

---

## Commands

| Command | Args | Description |
|---------|------|-------------|
| `:ObsidianNew [title]` | optional | Quick-create a note to the default `notes_subdir`; prompts for title if omitted |
| `:ObsidianNewHere` | none | Create a note in the current file explorer's focused directory (snacks explorer / neo-tree / nvim-tree / oil.nvim / netrw) |
| `:ObsidianSwitch` | none | Open quick-switch picker |
| `:ObsidianSearch [query]` | optional | Full-text search; prompts if omitted |
| `:ObsidianSwitchVault` | none | Open vault selector and switch |
| `:ObsidianTemplate` | none | Pick and insert a template |
| `:ObsidianNewTemplate [name]` | optional | Create a new template file; prompts if omitted |
| `:ObsidianPasteImg [name]` | optional | Paste clipboard image (macOS); prompts if omitted |
| `:ObsidianToday` | none | Open or create today's daily note (`vault/dailies_folder/date.md`) |
| `:ObsidianSetup` | none | Initialize plugin with default config (rarely needed manually) |

---

## Lua API

```lua
-- Note management
require("miniobsidian.note").new_note(title?)         -- Quick-create a note (always to notes_subdir)
require("miniobsidian.note").new_note_here()           -- Create a note in the current file explorer dir (snacks/neo-tree/nvim-tree/oil/netrw)
require("miniobsidian.note").new_note_in_dir(dir)      -- Create a note in the given absolute path (must be inside vault)
require("miniobsidian.note").quick_switch()            -- Open note picker
require("miniobsidian.note").search(query?)            -- Full-text search (optional initial query)
require("miniobsidian.note").follow_or_create(stem)    -- Jump to note by stem; prompt to create if not found

-- Daily note
require("miniobsidian.daily").open_today()             -- Open or create today's daily note

-- Wiki links
require("miniobsidian.link").follow_link_or_toggle()   -- Follow [[link]] or toggle checkbox
require("miniobsidian.link").link_at_cursor()          -- Returns note name at cursor [[link]], or nil

-- Checkbox
require("miniobsidian.checkbox").toggle()              -- Cycle checkbox state
require("miniobsidian.checkbox").clear()               -- Strip checkbox marker, restore to plain list item

-- Templates
require("miniobsidian.template").new_template(name?)   -- Create a new template file (prompts if no name)
require("miniobsidian.template").insert()              -- Pick and insert a template

-- Images
require("miniobsidian.image").paste_img(name?)         -- Paste clipboard image (macOS)

-- Vault management
require("miniobsidian.vault").pick_and_switch()        -- Open vault picker
require("miniobsidian.vault").do_switch(entry)         -- Switch to a vault directly (entry = {name, path})
require("miniobsidian.vault").list_vaults(parent)      -- List all valid vaults under a parent directory

-- Core module
require("miniobsidian").config                         -- Current config (includes runtime vault_path)
require("miniobsidian").active_vault_name              -- Name of the active vault (use in statusline)
require("miniobsidian").get_all_notes(force?)          -- All .md paths in the vault (5s cached)
require("miniobsidian").in_vault(path)                 -- Returns true if path is inside the active vault
require("miniobsidian").invalidate_cache()             -- Force-clear the note path cache
```

---

## Wiki link formats

`<CR>` (`follow_link_or_toggle()`) handles all standard Obsidian wiki link formats:

| Format | Example | Notes |
|--------|---------|-------|
| Simple | `[[my-note]]` | Jumps to the matching note |
| With alias | `[[my-note\|Display text]]` | Alias is for rendering only; jump target is `my-note` |
| With heading | `[[my-note#Section]]` | Jumps to `my-note` (heading anchor handled by Markdown renderer) |
| With path | `[[folder/my-note]]` | Extracts the last segment `my-note` for lookup |

**Three-tier lookup strategy (tried in order):**

1. **Exact match** — stem is identical (`my-note` → `my-note.md`)
2. **Case-insensitive match** — `[[My Note]]` finds `my-note.md`
3. **Path-prefix strip** — `[[folder/note]]` is searched as `note`

The first tier that finds a match jumps immediately. If all three fail, a prompt offers to create the note.

---

## How autocomplete works

Only activates in Markdown files **inside your active vault** — no interference with other Markdown files.

| Input | Effect |
|-------|--------|
| `[[` | Shows all note names in the vault for fuzzy selection; **hovering an item previews the note's first 10 lines** |
| `- [`, `* [`, `+ [` | Shows all states from your `checkbox_states` config as candidates |

**Caching & performance:** A full vault scan runs on first completion and is stored in memory. The cache is invalidated automatically on `BufWritePost` for vault Markdown files, and also expires after 5 seconds as a safety net — so new and deleted notes stay up to date without noticeable I/O overhead.

---

## Statusline integration

`require("miniobsidian").active_vault_name` is updated whenever the vault changes and can be used directly in lualine or any other statusline plugin:

```lua
-- lualine example
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

## Custom events

The plugin fires Neovim `User` events so that other plugins or your config can react:

| Event | Fired when | Data |
|-------|-----------|------|
| `User MiniObsidianSetup` | `setup()` completes | none |
| `User MiniObsidianVaultSwitch` | Vault is switched (cwd already updated) | `{ name: string, path: string }` |

```lua
-- Example: refresh neo-tree root after switching vaults
vim.api.nvim_create_autocmd("User", {
  pattern = "MiniObsidianVaultSwitch",
  callback = function(ev)
    local name = ev.data.name
    local path = ev.data.path
    -- e.g. update lualine, refresh neo-tree root, etc.
    vim.notify("Switched to vault: " .. name .. "\n" .. path)
  end,
})
```

---

## File structure

```
lua/miniobsidian/
├── init.lua          Core: setup(), vault detection, note path cache, in_vault()
├── vault.lua         Multi-vault discovery, switching (updates cwd), picker UI
├── note.lua          Note creation, quick switch, full-text search, follow_or_create
├── daily.lua         Daily note (:ObsidianToday)
├── link.lua          Wiki link parsing and navigation (link_at_cursor, follow_link_or_toggle)
├── checkbox.lua      Multi-state checkbox cycle and clear
├── completion.lua    blink.cmp source (wiki links + checkboxes + hover preview)
├── template.lua      Template selection, variable substitution, insertion (subdirs supported)
├── image.lua         Clipboard image paste (macOS)
└── scripts/
    └── paste_image.js  macOS JXA script (image saving, format auto-detection)
plugin/
└── miniobsidian.lua  User command registration + autocmds (BufWritePost cache refresh, TextChangedI completion trigger)
```

---

## Acknowledgements

- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim) by [@epwalsh](https://github.com/epwalsh) — the original inspiration for this plugin. If you need a full-featured, battle-tested Obsidian client for Neovim, use that instead.
- [snacks.nvim](https://github.com/folke/snacks.nvim) by [@folke](https://github.com/folke) — powers the picker UI.
- [blink.cmp](https://github.com/Saghen/blink.cmp) by [@Saghen](https://github.com/Saghen) — powers the autocomplete integration.

## License

MIT © [andy-neoaira](https://github.com/andy-neoaira)
