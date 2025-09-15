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
--- get node under cursor
--- @return TSNode|nil
M.get_node_at_cursor = vim.treesitter.get_node

M.node_parent = function(node, bufer)
	return node:parent()
end

return M
