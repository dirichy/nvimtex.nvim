local M = {}
M.get_magic_comment = function(key, ific, buffer)
	buffer = buffer or 0
	if ific == nil then
		ific = true
	end
	if ific then
		key = string.lower(key)
	end
	local i = 0
	local value = nil
	while true do
		local line = vim.api.nvim_buf_get_lines(buffer, i, i + 1, false)[1]
		if string.match(line, "^%%![Tt][Ee][Xx]") then
			if ific then
				line = string.lower(line)
			end
			local k, v = string.match(line, "^%%![Tt][Ee][Xx]%s*([^=]-)%s*=%s*(%a*)%s*$")
			if key == k then
				value = v
				break
			end
			i = i + 1
		elseif string.match(line, "^%%!") then
			i = i + 1
			goto continue
		else
			break
		end
		::continue::
	end
	return value
end
--- Get documentclass for a latex buffer
---@param source number|string
---@return table
M.get_documentclass = function(source)
	local root
	if type(source) == "number" then
		root = vim.treesitter.get_parser(source, "latex"):trees()[1]:root()
	else
		root = vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
	end
	---@type TSNode?
	local class_node
	for node in root:iter_children() do
		if node:type() == "class_include" then
			class_node = node
			break
		end
	end
	local res = { opts = {}, name = "" }
	if class_node then
		local options = class_node:field("options")[1]
		if options then
			for _, pair in ipairs(options:field("pair")) do
				res.opts[vim.treesitter.get_node_text(pair:field("key")[1], source)] = pair:field("value")[1]
						and vim.treesitter.get_node_text(pair:field("value")[1], source)
					or true
			end
		end
		class_node = class_node:field("path")[1]
		if class_node then
			class_node = class_node:field("path")[1]
			if class_node then
				res.name = vim.treesitter.get_node_text(class_node, source)
			end
		end
	end
	return res
end
function M.get_packages(source)
	local root = vim.treesitter.get_parser(source, "latex"):trees()[1]:root()
	local res = {}
	---@type TSNode?
	for node in root:iter_children() do
		if node:type() == "package_include" then
			local opts = {}
			local options = node:field("options")[1]
			if options then
				for _, pair in ipairs(options:field("pair")) do
					opts[vim.treesitter.get_node_text(pair:field("key")[1], source)] = pair:field("value")[1]
							and vim.treesitter.get_node_text(pair:field("value")[1], source)
						or true
				end
			end
			local packages = node:field("paths")[1]
			if packages then
				for _, path in ipairs(packages:field("path")) do
					local name = vim.treesitter.get_node_text(path, source)
					local item = { name = name, opts = opts }
					table.insert(res, item)
					res[name] = item
				end
			end
		end
	end
	return res
end
function M.showlog(path)
	path = path or vim.fn.expand("%:p")
	-- 提取文件名（去除路径和.tex扩展名）
	local jobname = vim.fn.fnamemodify(path, ":t:r") --(path, "([^/]*)%.tex$")
	-- 获取文件所在目录
	local cwd = vim.fn.fnamemodify(path, ":h") --(path, "(.*)/[^/]*%.tex$")
	local cmd = table.concat({ "texlogsieve", cwd .. "/" .. jobname .. ".log", "--color" }, " ")
	-- 获取命令输出并写入 buffer
	local lines = vim.fn.systemlist(cmd)
	M.showbelow(lines)
end
function M.showbelow(lines)
	-- 计算 30% 的高度
	local total = vim.o.lines
	local height = math.floor(total * 0.3)
	if height < 1 then
		height = 1
	end

	-- 创建 scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	-- 打开普通 split 在当前窗口下方
	local win = vim.api.nvim_open_win(buf, true, {
		win = 0,
		split = "below",
		height = height,
	})

	require("baleia").setup({}).buf_set_lines(buf, 0, -1, false, lines)

	-- 设置 buffer-local 选项：filetype 和 modifiable
	vim.api.nvim_set_option_value("filetype", "terminal", { scope = "local", buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { scope = "local", buf = buf })
	-- 设置 window-local 选项：concealcursor
	vim.api.nvim_set_option_value("concealcursor", "nvic", { scope = "local", win = win })

	-- 设置 buffer-local q 键映射关闭窗口
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
end
function M.readfile(path)
	local f, e = io.open(path, "r")
	if not f then
		return {}
	end
	local res = {}
	local line = f:read("*l")
	while line do
		table.insert(res, line)
		line = f:read("*l")
	end
	f:close()
	return res
end

return M
