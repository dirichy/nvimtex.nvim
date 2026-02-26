---@alias Nvimtex.Consumer fun(lnode:Nvimtex.LNode,field:string,source:number|string):Nvimtex.Consumer.feedback,Nvimtex.Consumer|Nvimtex.LNode.withfield|Nvimtex.Consumer.result.residual|nil
local M = {}
local LNode = require("nvimtex.parser.lnode")
---@enum Nvimtex.Consumer.feedback
M.feedback = {
	continue = 0,
	subconsumer = 1,
	finish = 2,
	residual = 3,
}
---@enum Nvimtex.Consumer.creater.feedback
M.creater_feedback = {
	success = 0,
	noneed = 1,
	multi = 2,
	residual = 3,
}

function M.if_statement(begin_node, result_field)
	local result_node = LNode:new("if_statement")
	local if_node = LNode:new(begin_node:child(0))
	if_node._type = "if"
	result_node:add_child(if_node, "if")
	result_node:set_start(begin_node)
	---@type Nvimtex.LNode?
	local block
	local _else = false
	---@param node Nvimtex.LNode
	return M.creater_feedback.success,
		function(node, field, source)
			if not block then
				local t = _else and "else_block" or "if_block"
				block = LNode:new(t)
				block:add_child(node, field)
				block:set_start(node)
				result_node:add_child(block, t)
				return M.feedback.continue
			end
			local ntype = node:type()
			if ntype ~= "generic_command" then
				block:add_child(node, field)
				return M.feedback.continue
			end
			local command_name = vim.treesitter.get_node_text(node:child(0), source):sub(2, -1)
			if command_name == "else" then
				block:set_end()
				block = nil
				_else = true
				local elsenode = LNode:new(begin_node:child(0))
				elsenode._type = "else"
				result_node:add_child(elsenode, "else")
				return M.feedback.continue
			elseif command_name == "fi" then
				block:set_end()
				local fi_node = LNode:new(begin_node:child(0))
				fi_node._type = "if"
				result_node:add_child(fi_node, "fi")
				result_node:set_end(node)
				return M.feedback.finish, { result_node, result_field }
			else
				block:add_child(node, field)
				return M.feedback.continue
			end
		end
end

--- create a consumer to eat node until find a node with type in `until_type`
---@param until_type string|string[]
---@param begin_node Nvimtex.LNode first node to feed to the consumer
---@param begin_field string? field of first node
---@param result_type string type of result node
---@param result_field string? field of result node
---@return Nvimtex.Consumer.creater.feedback, Nvimtex.Consumer|Nvimtex.LNode.withfield|table|nil
function M.until_node_type(until_type, begin_node, begin_field, result_type, result_field)
	local result_node = LNode:new(result_type)
	result_node:add_child(begin_node, begin_field)
	result_node:set_start(begin_node)
	if type(until_type) == "string" then
		until_type = { until_type }
	end
	for key, value in pairs(until_type) do
		until_type[value] = true
	end
	return M.creater_feedback.success,
		function(lnode, field, source)
			if not lnode then
				result_node:set_end()
				return M.feedback.finish, { result_node, result_field }
			end
			result_node:add_child(lnode, field)
			if until_type[lnode:type()] then
				result_node:set_end(lnode)
				return M.feedback.finish, { result_node, result_field }
			end
			return M.feedback.continue
		end
end

--- create a consumer to parse a generic_command
---@param generic_command_node Nvimtex.LNode first node to feed to the consumer
---@param oarg boolean
---@param narg integer
---@param result_field string? field of result node
---@return Nvimtex.Consumer.creater.feedback, Nvimtex.Consumer|Nvimtex.LNode.withfield|table|nil
function M.generic_command(generic_command_node, oarg, narg, result_field)
	narg = narg or 0
	local original_arg_nodes = generic_command_node:field("arg")
	local result
	local cur_narg = 0
	if #original_arg_nodes > 0 then
		oarg = false
		if #original_arg_nodes == narg then
			return M.creater_feedback.noneed
		end
		if #original_arg_nodes > narg then
			result = LNode:new("generic_command")
			result:set_range(generic_command_node)
			local iter = generic_command_node:iter_children()
			for node, field in iter do
				result:add_child(node, field)
				if field == "arg" then
					cur_narg = cur_narg + 1
				end
				if cur_narg >= narg then
					result:set_end(node)
					return M.creater_feedback.residual, { finish = { result, result_field }, residual = iter }
				end
			end
		end
	end
	result = LNode:new(generic_command_node)
	cur_narg = #original_arg_nodes
	return M.creater_feedback.success,
		function(lnode, field, source)
			if not lnode then
				result:set_end()
				return M.feedback.finish, { result, result_field }
			end
			if oarg then
				if lnode:type() == "[" then
					local feed, con = M.until_node_type("]", lnode, nil, "brack_group", "optional_arg")
					return M.feedback.subconsumer, con
				elseif lnode:type() == "brack_group" then
					oarg = false
					result:add_child(lnode, "optional_arg")
					if narg == 0 then
						result:set_end(lnode)
						return M.feedback.finish, { result, result_field }
					end
					return M.feedback.continue
				else
					oarg = false
				end
			end
			if lnode:type() == "word" then
				local a, b, x, c, d, y = lnode:range(true)
				local arg_node
				while d - b > 0 and cur_narg < narg do
					arg_node = LNode:new(lnode)
					arg_node:set_range(a, b, x, a, b + 1, x + 1)
					result:add_child(arg_node, "arg")
					cur_narg = cur_narg + 1
					b = b + 1
					x = x + 1
				end
				if cur_narg >= narg then
					result:set_end(arg_node)
					if d - b > 0 then
						arg_node = LNode:new(lnode)
						arg_node:set_range(a, b, x, c, d, y)
						return M.feedback.residual,
							{ finish = { result, result_field }, residual = { { arg_node, field } } }
					else
						return M.feedback.finish, { result, result_field }
					end
				else
					return M.feedback.continue
				end
			else
				result:add_child(lnode, "arg")
				cur_narg = cur_narg + 1
				if cur_narg >= narg then
					result:set_end(lnode)
					return M.feedback.finish, { result, result_field }
				end
				return M.feedback.continue
			end
		end
end

return M
