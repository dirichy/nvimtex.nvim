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
3. for now, bibtex and biber are not implemented, but they are on schedule. 

## snippet
I provided many snippets to use, in the `luasnippets` folder, but for now they are not documetationed. 
I also provide some cmp source for `blink.cmp`, supporting show unicode char in cmp window, but they are still alpha. 

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
