# Quickfix implementation / Quickfix 实现

The LaTeX message semantics, warning path heuristic, and bibliography rules are adapted
from VimTeX, revision `cedc0a172e40d0d1d49670dd0d936d6e2df61de7`.
The MIT copyright and permission notice is preserved in `LICENSES/VimTeX.txt`.

LaTeX 消息语义、警告路径启发式和文献日志规则参考上述 VimTeX 版本。
原 MIT 版权与许可保存在 `LICENSES/VimTeX.txt`。

## Ownership / 职责

- `compile/log.lua`: Lua pattern parsing, multiline message state, and LaTeX path recovery.
- `compile/bibliography.lua`: BibTeX/Biber parsing and bibliography entry lookup.
- `compile/quickfix.lua`: reading both logs, filtering, stable error-first order,
  and native quickfix presentation.
- Both backend completion callbacks invoke `quickfix.update()`, sharing log
  lookup, settings, and the raw-output fallback decision. There is no LSP or
  diagnostic namespace to synchronize.

上述模块分别负责 Lua pattern 解析、多行消息和路径修正，文献日志与条目定位，列表合并与交互。
latexmk 和 arara 的完成回调共用 `quickfix.update()`，统一日志查找、配置和兜底判断，
不引入 LSP 状态同步。

Parsing uses Lua patterns and a single forward pass to recognize message starts,
continuations, and ends. Ordinary tracing output closes the active message.
Package-specific continuation rules preserve VimTeX's text and indentation;
the first explicit location wins over later source excerpts. Box source recovery
retains its separate backward parenthesis heuristic. BibTeX continuations supply
locations; Biber lines supply severity directly.

解析通过 Lua pattern 单次向前遍历识别消息开始、续行与结束；普通追踪输出结束
当前消息。保留宏包续行的缩进和结束规则，后续源码片段不覆盖已有明确位置。
box 来源定位仍使用独立的向后括号启发式；BibTeX 续行补充位置，Biber 按行识别级别。

Neither `errorformat` nor `vim.regex` is used for log recognition. Parsed entries
carry project-relative or absolute filenames directly, including missing source
files. No directory or option is changed and no source buffer is loaded.
Only presentation uses native quickfix APIs. User-configured `ignore` patterns
remain Vim regular expressions; that API is independent of log recognition.

日志识别不再使用 errorformat 或 vim.regex，直接生成带文件路径的条目，支持已不存在
的源文件。不切换目录、修改选项或加载源码 buffer；展示使用原生 quickfix API。
用户配置的 ignore 仍为 Vim 正则，该接口独立于日志识别。

Path resolution shares `util.normalize_file(path, { cwd = root })`, including
absolute/Windows drive paths and `.`/`..` cleanup. Literal bibliography declarations
and preamble readers share `util.strip_comment(line)`: an odd run of backslashes
escapes `%`, while an even run starts a comment. These helpers do not execute TeX
or interpret catcode changes.

路径解析统一复用 `util.normalize_file()`，处理绝对路径、Windows 盘符和 `.`/`..`。
字面文献声明与导言区读取统一复用 `util.strip_comment()`，根据反斜杠奇偶区分
转义百分号和注释，不执行 TeX，也不解释 catcode 变更。

## Changes from VimTeX / 与参考实现的差异

- Box warnings are indexed by occurrence, so identical messages in different
  files do not all resolve to the first occurrence. Path recovery also runs on
  logs longer than 10,000 lines; it retains the backward parenthesis heuristic
  and its limitations, rather than pretending to parse arbitrary TeX output.
- Bibliography keys are indexed once per file per read, shared by all messages.
  Biber's temporary decoded `.utf8` paths map back to its announced source.
- Generic BibTeX syntax messages containing `---line N of file F` are recognized.
  A following `while executing---line ...` supplies the prior message location.
  Biber rules also accept messages without the traditional `module:line>` prefix.
- No errorformat engine, temporary option mutation, external pplatex/pulp
  backend, cursor-keystroke autoclose, or recursive TeX macro evaluation is added.
- Bibliography resource fallback reads literal `\addbibresource` declarations in
  the main file. It does not recursively search included preambles. Some uncommon
  bibliography messages retain their raw wording instead of VimTeX's rewritten
  text or source-search location. Arbitrary log formats remain unsupported.

box 警告按出现顺序索引，区分不同文件中的同文消息；超过一万行仍进行来源定位。
保留向后平衡括号的启发式及其局限。每次读取只给每份文献建立一次 key 索引。
补充通用 BibTeX 语法错误和无模块前缀的 Biber 格式；不调用 errorformat，
不修改临时选项，也不加入外部解析后端、按移动次数关窗等交互。
文献资源回退只读主文件的字面声明，不递归解析导言区或执行宏；少见文献消息可能
保留原文，不完全复刻 VimTeX 的消息重写或源码搜索定位。

## Verification / 验证

`tests/headless/quickfix_spec.lua` compares frozen VimTeX outputs on the upstream
fixtures (including filenames), and covers directory independence, native state
preservation, filtering, list reuse/clearing, duplicate box warnings in a large
log, message-state boundaries, first-location precedence, and real BibTeX/Biber
syntax-error logs. It needs no reference checkout or
TeX installation. Original upstream assertions can also be run unchanged against
the replacement parser:

日常测试不依赖 VimTeX checkout 或 TeX 工具，比较原夹具的冻结输出，并补充上述
回归。也可用现有 `.dev/vimtex` 运行四份原始断言，只替换解析入口：

```sh
sh tests/run_quickfix_vimtex.sh
# VIMTEX_PATH=/path/to/vimtex sh tests/run_quickfix_vimtex.sh
```

## Benchmark / 性能对照

Run backends sequentially in separate minimal Neovim processes:

依次启动两个独立的最小 Neovim 进程，避免共同加载和并行争用：

```sh
QF_BACKEND=vimtex nvim --headless -u NONE -i NONE -l tests/bench_quickfix.lua
QF_BACKEND=nvimtex nvim --headless -u NONE -i NONE -l tests/bench_quickfix.lua
```

Both runs read the same log files and update native quickfix. Each case warms up
20 times, then measures nine batches of 30 calls, reporting median batch-average
milliseconds per call. File I/O, parsing, path correction, and list replacement
are included; process startup, UI redraw, and TeX compilation are excluded.
Outputs are saved to `/tmp/nvimtex-quickfix-bench/{vimtex,nvimtex}.json` for equality
checks. The synthetic box log is below VimTeX's 10,000-line cutoff; the larger log
contains file:line errors, so both backends perform equivalent location work.

测量包含读日志、解析、路径修正和更新列表；不包含启动、重绘和 TeX 编译。
每项预热 20 次，取九组、每组 30 次的组平均中位数。JSON 保存文件、行号、类型和消息，便于校验
两次输出相同。box 用例低于 VimTeX 的一万行限制；大日志用明确 file:line 错误，
避免用省略定位工作的结果做比较。

Measured on this machine on 2026-11-16. Each implementation ran independently;
all four cases have identical filenames, line numbers, types, and message texts
(after normalizing path spelling). The retired errorformat implementation was
snapshotted to `/tmp` for this comparison; it is not retained as a runtime backend.

2026-11-16 本机独立进程实测，三种实现的四组文件、行号、类型和消息均一致。
替换前的 errorformat 实现仅在 `/tmp` 临时保留用于对照，不作为兼容后端留下。
单位为毫秒/次，最后一列相对替换前的 nvimtex 版本：

| Case / 场景 | VimTeX | nvimtex errorformat | nvimtex Lua pattern | Speedup / 倍率 |
| --- | ---: | ---: | ---: | ---: |
| Upstream messages / 原消息夹具 | 1.781 | 0.879 | 0.293 | 3.00× |
| Filenames with spaces / 空格路径 | 13.725 | 5.613 | 0.753 | 7.46× |
| 6,902 lines, 300 boxes / 合成密集警告 | 138.290 | 50.888 | 3.899 | 13.05× |
| 20,001 lines, 80 errors / 合成大日志 | 145.762 | 137.197 | 2.423 | 56.63× |

The dedicated parser skips irrelevant tracing lines cheaply and avoids the
general errorformat engine and its source-buffer bookkeeping. This measures the
whole parser change, not the isolated speed of Lua patterns versus Vim regex.
The large and dense cases are synthetic stress logs; they do not establish
end-to-end compilation or editing latency improvements.

专用解析器快速跳过普通追踪行，并省去了通用 errorformat 引擎及其源码 buffer
管理。这里测量整套解析器替换的收益，不能单独归因于 Lua pattern 比 Vim 正则快。
大日志与密集警告为合成压力夹具，不代表整个编译或编辑操作的延迟提升。
