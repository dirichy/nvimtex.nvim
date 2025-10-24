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
			local k, v = string.match(line, "^%%![Tt][Ee][Xx]%s*(%a*)%s*=%s*(%a*)%s*$")
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
M.get_documentclass = function(subfile_find_root, buffer) end
return M
