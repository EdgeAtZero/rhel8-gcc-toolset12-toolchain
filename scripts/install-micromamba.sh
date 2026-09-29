#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/manifests/toolchain.json"
DESTINATION=""

usage() {
  cat <<EOF
Usage: $0 --destination PATH

Download the manifest-pinned micromamba bootstrap binary and verify SHA-256.
EOF
}

while (($#)); do
  case "$1" in
    --destination)
      DESTINATION="${2:-}"
      shift 2
      ;;
    --destination=*)
      DESTINATION="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$DESTINATION" ]] || {
  echo "--destination is required." >&2
  exit 2
}

for cmd in python3 curl sha256sum install uname; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Required command not found: $cmd" >&2
    exit 1
  }
done

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) ;;
  *)
    echo "Pinned micromamba bootstrap is available only for Linux x86_64." >&2
    exit 1
    ;;
esac

mapfile -d '' -t values < <(
  python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

m = data["bootstrap"]["micromamba"]
for value in (m["version"], m["url"], m["sha256"]):
    print(value, end="\0")
PY
)

(("${#values[@]}" == 3)) || {
  echo "Invalid micromamba manifest data." >&2
  exit 1
}

version="${values[0]}"
url="${values[1]}"
sha256="${values[2]}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl --fail --location --retry 5 --retry-all-errors --proto '=https' --tlsv1.2 "$url" -o "$tmp"
printf '%s  %s\n' "$sha256" "$tmp" | sha256sum -c -

mkdir -p "$(dirname "$DESTINATION")"
install -m 0755 "$tmp" "$DESTINATION"

echo "Installed micromamba $version: $DESTINATION"
