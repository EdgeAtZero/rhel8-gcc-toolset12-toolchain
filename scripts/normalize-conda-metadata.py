#!/usr/bin/env python3
import json
import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit(f"Usage: {sys.argv[0]} PREFIX")

prefix = pathlib.Path(sys.argv[1]).resolve()
conda_meta = prefix / "conda-meta"
if not conda_meta.is_dir():
    raise SystemExit(f"conda-meta directory not found: {conda_meta}")

volatile_top_level = {
    "extracted_package_dir",
    "package_tarball_full_path",
}

for path in sorted(conda_meta.glob("*.json")):
    with path.open(encoding="utf-8") as f:
        data = json.load(f)

    for key in volatile_top_level:
        data.pop(key, None)

    link = data.get("link")
    if isinstance(link, dict):
        link.pop("source", None)
        if not link:
            data.pop("link", None)

    with path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, sort_keys=True, indent=2)
        f.write("\n")

history = conda_meta / "history"
history.write_text(
    "# Normalized standalone toolchain package state.\n"
    "# Exact inputs are recorded in ../CONDA-EXPLICIT.lock.\n",
    encoding="utf-8",
    newline="\n",
)
