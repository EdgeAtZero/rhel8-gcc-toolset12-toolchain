#!/usr/bin/env python3
import json
import pathlib
import re
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests/toolchain.json"
LOCK = ROOT / "manifests/conda-linux-64.lock"
BUILDER_LOCK = ROOT / "manifests/conda-builder-linux-64.lock"


def parse_lock(path: pathlib.Path):
    records = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line == "@EXPLICIT":
            continue
        url = line.split("#", 1)[0]
        filename = pathlib.PurePosixPath(urllib.parse.urlparse(url).path).name
        for suffix in (".conda", ".tar.bz2"):
            if filename.endswith(suffix):
                filename = filename[: -len(suffix)]
                break
        try:
            name, version, build = filename.rsplit("-", 2)
        except ValueError as exc:
            raise SystemExit(f"Cannot parse explicit package filename: {filename}") from exc
        if name in records:
            raise SystemExit(f"Duplicate package in explicit lock: {name}")
        records[name] = (version, build)
    return records


def exact_requirements(path: pathlib.Path):
    result = {}
    pattern = re.compile(r"^\s*-\s+([A-Za-z0-9_.-]+)\s+==([^\s]+)\s+([^\s]+)\s*$")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            result[match.group(1)] = (match.group(2), match.group(3))
    return result


manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
lock = parse_lock(LOCK)
builder_lock = parse_lock(BUILDER_LOCK)

gcc_version = manifest["compiler"]["gcc_version"]
sysroot_version = manifest["compiler"]["sysroot_version"]

for name in (
    "gcc_impl_linux-64",
    "gcc_linux-64",
    "gxx_impl_linux-64",
    "gxx_linux-64",
    "libgcc-devel_linux-64",
    "libstdcxx-devel_linux-64",
):
    actual = lock.get(name)
    if actual is None or actual[0] != gcc_version:
        raise SystemExit(
            f"{name}: lock version {actual!r} does not match manifest GCC {gcc_version}"
        )

actual_sysroot = lock.get("sysroot_linux-64")
if actual_sysroot is None or actual_sysroot[0] != sysroot_version:
    raise SystemExit(
        f"sysroot_linux-64: lock version {actual_sysroot!r} "
        f"does not match manifest sysroot {sysroot_version}"
    )

toolchain_recipe = ROOT / "conda/recipes/toolchain/recipe.yaml"
activate_recipe = ROOT / "conda/recipes/activate/recipe.yaml"
compat_recipe = ROOT / "conda/recipes/compat/recipe.yaml"

toolchain_requirements = exact_requirements(toolchain_recipe)
for name, expected in sorted(lock.items()):
    actual = toolchain_requirements.get(name)
    if actual != expected:
        raise SystemExit(
            f"toolchain recipe mismatch for {name}: recipe={actual}, lock={expected}"
        )

for recipe in (activate_recipe, toolchain_recipe):
    for name, actual in exact_requirements(recipe).items():
        if name in lock and actual != lock[name]:
            raise SystemExit(
                f"{recipe.relative_to(ROOT)} mismatch for {name}: "
                f"recipe={actual}, lock={lock[name]}"
            )

version_expression = 'version: ${{ env.get("TOOLCHAIN_VERSION", default="0.0.0") }}'
for recipe in (compat_recipe, activate_recipe, toolchain_recipe):
    text = recipe.read_text(encoding="utf-8")
    if version_expression not in text:
        raise SystemExit(
            f"{recipe.relative_to(ROOT)} must derive its package version "
            "from TOOLCHAIN_VERSION"
        )

for recipe in (activate_recipe, toolchain_recipe):
    text = recipe.read_text(encoding="utf-8")
    if "==${{ version }}" not in text:
        raise SystemExit(
            f"{recipe.relative_to(ROOT)} must pin custom package dependencies "
            "to the rendered release version"
        )

rattler = builder_lock.get("rattler-build")
if rattler is None or rattler[0] != "0.76.1":
    raise SystemExit(
        f"builder lock must pin rattler-build 0.76.1, found {rattler!r}"
    )

print("Manifest, explicit locks, and conda recipes are consistent.")
