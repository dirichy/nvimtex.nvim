-- LaTeX message handling and path recovery adapted from VimTeX (MIT).
-- Copyright (c) 2025 Karl Yngve Lervåg. See LICENSES/VimTeX.txt.
local util = require("nvimtex.util")
---@class nvimtex.compile.LogEntry: vim.quickfix.entry
---@field text string
---@field type string
---@field lnum integer
---@field bufnr integer
local M = {}
local indented_packages = {
	biblatex = true,
	babel = true,
	hyperref = true,
	scrreprt = true,
	fixltx2e = true,
	titlesec = true,
	silence = true,
}

---@param kind string
---@param text string
---@param file string
---@param lnum? integer
---@return nvimtex.compile.LogEntry
function M.entry(kind, text, file, lnum)
	return { type = kind, text = text, filename = file, lnum = lnum or 0, col = 0, bufnr = 0, valid = 1 }
end

-- Box warnings can follow the closing ')' of an input file. Keep VimTeX's
-- backward parenthesis heuristic rather than assigning the current stack top.
local function box_source(lines, index, root, paths)
	local level, file = 1, nil
	for i = index - 1, 2, -1 do
		if paths[i] then
			file = paths[i]
			break
		end
		local _, closes = lines[i]:gsub("%)", "")
		local _, opens = lines[i]:gsub("%(", "")
		level = level + closes - opens
		if i == index - 1 or level <= 0 then
			local name = lines[i]:match("%(([^%s()]+)%)?%s*%[?%d*%]?%s*$")
			if name then
				file = util.normalize_file(name, { cwd = root })
				break
			end
		end
	end
	if file and vim.fn.filereadable(file) == 1 then
		paths[index] = file
		return vim.fn.fnamemodify(file, ":.")
	end
end

---@param main string Absolute main TeX path.
---@param logfile string Absolute log path.
---@return nvimtex.compile.LogEntry[]
function M.latex(main, logfile)
	local lines = vim.fn.readfile(logfile)
	local root = vim.fs.dirname(main)
	local local_root = root == vim.fn.getcwd()
	local items, paths = {}, {}
	-- Only adjacent recognized continuation lines belong to a message. An
	-- ordinary log line closes it, so later source excerpts cannot leak in.
	---@type nvimtex.compile.LogEntry?
	local current
	local package_name
	for index, line in ipairs(lines) do
		local first = line:sub(1, 1)
		local kind, message, file, row, package_start
		-- Most tracing lines have no ': '. Test that cheaply before matching
		-- arbitrary file:line paths, including spaces and drive letters.
		if line:find(": ", 1, true) then
			local number
			file, number, message = line:match("^(.-):(%d+): (.+)$")
			if file then
				kind, row = "E", tonumber(number)
				message = message:gsub("^ ==> ", "")
				file = local_root and file or util.normalize_file(file, { cwd = root })
			end
		end
		if kind then
			-- An explicit location starts a new message, even after a runaway.
		elseif first == "!" then
			if line == "! Emergency stop." then
				kind, message = "E", "Emergency stop (fatal error)!"
			elseif line:sub(1, 14) == "! LaTeX Error:" then
				kind, message = "E", line:sub(16)
			elseif line:sub(1, 15) == "!pdfTeX error: " then
				kind, message = "E", line:sub(16)
			elseif current and current.type == "E" then
				current.text = current.text .. "\n" .. line:sub(3)
			else
				current = nil
			end
		elseif line == "Runaway argument?" then
			kind, message = "E", line
		elseif first == "P" or first == "L" or first == "C" then
			package_start = line:match("^Package (%S+) [Ww]arning:") or line:match("^Class (%S+) [Ww]arning:")
			if package_start or line:match("^LaTeX .-[Ww]arning:") or line:match("^Class .-[Ww]arning:") then
				kind, message = "W", line
				row = tonumber(line:match(".*line (%d+)"))
			else
				current = nil
			end
		elseif first == "O" or first == "U" then
			if line:match("^Overfull \\[hv]box") or line:match("^Underfull \\[hv]box") then
				kind, message = "W", line
				row = tonumber(line:match("lines? (%d+)"))
				file = box_source(lines, index, root, paths)
			else
				current = nil
			end
		elseif line:sub(1, 19) == "Missing character: " then
			kind, message = "W", line
		elseif first == "(" and current and current.type == "W" then
			local marker, rest = line:match("^%(([^)]+)%)(.*)$")
			local number = tonumber(line:match("on input line (%d+)%.$"))
			local finished = false
			if marker == "Font" and current.text:match("^LaTeX Font Warning:") then
				current.text = current.text .. "\n" .. rest:gsub("^%s+", "")
			elseif marker and marker == package_name then
				local ignored = marker == "biblatex"
					and (rest:find("in t", 1, true) or rest:find("Please v", 1, true) or rest:find("LaTeX a", 1, true))
				if marker == "babel" and number then
					finished = true
				elseif not ignored then
					current.text = current.text .. "\n" .. (indented_packages[marker] and rest or rest:gsub("^ ", ""))
					finished = number ~= nil and not indented_packages[marker]
				end
			else
				current = nil
			end
			if current and current.lnum == 0 then
				current.lnum = number or 0
			end
			if finished then
				current = nil
			end
		elseif
			first == " "
			and current
			and current.type == "W"
			and line:match("^               .+on input line %d+%.")
		then
			current.text = current.text .. "\n" .. line:gsub("^%s+", "")
			if current.lnum == 0 then
				current.lnum = tonumber(line:match("on input line (%d+)%.")) or 0
			end
		elseif first == "l" and current and current.type == "E" then
			local number, excerpt = line:match("^l%.(%d+) (.+)$")
			if number then
				if current.lnum == 0 then
					current.lnum = tonumber(number) or 0
				end
				current.text = current.text .. "\n" .. excerpt
			else
				current = nil
			end
		elseif first == "{" and current and current.type == "E" and line:sub(1, 2) ~= "{/" then
			current.text = current.text .. "\n" .. line
		elseif line:sub(1, 11) == "<argument> " and current and current.type == "E" then
			current.text = current.text .. "\n" .. line:sub(12)
			current = nil
		else
			current = nil
		end
		if kind then
			current = M.entry(kind, message or line, file or main, row)
			package_name = package_start
			items[#items + 1] = current
		end
	end
	for _, item in ipairs(items) do
		if item.lnum > 0 then
			item.text = item.text:gsub("%s*on input line %d+%.$", "")
		end
	end
	return items
end

return M
