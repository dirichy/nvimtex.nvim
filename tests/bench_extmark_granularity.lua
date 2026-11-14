vim.opt.swapfile = false
vim.opt.conceallevel = 2
vim.opt.concealcursor = "nvic"

local uv = vim.uv or vim.loop
local api = vim.api
local ns = api.nvim_create_namespace("nvimtex.extmark_granularity_bench")

local command_count = tonumber(vim.env.NVIMTEX_EXTMARK_COMMANDS) or 1000
local atom_count = tonumber(vim.env.NVIMTEX_EXTMARK_ATOMS) or 20
local setup_rounds = tonumber(vim.env.NVIMTEX_EXTMARK_SETUP_ROUNDS) or 9
local redraw_rounds = tonumber(vim.env.NVIMTEX_EXTMARK_REDRAW_ROUNDS) or 100

local source_text = string.rep("x", atom_count)
local lines = {}
for index = 1, command_count do
	lines[index] = source_text
end
api.nvim_buf_set_lines(0, 0, -1, false, lines)
api.nvim_win_set_height(0, math.min(command_count, 40))
api.nvim_win_set_cursor(0, { math.max(math.floor(command_count / 2), 1), 0 })
vim.cmd("normal! zz")

local highlights = {
	"DiagnosticError",
	"DiagnosticWarn",
	"DiagnosticInfo",
	"DiagnosticHint",
}

local function big_extmarks()
	local atoms = {}
	for column = 1, atom_count do
		atoms[column] = { "y", highlights[(column - 1) % #highlights + 1] }
	end
	for row = 0, command_count - 1 do
		api.nvim_buf_set_extmark(0, ns, row, 0, {
			end_row = row,
			end_col = atom_count,
			conceal = "",
			virt_text = atoms,
			virt_text_pos = "inline",
			undo_restore = false,
			invalidate = true,
		})
	end
end

local function small_extmarks()
	for row = 0, command_count - 1 do
		for column = 0, atom_count - 1 do
			api.nvim_buf_set_extmark(0, ns, row, column, {
				end_row = row,
				end_col = column + 1,
				conceal = "",
				virt_text = { { "y", highlights[column % #highlights + 1] } },
				virt_text_pos = "inline",
				undo_restore = false,
				invalidate = true,
			})
		end
	end
end

local function median(samples)
	table.sort(samples)
	return samples[math.ceil(#samples / 2)]
end

local function measure_setup(name, setup)
	local samples = {}
	for round = 1, setup_rounds do
		api.nvim_buf_clear_namespace(0, ns, 0, -1)
		collectgarbage("collect")
		local started = uv.hrtime()
		setup()
		samples[round] = (uv.hrtime() - started) / 1e6
	end
	local count = #api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
	print(string.format("setup  %-8s median=%9.3f ms  extmarks=%d", name, median(samples), count))
end

local function measure_clear(name, setup)
	local samples = {}
	for round = 1, setup_rounds do
		api.nvim_buf_clear_namespace(0, ns, 0, -1)
		setup()
		local started = uv.hrtime()
		api.nvim_buf_clear_namespace(0, ns, 0, -1)
		samples[round] = (uv.hrtime() - started) / 1e6
	end
	print(string.format("clear  %-8s median=%9.3f ms", name, median(samples)))
end

local function measure_redraw(name, setup)
	api.nvim_buf_clear_namespace(0, ns, 0, -1)
	setup()
	vim.cmd("redraw!")
	local samples = {}
	for round = 1, redraw_rounds do
		local started = uv.hrtime()
		vim.cmd("redraw!")
		samples[round] = (uv.hrtime() - started) / 1e6
	end
	print(
		string.format(
			"redraw %-8s median=%9.3f ms  visible-lines=%d",
			name,
			median(samples),
			vim.fn.line("w$") - vim.fn.line("w0") + 1
		)
	)
end

print(string.format("commands=%d atoms/command=%d", command_count, atom_count))
measure_setup("1x20", big_extmarks)
measure_setup("20x1", small_extmarks)
measure_clear("1x20", big_extmarks)
measure_clear("20x1", small_extmarks)
measure_redraw("1x20", big_extmarks)
measure_redraw("20x1", small_extmarks)
api.nvim_buf_clear_namespace(0, ns, 0, -1)
