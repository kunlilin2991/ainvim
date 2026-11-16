#!/usr/bin/env bash
# nvim-ai 一键安装脚本
# 在线优先:能联网就从官方源安装;离线时使用 --offline-bundle 指定的外部离线包。
# 用法:
#   ./install.sh                 # 自动检测网络,在线优先,失败回退离线
#   ./install.sh --online        # 强制联网安装(插件/GLOBAL/Node 等)
#   ./install.sh --offline       # 强制离线(需 --offline-bundle)
#   ./install.sh --offline-bundle PATH  # 使用下载好的离线包
#   ./install.sh --no-ai         # 不装 Claude/Codex/ACP
#   ./install.sh --no-mcp        # 不改 Claude/Codex MCP 配置
#   ./install.sh --no-plugins    # 只装配置/依赖,不装 Neovim 插件
#   ./install.sh --no-tmux       # 不改 ~/.tmux.conf 滚轮透传
#   ./install.sh --skip-deps     # 依赖缺失也继续
#   ./install.sh --index PATH    # 安装后为 PATH 建 gtags 索引
#   ./install.sh --dry-run       # 只打印动作,不修改
set -euo pipefail

BUNDLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG_SRC="$BUNDLE_DIR/nvim-ai"
BIN_SRC="$BUNDLE_DIR/bin/aivim"
VENDOR="$BUNDLE_DIR/vendor"

CONFIG_DIR="${HOME}/.config/nvim-ai"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${HOME}/.local/share/nvim-ai"
export NVIM_APPNAME=nvim-ai
export PATH="$BIN_DIR:$PATH"

DRY_RUN=0
OFFLINE=0
FORCE_ONLINE=0
NO_AI=0
NO_MCP=0
NO_PLUGINS=0
NO_TMUX=0
SKIP_DEPS=0
INDEX_PATH=""
OFFLINE_BUNDLE=""
PYTHON=""
NVIM=""
NODE_OK=0
GTAGS_OK=0
PLUGINS_OK=0
WARNINGS=()

usage() {
  cat <<'EOF'
nvim-ai 一键安装脚本
用法:
  ./install.sh                 # 自动检测网络,在线优先,失败回退离线
  ./install.sh --online        # 强制联网安装(插件/GLOBAL/Node 等)
  ./install.sh --offline       # 强制离线(需 --offline-bundle)
  ./install.sh --offline-bundle PATH  # 使用下载好的离线包
  ./install.sh --no-ai         # 不装 Claude/Codex/ACP
  ./install.sh --no-mcp        # 不改 Claude/Codex MCP 配置
  ./install.sh --no-plugins    # 只装配置/依赖,不装 Neovim 插件
  ./install.sh --no-tmux       # 不改 ~/.tmux.conf 滚轮透传
  ./install.sh --skip-deps     # 依赖缺失也继续
  ./install.sh --index PATH    # 安装后为 PATH 建 gtags 索引
  ./install.sh --dry-run       # 只打印动作,不修改
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --offline) OFFLINE=1 ;;
    --online) FORCE_ONLINE=1 ;;
    --no-ai) NO_AI=1 ;;
    --no-mcp) NO_MCP=1 ;;
    --no-plugins) NO_PLUGINS=1 ;;
    --no-tmux) NO_TMUX=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --offline-bundle) OFFLINE_BUNDLE="${2:?--offline-bundle 需要路径}"; shift ;;
    --index) INDEX_PATH="${2:?--index 需要路径}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

say() { printf '\n== %s ==\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
warn() { WARNINGS+=("$*"); echo "  [warn] $*"; }

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

backup() {
  local p="$1"
  if [ -e "$p" ] || [ -L "$p" ]; then
    local b="${p}.bak-$(date +%Y%m%d-%H%M%S)"
    run mv "$p" "$b"
    echo "  backup: $b"
  fi
}

version_ge() {
  [ "$(printf '%s\n' "$2" "$1" | sort -V 2>/dev/null | head -n1)" = "$2" ]
}

download() {
  local url="$1" out="$2"
  if [ "$DRY_RUN" = 1 ]; then
    echo "  [dry] download $url -> $out"
    return 0
  fi
  if have curl; then
    curl -fL --retry 3 --connect-timeout 20 -o "$out" "$url"
  elif have wget; then
    wget -O "$out" "$url"
  else
    return 1
  fi
}

# 离线大文件可能被拆成 <name>.part-*;需要时拼接到临时目录
materialize() {
  local name="$1" out
  if [ -f "$VENDOR/$name" ]; then
    printf '%s\n' "$VENDOR/$name"
    return 0
  fi
  local parts=( "$VENDOR/$name".part-* )
  if [ -e "${parts[0]}" ]; then
    out="$TMPDIR/$name"
    if [ ! -f "$out" ]; then
      cat "${parts[@]}" > "$out"
    fi
    printf '%s\n' "$out"
    return 0
  fi
  return 1
}

manual_hint() {
  local pkg="$1"
  cat <<EOF
  请手动安装 $pkg:
    Debian/Ubuntu : sudo apt install $pkg
    Fedora        : sudo dnf install $pkg
    Arch          : sudo pacman -S $pkg
    openSUSE      : sudo zypper install $pkg
    Alpine        : sudo apk add $pkg
EOF
}

TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/nvim-ai-install.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT
if [ ! -d "$VENDOR" ]; then
  VENDOR="$TMPDIR/vendor"
  mkdir -p "$VENDOR"
fi

OS=$(uname -s)
ARCH=$(uname -m)
JOBS=$( (command -v nproc >/dev/null && nproc) || echo 4 )

say "环境检测"
echo "  OS: $OS  ARCH: $ARCH  HOME: $HOME"

# ── 包管理器 / sudo ──────────────────────────────────────────────
PM=""
for p in apt-get dnf yum pacman zypper apk; do
  if have "$p"; then
    case "$p" in
      apt-get) PM=apt ;;
      dnf) PM=dnf ;;
      yum) PM=yum ;;
      pacman) PM=pacman ;;
      zypper) PM=zypper ;;
      apk) PM=apk ;;
    esac
    break
  fi
done
SUDO=""
if [ "$(id -u)" = 0 ]; then
  SUDO=""
elif have sudo; then
  if sudo -n true 2>/dev/null; then
    SUDO="sudo"
  elif [ -t 0 ]; then
    SUDO="sudo"
  fi
fi
can_pm() {
  [ -n "$PM" ] || return 1
  [ "$(id -u)" = 0 ] || [ -n "$SUDO" ]
}
pm_install() {
  [ "$#" -gt 0 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    echo "  [dry] $PM install $*"
    return 0
  fi
  can_pm || return 1
  case "$PM" in
    apt)
      $SUDO apt-get update -y >/dev/null 2>&1 || true
      $SUDO apt-get install -y "$@"
      ;;
    dnf) $SUDO dnf install -y "$@" ;;
    yum) $SUDO yum install -y "$@" ;;
    pacman) $SUDO pacman -Sy --noconfirm "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
    apk) $SUDO apk add --no-cache "$@" ;;
    *) return 1 ;;
  esac
}
echo "  package manager: ${PM:-none}  sudo: ${SUDO:-no}"

# ── 离线包 ─────────────────────────────────────────────────────
offline_help() {
  cat <<'EOF'
离线安装需要单独的离线包(仓库不包含大文件):
  1. 在联网机器打开:
       https://github.com/kunlilin2991/ainvim/releases
     下载 ainvim-offline-*.tar.gz
     (或向维护者获取;包内应有 vendor/ 目录)
  2. 拷贝到本机
  3. ./install.sh --offline-bundle /path/to/ainvim-offline.tar.gz
离线包内容: vendor/ 下的 Neovim、Node、GNU GLOBAL、LazyVim/插件、tree-sitter/解析器。
EOF
}

extract_offline_bundle() {
  local bundle="$1"
  if [ ! -f "$bundle" ]; then
    echo "  找不到离线包: $bundle"
    return 1
  fi
  echo "  使用离线包: $bundle"
  if [ "$DRY_RUN" = 1 ]; then
    VENDOR="$TMPDIR/offline/vendor"
    OFFLINE=1; NET=0; NO_AI=1
    return 0
  fi
  mkdir -p "$TMPDIR/offline"
  if ! tar -xzf "$bundle" -C "$TMPDIR/offline"; then
    echo "  解压离线包失败"
    return 1
  fi
  local v
  v=$(find "$TMPDIR/offline" -maxdepth 3 -type d -name vendor | head -1)
  if [ -z "$v" ]; then
    echo "  离线包内没有 vendor/ 目录"
    return 1
  fi
  VENDOR="$v"
  OFFLINE=1; NET=0; NO_AI=1
  echo "  vendor: $VENDOR"
}

ask_offline_mode() {
  if [ -n "$OFFLINE_BUNDLE" ]; then
    extract_offline_bundle "$OFFLINE_BUNDLE" || { offline_help; exit 1; }
    return
  fi
  if [ "$OFFLINE" = 1 ]; then
    if [ -d "$BUNDLE_DIR/vendor" ]; then
      VENDOR="$BUNDLE_DIR/vendor"
      echo "  离线模式: 使用本地 vendor ($VENDOR)"
    else
      offline_help
      exit 1
    fi
    return
  fi
  if [ "$FORCE_ONLINE" = 1 ] || [ ! -t 0 ]; then
    return
  fi
  printf '是否在离线环境安装? [y/N]: '
  local ans=""
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes|YES)
      printf '离线包路径 [./ainvim-offline.tar.gz]: '
      local path=""
      read -r path || path=""
      [ -n "$path" ] || path="./ainvim-offline.tar.gz"
      extract_offline_bundle "$path" || { offline_help; exit 1; }
      ;;
  esac
}

# ── 网络检测 ────────────────────────────────────────────────────
if [ "$OFFLINE" = 1 ] || [ -n "$OFFLINE_BUNDLE" ]; then
  NET=0
elif [ "$FORCE_ONLINE" = 1 ]; then
  NET=1
elif have curl; then
  if curl -fsI --max-time 8 https://github.com >/dev/null 2>&1; then NET=1; else NET=0; fi
elif have wget; then
  if wget -q --spider --timeout=8 https://github.com >/dev/null 2>&1; then NET=1; else NET=0; fi
elif getent hosts github.com >/dev/null 2>&1; then
  NET=1
else
  NET=0
fi
echo "  network: $([ "$NET" = 1 ] && echo online || echo offline)"
ask_offline_mode

if [ "$OFFLINE" = 1 ]; then
  echo "  离线模式: 跳过 npm ACP adapters"
  NO_AI=1
fi

# ── 基础工具 ────────────────────────────────────────────────────
say "基础工具(git/tar/curl/gcc/make/xz)"
need=()
for c in git tar gzip expr; do have "$c" || need+=("$c"); done
if ! have curl && ! have wget; then need+=(curl); fi
have gcc || need+=(gcc)
have make || need+=(make)
have xz || need+=(xz)
if [ "${#need[@]}" -gt 0 ]; then
  echo "  缺少: ${need[*]}"
  if [ "$NET" = 1 ]; then
    case "$PM" in
      apt) pm_install git tar gzip coreutils curl ca-certificates build-essential xz-utils || true ;;
      dnf|yum) pm_install git tar gzip coreutils curl ca-certificates gcc gcc-c++ make xz || true ;;
      pacman) pm_install git tar gzip coreutils curl ca-certificates base-devel xz || true ;;
      zypper) pm_install git tar gzip coreutils curl ca-certificates gcc gcc-c++ make xz || true ;;
      apk) pm_install git tar gzip coreutils curl ca-certificates build-base xz || true ;;
    esac
  fi
fi
if ! have git || ! have tar; then
  warn "git/tar 缺失,无法完整安装"
  [ "$SKIP_DEPS" = 1 ] || exit 1
fi

# ── Python ──────────────────────────────────────────────────────
say "Python >= 3.8"
if have python3 && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
  PYTHON=python3
  echo "  $(python3 --version)"
else
  if [ "$NET" = 1 ]; then pm_install python3 || true; fi
  if have python3 && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
    PYTHON=python3
    echo "  $(python3 --version)"
  else
    warn "Python >= 3.8 未安装;索引/MCP 将不可用"
    manual_hint python3
    [ "$SKIP_DEPS" = 1 ] || exit 1
  fi
fi

# ── GNU GLOBAL ──────────────────────────────────────────────────
say "GNU GLOBAL (gtags/global)"
run mkdir -p "$BIN_DIR" "$HOME/.local/opt"
if have gtags && have global; then
  GTAGS_OK=1
  echo "  $(gtags --version | head -1)"
else
  if [ "$NET" = 1 ]; then
    echo "  尝试系统包 global ..."
    if pm_install global; then
      have gtags && have global && GTAGS_OK=1
    fi
  fi
  if [ "$GTAGS_OK" != 1 ]; then
    echo "  尝试源码编译 GNU GLOBAL 6.6.4 ..."
    src="$VENDOR/global-6.6.4.tar.gz"
    if [ ! -f "$src" ] && [ "$NET" = 1 ]; then
      download "https://ftp.gnu.org/gnu/global/global-6.6.4.tar.gz" "$TMPDIR/global-6.6.4.tar.gz" \
        && src="$TMPDIR/global-6.6.4.tar.gz" || true
    fi
    if [ -f "$src" ] && have gcc && have make && have tar; then
      if [ "$NET" = 1 ]; then
        case "$PM" in
          apt) pm_install libsqlite3-dev libltdl-dev libncurses-dev || true ;;
          dnf|yum) pm_install sqlite-devel libtool-ltdl-devel ncurses-devel || true ;;
          pacman) pm_install sqlite libtool ncurses || true ;;
        esac
      fi
      run mkdir -p "$TMPDIR/global-build"
      run tar -xzf "$src" -C "$TMPDIR/global-build"
      gdir=$(find "$TMPDIR/global-build" -mindepth 1 -maxdepth 1 -type d -name 'global-*' | head -1)
      if [ -n "$gdir" ]; then
        ( cd "$gdir" \
          && run ./configure --prefix="$HOME/.local/opt/global" \
          && run make -j"$JOBS" \
          && run make install ) || true
        run mkdir -p "$BIN_DIR"
        for b in gtags global gtags-cscope; do
          [ -x "$HOME/.local/opt/global/bin/$b" ] && run ln -sfn "$HOME/.local/opt/global/bin/$b" "$BIN_DIR/$b"
        done
      fi
    fi
  fi
  if have gtags && have global; then
    GTAGS_OK=1
    echo "  $(gtags --version | head -1)"
  else
    warn "GNU GLOBAL 不可用;索引功能禁用,请手动安装 global"
    manual_hint global
  fi
fi

# ── Neovim ──────────────────────────────────────────────────────
say "Neovim >= 0.11.2"
if have nvim; then
  v=$(nvim --version | head -1 | awk '{print $2}' | sed 's/^v//')
  if version_ge "$v" 0.11.2; then
    NVIM=$(command -v nvim)
    echo "  使用系统 nvim $v"
  fi
fi
if [ -z "$NVIM" ]; then
  echo "  安装用户级 Neovim 0.11.5 ..."
  case "$ARCH" in
    x86_64) nvim_tar=nvim-linux-x86_64.tar.gz ;;
    aarch64|arm64) nvim_tar=nvim-linux-arm64.tar.gz ;;
    *) nvim_tar="" ;;
  esac
  tb=""
  if [ -n "$nvim_tar" ]; then
    if [ "$NET" = 1 ]; then
      download "https://github.com/neovim/neovim/releases/download/v0.11.5/$nvim_tar" "$TMPDIR/$nvim_tar" \
        && tb="$TMPDIR/$nvim_tar" || true
    fi
    if [ -z "$tb" ]; then
      tb=$(materialize "$nvim_tar" 2>/dev/null || true)
    fi
  fi
  if [ -n "$tb" ] && [ -f "$tb" ]; then
    run rm -rf "$HOME/.local/opt/nvim"
    run mkdir -p "$HOME/.local/opt/nvim"
    run tar -xzf "$tb" -C "$HOME/.local/opt/nvim"
    nbin=$(find "$HOME/.local/opt/nvim" -maxdepth 4 -type f -name nvim | head -1)
    if [ -n "$nbin" ]; then
      run mkdir -p "$BIN_DIR"
      run ln -sfn "$nbin" "$BIN_DIR/nvim"
      NVIM="$BIN_DIR/nvim"
      if "$NVIM" --version >/dev/null 2>&1; then
        echo "  已安装: $("$NVIM" --version | head -1)"
      else
        echo "  官方二进制与当前 glibc 不兼容,改为源码编译 ..."
        run rm -f "$BIN_DIR/nvim"
        NVIM=""
      fi
    fi
  fi
fi
if [ -z "$NVIM" ] && [ "$NET" = 1 ] && have git && have make; then
  if can_pm; then
    case "$PM" in
      apt) pm_install cmake ninja-build gettext libtool-bin || true ;;
      dnf|yum) pm_install cmake ninja-build gettext libtool || true ;;
      pacman) pm_install cmake ninja gettext libtool || true ;;
      zypper) pm_install cmake ninja gettext libtool || true ;;
      apk) pm_install cmake ninja gettext libtool || true ;;
    esac
  fi
  if have cmake && have ninja; then
    echo "  尝试源码编译 Neovim(可能较慢) ..."
    run rm -rf "$TMPDIR/neovim-src"
    if run git clone --depth 1 --branch v0.11.5 https://github.com/neovim/neovim "$TMPDIR/neovim-src"; then
      run make -C "$TMPDIR/neovim-src" deps || true
      if run make -C "$TMPDIR/neovim-src" CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX="$HOME/.local/opt/nvim"; then
        run make -C "$TMPDIR/neovim-src" install || true
        run mkdir -p "$BIN_DIR"
        run ln -sfn "$HOME/.local/opt/nvim/bin/nvim" "$BIN_DIR/nvim"
        NVIM="$BIN_DIR/nvim"
        if "$NVIM" --version >/dev/null 2>&1; then
          echo "  编译安装完成: $("$NVIM" --version | head -1)"
        else
          NVIM=""
        fi
      fi
    fi
  fi
fi
if [ -z "$NVIM" ]; then
  warn "无法自动安装 Neovim;请手动安装 >=0.11.2"
  [ "$SKIP_DEPS" = 1 ] || exit 1
fi

# ── Node.js / npm ───────────────────────────────────────────────
say "Node.js >= 18 / npm"
if have node && have npm && node -e 'process.exit(parseInt(process.versions.node,10) >= 18 ? 0 : 1)' 2>/dev/null; then
  NODE_OK=1
  echo "  使用系统 node $(node --version), npm $(npm --version)"
else
  if [ "$NET" = 1 ] || materialize node-v22.23.5-linux-x64.tar.xz >/dev/null 2>&1; then
    echo "  安装用户级 Node.js 22 ..."
    case "$ARCH" in
      x86_64) node_tar=node-v22.23.5-linux-x64.tar.xz ;;
      aarch64|arm64) node_tar=node-v22.23.5-linux-arm64.tar.xz ;;
      *) node_tar="" ;;
    esac
    tb=""
    if [ -n "$node_tar" ]; then
      if [ "$NET" = 1 ]; then
        download "https://nodejs.org/dist/v22.23.5/$node_tar" "$TMPDIR/$node_tar" \
          && tb="$TMPDIR/$node_tar" || true
      fi
      if [ -z "$tb" ]; then
        tb=$(materialize "$node_tar" 2>/dev/null || true)
      fi
    fi
    if [ -n "$tb" ] && [ -f "$tb" ]; then
      run mkdir -p "$HOME/.local/opt"
      run tar -xf "$tb" -C "$HOME/.local/opt"
      ndir=$(find "$HOME/.local/opt" -maxdepth 1 -type d -name 'node-v*' | sort | tail -1)
      if [ -n "$ndir" ]; then
        run mkdir -p "$BIN_DIR"
        run ln -sfn "$ndir/bin/node" "$BIN_DIR/node"
        run ln -sfn "$ndir/bin/npm" "$BIN_DIR/npm"
        run ln -sfn "$ndir/bin/npx" "$BIN_DIR/npx"
        hash -r 2>/dev/null || true
        NODE_OK=1
        echo "  已安装: node $(node --version), npm $(npm --version)"
      fi
    fi
  fi
  if [ "$NODE_OK" != 1 ]; then
    warn "Node.js/npm 不可用;AI 部分将跳过"
  fi
fi
if [ "$NODE_OK" = 1 ] && have npm; then
  npm_prefix=$(npm config get prefix 2>/dev/null || true)
  if [ -z "$npm_prefix" ] || [ ! -w "$npm_prefix" ]; then
    run npm config set prefix "$HOME/.local"
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# ── 配置 / 启动器 ───────────────────────────────────────────────
say "安装配置与启动器"
backup "$CONFIG_DIR"
backup "$BIN_DIR/aivim"
run mkdir -p "$(dirname "$CONFIG_DIR")" "$BIN_DIR"
run cp -a "$CONFIG_SRC" "$CONFIG_DIR"
run cp "$BIN_SRC" "$BIN_DIR/aivim"
run chmod +x "$BIN_DIR/aivim"
echo "  config: $CONFIG_DIR"
echo "  launcher: $BIN_DIR/aivim"

# ── tree-sitter CLI / 解析器 ─────────────────────────────────────
say "tree-sitter CLI"
ts_bin=$(materialize tree-sitter 2>/dev/null || true)
if [ -n "$ts_bin" ] && [ -f "$ts_bin" ] && [ "$OS" = "Linux" ] && [ "$ARCH" = "x86_64" ]; then
  chmod +x "$ts_bin" 2>/dev/null || true
fi
if [ -n "$ts_bin" ] && [ -f "$ts_bin" ] && [ "$OS" = "Linux" ] && [ "$ARCH" = "x86_64" ] && "$ts_bin" --version >/dev/null 2>&1; then
  run install -m 755 "$ts_bin" "$BIN_DIR/tree-sitter"
elif have tree-sitter && tree-sitter --version >/dev/null 2>&1; then
  echo "  已有: $(tree-sitter --version)"
elif [ "$NET" = 1 ] && have cargo; then
  run cargo install tree-sitter-cli@0.22.6 --locked || true
  [ -x "$HOME/.cargo/bin/tree-sitter" ] && run ln -sfn "$HOME/.cargo/bin/tree-sitter" "$BIN_DIR/tree-sitter"
else
  warn "tree-sitter CLI 不可用;C/C++ 高亮可能失败"
fi
if [ -x "$BIN_DIR/tree-sitter" ]; then
  run mkdir -p "$DATA_DIR/mason/bin"
  run ln -sfn "$BIN_DIR/tree-sitter" "$DATA_DIR/mason/bin/tree-sitter"
fi

say "tree-sitter 解析器"
if [ "$OS" = "Linux" ] && [ "$ARCH" = "x86_64" ] && [ -d "$VENDOR/parser" ]; then
  run mkdir -p "$DATA_DIR/site/parser"
  run cp -a "$VENDOR/parser/." "$DATA_DIR/site/parser/"
  echo "  已复制 $(find "$VENDOR/parser" -name '*.so' | wc -l) 个解析器"
elif [ "$NET" = 1 ] && [ -n "$NVIM" ] && [ "$NO_PLUGINS" = 0 ]; then
  echo "  由 nvim-treesitter 在线安装 ..."
  run "$NVIM" --headless "+lua require('lazy').load({plugins={'nvim-treesitter'}})" "+lua vim.wait(180000)" +qa || true
else
  warn "预编译解析器不可用;请联网或在 Neovim 里 :TSUpdate"
fi

# ── Neovim 插件 ────────────────────────────────────────────────
say "Neovim 插件"
if [ "$NO_PLUGINS" = 1 ]; then
  echo "  --no-plugins: 跳过"
else
  if [ "$NET" = 1 ] && [ "$OFFLINE" = 0 ] && [ -n "$NVIM" ]; then
    echo "  从网络安装/同步插件 ..."
    if run "$NVIM" --headless "+Lazy! sync" +qa; then
      run "$NVIM" --headless "+Lazy! restore" +qa || true
      PLUGINS_OK=1
    fi
  fi
  lazy_tar=$(materialize lazy.tar.gz 2>/dev/null || true)
  if [ "$PLUGINS_OK" != 1 ] && [ -n "$lazy_tar" ] && [ -f "$lazy_tar" ]; then
    echo "  使用离线插件包 ..."
    backup "$DATA_DIR/lazy"
    run mkdir -p "$DATA_DIR"
    run tar -xzf "$lazy_tar" -C "$DATA_DIR"
    PLUGINS_OK=1
  fi
  if [ "$PLUGINS_OK" != 1 ]; then
    warn "插件未安装;请联网后运行 :Lazy sync"
  fi
fi

if [ "$PLUGINS_OK" = 1 ] && [ -n "$NVIM" ] && [ "$DRY_RUN" = 0 ]; then
  if ! "$NVIM" --headless "+lua local ok,err=pcall(vim.treesitter.language.add,'c'); print('treesitter-c:',ok,err)" +qa; then
    warn "C treesitter 解析器加载失败;可在 Neovim 里 :TSUpdate"
  fi
fi

# ── Claude Code / Codex / ACP ─────────────────────────────────
say "AI CLI (Claude Code / Codex / ACP)"
if [ "$NO_AI" = 1 ]; then
  echo "  跳过"
else
  if [ "$NODE_OK" != 1 ] || ! have npm; then
    warn "没有 Node/npm;跳过 Claude/Codex/ACP 安装"
    NO_AI=1
  fi
fi
if [ "$NO_AI" = 0 ]; then
  # Claude Code
  if have claude; then
    echo "  Claude: $(claude --version 2>/dev/null | head -1)"
  elif [ "$NET" = 1 ]; then
    echo "  安装 Claude Code ..."
    if ! run npm i -g @anthropic-ai/claude-code; then
      if have curl; then
        run sh -c 'curl -fsSL https://claude.ai/install.sh | bash' || true
      fi
    fi
    hash -r 2>/dev/null || true
    have claude && echo "  Claude: $(claude --version 2>/dev/null | head -1)" || \
      warn "Claude Code 安装失败;请手动 npm i -g @anthropic-ai/claude-code"
  else
    warn "离线包不包含 Claude Code(二进制约 346MB);联网后执行: npm i -g @anthropic-ai/claude-code"
  fi

  # Codex
  if have codex; then
    echo "  Codex: $(codex --version 2>/dev/null | head -1)"
  elif [ "$NET" = 1 ]; then
    echo "  安装 Codex CLI ..."
    run npm i -g @openai/codex || true
    hash -r 2>/dev/null || true
    have codex && echo "  Codex: $(codex --version 2>/dev/null | head -1)" || \
      warn "Codex 安装失败;请手动 npm i -g @openai/codex"
  else
    warn "离线包不包含 Codex CLI;联网后执行: npm i -g @openai/codex"
  fi

  # ACP adapters
  if [ "$NET" = 1 ] && have npm; then
    echo "  安装 ACP adapters ..."
    backup "$BIN_DIR/codex-acp"
    run npm uninstall -g @zed-industries/codex-acp >/dev/null 2>&1 || true
    if ! run npm i -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp; then
      warn "ACP adapters 安装失败;请手动 npm i -g @agentclientprotocol/claude-agent-acp @agentclientprotocol/codex-acp"
    fi
  else
    warn "离线模式/无 npm:跳过 ACP adapters"
  fi
fi

# ── MCP ────────────────────────────────────────────────────────
say "MCP (aivim-gtags)"
MCP_PY="$CONFIG_DIR/tools/aicx.py"
if [ "$NO_MCP" = 1 ]; then
  echo "  --no-mcp: 跳过"
elif [ -z "$PYTHON" ] || [ ! -f "$MCP_PY" ]; then
  warn "Python 或 aicx.py 不可用;跳过 MCP 注册"
else
  if have claude; then
    [ -f "$HOME/.claude.json" ] && backup "$HOME/.claude.json"
    if claude mcp list 2>/dev/null | grep -q 'aivim-gtags'; then
      echo "  Claude: aivim-gtags 已注册"
    else
      run claude mcp add --scope user aivim-gtags "$PYTHON" "$MCP_PY" mcp || \
        warn "claude mcp add 失败"
    fi
  else
    echo "  Claude Code 未安装,跳过"
  fi
  if have codex; then
    [ -f "$HOME/.codex/config.toml" ] && backup "$HOME/.codex/config.toml"
    if codex mcp list 2>/dev/null | grep -q 'aivim-gtags'; then
      echo "  Codex: aivim-gtags 已注册"
    else
      run codex mcp add aivim-gtags -- "$PYTHON" "$MCP_PY" mcp || \
        warn "codex mcp add 失败"
    fi
    if [ "$DRY_RUN" = 0 ] && [ -f "$HOME/.codex/config.toml" ]; then
      "$PYTHON" - "$HOME/.codex/config.toml" <<'PY' || true
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
m = re.search(r'(\[mcp_servers\.aivim-gtags\])(.*?)(?=\n\[|\Z)', s, re.S)
if m and "default_tools_approval_mode" not in m.group(2):
    section = m.group(0)
    new_section = re.sub(
        r'(args\s*=\s*\[[^\]]*\]\n)',
        r'\1default_tools_approval_mode = "approve"\n',
        section, count=1,
    )
    if new_section != section:
        p.write_text(s.replace(section, new_section, 1))
PY
    fi
  else
    echo "  Codex 未安装,跳过"
  fi
fi

# ── tmux ───────────────────────────────────────────────────────
say "tmux 鼠标滚轮透传"
if [ "$NO_TMUX" = 1 ]; then
  echo "  --no-tmux: 跳过"
elif have tmux && [ -f "$HOME/.tmux.conf" ]; then
  if grep -q 'nvim-ai: 让启用了鼠标的应用' "$HOME/.tmux.conf"; then
    echo "  已存在滚轮透传配置"
  else
    backup "$HOME/.tmux.conf"
    if [ "$DRY_RUN" = 1 ]; then
      echo "  [dry] append tmux/nvim-ai-mouse.conf to ~/.tmux.conf"
    else
      cat "$BUNDLE_DIR/tmux/nvim-ai-mouse.conf" >> "$HOME/.tmux.conf"
      echo "  已追加滚轮透传配置"
    fi
  fi
  if tmux ls >/dev/null 2>&1; then
    run tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 || true
  fi
else
  echo "  未找到 tmux 或 ~/.tmux.conf,跳过"
fi

# ── 索引 ───────────────────────────────────────────────────────
if [ -n "$INDEX_PATH" ]; then
  say "建立索引: $INDEX_PATH"
  if [ -n "$PYTHON" ] && [ "$GTAGS_OK" = 1 ]; then
    run "$PYTHON" "$MCP_PY" index build "$INDEX_PATH" --json
  else
    warn "Python/GNU GLOBAL 不可用,跳过索引"
  fi
else
  echo
  echo "未指定 --index。之后可运行:"
  echo "  $PYTHON \"$MCP_PY\" index build <工程路径> --json"
  echo "  或在 Neovim 里打开文件后执行 :IndexBuild"
fi

# ── 自检 ───────────────────────────────────────────────────────
say "安装后自检"
if [ "$DRY_RUN" = 0 ] && [ "$PLUGINS_OK" = 1 ] && [ -x "$BIN_DIR/aivim" ]; then
  if "$BIN_DIR/aivim" --headless "+luafile $CONFIG_DIR/scripts/check.lua" +qa >/tmp/nvim-ai-install-check.log 2>&1; then
    echo "  按键/选项审计: OK (missing=0)"
  else
    warn "自检未通过,日志: /tmp/nvim-ai-install-check.log"
    tail -20 /tmp/nvim-ai-install-check.log || true
  fi
fi

# ── 汇总 ───────────────────────────────────────────────────────
say "安装完成"
echo "  config   : $CONFIG_DIR"
echo "  launcher : $BIN_DIR/aivim"
echo "  data     : $DATA_DIR"
echo "  nvim     : ${NVIM:-missing}"
echo "  python   : ${PYTHON:-missing}"
echo "  node     : $(have node && node --version || echo missing)"
echo "  npm      : $(have npm && npm --version || echo missing)"
echo "  gtags    : $(have gtags && gtags --version | head -1 || echo missing)"
echo "  claude   : $(have claude && claude --version 2>/dev/null | head -1 || echo missing)"
echo "  codex    : $(have codex && codex --version 2>/dev/null | head -1 || echo missing)"
echo
echo "启动: aivim"
echo "帮助: :AivimDiag / :IndexStatus / ;i?"
echo "旧配置未改动: $HOME/.config/nvim"
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo
  echo "注意:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi
