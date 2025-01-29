local M = {}

---@class ConflictObj
---@field buf number
---@field lines number[]
---@field local_change string[]
---@field remote_change string[]

---@type ConflictObj
M.current_conflict = nil

local function starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

function M.run_command(command, callback)
	local result = vim.fn.system(command)
	if vim.v.shell_error == 0 then
		vim.notify("Comando executado com sucesso: " .. command)
		if callback then callback(result) end
		return true
	else
		vim.notify("Erro ao executar comando: " .. command .. "\nErro: " .. result, vim.log.levels.ERROR)
		return false
	end
end

function M.set_highlight()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local head, branch = nil, nil

	for i, line in ipairs(lines) do
		if starts_with(line, "<<<<<<< HEAD") then
			vim.api.nvim_buf_add_highlight(buf, -1, "DiffAdd", i - 1, 0, -1)
			head = i
		elseif starts_with(line, "=======") then
			head = nil
			branch = i
		elseif starts_with(line, ">>>>>>>") then
			branch = nil
			vim.api.nvim_buf_add_highlight(buf, -1, "IncSearch", i - 1, 0, -1)
		elseif head then
			vim.api.nvim_buf_add_highlight(buf, -1, "DiffChange", i - 1, 0, -1)
		elseif branch then
			vim.api.nvim_buf_add_highlight(buf, -1, "Search", i - 1, 0, -1)
		end
	end
end

function M.get_conflicts()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local conflicts, local_changes, remote_changes = {}, {}, {}
	local add_local, add_remote, start_line

	for i, line in ipairs(lines) do
		if starts_with(line, "<<<<<<< HEAD") then
			add_local, start_line = true, i
		elseif starts_with(line, "=======") then
			add_local, add_remote = false, true
		elseif starts_with(line, ">>>>>>>") then
			add_remote = false
			table.insert(conflicts,
				{ buf = buf, lines = { start_line, i }, local_change = local_changes, remote_change = remote_changes })
			local_changes, remote_changes = {}, {}
		elseif add_local then
			table.insert(local_changes, line)
		elseif add_remote then
			table.insert(remote_changes, line)
		end
	end
	return conflicts
end

function M.get_merge_files()
	local files = {}
	M.run_command("git diff --name-only --diff-filter=U", function(output)
		for line in output:gmatch("[^\r\n]+") do
			table.insert(files, line)
		end
	end)
	return files
end

function M.get_current_conflict()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local buf = vim.api.nvim_get_current_buf()
	for _, conflict in ipairs(M.buf_conflicts or {}) do
		if conflict.buf == buf and conflict.lines[1] <= row and conflict.lines[2] >= row then
			return conflict
		end
	end
end

local function accept_changes(type)
	if not M.buf_conflicts then return end
	local conflict = M.get_current_conflict()
	if not conflict then return end
	vim.api.nvim_buf_set_lines(conflict.buf, conflict.lines[1] - 1, conflict.lines[2], false,
		type == "local" and conflict.local_change or conflict.remote_change)
	M.buf_conflicts = vim.tbl_filter(function(c) return c.lines[1] ~= conflict.lines[1] end, M.buf_conflicts)
	M.list_all_conflicts()
end

M.accept_local_changes = function() accept_changes("local") end
M.accept_remote_changes = function() accept_changes("remote") end

function M.list_all_conflicts()
	M.buf_conflicts = {}
	for _, file in ipairs(M.get_merge_files()) do
		vim.cmd("edit " .. file)
		M.set_highlight()
		local buf = vim.api.nvim_get_current_buf()
		for _, conflict in ipairs(M.get_conflicts()) do
			conflict.buf = buf
			table.insert(M.buf_conflicts, conflict)
		end
	end
end

local function tbl_indexof(table, item)
	for index, _item in ipairs(table) do
		if _item.lines[1] == item.lines[1] then
			return index
		end
	end
end
local function navigate_conflict(direction)
	if not M.buf_conflicts or #M.buf_conflicts == 0 then return end
	if not M.current_conflict then M.current_conflict = M.get_current_conflict() or M.buf_conflicts[1] end
	local index = tbl_indexof(M.buf_conflicts, M.current_conflict) or 1
	M.current_conflict = M.buf_conflicts[(index + direction - 1) % #M.buf_conflicts + 1]
	vim.api.nvim_set_current_buf(M.current_conflict.buf)
	vim.api.nvim_win_set_cursor(0, { M.current_conflict.lines[1], 0 })
end

M.to_next_conflict = function() navigate_conflict(1) end
M.to_prev_conflict = function() navigate_conflict(-1) end
M.confirm_merge = function()
end

function M.setup(opts)
	M.keymapAcceptLocalChanges = opts.accept_local_changes or ":GitMergeToolAcceptLocalChange"
	M.keymapAcceptRemoteChanges = opts.accept_remote_changes or ":GitMergeToolAcceptRemoteChange"
	M.keymapListAllConflicts = opts.list_all_conflicts or ":GitMergeToolListAllConflicts"
	M.keymapNextConflict = opts.next_conflict or ":GitMergeToolToNextConflict"
	M.keymapPrevConflict = opts.prev_conflict or ":GitMergeToolToPrevConflict"
	M.keymapConfirmMerge = opts.prev_conflict or ":GitMergeToolConfirmMerge"

	if vim.fn.executable("git") == 0 then
		vim.notify("Git não está instalado! Este plugin pode não funcionar corretamente.", vim.log.levels.ERROR)
	end

	vim.api.nvim_create_user_command(M.keymapAcceptLocalChanges:sub(2), M.accept_local_changes, {})
	vim.api.nvim_create_user_command(M.keymapAcceptRemoteChanges:sub(2), M.accept_remote_changes, {})
	vim.api.nvim_create_user_command(M.keymapListAllConflicts:sub(2), M.list_all_conflicts, {})
	vim.api.nvim_create_user_command(M.keymapNextConflict:sub(2), M.to_next_conflict, {})
	vim.api.nvim_create_user_command(M.keymapPrevConflict:sub(2), M.to_prev_conflict, {})
	vim.api.nvim_create_user_command(M.keymapConfirmMerge:sub(2), M.confirm_merge, {})
end

return M
