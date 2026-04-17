-- ============================================================
-- 文件名：vault.lua
-- 模块职责：vault 的扫描发现、运行时切换以及选择 UI。
--           通过检测子目录内是否含有 .obsidian/ 来识别有效的 Obsidian vault。
-- 依赖关系：miniobsidian（config、invalidate_cache）、snacks.nvim（可选，回退 vim.ui.select）
-- 对外 API：M.list_vaults(parent)、M.refresh_vaults()、M.do_switch(entry)、M.pick_and_switch()
-- ============================================================
local M = {}

-- vault 列表缓存：首次扫描后存储，避免每次打开切换器都重复读磁盘。
-- 调用 M.refresh_vaults() 或 setup() 可主动清除缓存。
local _vaults_cache = nil

--- 清除 vault 列表缓存，下次调用 list_vaults 时重新扫描磁盘。
-- 在 vaults_parent 可能发生变化（如用户修改配置后重新 setup）时自动调用。
function M.refresh_vaults()
  _vaults_cache = nil
end

--- 扫描指定父目录，返回所有含 .obsidian/ 子目录的有效 vault 列表。
-- 识别规则：子目录存在 AND 子目录内含 .obsidian/ → 视为 Obsidian vault。
-- 结果按目录名字母序排列，保证多次调用顺序稳定。
-- 扫描结果带模块级缓存，session 内首次调用后即时响应；
-- 调用 refresh_vaults() 或 setup() 可清除缓存重新扫描。
---@param parent string vault 父目录的绝对路径（已展开 ~）
---@return {name: string, path: string}[] 有效 vault 列表（可能为空）
function M.list_vaults(parent)
  if _vaults_cache then return _vaults_cache end   -- 命中缓存，直接返回

  if vim.fn.isdirectory(parent) == 0 then
    vim.notify("[miniobsidian] vaults_parent 目录不存在: " .. parent, vim.log.levels.ERROR)
    return {}
  end

  local vaults = {}

  for _, name in ipairs(vim.fn.readdir(parent)) do
    -- 跳过隐藏目录（如 .DS_Store 生成的 ._ 前缀条目）
    if not name:match("^%.") then
      local vault_path = parent .. "/" .. name
      if vim.fn.isdirectory(vault_path) == 1
        and vim.fn.isdirectory(vault_path .. "/.obsidian") == 1
      then
        table.insert(vaults, { name = name, path = vault_path })
      end
    end
  end

  table.sort(vaults, function(a, b) return a.name < b.name end)
  _vaults_cache = vaults   -- 存入缓存
  return vaults
end

--- 切换当前活跃 vault，更新运行时状态并使笔记缓存失效。
-- 调用后，所有子模块（note/template/completion 等）将自动使用新 vault 路径，
-- 因为它们均通过 require("miniobsidian").config.vault_path 读取路径。
-- 同时将 Neovim 的工作目录切换到新 vault，触发 User MiniObsidianVaultSwitch 事件
-- 供外部工具（如项目根目录缓存）响应。
---@param entry {name: string, path: string} 目标 vault 条目
function M.do_switch(entry)
  local core = require("miniobsidian")
  core.config.vault_path = entry.path
  core.active_vault_name = entry.name
  core.invalidate_cache()

  -- 同步 Neovim 全局工作目录，确保 snacks.picker / neo-tree / root 缓存等
  -- 依赖 cwd 的工具能感知到 vault 已切换。
  local ok, err = pcall(vim.api.nvim_set_current_dir, entry.path)
  if not ok then
    vim.notify("[miniobsidian] 切换工作目录失败: " .. tostring(err), vim.log.levels.WARN)
  end

  -- 触发自定义 User 事件，外部插件可通过监听此事件做额外刷新（如 root 缓存失效）。
  -- 事件 data 携带新 vault 的 name 与 path，供回调使用。
  vim.api.nvim_exec_autocmds("User", {
    pattern = "MiniObsidianVaultSwitch",
    data    = { name = entry.name, path = entry.path },
  })

  vim.notify("[miniobsidian] 已切换到 vault：" .. entry.name, vim.log.levels.INFO)
end

--- 弹出选择 UI，让用户选择并切换到目标 vault。
-- 优先使用 Snacks.picker.select（支持模糊搜索），不可用时回退到 vim.ui.select。
-- 当前活跃 vault 以 ● 标记，其余以 ○ 标记，方便视觉区分。
function M.pick_and_switch()
  local core   = require("miniobsidian")
  local vaults = M.list_vaults(core.config.vaults_parent)

  if #vaults == 0 then
    vim.notify(
      "[miniobsidian] 未找到可用的 vault（vaults_parent 下无含 .obsidian/ 的子目录）",
      vim.log.levels.WARN
    )
    return
  end

  -- 构造显示标签，并建立标签→条目的反向索引（供回调查找原始条目）
  local labels        = {}
  local label_to_entry = {}

  for _, v in ipairs(vaults) do
    local label = (v.path == core.config.vault_path and "● " or "○ ") .. v.name
    table.insert(labels, label)
    label_to_entry[label] = v
  end

  -- 选择 UI：优先 Snacks.picker.select，回退 vim.ui.select
  local ok_snacks, snacks = pcall(require, "snacks")
  local select_fn
  if ok_snacks and snacks.picker and snacks.picker.select then
    select_fn = function(items, opts, on_choice)
      snacks.picker.select(items, opts, on_choice)
    end
  else
    select_fn = vim.ui.select
  end

  select_fn(labels, { prompt = "切换 Vault" }, function(choice)
    if not choice then return end
    local entry = label_to_entry[choice]
    if not entry then return end
    -- vim.schedule：规避 select 回调在 textlock 状态下调用 notify 等 API 的问题
    vim.schedule(function()
      M.do_switch(entry)
    end)
  end)
end

return M
