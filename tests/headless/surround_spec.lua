vim.opt.runtimepath:prepend(vim.fn.getcwd())

local surround = require("nvimtex.surround")

local notifications = {}
vim.notify = function(message)
	table.insert(notifications, message)
end

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function first_node(root, predicate)
	if predicate(root) then
		return root
	end
	for child in root:iter_children() do
		local result = first_node(child, predicate)
		if result then
			return result
		end
	end
end

local function parse(source)
	return vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
end

local function first_math_environment(source)
	return first_node(parse(source), function(node)
		return node:type() == "math_environment"
	end)
end

local function buffer_node(source, node_type)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(source, "\n", { plain = true }))
	local root = vim.treesitter.get_parser(buf, "latex"):parse()[1]:root()
	return buf, first_node(root, function(node)
		return node:type() == node_type
	end)
end

local aligned_source = [[
\begin{equation}
\begin{aligned}
a&=b
\end{aligned}
\end{equation}
]]
eq(
	surround.get_math_type(aligned_source, first_math_environment(aligned_source)),
	surround.mtype.aligned,
	"aligned body"
)
print("ok surround aligned body")

local mixed_source = [[
\begin{equation}
x+
\begin{aligned}
a&=b
\end{aligned}
\end{equation}
]]
eq(
	surround.get_math_type(mixed_source, first_math_environment(mixed_source)),
	surround.mtype.equation,
	"mixed equation"
)
print("ok surround mixed equation")

local inline_buf, inline_node = buffer_node("$a=b$", "inline_formula")
eq(
	surround.format_math(inline_buf, inline_node, { "\\[", "\\]", true, false }),
	{ "\\[", "a=b", "\\]" },
	"inline to display"
)
print("ok surround inline format")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "tex"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "plain text" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local ok, err = pcall(surround.upgrade_math)
if not ok then
	error("upgrade outside math should not throw: " .. err)
end
eq(notifications[#notifications], "Can't find math node on cursor!", "outside math notify")
print("ok surround upgrade outside math")
