local M = {}

local function get_health()
  if vim.health then return vim.health end
  local ok, h = pcall(require, "health")
  if ok then return h end
  return nil
end

local function ver_ge(a, b)
  if a.major ~= b.major then return a.major > b.major end
  if a.minor ~= b.minor then return a.minor > b.minor end
  return a.patch >= b.patch
end

local function uname()
  local uv = vim.uv or vim.loop
  if not uv or not uv.os_uname then return nil end
  return uv.os_uname()
end

function M.check()
  local h = get_health()
  if not h then return end

  h.start("miniobsidian.nvim")

  local required = { major = 0, minor = 11, patch = 2 }
  local current = vim.version()
  if ver_ge(current, required) then
    h.ok(("Neovim %d.%d.%d"):format(current.major, current.minor, current.patch))
  else
    h.error(
      ("Neovim %d.%d.%d (required >= %d.%d.%d)"):format(
        current.major,
        current.minor,
        current.patch,
        required.major,
        required.minor,
        required.patch
      )
    )
  end

  local ok_snacks, snacks = pcall(require, "snacks")
  if ok_snacks and snacks and snacks.picker then
    h.ok("snacks.nvim found")
  else
    h.error("snacks.nvim not found (required)")
  end

  if vim.fn.executable("rg") == 1 then
    h.ok("ripgrep (rg) found")
  else
    h.error("ripgrep (rg) not found")
  end

  local sys = uname()
  local is_macos = sys and sys.sysname == "Darwin"
  if is_macos then
    if vim.fn.executable("osascript") == 1 then
      h.ok("osascript found (image paste enabled)")
    else
      h.warn("osascript not found (image paste may not work)")
    end
  else
    h.info("non-macOS: image paste is disabled")
  end

  local ok_blink = pcall(require, "blink.cmp")
  if ok_blink then
    h.ok("blink.cmp found (completion enabled)")
  else
    h.info("blink.cmp not found (completion disabled)")
  end

  local core_ok, core = pcall(require, "miniobsidian")
  if not core_ok or not core or not core.config then
    h.warn("miniobsidian core not loaded")
    return
  end

  local parent = core.config.vaults_parent
  if not parent or parent == "" then
    h.error("config.vaults_parent is empty (call setup({ vaults_parent = ... }))")
    return
  end

  parent = vim.fn.expand(parent)
  if vim.fn.isdirectory(parent) == 1 then
    h.ok(("vaults_parent: %s"):format(parent))
  else
    h.error(("vaults_parent directory does not exist: %s"):format(parent))
    return
  end

  local vault = require("miniobsidian.vault")
  vault.refresh_vaults()
  local vaults = vault.list_vaults(parent)
  if #vaults == 0 then
    h.error("no valid vault found (a vault must contain .obsidian/)")
    return
  end

  h.ok(("vaults found: %d"):format(#vaults))

  if core.config.vault_path and core.config.vault_path ~= "" then
    if vim.fn.isdirectory(core.config.vault_path) == 1 then
      h.ok(("active vault_path: %s"):format(core.config.vault_path))
    else
      h.warn(("active vault_path does not exist: %s"):format(core.config.vault_path))
    end
  else
    h.warn("active vault_path is empty (did setup() run successfully?)")
  end
end

return M
