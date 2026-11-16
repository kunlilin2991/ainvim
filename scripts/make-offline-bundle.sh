#!/bin/sh
# 在联网机器安装成功后，把 vendor/ 打成可离线使用的包。
set -eu
cd "$(dirname "$0")/.."
if [ ! -d vendor ]; then
  echo "没有 vendor/ 目录。请先在联网机器成功安装，或使用已有的离线包。" >&2
  exit 1
fi
OUT="${1:-ainvim-offline-$(date +%Y%m%d).tar.gz}"
tar -czf "$OUT" vendor
echo "created: $OUT"
echo "拷贝到离线机器后运行:"
echo "  ./install.sh --offline-bundle /path/to/$OUT"
