#!/bin/sh
# 推送 ainvim 到 GitHub。
# 先尝试直连 SSH;若直连被网络阻断且存在 https_proxy,则用 ssh-proxy.py 走 HTTPS 代理隧道。
set -eu
cd "$(dirname "$0")/.."

if ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new -p 443 -T git@ssh.github.com >/dev/null 2>&1; then
  exec git push -u origin main
fi

if [ -n "${https_proxy:-}${HTTPS_PROXY:-}" ] && [ -f scripts/ssh-proxy.py ]; then
  echo "direct SSH unavailable; using HTTPS proxy tunnel ..."
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=10 -o ServerAliveCountMax=30 -o ProxyCommand='python3 $(pwd)/scripts/ssh-proxy.py %h %p'" \
    exec git push -u origin main
fi

echo "SSH unreachable and no https_proxy; configure direct SSH or use an HTTPS token." >&2
exit 1
