local M = {}
function M.source_lines(source)
	if type(source) == "number" then
		return vim.api.nvim_buf_get_lines(source, 0, -1, false)
	end
	if type(source) == "string" then
		return vim.split(source, "\n", { plain = true })
	end
	return {}
end

M.get_magic_comment = function(source, ific)
	source = source or 0
	if ific == nil then
		ific = true
	end
	local i = 0
	local result = {}
	local lines = M.source_lines(source)
	while true do
		local line = lines[i + 1]
		if not line then
			break
		end
		if string.match(line, "^%%%s*!%s*[Tt][Ee][Xx]%s") then
			local k, v = string.match(line, "^%%%s*!%s*[Tt][Ee][Xx]%s*([^=]-)%s*=%s*(.-)%s*$")
			if ific and k then
				k = string.lower(k)
			end
			if k then
				local item = { key = k, value = v }
				table.insert(result, item)
				result[k] = result[k] or v
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
	return result
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
	for _, line in ipairs(M.source_lines(source)) do
		line = line:gsub("%%.*$", "")
		for options, package_text in line:gmatch("\\usepackage%s*(%b[])%s*(%b{})") do
			local opts = parse_options(options)
			local package_names = package_text:sub(2, -2)
			for name in package_names:gmatch("[^,]+") do
				add_package(result, name, opts)
			end
		end
		for package_text in line:gmatch("\\usepackage%s*(%b{})") do
			local package_names = package_text:sub(2, -2)
			for name in package_names:gmatch("[^,]+") do
				add_package(result, name, {})
			end
		end
	end
	return result
end

local function get_packages_by_treesitter(source)
	local root
	if type(source) == "number" then
		root = vim.treesitter.get_parser(source, "latex"):trees()[1]:root()
	else
		root = vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
	end
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
	local ok, result = pcall(get_packages_by_treesitter, source)
	if ok then
		return result
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

function M.normalize_file(path, opts)
	opts = opts or {}
	if opts.extension then
		path = M.with_extension(path, opts.extension)
	end
	if opts.cwd and not M.is_absolute_path(path) then
		path = opts.cwd .. "/" .. path
	end
	return vim.fs.normalize(path)
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
