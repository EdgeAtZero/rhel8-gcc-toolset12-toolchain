#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import json
import pathlib

parser = argparse.ArgumentParser()
parser.add_argument("--prefix", required=True)
parser.add_argument("--manifest", required=True)
parser.add_argument("--archive", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--version", default="dev")
parser.add_argument("--source-commit", default="unknown")
parser.add_argument("--source-date-epoch", type=int, required=True)
args = parser.parse_args()

prefix = pathlib.Path(args.prefix)
manifest_path = pathlib.Path(args.manifest)
archive_path = pathlib.Path(args.archive)
output_path = pathlib.Path(args.output)

with manifest_path.open(encoding="utf-8") as f:
    manifest = json.load(f)

def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

created = dt.datetime.fromtimestamp(args.source_date_epoch, tz=dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
archive_sha256 = sha256_file(archive_path)
manifest_sha256 = sha256_file(manifest_path)
namespace_version = args.source_commit if args.source_commit != "unknown" else manifest_sha256
namespace = (
    f"https://github.com/EdgeAtZero/rhel8-gcc-toolset12-toolchain/sbom/"
    f"{namespace_version}/{archive_sha256}"
)

packages = []
relationships = []
root_id = "SPDXRef-Toolchain"
packages.append({
    "SPDXID": root_id,
    "name": manifest["name"],
    "versionInfo": args.version,
    "downloadLocation": "NOASSERTION",
    "filesAnalyzed": False,
    "licenseConcluded": "NOASSERTION",
    "licenseDeclared": "NOASSERTION",
    "checksums": [{"algorithm": "SHA256", "checksumValue": archive_sha256}],
    "externalRefs": [{
        "referenceCategory": "OTHER",
        "referenceType": "manifest-sha256",
        "referenceLocator": manifest_sha256,
    }],
})

conda_meta = prefix / "conda-meta"
for index, meta_path in enumerate(sorted(conda_meta.glob("*.json")), start=1):
    with meta_path.open(encoding="utf-8") as f:
        meta = json.load(f)

    spdx_id = f"SPDXRef-Conda-{index}"
    package = {
        "SPDXID": spdx_id,
        "name": meta["name"],
        "versionInfo": meta["version"],
        "downloadLocation": meta.get("url") or "NOASSERTION",
        "filesAnalyzed": False,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": meta.get("license") or "NOASSERTION",
        "supplier": "Organization: conda-forge",
        "checksums": [],
        "externalRefs": [{
            "referenceCategory": "PACKAGE-MANAGER",
            "referenceType": "purl",
            "referenceLocator": f"pkg:conda/{meta['name']}@{meta['version']}?build={meta['build']}&channel=conda-forge",
        }],
    }
    if meta.get("sha256"):
        package["checksums"].append({"algorithm": "SHA256", "checksumValue": meta["sha256"]})
    if not package["checksums"]:
        package.pop("checksums")

    packages.append(package)
    relationships.append({
        "spdxElementId": root_id,
        "relationshipType": "CONTAINS",
        "relatedSpdxElement": spdx_id,
    })

for index, (key, rpm) in enumerate(sorted(manifest["rpms"].items()), start=1):
    filename = rpm["filename"]
    version = rpm.get("version") or filename
    spdx_id = f"SPDXRef-RPM-{index}"
    package_name = rpm.get("package") or key.replace("_", "-")
    packages.append({
        "SPDXID": spdx_id,
        "name": package_name,
        "versionInfo": version,
        "downloadLocation": rpm["url"],
        "filesAnalyzed": False,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": "NOASSERTION",
        "supplier": "Organization: AlmaLinux OS Foundation",
        "checksums": [{"algorithm": "SHA256", "checksumValue": rpm["sha256"]}],
        "externalRefs": [{
            "referenceCategory": "PACKAGE-MANAGER",
            "referenceType": "purl",
            "referenceLocator": f"pkg:rpm/almalinux/{package_name}@{version}?arch=x86_64",
        }],
    })
    relationships.append({
        "spdxElementId": root_id,
        "relationshipType": "CONTAINS",
        "relatedSpdxElement": spdx_id,
    })

document = {
    "spdxVersion": "SPDX-2.3",
    "dataLicense": "CC0-1.0",
    "SPDXID": "SPDXRef-DOCUMENT",
    "name": f"{manifest['name']}-{args.version}",
    "documentNamespace": namespace,
    "creationInfo": {
        "created": created,
        "creators": ["Tool: rhel8-gcc-toolset12-toolchain"],
    },
    "documentDescribes": [root_id],
    "packages": packages,
    "relationships": relationships,
}

output_path.parent.mkdir(parents=True, exist_ok=True)
with output_path.open("w", encoding="utf-8", newline="\n") as f:
    json.dump(document, f, sort_keys=True, indent=2)
    f.write("\n")
