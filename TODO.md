# TODO

本文档基于当前代码阅读和 VimTeX 功能面做对照整理。参考：

- VimTeX README: https://github.com/lervag/vimtex
- VimTeX help: https://github.com/lervag/vimtex/blob/master/doc/vimtex.txt

## 目标定位

当前 nvimtex.nvim 的强项是 Lua/Neovim 原生实现、数学符号 conceal、动态 conceal、snippet、简单编译和 Sioyek/Zathura 查看器集成。和 VimTeX 相比，目前更像一个可用的 LaTeX 编辑增强插件原型，还没有形成完整的 LaTeX 项目工作流。

如果目标不是完整复刻 VimTeX，建议优先把“编辑体验 + 编译/viewer 闭环 + 稳定 parser/conceal”做扎实；completion、TOC、quickfix、multi-file project 可以作为第二阶段。

## 与 VimTeX 相比缺的主要 Feature

### 编译与错误反馈

- [ ] 支持 latexmk 后端。VimTeX 默认推荐 latexmk，因为它能处理 rerun、bibtex/biber、索引等多轮逻辑。
- [ ] 支持 tectonic、latexrun、texpresso 等后端，或至少提供可扩展 backend 接口。
- [x] 实现 bibtex/biber 检测与运行。已支持显式配置、TeX magic comment、biblatex package option、package/source command、`.bcf`/`.aux` 控制文件多信号判断；`.bib` 文件优先从源码命令解析，产物只作 fallback。
- [ ] 解析 `.log` 到 quickfix/location list，而不是只弹出原始日志窗口。
- [ ] 支持编译当前选区/局部文档。
- [ ] 编译任务需要 job 状态管理：正在运行、停止、重启、防并发、多 buffer 隔离。
- [ ] 编译命令应支持 root file、多文件项目、jobname、outdir、auxdir、自定义参数。
- [ ] `showlog()` 应检测 `texlogsieve` 是否存在；不存在时 fallback 到原始 `.log`。

### PDF 查看器与 SyncTeX

- [ ] 完整 forward search 和 inverse search 抽象。
- [ ] 增加常见 viewer：Okular、Skim、SumatraPDF、MuPDF、qpdfview、TeXShop。
- [ ] 提供 generic viewer 配置接口。
- [ ] viewer 句柄需要按 buffer/root file 管理，而不是全局一个 handle。
- [ ] `sync()` 当前用 `CursorMoved` 反复调用 viewer，后续应改成 viewer-specific forward search 命令或节流。

### Completion

- [ ] citation completion：从 `.bib` 文件解析 cite key。
- [ ] label completion：收集 `\label{}`，用于 `\ref{}`/`\eqref{}` 等。
- [ ] command completion：内置命令、用户 `\newcommand`、package command。
- [ ] file completion：`\includegraphics`、`\input`、`\include`、`\includepdf`、`\includestandalone`。
- [ ] glossary completion。
- [ ] package/documentclass completion，可调用 `kpsewhich` 或 TeX tree 查询 `.sty`/`.cls`。
- [ ] 当前 blink source 只覆盖符号/alias，建议先补文档和稳定 API。

### 导航与项目结构

- [ ] TOC/table of contents：section、subsection、environment、label、todo 等。
- [ ] table of labels。
- [ ] 配置 `include`、`includeexpr`、`suffixesadd`、`define`，增强 `gf` 和定义跳转。
- [ ] root file 发现：支持 `% !TeX root = ...`、`.latexmkrc`、subfiles/import、多文件 include graph。
- [ ] package 文档查询：类似 VimTeX 的 latexdoc 入口。
- [ ] word count：集成 `texcount`。

### Motions / Text Objects / Surround

- [ ] section motions：`[[`、`[]`、`][`、`]]`。
- [ ] environment motions：`[m`、`]m` 等。
- [ ] math environment motions。
- [ ] frame/comment motions。
- [ ] `%` 匹配 LaTeX delimiter/environment。
- [ ] textobject 覆盖范围补齐：delimiter、section、item、math、environment、command arg。
- [ ] surround 操作补齐：delete/change command、environment、delimiter、math。
- [ ] toggle 操作：starred command/env、inline/display math、fraction、line break、left/right delimiter、互补环境。

### Folding / Indent / Syntax

- [ ] foldexpr：按 section、environment、preamble、comments 折叠。
- [ ] indentexpr：LaTeX 环境、列表、align、braces 的缩进规则。
- [ ] syntax/highlight：目前主要依赖 treesitter 和 conceal，缺少 package-specific highlighting。
- [ ] delimiter matching highlight。

### 文档、配置与用户接口

- [ ] 提供 `:NvimtexCompile`、`:NvimtexView`、`:NvimtexSync`、`:NvimtexToggleConceal` 等命令。
- [ ] 提供默认 keymap，可配置关闭。
- [ ] README 需要列全依赖：nvim-treesitter latex parser、baleia、plenary 或改掉 plenary 依赖、mini.ai 可选、luasnip/blink/telescope 可选。
- [ ] 为每个模块写最小使用示例。
- [ ] 增加 healthcheck：检查 latex parser、编译器、viewer、texlogsieve、texcount、kpsewhich。

## 代码质量 TODO

### 高优先级

- [ ] 给 `compile` 模块加任务状态，避免同一 buffer 重复启动多个编译 job。
- [x] `compile.smart` 里未使用的 `cache`、`log` 已删除，`bcf` 已用于 biber 检测。
- [x] `compile.smart` 已从 aux 稳定循环改成固定 job pipeline：LaTeX，必要时 BibTeX/Biber，然后 LaTeX 两次。
- [x] 通用 job 启动和结果展示已放到 `compile.util`；bib/source/artifact 判断保留在自带 `compile.smart` 后端中。
- [x] 自带 `compile.smart` 后端默认把中间产物写到 `/tmp/nvimtex.nvim/<hash>/`，编译成功后把 PDF 和 SyncTeX 复制回 tex 所在目录。
- [x] 自带 `compile.smart` 后端成功时显示编译摘要，包含命令链、单步耗时和总耗时，不再 notify 原始日志。
- [ ] `compile.smart` 需要把 `opts.path` 对应的 buffer/source 分开；当前 TODO 已指出 source 默认当前 buffer。
- [ ] `util.get_documentclass()`、`get_packages()` 应处理 parser 不存在或 parse 失败，不应直接索引 `trees()[1]`。
- [ ] `parser.iter_children()` 使用 pool 但没有归还 parser；要么实现归还和状态清理，要么删除 pool。
- [ ] `parser.iter_children()` 在 node 为 nil 时仍进入 consumer，需要系统性测试 EOF/residual 行为。
- [ ] `LNode.add_child(child, field, index)` 插入到中间时 `_index_2_field` 不会重排，后续 field 映射可能错。
- [ ] `LNode.remove_bracket()` 假设首尾 child 存在；空 group 或 parse error 下需要保护。
- [ ] conceal 的 namespace 清理不完整：`refresh()` 只清 fast namespace，但实际 conceal 多数用动态 `nvimtex` namespace。
- [ ] conceal 的 cursor refresh 每次全屏区域遍历，性能可能随大文件恶化，需要按 changed range 或 visible range 优化。
- [ ] `processor.source_file`/`generic_environment` 对 node child chain 假设太硬，应改 field 访问并保护 nil。
- [ ] `textobject` 依赖 mini.ai，应在 README 标为可选依赖，并在缺失时有 debug 级提示或 healthcheck。

### 中优先级

- [ ] telescope extension 目前像本地配置迁移进仓库，需改成正式 extension API、可选依赖保护，并提供插入选中符号的行为。
- [ ] `latex/items.lua` 在遍历 M 时又 `table.insert(M, ...)`，pairs 遍历期间修改表不稳定，建议先收集扩展项再 append。
- [ ] `conditions.luasnip.in_env()` 用 `match("[A-Za-z]+")` 会丢掉带星号的环境名，如 `align*`。
- [ ] `conditions.luasnip.in_cmd_arg()` 只匹配字母命令名，`\[`、`\"`、自定义含 `@` 的命令都可能不准。
- [ ] `view.zathura` 里有 macOS `osascript` 逻辑，Linux 下不适用；应按系统拆分。
- [ ] `view.sioyek` inverse-search command 拼字符串，文件名含空格/特殊字符时可能失败，需要 shell escaping 或 argv 方式。
- [ ] `compile.util.showlog()` 用字符串拼 systemlist，路径含空格会失败；应改 list argv 或 `vim.system`。
- [ ] `showbelow()` 每次 `require("baleia").setup({})`，应复用实例。
- [ ] Autocmd 应建 augroup，重复 setup 时先 clear，避免重复事件。

### 测试 TODO

- [ ] 建立最小 busted/plenary.nvim test 或 headless nvim test runner。
- [ ] parser/LNode：覆盖 generic command 参数消费、optional arg、word 拆分、residual、ifmmode。
- [ ] conceal：覆盖 `\frac`、`\sqrt`、`\not`、style command、新命令解析开关。
- [x] compile：已有 headless nvim 测试覆盖 smart 后端 compiler 识别、bib backend 识别、编译次数、bibtex/biber 顺序、禁用 bib、artifact fallback、输出复制，并包含真实 TeX fixture。
- [ ] compile：继续覆盖 root file、失败路径、index/glossary、多文件 include。
- [ ] view：mock executable/spawn，覆盖不存在 viewer、root file、single spawn。
- [ ] textobject/surround：用 fixture tex 验证 range 和替换结果。

## 本轮已处理

- [x] `setup()` 现在会把 `opts.conceal` 传给 conceal 模块。
- [x] `view` 模块改为 lazy require viewer，避免 setup 时因为 zathura/plenary 缺失崩溃。
- [x] `view()` 修复了新开 viewer 时调用两次 viewer function 的问题。
- [x] `sioyek` 的 `vim.fn.executable()` 判断已改为 `== 0`。
- [x] `sioyek` spawn 使用配置里的 `opts.command`，不再硬编码第二份命令名。
- [x] `textobject` 的 FileType autocmd pattern 已从 `*.tex` 改成 `tex`/`latex`。
- [x] 缺少 `mini.ai` 时 textobject setup 不再直接报错。
- [x] conceal `setup_buf()` 先规范化 autocmd event/bufnr，再检查 `have_setup`。
- [x] `get_magic_comment()` 现在一次扫描返回 table，能安全处理 EOF，并保留 value 原大小写，支持 path/空格等非纯字母值。
