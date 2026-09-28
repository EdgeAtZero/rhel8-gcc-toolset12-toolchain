#!/usr/bin/env bash
set -euo pipefail

TOOLCHAIN_NAME="linux-x86_64-rhel8-gcc-toolset12"
DEFAULT_PREFIX="/opt/toolchains/$TOOLCHAIN_NAME"
PREFIX="$DEFAULT_PREFIX"
FORCE=0

GCC_VERSION="12.2.0"
SYSROOT_VERSION="2.28"
TARGET="x86_64-conda-linux-gnu"

ALMA_BASEOS="https://repo.almalinux.org/almalinux/8/BaseOS/x86_64/os/Packages"
ALMA_APPSTREAM="https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages"

LIBSTDCXX_RPM="libstdc++-8.5.0-28.el8_10.alma.1.x86_64.rpm"
LIBSTDCXX_SHA256="0302b9006d719a31dd51aeaf31fec03d70aad5c318674537bd80c49f9174b066"
LIBGCC_RPM="libgcc-8.5.0-28.el8_10.alma.1.x86_64.rpm"
LIBGCC_SHA256="629a08266f7c1397c00d7c32c0ac6d110fe56e993dcf94024559aa28a570f18d"
GTS_RPM="gcc-toolset-12-libstdc++-devel-12.2.1-7.8.el8_10.x86_64.rpm"
GTS_SHA256="acdc19b1ee0b01cbf06377522bd412c20ca2bdbda68630ea6c9ae9ca7c344711"

usage() {
  cat <<EOF
Usage: $0 [--prefix PATH] [--force]

Build the RHEL 8 / GCC Toolset 12 compatibility toolchain.

Options:
  --prefix PATH   Installation prefix (default: $DEFAULT_PREFIX)
  --force         Remove an existing prefix before rebuilding
  -h, --help      Show this help
EOF
}

while (($#)); do
  case "$1" in
    --prefix)
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

for cmd in micromamba curl sha256sum rpm2cpio cpio python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Required command not found: $cmd" >&2
    exit 1
  }
done

SUDO=()
if [[ "$PREFIX" == /opt/* && ! -w "$(dirname "$PREFIX")" ]]; then
  command -v sudo >/dev/null 2>&1 || {
    echo "sudo is required to install under /opt." >&2
    exit 1
  }
  SUDO=(sudo)
fi

if [[ -e "$PREFIX" ]]; then
  if ((FORCE)); then
    "${SUDO[@]}" rm -rf "$PREFIX"
  else
    echo "Prefix already exists: $PREFIX" >&2
    echo "Use --force to rebuild it." >&2
    exit 1
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
    curl -fL --retry 3 "$url/$file" -o "$dst"
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

download_and_verify "$ALMA_BASEOS" "$LIBSTDCXX_RPM" "$LIBSTDCXX_SHA256"
download_and_verify "$ALMA_BASEOS" "$LIBGCC_RPM" "$LIBGCC_SHA256"
download_and_verify "$ALMA_APPSTREAM" "$GTS_RPM" "$GTS_SHA256"

extract_rpm "$CACHE_ROOT/$LIBSTDCXX_RPM" "$WORK_DIR/libstdcxx"
extract_rpm "$CACHE_ROOT/$LIBGCC_RPM" "$WORK_DIR/libgcc"
extract_rpm "$CACHE_ROOT/$GTS_RPM" "$WORK_DIR/gts"

MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$CACHE_ROOT/mamba-root}"
"${SUDO[@]}" env MAMBA_ROOT_PREFIX="$MAMBA_ROOT_PREFIX" micromamba create -y   -p "$PREFIX"   -c conda-forge   --strict-channel-priority   "gcc_linux-64=$GCC_VERSION"   "gxx_linux-64=$GCC_VERSION"   "sysroot_linux-64=$SYSROOT_VERSION"   "libstdcxx-devel_linux-64=$GCC_VERSION"   "libgcc-devel_linux-64=$GCC_VERSION"   binutils_linux-64

SYSROOT="$PREFIX/$TARGET/sysroot"
TARGET_LIB="$PREFIX/$TARGET/lib"
GCC_LIB="$PREFIX/lib/gcc/$TARGET/$GCC_VERSION"
SPECS="$GCC_LIB/specs"

"${SUDO[@]}" install -D -m 0755   "$WORK_DIR/libstdcxx/usr/lib64/libstdc++.so.6.0.25"   "$SYSROOT/usr/lib64/libstdc++.so.6.0.25"
"${SUDO[@]}" ln -sfn libstdc++.so.6.0.25 "$SYSROOT/usr/lib64/libstdc++.so.6"

"${SUDO[@]}" install -D -m 0755   "$WORK_DIR/libgcc/lib64/libgcc_s.so.1"   "$SYSROOT/usr/lib64/libgcc_s.so.1"

"${SUDO[@]}" install -m 0644   "$WORK_DIR/gts/opt/rh/gcc-toolset-12/root/usr/lib/gcc/x86_64-redhat-linux/12/libstdc++_nonshared.a"   "$GCC_LIB/libstdc++_nonshared.a"

"${SUDO[@]}" rm -f   "$TARGET_LIB/libstdc++.so"   "$TARGET_LIB/libstdc++.so.6"   "$TARGET_LIB/libstdc++.so.6.0.30"

cat >"$WORK_DIR/libstdc++.so" <<'EOF'
/* RHEL 8 / GCC Toolset 12 compatibility linker script. */
INPUT ( libstdc++.so.6 -lstdc++_nonshared )
EOF
"${SUDO[@]}" install -m 0644 "$WORK_DIR/libstdc++.so" "$TARGET_LIB/libstdc++.so"
"${SUDO[@]}" ln -sfn "$SYSROOT/usr/lib64/libstdc++.so.6" "$TARGET_LIB/libstdc++.so.6"

"${SUDO[@]}" rm -f "$TARGET_LIB/libgcc_s.so" "$TARGET_LIB/libgcc_s.so.1"
cat >"$WORK_DIR/libgcc_s.so" <<'EOF'
/* RHEL 8 compatibility linker script. */
GROUP ( libgcc_s.so.1 -lgcc )
EOF
"${SUDO[@]}" install -m 0644 "$WORK_DIR/libgcc_s.so" "$TARGET_LIB/libgcc_s.so"
"${SUDO[@]}" ln -sfn "$SYSROOT/usr/lib64/libgcc_s.so.1" "$TARGET_LIB/libgcc_s.so.1"

if [[ -f "$SPECS" ]]; then
  "${SUDO[@]}" cp -a "$SPECS" "$SPECS.conda.bak"
  python3 - "$SPECS" "$PREFIX" "$WORK_DIR/specs" <<'PY'
import pathlib
import sys

src = pathlib.Path(sys.argv[1])
prefix = sys.argv[2]
dst = pathlib.Path(sys.argv[3])

text = src.read_text()
fragment = f" %{{!static:-rpath {prefix}/lib}}"
if fragment not in text:
    raise SystemExit(f"Expected conda RPATH fragment not found: {fragment}")
dst.write_text(text.replace(fragment, ""))
PY
  "${SUDO[@]}" install -m 0644 "$WORK_DIR/specs" "$SPECS"
fi

compiler="$PREFIX/bin/$TARGET-gcc"
target="$("$compiler" -dumpmachine)"

link_short() {
  local short="$1"
  local target_name="$2"
  local src="$PREFIX/bin/$target_name"

  [[ -e "$src" ]] || return 0
  "${SUDO[@]}" ln -sfn "$target_name" "$PREFIX/bin/$short"
}

for name in gcc g++ cpp ar as ld nm objcopy objdump ranlib readelf strings strip addr2line c++filt elfedit size gprof; do
  link_short "$name" "$target-$name"
done
"${SUDO[@]}" ln -sfn gcc "$PREFIX/bin/cc"
"${SUDO[@]}" ln -sfn g++ "$PREFIX/bin/c++"

cat >"$WORK_DIR/TOOLCHAIN-METADATA.txt" <<EOF
Toolchain: $TOOLCHAIN_NAME
Prefix: $PREFIX
Target: $TARGET
GCC: $GCC_VERSION
glibc sysroot: $SYSROOT_VERSION

Runtime ABI source:
  AlmaLinux 8 BaseOS $LIBSTDCXX_RPM
  AlmaLinux 8 BaseOS $LIBGCC_RPM
  AlmaLinux 8 AppStream $GTS_RPM

Compatibility model:
  GCC 12 C++ headers/compiler
  + RHEL 8 GCC 8-era shared libstdc++/libgcc_s
  + GCC Toolset 12 libstdc++_nonshared.a

Expected ceilings:
  GLIBC <= 2.28
  GLIBCXX <= 3.4.25
EOF
"${SUDO[@]}" install -m 0644 "$WORK_DIR/TOOLCHAIN-METADATA.txt" "$PREFIX/TOOLCHAIN-METADATA.txt"

echo
echo "Created: $PREFIX"
echo "Compiler: $("$PREFIX/bin/gcc" --version | head -n 1)"
echo "Sysroot : $("$PREFIX/bin/gcc" -print-sysroot)"
echo
echo "Run scripts/verify-toolchain.sh to validate the ABI."
