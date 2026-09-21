# nvimtex.nvim
A LaTeX plugin for neovim, still alpha.
# features
## conceal
1. support multichar and any highight conceal. 
1. support dynamic conceal with latex args.
1. partially support `\newcommand` auto parsing, but since this feature is testing, now need manually enable it by
```latex
\newcommand{\testd}[2][1]{
  \ifmmode
  \mathrm{#1#2}
  \else
  #1#2
  \fi
}
%nvimtex: enable_parser_command_definition
\newcommand{\testa}[9][\mathbb{ABC}]{\mathrm{#1#2#3#4#5#6#7#8#9}}
\newcommand{\testb}[2][1]{
  \ifmmode
  \mathrm{#1#2}
  \else
  #1#2
  \fi
}
%nvimtex: disable_parser_command_definition
\newcommand{\testc}[2][1]{
  \ifmmode
  \mathrm{#1#2}
  \else
  #1#2
  \fi
}
```
in this example, `testa` and `testb` are parsed, `testc` and `testd` are not parsed. 

## compiling
1. support smartly guess compiler for the `tex` file by
```lua
require("nvimtex.compile").default()
```
2. support smartly guess how many turns need to run. 
3. support BibTeX/Biber in the builtin backend. It detects `biblatex`, BibTeX-style bibliography commands, and LaTeX-generated `.bcf`/`.aux` control files, runs the bibliography backend when needed, then reruns LaTeX.
   The backend is guessed from, in order: explicit config, TeX magic comments such as `% !TeX bib-program = biber`, explicit `biblatex` package backend option, bibliography-related packages, source commands such as `\addbibresource` or `\bibliography`, then LaTeX output artifacts.
4. builtin compile backend writes intermediate files to `/tmp/nvimtex.nvim/<hash>/` by default, then copies the final PDF and SyncTeX file back to the tex file directory.
5. successful builtin compiles notify a short summary with the command chain, per-step time, and total time.
```lua
require("nvimtex").setup({
  compile = {
    build_root = "/tmp/nvimtex.nvim",
    bib = {
      enabled = true,
      backend = "auto", -- "auto", "bibtex", or "biber"
      commands = {
        bibtex = "bibtex",
        biber = "biber",
      },
    },
  },
})
```

## snippet
I provided many snippets to use, in the `luasnippets` folder, but for now they are not documetationed. 
I also provide some cmp source for `blink.cmp`, supporting show unicode char in cmp window, but they are still alpha. 

## imselect
this plugin can be used to switch im according math_environment, etc. 
see [imselect.nvim](https://github.com/dirichy/imselect.nvim)

# install
you can use `lazy.nvim` or other manager to install this plugin. 
```lua
	{
		"dirichy/nvimtex.nvim",
		ft = { "tex", "latex" },
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"m00qek/baleia.nvim",
		},
		keys = {
			{
				"<leader>tv",
				function()
					require("nvimtex.view").view()
				end,
				desc = "View Pdf",
			},
			{
				"<leader>ts",
				function()
					require("nvimtex.view").sync()
				end,
				desc = "sync position via synctex",
			},
			{
				"<leader>tb",
				function()
					vim.cmd.wall()
					require("nvimtex.compile").default()
				end,
				desc = "Compile LaTeX File",
			},
			{
				"<leader>tl",
				function()
					require("nvimtex.compile").showlog()
				end,
				desc = "Show log file",
			},
		},
		config = function()
			require("nvimtex").setup()
            -- this line is to enable snippets
			require("luasnip.loaders.from_lua").load({})
		end,
	},
```

# tests
```sh
sh tests/run_headless.sh
```
This runs smart backend strategy tests, mocked compile pipeline tests, and real TeX fixture tests. Real engine cases are skipped when the corresponding executable exists but cannot compile cleanly in the local environment.
