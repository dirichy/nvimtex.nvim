local M = {}

local markdown_filetypes = {
	markdown = true,
	rmd = true,
	quarto = true,
}

local excluded_nodes = {
	code_span = true,
	code_span_delimiter = true,
	fenced_code_block = true,
	fenced_code_block_delimiter = true,
	code_fence_content = true,
	indented_code_block = true,
	html_block = true,
	minus_metadata = true,
	plus_metadata = true,
	latex_block = true,
}

local function is_markdown_filetype()
	local ft = vim.api.nvim_get_option_value("filetype", { scope = "local" })
	return markdown_filetypes[ft] or false
end

local function has_excluded_ancestor(node)
	while node do
		if excluded_nodes[node:type()] then
			return true
		end
		node = node:parent()
	end
	return false
end

function M.in_text()
	if not is_markdown_filetype() then
		return false
	end

	local node = vim.treesitter.get_node()
	return node ~= nil and not has_excluded_ancestor(node)
end

return M
