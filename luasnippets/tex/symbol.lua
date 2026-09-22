local ls = require("luasnip")
local s, i = ls.snippet, ls.insert_node
local fmta = require("luasnip.extras.fmt").fmta
local tex = require("nvimtex.conditions.luasnip")

local function template_nodes(body)
	local nodes = {}
	for _ in body:gmatch("<>") do
		local index = #nodes + 1
		nodes[index] = i(index)
	end
	return fmta(body, nodes)
end

local function condition(line_to_cursor, matched_trigger)
	local prefix_length = #line_to_cursor - #matched_trigger
	if prefix_length > 0 then
		local byte = line_to_cursor:byte(prefix_length)
		local is_letter = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
		if byte == 92 or is_letter then
			return false
		end
	end
	return tex.in_math()
end

local snippets = {}
for alias, body in pairs(require("nvimtex.snip.math").luasnip) do
	if alias ~= "" and type(body) == "string" and body:find("<>", 1, true) then
		snippets[#snippets + 1] = s({
			trig = alias,
			wordTrig = false,
			priority = 500,
			hidden = true,
			snippetType = "autosnippet",
		}, template_nodes(body), { condition = condition })
	end
end

return snippets
