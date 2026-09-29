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
SOURCE_CACHE="${SOURCE_CACHE:-$CACHE_ROOT/source-rpms}"
SOURCE_DIR="$CHANNEL_DIR/sources"

for command in curl sha256sum python3 stat cmp; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

mkdir -p "$SOURCE_CACHE" "$SOURCE_DIR"

mapfile -t rows < <(
  python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

rpms = data["rpms"]
sources = data["corresponding_sources"]

by_filename = {source["filename"]: key for key, source in sources.items()}
if len(by_filename) != len(sources):
    raise SystemExit("corresponding source filenames must be unique")

for rpm_key, rpm in rpms.items():
    source_name = rpm.get("source_rpm")
    if source_name not in by_filename:
        raise SystemExit(f"{rpm_key}: source_rpm is not declared: {source_name}")

for source_key, source in sources.items():
    expected = sorted(
        key for key, rpm in rpms.items()
        if rpm.get("source_rpm") == source["filename"]
    )
    declared = sorted(source.get("provides_for", []))
    if declared != expected:
        raise SystemExit(
            f"{source_key}: provides_for mismatch: declared={declared}, expected={expected}"
        )
    print(
        "\t".join(
            (
                source["filename"],
                source["url"],
                source["sha256"],
                str(source["size"]),
            )
        )
    )
PY
)

for row in "${rows[@]}"; do
  IFS=$'\t' read -r filename url sha256 size <<<"$row"
  cache_path="$SOURCE_CACHE/$filename"
  dest_path="$SOURCE_DIR/$filename"

  if [[ -f "$cache_path" ]] &&
     printf '%s  %s\n' "$sha256" "$cache_path" | sha256sum -c - >/dev/null 2>&1 &&
     [[ "$(stat -c %s "$cache_path")" == "$size" ]]; then
    echo "Using cached corresponding source: $filename"
  else
    rm -f "$cache_path.tmp" "$cache_path"
    curl -fL --retry 3 --output "$cache_path.tmp" "$url"
    printf '%s  %s\n' "$sha256" "$cache_path.tmp" | sha256sum -c -
    [[ "$(stat -c %s "$cache_path.tmp")" == "$size" ]] || {
      echo "Corresponding source size mismatch: $filename" >&2
      exit 1
    }
    mv "$cache_path.tmp" "$cache_path"
  fi

  cp -f "$cache_path" "$dest_path"
  printf '%s  %s\n' "$sha256" "$dest_path" | sha256sum -c - >/dev/null
done

python3 - "$MANIFEST" "$SOURCE_DIR/SOURCE-METADATA.json" <<'PY'
import json
import sys

manifest_path, output_path = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as f:
    data = json.load(f)

rpms = data["rpms"]
items = []
for source_key, source in data["corresponding_sources"].items():
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
    items.append(
        {
            "id": source_key,
            "filename": source["filename"],
            "url": source["url"],
            "sha256": source["sha256"],
            "size": source["size"],
            "binary_inputs": binary_inputs,
        }
    )

document = {
    "schema": 1,
    "purpose": "Corresponding source for GPL-covered compatibility payloads",
    "source_rpms": items,
}
with open(output_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(document, f, indent=2, sort_keys=True)
    f.write("\n")
PY

python3 - "$MANIFEST" "$SOURCE_DIR/SHA256SUMS" <<'PY'
import json
import sys

manifest_path, output_path = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as f:
    data = json.load(f)

lines = sorted(
    f'{source["sha256"]}  {source["filename"]}'
    for source in data["corresponding_sources"].values()
)
with open(output_path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
PY

cat >"$SOURCE_DIR/README.txt" <<'EOF'
Corresponding Source
====================

This directory accompanies the custom conda packages that redistribute selected
GCC runtime objects from AlmaLinux RPMs.

SOURCE-METADATA.json maps each redistributed binary input and selected payload
to its exact AlmaLinux source RPM. SHA256SUMS authenticates the mirrored source
RPM bytes.

The source RPMs are mirrored here so a public channel can offer object code and
its Corresponding Source through the same distribution surface. The original
AlmaLinux vault URLs remain recorded in SOURCE-METADATA.json as provenance.
EOF

echo "Prepared corresponding source bundle: $SOURCE_DIR"
