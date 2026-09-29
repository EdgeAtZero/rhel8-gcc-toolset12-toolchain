#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/rhel8-gcc-toolset12-toolchain"
CHANNEL_DIR="${CHANNEL_DIR:-$CACHE_ROOT/conda-channel}"
BUILD_DIR="${BUILD_DIR:-$CACHE_ROOT/conda-build}"
TOOLS_PREFIX="${TOOLS_PREFIX:-$CACHE_ROOT/conda-channel-tools}"
TEST_PREFIX="${TEST_PREFIX:-$CACHE_ROOT/conda-channel-test}"
BUILDER_LOCK="$REPO_ROOT/manifests/conda-builder-linux-64.lock"
TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION:-0.0.0}"
SEED_CHANNEL_URL="${SEED_CHANNEL_URL:-}"
export TOOLCHAIN_VERSION

[[ "$TOOLCHAIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  echo "Invalid TOOLCHAIN_VERSION: $TOOLCHAIN_VERSION" >&2
  exit 2
}

for command in micromamba curl sha256sum python3 /usr/bin/rpm2cpio /usr/bin/cpio; do
  if [[ "$command" == /* ]]; then
    [[ -x "$command" ]] || {
      echo "Required command not found: $command" >&2
      exit 1
    }
  else
    command -v "$command" >/dev/null 2>&1 || {
      echo "Required command not found: $command" >&2
      exit 1
    }
  fi
done

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) ;;
  *)
    echo "Local channel validation currently supports Linux x86_64 only." >&2
    exit 1
    ;;
esac

"$REPO_ROOT/scripts/verify-metadata-consistency.py"

builder_lock_hash="$(sha256sum "$BUILDER_LOCK" | awk '{print $1}')"
builder_lock_marker="$TOOLS_PREFIX/.explicit-lock.sha256"
if [[ ! -x "$TOOLS_PREFIX/bin/rattler-build" ]] ||
   [[ ! -f "$builder_lock_marker" ]] ||
   [[ "$(cat "$builder_lock_marker")" != "$builder_lock_hash" ]]; then
  rm -rf "$TOOLS_PREFIX"
  MAMBA_ROOT_PREFIX="$CACHE_ROOT/conda-channel-mamba" \
    micromamba --no-rc create -y -p "$TOOLS_PREFIX" -f "$BUILDER_LOCK"
  printf '%s\n' "$builder_lock_hash" >"$builder_lock_marker"
fi

RATTLER_BUILD="$TOOLS_PREFIX/bin/rattler-build"

rm -rf "$CHANNEL_DIR" "$BUILD_DIR" "$TEST_PREFIX"
mkdir -p "$BUILD_DIR"

if [[ -n "$SEED_CHANNEL_URL" ]]; then
  "$REPO_ROOT/scripts/seed-conda-channel.py" "$SEED_CHANNEL_URL" "$CHANNEL_DIR"
fi

publish_recipe() {
  local package="$1"
  local recipe="$2"
  local out="$BUILD_DIR/$package"
  shift 2

  mkdir -p "$out/noarch" "$out/linux-64"

  local build_args=(
    build
    --recipe "$recipe"
    --output-dir "$out"
    --package-format conda
    --test skip
  )
  "$RATTLER_BUILD" "${build_args[@]}" "$@"

  local artifact platform destination
  artifact="$(find "$out" -type f -name "$package-*.conda" -print | sort | tail -n 1)"
  [[ -n "$artifact" ]] || {
    echo "Built package not found for: $package" >&2
    exit 1
  }

  platform="$(basename "$(dirname "$artifact")")"
  destination="$CHANNEL_DIR/$platform/$(basename "$artifact")"

  if [[ -f "$CHANNEL_DIR/$platform/repodata.json" ]]; then
    python3 - "$CHANNEL_DIR/$platform/repodata.json" "$package" "$TOOLCHAIN_VERSION" "$recipe" <<'PY'
import json
import pathlib
import re
import sys

repodata_path, package, version, recipe_path = sys.argv[1:]
recipe_file = pathlib.Path(recipe_path)
if recipe_file.is_dir():
    recipe_file = recipe_file / "recipe.yaml"
recipe = recipe_file.read_text(encoding="utf-8")
match = re.search(r"^\s*number:\s*(\d+)\s*$", recipe, re.MULTILINE)
if match is None:
    raise SystemExit(f"Cannot determine build number from {recipe_path}")
build_number = int(match.group(1))

with open(repodata_path, encoding="utf-8") as f:
    repodata = json.load(f)

for group in ("packages", "packages.conda"):
    for record in repodata.get(group, {}).values():
        if (
            record.get("name") == package
            and record.get("version") == version
            and record.get("build_number") == build_number
        ):
            raise SystemExit(
                f"Refusing to reuse published conda coordinate: "
                f"{package} {version} build {build_number}"
            )
PY
  fi

  if [[ -e "$destination" ]]; then
    echo "Refusing to overwrite published conda package: $destination" >&2
    exit 1
  fi

  "$RATTLER_BUILD" publish "$artifact" --to "file://$CHANNEL_DIR"
}

publish_recipe rhel8-gcc-toolset12-compat "$REPO_ROOT/conda/recipes/compat" -c conda-forge
publish_recipe rhel8-gcc-toolset12-activate "$REPO_ROOT/conda/recipes/activate" -c "file://$CHANNEL_DIR" -c conda-forge
publish_recipe rhel8-gcc-toolset12-toolchain "$REPO_ROOT/conda/recipes/toolchain" -c "file://$CHANNEL_DIR" -c conda-forge

CHANNEL_DIR="$CHANNEL_DIR" "$REPO_ROOT/scripts/prepare-conda-sources.sh"
CHANNEL_DIR="$CHANNEL_DIR" "$REPO_ROOT/scripts/verify-conda-sources.sh"

test_mamba_root="$CACHE_ROOT/conda-channel-test-mamba"
if [[ -d "$test_mamba_root/pkgs" ]]; then
  python3 - "$test_mamba_root/pkgs" <<'PY'
import pathlib
import shutil
import sys

root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob("rhel8-gcc-toolset12-*"), key=lambda p: len(p.parts), reverse=True):
    if not path.exists() and not path.is_symlink():
        continue
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()
PY
fi

create_args=(
  --no-rc create -y
  -p "$TEST_PREFIX"
  --override-channels
  -c "file://$CHANNEL_DIR"
  -c conda-forge
  --strict-channel-priority
  "rhel8-gcc-toolset12-toolchain=$TOOLCHAIN_VERSION"
)
MAMBA_ROOT_PREFIX="$test_mamba_root" micromamba "${create_args[@]}"

PREFIX="$TEST_PREFIX" "$REPO_ROOT/scripts/verify-conda-channel.sh"
PREFIX="$TEST_PREFIX" "$REPO_ROOT/scripts/verify-conda-activation.sh"

echo
echo "Local channel:"
echo "  file://$CHANNEL_DIR"
echo "Test prefix:"
echo "  $TEST_PREFIX"
echo
echo "Manual install:"
printf '  micromamba create -y -p /tmp/rhel8-gcc12 --override-channels -c %q -c conda-forge --strict-channel-priority rhel8-gcc-toolset12-toolchain=%s\n' \
  "file://$CHANNEL_DIR" "$TOOLCHAIN_VERSION"
