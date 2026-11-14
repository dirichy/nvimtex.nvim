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
| `a` | Argument contents / 参数内容 | Argument with delimiters / 参数及定界符 |
| `m` | Math contents / 数学内容 | Math with delimiters / 数学及定界符 |
| `e` | Environment body / 环境正文 | Complete environment / 完整环境 |
| `g` | Group contents / 分组内容 | `{…}` or `[…]` group / 含定界符的分组 |
| `S` | Current sub/superscript contents / 当前上下标内容 | Suffix with marker / 含标记的后缀 |
| `N` | Environment name / 环境名 | Its `{name}` group / 环境名分组 |

`cic` changes a command's name while preserving all arguments, including optional
ones. It works for single-argument, multi-argument, and argument-free commands.
`ia/aa` select the argument containing the reference, including optional or bare
arguments. `ig/ag` work for any parsed curly/bracket group, including standalone
and script groups. For `x_{ij}^2`, `iS/aS` select `ij`/`_{ij}` in the subscript,
or `2`/`^2` in the superscript; the base is excluded. `iN/aN` select the opening
environment name and its group from the body, or the closing name/group at
`\end`. Editing `iN` affects one end only. Uppercase IDs avoid replacing sentence
objects and MiniAi's next-object prefixes. Empty interiors are valid. Counts select enclosing layers; nonempty
references require a strictly larger containing selection. No match returns nil.
A single-character Visual reference starts a cursor query in both adapters.

`cic` 修改命令名并保留全部参数，包括可选参数；支持单参数、多参数和无参数命令。
`ia/aa` 选择参考位置所在的参数，包括可选参数和隐式参数。`ig/ag` 选择任意已解析
花括号或方括号分组，包括独立分组和上下标中的分组。`x_{ij}^2` 中，`iS/aS` 在
下标处选择 `ij/_{ij}`，在上标处选择 `2/^2`，不包含底数。`iN/aN` 从正文选择
begin 端的名字及其分组，从 end 端选择结束名字及其分组；编辑 `iN` 只影响一端。
大写 ID 保留原生句子对象及 MiniAi 的 next-object 前缀。内部可以为空。
计数选择包围层级，非空参考选区必须扩展为更大的包围选区；无匹配返回 nil。
两个适配器都将单字符可视选区作为光标查询。

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
`find(id, context)` returns Range4 for `c/a/m/e/g/S/N`: zero-based rows and byte
columns, exclusive end. Equal endpoints mean a cursor point on input or an
empty selection on output. `find_bounds(id, context, record?)` returns selection
boundaries `outer_start`, `inner_start`, `inner_end`, `outer_end` as `{row, col}`.
`find_pair(id, context, record?)` returns the same shape for removable
`c/m/e/g` boundaries. Command wrappers require one braced argument and exclude
begin/end markers; math and environment boundaries require complete syntax. The optional callback receives
counted layers, including intermediate ones.

`bufnr/reference/inner` 必填，count 默认 1。`find(id, context)` 支持 `c/a/m/e/g/S/N`，
返回 Range4：行列从零开始，列以字节计，末端不包含；相同起止表示输入光标点或
输出空选区。`find_bounds(id, context, record?)` 返回选区的四个边界
`outer_start/inner_start/inner_end/outer_end`，每个为 `{行, 字节列}`。
`find_pair(id, context, record?)` 为可移除的 `c/m/e/g` 边界返回同样形状。
命令包装要求一个花括号参数，排除 begin/end；数学和环境要求完整语法。可选回调接收计数经过的各层，包括中间层。

The core parses the specified buffer and LaTeX injections, including hidden
buffers, without reading the current cursor or editing text, selections, or
mappings. It depends on neither plugin. MiniAi converts Range4 to its one-based,
inclusive regions, handling UTF-8 and newlines, and merges objects into buffer
`miniai_config` without copying global options. Pairwise uses only its public
`api.register`: IDs `nvimtex.c/a/m/e/g/S/N`, scoped to the buffer, register
`textobject.find`; `c/m/e/g` also supply independent `surround.find` and `add`.
The Pairwise adapter exports these wrapper finders in `pairs` and textobject
finders in `objects`.
The finder session receives complete counted layers through its documented
`matches` collection. Pairwise owns mappings, operations, registers, Undo, repeat,
and the registration lifecycle.

core 解析指定 buffer 及 LaTeX 注入区域，支持隐藏 buffer，不读取当前光标，
不修改文本、选区或映射，也不依赖上述插件。MiniAi 将 Range4 转换为从一开始、
包含末端的坐标，处理 UTF-8 和换行；只合并 buffer 的 `miniai_config`，不复制
全局选项。Pairwise 仅通过公开 `api.register` 注册 buffer 局部的
`nvimtex.c/a/m/e/g/S/N`，提供 `textobject.find`；`c/m/e/g` 另提供独立的
`surround.find` 和 `add`。Pairwise 适配器通过 `pairs` 导出包装 finder，通过
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
