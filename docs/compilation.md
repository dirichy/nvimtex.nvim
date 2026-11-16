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
