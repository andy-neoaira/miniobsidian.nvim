-- blink.cmp 补全源：提供两类补全
--   1. [[ 后 → vault 内笔记链接（支持模糊搜索 + resolve 时显示笔记预览）
--   2. - [ 后 → checkbox 状态列表（按用户配置顺序排列）
local M = {}

-- 使用 blink 自带的 CompletionItemKind 常量，避免硬编码数字导致未来版本不兼容
local ItemKind = require("blink.cmp.types").CompletionItemKind

-- PlainText = 1，Snippet = 2；我们所有插入内容均为纯文本，显式声明避免 blink 误判
local PlainText = vim.lsp.protocol.InsertTextFormat.PlainText

-- ──────────────────────────────────────────────
-- 解析函数
-- blink ctx 已经携带了 ctx.line / ctx.cursor，直接读取，无需再调 nvim API
-- ctx.cursor[1] = 行号（1-indexed），ctx.cursor[2] = 列偏移（0-indexed 字节）
-- ──────────────────────────────────────────────

--- 检测光标是否处于 [[ wiki link 输入上下文中
---@param ctx table  blink.cmp Context 对象
---@return table|nil { query, start_byte, end_byte, row0 }
local function parse_wikilink(ctx)
	local cursor_row = ctx.cursor[1] -- 1-indexed 行号
	local cursor_col = ctx.cursor[2] -- 0-indexed 字节列偏移
	local line = ctx.line or "" -- 当前行完整文本（blink 已填充，无需再调 API）

	local before = line:sub(1, cursor_col) -- 光标前文本（1-indexed sub，cursor_col 即截止位置）

	-- 找 before 中最后一个 "[["，用循环而非贪婪匹配，保证处理嵌套 "[["
	local open_pos = nil
	local search = 1
	while true do
		local s = before:find("%[%[", search)
		if not s then
			break
		end
		open_pos = s
		search = s + 2
	end
	if not open_pos then
		return nil
	end -- 行内无 "[["，非 wikilink 上下文

	local query = before:sub(open_pos + 2) -- "[[ " 后到光标的文本，即用户已键入的查询词
	if query:find("%]%]") then
		return nil
	end -- 链接已闭合（含 ]]），不触发

	-- 若光标后紧跟 "]]"（mini.pairs 自动闭合），把替换范围延伸过去
	local after = line:sub(cursor_col + 1)
	local end_byte = cursor_col
	if after:match("^%]%]") then
		end_byte = cursor_col + 2
	end

	return {
		query = query,
		start_byte = open_pos - 1, -- 0-indexed：open_pos 是 1-indexed，转换减 1
		end_byte = end_byte, -- 0-indexed，end-exclusive，LSP textEdit 规范
		row0 = cursor_row - 1, -- 预算好 0-indexed 行号，给 textEdit.range 直接用
	}
end

--- 检测光标是否处于 checkbox 触发上下文中
-- 支持两种格式：
--   标准：`  - [` / `  * [` / `  + [`（marker 后有空格）
--   快捷：`  -[` / `  *[` / `  +[`（marker 后无空格）
---@param ctx table
---@return table|nil { marker, start_byte, end_byte, row0 }
local function parse_checkbox(ctx)
	local cursor_row = ctx.cursor[1]
	local cursor_col = ctx.cursor[2]
	local line = ctx.line or ""
	local before = line:sub(1, cursor_col)

	-- 尝试标准格式，再尝试快捷格式
	local indent, marker = before:match("^(%s*)([-*+])%s+%[$")
	if not indent then
		indent, marker = before:match("^(%s*)([-*+])%[$")
	end
	if not indent then
		return nil
	end -- 两种格式均不匹配

	-- 若光标后紧跟 "]"（mini.pairs 自动闭合），把替换范围延伸过去
	local after = line:sub(cursor_col + 1)
	local end_byte = cursor_col
	if after:match("^%]") then
		end_byte = cursor_col + 1
	end

	return {
		marker = marker, -- 列表标记符（- * +），拼接补全文本时使用
		start_byte = #indent, -- 0-indexed：缩进长度即 marker 起始字节
		end_byte = end_byte,
		row0 = cursor_row - 1, -- 0-indexed 行号
	}
end

-- ──────────────────────────────────────────────
-- blink.cmp Source 接口
-- ──────────────────────────────────────────────

-- wikilink items 缓存（只缓存无 textEdit 的"骨架"，range 每次按实时光标填入）
-- blink 文档明确："blink.cmp will mutate the items you return"
-- 因此缓存的是原始数据（_stem / label / detail），返回时在 final_items 中重新构建——安全
local _items_cache = nil -- CompletionItem 骨架数组，nil 表示尚未构建
local _items_cache_stamp = -1 -- 上次构建对应的 core.get_cache_stamp()，用于失效检测

---@param _config table  blink provider 配置中 opts 字段
---@return table         source 实例
function M.new(_config)
	-- setmetatable 创建实例，__index = M 使实例可以访问所有方法
	return setmetatable({}, { __index = M })
end

---@return string[]
function M:get_trigger_characters()
	-- 只注册 "[" 作为触发字符：
	--   wikilink：输入 "[" 后的第二个 "[" 触发
	--   checkbox：输入 "- [" 里的 "[" 触发
	-- 不注册 "-" 是为了避免普通列表输入干扰
	return { "[" }
end

--- 仅在 markdown 文件且文件处于 vault 目录内时启用
---@return boolean
function M:enabled()
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.api.nvim_get_option_value("filetype", { buf = bufnr }) ~= "markdown" then
		return false
	end
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return false
	end
	local ok, core = pcall(require, "miniobsidian")
	if not ok then
		return false
	end
	return core.in_vault(path)
end

---@param ctx      table      blink.cmp Context
---@param callback function   接收 CompletionResponse 的回调
---@return function            取消函数（同步源无实际取消逻辑，返回空函数符合规范）
function M:get_completions(ctx, callback)
	local ok, result = pcall(function()
		-- ── Wiki Link 补全 ────────────────────────────────────────────
		local wl = parse_wikilink(ctx)
		if wl then
			local core = require("miniobsidian")
			local notes = core.get_all_notes() -- vault 内所有笔记路径（core 内部缓存）
			local vault = core.config.vault_path

			-- 缓存失效：首次或笔记列表已更新
			if _items_cache == nil or core.get_cache_stamp() ~= _items_cache_stamp then
				-- 统计 stem 出现次数，同名文件的 label 需要加父目录前缀
				local stem_count = {}
				for _, path in ipairs(notes) do
					local stem = core.note_stem(path)
					stem_count[stem] = (stem_count[stem] or 0) + 1
				end

				local items = {}
				for _, path in ipairs(notes) do
					local stem = core.note_stem(path)
					local rel = path:sub(#vault + 2) -- 去掉 "vault/" 前缀，得到相对路径
					local parts = {}
					for part in rel:gmatch("[^/]+") do
						table.insert(parts, part)
					end
					local detail = #parts >= 2 and (parts[#parts - 1] .. "/" .. parts[#parts]) or rel
					local parent = #parts >= 2 and parts[#parts - 1] or ""
					local label = (stem_count[stem] > 1 and parent ~= "") and (parent .. "/" .. stem) or stem
					-- 同名文件加父目录前缀区分；唯一文件直接用 stem 保持简洁
					table.insert(items, {
						label = label,
						filterText = label, -- 与 label 一致，blink 模糊过滤基于此字段
						kind = ItemKind.File, -- 显示文件图标，语义清晰
						detail = detail, -- 菜单右侧灰色文字
						_stem = stem, -- 私有字段：插入 [[stem]] 而不是 [[label]]
						_path = path, -- 私有字段：resolve() 时读取笔记内容用
					})
				end
				_items_cache = items
				_items_cache_stamp = core.get_cache_stamp()
			end

			-- textEdit.range 依赖实时光标位置，每次重建（不能缓存，否则换行后 range 错位）
			-- 同时避免直接返回缓存 item（blink 会 mutate 返回的 items）
			local final_items = {}
			for _, item in ipairs(_items_cache) do
				table.insert(final_items, {
					label = item.label,
					filterText = item.filterText,
					kind = item.kind,
					detail = item.detail,
					insertTextFormat = PlainText,
					_stem = item._stem, -- 保留私有字段供 resolve() 方法使用
					_path = item._path,
					textEdit = {
						newText = "[[" .. item._stem .. "]]",
						range = {
							start = { line = wl.row0, character = wl.start_byte },
							["end"] = { line = wl.row0, character = wl.end_byte },
							-- ["end"] 是 Lua 保留字，必须用方括号语法
						},
					},
				})
			end
			-- is_incomplete_forward = false：已拿到全量笔记，后续输入让 blink 客户端过滤即可
			return { is_incomplete_backward = false, is_incomplete_forward = false, items = final_items }
		end

		-- ── Checkbox 补全 ─────────────────────────────────────────────
		local cb = parse_checkbox(ctx)
		if cb then
			-- 状态描述表（Obsidian / GitHub 风格），未知状态回退到通用描述
			local state_labels = {
				[" "] = "待办",
				["/"] = "进行中",
				["x"] = "已完成",
				["-"] = "已取消",
				[">"] = "已转移",
				["!"] = "重要",
				["?"] = "疑问",
			}

			local core = require("miniobsidian")
			local states = (core.config and core.config.checkbox_states) or { " ", "x" }

			local items = {}
			for i, state in ipairs(states) do
				local new_text = cb.marker .. " [" .. state .. "] "
				table.insert(items, {
					label = new_text,
					kind = ItemKind.Text,
					detail = state_labels[state] or ("状态: " .. state),
					sortText = string.format("%02d", i), -- 两位数字串保证字典序 = 用户配置顺序
					filterText = new_text,
					insertTextFormat = PlainText,
					textEdit = {
						newText = new_text,
						range = {
							start = { line = cb.row0, character = cb.start_byte },
							["end"] = { line = cb.row0, character = cb.end_byte },
						},
					},
				})
			end
			return { is_incomplete_backward = false, is_incomplete_forward = false, items = items }
		end

		-- 两种上下文均不匹配，返回空结果
		-- is_incomplete_forward = true：不缓存此空结果，继续输入时仍需重查
		return { is_incomplete_backward = false, is_incomplete_forward = true, items = {} }
	end)

	if ok then
		callback(result)
	else
		-- pcall 捕获异常，安全回退，不影响其他 source 正常工作
		callback({ is_incomplete_backward = false, is_incomplete_forward = true, items = {} })
	end

	return function() end -- 取消函数（同步源无异步操作，空函数符合 blink source 规范）
end

--- resolve：在用户悬停某个 wikilink 候选时，读取笔记前几行作为 documentation 预览
-- blink 调用时机：用户导航到某 item 后（不是每个 item 都立即调用，按需懒加载）
-- blink 会将 callback 返回的字段 deep merge 到原 item 上
---@param item     table     CompletionItem（含我们附加的 _path 私有字段）
---@param callback function  接收 resolved item 的回调
function M:resolve(item, callback)
	-- checkbox items 没有 _path 字段，直接原样返回
	if not item._path then
		return callback(item)
	end

	-- 异步读取笔记文件前 10 行作为预览，避免阻塞主线程
	vim.uv.fs_open(item._path, "r", 438, function(err, fd)
		if err or not fd then
			return callback(item)
		end -- 打开失败，安全回退

		vim.uv.fs_read(fd, 2048, 0, function(err2, data)
			vim.uv.fs_close(fd, function() end) -- 无论成功与否，关闭文件描述符
			if err2 or not data then
				return callback(item)
			end

			-- 截取前 10 行，拼成 markdown 字符串
			local lines = {}
			local count = 0
			for line in (data .. "\n"):gmatch("([^\n]*)\n") do
				count = count + 1
				table.insert(lines, line)
				if count >= 10 then
					break
				end
			end

			-- 通过 vim.schedule 切回主线程，避免在 libuv 回调中操作 nvim API
			vim.schedule(function()
				callback({
					documentation = {
						kind = "markdown",
						value = table.concat(lines, "\n"), -- 返回 markdown 格式预览
					},
				})
			end)
		end)
	end)
end

return M
