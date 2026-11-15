# Textobjects / 文本对象

## Setup / 配置

Initialize MiniAi or Pairwise normally, then select one integration at startup:

先正常初始化 MiniAi 或 Pairwise，再在启动时选择接入方式：

```lua
require("nvimtex").setup({
  textobject = { integration = "pairwise" }, -- default / 默认: "mini.ai"
})
```

The Pairwise checkout must support feature-specific `textobject.find` and
`surround.find` in `pairwise.api.register`. Nvimtex supplies its own parser
results; Pairwise's LaTeX preset is not required. Supported buffer filetypes are
`tex`, `plaintex`, `latex`, `markdown`, `rmd`, and `quarto`. Install the `latex`
Tree-sitter parser; Markdown also needs `markdown` and `markdown_inline`.

Pairwise 需支持 `pairwise.api.register` 中独立的 `textobject.find` 和
`surround.find`。解析结果由 nvimtex 提供，不依赖 Pairwise 的 LaTeX preset。
支持的 buffer filetype 为 `tex/plaintex/latex/markdown/rmd/quarto`。安装 `latex`
Tree-sitter parser；Markdown 另需 `markdown`、`markdown_inline`。

Set `textobject = false` to disable automatic registration. A missing integration
plugin is skipped and retried on `BufEnter`. Select the integration at startup;
changing or disabling it later does not undo installed buffer configuration or
Pairwise registrations.

`textobject = false` 关闭自动注册。对应插件缺失时跳过，在 `BufEnter` 重试。
请在启动时选定接入方式；运行中切换或关闭不会撤销已安装的 buffer 配置或
Pairwise 注册。

## Selection and surround / 选区与包装

| Object / 对象 | Inside / 内部 | Around / 整体 |
| --- | --- | --- |
| `c` | Command name without `\` / 命令名，不含反斜杠 | Command and all arguments / 命令及全部参数 |
| `a` | Complete group contents / 完整分组内容 | Group with delimiters / 分组及定界符 |
| `m` | Math contents / 数学内容 | Math with delimiters / 数学及定界符 |
| `e` | Environment body / 环境正文 | Complete environment / 完整环境 |
| `u` | Current sub/superscript contents / 当前上下标内容 | Suffix with marker / 含标记的后缀 |
| `S` | Section body / 章节正文 | Heading and complete section / 标题及完整章节 |
| `i` | List item body / 列表项正文 | Complete item with label / 含标签的完整条目 |
| `d` | Delimited contents / 定界符内容 | Complete delimiters / 完整定界符 |

`cic` changes a command's name while preserving all arguments, including optional
ones. It works for single-argument, multi-argument, and argument-free commands.
`ia/aa` only select complete parsed curly or bracket groups. This includes
braced required/optional command arguments, environment names in begin/end
markers, braced script arguments, standalone groups, and named grammar groups
such as label and section arguments. Selection depends on the group structure,
not an enumeration of parent node types. Environment names require the reference
within their group; queries in the body do not jump to a name.

For `x_{ij}^2`, `ia/aa` select `ij`/`{ij}` in the subscript. The bare superscript
`2` is not an argument selection. `iu/au` remain available for both forms: they
select `ij`/`_{ij}` or `2`/`^2`, excluding the base and including the marker for
around. `x^\alpha` and `\sqrt x` have no `ia/aa` match unless a complete enclosing
group exists. Incomplete groups are skipped. Empty interiors are valid. Counts
select enclosing groups; nonempty references require a strictly larger containing
selection. No match returns nil. A single-character Visual reference starts a
cursor query in both adapters.

`cic` 修改命令名并保留全部参数，包括可选参数；支持单参数、多参数和无参数命令。
`ia/aa` 只选择完整的花括号或方括号分组，覆盖带括号的命令参数、begin/end 中的
环境名、带括号的上下标、独立分组，以及 label、section 等专用语法中的参数分组。
依据分组结构识别，不枚举父节点类型。环境名要求参考位置在其分组中，不从正文跳转。

`x_{ij}^2` 中，`ia/aa` 在下标处选择 `ij/{ij}`，不选择裸上标 `2`。`iu/au` 仍然
支持两种形式，分别选择 `ij/_{ij}` 或 `2/^2`，不含底数，around 包含标记。
`x^\alpha` 和 `\sqrt x` 的裸参数不匹配 `ia/aa`；若外面还有完整分组，则可选择
那个包围分组。不完整分组会跳过，内部可以为空。计数选择包围分组，非空参考选区
要求严格扩展，无匹配返回 nil；两个适配器都把单字符可视选区视为光标查询。

The default objects are `c/a/m/e/u/S/i/d`; scripts use `u`, while `S` is reserved for sections. The separate `g/N` textobjects have been
merged into `a`. Pairwise keeps `g` as a surround-only selector. Editing an
environment name through `ia` changes that end only; use `csee` to rename both.

默认文本对象为 `c/a/m/e/u/S/i/d`；独立的 `g/N` 对象合并进 `a`。Pairwise 保留 `g` 作为
仅用于 surround 的 selector。通过 `ia` 修改环境名只影响选中的一端，同时修改
两端请用 `csee`。

`iS/aS` select sections, preserving native `is/as` sentence objects. Section
inside excludes the heading, short title, and surrounding whitespace; around
includes the heading, indentation, and separators through the next same/higher
section or container boundary. Subsections belong to their parent section.
`ii/ai` similarly select list item contents or the complete item, including
`\item[label]`. Nested lists are handled structurally; counts select enclosing
items/sections rather than adjacent siblings. Trailing blank lines belong to
the preceding entry. These are characterwise ranges that include complete lines
when the entry occupies its own lines, so `daS` and `dai` remove whole entries.

`iS/aS` 选择章节，保留原生 `is/as` 句子对象。章节内部不含标题、短标题选项和
两端空白；整体包含标题、缩进及到下一个同级/上级章节或容器边界之前的分隔空白。
子章节归属父章节。`ii/ai` 类似地选择列表项正文或包含 `\item[label]` 的完整条目。
嵌套列表依照语法结构处理，计数选择外层条目/章节，不选择相邻条目。尾部空行归属
前一条目。返回字符选区；当条目独占行时包含完整行，`daS/dai` 因此能删除完整条目。

`id/ad` cover curly/bracket groups, ordinary parentheses, explicit paired commands
such as `\langle…\rangle`, and sized `\left…\right` / `\bigl…\bigr` delimiters.
Inside retains whitespace immediately between the delimiters. Invisible `.`
delimiters and multiline contents are supported; unbalanced syntax is skipped.
Plain bars and `\vert` are not guessed as pairs, since they also denote relations.
Pairwise's `dsd` removes the selected pair; `ysiwd` adds `\left(…\right)`.
The implementation uses nvimtex's parsed nodes and scoped token matching, not
VimTeX regexes or cursor manipulation. `im/am` continue selecting math regions;
VimTeX's item key `m` is deliberately assigned to `i` here.

`id/ad` 支持花括号/方括号分组、普通圆括号、`\langle…\rangle` 等显式成对命令，
以及 `\left…\right`、`\bigl…\bigr` 等大小修饰定界符。内部保留定界符之间的空白。
支持不可见的 `.` 定界符和多行内容，跳过不完整配对。普通竖线和 `\vert` 也可表示
关系，因此不猜测配对。Pairwise 的 `dsd` 删除配对，`ysiwd` 添加 `\left(…\right)`。
实现使用 nvimtex 解析节点和同一语法作用域内的 token 匹配，不使用 VimTeX 正则或
移动光标。`im/am` 保持数学区域含义；VimTeX 的 item 按键 `m` 在这里改为 `i`。

Command surround is separate from `ic`: only a complete braced single-argument
command is a wrapper. For `\sqrt[3]{x}`, opening is `\sqrt[3]{`, inside is `x`,
and closing is `}`. `dsc` unwraps to `x`, `cscc` prompts for a new wrapper name,
`csc(` changes it to `(x)`, and `ysiwc` wraps a word in a prompted command.
Empty input or Escape cancels. Names may include a leading backslash. Known
non-single-argument commands cannot be destinations; unknown names are treated
as single-argument wrappers. Multi-argument, bare, incomplete, and argument-free
commands are skipped by surround; an enclosing supported wrapper can still match.

命令 surround 与 `ic` 独立：只把完整花括号单参数命令作为包装。
`\sqrt[3]{x}` 的 opening 为 `\sqrt[3]{`，内部为 `x`，closing 为 `}`。
`dsc` 得到 `x`，`cscc` 输入新包装命令，`csc(` 得到 `(x)`，`ysiwc` 输入命令包装单词。
空输入或 Escape 取消，命令名可带反斜杠。已知的非单参数命令不能作为目标，
未知名字按单参数包装处理。surround 跳过多参数、无花括号、不完整和无参数命令，
仍可匹配外层支持的包装。

Math, environment, and group surround reuse their complete syntax boundaries.
`dsm/dse/dsg` remove delimiters without changing contents. `csee` prompts for an
environment name and updates both delimiters. `ysiwm`, `ysiwe`, and `ysiwg` add
`$…$`, a prompted `\begin{name}…\end{name}`, and `{…}` respectively. Existing
newlines are preserved; there is no automatic reindentation or line insertion.
Incomplete groups and environments with mismatched names are not removable.

数学、环境和分组 surround 复用完整语法边界。`dsm/dse/dsg` 删除定界符并保留内容。
`csee` 输入新环境名并更新两端；`ysiwm/ysiwe/ysiwg` 分别添加 `$…$`、输入名字的
`\begin{name}…\end{name}` 和 `{…}`。保留已有换行，不自动缩进或插入换行。
不完整分组和名字不匹配的环境不提供可移除边界。

This version only searches enclosing syntax. MiniAi `search_method`, `n_lines`,
candidate lists, and explicit `vis_mode` are not implemented.

第一版只查找包围语法，不实现 MiniAi 的 `search_method`、`n_lines`、候选列表和
显式 `vis_mode`。

## Core and integrations / 核心与接入

```lua
local core = require("nvimtex.textobject.core")
local context = {
  bufnr = bufnr,
  reference = { row, col, row, col },
  inner = true,
  count = 1,
}
local range = core.find("c", context)
local selection = core.find_bounds("c", context)
local wrapper = core.find_pair("c", context)
```

`bufnr`, `reference`, and `inner` are required; count defaults to 1.
`find(id, context)` returns Range4 for `c/a/m/e/u/S/i/d`: zero-based rows and byte
columns, exclusive end. Equal endpoints mean a cursor point on input or an
empty selection on output. `find_bounds(id, context, record?)` returns selection
boundaries `outer_start`, `inner_start`, `inner_end`, `outer_end` as `{row, col}`.
`find_pair(id, context, record?)` returns the same shape for removable
`c/m/e/g/d` boundaries. Command wrappers require one braced argument and exclude
begin/end markers; math and environment boundaries require complete syntax. The optional callback receives
counted layers, including intermediate ones.

`bufnr/reference/inner` 必填，count 默认 1。`find(id, context)` 支持 `c/a/m/e/u/S/i/d`，
返回 Range4：行列从零开始，列以字节计，末端不包含；相同起止表示输入光标点或
输出空选区。`find_bounds(id, context, record?)` 返回选区的四个边界
`outer_start/inner_start/inner_end/outer_end`，每个为 `{行, 字节列}`。
`find_pair(id, context, record?)` 为可移除的 `c/m/e/g/d` 边界返回同样形状。
命令包装要求一个花括号参数，排除 begin/end；数学和环境要求完整语法。可选回调接收计数经过的各层，包括中间层。

The core parses the specified buffer and LaTeX injections, including hidden
buffers, without reading the current cursor or editing text, selections, or
mappings. It depends on neither plugin. MiniAi converts Range4 to its one-based,
inclusive regions, handling UTF-8 and newlines, and merges objects into buffer
`miniai_config` without copying global options. Pairwise uses only its public
`api.register`: IDs `nvimtex.c/a/m/e/u/S/i/d`, scoped to the buffer, register
`textobject.find`; `c/m/e/d` also supply independent `surround.find` and `add`.
`nvimtex.g` supplies only surround lookup/addition, with textobjects disabled.
The Pairwise adapter exports these wrapper finders in `pairs` and textobject
finders in `objects`.
The finder session receives complete counted layers through its documented
`matches` collection. Pairwise owns mappings, operations, registers, Undo, repeat,
and the registration lifecycle.

core 解析指定 buffer 及 LaTeX 注入区域，支持隐藏 buffer，不读取当前光标，
不修改文本、选区或映射，也不依赖上述插件。MiniAi 将 Range4 转换为从一开始、
包含末端的坐标，处理 UTF-8 和换行；只合并 buffer 的 `miniai_config`，不复制
全局选项。Pairwise 仅通过公开 `api.register` 注册 buffer 局部的
`nvimtex.c/a/m/e/u/S/i/d`，提供 `textobject.find`；`c/m/e/d` 另提供独立的
`surround.find` 和 `add`。`nvimtex.g` 只提供 surround 查找与添加，关闭文本对象。Pairwise 适配器通过 `pairs` 导出包装 finder，通过
`objects` 导出文本对象 finder。
通过 finder session 文档中的 `matches` 集合报告完整计数层级。
映射、操作符、寄存器、撤销、重复和注册生命周期由 Pairwise 负责。

## Custom registration / 自定义注册

Disable automatic integration when registering your own objects:

自行注册时关闭自动接入：

```lua
local objects = require("nvimtex.textobject.integrations.pairwise").objects
require("pairwise.api").register({
  id = "my.math", key = "M", language = "latex",
  textobject = { find = objects.m },
  surround = false,
})
```

For MiniAi / MiniAi 配置：

```lua
local objects = require("nvimtex.textobject.integrations.mini_ai").objects
require("mini.ai").setup({ custom_textobjects = { M = objects.m } })
```

The Pairwise adapter's `objects` now return four selection boundaries, as required
by the feature finder API, rather than a Range4. MiniAi specs remain unchanged.
The old `require("nvimtex.textobject").textobject` export is replaced by
`require("nvimtex.textobject.integrations.mini_ai").objects`.

Pairwise 适配器的 `objects` 现在按 feature finder API 返回四个选区边界，
不再返回 Range4；MiniAi spec 接口不变。旧的
`require("nvimtex.textobject").textobject` 改为
`require("nvimtex.textobject.integrations.mini_ai").objects`。

The local VimTeX reference is `.dev/vimtex` at `cedc0a1`. Its
`autoload/vimtex/text_obj.vim` also selects command names without the backslash
for `ic`; `autoload/vimtex/cmd.vim` unwraps braces for single-argument deletion.
Nvimtex uses its own parser rather than VimTeX implementation code.

本地 VimTeX 参考仓库为 `.dev/vimtex`，版本 `cedc0a1`。
`autoload/vimtex/text_obj.vim` 的 `ic` 同样选择不含反斜杠的命令名；
`autoload/vimtex/cmd.vim` 在单参数删除时去掉参数括号。nvimtex 使用自身 parser。
