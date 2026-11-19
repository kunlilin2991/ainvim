# nvim-ai 键位速查

Leader 为 **`;`**，localleader 为 **`\`**。以下 `<leader>` 即 `;`。

## 一、基础编辑

| 键位 | 作用 | 模式 |
|---|---|---|
| `le` / `lb` | 行尾 / 行首 | n/x/o |
| `;w` | 保存 | n |
| `;wq` | 保存全部并退出 | n |
| `;W` | sudo 保存 | n |
| `;Q` | 关闭当前 buffer（`:bd`） | n |
| `;y` / `;p` | 系统剪贴板（vimrc 中为注释，默认不启用） | — |
| `;sp` | paste 切换（`:set invpaste`） | n |
| `;/` | 清除搜索高亮 | n |
| `;.` | 重复上一条命令行命令 | n |
| `;m` | 配对符跳转（`%`） | n |
| 鼠标滚轮 | 所有窗口可滚动（`mouse=a`；vimrc 原为 `mouse=c`） | — |

## 二、缓冲区 / 窗口 / 页面

| 键位 | 作用 |
|---|---|
| `;1` … `;12` | 跳到第 N 个 buffer（BufferLine；顶部序号与之一致） |
| `[b` / `]b` | 上一个 / 下一个 buffer |
| `;Q` | 关闭当前 buffer |

> 顶部 bufferline 只显示「序号 + 文件名」：无文件类型图标、无诊断、无修改点、无关闭 `x`。序号是 ordinal，和 `;1`…`;12` 对应。
| `wn` | 窗口循环（`<C-w><C-w>`） |
| `<C-w>h/j/k/l` | 窗口跳转（normal **和 terminal** 模式都可用） |
| `<C-w>w` | 窗口循环（normal 和 terminal 都可用） |
| `;wl` / `;wr` | 右 / 左窗口（保持 vimrc 的映射方向） |
| `;wj` / `;wk` | 下 / 上窗口 |
| `gt` / `gT` | 下一个 / 上一个 tab（原生） |

## 三、文件 / 结构

| 键位 | 作用 |
|---|---|
| `;n` | 文件树（Neo-tree toggle） |
| `;f` | 模糊查找文件（LazyVim picker） |
| `;a` | 头文件 / 源文件切换（a.vim `:A`） |
| `F9` / `;tb` | 结构大纲（Aerial，treesitter） |
| `;td` | TODO / FIXME / HACK / NOTE / WARN / MODIFY 列表（Trouble） |
| `;bm` | git blame 当前行（gitsigns） |
| `F8` | 缩进线开关（indentLine） |

## 四、索引 / 语义查询

| 键位 | 作用 | 实现 |
|---|---|---|
| `<C-]>` | 跳到定义（唯一时直接跳） | `tagfunc` → `global -d` |
| `<C-\>` | **1 个定义直接跳；多个定义才列表选择** | `aivim.index.definition()` |
| `<C-t>` | 弹出 tag 栈 | 原生 |
| `<C-o>` / `<C-i>` | jumplist 后退 / 前进 | 原生 |
| `;gg` | 定义 | `global -d` → quickfix |
| `;gr` | 引用（谁用了它） | `global -r` → quickfix |
| `;gs` | 符号（定义 + 引用合并去重） | `global -d` + `-r` |
| `;gt` | 文本查询 | grep/rg（不用 `global -g`） |
| `;ge` | egrep（输入正则） | grep/rg |
| `;gf` | 文件 | `global -P` |
| `;gi` | include 查询 | grep/rg |
| `;gc` | callers（调用它的地方） | grep `\bword\s*\(` |
| `;gd` | callees（当前函数调用的函数） | treesitter + 选择跳转 |
| `;ga` | 赋值位置 | grep `\bword\s*=` |
| `;gz` | extra/symbol | 同 `;gs` |
| `;gh` | 关闭 quickfix 窗口 | `:cclose` |
| `q`（quickfix 内） | 关闭 quickfix 窗口 | buffer-local `:cclose` |
| `;jd` / `;jc` | 跳定义 / 定义列表 | `:tag` / `:tselect` |

> GLOBAL 的 `-r` 会把头文件里的声明也算作引用；需要只看调用点时用 `;gc`。
>
> 索引还没建好时，`<C-\>` / `<C-]>` 会先用 grep 找顶层定义兜底，不会报 `E987`；建完后自动走 GLOBAL。

## 五、easymotion

| 键位 | 作用 | 模式 |
|---|---|---|
| `<leader><leader>w` | 词首跳转（**向后**，双字符标签） | n/x/o |
| `<leader><leader>W` | 词首跳转（**向前**） | n/x/o |
| `<leader><leader>f` | 字符跳转（**向后**，输入字符后出标签） | n/x/o |
| `<leader><leader>F` | 字符跳转（**向前**） | n/x/o |

## 六、编辑增强

| 键位 | 作用 | 模式 |
|---|---|---|
| `;cc` | 注释 | n/x |
| `;cu` | 取消注释 | n/x |
| `;cn` | 嵌套注释 | n/x |
| `;cA` | 行尾添加注释 | n/x |
| `<Enter>` | 对齐（EasyAlign） | x |
| `<C-k>` / `<C-j>` | 上一个 / 下一个 ALE 错误 | n |

## 七、AI / Agent（前缀 `;i`）

| 键位 | 作用 |
|---|---|
| `;it` / `;ic` | 打开/切换 Agent 面板（默认 Claude） |
| `;iP` | 选择 provider（Claude / Codex / Gemini / OpenCode） |
| `;iR` | 新会话 |
| `;ir` | 恢复会话 |
| `;is` | 发送可视选区（visual） |
| `;ib` | 当前文件加入上下文（Referenced Files） |
| `;ia` | 当前函数加入上下文（只带函数体） |
| `;ie` | 解释当前函数（自动提问，只带函数体） |
| `;iE` | 解析当前文件（自动提问，不塞整个文件） |
| `;ix` | 解释选中代码（visual，自动提问，>800 行会拦截） |
| `;id` | 当前 buffer 诊断加入上下文 |
| `;iS` | 停止生成 |
| `;i?` | AI 键位帮助 |

面板内：`\s` 切 provider、`\m` 切 model、`\l` 会话列表、`]c`/`[c` 跳 diff。

## 八、补全（blink.cmp）

| 键位 | 作用 |
|---|---|
| `<CR>` | 选中当前候选 |
| `<C-n>` / `<C-p>` | 下一个 / 上一个 |
| `<Tab>` / `<S-Tab>` | 展开片段 / 反向，或下一个/上一个 |
| `<C-j>` / `<C-k>` | 片段占位符向前 / 向后 |

来源：gtags 符号 + buffer + 片段 + 路径（无 LSP）。

## 九、索引命令

| 命令 | 作用 |
|---|---|
| `:IndexBuild [path]` | 自动识别并建/重建当前或指定工作区 |
| `:IndexUpdate` | 立即增量 |
| `:IndexStatus` | 查看工作区/文件数/库大小/时间 |
| `:IndexCancel` | 取消当前建库 |
| `:IndexClean [--all]` | 清理缓存 |
