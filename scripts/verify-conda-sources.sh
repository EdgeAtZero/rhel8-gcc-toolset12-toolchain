#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/manifests/toolchain.json"

CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/rhel8-gcc-toolset12-toolchain"
CHANNEL_DIR="${CHANNEL_DIR:-$CACHE_ROOT/conda-channel}"
SOURCE_DIR="$CHANNEL_DIR/sources"

for command in sha256sum python3 stat rpm2cpio cpio; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

[[ -f "$SOURCE_DIR/SOURCE-METADATA.json" ]] || {
  echo "Missing source metadata: $SOURCE_DIR/SOURCE-METADATA.json" >&2
  exit 1
}
[[ -f "$SOURCE_DIR/SHA256SUMS" ]] || {
  echo "Missing source checksums: $SOURCE_DIR/SHA256SUMS" >&2
  exit 1
}
[[ -f "$SOURCE_DIR/README.txt" ]] || {
  echo "Missing source README: $SOURCE_DIR/README.txt" >&2
  exit 1
}

python3 - "$MANIFEST" "$SOURCE_DIR" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
source_dir = pathlib.Path(sys.argv[2])

with manifest_path.open(encoding="utf-8") as f:
    data = json.load(f)

rpms = data["rpms"]
sources = data["corresponding_sources"]
filenames = {source["filename"] for source in sources.values()}

for rpm_key, rpm in rpms.items():
    if rpm.get("source_rpm") not in filenames:
        raise SystemExit(f"{rpm_key}: unresolved source_rpm {rpm.get('source_rpm')}")

expected_items = []
expected_sums = []
for source_key, source in sources.items():
    expected_keys = sorted(
        key for key, rpm in rpms.items()
        if rpm.get("source_rpm") == source["filename"]
    )
    if sorted(source["provides_for"]) != expected_keys:
        raise SystemExit(f"{source_key}: provides_for does not match binary mapping")

    path = source_dir / source["filename"]
    if not path.is_file():
        raise SystemExit(f"missing source RPM: {path}")
    if path.stat().st_size != source["size"]:
        raise SystemExit(f"source RPM size mismatch: {source['filename']}")

    hasher = hashlib.sha256()
    with path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    if digest != source["sha256"]:
        raise SystemExit(f"source RPM SHA-256 mismatch: {source['filename']}")

    binary_inputs = []
    for rpm_key in source["provides_for"]:
        rpm = rpms[rpm_key]
        binary_inputs.append(
            {
                "key": rpm_key,
                "filename": rpm["filename"],
                "sha256": rpm["sha256"],
                "payload": rpm["payload"],
            }
        )

    expected_items.append(
        {
            "id": source_key,
            "filename": source["filename"],
            "url": source["url"],
            "sha256": source["sha256"],
            "size": source["size"],
            "binary_inputs": binary_inputs,
        }
    )
    expected_sums.append(f"{source['sha256']}  {source['filename']}")

expected_metadata = {
    "schema": 1,
    "purpose": "Corresponding source for GPL-covered compatibility payloads",
    "source_rpms": expected_items,
}
with (source_dir / "SOURCE-METADATA.json").open(encoding="utf-8") as f:
    actual_metadata = json.load(f)
if actual_metadata != expected_metadata:
    raise SystemExit("SOURCE-METADATA.json does not match manifests/toolchain.json")

actual_sums = (source_dir / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
if actual_sums != sorted(expected_sums):
    raise SystemExit("sources/SHA256SUMS does not match the manifest")
PY

while IFS= read -r source_rpm; do
  path="$SOURCE_DIR/$source_rpm"
  listing="$(rpm2cpio "$path" | cpio -t 2>/dev/null)"
  grep -Eq '(^|/)gcc\.spec$' <<<"$listing" || {
    echo "Source RPM does not contain gcc.spec: $source_rpm" >&2
    exit 1
  }
  grep -Eq '(^|/)gcc-[0-9].*\.tar\.(xz|gz|bz2)$' <<<"$listing" || {
    echo "Source RPM does not contain a GCC source tarball: $source_rpm" >&2
    exit 1
  }
done < <(
  python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data=json.load(f)
for source in data["corresponding_sources"].values():
    print(source["filename"])
PY
)

echo "Corresponding source bundle verification passed."
