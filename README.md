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
| `a` | Contents of a complete `{…}` or `[…]` group | Group with delimiters |
| `m` | Math contents | Math with delimiters |
| `e` | Environment body | Complete environment |
| `u` | Current sub/superscript contents | Current suffix, e.g. `_{ij}` |
| `S` | Section body, including subsections | Heading and complete section |
| `i` | Item body | Complete `\item` entry, including label |
| `d` | Delimited contents | Complete delimiters, including sizing commands |

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
`ia/aa` only select complete parsed `{…}` or `[…]` groups, including environment
names, braced script arguments, and standalone groups. For `x_{ij}`, `ia/aa`
select `ij`/`{ij}` while `au` selects `_{ij}`. Bare arguments such as `x_i` or
`\sqrt x` are excluded from `ia/aa`; use `iu/au` for bare scripts. Environment name
selection requires the cursor at that name and edits one end; use `csee` to
rename both ends together. `iS/aS` select sections; `is/as` retain native sentence behavior.
The Pairwise integration requires its `textobject.find` / `surround.find` API
and uses nvimtex parsing independently of Pairwise language presets.

Use `iu/au` for scripts, `iS/aS` for sections, `ii/ai` for list items, and `id/ad`
for delimiters such as `\left(…\right)`, `\bigl[…\bigr]`, and `\langle…\rangle`.
Section/item inside excludes the heading or `\item[label]` and surrounding
whitespace; around includes indentation and separators up to the next sibling
or enclosing boundary. Counts expand to enclosing sections/items. Plain `|`
and `\vert` are not paired automatically because they can denote relations.
Pairwise also supports `dsd` to remove delimiters and `ysiwd` to add `\left(…\right)`.

Objects are enabled in `tex`, `plaintex`, `latex`, `markdown`, `rmd`, and `quarto`
buffers. Install the `latex` Tree-sitter parser; Markdown also needs `markdown`
and `markdown_inline`. Set `textobject = false` to disable automatic integration.
See the bilingual [textobject API notes](docs/textobjects.md) for custom mappings
and implementation details.

中文：默认接入 mini.ai，也可选择 Pairwise；`c/a/m/e` 分别表示命令、参数、数学和环境，
配合 `i/a` 选择内部或整体。支持计数和可视选区向外扩展；第一版只查找包围当前位置
的对象，不支持向附近搜索。`ic` 选择命令名（不含反斜杠），`ac` 选择命令及所有参数。
Pairwise 的 `dsc/cscc/ysiwc` 处理单参数包装；`cic` 可直接改名并保留全部参数。
`iu/au` 选择上下标，`iS/aS` 选择章节，`ii/ai` 选择列表项，`id/ad` 选择定界符；
保留原生 `is/as` 句子对象及现有 `im/am` 数学区域对象。
`ia/aa` 只识别完整的花括号或方括号分组，包括环境名、带括号的上下标和独立分组。
不选择 `x_i`、`\sqrt x` 等裸参数；裸上下标仍可用 `iu/au`，`au` 包含 `_` 或 `^`。
环境名需要光标位于名字处，且只编辑一端；
用 `csee` 同时改两端。Pairwise 的 `dsm/dse/dsg` 可删除对应边界，`g` 仅用于 surround。
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
This runs smart backend strategy tests, mocked compile pipeline tests, and real
TeX fixture tests. Missing executables skip their cases; installed engines that
fail to compile cause a test failure with the compiler output. Build outputs go
to `/tmp`, while engine formats and font caches use your normal TeX configuration
so each run does not rebuild the font database.

测试包含编译策略、模拟编译流程和真实 TeX 用例。缺少可执行文件时跳过对应用例；
已安装的引擎编译失败则报错并显示日志。编译产物放在 `/tmp`，格式文件和字体缓存
沿用正常 TeX 配置，不在每次运行时重建字体数据库。

Run just the parser and conceal regression suite with:
```sh
sh tests/run_conceal.sh
```
It covers command expansion and buffer isolation, edit invalidation, cursor
reveal, adjacent formulas, scrolling, split windows, toggling, and buffer cleanup.
The test scripts return a nonzero status on assertion failure.

Parser extensions use TSNode-style nodes and semantic helpers instead of grammar
fields. See the bilingual [parser API notes](docs/parser.md) for examples and migration details.
