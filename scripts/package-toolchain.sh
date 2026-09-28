#!/usr/bin/env bash
set -euo pipefail

TOOLCHAIN_NAME="linux-x86_64-rhel8-gcc-toolset12"
PREFIX="${PREFIX:-/opt/toolchains/$TOOLCHAIN_NAME}"
ROOT="$(dirname "$PREFIX")"
NAME="$(basename "$PREFIX")"
OUT_DIR="${OUT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dist}"

[[ -d "$PREFIX" ]] || {
  echo "Toolchain prefix not found: $PREFIX" >&2
  exit 1
}

command -v zstd >/dev/null 2>&1 || {
  echo "zstd is required to package the toolchain." >&2
  exit 1
}

mkdir -p "$OUT_DIR"
archive="$OUT_DIR/$NAME.tar.zst"
checksum="$archive.sha256"

tar -C "$ROOT" --zstd -cf "$archive" "$NAME"
(
  cd "$OUT_DIR"
  sha256sum "$NAME.tar.zst" > "$NAME.tar.zst.sha256"
)

echo "Created:"
echo "  $archive"
echo "  $checksum"
