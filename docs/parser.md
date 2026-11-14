# Parser nodes / 解析节点

## 中文

插件包装节点继续使用 TSNode 风格的读取接口：`type()`、`range()`、
`start()`、`end_()`、`child(index)`、`child_count()`、`named()`、
`named_child(index)`、`named_child_count()` 和 `iter_children()`。
`child()` 使用从零开始的下标；包装节点额外保留负下标访问。

包装节点不实现 `field()`，不保存原始 TSNode 供字段回查，也不维护字段缓存。
包装节点和 `parser.iter_children()` 的迭代器均只返回一个节点。
原始 TSNode 仍属于 Neovim；其接口没有被修改。

通过 `nvimtex.parser.latex_nodes` 读取 LaTeX 语义：

```lua
local nodes = require("nvimtex.parser.latex_nodes")
local name = nodes.command_name(source, command)
local args = nodes.arguments(command)
local optional = nodes.optional_argument(command)
local body = nodes.branch(conditional)       -- ifmmode 分支
local alternative = nodes.branch(conditional, true)
```

`arguments()` 返回必需参数，包含 parser 补读的裸参数，不包含可选参数和注释。
`optional_argument()` 返回节点或 nil。定义通过 `definition_parts()` 取得
声明、参数数量节点、默认值和实现节点；环境名通过 `environment_name()` 读取。
这些 helper 同时接受原始 TSNode 和包装节点，将语法类型、子节点位置和缺失项处理
集中在一处。调用方不再维护 grammar 字段映射。

迁移时用语义 helper 替换 `field("arg")` 等调用，去掉迭代器的第二接收变量。
构造包装节点使用 `add_child(child, index?)`；第二个参数是可选的一基插入位置，
不再是字段名。自定义 parser 回调只接收 `(context, node)` 并返回节点。
调试输出 `parser:sexpr(node, source)` 不再打印字段标签。

`Stream` 全程使用索引访问，在子节点较多时二分定位可见范围附近的起点。
命令参数和公式内部仍按完整语义处理，范围裁剪不截断单个已选中的公式。

## English

Wrapped nodes retain TSNode-style read methods: `type()`, `range()`, `start()`,
`end_()`, `child(index)`, `child_count()`, `named()`, `named_child(index)`,
`named_child_count()`, and `iter_children()`. Child indices are zero-based;
wrapped nodes also retain the existing negative-index extension.

Wrapped nodes have no `field()` method, backing TSNode for field lookup, or field
cache. Their iterators and `parser.iter_children()` return only a node. Native
TSNodes still belong to Neovim and are not modified.

Use `nvimtex.parser.latex_nodes` for semantic access:

- `command_name(source, node)` reads a command name.
- `arguments(node)` returns required arguments, including parsed bare tokens,
  while excluding optional groups and comments.
- `optional_argument(node)` returns the optional group or nil.
- `branch(node, alternative?)` selects an ifmmode or else body.
- `definition_parts(node)` returns declaration, argument-count node, default, and body.
- `environment_name(source, node)` reads the environment name.

These helpers accept both native and wrapped nodes. Grammar-specific child
positions, node types, and missing-node handling stay in the helper module.

Replace calls such as `field("arg")` with semantic helpers and remove the second
iterator variable. `add_child(child, index?)` accepts an optional one-based
insertion index, not a field name. Custom parser callbacks receive
`(context, node)` and return a node. `parser:sexpr(node, source)` no longer emits
field labels.

The stream uses indexed access throughout and binary seeking for large child
lists. Once selected, commands and formulas are processed as complete units;
viewport pruning does not truncate their internal syntax.

## Performance / 性能

The reproducible microbenchmark is `tests/bench_parser_nodes.lua`. Run the same
script in separate Neovim processes; `NVIMTEX_BENCH_ROOT` selects a checkout.
It parses the native syntax trees before timing, warms each workload, and then
measures three formulas. Node checksums match between revisions (87 nodes).

```sh
XDG_STATE_HOME=/tmp/nvimtex-bench-state nvim --headless -u NONE -i NONE -l tests/bench_parser_nodes.lua
NVIMTEX_BENCH_ROOT=/path/to/before XDG_STATE_HOME=/tmp/nvimtex-bench-state nvim --headless -u NONE -i NONE -l tests/bench_parser_nodes.lua
```

本机三轮独立进程对照，交替前后版本顺序，以下为每条公式耗时的中位数。
Three independent process pairs, with alternating revision order, gave these medians:

| Workload / 工作量 | Before / 之前 | After / 之后 | Reduction / 降低 |
|---|---:|---:|---:|
| Recursive parser walk / 递归解析遍历 | 49.46 μs | 28.59 μs | 42.2% |
| RenderTree construction / 构造显示树 | 69.07 μs | 52.05 μs | 24.6% |
| Construction and extmark output / 构造及输出 | 102.07 μs | 82.56 μs | 19.1% |

These are local CPU microbenchmarks, not end-to-end editing latency: they exclude
native Tree-sitter parsing, debounce delays, and screen redraw. The fixtures cover
fractions, a root, fonts, delimiters, and scripts, not every document shape.
这些是局部 CPU 测量，不含原生解析、防抖等待和屏幕重绘；不能直接当作整次刷新收益。
移除的是通用字段存储和传递，语义 helper 本身仍有实现与维护成本。

For the changed parser/conceal production files, nonblank, noncomment lines grew
from 1,791 to 1,873 (+82), excluding tests and documentation. The benefit is fewer
metadata structures and a single semantic-access boundary, rather than fewer
source lines. 在本次修改的 parser/conceal 生产文件中，去掉空行和注释后净增 82 行；
维护成本转为显式的语义 helper，并不是代码总行数减少。
