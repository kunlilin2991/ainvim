# ainvim

AI 时代的 Neovim 配置 + 一键安装器，面向大型 **C/C++ 代码库**（普通工程、平台代码、内核/驱动类代码均可）。

保留 `~/.vimrc` 的高频按键习惯，同时提供：

- GNU GLOBAL 索引（定义 / 引用 / 符号 / 文本 / callers / callees）
- `agentic.nvim` ACP 多智能体（Claude Code / Codex / Gemini / OpenCode）
- `aicx mcp` 把 gtags 能力暴露给 agent，让 AI 能读代码
- 在线优先、断网回退离线包的一键安装

## 快速开始

```sh
cd ~/tmp/ainvim
./install.sh              # 启动时会询问是否离线
./install.sh --offline-bundle /path/ainvim-offline-*.tar.gz
```

安装完成后：

```sh
aivim
```

旧配置 `~/.config/nvim`、`~/.vimrc` 不会被改动；新配置使用独立 `NVIM_APPNAME=nvim-ai`。

## 安装器会做什么

| 依赖 | 在线 | 离线(外部包) |
|---|---|---|
| Neovim | 系统版本够就用；否则官方 0.11.5；glibc 不兼容时源码编译 | 由离线包提供 |
| LazyVim + 插件 | `lazy.nvim` 按 `lazy-lock.json` 安装 | 由离线包提供 |
| GNU GLOBAL | 系统包 `global`；否则源码编译 | 由离线包提供 |
| Node.js/npm | 系统 >=18；否则 Node 22 | 由离线包提供 |
| Claude Code / Codex / ACP | npm / 官方安装器 | 不在包内，脚本说明 |
| tree-sitter | 在线 | 由离线包提供 |
| MCP | 注册 `aivim-gtags` | 同左 |
| tmux 滚轮 | 追加透传配置 | 同左 |

系统基础工具（Python、git、tar、gzip、curl、gcc、make、xz）在线时由包管理器安装，离线时需预装。

### 离线安装

仓库不包含大文件。离线包单独获取：

```sh
# 方式 1:从 GitHub Releases 下载
#   https://github.com/kunlilin2991/ainvim/releases
# 方式 2:在联网机器安装后生成
./scripts/make-offline-bundle.sh
# 然后把 ainvim-offline-*.tar.gz 拷到目标机器
./install.sh --offline-bundle /path/to/ainvim-offline.tar.gz
```

## 目录

```
install.sh                 一键安装器
nvim-ai/                   完整 Neovim 配置
  lua/aivim/               工作区检测、GLOBAL 索引、blink 源
  lua/plugins/             LazyVim 覆盖、AI、bufferline、legacy 插件
  tools/aicx.py            索引器 + MCP server
  scripts/check.lua        按键/选项审计
bin/aivim                  启动器
tmux/nvim-ai-mouse.conf    tmux 滚轮透传
scripts/push-github.sh     安全推送脚本
REQUIREMENTS.md            需求与设计
README-INSTALL.md          详细安装说明
```

## 常用键

| 键 | 作用 |
|---|---|
| `<C-]>` | 跳定义 |
| `<C-\>` | 智能定义：1 个直接跳，多个列表 |
| `;gr` / `;gs` / `;gt` | 引用 / 符号 / 文本 |
| `;gc` / `;gd` | callers / callees |
| `;;w` / `;;W` | easymotion 词首（后 / 前） |
| `;;f` / `;;F` | easymotion 字符（后 / 前） |
| `;ie` / `;iE` / `;ix` | 解释函数 / 解析文件 / 解释选区 |
| `;ic` / `;iP` | AI 面板 / 选择 provider |
| `;1`…`;12`、`[b`/`]b` | 缓冲区 |
| `wn`、`;wl/wr/wj/wk` | 窗口 |
| `q`（quickfix 内） / `;gh` | 关闭 quickfix |

完整键位见 `nvim-ai/KEYMAPS.md`。

## 索引

```vim
:IndexBuild      " 建/重建
:IndexUpdate     " 增量
:IndexStatus     " 状态
:IndexClean      " 清理
```

索引缓存：`~/.cache/nvim-ai/index`，不写源码树。工作区自动识别；项目级配置可用 `.aivim-index.json` 覆盖。

## AI / MCP

```vim
;ic              " 打开 Agent 面板（默认 Claude）
;iP              " 选择 provider
;ie / ;iE / ;ix  " 自动解释
```

MCP：

```sh
claude mcp list   # aivim-gtags ... Connected
codex mcp list    # aivim-gtags enabled
```

详细见 `nvim-ai/docs/mcp.md`。

## 推送到 GitHub

仓库：`ssh://git@ssh.github.com:443/kunlilin2991/ainvim.git`

推荐使用 SSH。直接 SSH 可用时：

```sh
git push -u origin main
```

如果直连 SSH 被网络阻断、但环境有 `https_proxy`：

```sh
./scripts/push-github.sh
```

脚本会先尝试直连，失败后用 `scripts/ssh-proxy.py` 通过 HTTPS 代理建立 SSH 隧道；不写 `~/.ssh/config`、不保存 token。

也可以使用 HTTPS PAT（可选）：把 token 放到 0600 文件后，将 remote 改成 HTTPS 再 push。不要把 token 贴到聊天/命令/远程 URL。

## 安全

- 仓库不包含 API key、Claude/Codex 登录信息。
- MCP server 只读，限制在工作区内。
- 旧 `~/.config/nvim`、`~/.vimrc` 不动。
- 安装时旧配置备份为 `*.bak-<timestamp>`。
