#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

echo "NOTICE: generated toolchain archives are for local/internal use by default." >&2
echo "Public redistribution requires separate third-party license/source review; see THIRD_PARTY.md." >&2

TOOLCHAIN_NAME="linux-x86_64-rhel8-gcc-toolset12"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${PREFIX:-$("$REPO_ROOT/scripts/resolve-toolchain-prefix.sh")}"
ROOT="$(dirname "$PREFIX")"
NAME="$(basename "$PREFIX")"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist}"
MANIFEST="$REPO_ROOT/manifests/toolchain.json"
RELEASE_VERSION="${RELEASE_VERSION:-dev}"
SOURCE_COMMIT="${SOURCE_COMMIT:-}"

[[ -d "$PREFIX" ]] || {
  echo "Toolchain prefix not found: $PREFIX" >&2
  exit 1
}

for cmd in tar zstd sha256sum python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Required command not found: $cmd" >&2
    exit 1
  }
done

if [[ -z "$SOURCE_COMMIT" ]] && command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
  SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
fi
SOURCE_COMMIT="${SOURCE_COMMIT:-unknown}"

if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
  if [[ "$SOURCE_COMMIT" != "unknown" ]] && command -v git >/dev/null 2>&1; then
    SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" show -s --format=%ct "$SOURCE_COMMIT")"
  else
    echo "SOURCE_DATE_EPOCH is required outside a Git checkout." >&2
    exit 1
  fi
fi

[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || {
  echo "SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
  exit 1
}

mkdir -p "$OUT_DIR"
archive="$OUT_DIR/$NAME.tar.zst"
checksum="$archive.sha256"
sbom="$OUT_DIR/$NAME.spdx.json"
metadata="$OUT_DIR/RELEASE-METADATA.json"
sums="$OUT_DIR/SHA256SUMS"

rm -f "$archive" "$checksum" "$sbom" "$metadata" "$sums"

tar   --sort=name   --mtime="@${SOURCE_DATE_EPOCH}"   --owner=0   --group=0   --numeric-owner   --format=gnu   -C "$ROOT"   -cf -   "$NAME" |
  zstd -T1 -10 --no-progress -o "$archive"

archive_sha256="$(sha256sum "$archive" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha256" "$NAME.tar.zst" >"$checksum"

python3 "$REPO_ROOT/scripts/generate-sbom.py"   --prefix "$PREFIX"   --manifest "$MANIFEST"   --archive "$archive"   --output "$sbom"   --version "$RELEASE_VERSION"   --source-commit "$SOURCE_COMMIT"   --source-date-epoch "$SOURCE_DATE_EPOCH"

python3 - "$MANIFEST" "$REPO_ROOT/manifests/conda-linux-64.lock" "$archive" "$sbom" "$metadata" "$RELEASE_VERSION" "$SOURCE_COMMIT" "$SOURCE_DATE_EPOCH" <<'PY'
import hashlib
import json
import pathlib
import subprocess
import sys

manifest, lock, archive, sbom, output = map(pathlib.Path, sys.argv[1:6])
release_version, source_commit, source_date_epoch = sys.argv[6:9]

def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def first_line(command):
    return subprocess.check_output(command, text=True).splitlines()[0]

data = {
    "schema": 1,
    "release_version": release_version,
    "source_commit": source_commit,
    "source_date_epoch": int(source_date_epoch),
    "manifest_sha256": sha256(manifest),
    "conda_lock_sha256": sha256(lock),
    "archive": {
        "name": archive.name,
        "sha256": sha256(archive),
        "size": archive.stat().st_size,
    },
    "sbom": {
        "name": sbom.name,
        "sha256": sha256(sbom),
        "size": sbom.stat().st_size,
        "format": "SPDX-2.3",
    },
    "packaging": {
        "tar": first_line(["tar", "--version"]),
        "zstd": first_line(["zstd", "--version"]),
    },
}

with output.open("w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, sort_keys=True, indent=2)
    f.write("\n")
PY

(
  cd "$OUT_DIR"
  sha256sum "$NAME.tar.zst" "$NAME.spdx.json" "RELEASE-METADATA.json" >"SHA256SUMS"
)

echo "Created:"
echo "  $archive"
echo "  $checksum"
echo "  $sbom"
echo "  $metadata"
echo "  $sums"
