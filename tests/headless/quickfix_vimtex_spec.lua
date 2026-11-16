-- Optional: run VimTeX's original assertions against nvimtex's replacement.
local repo = vim.env.NVIMTEX_PATH or vim.fn.getcwd()
local reference = vim.env.VIMTEX_PATH or repo .. "/.dev/vimtex"
vim.opt.runtimepath:prepend(repo)
vim.opt.runtimepath:append(reference)
vim.cmd("runtime autoload/vimtex/qf.vim")
vim.cmd([[
function! vimtex#qf#setqflist(...) abort
  let opts = {'path': expand('%:p'), 'open': v:false, 'ignore': get(g:, 'vimtex_quickfix_ignore_filters', [])}
  call luaeval('require("nvimtex.compile.quickfix").show(_A)', opts)
endfunction
]])
vim.cmd.cd(reference .. "/test/" .. vim.env.QF_TEST_DIR)
vim.cmd.source(vim.env.QF_TEST)
