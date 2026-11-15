# Math conversion / 数学环境转换

`nvimtex.setup()` installs buffer-local normal-mode mappings in
`tex/plaintex/latex/markdown/rmd/quarto` buffers, including buffers already open
when setup runs:

`nvimtex.setup()` 自动在上述 filetype 的 buffer 中安装普通模式局部映射，
包括 setup 时已打开的 buffer：

| Mapping / 按键 | Action / 操作 |
| --- | --- |
| `m<C-a>` | Upgrade math / 升级数学环境 |
| `m<C-x>` | Downgrade math / 降级数学环境 |

The cycle is inline → display → equation → equation with aligned → align →
inline. Reverse conversion follows the opposite order. A count repeats the
operation: `2m<C-a>` advances two levels. Plain `<C-a>/<C-x>` keep their native
meaning outside a keyflow session. The LaTeX Tree-sitter parser is required;
Markdown also needs `markdown` and `markdown_inline` parsers.

循环顺序为行内 → 展示公式 → equation → equation 内嵌 aligned → align → 行内，
降级按相反方向循环。`2m<C-a>` 连续升级两级。keyflow 会话之外，单独的
`<C-a>/<C-x>` 保留原生行为。需要 LaTeX Tree-sitter parser；Markdown 另需
`markdown` 和 `markdown_inline`。

## Configuration / 配置

```lua
require("nvimtex").setup({
  surround = {
    keyflow = false, -- default / 默认
    keymaps = {
      upgrade_math = "m<C-a>",
      downgrade_math = "m<C-x>",
    },
  },
})
```

Set `surround = false` to disable this feature's automatic mappings. Set either
key to `false` to disable that direction, or supply another nonempty mapping:

`surround = false` 关闭这部分自动映射；单个 key 设为 `false` 可禁用一个方向，
也可以指定其他非空按键：

```lua
require("nvimtex").setup({
  surround = {
    keymaps = { upgrade_math = "g+", downgrade_math = false },
  },
})
```

Configure at startup. Re-running setup does not restore mappings already
installed in existing buffers. `surround = false` does not disable Pairwise's
independent textobject/surround registrations; those are controlled by
`textobject`. Direct `require("nvimtex.surround").upgrade_math()` and
`downgrade_math()` remain available without automatic mappings.

请在启动时配置；重复 setup 不会恢复已安装的 buffer 映射。`surround = false`
不影响 Pairwise 的独立 textobject/surround 注册，后者由 `textobject` 选项控制。
关闭自动映射后仍可直接调用 `upgrade_math()`、`downgrade_math()`。

## Optional keyflow / 可选 keyflow

Keyflow is disabled by default and is not loaded for normal mappings. After
installing a version exposing `require("keyflow").mode(spec)`, enable it:

默认关闭 keyflow，普通映射不会加载它。安装提供新版 `mode(spec)` 接口的
keyflow 后，可显式开启：

```lua
require("nvimtex").setup({ surround = { keyflow = true } })
```

Press `m<C-a>` or `m<C-x>` (or your custom mapping) to convert and enter the
exclusive input session. Continue with `<C-a>/<C-x>`; counts work in the session.
Escape exits; other keys exit and pass through to Neovim. If a direction is
disabled, it is also absent from the transient mode. A failed conversion exits
the session. Enabling this option requires keyflow to be available at setup.

按默认或自定义入口键完成一次转换并进入独占输入会话，之后可直接按
`<C-a>/<C-x>`，会话内也支持计数。Escape 退出，其他键退出并交回 Neovim。
禁用的方向不会加入会话；转换失败也会退出。显式开启时，keyflow 必须在 setup
时可用。

Remove any old hand-written math mode registration using `keyflow.mode.new`;
nvimtex now owns these mappings. This setting does not configure your other
keyflow modes or Pairwise's optional keyflow integration.

请移除个人配置中使用旧 `keyflow.mode.new` 注册数学模式的代码，由 nvimtex
统一管理这些按键。该选项不配置其他 keyflow 模式或 Pairwise 的 keyflow 整合。

## Behavior / 行为

Conversion uses the existing formatter: aligned/align forms split relation
operators and normalize layout. It is a formatting operation, not a promise of
whitespace-preserving delimiter replacement. Unknown environment types and
unsupported align layouts are left unchanged with a notification. The operation
returns `true` only when text changed. Parser selection is explicit for TeX
buffers and includes LaTeX injections for Markdown.

转换沿用现有 formatter，aligned/align 形式会按关系运算符拆分并规范排版，
不保证只替换边界、原样保留空白。不支持的环境类型或对齐布局会提示并保留原文。
只有完成修改才返回 `true`。TeX buffer 显式选择 LaTeX parser，Markdown 查找
包含 LaTeX 注入区域。
