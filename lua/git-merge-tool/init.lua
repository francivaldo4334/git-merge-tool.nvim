local M = {}
---@class ConflitObj
---@field buf number
---@field lines number[]
---@field local_change string[]
---@field remote_change string[]

---@type ConflitObj
M.current_conflit = nil
function M.run_command(command, callback)
	local result = vim.fn.system(command)
	if vim.v.shell_error == 0 then
		if callback then
			callback(result)
		end
		return true
	else
		vim.notify(string.format("Erro ao executar comando: %s, error: %s", command, result), vim.log.levels.ERROR)
		return false
	end
end

function M.set_highlight()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local lineContentHead = nil
	local lineContentBranch = nil
	for i, line in ipairs(lines) do
		if vim.startswith(line, "<<<<<<< HEAD") then
			vim.api.nvim_buf_add_highlight(buf, -1, "DiffAdd", i - 1, 0, -1)
			vim.diagnostic.set(vim.api.nvim_create_namespace("merge_conflit_" .. i), buf, {
				{
					lnum = i - 1,
					col = 0,
					severity = vim.diagnostic.severity.INFO,
					message = string.format(
						"(%s) Para aceitar alterações locais || (%s) Para aceitar alterações remotas",
						M.keymapAcceptLocalChanges,
						M.keymapAcceptRemoteChanges
					),
				},
			})
			lineContentHead = i
		elseif vim.startswith(line, "=======") then
			lineContentHead = nil
			lineContentBranch = i
		elseif vim.startswith(line, ">>>>>>>") then
			lineContentBranch = nil
			vim.api.nvim_buf_add_highlight(buf, -1, "IncSearch", i - 1, 0, -1)
		else
			if lineContentHead then
				lineContentHead = i
				vim.api.nvim_buf_add_highlight(buf, -1, "DiffChange", lineContentHead - 1, 0, -1)
			end
			if lineContentBranch then
				lineContentBranch = i
				vim.api.nvim_buf_add_highlight(buf, -1, "Search", lineContentBranch - 1, 0, -1)
			end
		end
	end
end

---@return ConflitObj[]
function M.get_conflits()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	---@type ConflitObj[]
	local conflits = {}
	local LLines = {}
	local RLines = {}
	local addLLine = false
	local addRLine = false
	local addComflit = false
	local initLine = nil
	local endLine = nil
	for i, line in ipairs(lines) do
		if vim.startswith(line, "<<<<<<< HEAD") then
			addLLine = true
			initLine = i
		elseif vim.startswith(line, "=======") then
			addLLine = false
			addRLine = true
		elseif vim.startswith(line, ">>>>>>>") then
			addRLine = false
			addComflit = true
			endLine = i
		elseif addLLine then
			table.insert(LLines, line)
		elseif addRLine then
			table.insert(RLines, line)
		end
		if addComflit then
			table.insert(
				conflits,
				---@ConflitObj
				{
					buf = 0,
					lines = { initLine, endLine },
					local_change = LLines,
					remote_change = RLines,
				}
			)
			LLines = {}
			RLines = {}
			addComflit = false
			initLine = nil
			endLine = nil
		end
	end
	return conflits
end

function M.get_list_merge_files()
	local files = {}
	M.run_command("git diff --name-only --diff-filter=U", function(text)
		for line in string.gmatch(text, "[^\r\n]+") do
			table.insert(files, line)
		end
	end)
	return files
end

function M.get_current_conflit()
	local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
	local buf = vim.api.nvim_get_current_buf()
	for _, item in ipairs(M.buf_comflits) do
		if item.buf == buf then
			if item.lines[1] <= row and item.lines[2] >= row then
				return item
			end
		end
	end
end

function remove_conflit(item)
	for i, conflit in ipairs(M.buf_comflits) do
		if conflit.lines[1] == item.lines[1] then
			table.remove(M.buf_comflits, i)
			break
		end
	end
end

function clean_namespaces(item)
	local namespaces = vim.api.nvim_get_namespaces()
	for id, ns in pairs(namespaces) do
		if vim.startswith(id, "merge_conflit_") then
			vim.diagnostic.reset(ns, item.buf)
		end
	end
end

function M.accept_local_changes()
	local item = M.get_current_conflit()
	if not M.buf_comflits or not item then
		return
	end
	vim.api.nvim_buf_set_lines(item.buf, item.lines[1] - 1, item.lines[2], false, item.local_change)
	vim.api.nvim_buf_call(item.buf, function()
		vim.cmd("write")
	end)
	clean_namespaces(item)
	remove_conflit(item)
	M.list_all_conflits()
end

function M.accept_remote_changes()
	local item = M.get_current_conflit()
	if not M.buf_comflits or not item then
		return
	end
	vim.api.nvim_buf_set_lines(item.buf, item.lines[1] - 1, item.lines[2], false, item.remote_change)
	vim.api.nvim_buf_call(item.buf, function()
		vim.cmd("write")
	end)
	clean_namespaces(item)
	remove_conflit(item)
	M.list_all_conflits()
end

function M.accept_all_changes()
	local item = M.get_current_conflit()
	if not M.buf_comflits or not item then
		return
	end
	local lines = item.local_change
	for _, line in ipairs(item.remote_change) do
		table.insert(lines, line)
	end
	vim.api.nvim_buf_set_lines(item.buf, item.lines[1] - 1, item.lines[2], false, lines)
	vim.api.nvim_buf_call(item.buf, function()
		vim.cmd("write")
	end)
	clean_namespaces(item)
	remove_conflit(item)
	M.list_all_conflits()
end

function M.list_all_conflits()
	local files = M.get_list_merge_files()
	---@type ConflitObj[]
	M.buf_comflits = {}
	for _, file in ipairs(files) do
		vim.cmd("edit " .. file)
		M.set_highlight()
		local buf = vim.api.nvim_get_current_buf()
		local conflits = M.get_conflits()
		for _, conflit in ipairs(conflits) do
			conflit.buf = buf
			table.insert(M.buf_comflits, conflit)
		end
	end
end

function M.to_next_conflit()
	if not M.buf_comflits then
		return
	end
	if not M.current_conflit then
		M.current_conflit = M.get_current_conflit() or next(M.buf_comflits)[2]
	end
	for i, conflit in ipairs(M.buf_comflits) do
		if conflit.lines[1] == M.current_conflit.lines[1] then
			if i + 1 > #M.buf_comflits then
				M.current_conflit = M.buf_comflits[1]
			else
				M.current_conflit = M.buf_comflits[i + 1]
			end
			break
		end
	end
	vim.api.nvim_set_current_buf(M.current_conflit.buf)
	vim.api.nvim_win_set_cursor(0, { M.current_conflit.lines[1], 0 })
end

function M.to_prev_conflit()
	if not M.buf_comflits then
		return
	end
	if not M.current_conflit then
		M.current_conflit = M.get_current_conflit() or next(M.buf_comflits)[2]
	end
	for i, conflit in ipairs(M.buf_comflits) do
		if conflit.lines[1] == M.current_conflit.lines[1] then
			if i - 1 <= 0 then
				M.current_conflit = M.buf_comflits[#M.buf_comflits]
			else
				M.current_conflit = M.buf_comflits[i - 1]
			end
			break
		end
	end
	vim.api.nvim_set_current_buf(M.current_conflit.buf)
	vim.api.nvim_win_set_cursor(0, { M.current_conflit.lines[1], 0 })
end

function M.configm_merge()
	M.run_command("git add .")
	M.run_command("git commit --no-edit")
end

function M.setup(opts)
	M.keymapAcceptLocalChanges = ":GitMergeToolAcceptLocalChange"
	M.keymapAcceptRemoteChanges = ":GitMergeToolAcceptRemoteChange"
	M.keymapAcceptAllChanges = ":GitMergeToolAcceptAllChanges"
	M.keymapLisAllConflits = ":GitMergeToolListAllConflicts"
	M.keymapNextConflit = ":GitMergeToolToNextConflict"
	M.keymapPrevConflit = ":GitMergeToolToPrevConflict"
	M.keymapConfirmMerge = ":GitMergeToolConfirmMerge"
	if vim.fn.executable("git") == 0 then
		vim.notify(
			"git-commit-tool: Git não está instalado! Este plugin pode não funcionar corretamente.",
			vim.log.levels.ERROR
		)
	end
	vim.api.nvim_create_user_command(M.keymapAcceptLocalChanges:sub(2), M.accept_local_changes, {})
	vim.api.nvim_create_user_command(M.keymapAcceptRemoteChanges:sub(2), M.accept_remote_changes, {})
	vim.api.nvim_create_user_command(M.keymapAcceptAllChanges:sub(2), M.accept_all_changes, {})
	vim.api.nvim_create_user_command(M.keymapLisAllConflits:sub(2), M.list_all_conflits, {})
	vim.api.nvim_create_user_command(M.keymapNextConflit:sub(2), M.to_next_conflit, {})
	vim.api.nvim_create_user_command(M.keymapPrevConflit:sub(2), M.to_prev_conflit, {})
	vim.api.nvim_create_user_command(M.keymapConfirmMerge:sub(2), M.configm_merge, {})
	if opts.keymaps then
		local function set_keymap(keymap, command)
			if keymap then
				vim.api.nvim_set_keymap("n", keymap, command .. "<CR>", { silent = true })
			end
		end

		set_keymap(opts.keymaps.accept_local_changes, M.keymapAcceptLocalChanges)
		set_keymap(opts.keymaps.accept_remote_changes, M.keymapAcceptRemoteChanges)
		set_keymap(opts.keymaps.accept_all_changes, M.keymapAcceptAllChanges)
		set_keymap(opts.keymaps.lis_all_conflits, M.keymapLisAllConflits)
		set_keymap(opts.keymaps.next_conflit, M.keymapNextConflit)
		set_keymap(opts.keymaps.prev_conflit, M.keymapPrevConflit)
		set_keymap(opts.keymaps.confirm_merge, M.keymapConfirmMerge)

		M.keymapAcceptLocalChanges = opts.keymaps.accept_local_changes or M.keymapAcceptLocalChanges
		M.keymapAcceptRemoteChanges = opts.keymaps.accept_remote_changes or M.keymapAcceptRemoteChanges
		M.keymapAcceptAllChanges = opts.keymaps.accept_all_changes or M.keymapAcceptAllChanges
		M.keymapLisAllConflits = opts.keymaps.lis_all_conflits or M.keymapLisAllConflits
		M.keymapNextConflit = opts.keymaps.next_conflit or M.keymapNextConflit
		M.keymapPrevConflit = opts.keymaps.prev_conflit or M.keymapPrevConflit
		M.keymapConfirmMerge = opts.keymaps.confirm_merge or M.keymapConfirmMerge
	end
end

return M
