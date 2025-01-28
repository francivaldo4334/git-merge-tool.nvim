local M = {}
local function startWith(value, prefix)
	if value:sub(1, #prefix) == prefix then
		return true
	end
	return false
end
function M.set_highlight()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local lineContentHead = nil
	local lineContentBranch = nil
	for i, line in ipairs(lines) do
		if startWith(line, "<<<<<<< HEAD") then
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
		elseif startWith(line, "=======") then
			lineContentHead = nil
			lineContentBranch = i
		elseif startWith(line, ">>>>>>>") then
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

function M.setup(opts)
	local usekeymaps = opts.usekeymaps
	if usekeymaps then
		-- definir atatlhos
	end
end

return M
