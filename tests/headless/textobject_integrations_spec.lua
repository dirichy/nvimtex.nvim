vim.opt.runtimepath:prepend(vim.fn.getcwd())
local mini_path = vim.env.NVIMTEX_MINI_AI_PATH or (vim.fn.stdpath("data") .. "/lazy/mini.ai")
local pairwise_path = vim.env.NVIMTEX_PAIRWISE_PATH or vim.fn.expand("~/pairwise.nvim")
if
	not vim.uv.fs_stat(mini_path .. "/lua/mini/ai.lua")
	or not vim.uv.fs_stat(pairwise_path .. "/lua/pairwise/textobject/init.lua")
then
	print("skip textobject integrations: set NVIMTEX_MINI_AI_PATH and NVIMTEX_PAIRWISE_PATH to installed checkouts")
	return
end
vim.opt.runtimepath:prepend(mini_path)
vim.opt.runtimepath:prepend(pairwise_path)

local function eq(actual, expected, label)
	assert(
		vim.deep_equal(actual, expected),
		label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
	)
end
local mini = require("mini.ai")
mini.setup({ silent = true })
local mini_adapter = require("nvimtex.textobject.integrations.mini_ai")
local pairwise_adapter = require("nvimtex.textobject.integrations.pairwise")

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(bufnr)
vim.bo[bufnr].filetype = "tex"
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { [[\frac{a+\sqrt{x}}{b}]] })
vim.api.nvim_win_set_cursor(0, { 1, 14 })
vim.b[bufnr].miniai_config = { n_lines = 7, custom_textobjects = {
	z = function()
		return nil
	end,
} }
assert(mini_adapter.setup_buf(bufnr))
eq(vim.b[bufnr].miniai_config.n_lines, 7, "MiniAi buffer options are retained")
assert(vim.b[bufnr].miniai_config.custom_textobjects.z, "other MiniAi custom objects are retained")
local opts = { reference_region = { from = { line = 1, col = 15 } }, n_times = 1 }
local inside = assert(mini.find_textobject("i", "a", opts))
eq(inside, { from = { line = 1, col = 15 }, to = { line = 1, col = 15 } }, "MiniAi inside argument")
local around = assert(mini.find_textobject("a", "a", opts))
eq(around, { from = { line = 1, col = 14 }, to = { line = 1, col = 16 } }, "MiniAi around argument")
opts.n_times = 2
eq(mini.find_textobject("i", "a", opts), { from = { line = 1, col = 7 }, to = { line = 1, col = 16 } }, "MiniAi count")
opts.n_times, opts.reference_region = 1, around
eq(
	mini.find_textobject("i", "a", opts),
	{ from = { line = 1, col = 7 }, to = { line = 1, col = 16 } },
	"MiniAi reference expansion"
)

local pairwise_context = require("pairwise.textobject.context")
local ctx = pairwise_context.new({ bufnr = bufnr, row = 0, col = 14, inner = true })
local bounds = assert(pairwise_adapter.objects.a(ctx))
eq(bounds.inner_start, { 0, 14 }, "Pairwise inside start")
eq(bounds.inner_end, { 0, 15 }, "Pairwise inside end")
assert(pairwise_adapter.setup_buf(bufnr))
eq(vim.api.nvim_buf_get_keymap(bufnr, "o"), {}, "integration uses registration, not custom mappings")
local registry = require("pairwise.pair.registry")
local selected = assert(registry.by_key(ctx, "c", "textobject"))
local wrapper = assert(registry.by_key(ctx, "c", "surround"))
eq(selected.find, pairwise_adapter.objects.c, "textobject finder is registered through the API")
eq(wrapper.find, pairwise_adapter.pairs.c, "surround finder is independent")

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { [[\frac{αβ}{c}]] })
opts.reference_region = { from = { line = 1, col = 7 } }
local unicode = assert(mini.find_textobject("i", "a", opts))
eq(unicode.to.col, 10, "MiniAi endpoint includes the complete UTF-8 argument")
opts.reference_region = { from = { line = 1, col = 7 }, to = { line = 1, col = 9 } }
eq(mini.find_textobject("i", "a", opts), nil, "UTF-8 Visual reference includes its final codepoint")

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { [[\begin{equation}]], "x", [[\end{equation}]] })
opts.reference_region = { from = { line = 2, col = 1 } }
eq(
	mini.find_textobject("i", "e", opts),
	{ from = { line = 1, col = 17 }, to = { line = 2, col = 2 } },
	"MiniAi multiline newline endpoints"
)

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { [[\frac{}{b}]] })
opts.reference_region = { from = { line = 1, col = 6 } }
eq(mini.find_textobject("i", "a", opts), { from = { line = 1, col = 7 } }, "MiniAi empty argument")
print("ok real MiniAi and Pairwise textobject adapters")
