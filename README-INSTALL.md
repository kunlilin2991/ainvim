# nvim-ai 离线安装包

这个目录是 `aivim` 的完整迁移包：配置、插件、tree-sitter、C/C++ 解析器、安装脚本都在里面。

## 一条命令安装

```sh
cd ~/tmp/ainvim
chmod +x install.sh
./install.sh
```

默认行为：

- 使用包内 `vendor/lazy.tar.gz` 安装全部插件（离线）
- 复制配置到 `~/.config/nvim-ai`
- 安装启动器 `~/.local/bin/aivim`
- 安装 `~/.local/bin/tree-sitter` 和 C/C++ 等解析器
- `npm i -g` 安装 Claude/Codex ACP adapters（需要网络）
- 注册 `aivim-gtags` MCP 到 Claude Code / Codex（本机执行，不联网）
- 如果存在 `~/.tmux.conf`，追加滚轮透传配置（让 Neovim 自己处理滚轮）
- 运行按键/选项自检

**旧的 `~/.config/nvim`、`~/.vimrc` 不会动。**

## 依赖安装策略

默认是**在线优先**，失败后再回退到包内 `vendor`：

| 依赖 | 在线 | 离线(`--offline`) |
|---|---|---|
| Neovim | 系统版本够就用；否则下载官方 0.11.5 到 `~/.local/opt/nvim`；官方二进制与 glibc 不兼容时自动源码编译 | 使用 `vendor/nvim-linux-x86_64.tar.gz`；旧 glibc 不兼容时无法编译，会明确提示 |
| GNU GLOBAL | 优先系统包 `global`；否则源码编译 6.6.4 到 `~/.local/opt/global` | 使用 `vendor/global-6.6.4.tar.gz` 源码编译（需要 gcc/make） |
| Node.js/npm | 系统 >=18 就用；否则下载 Node 22 到 `~/.local/opt/node` | 使用 `vendor/node-v22.23.5-linux-x64.tar.xz` |
| git/tar/gzip/curl/gcc/make/xz | 包管理器安装 | **不在包内**，需要系统预装 |
| Python >=3.8 | 包管理器安装 | **不在包内**，需要系统预装 |
| Claude Code | `npm i -g @anthropic-ai/claude-code` 或官方安装器 | **不在包内**（约 346MB 且需登录），会说明 |
| Codex CLI | `npm i -g @openai/codex` | **不在包内**，会说明 |
| ACP adapters | npm 在线安装 | **不在包内**，会说明 |
| Neovim 插件 | `Lazy! sync` + `Lazy! restore`；失败回退 vendor | 使用 `vendor/lazy.tar.gz` |
| tree-sitter/解析器 | 包内优先；其他架构在线 | 使用包内 `vendor/tree-sitter` + `vendor/parser` |

说明：

- 脚本会尝试 `sudo`（密码免输或交互输入）；没有 sudo/root 时，Neovim/Node/GLOBAL 会尽量装到 `~/.local`。
- 官方 Neovim 二进制可能需要 glibc >= 2.34；不兼容时会尝试源码编译（需要联网和 cmake/ninja/gettext）。
- 完全离线且系统缺少 Python/gcc/make 等基础工具时，无法从包内补齐，脚本会明确列出缺失项和手动安装命令。

## 安装前系统依赖

| 依赖 | 说明 |
|---|---|
| Neovim >= 0.11.2 | 必须 |
| Python >= 3.8 | `aicx.py` 只用标准库 |
| GNU GLOBAL (`gtags`/`global`) | 索引必须 |
| git、tar | 安装/解压 |
| Node.js + npm | ACP adapters；没有会跳过 AI 部分 |
| cargo（可选） | 包内 tree-sitter 不可用时才需要 |

系统包安装示例：

```sh
# Debian/Ubuntu
sudo apt install global python3 git tar

# Fedora
sudo dnf install global python3 git tar

# Arch
sudo pacman -S global python3 git tar
```

Neovim：发行版自带版本可能太旧，建议用官方 AppImage 或源码安装。

## 可选参数

```sh
./install.sh --online        # 不用包内插件,从网络按 lazy-lock 安装
./install.sh --offline       # 完全离线:不装 npm ACP adapters
./install.sh --no-ai         # 不装 Claude/Codex ACP adapters
./install.sh --no-mcp        # 不修改 Claude/Codex 的 MCP 配置
./install.sh --no-plugins    # 只装配置和工具
./install.sh --no-tmux       # 不改 ~/.tmux.conf 的滚轮透传
./install.sh --skip-deps     # 缺系统依赖也继续
./install.sh --index PATH    # 安装后为 PATH 建 gtags 索引
./install.sh --dry-run       # 只打印动作,不修改
```

## 安装后

```sh
aivim                 # 启动新配置
aivim path/to/file.c  # 打开文件,首次会自动检测/建索引
```

常用命令：

```vim
:AivimDiag     " 查看版本/模块/工作区/tagfunc
:AivimReload   " 热重载索引、键位、autocmds、bufferline
:IndexStatus   " 当前工作区索引状态
:IndexBuild    " 建/重建索引
:IndexUpdate   " 立即增量
:IndexClean    " 清理当前工作区缓存
```

MCP 检查：

```sh
claude mcp list    # aivim-gtags 应显示 Connected
codex mcp list     # aivim-gtags enabled
```

## 包内容

```
install.sh                 一键安装
nvim-ai/                   完整配置源码
bin/aivim                  启动器
vendor/tree-sitter.part-*  Linux x86_64 tree-sitter 0.22.6(分片)
vendor/parser/*.so         C/C++/Lua/Vim 等预编译解析器
vendor/lazy.tar.gz.part-* 全部 Neovim 插件(含 lazy.nvim,分片存储; install.sh 自动拼接)
vendor/nvim-linux-x86_64.tar.gz   Neovim 0.11.5 官方二进制(离线兜底)
vendor/node-v22.23.5-linux-x64.tar.xz.part-*  Node.js 22(分片; install.sh 自动拼接)
vendor/global-6.6.4.tar.gz GNU GLOBAL 源码(离线编译)
README-INSTALL.md          本文件
MANIFEST.txt               版本/内容清单
```

## 兼容性说明

- `vendor/tree-sitter` 和 `vendor/parser/*.so` 是 **Linux x86_64**、在本机 glibc 2.31 上构建的。
  - 其他机器同架构且 glibc >= 2.31: 可用。
  - ARM/其他系统: 安装脚本自动改为在线安装/用 cargo 编译。
- 解析器 ABI 与 Neovim 版本相关；如果目标机器 Neovim 版本差异较大，脚本会提示，你也可以在 Neovim 里运行 `:TSUpdate`。
- `~/.cache/tags` 等旧缓存不会被复制或删除；新索引缓存在 `~/.cache/nvim-ai`，需要在新机器上重建。
- 包内不包含任何 API key、Claude/Codex 登录信息、`.claude.json`、`~/.codex/config.toml`。

## 卸载

```sh
rm -rf ~/.config/nvim-ai ~/.local/share/nvim-ai ~/.local/state/nvim-ai ~/.cache/nvim-ai
rm -f ~/.local/bin/aivim ~/.local/bin/tree-sitter
# MCP 可选:
claude mcp remove aivim-gtags
codex mcp remove aivim-gtags
```

安装时的旧配置备份在 `~/.config/nvim-ai.bak-*`、`~/.local/bin/aivim.bak-*`。
