local core = require("nvimtex.textobject.core")
local M = {}

-- A completed AST query publishes its counted layers through the finder session.
-- No Pairwise modules are needed beyond its public registration API.
---@param session? Pairwise.FindSession
---@return (fun(pair:Nvimtex.Textobject.Pair))?
local function recorder(session)
	if session then
		return function(pair)
			session.matches[#session.matches + 1] = pair
		end
	end
end

---@type table<Nvimtex.Textobject.Id,Pairwise.PairFinder>
M.objects = {}
for _, id in ipairs(core.ids) do
	M.objects[id] = function(ctx, session)
		return core.find_bounds(id, {
			bufnr = ctx.bufnr,
			reference = ctx.reference,
			inner = ctx.inner,
			count = ctx.count,
		}, recorder(session))
	end
end

---@type Pairwise.Add
local function add_command(ctx)
	local ok, name = pcall(vim.fn.input, "Command: ")
	if not ok then
		return nil
	end
	name = name:gsub("^\\", "")
	if not name:match("^[%a@]+%*?$") or name == "begin" or name == "end" then
		return nil
	end
	local spec = require("nvimtex.parser").command_spec(name, ctx.bufnr)
	if spec and (spec.parse or spec.narg ~= 1) then
		return nil
	end
	return { "\\" .. name .. "{", "}" }
end

---@type Pairwise.Add
local function add_environment()
	local ok, name = pcall(vim.fn.input, "Environment: ")
	if not ok or not name:match("^[%a][%w@_*%-]*$") then
		return nil
	end
	return { "\\begin{" .. name .. "}", "\\end{" .. name .. "}" }
end

local additions = { c = add_command, m = { "$", "$" }, e = add_environment, g = { "{", "}" } }
---@type table<Nvimtex.Textobject.Id,Pairwise.PairFinder>
M.pairs = {}
for id in pairs(additions) do
	M.pairs[id] = function(ctx, session)
		return core.find_pair(id, {
			bufnr = ctx.bufnr,
			reference = ctx.reference,
			inner = ctx.inner,
			count = ctx.count,
		}, recorder(session))
	end
end

---@param bufnr integer
---@return boolean installed
function M.setup_buf(bufnr)
	local ok, api = pcall(require, "pairwise.api")
	if not ok then
		return false
	end
	for _, id in ipairs(core.ids) do
		api.register({
			id = "nvimtex." .. id,
			key = id,
			buffer = bufnr,
			override = true,
			textobject = { find = M.objects[id] },
			surround = M.pairs[id] and { find = M.pairs[id] } or false,
			add = additions[id],
			autopair = false,
			matchup = false,
		})
	end
	return true
end

return M
