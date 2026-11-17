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

`conceal.conceal_cursor` (default `"nvic"`, `false` to leave it unchanged) only
sets `concealcursor` once when initializing `tex`, `plaintex`, and `latex` buffers.
Markdown, Rmd, and Quarto preserve the window's current setting because it also
controls Tree-sitter conceal. Use `setlocal concealcursor=` to reveal the whole
cursor line in all modes.
`conceallevel` is initialized to `2` once. Later refreshes preserve both options:
`conceallevel=0` disables rendering, and lines revealed by `concealcursor` get no
conceal or virtual replacements, including selected lines in Visual mode.

`conceal.conceal_cursor`（默认 `"nvic"`，设为 `false` 则不修改）仅在 `tex`、
`plaintex`、`latex` 首次初始化时设置一次 `concealcursor`。Markdown、Rmd、Quarto
保留窗口当前设置，因为它也控制 Tree-sitter conceal。使用 `setlocal concealcursor=` 可在所有
模式下显示光标整行的原文。
`conceallevel` 也只在初始化时设为 `2`，后续刷新保留这两个选项的用户修改：
`conceallevel=0` 关闭渲染；根据 `concealcursor` 应显示原文的行不会添加 conceal
或虚拟替换文本，包括 Visual 模式选中的各行。

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

## math environment conversion

Normal-mode `m<C-a>` and `m<C-x>` automatically upgrade/downgrade math in LaTeX
buffers and Markdown LaTeX regions. Counts are supported. Keyflow is opt-in:

```lua
require("nvimtex").setup({
  surround = {
    keyflow = true, -- default: false; requires keyflow.mode(spec)
    keymaps = {
      upgrade_math = "m<C-a>", -- another key or false
      downgrade_math = "m<C-x>",
    },
  },
})
```

Set `surround = false` to disable automatic math-conversion mappings. With
keyflow enabled, the first mapping enters a transient mode for repeated
`<C-a>/<C-x>`; Escape exits. Remove old manual math-mode registrations from your
configuration. See [math conversion](docs/math-conversion.md) for details.

中文：默认自动安装 buffer 局部的 `m<C-a>/m<C-x>` 升降数学环境映射。
`surround = false` 整体禁用，单个 key 设为 `false` 可分别禁用，也可改绑。
keyflow 默认关闭，设为 `true` 后才加载并启用连续操作；请移除个人配置中的旧数学
模式注册。详见[中英文说明](docs/math-conversion.md)。

## compiling

Install `latexmk` and your TeX engines, save the document, then run:

```lua
require("nvimtex.compile").default()
```

The default backend calls latexmk once. Latexmk handles reruns, BibTeX/Biber,
indexes, dependencies, and project `.latexmkrc` rules. nvimtex selects the engine
from TeX magic comments, packages, document class, and the configured preference
order; set `engine` to override detection. Compilation can work without
Tree-sitter: header helpers reuse an active valid tree or read the preamble as
text, without starting a parser. From a child file, declare the main
document with `% !TeX root = ../main.tex` or
`\documentclass[../main.tex]{subfiles}`. Otherwise the current file is compiled.
Lua callers can pass an exact target with `default({ path = "/path/to/main.tex" })`.

```lua
require("nvimtex").setup({
  compile = {
    -- engine = "lualatex", -- optional; default: automatic selection
    executable = "latexmk",
  },
})
```

Output locations and filenames follow latexmk defaults and your `.latexmkrc` or
`args`; nvimtex does not create a temporary build directory or copy artifacts.
The notification reports latexmk's total elapsed time.
`require("nvimtex.compile").showlog()` opens the main file's sibling log; pass an
explicit `.log` path for custom directories/jobnames.
`require("nvimtex.compile").arara()` remains available as an explicit backend.
After latexmk or arara finishes, saved LaTeX/BibTeX/Biber logs update quickfix.
Open it again with `require("nvimtex.compile").errors()` and navigate with `:cnext` /
`:cprev`. Set `compile.quickfix = false` to disable automatic updates, or
`compile.quickfix = { open = false }` to update without opening the window.
See [compilation configuration and migration](docs/compilation.md).

中文：默认后端调用 latexmk，由它管理重编译、参考文献、索引、依赖和项目
`.latexmkrc`。nvimtex 保留引擎自动选择，也可用 `compile.engine` 指定。
编译所需的文件头 helper 可在没有 Tree-sitter 时工作：有有效的活动树则复用，
否则读取导言区文本，不启动 parser。
子文件通过 `% !TeX root = ../main.tex` 或 `subfiles` 文档类参数声明主文件；
没有声明则编译当前文件，也可在 Lua 调用中传 `path`。声明的相对路径按子文件目录
解析，不进行启发式搜索；无效声明报错。日志和查看器使用同一个主文件。
请安装 latexmk 和所需 TeX 引擎，并先保存文档。产物目录和名称遵循 latexmk
默认行为、项目 `.latexmkrc` 或用户参数；插件不再创建临时构建目录或复制产物。
`showlog()` 默认读取主文件旁的日志，自定义目录或名称时直接传 `.log` 路径。
latexmk 或 arara 结束后会读取 LaTeX/BibTeX/Biber 日志更新 quickfix；用 `errors()`
重新打开，`:cnext` / `:cprev` 跳转。`compile.quickfix = false` 禁用自动更新，
`compile.quickfix = { open = false }` 只更新列表，不自动打开窗口。
自带的轮数判断、参考文献调度和默认 PGF 忽略规则已移除；旧配置迁移见
[中英文说明](docs/compilation.md)。

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
			"nvim-lua/plenary.nvim", -- compilation jobs
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
This runs parser/conceal and editing regressions, engine-selection and compile
adapter tests, and real latexmk builds. Real cases cover all three engines,
references, a table of contents requiring more than two passes, BibTeX/Biber,
incremental bibliography updates, and explicit project rules for unstable PGF
marks. Missing executables skip their cases; installed tools that fail cause a
test failure. Tests copy fixtures to `/tmp`; formats and font caches use your
normal TeX configuration.

测试包含解析、显示和编辑回归，以及引擎识别、编译适配和真实 latexmk 构建。
真实用例覆盖三种引擎、引用、超过两轮的目录收敛、参考文献增量更新及 PGF
项目规则。缺少可执行文件时跳过对应用例；已安装工具失败则报错。
编译产物放在 `/tmp`，字体缓存沿用正常 TeX 配置，不在每次测试时重建。

Run just the parser and conceal regression suite with:
```sh
sh tests/run_conceal.sh
```
It covers command expansion and buffer isolation, edit invalidation, cursor
reveal, adjacent formulas, scrolling, split windows, toggling, and buffer cleanup.
The test scripts return a nonzero status on assertion failure.

Parser extensions use TSNode-style nodes and semantic helpers instead of grammar
fields. See the bilingual [parser API notes](docs/parser.md) for examples and migration details.
