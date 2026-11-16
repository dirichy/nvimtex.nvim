# Quickfix fixtures

`vimtex/` contains the LaTeX quickfix fixtures and four original test scripts from
[lervag/vimtex](https://github.com/lervag/vimtex), revision
`cedc0a172e40d0d1d49670dd0d936d6e2df61de7` (MIT; see `LICENSES/VimTeX.txt`).
The adjacent JSON files freeze VimTeX's complete output (message, type, line,
and project-relative filename). Normal tests need neither VimTeX nor TeX tools.

`vimtex/` 包含上述 VimTeX 版本的日志、源码夹具及四份原始测试脚本。
JSON 保存原实现的完整输出，除原测试的消息、类型和行号之外，也比较文件路径。
日常测试不需要安装 VimTeX 或 TeX 工具。

`bibtex-error/` and `biber-error/` were generated with TeX Live 2026, BibTeX
0.99e and Biber 2.22. Each intentionally omits a comma in `refs.bib` to exercise
real syntax-error locations, including Biber's temporary decoded `.utf8` path.

这两份自有夹具故意省略文献字段间的逗号，用于验证真实编译错误的文件与行号。
