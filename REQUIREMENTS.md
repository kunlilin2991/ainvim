# ainvim 需求与设计

## 1. 目标

一套 AI 时代的 Neovim 配置与安装器，面向 **C/C++ 代码库**：

- 保留 `~/.vimrc` 的高频按键习惯。
- 快速跳定义、查引用、查符号/文本/调用者，不依赖 LSP/CMake/`compile_commands.json`。
- 调用多种 AI agent（Claude Code、Codex、Gemini、OpenCode 等），并让 agent 通过 MCP 读取代码。
- 全新机器一条命令安装；联网优先，断网回退仓库内离线包。

## 2. 适用代码库

任意 C/C++ 工程都可使用。内置工作区自动识别与 profile 机制，大型平台代码、内核/驱动类代码只是支持的场景之一，不是本工具的硬约束。

- 自动识别工程根与类型；不依赖固定路径。
- 项目级 `.aivim-index.json` 可覆盖 `profile`、`arch`、`include`、`exclude`、`extensions`。
- 一个工作区一个合并索引，缓存放在 `~/.cache/nvim-ai/index`，不写源码树。

## 3. 按键（必须保留）

- 行内：`le` 行尾、`lb` 行首。
- 保存/退出：`;w`、`;wq`、`;W`（sudo）、`;Q`（`:bd`）。
- 缓冲区：`;1`…`;12`、`[b`、`]b`、`;Q`。
- 窗口：`wn`、`;wl`、`;wr`、`;wj`、`;wk`。
- 搜索：`;/`、`;.`、`;m`。
- easymotion：`;;w` 向后词首、`;;W` 向前词首；`;;f` 向后字符、`;;F` 向前字符。
- 文件/结构：`;n`、`;f`、`;a`、`F9`/`;tb`、`;td`。
- 注释：`;cc`、`;cu`、`;cn`、`;cA`；可视 `<Enter>` 对齐。
- 编辑：`;sp`、`F8`、`;bm`、`<C-k>`/`<C-j>`。
- 语义：
  - `<C-]>` 直接跳定义。
  - `<C-\>` 智能版：1 个定义直接跳，多个列表选择。
  - `<C-t>` 弹栈；`<C-o>`/`<C-i>` jumplist。
  - `;gg` 定义、`;gr` 引用、`;gs` 定义+引用、`;gt` 文本、`;ge` egrep、`;gf` 文件、`;gi` include、`;gc` callers、`;gd` callees、`;ga` 赋值、`;gz` extra、`;gh` 关闭 quickfix。
- quickfix 窗口内 `q` 关闭窗口。

## 4. 索引

- 引擎：GNU GLOBAL（`gtags`/`global`），不依赖 LSP/CMake/编译数据库。
- 每个工作区一个合并库；自动识别根，缓存 `~/.cache/nvim-ai/index/<key>`。
- 首次后台建库；保存后增量；新增/删除重建文件列表。
- 建库期间 `<C-]>`/`<C-\>` 用 grep 顶层定义兜底，完成后走 GLOBAL。
- 命令：`:IndexBuild`、`:IndexUpdate`、`:IndexStatus`、`:IndexCancel`、`:IndexClean`。
- quickfix 单次最多 5000 条，超出标记 `[truncated 5000]`。

## 5. AI / MCP

- `agentic.nvim` + ACP：Claude Code、Codex、Gemini、OpenCode 等；复用 CLI 登录/API key。
- 前缀 `;i`：
  - `;ic`/`;it` 面板；`;iP` 选择 provider
  - `;ie` 解释当前函数（自动提交，只带函数体）
  - `;iE` 解析当前文件（自动提交，不塞整个文件）
  - `;ix` 解释选区（visual，自动提交，>800 行拦截）
  - `;ia`/`;ib`/`;is`/`;id` 加入上下文/诊断
  - `;iR`/`;ir`/`;iS`/`;i?` 新会话/恢复/停止/帮助
- `aicx mcp` 提供只读工具：`workspace_info`、`find_definition`、`find_references`、`find_symbol`、`search_text`、`list_files`、`read_file`、`git_diff`。
- 可注册到任意 MCP 客户端；仓库示例为 Claude Code / Codex。

## 6. 安装

- 一键脚本：`install.sh`。
- **在线优先**：安装系统基础工具、Neovim、GNU GLOBAL、Node、LazyVim/插件、AI CLI/ACP、tree-sitter、MCP、tmux。
- **离线兜底**：仓库不提交大文件；离线时通过 `--offline-bundle` 使用单独下载/生成的离线包（内含 Neovim、Node、GNU GLOBAL、LazyVim+插件、tree-sitter+解析器）。
- 离线限制：
  - 系统基础工具（Python/git/tar/gzip/curl/gcc/make/xz）需预装；
  - Claude Code / Codex / ACP adapters 不在离线包内，脚本会说明；
  - 旧 glibc 上官方 Neovim 二进制不兼容且无法编译时，脚本会明确提示。

## 7. 非目标

- 不针对特定项目/厂商/架构做硬编码约束；相关支持只是可选 profile。
- 不引入 LSP 诊断；高亮靠 treesitter，导航靠 GLOBAL。
- 不自动格式化代码。
- 不替换旧的 `~/.config/nvim`。

## 8. 验收

- `scripts/check.lua`：按键/选项审计 `missing=0`。
- `:IndexStatus`：workspace/profile/arch/indexed/files/size 正确。
- 在样本 C/C++ 工程上验证定义/引用查询。
- `;ie`/`;iE`/`;ix` 只带函数/选区。
- MCP 客户端能看到 `aivim-gtags` 工具。
- 鼠标滚轮在 Agentic Chat / quickfix / help 窗口可用。
