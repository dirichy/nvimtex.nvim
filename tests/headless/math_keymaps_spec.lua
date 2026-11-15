local root = vim.fn.getcwd()
local keyflow_path = vim.env.NVIMTEX_KEYFLOW_PATH or vim.fn.expand("~/keyflow.nvim")
local cases = {
	{ name = "default", opts = {} },
	{ name = "disabled", opts = false },
	{ name = "custom", opts = { keymaps = { upgrade_math = "g+", downgrade_math = false } } },
	{ name = "keyflow", opts = { keyflow = true } },
}

for _, case in ipairs(cases) do
	if case.name == "keyflow" and not vim.uv.fs_stat(keyflow_path .. "/lua/keyflow/init.lua") then
		print("skip optional keyflow test: set NVIMTEX_KEYFLOW_PATH to an installed checkout")
	else
		local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, {
			rpc = true,
			env = { NVIM_LOG_FILE = vim.fn.tempname() },
		})
		assert(child > 0)
		local function lua(code, ...)
			return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
		end
		local function keys(input)
			vim.rpcrequest(child, "nvim_input", input)
			vim.wait(30)
		end
		local function fixture(source, filetype)
			lua(
				[[local source,ft=...; vim.cmd('enew!'); vim.bo.swapfile=false
                vim.api.nvim_buf_set_lines(0,0,-1,false,vim.split(source,'\n',{plain=true}))
                vim.bo.filetype=ft; vim.api.nvim_win_set_cursor(0,{1,1})]],
				source or "$a=b$",
				filetype or "tex"
			)
		end
		local function expect(lines)
			local actual = assert(lua([[return {vim.api.nvim_buf_get_lines(0,0,-1,false),vim.api.nvim_get_mode().mode,
                vim.api.nvim_exec2('messages',{output=true}).output}]]))
			assert(
				vim.deep_equal(actual[1], lines) and actual[2] == "n" and not actual[3]:find("E%d+:"),
				case.name .. ": " .. vim.inspect(actual)
			)
		end
		local function mapped(lhs)
			return lua([[local map=vim.fn.maparg(...,'n',false,true); return map.buffer==1]], lhs)
		end
		local ok, err = xpcall(function()
			lua(
				[[local root,keyflow=...; vim.opt.rtp:prepend(root); vim.opt.rtp:prepend(keyflow); vim.o.more=false]],
				root,
				keyflow_path
			)
			-- Buffers already open at setup time also receive the default mappings.
			fixture()
			lua([[require('nvimtex').setup({surround=...,input=false,textobject=false})]], case.opts)
			assert(lua([[return package.loaded.keyflow~=nil]]) == (case.name == "keyflow"), "keyflow is opt-in")
			if case.name == "disabled" then
				assert(not mapped("m<C-a>") and not mapped("m<C-x>"))
				fixture()
				assert(not mapped("m<C-a>"), "disabled setup creates no FileType mappings")
			elseif case.name == "custom" then
				assert(mapped("g+") and not mapped("m<C-a>") and not mapped("m<C-x>"))
				keys("g+")
				expect({ "\\[", "a=b", "\\]" })
			elseif case.name == "default" then
				assert(mapped("m<C-a>") and mapped("m<C-x>"))
				keys("m<C-a>")
				expect({ "\\[", "a=b", "\\]" })
				keys("m<C-a>")
				expect({ "\\begin{equation}", "a=b", "\\end{equation}" })
				keys("u")
				expect({ "\\[", "a=b", "\\]" })
				fixture()
				keys("2m<C-a>")
				expect({ "\\begin{equation}", "a=b", "\\end{equation}" })
				keys("m<C-x>")
				expect({ "\\[", "a=b", "\\]" })
				fixture("text $a=b$ tail", "markdown")
				lua([[vim.api.nvim_win_set_cursor(0,{1,6})]])
				keys("m<C-a>")
				expect({ "text \\[", "a=b", "\\] tail" })
				assert(lua([[return package.loaded.keyflow==nil]]), "normal mappings never load keyflow")
				fixture("$a=b$ 12")
				lua([[vim.api.nvim_win_set_cursor(0,{1,7})]])
				keys("<C-a>")
				expect({ "$a=b$ 13" })
			else
				keys("m<C-a><C-a><Esc>")
				expect({ "\\begin{equation}", "a=b", "\\end{equation}" })
				assert(lua([[return require('keyflow').active()==nil]]), "Escape exits the exclusive mode")
				fixture()
				keys("m<C-a>2<C-a><Esc>")
				expect({ "\\begin{equation}\\begin{aligned}", "a&= b", "\\end{aligned}\\end{equation}" })
				fixture()
				keys("m<C-a><C-a><C-x>l")
				expect({ "\\[", "a=b", "\\]" })
				assert(lua([[return require('keyflow').active()==nil]]), "foreign keys exit and pass through")
				fixture("plain text")
				keys("m<C-a>")
				expect({ "plain text" })
				assert(lua([[return require('keyflow').active()==nil]]), "failed conversion exits keyflow")
			end
			fixture("plain text", "lua")
			assert(not mapped("m<C-a>") and not mapped("m<C-x>") and not mapped("g+"), "other filetypes are unaffected")
		end, debug.traceback)
		vim.fn.jobstop(child)
		assert(ok, err)
		print("ok math mappings " .. case.name)
	end
end
