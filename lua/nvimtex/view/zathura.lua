local util = require("nvimtex.util")
local default_args = function(path)
	path = path or vim.fn.expand("%:p")
	local jobname = string.match(path, "([^/]*)%.tex$")
	local cwd = string.match(path, "(.*)/[^/]*%.tex$")
	local args = { cwd .. "/" .. jobname .. ".pdf" }
	local command = "zathura"
	return { command = command, cwd = cwd, args = args }
end
local Job = require("plenary.job")
local function zathura(args)
	local path
	if util.get_magic_comment("root") then
		path = vim.fn.expand("%:p:h") .. "/" .. util.get_magic_comment("root")
		path = vim.fs.normalize(path)
	end
	local opts = vim.tbl_deep_extend("force", default_args(path), args or {})
	Job:new({
		command = "which",
		args = { "zathura" },
		on_exit = function(j, return_value)
			local zathura_path = j:result()[1]
			Job:new({
				command = "ps",
				args = { "-e" },
				on_exit = function(jj, rr)
					local pid = nil
					for _, line in ipairs(jj:result()) do
						if string.match(line, "zathura") then
							if string.match(line, opts.args[1]) then
								pid = string.match(line, "^[0-9]*")
								break
							end
						end
					end
					if not pid then
						Job:new(opts):start()
					else
						Job:new({
							command = "osascript",
							args = {
								"-e",
								[=[tell application "System Events"
      set frontmost of the first process whose unix id is ]=] .. pid .. [=[ to true
    end tell
  ]=],
							},
						}):start()
					end
				end,
			}):start()
		end,
	}):start()
end
return zathura
