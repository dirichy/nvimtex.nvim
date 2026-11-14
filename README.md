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

Document commands are compiled from the preamble and scoped to their buffer.
Supported expansions include repeated arguments, an optional first argument,
forward references, symbols, fractions, roots, fonts, and scripts. Unsupported
or recursive expansions keep the invocation visible. Editing an expanded command
reveals its complete source until the cursor leaves it.

Conceal updates the visible region on edits, cursor movement, and scrolling.
`require("nvimtex.conceal").toggle()` turns it off or on for initialized buffers;
`forceRefresh()` rebuilds the current buffer's definitions and display.

```lua
require("nvimtex").setup({
  conceal = {
    debounce = 50,       -- milliseconds, independently per buffer
    viewport_margin = 3,
    binary_threshold = 16,
    child_lookbehind = 2,
  },
})
```

## textobjects

Use `mini.ai` (the default) or Pairwise for LaTeX textobjects. Initialize your
chosen plugin, then configure nvimtex at startup:

```lua
require("mini.ai").setup()
require("nvimtex").setup()
```

For Pairwise instead:

```lua
require("pairwise").setup()
require("nvimtex").setup({ textobject = { integration = "pairwise" } })
```

| Object | Inside (`i`) | Around (`a`) |
| --- | --- | --- |
| `c` | Command name, excluding `\` | Command and all arguments |
| `a` | Argument contents | Argument with delimiters |
| `m` | Math contents | Math with delimiters |
| `e` | Environment body | Complete environment |
| `g` | Group contents | Group with `{…}` or `[…]` |
| `S` | Current sub/superscript contents | Current suffix, e.g. `_{ij}` |
| `N` | Environment name | Its `{name}` group |

For example, `cia` changes an argument, `dim` deletes math contents, and `d2aa`
deletes the second enclosing argument. Visual selections can expand outward.
This version only finds enclosing objects; MiniAi's `search_method` and
`n_lines` do not enable nearby-object searches.

With Pairwise, `dsc` removes a single-argument command wrapper; `cscc` prompts
for a replacement command name, and `ysiwc` wraps a word in a command.
For `\sqrt[3]{x}`, the opening is `\sqrt[3]{` and the closing is `}`.
For commands with any number of arguments, `cic` edits the name and preserves
arguments. Command surround supports complete braced single-argument wrappers;
`ia/aa` select individual arguments. Bare arguments are not command pairs.
Pairwise also supports `dsm` / `dse` / `dsg` to remove math, environment, and
group delimiters. `csee` prompts for an environment name and changes both ends;
`ysiwm`, `ysiwe`, and `ysiwg` add `$…$`, a prompted environment, or `{…}`.
`iN` selects one environment name (the closing name when queried at `\end`,
otherwise the opening name); use `csee` to rename both ends together.
Uppercase `S` and `N` preserve sentence objects and MiniAi's `in/an` prefixes.
The Pairwise integration requires its `textobject.find` / `surround.find` API
and uses nvimtex parsing independently of Pairwise language presets.

Objects are enabled in `tex`, `plaintex`, `latex`, `markdown`, `rmd`, and `quarto`
buffers. Install the `latex` Tree-sitter parser; Markdown also needs `markdown`
and `markdown_inline`. Set `textobject = false` to disable automatic integration.
See the bilingual [textobject API notes](docs/textobjects.md) for custom mappings
and implementation details.

中文：默认接入 mini.ai，也可选择 Pairwise；`c/a/m/e` 分别表示命令、参数、数学和环境，
配合 `i/a` 选择内部或整体。支持计数和可视选区向外扩展；第一版只查找包围当前位置
的对象，不支持向附近搜索。`ic` 选择命令名（不含反斜杠），`ac` 选择命令及所有参数。
Pairwise 的 `dsc/cscc/ysiwc` 处理单参数包装；`cic` 可直接改名并保留全部参数。
新增 `ig/ag` 分组、`iS/aS` 当前上下标、`iN/aN` 环境名；大写按键保留句子对象及
mini.ai 的 `in/an` 前缀。Pairwise 的 `dsm/dse/dsg` 可删除对应边界，
`csee` 输入新环境名可同时改两端；`iN` 只选择当前一端的名字。
接入需要 Pairwise 的 `textobject.find` / `surround.find` API，解析由 nvimtex 负责。
配置和自定义映射见[中英文说明](docs/textobjects.md)。

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
		ft = { "tex", "latex", "markdown" },
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
			require("luasnip").config.setup({ enable_autosnippets = true })
			require("nvimtex").setup()
			require("luasnip").filetype_extend("markdown", { "tex" })
			-- this line is to enable snippets
			require("luasnip.loaders.from_lua").load({})
		end,
	},
```

For Markdown conceal, install the `markdown`, `markdown_inline`, and `latex`
Tree-sitter parsers. LaTeX snippets are active inside Markdown LaTeX regions
after `filetype_extend("markdown", { "tex" })`.

# tests
```sh
sh tests/run_headless.sh
```
This runs smart backend strategy tests, mocked compile pipeline tests, and real TeX fixture tests. Real engine cases are skipped when the corresponding executable exists but cannot compile cleanly in the local environment.

Run just the parser and conceal regression suite with:
```sh
sh tests/run_conceal.sh
```
It covers command expansion and buffer isolation, edit invalidation, cursor
reveal, adjacent formulas, scrolling, split windows, toggling, and buffer cleanup.
The test scripts return a nonzero status on assertion failure.

Parser extensions use TSNode-style nodes and semantic helpers instead of grammar
fields. See the bilingual [parser API notes](docs/parser.md) for examples and migration details.
