#!/usr/bin/env python3
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
INPUTS = (
    "action.yml",
    "manifests/toolchain.json",
    "manifests/conda-linux-64.lock",
    "scripts/toolchain-identity.py",
    "scripts/install-micromamba.sh",
    "scripts/build-toolchain.sh",
    "scripts/normalize-conda-metadata.py",
    "scripts/resolve-toolchain-prefix.sh",
)

digest = hashlib.sha256()
for relative in INPUTS:
    path = ROOT / relative
    data = path.read_bytes()
    encoded = relative.encode("utf-8")
    digest.update(len(encoded).to_bytes(4, "big"))
    digest.update(encoded)
    digest.update(len(data).to_bytes(8, "big"))
    digest.update(data)

print(digest.hexdigest())
