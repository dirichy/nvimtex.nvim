# Compilation / 编译

Save the TeX document before calling `require("nvimtex.compile").default()`.
The default backend launches one latexmk process in the source directory.
Latexmk owns convergence, bibliography/index tools, dependency tracking, and its
normal system/user/project rc configuration. nvimtex does not force a pass count
or ignore changing PGF marks.

调用 `require("nvimtex.compile").default()` 前请保存 TeX 文件。默认后端在源文件
目录启动一个 latexmk 进程，由 latexmk 判断收敛、运行参考文献和索引工具、
追踪依赖，并读取正常的系统、用户和项目 rc 配置。nvimtex 不再固定编译轮数，
也不默认忽略 PGF 标记变化。

## Setup / 配置

```lua
require("nvimtex").setup({
  compile = {
    executable = "latexmk",
    -- engine = "lualatex", -- omit for automatic selection / 省略则自动选择
    favor = { "pdflatex", "xelatex", "lualatex" },
    args = {
      "-interaction=nonstopmode",
      "-halt-on-error",
      "-file-line-error",
      "-synctex=1",
    },
  },
})
```

The engine comes from an explicit `engine`, `% !TeX program` / `% !TeX TS-program`,
or package/document-class constraints resolved using `favor`. The adapter passes
`-pdf`, `-xelatex`, or `-lualatex` accordingly. Package/class detection uses the
existing active LaTeX Tree-sitter tree when it is valid; otherwise it reads the
preamble as text. Installing a parser alone does not enable this path or trigger
a parse. Existing custom `detection.documentclasses`,
`detection.documentclass_prefixes`, `detection.compiler_magic_keys`, and
`detection.packages` rules are retained.

引擎选择优先使用显式 `engine`，其次是 TeX magic comment，再按宏包、文档类和
`favor` 决定。适配层相应传入 `-pdf`、`-xelatex` 或 `-lualatex`。
宏包和文档类识别优先复用正在启用且有效的 LaTeX Tree-sitter 树；没有运行高亮、
树已失效或没有 parser 时，按文本读取导言区，不会为此启动或刷新 parser。
原有自定义引擎识别规则保留。

`args` replaces the default argument list; retain `-synctex=1` if you need PDF
search. Native latexmk flags such as `-r project.rc`, `-bibtex-`, or `-e` expressions
can be supplied as separate argv entries. Use `engine` to choose the engine.
Output locations, jobnames, and output formats are left to latexmk. A project rc's
engine default can be overridden by the adapter's explicit engine flag.

`args` 整体替换默认参数列表；需要 PDF 搜索时请保留 `-synctex=1`。
latexmk 原生选项及其参数应分别放在 argv 列表中。引擎通过 `engine` 设置。
可在 args/rc 中设置 `-outdir`、`-auxdir` 和 `-jobname`；插件不覆盖产物位置、
名称或格式。适配层传入的引擎选项可能覆盖项目 rc 中的默认引擎设置。

## Calls and outputs / 调用与产物

```lua
local compile = require("nvimtex.compile")
compile.default() -- current document’s main file / 当前文档声明的主文件
compile.default({ path = "/path/to/main.tex", engine = "xelatex" })
compile.showlog() -- main document’s TeX log / 主文件的 TeX 日志
compile.arara()   -- explicit alternative / 显式选择 arara
```

`default()` also accepts per-call `executable` and `args` overrides.
An optional `source` (buffer number or TeX string) affects engine detection only;
latexmk always compiles the saved file. With `path` alone, detection uses that
file's loaded buffer or reads it from disk, independently of the current buffer.
An explicit `path` is the exact target and bypasses declarations in the current file.

`default()` 可逐次覆盖 `executable` 和 `args`。可选 `source`
（buffer 编号或 TeX 字符串）只用于引擎识别；实际编译读取磁盘上的文件。
只传 `path` 时使用目标文件已加载的 buffer 或磁盘内容，不误用当前 buffer。
显式 `path` 直接指定编译目标，不受当前文件声明影响。

Text fallback reads literal `\documentclass`, `\usepackage`, and `\RequirePackage`
declarations up to `\begin{document}`, supporting multiline declarations and
comments. It does not execute macros, evaluate TeX conditionals, or follow
`\input` files. Put engine/root magic comments before the first ordinary source
or blank line. For declarations generated through macros or included preambles,
specify `engine` or an engine magic comment explicitly.

文本回退只读取 `\begin{document}` 前的字面文档类与宏包声明，支持跨行和注释，
不执行宏、不判断 TeX 条件分支，也不跟随 `\input`。引擎和 root magic comment
放在第一个普通源码行或空行之前。通过宏或导入文件生成的声明，请显式指定引擎。

## Main document / 主文件

Without `path`, compilation selects the current file's main document in this order:

1. A `% !TeX root = ../main.tex` comment, parsed by the existing magic-comment helper.
2. `\documentclass[../main.tex]{subfiles}`.
3. The current file itself.

Relative declarations are resolved against the declaring file's directory;
absolute paths and spaces are supported. Put root comments in the initial TeX
magic-comment block, before any blank or ordinary source line. Paths are literal:
no globbing, directory scan, reverse include search, or `.latexmain` lookup occurs.
A declared path must name an existing readable file; an empty root or malformed
`subfiles` option is an error. Supply the full filename, including `.tex`.

Declarations select one target, without recursively following that target's own
root/subfiles declaration. Engine detection then reads the selected main file
(unless `source` explicitly overrides it). Default log lookup, arara, and PDF viewers use the same
selection rule; Lua callers can still supply `path` to `default()` or `showlog()`.

不传 `path` 时，依次选择当前文件的 root magic comment、`subfiles` 文档类参数、
当前文件。相对路径按声明所在文件的目录解析，支持绝对路径和空格。
root comment 请放在文件开头的 TeX magic comment 块中，位于空行或普通源码之前。
路径按字面使用，不支持通配符，也不扫描目录、反查包含关系或查找 `.latexmain`。
请写完整文件名（包括 `.tex`）；声明目标不可读、root 为空或 `subfiles` 参数无效时报错。

声明只解析一层，不继续追踪目标文件自身的 root/subfiles 声明。
选定主文件后，从主文件识别引擎（显式传入 `source` 时除外）。
默认日志、arara 和 PDF 查看器复用相同规则；Lua 调用仍可直接传 `path`。

## Output locations and logs / 产物位置与日志

No output directory is imposed. By default, latexmk runs in the main document's
folder and places files there. Configure a project's `.latexmkrc` to put them
elsewhere, for example:

不指定输出目录时，latexmk 在主文件目录构建并保存产物。需要其他目录时，在
项目 `.latexmkrc` 中配置，例如：

```perl
$out_dir = 'build';
```

Alternatively, pass native latexmk output options in `args` (alongside the other
options you need). nvimtex does not copy or rename PDF/SyncTeX files, validate an
expected output path, or preserve a previous PDF through a separate publication
step; outputs follow latexmk and the selected tools' behavior, including failure
cases. The old `build_root` option has been removed. Existing temporary artifacts
are not deleted or migrated.

也可通过 `args` 传入 latexmk 原生输出选项，并保留需要的其他参数。
插件不复制、重命名 PDF/SyncTeX，不检查固定产物路径，也不再通过单独的发布步骤
保留旧 PDF；成功和失败时的产物行为都由 latexmk 和对应工具决定。
旧 `build_root` 选项已移除，已有临时产物不会自动删除或迁移。

Success reports the selected engine and latexmk's total elapsed time.
`showlog()` reads the main document's sibling `.log`; it also accepts a TeX path
or an exact `.log` path. Custom output directories/jobnames are not inferred:

成功通知显示引擎和 latexmk 总耗时。`showlog()` 默认读取主文件旁的 `.log`，
也可传 TeX 路径或具体日志路径；不推断用户配置中的输出目录和 jobname：

```lua
require("nvimtex.compile").showlog("/path/to/project/build/main.log")
```

The bundled PDF viewers currently assume a PDF beside the main TeX file with
its original basename; custom output paths/jobnames need a separately configured
viewer command (for example through TexLab). Setting a build directory does not
automatically configure viewer or LSP paths.

内置 PDF 查看器目前假定 PDF 位于主文件旁且同名；自定义产物目录或名称时，需要
另外配置查看器调用（例如使用 TexLab）。设置构建目录不会自动配置查看器或 LSP。

`showlog()` requires `texlogsieve` and `baleia.nvim`; compilation requires latexmk,
its selected tools, and `plenary.nvim`. Engine/font caches keep their normal TeX
configuration. Compilation, main-file selection, and PDF viewing do not require
a Tree-sitter parser; conceal and structural editing still do.

日志展示依赖 `texlogsieve` 和 `baleia.nvim`，编译依赖 latexmk、对应工具及
`plenary.nvim`。字体缓存沿用系统正常配置。编译、主文件识别及 PDF 查看不依赖
Tree-sitter parser；conceal 和结构编辑仍然依赖它。

## Errors and quickfix / 错误列表

The latexmk and arara backends share one completion handler that reads the saved
`.log` and `.blg` after both successful and failed builds. It opens nonempty
quickfix lists without moving focus, puts errors before warnings, and replaces
the current list when it belongs to the same main
file. A clean build clears that list and closes its window. Unrelated lists stay
in quickfix history; a clean build does not replace an unrelated current list.
Use native `:cnext`, `:cprev`, and `:copen` to navigate.

latexmk 和 arara 共用完成处理：成功或失败后读取磁盘上的 `.log` 和 `.blg`，更新 quickfix。
有消息时自动打开窗口但不移动焦点；错误排在警告前。同一主文件的当前列表会被
替换，重新编译干净后会清空并关闭该列表。其他列表保留在原生 quickfix 历史中；
干净构建不会替换其他来源的当前列表。使用 `:cnext`、`:cprev`、`:copen` 交互。

```lua
require("nvimtex").setup({
  compile = {
    -- quickfix = false, -- disable automatic parsing / 禁用自动解析
    quickfix = {
      open = false, -- update without opening / 只更新，不自动打开
      ignore = { [[Underfull]], [[Package hyperref Warning]] }, -- Vim regex
    },
  },
})

local compile = require("nvimtex.compile")
compile.errors() -- read saved logs and open quickfix / 读取日志并打开列表
compile.errors({ open = false, ignore = { [[Underfull]] } })
compile.errors({
  path = "/path/to/main.tex",
  log = "build/renamed.log", -- relative to main.tex / 相对主文件目录
  -- blg = "another/location/renamed.blg", -- default: log basename / 默认与 log 同名
})
-- Pass the log path to compilation too when outputs are customized:
-- 自定义输出位置时，也给编译调用传入日志路径：
compile.default({ log = "build/renamed.log" })
```

`errors()` returns the parsed quickfix entries and works even when automatic
quickfix is disabled. Its `path` follows the same main-file selection as
compilation; `log` and `blg` accept absolute paths or paths relative to that main
file's directory. Default lookup assumes sibling logs; output directories and
jobnames from arbitrary latexmkrc code are not inferred. Per-call `errors()`
options are independent of the automatic `compile.quickfix` settings.

`errors()` 返回解析后的 quickfix 条目，禁用自动更新后仍可手动调用。
`path` 与编译复用主文件选择规则；`log` 和 `blg` 可传绝对路径或相对主文件目录的
路径。默认查找同目录同名日志，不推断任意 latexmkrc 代码中的产物目录和名称。
`errors()` 的逐次参数独立于自动更新使用的 `compile.quickfix` 配置。

A Lua pattern parser supports file:line errors, multiline LaTeX/package/font warnings,
missing characters, box warnings, and common BibTeX/Biber failures and entry
warnings. Keep `-file-line-error` in the engine arguments. Parsing does not need
TexLab, Tree-sitter, texlogsieve, or baleia. If a failed build has no readable log
or no parsed error, the raw compiler output remains the fallback. This is saved
build output, not live LSP diagnostics; log formats and literal bibliography resource lookup still
have limits. See [parser design and benchmark](quickfix.md).

Lua pattern 解析支持 file:line 错误、多行 LaTeX/宏包/字体警告、缺字、box 警告，以及常见的
BibTeX/Biber 错误和文献条目警告。请保留引擎参数 `-file-line-error`。
解析本身不依赖 TexLab、Tree-sitter、texlogsieve 或 baleia。失败后日志不可读或
没有解析出错误时，两种后端均显示原始编译输出。
列表表示保存到日志的构建结果，不是实时 LSP 诊断；日志格式和字面文献资源查找
仍有限制。实现与性能说明见[开发文档](quickfix.md)。

`compile.arara()` uses the same `compile.quickfix` settings and accepts `log` /
`blg` overrides alongside its existing plenary job options:

`compile.arara()` 复用同一份 `compile.quickfix` 配置，并可在原有 plenary job
参数之外传入 `log` / `blg`：

```lua
compile.arara({ log = "build/main.log" })
```

Keep `-file-line-error` in the arara rule's engine options too. Default log lookup
still assumes sibling logs. Supplying your own job `on_exit` replaces the default
completion handler, including automatic quickfix updates.

arara 规则中的引擎选项也应保留 `-file-line-error`。默认仍查找同目录同名日志。
传入自定义 job `on_exit` 会替换默认完成处理，也就替换了自动 quickfix 更新。

## Migration / 旧配置迁移

The `compile.smart` backend, `compile_args`, `bib`, `rerun.skip`, and bibliography
`detection` rules have been removed. The public `compile.default()`, callable
`compile()`, `compile.showlog()`, and `compile.arara()` entry points remain.

旧的 `compile.smart`、`compile_args`、`bib`、`rerun.skip` 及参考文献识别规则已移除。
公开的编译、日志和 arara 入口保持不变。

| Old setting / 旧项 | Replacement / 替代 |
| --- | --- |
| `build_root` | `.latexmkrc` `$out_dir` / `$aux_dir`, or native output flags / 原生目录参数 |
| `compile_args` | `args`: latexmk arguments / latexmk 参数 |
| per-call `command = "xelatex"` | `engine = "xelatex"` |
| `bib.enabled = false` | latexmk `-bibtex-` |
| custom BibTeX/Biber commands | `.latexmkrc` `$bibtex` / `$biber` |
| `bib.backend` and bib magic comments | bibliography package configuration and latexmk / 交给参考文献宏包和 latexmk |
| `rerun.skip` Lua patterns | `.latexmkrc` `%hash_calc_ignore_pattern` Perl regex |

For a project that deliberately ignores known PGF coordinate drift, an explicit
`.latexmkrc` can contain the rule below. Repairing a drawing that fails to
converge is preferable; suppressing a changing mark does not prove its positioning
is correct.

项目确实需要忽略已知 PGF 坐标漂移时，可以显式配置下面的 `.latexmkrc`。
更应优先修正不收敛的绘图；忽略变化不代表定位正确。

```perl
$hash_calc_ignore_pattern{'aux'} = '^\\\\pgfsyspdfmark\b';
```
