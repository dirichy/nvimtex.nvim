local M = {}
M.latex_filetypes = { "tex", "plaintex", "latex", "markdown", "rmd", "quarto" }
function M.source_lines(source)
	if type(source) == "number" then
		return vim.api.nvim_buf_get_lines(source, 0, -1, false)
	end
	if type(source) == "string" then
		return vim.split(source, "\n", { plain = true })
	end
	return {}
end

---Remove a TeX line comment, preserving escaped percent signs.
---@param line string
---@return string
function M.strip_comment(line)
	-- A percent sign starts a comment only after an even number of slashes.
	for start, slashes in line:gmatch("()(\\*)%%") do
		if #slashes % 2 == 0 then
			return line:sub(1, start + #slashes - 1)
		end
	end
	return line
end

-- Header readers fetch buffer lines in small batches and stop at the preamble.
local function header_lines(source)
	if type(source) ~= "number" then
		return (source .. "\n"):gmatch("([^\n]*)\n")
	end
	local row, index, lines = 0, 0, {}
	return function()
		if index == #lines then
			lines = vim.api.nvim_buf_get_lines(source, row, row + 64, false)
			row, index = row + #lines, 0
		end
		index = index + 1
		return lines[index]
	end
end

local function preamble(source)
	local lines = {}
	for line in header_lines(source) do
		line = M.strip_comment(line)
		local finish = line:find("\\begin%s*{%s*document%s*}")
		lines[#lines + 1] = finish and line:sub(1, finish - 1) or line
		if finish then
			break
		end
	end
	return table.concat(lines, "\n")
end

-- Reuse a current tree only while its highlighter is active. Merely having a
-- parser installed must not start a full parse after users stop Tree-sitter.
local function header_root(source)
	if type(source) ~= "number" then
		return
	end
	local buffer = source == 0 and vim.api.nvim_get_current_buf() or source
	local highlighter = vim.treesitter.highlighter.active[buffer]
	if highlighter and highlighter.tree:lang() == "latex" and highlighter.tree:is_valid(true) then
		local tree = highlighter.tree:trees()[1]
		return tree and tree:root()
	end
end

M.get_magic_comment = function(source, ific)
	source = source or 0
	if ific == nil then
		ific = true
	end
	local result = {}
	for line in header_lines(source) do
		if line:match("^%%%s*!%s*[Tt][Ee][Xx]%s") then
			local k, v = line:match("^%%%s*!%s*[Tt][Ee][Xx]%s*([^=]-)%s*=%s*(.-)%s*$")
			if ific and k then
				k = k:lower()
			end
			if k then
				result[#result + 1] = { key = k, value = v }
				result[k] = result[k] or v
			end
		elseif not line:match("^%%!") then
			break
		end
	end
	return result
end
---Resolve the current file's declared main document without searching directories.
---@return string
function M.main_file()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		error("Save the TeX buffer before selecting its main file.")
	end
	local declaration = M.get_magic_comment().root
	if declaration == nil then
		local class = M.get_documentclass(0)
		if class.name == "subfiles" then
			-- The subfiles class takes one bare option: its main document path.
			local option, value = next(class.opts)
			if option == nil or value ~= true or next(class.opts, option) ~= nil then
				error("The subfiles document class requires one main-file path.")
			end
			declaration = option
		end
	end
	if declaration == nil then
		return path
	end
	if declaration == "" then
		error("The TeX root declaration must contain a main-file path.")
	end
	local main = M.normalize_file(declaration, { cwd = vim.fs.dirname(path) })
	if vim.fn.filereadable(main) == 0 then
		error("Declared TeX main file is not readable: " .. main)
	end
	return main
end
local function parse_options(text)
	local opts = {}
	if not text or text == "" then
		return opts
	end
	text = text:gsub("^%[", ""):gsub("%]$", "")
	for item in text:gmatch("[^,]+") do
		local key, value = item:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
		if key then
			opts[vim.trim(key)] = vim.trim(value)
		else
			local name = vim.trim(item)
			if name ~= "" then
				opts[name] = true
			end
		end
	end
	return opts
end

--- Get documentclass for a latex buffer
---@param root TSNode
---@param source number|string
---@return table
local function get_documentclass_by_treesitter(root, source)
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
---@param source number|string
---@return {name:string, opts:table<string,string|boolean>}
function M.get_documentclass(source)
	local root = header_root(source)
	if root then
		local ok, class = pcall(get_documentclass_by_treesitter, root, source)
		if ok then
			return class
		end
	end
	local text = preamble(source)
	local options, name = text:match("\\documentclass%f[^%a@]%s*(%b[])%s*(%b{})")
	name = name or text:match("\\documentclass%f[^%a@]%s*(%b{})")
	return { name = name and vim.trim(name:sub(2, -2)) or "", opts = parse_options(options) }
end

local function add_package(result, name, opts)
	name = vim.trim(name)
	if name == "" then
		return
	end
	local item = { name = name, opts = opts }
	table.insert(result, item)
	result[name] = item
end

local function get_packages_by_text(source)
	local result = {}
	for command, rest in preamble(source):gmatch("\\([%a@]+)([^\\]*)") do
		if command == "usepackage" or command == "RequirePackage" then
			local options, names = rest:match("^%s*(%b[])%s*(%b{})")
			names = names or rest:match("^%s*(%b{})")
			if names then
				local opts = parse_options(options)
				for name in names:sub(2, -2):gmatch("[^,]+") do
					add_package(result, name, opts)
				end
			end
		end
	end
	return result
end

---@param root TSNode
---@param source number|string
local function get_packages_by_treesitter(root, source)
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
					add_package(res, name, opts)
				end
			end
		end
	end
	return res
end

function M.get_packages(source)
	local root = header_root(source)
	if root then
		local ok, result = pcall(get_packages_by_treesitter, root, source)
		if ok then
			return result
		end
	end
	return get_packages_by_text(source)
end

function M.readfile(path)
	local f = io.open(path, "r")
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

function M.is_absolute_path(path)
	return path:match("^/") or path:match("^%a:[/\\]")
end

function M.with_extension(path, extension)
	extension = extension:gsub("^%.", "")
	if path:sub(-#extension - 1) == "." .. extension then
		return path
	end
	return path .. "." .. extension
end

function M.file_path(dir, stem, extension)
	return dir .. "/" .. M.with_extension(stem, extension)
end

---@param path string
---@param opts? { cwd?: string, extension?: string }
---@return string
function M.normalize_file(path, opts)
	opts = opts or {}
	if opts.extension then
		path = M.with_extension(path, opts.extension)
	end
	if opts.cwd and not M.is_absolute_path(path) then
		path = opts.cwd .. "/" .. path
	end
	return vim.fs.normalize(vim.fn.simplify(path))
end

function M.relative_path(base, path)
	base = vim.fs.normalize(base)
	path = vim.fs.normalize(path)
	if path:sub(1, #base + 1) == base .. "/" then
		return path:sub(#base + 2)
	end
	return vim.fn.fnamemodify(path, ":t")
end

function M.ensure_dir(path)
	vim.fn.mkdir(path, "p")
	return path
end

function M.copy_file(source, target)
	if not vim.uv.fs_stat(source) then
		return false
	end
	local parent = vim.fs.dirname(target)
	if parent then
		M.ensure_dir(parent)
	end
	local data = vim.fn.readfile(source, "b")
	vim.fn.writefile(data, target, "b")
	return true
end

function M.file_newer_than(path, other_path)
	local stat = vim.uv.fs_stat(path)
	local other_stat = vim.uv.fs_stat(other_path)
	local mtime = stat and (stat.mtime.sec + stat.mtime.nsec / 1000000000) or 0
	local other_mtime = other_stat and (other_stat.mtime.sec + other_stat.mtime.nsec / 1000000000) or 0
	return mtime > other_mtime
end

function M.debounce(fn, ms)
	local timer = vim.uv.new_timer()

	return function(...)
		local argv = { ... }

		timer:stop()

		timer:start(ms, 0, function()
			vim.schedule(function()
				fn(unpack(argv))
			end)
		end)
	end
end

return M
