# nvimtex conceal 优化案例：从全文件遍历到可交互 RenderTree

这次优化最初只是一个很普通的性能问题：每次刷新 LaTeX conceal 都要扫描整个文件。继续分析后，我们发现真正值得重构的不只是扫描范围，而是从 Tree-sitter 节点、命令展开、显示结构到 extmark 输出的整条链路。

最后形成的方案并不是“把某个循环写快一点”，而是重新划分职责：

- Tree-sitter 负责提供语法结构；
- processor 只决定哪些区域和节点需要处理；
- renderer 把一整段数学公式转换成 RenderTree；
- RenderTree 保留足够细的显示粒度，并在最后统一生成 extmark；
- 命令模板负责普通命令的渲染和光标交互策略；
- 自定义命令可以预编译成一张紧凑的后缀操作表。

这篇文章记录了期间做过的主要尝试、基准结果，以及哪些优化最终值得保留。

## 1. 起点：为什么每次都要扫描整个文件

原来的 conceal 流程会从语法树根节点向下遍历。即使用户只看屏幕附近几十行，也可能处理整个 LaTeX 文件和整个导言区。

最直接的想法是只处理可见区域，并在上下额外保留少量 lookbehind。最初考虑过 20 行，后来认为 LaTeX 命令跨越 20 行并不常见，最终把设计目标缩小到 3 行：如果一个命令真的跨越了更大的范围，暂时不能 conceal 也是可以接受的。

这里有两个独立问题：

1. 怎样快速找到与可见范围相交的子节点；
2. 导言区什么时候需要重新扫描。

### 1.1 对有层次的语法树使用二分定位

Tree-sitter 子节点通常按源码位置有序，因此可以根据节点范围二分查找第一个可能与 viewport 相交的 child，然后只向后遍历相关节点。

这个策略对有层次的树很有效，但它不是万能的：

- 如果根节点下面直接挂了几千个同级节点，二分可以明显减少起点之前的遍历；
- 如果某个节点内部本身非常扁平，仍然要处理可见范围覆盖的那些同级节点；
- 如果每一层都自己建立 Lua 索引，索引成本可能抵消遍历收益。

因此最终结论不是“把所有遍历都换成二分”，而是：

> 对有序且子节点很多的层级使用范围定位；找到局部起点后，继续使用简单的顺序迭代。

我们还研究了 Tree-sitter 的原生 tree cursor、query 和底层 API。底层当然知道如何定位节点，但 Neovim 的 Lua API 没有完整暴露按 child index 定位或从指定 index 开始迭代的能力。为此整理过一个 Neovim issue，讨论了三种方向：完整暴露底层 API、提供针对 Lua 的高层 API，或先扩展 `iter_children` 作为 MVP。

### 1.2 导言区和正文必须分开

导言区扫描主要为了读取 `\newcommand` 等定义，它和正文 conceal 的触发时机不同：

- 正文 conceal 应围绕 viewport 和光标变化更新；
- 导言区只应在定义可能变化时更新；
- 修改正文不应该重新解析整个导言区。

当前实现已经把 `scan_preamble` 和 `process_conceal` 分开，并记录导言区 dirty 状态。进一步的理想方案是按定义节点缓存：只有某个 `new_command_definition` 内部发生变化时，重新编译对应定义，而不是重建全部自定义命令。

这部分带来的经验是：

> 在优化遍历前，先检查是不是把生命周期完全不同的工作放进了同一个 `process()`。

## 2. 真正的瓶颈不只在扫描：旧 Inline 的问题

旧实现使用一个可变 Inline 对象不断 append。它写起来方便，但逐渐暴露出几个问题：

- 连续相加可能频繁复制数组；
- style 往往需要重新遍历整段结果；
- 每个 atom 同时保存文本和高亮，结构与输出格式耦合；
- 很难表达“源码保持不变”“替换源码”“插入显示”“整段原子替换”等不同语义；
- extmark 粒度只能在很晚的时候猜测；
- 自定义命令展开、参数复用和重排越来越难处理。

我们讨论过几种替代结构。

### 2.1 可变双端数组

双端数组可以让左右拼接都比较便宜。如果所有结果都只使用一次，它是很现实的实现。

但它有两个问题：

- 一个子结果被复用时，调用者必须知道它会不会被后续修改；
- style、参数替换和缓存需要更谨慎地处理所有权。

### 2.2 不可变二叉树

让 `a + b` 只创建一个 concat 节点，可以把拼接从复制数组变成近似 O(1)。不过连续左结合相加会形成很深的二叉树：

```text
((((a + b) + c) + d) + e)
```

这种树构造便宜，但 flatten 时有较深的遍历栈和较差的局部性。

### 2.3 不可变多叉树

最终选择了不可变多叉 RenderTree：

```lua
Render.concat_many({ prefix, argument, separator, result })
```

一次连接多个 child，不会无谓增加树深度。它同时保留了不可变结构的优点：

- 子树可以安全复用；
- style 可以作为包裹节点作用于整个子树；
- 构造阶段不需要提前 flatten；
- renderer 可以组合小结果，而不必关心最终 extmark。

在实际公式上，它的性能和旧的可变 append 已经接近，而显示粒度明显更好。因此这里的目标不再是追求构造阶段的绝对最短时间，而是用近似相同的成本获得更清楚的语义和更好的交互能力。

## 3. RenderTree 的核心语义

当前 RenderTree 包含几类节点：

- `text`：一个有源码起点的显示叶子；
- `concat`：多个子树；
- `highlight`：对子树施加高亮；
- `alphabet`：对子树施加数学字母表转换；
- `delimiter`：带括号深度变化的特殊叶子；
- `atomic`：整个源码范围只能作为一个整体替换；
- `boundary`：给最后一个叶子提供明确的源码终点；
- `empty`：共享的空树。

### 3.1 叶子只保存 start，end 由下一个叶子决定

最初每个 atom 都保存完整 range。后来发现只保存起点就够了：

```text
leaf[i].end = leaf[i + 1].start
```

最后一个叶子的终点由 boundary 提供。

这个设计有几个好处：

- 命令名、花括号和被忽略的空格会自然被相邻叶子的范围吞掉；
- renderer 不需要不断维护重复的 end position；
- 输出粒度由叶子划分直接决定。

如果某段源码必须保持可见，则显式插入一个 `plain` 或 `reveal` leaf。也就是说，默认假设整段 math 都可以被覆盖，例外必须在树中明确表达。

### 3.2 为什么 highlight 是一个节点，而不是每个节点的字段

高亮被设计成对子树的修饰器：

```lua
Render.highlight(subtree, "Constant")
```

这样给一棵有 20 个 leaf 的树加高亮只需要创建一个 wrapper，不需要复制或修改 20 个 leaf。它也自然支持嵌套和结构共享。

如果把最终高亮直接存进每个 leaf，flatten 可能少经过一个 wrapper，但构造、复用和 style 的成本更高。当前 cursor 遇到 highlight 节点时只是更新上下文并继续向下，不会额外压入普通 concat frame，因此 wrapper 的实际成本很低。

### 3.3 plain、reveal、replace 和 insert

RenderTree 的叶子 mode 用来区分输出语义：

- `replace`：conceal 对应源码并显示虚拟文本；
- `plain`：保留原源码，通常用于普通数学文本；
- `reveal`：因为失败或交互而明确显示源码；
- `insert`：不吞掉源码，只在锚点插入显示内容。

这些 mode 使用字符串而不是压缩成数字 enum。Lua 中相同字符串通常会驻留复用，而且这里的性能差异不值得牺牲调试可读性。

## 4. extmark 粒度：不要过早合并

一个大 extmark 通常比很多小 extmark 便宜，但交互效果更差。例如 flash.nvim 需要对显示后的局部位置进行跳转：如果整个命令只有一个 extmark，其他插件插入的 extmark 容易被整体虚拟文本挤到末尾。

因此普通命令尽量保留细粒度 leaf：

- 每个 leaf 可以生成自己的 extmark；
- 原始文本 leaf 可以完全不 conceal；
- 光标进入时可以只 reveal 一个 leaf。

但参数重排和重复是例外。例如：

```tex
\swap{A}{B}
\duplicate{A}
```

显示顺序与源码顺序不同，或者同一个源码参数需要显示多次。此时无法同时保证：

- 显示结果正确；
- 源码映射单调；
- flash.nvim 对每一份显示都有独立、正确的源码位置。

第一版对自定义命令采用 atomic 是更诚实的选择：整个调用由一个 extmark 拥有。对于重复参数，可以让第一次出现保留源码映射，后续出现视作生成内容；但这属于未来可选的细化策略。

## 5. flatten 遍历优化

最初 flatten 使用一个 stack，每遇到节点就压入一个包含 node、highlight、alphabet 等字段的临时对象。这会产生很多短命 Lua table。

后来改成 parent + child index cursor：

```text
parents[depth]
indices[depth]
parent_highlights[depth]
parent_alphabets[depth]
```

每次从 parent 取下一个 child，并更新 index。stack 大小只与树深度有关，而不与总节点数有关。highlight 和 alphabet wrapper 可以直接尾递归式向下，不必创建 frame。

基准结果：

| 场景 | 修改前 | parent/index cursor | 改善 |
|---|---:|---:|---:|
| 1000 leaf 深树 flatten | 约 193–194 ms | 约 112–114 ms | 约 42% |
| 宽多叉树 flatten | 约 142–144 ms | 约 92–93 ms | 约 35% |

真实公式的总耗时改善没有这么夸张，因为 flatten 之外还有 Tree-sitter、字符串转换和 extmark API 等成本。但这个优化局部收益明确，而且没有损害结构。

### 5.1 尝试让 concat 自身充当 child 数组

我们还试过把 concat 节点写成混合 table：元数据放哈希字段，children 直接放数组部分，从而省掉一层 `children = { ... }`。

结果并不稳定：

- 宽树略有收益；
- 深二叉树反而慢约 4%；
- 调试打印明显更难读；
- `#parent` 在混合 metatable table 上没有表现出预期优势。

因此最终撤回，保留：

```lua
{
    kind = kind.concat,
    children = { ... },
}
```

这是一个很典型的结论：少一个 table 不等于整体更快，尤其当它让热循环中的访问形式变差时。

## 6. position 表是否值得压缩

早期每个位置使用：

```lua
start = { row, col }
```

后来复制一份实现，改成：

```lua
row = row,
col = col,
```

纯构造基准大约快 4%，完整 build + emit 只快约 1%。提升不大，但字段更直接，也减少大量小位置 table，因此保留了标量字段设计。

这个实验也提醒我们：

> 微观对象布局可以测，但应该看端到端结果；4% 的局部收益可能只对应 1% 的整体收益。

## 7. style：不要在 render 前后反复扫描

旧思路是在树构造完成后调用 `try_style`，它需要重新 flatten 或遍历整棵树。我们探索过：

- 给树维护 `style_mask`；
- 第一次 `try_style` 时缓存不同 style 的结果；
- 为 requested style 和 plain 结果各保存一棵树；
- 在展开命令时携带 style request；
- 在 renderer 已知目标 style 时边展开边检查。

这些方案有些能提高长字符串的重复 style 性能，但字体命令和上下标通常很短。为了几个字符维护两套树、mask 或复杂缓存，会增加大量状态和失效逻辑。

最终保留的简单策略是：

- 普通 style 用一个 wrapper；
- 必须成功的字符转换使用 `try_transform`；
- renderer 已知某段需要哪种转换时立即尝试；
- 不为短 style 结果维护双树缓存。

### 7.1 字体命令必须严格失败

对于 `\mathbb`，最终规则是所有字符都必须能映射，否则整条命令显示源码：

```tex
\mathbb{R}        % 支持
\mathbb{R_2}      % 不支持，应该写成 \mathbb{R}_2
\mathbb{R+R}      % 不支持，应该分别作用于两个 R
\mathbb{\unknown} % 不支持
```

这样不会为了隐藏命令而掩盖不规范或未知输入。

字体 style 采用覆盖语义；script 是为了显示效果模拟出来的 style，优先级更低；只改变 highlight 的 `\mathbf` 一类则不必参与字符 style 冲突。

## 8. 从“每个 command render”改成“每个 math render 一次”

旧 concealer 按命令调用 renderer。新 RenderTree 已经能保留细粒度 leaf，因此不再需要靠多次 renderer 调用维持 extmark 粒度。

现在一整个 math environment 只 render 一次：

```text
math TS subtree
    -> renderer.render_node(...)
    -> one RenderTree
    -> flatten
    -> many fine-grained extmarks
```

好处包括：

- delimiter 深度可以在一次 flatten 中连续计算；
- style 和参数结构不会跨 renderer 调用丢失；
- 少了重复的入口、状态和小对象；
- 光标交互仍然能精确到 leaf。

对于没有自定义命令的常见公式，整体 render 至少没有性能退化，并且入口逻辑明显简单。

## 9. 多行公式与缩进

如果一个替换范围跨行，直接用一个 extmark conceal 整段源码会吃掉后续行缩进，导致显示错位。

最终把这个问题推迟到 flatten/emit 阶段处理：

- 如果两个 leaf 之间换行，后一个 leaf 自然从自己的源码起点开始；
- 如果单个 leaf 跨行，把显示文本放在第一行；
- 后续行只 conceal 非缩进字符；
- continuation extmark 不携带虚拟文本；
- 行首空白保持原样。

这比 renderer 为每个跨行命令手工插 boundary 更可靠，因为换行和实际 buffer 文本只在 emit 阶段才完全明确。

## 10. delimiter 不再依赖全局 State

数学环境中的旧 State 主要承担 delimiter 深度和自定义命令 placeholder。自定义命令计划改成 ArgRef 后，通用 State 的意义大幅下降。

delimiter 改成三种直接接口：

```lua
Render.delim_open(...)
Render.delim_middle(...)
Render.delim_close(...)
```

每个 delimiter leaf 保存 flatten 前后的深度变化。flatten 时维护当前 depth，并生成 rainbow highlight。调用者保证 open/close 成对；少数特殊情况仍可使用通用 delimiter 构造器。

这个设计比 scope 对象简单，而且覆盖了绝大多数 LaTeX 显示结构。

## 11. 命令模板 API

旧 concealer 中已经有一些好用的模板，例如 `style`、`delim` 和参数 adapter。它们被迁移成建立 RenderTree 的高层命令 API：

```lua
Command.highlight(highlight)
Command.transform(map, highlight)
Command.accent(suffix, highlight)
Command.style(map, highlight)
Command.alphabet(map, highlight)
Command.delimited(left, ..., right)
Command.optional(narg, default, render)
Command.create(narg, render, options)
```

普通命令可以很短：

```lua
renderer.register_command(
    "mathbb",
    Command.alphabet(mathstyle.mathbb, hl.symbol)
)

renderer.register_command(
    "abs",
    Command.delimited("|", "|")
)
```

`frac`、`sqrt` 等复杂命令仍然可以直接使用底层 `render(args, context)`。

注册命令时会缓存 adapter，不再在每次 render 时临时创建闭包。这里也验证了一个容易误解的问题：闭包本身不是主要问题；真正浪费的是在热路径上为同一个 spec 重复创建闭包。注册时创建一次并复用就足够了。

## 12. 自定义命令：闭包、树 IR、Lua 源码还是后缀操作表

我们比较了几种 `\newcommand` 编译方式：

1. 每次调用时重新解释 Tree-sitter 定义树；
2. 为定义中的每一层生成 Lua 闭包；
3. 编译成嵌套 table IR；
4. 生成 Lua 源码再 `load`；
5. 编译成类似逆波兰表达式的扁平操作表。

生成 Lua 源码可能得到很快的执行速度，但维护、调试、安全边界和错误定位成本都过高，因此暂时排除。

扁平操作表只需要少数指令：

```text
OP_CONSTANT
OP_ARGUMENT
OP_CALL
OP_CONCAT
```

例如：

```tex
\newcommand{\demo}[2]{\mathbb{#1}+#2+#1}
```

可以编译为一张后缀程序表。执行器使用一个栈：遇到参数就压入实际 RenderTree，遇到 CALL 就弹出参数并调用已注册 renderer，遇到 CONCAT 就合并栈顶若干树。

已经验证：

- 定义只需编译一次；
- 同一程序可以用不同参数反复执行；
- 嵌套调用模板可行；
- 同一个 `#1` 可以重复引用；
- 执行不会修改操作表；
- 最终结果可以包装为一个 atomic RenderTree 并生成单个 extmark。

目前这仍是经过测试的 demo，尚未完全接管生产中的导言区 `newcommand` 注册。下一步是把编译后的 Program 缓存在定义节点对应的缓存项中，并在该定义变脏时单独替换。

## 13. 光标交互：从整条公式取消 conceal 到逻辑 reveal

旧行为是：只要光标进入需要 conceal 的 math 节点，就删除整个节点的 extmark。公式会突然完全展开，跳动很大。

第一种改进是只 reveal 光标所在 leaf。进一步又加入了 renderer 驱动的逻辑策略：renderer 最清楚哪些源码片段属于同一个命令结构，因此不应该让 flatten 反向猜测。

`RenderContext` 只额外传入：

```lua
context.cursor = { row, col }
```

当前策略是：

- 普通 leaf：只 reveal 光标所在 leaf；
- `highlight`、`transform`、`accent`、`style`、`alphabet`：
  - 光标在参数内，只 reveal 命中的参数 leaf；
  - 光标在命令名或花括号上，只 reveal 命令外壳；
- `delimited` 和 `frac`：
  - 光标在参数内，外层 delimiter 保持正常显示；
  - 光标在任一结构片段上，open/middle/close 全部 reveal，并保留 rainbow 高亮；
- `sqrt` 和上下标具有各自的外壳策略；
- 未声明 cursor 策略的底层 renderer 保守地整条 reveal；
- atomic 自定义命令只能整体 reveal。

例如光标进入 `\frac{\alpha}{\beta}`：

- 在 `\alpha` 上时只展开 `\alpha`；
- 外层 fraction 仍显示为括号和斜线；
- 在 `\frac`、`}{` 或最后的 `}` 上时，三段 fraction 结构同时恢复源码并高亮；
- `\alpha` 和 `\beta` 仍保持各自的 conceal 状态。

CursorMoved 不需要重画所有公式。processor 保存上一次交互 RenderTree 产生的 extmark id：

1. 删除上一次交互树的 extmark；
2. 它在正常 viewport 遍历中恢复普通 conceal；
3. 当前光标所在 math 重新 render，并把 cursor 放入 context；
4. 其他已有公式保持原 extmark。

因此每次光标移动只需要真正重算旧位置和当前位置涉及的 math tree。

## 14. 哪些尝试最终没有保留

以下方案都提供了有价值的信息，但最终没有进入主设计：

### 14.1 为所有层级建立 Lua child index

索引和 sibling 查询本身也有成本。对于普通 LaTeX 文件，全面复制 Tree-sitter 底层索引不一定划算。保留范围定位和顺序 cursor 更简单。

### 14.2 concat 节点直接使用自身数组部分

省了一张 children table，但深树性能略退化，打印也更难看，因此撤回。

### 14.3 可变双端 RenderTree

拼接方便，但所有权、复用和缓存语义变复杂。不可变多叉树已经足够快。

### 14.4 为 style 保存 requested/plain 两棵树

理论上可以空间换时间，但实际字体和上下标通常很短，属于过度优化。

### 14.5 为每个 style 维护 mask 和多份缓存

会把简单的短字符串转换变成复杂的缓存失效问题，整体收益有限。

### 14.6 生成并即时编译 Lua 源码

性能潜力存在，但维护成本高于当前需求。扁平操作表更容易检查、序列化和测试。

### 14.7 所有命令都合并成一个 extmark

extmark 数量更少，但破坏 flash.nvim 等工具需要的显示粒度。只对无法保持单调源码映射的命令使用 atomic。

## 15. 最重要的工程结论

### 15.1 先改变工作量，再优化循环

只处理 viewport、拆分导言区生命周期、每个 math 只 render 一次，这些结构性变化通常比把某个 Lua 循环优化 10% 更重要。

### 15.2 数据结构要同时服务性能和语义

RenderTree 的价值不只是拼接更便宜。它同时解决了：

- style 的作用域；
- delimiter 深度；
- extmark 粒度；
- reveal/plain/replace 的区别；
- atomic 命令；
- 光标交互；
- 自定义命令的预编译目标。

如果一个优化后的结构只能让 benchmark 更快，却让这些语义更难表达，它很可能不是正确的抽象。

### 15.3 不可变并不等于慢

不可变多叉树避免了大数组重复复制，又允许结构共享。只要 flatten 使用合适的 cursor，它可以接近可变 append 的实际性能。

### 15.4 不要为短数据建立复杂缓存

字体和上下标大多只有几个字符。缓存两棵树、style mask 或大量预计算结果，可能比直接遍历更贵，也更难保证正确。

### 15.5 benchmark 必须覆盖不同树形

只测宽树会认为“concat 自身做数组”很好；加入深二叉树后才能看到退化。至少应该分别测试：

- 深树；
- 宽树；
- 常见真实公式；
- 构造；
- flatten；
- build + emit 的端到端成本。

### 15.6 可读性本身也是性能优化的约束

一个只快几个百分点但让打印、调试和不变量更难理解的结构，通常不值得保留。我们撤回 concat 自身数组方案，就是因为收益不稳定，而 `children` 字段能显著降低维护成本。

## 16. 当前状态

已经落地并经过测试的部分：

- viewport 范围处理和有限 lookbehind；
- 导言区扫描与正文 conceal 分离；
- 每个 math environment 只调用一次新 renderer；
- 不可变多叉 RenderTree；
- parent/index flatten cursor；
- 标量 row/col；
- 多行 replacement 分段；
- delimiter 深度在 flatten 时解析；
- 高层命令模板和底层 renderer 逃生口；
- 注册时缓存 command adapter；
- renderer 驱动的 cursor reveal；
- 自定义命令后缀操作表接入生产渲染，支持可选参数、重复参数、前向引用及嵌套调用；
- buffer 级命令定义和 parser signature 隔离，重新扫描时移除旧定义；
- 每个 buffer 独立防抖，正文 changedtick 变化时清理旧显示；
- toggle、滚动、窗口切换及 buffer detach 生命周期回归测试；
- 不完整命令保留公式结束符，递归展开和递归默认参数有深度限制。

仍适合继续推进的部分：

- 以定义节点为单位缓存和失效，而不是导言区整体重建；
- 根据真实大文档 profile 决定是否还需要更底层的 Tree-sitter child 定位 API；
- 为 atomic 自定义命令研究可选的“第一次参数映射、后续参数生成”策略。

这次重构最有价值的结果不是某一个 benchmark 数字，而是得到了一条清晰的边界：Tree-sitter 管语法，renderer 管语义，RenderTree 管显示结构，flatten 管最终布局，processor 管更新范围。每一层只做自己真正知道的事情，性能优化也因此更容易测量、撤回和继续演进。


## 17. 模块职责整理

- `parser/latex_nodes.lua` 负责命令名、环境名、分组标记和源码边界定位。
- `parser/init.lua` 负责逻辑子节点与 optional-first 参数布局；可选参数缺失时使用显式 count 遍历。
- `conceal/definitions.lua` 收集和校验导言区定义，先注册所有签名再编译，并管理定义的清理。
- `conceal/command.lua` 提供命令模板、默认参数求值和共享的上下标显示语义。
- `conceal/command_program.lua` 负责编译和执行指令，复用命令模板，不单独实现字体或上下标策略。
- `conceal/renderer.lua` 负责从语法节点生成显示树和源码 reveal 策略。
- `conceal/processor.lua` 负责可视范围遍历及交互 extmark 复用，不再保留旧 virtline 光标路径。
- `conceal/init.lua` 负责 buffer/window 生命周期和刷新调度。

必要注释保留在半开区间、稀疏参数槽、VM 空槽哨兵、前向引用的两阶段编译和 atomic 源码归属等约束附近。
