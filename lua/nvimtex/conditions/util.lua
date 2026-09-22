local M = {}
M.MATH_NODES = {
	displayed_equation = true,
	inline_formula = true,
	math_environment = true,
}

M.TEXT_NODES = {
	text_mode = true,
}

M.ENV_NODES = {
	generic_environment = true,
	math_environment = true,
	comment_environment = true,
	verbatim_environment = true,
	listing_environment = true,
	minted_environment = true,
	pycode_environment = true,
	sagesilent_environment = true,
	sageblock_environment = true,
}
M.ENG_NODES = {
	label_definition = true,
	label_reference = true,
}
M.CMD_NODES = {
	generic_command = true,
	class_include = true,
	package_include = true,
	theorem_definition = true,
	old_command_definition = true,
	begin = true,
	["end"] = true,
}

local function is_latex_node(node)
	while node do
		local node_type = node:type()
		if
			node_type == "source_file"
			or M.MATH_NODES[node_type]
			or M.TEXT_NODES[node_type]
			or M.ENV_NODES[node_type]
			or M.CMD_NODES[node_type]
		then
			return true
		end
		node = node:parent()
	end
	return false
end

--- get node under cursor
--- @return TSNode|nil
function M.get_node_at_cursor()
	local ft = vim.api.nvim_get_option_value("filetype", { scope = "local" })
	if ft == "markdown" or ft == "rmd" or ft == "quarto" then
		pcall(function()
			vim.treesitter.get_parser(0):parse(true)
		end)
		local node = vim.treesitter.get_node({ ignore_injections = false })
		if is_latex_node(node) then
			return node
		end
		return nil
	end
	local ok, node = pcall(vim.treesitter.get_node, { lang = "latex" })
	if ok and node then
		return node
	end
	return vim.treesitter.get_node()
end

function M.in_latex_tree()
	return M.get_node_at_cursor() ~= nil
end

M.node_parent = function(node, bufer)
	return node:parent()
end

return M
