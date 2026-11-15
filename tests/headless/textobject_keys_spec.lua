vim.opt.runtimepath:prepend(vim.fn.getcwd())
local root = vim.fn.getcwd()
local mini_path = vim.env.NVIMTEX_MINI_AI_PATH or (vim.fn.stdpath("data") .. "/lazy/mini.ai")
local pairwise_path = vim.env.NVIMTEX_PAIRWISE_PATH or vim.fn.expand("~/pairwise.nvim")

if
	not vim.uv.fs_stat(mini_path .. "/lua/mini/ai.lua")
	or not vim.uv.fs_stat(pairwise_path .. "/lua/pairwise/textobject/init.lua")
then
	print("skip textobject key tests: set NVIMTEX_MINI_AI_PATH and NVIMTEX_PAIRWISE_PATH to installed checkouts")
	return
end

for _, backend in ipairs({ "mini.ai", "pairwise" }) do
	local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, {
		rpc = true,
		env = { NVIM_LOG_FILE = vim.fn.tempname() },
	})
	assert(child > 0, "embedded Neovim starts")
	local function lua(code, ...)
		return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
	end
	local function keys(input)
		vim.rpcrequest(child, "nvim_input", input)
		vim.wait(30)
	end
	local function fixture(marked, filetype)
		keys("<Esc>")
		local lines = vim.split(marked, "\n", { plain = true })
		local row, col
		for index, line in ipairs(lines) do
			local marker = line:find("|", 1, true)
			if marker then
				row, col = index, marker - 1
				lines[index] = line:sub(1, marker - 1) .. line:sub(marker + 1)
			end
		end
		assert(row, "fixture needs a cursor marker")
		lua(
			[[local lines,row,col,filetype=...; vim.cmd('enew!'); vim.bo.swapfile=false
            vim.api.nvim_buf_set_lines(0,0,-1,false,lines); vim.bo.filetype=filetype
            vim.api.nvim_win_set_cursor(0,{row,col})]],
			lines,
			row,
			col,
			filetype or "tex"
		)
	end
	local function expect(expected)
		local actual = assert(lua([[return {vim.api.nvim_buf_get_lines(0,0,-1,false),vim.api.nvim_get_mode().mode,
            vim.api.nvim_exec2('messages',{output=true}).output}]]))
		assert(
			vim.deep_equal(actual[1], type(expected) == "string" and { expected } or expected)
				and actual[2] == "n"
				and not actual[3]:find("E%d+:"),
			backend .. ": " .. vim.inspect(actual)
		)
	end
	local ok, err = xpcall(function()
		lua(
			[[local root,mini,pairwise,backend=...
            vim.opt.rtp:prepend(root); vim.opt.rtp:prepend(mini); vim.opt.rtp:prepend(pairwise); vim.o.more=false
            if backend=='mini.ai' then require('mini.ai').setup({silent=true})
            else require('pairwise').setup({preset={global=true},matchup=false}) end
            require('nvimtex').setup({textobject={integration=backend},input=false})]],
			root,
			mini_path,
			pairwise_path,
			backend
		)
		fixture([[\frac{a+\sqrt{|x}}{b}]])
		keys("ciaZ<Esc>")
		expect([[\frac{a+\sqrt{Z}}{b}]])
		keys("u")
		expect([[\frac{a+\sqrt{x}}{b}]])
		fixture([[\frac{a+\sqrt{|x}}{b}]])
		keys("d2aa")
		expect([[\frac{b}]])
		fixture([[$|中文+α$]])
		keys("dim")
		expect("$$")
		fixture([[\frac{|}{b}]])
		keys("ciaQ<Esc>")
		expect([[\frac{Q}{b}]])
		fixture([[\frac{|a}{b}]])
		keys('"ayia')
		expect([[\frac{a}{b}]])
		assert(lua([[return vim.fn.getreg('a')]]) == "a", backend .. " named register yank")
		fixture([[\frac{a+\sqrt{|x}}{b}]])
		keys("via")
		assert(
			lua([[return table.concat(vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.')),'\n')]]) == "x",
			backend .. " visual inner argument"
		)
		keys("aa")
		assert(
			lua([[return table.concat(vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.')),'\n')]]) == "{x}",
			backend .. " visual expands to around argument"
		)
		fixture([[\frac{|a}{b} \frac{c}{d}]])
		keys("ciaZ<Esc>")
		expect([[\frac{Z}{b} \frac{c}{d}]])
		lua([[vim.api.nvim_win_set_cursor(0,{1,19})]])
		keys(".")
		expect([[\frac{Z}{b} \frac{Z}{d}]])
		fixture("\\begin{equation}\n|x\n\\end{equation}")
		keys("die")
		expect([[\begin{equation}\end{equation}]])
		fixture([[text $\frac{|a}{b}$ tail]], "markdown")
		keys("ciaZ<Esc>")
		expect([[text $\frac{Z}{b}$ tail]])
		fixture([[\sqrt{|x}]])
		keys("cicmathrm<Esc>")
		expect([[\mathrm{x}]])
		fixture([[\frac{|a}{b}]])
		keys("cicdfrac<Esc>")
		expect([[\dfrac{a}{b}]])
		keys("dac")
		expect("")
		for _, sample in ipairs({ [[\frac{|a}{b}]], [[\frac{a}{|b}]], [[\sqrt[3]{|x}]] }) do
			fixture(sample)
			keys('"ayac')
			local source = sample:gsub("|", "")
			assert(lua([[return vim.fn.getreg('a')]]) == source, backend .. " complete command around")
			keys('"ayic')
			assert(
				lua([[return vim.fn.getreg('a')]]) == (source:find("frac", 1, true) and "frac" or "sqrt"),
				backend .. " command name from argument"
			)
		end

		fixture([[\custom[3]{a}{|b}]])
		lua([[require('nvimtex.parser').buffer_command_specs[vim.api.nvim_get_current_buf()]={
            custom={narg=2,oarg=true}}]])
		keys('"ayac')
		assert(lua([[return vim.fn.getreg('a')]]) == [[\custom[3]{a}{b}]], backend .. " nvimtex custom command parsing")
		keys("cicrenamed<Esc>")
		expect([[\renamed[3]{a}{b}]])

		fixture([[plain {a{|中文}b}]])
		keys("ciaZ<Esc>")
		expect([[plain {a{Z}b}]])
		fixture([[$x_{|ij}^2$]])
		keys("ciukl<Esc>")
		expect([[$x_{kl}^2$]])
		keys("dau")
		expect([[$x^2$]])
		fixture([[\begin{al|ign*}x\end{align*}]])
		keys('"ayia')
		assert(lua([[return vim.fn.getreg('a')]]) == "align*", backend .. " opening environment name")
		fixture([[\begin{align*}x\end{al|ign*}]])
		keys('"ayaa')
		assert(lua([[return vim.fn.getreg('a')]]) == "{align*}", backend .. " closing environment name")

		fixture([[$x_{|ij}^2$]])
		keys("ciaZ<Esc>")
		expect([[$x_{Z}^2$]])
		keys("daa")
		expect([[$x_^2$]])
		fixture([[$x_|i$]])
		keys("dia")
		expect([[$x_i$]])
		keys("ciuj<Esc>")
		expect([[$x_j$]])
		fixture([[$x^\al|pha$]])
		keys("daa")
		expect([[$x^\alpha$]])
		keys('"ayiu')
		assert(lua([[return vim.fn.getreg('a')]]) == [[\alpha]], backend .. " bare scripts remain available through u")
		fixture([[\sqrt |x]])
		keys("daa")
		expect([[\sqrt x]])

		fixture([[$\left( |x \right)$]])
		keys('"ayad')
		assert(lua([[return vim.fn.getreg('a')]]) == [[\left( x \right)]], backend .. " sized delimiters around")
		keys("cidZ<Esc>")
		expect([[$\left(Z\right)$]])
		fixture("\\section{A}\n|first\n\n\\section{B}\nsecond")
		keys("daS")
		expect({ [[\section{B}]], "second" })
		fixture("\\section{A}\nfirst\n\\subsection{B}\n|second\n\\section{C}\nthird")
		keys("ciSQ<Esc>")
		expect({ [[\section{A}]], "first", [[\subsection{B}]], "Q", [[\section{C}]], "third" })
		fixture("\\begin{itemize}\n  \\item[label] |first\n  \\item second\n\\end{itemize}")
		keys("ciiQ<Esc>")
		expect({ [[\begin{itemize}]], [[  \item[label] Q]], [[  \item second]], [[\end{itemize}]] })
		keys("dai")
		expect({ [[\begin{itemize}]], [[  \item second]], [[\end{itemize}]] })
		fixture("\\section{Only}\n|body")
		keys("daS")
		expect("")

		fixture("|first. Second.")
		keys('"ayis')
		assert(lua([[return vim.fn.getreg('a')]]) == "first.", backend .. " native sentence is retained")

		if backend == "pairwise" then
			fixture([[\sqrt[3]{|中文+α}]])
			keys("dsc")
			expect("中文+α")
			keys("u")
			expect([[\sqrt[3]{中文+α}]])
			fixture([[\sqrt{|x}]])
			keys("csc(")
			expect("(x)")
			fixture("|hello")
			keys("ysiwcmathrm<CR>")
			expect([[\mathrm{hello}]])
			fixture([[\sqrt{|x} \sqrt{y}]])
			keys("csccmathrm<CR>")
			expect([[\mathrm{x} \sqrt{y}]])
			lua([[vim.api.nvim_win_set_cursor(0,{1,18})]])
			keys(".")
			expect([[\mathrm{x} \mathrm{y}]])
			keys("u")
			expect([[\mathrm{x} \sqrt{y}]])
			fixture([[\sqrt{|x}]])
			keys("csccfrac<CR>")
			expect([[\sqrt{x}]])
			fixture([[\sqrt{|x}]])
			keys("cscc<Esc>")
			expect([[\sqrt{x}]])
			fixture([[\frac{|a}{b}]])
			keys("dsc")
			expect([[\frac{a}{b}]])
			fixture([[\mathrm{\sqrt{|x}}]])
			keys("2dsc")
			expect([[\sqrt{x}]])
			fixture([[(\mathrm{\sqrt{|x}})]])
			lua([[require('pairwise.api').register_group({key='q',buffer=true,pairs={'nvimtex.c','('}})]])
			keys('"ay2aq')
			assert(lua([[return vim.fn.getreg('a')]]) == [[\mathrm{\sqrt{x}}]], "group merges nvimtex wrapper layers")

			fixture([[$\left( |x \right)$]])
			keys("dsd")
			expect("$ x $")
			fixture("|hello")
			keys("ysiwd")
			expect([[\left(hello\right)]])

			fixture([[$|中文+α$]])
			keys("dsm")
			expect("中文+α")
			fixture([=[\[|x+α\]]=])
			keys("csmg")
			expect("{x+α}")
			fixture([[{|hello}]])
			keys("dsg")
			expect("hello")
			fixture("|hello")
			keys("ysiwm")
			expect("$hello$")
			fixture([[\begin{align}|x\end{align}]])
			keys("cseeequation<CR>")
			expect([[\begin{equation}x\end{equation}]])
			keys("u")
			expect([[\begin{align}x\end{align}]])
			fixture([[\begin{align}|x\end{align}]])
			keys("csee<Esc>")
			expect([[\begin{align}x\end{align}]])
			fixture("\\begin{align}\n|x\n\\end{align}")
			keys("dse")
			expect({ "", "x", "" })
			fixture("|hello")
			keys("ysiwequote<CR>")
			expect([[\begin{quote}hello\end{quote}]])

			fixture([[text $\sqrt{|x}$ tail]], "markdown")
			keys("dsc")
			expect("text $x$ tail")
		end

		fixture("plain |text")
		keys("dim")
		expect("plain text")
		lua([[vim.cmd('enew!'); vim.bo.filetype='lua']])
		assert(
			lua([[for _,map in ipairs(vim.api.nvim_buf_get_keymap(0,'o')) do
            if map.desc and map.desc:find('LaTeX',1,true) then return false end end
            return vim.b.miniai_config==nil]]),
			backend .. " ignores unrelated filetypes"
		)
	end, debug.traceback)
	vim.fn.jobstop(child)
	assert(ok, err)
	print("ok " .. backend .. " native operations, count, Visual expansion, empty ranges, registers, Undo, and repeat")
end
