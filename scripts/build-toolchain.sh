#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/manifests/toolchain.json"

for cmd in python3 micromamba curl sha256sum rpm2cpio cpio install ln rm mkdir id readlink grep; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Required command not found: $cmd" >&2
    exit 1
  }
done

mapfile -d '' -t manifest_values < <(
  python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

values = [
    data["name"],
    data["target"],
    data["environment_name"],
    data["compiler"]["gcc_version"],
    data["compiler"]["sysroot_version"],
    data["compiler"]["conda_lock"],
    data["abi"]["glibc_max"],
    data["abi"]["glibcxx_max"],
    data["abi"]["cxxabi_max"],
    data["abi"]["gcc_max"],
    data["abi"]["interpreter"],
    data["abi"]["libstdcxx_runtime"],
]

for key in ("libstdcxx", "libgcc", "libstdcxx_nonshared"):
    rpm = data["rpms"][key]
    values.extend((rpm["filename"], rpm["url"], rpm["sha256"], rpm["payload"]))

for value in values:
    print(value, end="\0")
PY
)

(("${#manifest_values[@]}" == 24)) || {
  echo "Invalid toolchain manifest: expected 24 values, got ${#manifest_values[@]}." >&2
  exit 1
}

TOOLCHAIN_NAME="${manifest_values[0]}"
TARGET="${manifest_values[1]}"
ENVIRONMENT_NAME="${manifest_values[2]}"
GCC_VERSION="${manifest_values[3]}"
SYSROOT_VERSION="${manifest_values[4]}"
CONDA_LOCK_REL="${manifest_values[5]}"
GLIBC_MAX="${manifest_values[6]}"
GLIBCXX_MAX="${manifest_values[7]}"
CXXABI_MAX="${manifest_values[8]}"
GCC_ABI_MAX="${manifest_values[9]}"
INTERPRETER="${manifest_values[10]}"
LIBSTDCXX_RUNTIME="${manifest_values[11]}"

LIBSTDCXX_RPM="${manifest_values[12]}"
LIBSTDCXX_URL="${manifest_values[13]}"
LIBSTDCXX_SHA256="${manifest_values[14]}"
LIBSTDCXX_PAYLOAD="${manifest_values[15]}"

LIBGCC_RPM="${manifest_values[16]}"
LIBGCC_URL="${manifest_values[17]}"
LIBGCC_SHA256="${manifest_values[18]}"
LIBGCC_PAYLOAD="${manifest_values[19]}"

NONSHARED_RPM="${manifest_values[20]}"
NONSHARED_URL="${manifest_values[21]}"
NONSHARED_SHA256="${manifest_values[22]}"
NONSHARED_PAYLOAD="${manifest_values[23]}"

CONDA_LOCK="$REPO_ROOT/$CONDA_LOCK_REL"
PREFIX=""
FORCE=0

usage() {
  cat <<EOF
Usage: $0 [--prefix PATH] [--force]

Build the RHEL 8 / GCC Toolset 12 compatibility toolchain from pinned inputs.

Options:
  --prefix PATH   Override the micromamba named-environment location
  --force         Remove an existing prefix before rebuilding
  -h, --help      Show this help
EOF
}

while (($#)); do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || {
        echo "--prefix requires a value." >&2
        exit 2
      }
      PREFIX="$2"
      shift 2
      ;;
    --prefix=*)
      PREFIX="${1#*=}"
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -f "$CONDA_LOCK" ]] || {
  echo "Conda explicit lock not found: $CONDA_LOCK" >&2
  exit 1
}
grep -Fx '@EXPLICIT' "$CONDA_LOCK" >/dev/null || {
  echo "Conda lock is not an explicit specification: $CONDA_LOCK" >&2
  exit 1
}

if [[ -n "$PREFIX" ]]; then
  if [[ -e "$PREFIX" ]]; then
    if ((FORCE)); then
      rm -rf "$PREFIX"
    else
      echo "Prefix already exists: $PREFIX" >&2
      echo "Use --force to rebuild it." >&2
      exit 1
    fi
  fi
  mkdir -p "$(dirname "$PREFIX")"
else
  if micromamba run -n "$ENVIRONMENT_NAME" true >/dev/null 2>&1; then
    if ((FORCE)); then
      micromamba env remove -y -n "$ENVIRONMENT_NAME"
    else
      echo "Micromamba environment already exists: $ENVIRONMENT_NAME" >&2
      echo "Use --force to rebuild it." >&2
      exit 1
    fi
  fi
fi

CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/rhel8-gcc-toolset12-toolchain"
mkdir -p "$CACHE_ROOT"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

download_and_verify() {
  local url="$1"
  local file="$2"
  local sha256="$3"
  local dst="$CACHE_ROOT/$file"

  if [[ ! -f "$dst" ]] || ! printf '%s  %s\n' "$sha256" "$dst" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$dst"
    curl --fail --location --retry 5 --retry-all-errors --proto '=https' --tlsv1.2 "$url" -o "$dst"
  fi

  printf '%s  %s\n' "$sha256" "$dst" | sha256sum -c -
}

extract_rpm() {
  local rpm="$1"
  local dst="$2"
  mkdir -p "$dst"
  (
    cd "$dst"
    rpm2cpio "$rpm" | cpio -idm --quiet
  )
}

download_and_verify "$LIBSTDCXX_URL" "$LIBSTDCXX_RPM" "$LIBSTDCXX_SHA256"
download_and_verify "$LIBGCC_URL" "$LIBGCC_RPM" "$LIBGCC_SHA256"
download_and_verify "$NONSHARED_URL" "$NONSHARED_RPM" "$NONSHARED_SHA256"

extract_rpm "$CACHE_ROOT/$LIBSTDCXX_RPM" "$WORK_DIR/libstdcxx"
extract_rpm "$CACHE_ROOT/$LIBGCC_RPM" "$WORK_DIR/libgcc"
extract_rpm "$CACHE_ROOT/$NONSHARED_RPM" "$WORK_DIR/nonshared"

for payload in   "$WORK_DIR/libstdcxx/$LIBSTDCXX_PAYLOAD"   "$WORK_DIR/libgcc/$LIBGCC_PAYLOAD"   "$WORK_DIR/nonshared/$NONSHARED_PAYLOAD"; do
  [[ -f "$payload" ]] || {
    echo "Expected RPM payload was not found: $payload" >&2
    exit 1
  }
done

if [[ -n "$PREFIX" ]]; then
  micromamba create -y -p "$PREFIX" -f "$CONDA_LOCK"
else
  micromamba create -y -n "$ENVIRONMENT_NAME" -f "$CONDA_LOCK"
  PREFIX="$(micromamba run -n "$ENVIRONMENT_NAME" sh -c 'printf "%s\n" "$CONDA_PREFIX"')"
fi

compiler="$PREFIX/bin/$TARGET-gcc"
[[ -x "$compiler" ]] || {
  echo "Pinned compiler was not installed: $compiler" >&2
  exit 1
}

actual_target="$("$compiler" -dumpmachine)"
[[ "$actual_target" == "$TARGET" ]] || {
  echo "Unexpected compiler target: $actual_target (expected $TARGET)" >&2
  exit 1
}

actual_gcc="$("$compiler" -dumpfullversion)"
[[ "$actual_gcc" == "$GCC_VERSION" ]] || {
  echo "Unexpected GCC version: $actual_gcc (expected $GCC_VERSION)" >&2
  exit 1
}

SYSROOT="$PREFIX/$TARGET/sysroot"
GCC_LIB="$PREFIX/lib/gcc/$TARGET/$GCC_VERSION"
SPEC_SRC="$GCC_LIB/specs"
SPEC_DIR="$PREFIX/share/rhel8-gcc-toolset12"
SPEC_DST="$SPEC_DIR/link.specs"
COMPAT="$PREFIX/lib/rhel8-gcc-toolset12"
WRAPPER_DIR="$PREFIX/libexec/rhel8-gcc-toolset12/bin"

actual_sysroot="$(readlink -f "$("$compiler" -print-sysroot)")"
expected_sysroot="$(readlink -f "$SYSROOT")"
[[ "$actual_sysroot" == "$expected_sysroot" ]] || {
  echo "Unexpected compiler sysroot: $actual_sysroot" >&2
  echo "Expected: $expected_sysroot" >&2
  exit 1
}

install -d "$COMPAT" "$SPEC_DIR" "$WRAPPER_DIR"

install -m 0755 "$WORK_DIR/libstdcxx/$LIBSTDCXX_PAYLOAD" "$COMPAT/$LIBSTDCXX_RUNTIME"
ln -sfn "$LIBSTDCXX_RUNTIME" "$COMPAT/libstdc++.so.6"

install -m 0755 "$WORK_DIR/libgcc/$LIBGCC_PAYLOAD" "$COMPAT/libgcc_s.so.1"
install -m 0644 "$WORK_DIR/nonshared/$NONSHARED_PAYLOAD" "$COMPAT/libstdc++_nonshared.a"

cat >"$COMPAT/libstdc++.so" <<'EOF'
/* RHEL 8 / GCC Toolset 12 compatibility linker script. */
INPUT ( libstdc++.so.6 -lstdc++_nonshared )
EOF

cat >"$COMPAT/libgcc_s.so" <<'EOF'
/* RHEL 8 compatibility linker script. */
GROUP ( libgcc_s.so.1 -lgcc )
EOF

[[ -f "$SPEC_SRC" ]] || {
  echo "Expected GCC specs file not found: $SPEC_SRC" >&2
  exit 1
}

python3 - "$SPEC_SRC" "$SPEC_DST" "$PREFIX" <<'PY'
import pathlib
import sys

src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
dst = pathlib.Path(sys.argv[2])
prefix = sys.argv[3]

marker = "*link_command:\n"
start = src.find(marker)
if start < 0:
    raise SystemExit("GCC specs does not contain *link_command")

end = src.find("\n*", start + len(marker))
if end < 0:
    end = len(src)

section = src[start:end]
needle = f"%{{!static:-rpath {prefix}/lib}}"
count = section.count(needle)
if count != 1:
    raise SystemExit(
        f"Expected exactly one conda prefix RPATH fragment, found {count}: {needle}"
    )

dst.write_text(section.replace(needle, "", 1) + "\n", encoding="utf-8")
PY

cat >"$WRAPPER_DIR/compiler-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

self="$(readlink -f "$0")"
self_dir="$(cd "$(dirname "$self")" && pwd)"
prefix="$(cd "$self_dir/../../.." && pwd)"
target="x86_64-conda-linux-gnu"
name="$(basename "$0")"
name="${name#"$target-"}"

case "$name" in
  gcc|cc)
    real="$prefix/bin/$target-gcc"
    ;;
  g++|c++)
    real="$prefix/bin/$target-g++"
    ;;
  cpp)
    exec "$prefix/bin/$target-cpp" "$@"
    ;;
  *)
    echo "Unsupported compiler wrapper name: $name" >&2
    exit 2
    ;;
esac

exec "$real" \
  -specs="$prefix/share/rhel8-gcc-toolset12/link.specs" \
  -L"$prefix/lib/rhel8-gcc-toolset12" \
  "$@"
EOF
chmod 0755 "$WRAPPER_DIR/compiler-wrapper"

for name in gcc cc g++ c++ cpp; do
  ln -s "compiler-wrapper" "$WRAPPER_DIR/$TARGET-$name"
done
ln -s "$TARGET-gcc" "$WRAPPER_DIR/gcc"
ln -s "$TARGET-cc" "$WRAPPER_DIR/cc"
ln -s "$TARGET-g++" "$WRAPPER_DIR/g++"
ln -s "$TARGET-c++" "$WRAPPER_DIR/c++"
ln -s "$TARGET-cpp" "$WRAPPER_DIR/cpp"

# Keep convenient short command names in the assembled environment while
# routing compiler drivers through the compatibility wrappers.
for name in gcc cc g++ c++ cpp; do
  ln -sfn "../libexec/rhel8-gcc-toolset12/bin/$name" "$PREFIX/bin/$name"
done

# Binutils stay on the conda-forge target-prefixed binaries.
for name in ar as ld nm objcopy objdump ranlib readelf strings strip addr2line c++filt elfedit size gprof; do
  target_name="$TARGET-$name"
  [[ -e "$PREFIX/bin/$target_name" ]] || continue
  ln -sfn "$target_name" "$PREFIX/bin/$name"
done

if "$PREFIX/bin/gcc" -dumpspecs | grep -F -- "-rpath $PREFIX/lib" >/dev/null; then
  echo "Conda prefix RPATH is still present in effective GCC specs." >&2
  exit 1
fi

activate_dir="$PREFIX/etc/conda/activate.d"
deactivate_dir="$PREFIX/etc/conda/deactivate.d"
install -d "$activate_dir" "$deactivate_dir"

cat >"$activate_dir/zz-rhel8-gcc-toolset12.sh" <<'EOF'
_RHEL8_GCC_TOOLSET12_BIN="$CONDA_PREFIX/libexec/rhel8-gcc-toolset12/bin"
_RHEL8_GCC_TOOLSET12_TARGET="x86_64-conda-linux-gnu"

export PATH="$_RHEL8_GCC_TOOLSET12_BIN:$PATH"
export CC="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-cc"
export CXX="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-c++"
export CPP="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-cpp"
export GCC="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-gcc"
export GXX="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-g++"
export CC_FOR_BUILD="$CC"
export CXX_FOR_BUILD="$CXX"

if [ -n "${LDFLAGS:-}" ]; then
  _RHEL8_GCC_TOOLSET12_RPATH="-Wl,-rpath,$CONDA_PREFIX/lib"
  LDFLAGS=" ${LDFLAGS} "
  LDFLAGS="${LDFLAGS// $_RHEL8_GCC_TOOLSET12_RPATH / }"
  LDFLAGS="${LDFLAGS# }"
  LDFLAGS="${LDFLAGS% }"
  export LDFLAGS
  unset _RHEL8_GCC_TOOLSET12_RPATH
fi

unset _RHEL8_GCC_TOOLSET12_TARGET
unset _RHEL8_GCC_TOOLSET12_BIN
EOF

cat >"$deactivate_dir/zz-rhel8-gcc-toolset12.sh" <<'EOF'
_RHEL8_GCC_TOOLSET12_BIN="$CONDA_PREFIX/libexec/rhel8-gcc-toolset12/bin"
case ":$PATH:" in
  *":$_RHEL8_GCC_TOOLSET12_BIN:"*)
    PATH=":$PATH:"
    PATH="${PATH//:$_RHEL8_GCC_TOOLSET12_BIN:/:}"
    PATH="${PATH#:}"
    PATH="${PATH%:}"
    export PATH
    ;;
esac
unset _RHEL8_GCC_TOOLSET12_BIN
EOF

install -m 0644 "$MANIFEST" "$PREFIX/TOOLCHAIN-MANIFEST.json"
install -m 0644 "$CONDA_LOCK" "$PREFIX/CONDA-EXPLICIT.lock"

manifest_sha256="$(sha256sum "$MANIFEST" | awk '{print $1}')"
lock_sha256="$(sha256sum "$CONDA_LOCK" | awk '{print $1}')"

cat >"$WORK_DIR/TOOLCHAIN-METADATA.txt" <<EOF
Toolchain: $TOOLCHAIN_NAME
Prefix: $PREFIX
Target: $TARGET
GCC: $GCC_VERSION
glibc sysroot: $SYSROOT_VERSION
Manifest SHA-256: $manifest_sha256
Conda explicit lock SHA-256: $lock_sha256

Runtime ABI source:
  $LIBSTDCXX_RPM
  $LIBGCC_RPM
  $NONSHARED_RPM

Compatibility model:
  GCC 12 C++ headers/compiler
  + RHEL 8 GCC 8-era shared libstdc++/libgcc_s
  + GCC Toolset 12 libstdc++_nonshared.a

Expected ceilings:
  GLIBC <= $GLIBC_MAX
  GLIBCXX <= $GLIBCXX_MAX
  CXXABI <= $CXXABI_MAX
  GCC ABI <= $GCC_ABI_MAX
  Interpreter = $INTERPRETER
EOF
install -m 0644 "$WORK_DIR/TOOLCHAIN-METADATA.txt" "$PREFIX/TOOLCHAIN-METADATA.txt"

python3 "$REPO_ROOT/scripts/normalize-conda-metadata.py" "$PREFIX"

echo
echo "Created: $PREFIX"
echo "Compiler: $("$PREFIX/bin/gcc" --version | head -n 1)"
echo "Sysroot : $("$PREFIX/bin/gcc" -print-sysroot)"
echo "Inputs  : $CONDA_LOCK_REL + pinned AlmaLinux 8.10 RPMs"
echo
echo "Run scripts/verify-toolchain.sh to validate the ABI."
