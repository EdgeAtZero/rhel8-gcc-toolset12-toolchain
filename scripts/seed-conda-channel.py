#!/usr/bin/env python3
import argparse
import json
import pathlib
import urllib.error
import urllib.request

parser = argparse.ArgumentParser(
    description="Seed a local conda channel with the currently published immutable history."
)
parser.add_argument("channel_url")
parser.add_argument("destination")
args = parser.parse_args()

base = args.channel_url.rstrip("/")
destination = pathlib.Path(args.destination)
destination.mkdir(parents=True, exist_ok=True)


def fetch(relative: str, required: bool = True):
    url = f"{base}/{relative}"
    try:
        with urllib.request.urlopen(url) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        if exc.code == 404 and not required:
            return None
        raise


def download(relative: str, target: pathlib.Path):
    data = fetch(relative)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)


for subdir in ("linux-64", "noarch"):
    raw = fetch(f"{subdir}/repodata.json", required=False)
    if raw is None:
        continue
    target_dir = destination / subdir
    target_dir.mkdir(parents=True, exist_ok=True)
    (target_dir / "repodata.json").write_bytes(raw)
    repodata = json.loads(raw)
    package_names = sorted(
        set(repodata.get("packages", {})) | set(repodata.get("packages.conda", {}))
    )
    for filename in package_names:
        download(f"{subdir}/{filename}", destination / subdir / filename)

source_raw = fetch("sources/SOURCE-METADATA.json", required=False)
if source_raw is not None:
    source_dir = destination / "sources"
    source_dir.mkdir(parents=True, exist_ok=True)
    metadata = json.loads(source_raw)
    (source_dir / "SOURCE-METADATA.json").write_bytes(source_raw)
    for item in metadata.get("source_rpms", []):
        filename = item["filename"]
        download(f"sources/{filename}", source_dir / filename)
    for filename in ("SHA256SUMS", "README.txt"):
        raw = fetch(f"sources/{filename}", required=False)
        if raw is not None:
            (source_dir / filename).write_bytes(raw)

print(f"Seeded published channel history from {base}")
