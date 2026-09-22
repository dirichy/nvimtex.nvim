local M = {}
local namespace = vim.api.nvim_create_namespace("nvimtex.math_input")
local default_punctuation = {
	"<Space>", ".", ",", ";", ":", "?", "!", "/", "`", "'", '"',
	"+", "-", "*", "=", "_", "^", "|", "(", ")", "[", "]", "{", "}", "<", ">",
	"。", "，", "；", "：", "？", "！", "、",
}

local function default_entries()
	local entries = {}
	for alias, body in pairs(require("nvimtex.snip.math").luasnip) do
		if alias ~= "" and type(body) == "string" and not body:find("<>", 1, true) then
			entries[alias] = body
		end
	end
	return entries
end

local function is_boundary(typed)
	local key = vim.fn.keytrans(typed)
	return key == "<Esc>" or key == "<CR>" or key == "<Tab>" or M.punctuation[key] == true
end

local function normalize_punctuation(source)
	local result = {}
	if source == false then
		return result
	end
	if type(source) == "string" then
		source = { source }
	end
	for key, enabled in pairs(source or default_punctuation) do
		local value = type(key) == "number" and enabled or key
		if (type(key) == "number" or enabled) and type(value) == "string" then
			result[vim.fn.keytrans(vim.api.nvim_replace_termcodes(value, true, false, true))] = true
		end
	end
	return result
end

local function match_before_cursor()
	if vim.fn.mode():sub(1, 1) ~= "i" or not M.condition() then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local col = cursor[2]
	local before = vim.api.nvim_get_current_line():sub(1, col)
	local start = before:find("[A-Za-z]+$")
	if not start or before:sub(start - 1, start - 1) == "\\" then
		return
	end

	local alias = before:sub(start)
	return alias, M.entries[alias]
end

local function replace(alias, replacement, suffix)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	suffix = suffix or ""
	vim.api.nvim_buf_set_text(0, row, col - #alias, row, col, { replacement .. suffix })
	vim.api.nvim_win_set_cursor(0, { row + 1, col - #alias + #replacement + #suffix })
end

function M.handle(_, typed)
	if typed == nil or typed == "" or not M.boundary(typed) then
		return
	end
	local alias, replacement = match_before_cursor()
	if not replacement then
		return
	end

	local translated = vim.fn.keytrans(typed)
	if translated == "<Esc>" or translated == "<CR>" or translated == "<Tab>" then
		replace(alias, replacement)
		return
	end
	replace(alias, replacement, typed)
	return ""
end

function M.commit()
	local alias, replacement = match_before_cursor()
	if not replacement then
		return false
	end
	replace(alias, replacement)
	return true
end

function M.expandable()
	local _, replacement = match_before_cursor()
	return replacement ~= nil
end

function M.setup(opts)
	opts = opts or {}
	M.entries = opts.entries or default_entries()
	M.condition = opts.condition or require("nvimtex.conditions.luasnip").in_math
	M.punctuation = normalize_punctuation(opts.punctuation)
	M.boundary = opts.boundary or is_boundary

	vim.on_key(nil, namespace)
	vim.on_key(M.handle, namespace)
	return M
end

function M.disable()
	vim.on_key(nil, namespace)
end

return M
