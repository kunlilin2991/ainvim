#!/bin/sh
# nvim-ai 环境初始化(幂等,不删任何文件)
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
export NVIM_APPNAME=nvim-ai

say() { printf '\n== %s ==\n' "$*"; }

say "检查基础依赖"
missing=0
for c in nvim python3 gtags global git gcc node npm; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$c"
  else
    printf '  MISS %s\n' "$c"
    missing=$((missing + 1))
  fi
done
[ "$missing" -eq 0 ] || echo "  提示: 缺少依赖时先安装,再重新运行"

say "tree-sitter CLI(兼容旧 glibc)"
if command -v tree-sitter >/dev/null 2>&1 && tree-sitter --version >/dev/null 2>&1; then
  echo "  已有: $(tree-sitter --version)"
else
  if command -v cargo >/dev/null 2>&1; then
    echo "  编译 tree-sitter-cli 0.22.6 ..."
    cargo install tree-sitter-cli@0.22.6 --locked
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/nvim-ai/mason/bin"
    ln -sfn "$HOME/.cargo/bin/tree-sitter" "$HOME/.local/bin/tree-sitter"
    ln -sfn "$HOME/.cargo/bin/tree-sitter" "$HOME/.local/share/nvim-ai/mason/bin/tree-sitter"
  else
    echo "  缺少 cargo;请安装 Rust 或手动提供可用的 tree-sitter CLI"
  fi
fi

say "ACP provider(Node/npm)"
if command -v npm >/dev/null 2>&1; then
  npm i -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp || \
    echo "  npm 安装失败;可稍后手动安装"
fi

say "安装 Neovim 插件"
if command -v nvim >/dev/null 2>&1; then
  nvim --headless "+Lazy! sync" +qa
  echo "  解析器由 nvim-treesitter ensure_installed 自动安装(首次会下载/编译)"
  nvim --headless "+lua require('lazy').load({plugins={'nvim-treesitter'}})" "+lua vim.wait(120000)" +qa || true
fi

say "MCP 配置(按需手动执行)"
python3 "$ROOT/tools/aicx.py" mcp-config

say "索引示例"
cat <<EOF
  python3 "$ROOT/tools/aicx.py" index build <你的工程根> --json
  # 或在 Neovim 里打开文件后:
  #   :IndexBuild
EOF
