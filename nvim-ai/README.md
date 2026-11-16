# nvim-ai

基于 LazyVim 插件框架、但**按键/缩进/行为完全独立**的 Neovim 配置，面向大型 C/C++ 代码库。

- 保留 `~/.vimrc` 的高频键位。
- GNU GLOBAL 索引：定义 / 引用 / 符号 / 文本 / callers / callees。
- `agentic.nvim` ACP 多智能体 + `aicx mcp` 代码检索工具。
- 在线优先、断网回退离线包。

## 部署

```sh
# 配置源
<repo>/nvim-ai
# 部署位置(NVIM_APPNAME=nvim-ai)
~/.config/nvim-ai
# 启动器
~/.local/bin/nvim (aivim 兼容)
```

日常用 `nvim` 启动（wrapper 设置 `NVIM_APPNAME=nvim-ai`）；旧的 `~/.config/nvim` / LazyVim 配置完全不动。

## 设计原则

- 不继承 LazyVim 的按键、缩进、插件默认行为；所有冲突项显式覆盖。
- leader `;`，localleader `\`。
- C/C++/Makefile 强制 8 宽 tab、`noexpandtab`。
- 无 LSP 诊断；高亮靠 treesitter，导航靠 GLOBAL。
- 不自动格式化。
- 顶部 bufferline 只显示“序号 + 文件名”。
- `mouse=a`，AI chat / quickfix / help 可用滚轮。
- `<C-\>` 智能定义：1 个直接跳，多个列表。

## 目录结构

```
init.lua
lua/config/{lazy,options,keymaps,autocmds}.lua
lua/aivim/{workspace,index,blink}.lua
lua/plugins/{lazyvim,colorscheme,treesitter,editor,legacy,completion,lsp,ai,bufferline}.lua
tools/aicx.py            # 索引器 + MCP server
scripts/check.lua        # 按键/选项审计
KEYMAPS.md
docs/mcp.md
```

## 索引

### 自动识别

打开文件时按路径向上找工程根，自动选择 profile：

- 普通 C/C++ 工程
- 平台类 repo
- 内核/驱动类树（可选支持，不是硬约束）

没有索引时后台建库，不阻塞编辑；建库写临时目录，成功后原子替换。

项目级可用 `.aivim-index.json` 覆盖：

```json
{
  "profile": "generic-c",
  "arch": "all",
  "include": ["src", "include"],
  "exclude": ["**/build/**", "**/out/**"],
  "extensions": [".c", ".h", ".cc", ".cpp", ".hpp"]
}
```

### 命令

```vim
:IndexBuild [path]      " 自动识别并建/重建
:IndexUpdate            " 立即增量
:IndexStatus            " 查看 root/profile/arch/文件数/库大小/时间
:IndexCancel            " 取消当前建库
:IndexClean [--all]     " 清理缓存
```

CLI：

```sh
python3 ~/.config/nvim-ai/tools/aicx.py workspace detect --json <path>
python3 ~/.config/nvim-ai/tools/aicx.py index build <path> --json
python3 ~/.config/nvim-ai/tools/aicx.py index update <path> --json
python3 ~/.config/nvim-ai/tools/aicx.py index status <path> --json
python3 ~/.config/nvim-ai/tools/aicx.py query refs <symbol> --path <file>
```

索引缓存：`~/.cache/nvim-ai/index`，不写源码树。保存后后台增量；新增/删除文件重建文件列表。

示例规模：大型工程 60k 文件约 50s / 1.8GB，增量约 5s；中型 30k 约 30s / 400MB。quickfix 单次最多 5000 条。

## AI 智能体

默认 provider 是 Claude Code，已安装：

- `claude-agent-acp`
- `@agentclientprotocol/codex-acp`
- 可选：`gemini`、`opencode-ai`

`agentic.nvim` 复用 CLI 已有登录/环境变量，不在配置里保存 API key。

### `;i` 键位

| 键 | 作用 |
|---|---|
| `;it` / `;ic` | 打开/切换 Agent 面板（默认 Claude） |
| `;iP` | 选择 provider |
| `;iR` / `;ir` | 新会话 / 恢复会话 |
| `;is` | 发送可视选区 |
| `;ib` | 当前文件加入上下文 |
| `;ia` | 当前函数加入上下文（只带函数体） |
| `;ie` | 解释当前函数（自动提问，只带函数体） |
| `;iE` | 解析当前文件（自动提问，不塞整个文件） |
| `;ix` | 解释选中代码（visual，自动提问，>800 行拦截） |
| `;id` | 当前 buffer 诊断加入上下文 |
| `;iS` | 停止生成 |
| `;i?` | AI 键位帮助 |

面板内：`\s` 切 provider，`\m` 切 model，`\l` 会话列表，`]c`/`[c` 跳 diff。

Agent 的 cwd 使用工作区根，不是当前文件所在子目录。

## MCP（AI 读代码）

`aicx mcp` 是本地 stdio MCP server，工具：

- `workspace_info`
- `find_definition` / `find_references` / `find_symbol`
- `search_text` / `list_files`
- `read_file` / `git_diff`

注册示例：

```sh
claude mcp list
# aivim-gtags: python3 .../tools/aicx.py mcp - ✔ Connected

codex mcp list
# aivim-gtags ... enabled
```

详见 `docs/mcp.md`。

## 与 vimrc / 旧 LazyVim 的差异

| 项 | vimrc / 旧 LazyVim | nvim-ai |
|---|---|---|
| ctags 全树索引 | gutentags 每次重建，慢 | GNU GLOBAL 合并库，增量 |
| 查引用 | cscope 已移除 | `;gr` / `;gc` |
| `<C-\>` | `g<C-]>` 定义列表 | 智能：1 个直接跳，多个列表 |
| `;gs` | cscope symbol | 定义+引用合并去重 |
| `;gt` | cscope text | grep/rg |
| ALE | 全文件跑 gcc | 可配置忽略大型树，避免误报 |
| 缩进 | 视配置 | 8 宽 tab/noexpandtab（C/C++） |
| 鼠标 | 视配置 | `mouse=a`，支持滚轮 |

## 环境依赖与已处理的问题

- GNU GLOBAL 6.6.4（`gtags`/`global`）。
- Python 3.8+，`tools/aicx.py` 只用标准库。
- Node/npm 用于 ACP provider。
- tree-sitter CLI 可用；本包内提供兼容旧 glibc 的 0.22.6。
- 没有 `rg`/`fd` 时文本搜索回退 grep，文件列表回退 find。
- 旧 ctags/gtags 缓存不会被复制或删除；新缓存在 `~/.cache/nvim-ai`。

## 验收/自检

```sh
# 按键/选项审计(出现 MISSING 会返回非 0)
nvim --headless "+luafile ~/.config/nvim-ai/scripts/check.lua" +qa

# 工作区检测
python3 ~/.config/nvim-ai/tools/aicx.py workspace detect --json <path>

# agent 健康检查
nvim "+checkhealth agentic"

# MCP
claude mcp list
```

## 启动

```sh
nvim
nvim path/to/file.c
```
