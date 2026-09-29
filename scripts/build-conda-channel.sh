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
TEST_PREFIX="${TEST_PREFIX:-/tmp/rhel8-gcc-toolset12-conda-channel-test}"
RATTLER_BUILD_VERSION="${RATTLER_BUILD_VERSION:-0.76.1}"

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

if [[ ! -x "$TOOLS_PREFIX/bin/rattler-build" ]] ||
   [[ "$("$TOOLS_PREFIX/bin/rattler-build" --version | awk '{print $2}')" != "$RATTLER_BUILD_VERSION" ]]; then
  rm -rf "$TOOLS_PREFIX"
  MAMBA_ROOT_PREFIX="$CACHE_ROOT/conda-channel-mamba" micromamba --no-rc create -y -p "$TOOLS_PREFIX" -c conda-forge --strict-channel-priority "rattler-build=$RATTLER_BUILD_VERSION"
fi

RATTLER_BUILD="$TOOLS_PREFIX/bin/rattler-build"

rm -rf "$CHANNEL_DIR" "$BUILD_DIR" "$TEST_PREFIX"
mkdir -p "$BUILD_DIR"

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

  local artifact
  artifact="$(find "$out" -type f -name "$package-*.conda" -print | sort | tail -n 1)"
  [[ -n "$artifact" ]] || {
    echo "Built package not found for: $package" >&2
    exit 1
  }

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
  "rhel8-gcc-toolset12-toolchain=1.0.0"
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
printf '  micromamba create -y -p /tmp/rhel8-gcc12 --override-channels -c %q -c conda-forge --strict-channel-priority rhel8-gcc-toolset12-toolchain=1.0.0\n' "file://$CHANNEL_DIR"
