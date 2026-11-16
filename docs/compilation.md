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
    build_root = "/tmp/nvimtex.nvim",
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
LaTeX Tree-sitter parser. Existing custom `detection.documentclasses`,
`detection.documentclass_prefixes`, `detection.compiler_magic_keys`, and
`detection.packages` rules are retained.

引擎选择优先使用显式 `engine`，其次是 TeX magic comment，再按宏包、文档类和
`favor` 决定。适配层相应传入 `-pdf`、`-xelatex` 或 `-lualatex`。
宏包和文档类识别使用 LaTeX Tree-sitter parser；原有自定义引擎识别规则保留。

`args` replaces the default argument list; retain `-synctex=1` if you need PDF
search. Native latexmk flags such as `-r project.rc`, `-bibtex-`, or `-e` expressions
can be supplied as separate argv entries. Use `engine` to choose the engine.
The adapter manages output paths and expects the source basename as jobname;
do not change `-outdir`, `-auxdir`, or `-jobname` through args/rc. A project rc's
engine default can be overridden by the adapter's explicit engine flag.

`args` 整体替换默认参数列表；需要 PDF 搜索时请保留 `-synctex=1`。
latexmk 原生选项及其参数应分别放在 argv 列表中。引擎通过 `engine` 设置。
构建路径和产物名由适配层管理，请勿在 args/rc 中修改 `-outdir`、`-auxdir` 或
`-jobname`。适配层传入的引擎选项可能覆盖项目 rc 中的默认引擎设置。

## Calls and outputs / 调用与产物

```lua
local compile = require("nvimtex.compile")
compile.default() -- current saved file / 当前已保存文件
compile.default({ path = "/path/to/main.tex", engine = "xelatex" })
compile.showlog() -- current file's TeX log / 当前文件的 TeX 日志
compile.arara()   -- explicit alternative / 显式选择 arara
```

`default()` also accepts per-call `executable`, `args`, and `build_root` overrides.
An optional `source` (buffer number or TeX string) affects engine detection only;
latexmk always compiles the saved file. With `path` alone, detection uses that
file's loaded buffer or reads it from disk, independently of the current buffer.
Automatic main-file discovery is not implemented; pass the main file via `path`.

`default()` 可逐次覆盖 `executable`、`args` 和 `build_root`。可选 `source`
（buffer 编号或 TeX 字符串）只用于引擎识别；实际编译读取磁盘上的文件。
只传 `path` 时使用目标文件已加载的 buffer 或磁盘内容，不误用当前 buffer。
尚未实现自动发现主文件；多文件项目请通过 `path` 指定主文件。

Intermediate files live under `build_root/<sha256(absolute-source-path)>/`.
After exit code zero, the PDF and available `.synctex.gz` are copied beside the
source. A failed build leaves previously published files intact. Success reports
the selected engine and latexmk's total time; individual TeX/BibTeX timings are no
longer collected. `showlog()` requires `texlogsieve` and `baleia.nvim`; compilation
requires latexmk, its selected tools, and `plenary.nvim`. Engine/font caches keep
their normal TeX configuration.

中间文件放在 `build_root/<源文件绝对路径的 sha256>/`。进程成功退出后才把 PDF
和存在的 `.synctex.gz` 复制到源目录；失败时保留上次发布的结果。
成功通知显示引擎和 latexmk 总耗时，不再采集各个 TeX/BibTeX 子步骤的耗时。
日志展示依赖 `texlogsieve` 和 `baleia.nvim`，编译依赖 latexmk、对应工具及
`plenary.nvim`。字体缓存沿用系统正常配置。

## Migration / 旧配置迁移

The `compile.smart` backend, `compile_args`, `bib`, `rerun.skip`, and bibliography
`detection` rules have been removed. The public `compile.default()`, callable
`compile()`, `compile.showlog()`, and `compile.arara()` entry points remain.

旧的 `compile.smart`、`compile_args`、`bib`、`rerun.skip` 及参考文献识别规则已移除。
公开的编译、日志和 arara 入口保持不变。

| Old setting / 旧项 | Replacement / 替代 |
| --- | --- |
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
