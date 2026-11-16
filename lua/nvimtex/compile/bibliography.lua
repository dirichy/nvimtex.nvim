-- BibTeX/Biber rules adapted from VimTeX (MIT).
-- Copyright (c) 2025 Karl Yngve Lervåg. See LICENSES/VimTeX.txt.
local log = require("nvimtex.compile.log")
local util = require("nvimtex.util")
local M = {}

-- The only state here is the preceding BibTeX message: its next line may
-- supply a .bst/.bib location. Biber messages carry their own severity.
local function parse(lines, biber, main, root)
	local items, current = {}, nil
	for _, line in ipairs(lines) do
		local kind, message, file, row
		if biber then
			if line:find("ERROR -", 1, true) then
				kind, message = "E", line
			elseif
				line:find("WARN - Duplicate entry", 1, true)
				or (line:find("WARN - The entry", 1, true) and line:find("cannot be encoded", 1, true))
			then
				kind, message = "W", line
			end
		elseif current and (line:match("^while executing%-%-%-line ") or line:match("^%-%-line ")) then
			row, file = line:match("line (%d+) of file (.+)$")
			if file then
				current.lnum, current.filename = tonumber(row) or 0, util.normalize_file(file, { cwd = root })
			end
		else
			message, row, file = line:match("^(.-)%-%-%-line (%d+) of file (.+)$")
			if file then
				kind = "E"
			elseif line:match("^Name.*has a comma at the end") then
				kind, message = "E", line
			elseif line:match("^I found .-%-%-%-while reading file .+") then
				kind, message = "E", line
				file = line:match("%-%-%-while reading file (.+)$")
			elseif line:match("^Warning%-%-empty .+ in .+") or line:match("^Warning%-%-entry type for.+") then
				kind, message = "W", line
			else
				current = nil
			end
		end
		if kind then
			current = log.entry(
				kind,
				message or line,
				file and util.normalize_file(file, { cwd = root }) or main,
				tonumber(row)
			)
			items[#items + 1] = current
		end
	end
	return items
end

---@param main string
---@param logfile string
---@return nvimtex.compile.LogEntry[]
function M.read(main, logfile)
	if vim.fn.filereadable(logfile) == 0 then
		return {}
	end
	local lines = vim.fn.readfile(logfile)
	local root, directory = vim.fs.dirname(main), vim.fs.dirname(logfile)
	local text = table.concat(lines, "\n")
	local biber = text:find("INFO%s+%-%s+This is Biber") ~= nil
	local files, entries, resolved, sources = {}, {}, {}, {}
	local function resolve(name)
		if resolved[name] ~= nil then
			return resolved[name]
		end
		for _, base in ipairs({ root, directory }) do
			local path = util.normalize_file(name, { cwd = base })
			if vim.fn.filereadable(path) == 1 then
				resolved[name] = path
				return path
			end
		end
		local path = vim.fn.executable("kpsewhich") == 1 and vim.fn.systemlist({ "kpsewhich", name })[1]
		resolved[name] = path and vim.fn.filereadable(path) == 1 and path or false
		return resolved[name]
	end
	local function add_file(name)
		local file = resolve(name)
		if file and entries[file] == nil then
			files[#files + 1] = file
			entries[file] = false
		end
	end
	-- Successful builds need no entry scan. Index each source lazily and share it
	-- across all messages in this read, without a persistent invalidation cache.
	local function index_file(file)
		if entries[file] then
			return entries[file]
		end
		local index = {}
		for lnum, line in ipairs(vim.fn.readfile(file)) do
			local key = line:match("^%s*@[%w_]+%s*[{(]%s*([^,%s]+)")
			if key then
				index[key] = index[key] or lnum
			end
		end
		entries[file] = index
		return index
	end
	local active
	for _, line in ipairs(lines) do
		local name = line:match("Database file #%d+: (.+)") or line:match("INFO %- Found BibTeX data source '(.+)'$")
		if name then
			add_file(name)
			active = resolve(name)
		end
		sources[line] = active
	end
	-- Biber may fail before reporting its sources. Literal resource declarations
	-- are a fallback; TeX macros and conditional includes are not evaluated.
	local items = parse(lines, biber, main, root)
	if biber and #files == 0 and #items > 0 and vim.fn.filereadable(main) == 1 then
		for _, line in ipairs(vim.fn.readfile(main)) do
			line = util.strip_comment(line)
			for name in line:gmatch("\\addbibresource%s*%b[]%s*{([^}]+)}") do
				add_file(name)
			end
			for name in line:gmatch("\\addbibresource%s*{([^}]+)}") do
				add_file(name)
			end
		end
	end
	local function locate(item, key, name)
		local file = name and resolve(name)
		local lnum = file and index_file(file)[key]
		if lnum then
			item.filename, item.lnum = file, lnum
		else
			for _, source in ipairs(files) do
				local line = index_file(source)[key]
				if line then
					item.filename, item.lnum = source, line
					break
				end
			end
		end
		item.bufnr = 0
	end
	for _, item in ipairs(items) do
		local message = item.text
		if biber then
			local key, name = message:match("WARN %- Duplicate entry.-: '([^']+)' in file '([^']+)'")
			if key then
				locate(item, key, name)
				item.text = 'biblatex: Duplicate entry key "' .. key .. '"'
			elseif message:find("ERROR %- BibTeX subsystem") then
				local filename, lnum = message:match("(%S+%.bib).*line (%d+)")
				if not filename then
					filename, lnum = message:match("(%S+%.utf8).*line (%d+)")
				end
				-- Biber reports a temporary decoded .utf8 file. Its line numbers
				-- refer to the most recently announced bibliography source.
				local file = filename and resolve(filename)
				if not file and filename and filename:match("%.utf8$") then
					file = sources[message]
				end
				if file then
					item.bufnr, item.filename, item.lnum = 0, file, tonumber(lnum) or 0
				end
				local entry
				local index = file and index_file(file) or {}
				for candidate, line in pairs(index) do
					if line <= tonumber(lnum) and (not entry or line > index[entry]) then
						entry = candidate
					end
				end
				if entry then
					item.text = 'biblatex: Error parsing entry with key "' .. entry .. '"'
				end
			else
				key = message:match("The entry '([^']+)'.*cannot be encoded")
				if key then
					locate(item, key)
					item.text = "biblatex: Entry with key '" .. key .. "' has non-ascii characters"
				end
			end
		else
			local field, key, more = message:match("Warning%-%-empty (.-) in ([^ ;]+)(.*)")
			if key then
				locate(item, key)
				item.text = string.format('Missing "%s" in "%s"', field, key)
				if more:match("; (.+)") then
					item.text = item.text .. " (" .. more:match("; (.+)") .. ")"
				end
			else
				key = message:match('Warning%-%-entry type for "([^"]+)"')
				if key then
					locate(item, key)
					item.text = 'Entry type for "' .. key .. "\" isn't style-file defined"
				elseif message:find("I found no \\bibstyle", 1, true) then
					item.bufnr, item.filename = 0, main
					item.text = "BibTeX found no \\bibstyle command (missing \\bibliographystyle?)"
					for lnum, line in ipairs(vim.fn.readfile(main)) do
						if util.strip_comment(line):find("\\bibliography", 1, true) then
							item.lnum = lnum
							break
						end
					end
				elseif message:find("%-%-%-line %d+ of file") then
					item.text = message:match("^(.-)%-%-%-")
				end
			end
		end
		if not item.filename and (not item.bufnr or item.bufnr == 0) then
			item.filename = main
		end
	end
	return items
end

return M
