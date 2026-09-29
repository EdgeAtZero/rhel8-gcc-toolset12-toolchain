#!/usr/bin/env python3
import argparse
import json
import pathlib

parser = argparse.ArgumentParser(
    description="Export a micromamba/conda prefix as a SHA-256-pinned @EXPLICIT lock."
)
parser.add_argument("prefix")
parser.add_argument("output")
args = parser.parse_args()

prefix = pathlib.Path(args.prefix)
conda_meta = prefix / "conda-meta"
if not conda_meta.is_dir():
    raise SystemExit(f"conda-meta directory not found: {conda_meta}")

records = []
for path in conda_meta.glob("*.json"):
    with path.open(encoding="utf-8") as f:
        data = json.load(f)

    name = data.get("name")
    url = data.get("url")
    sha256 = data.get("sha256")
    if not name or not url or not sha256:
        raise SystemExit(f"Missing name/url/sha256 in {path}")

    records.append((name, f"{url}#{sha256}"))

records.sort(key=lambda item: item[0])

output = pathlib.Path(args.output)
output.parent.mkdir(parents=True, exist_ok=True)
with output.open("w", encoding="utf-8", newline="\n") as f:
    f.write("# Exact conda-forge input set for linux-x86_64-rhel8-gcc-toolset12.\n")
    f.write("# Generated from a verified prefix by scripts/export-conda-lock.py.\n")
    f.write("# This is a single-platform explicit specification; no solver is used at build time.\n")
    f.write("@EXPLICIT\n")
    for _, record in records:
        f.write(record + "\n")
