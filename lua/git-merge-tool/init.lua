local M = {}
local function start_with(value, prefix)
	if value:sub(1, #prefix) == prefix then
		return true
	end
	return false
end
function M.run_command(command, callback)
	local result = vim.fn.system(command)
	if vim.v.shell_error == 0 then
		vim.notify("Comando executado com sucesso: " .. command)
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
		if start_with(line, "<<<<<<< HEAD") then
			vim.api.nvim_buf_add_highlight(buf, -1, "DiffAdd", i - 1, 0, -1)
			vim.diagnostic.set(vim.api.nvim_create_namespace("merge"), buf, {
				{
					lnum = i - 2,
					col = 0,
					severity = vim.diagnostic.severity.INFO,
					message = "(<Leader>gml) Para aceitar alterações locais || (<Leader>gmr) Para aceitar alterações remotas",
				},
			})
			lineContentHead = i
		elseif start_with(line, "=======") then
			lineContentHead = nil
			lineContentBranch = i
		elseif start_with(line, ">>>>>>>") then
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

function M.get_conflits()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local comflits = {}
	local LLines = {}
	local RLines = {}
	local addLLine = false
	local addRLine = false
	local addComflit = false
	local initLine = nil
	local endLine = nil
	for i, line in ipairs(lines) do
		if start_with(line, "<<<<<<< HEAD") then
			addLLine = true
			initLine = i
		elseif start_with(line, "=======") then
			addLLine = false
			addRLine = true
		elseif start_with(line, ">>>>>>>") then
			addRLine = false
			addComflit = true
			endLine = i
		elseif addLLine then
			table.insert(LLines, line)
		elseif addRLine then
			table.insert(RLines, line)
		end
		if addComflit then
			table.insert(comflits, { LLines, RLines, { initLine, endLine } })
			addComflit = false
			initLine = nil
			endLine = nil
		end
	end
	return comflits
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

function M.init_merge()
	local files = M.get_list_merge_files()
	M.buf_comflits = {}
	for _, file in ipairs(files) do
		vim.cmd("edit " .. file)
		M.set_highlight()
		local buf = vim.api.nvim_get_current_buf()
		local conflits = M.get_conflits()
		table.insert(conflits, buf)
		table.insert(M.buf_comflits, conflits)
	end
end

function M.get_current_conflit(callback)
	local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
	local buf = vim.api.nvim_get_current_buf()
	for i, item in ipairs(M.buf_comflits) do
		if item[2] == buf then
			if item[1][3][1] >= row and item[1][3][2] <= row then
				callback(item)
				print(vim.inspect(item))
			end
		end
	end
end

function M.setup(opts)
	local usekeymaps = opts.usekeymaps
	if vim.fn.executable("git") == 0 then
		vim.notify(
			"git-commit-tool: Git não está instalado! Este plugin pode não funcionar corretamente.",
			vim.log.levels.ERROR
		)
	end
	if usekeymaps then
		-- definir atatlhos
	end
end

return M
