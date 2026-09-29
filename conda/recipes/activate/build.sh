#!/usr/bin/env bash
set -euo pipefail

target="x86_64-conda-linux-gnu"
gcc_version="12.4.0"
spec_src="$PREFIX/lib/gcc/$target/$gcc_version/specs"
spec_dir="$PREFIX/share/rhel8-gcc-toolset12"
spec_dst="$spec_dir/link.specs"

[[ -f "$spec_src" ]] || {
  echo "Expected conda-forge GCC specs not found: $spec_src" >&2
  exit 1
}

install -d "$spec_dir"

python - "$spec_src" "$spec_dst" "$PREFIX" <<'PY'
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

wrapper_dir="$PREFIX/libexec/rhel8-gcc-toolset12/bin"
install -d "$wrapper_dir"

cat >"$wrapper_dir/compiler-wrapper" <<'EOF'
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
chmod 0755 "$wrapper_dir/compiler-wrapper"

for name in gcc cc g++ c++ cpp; do
  ln -s compiler-wrapper "$wrapper_dir/$target-$name"
done

ln -s "$target-gcc" "$wrapper_dir/gcc"
ln -s "$target-cc" "$wrapper_dir/cc"
ln -s "$target-g++" "$wrapper_dir/g++"
ln -s "$target-c++" "$wrapper_dir/c++"
ln -s "$target-cpp" "$wrapper_dir/cpp"

activate_dir="$PREFIX/etc/conda/activate.d"
deactivate_dir="$PREFIX/etc/conda/deactivate.d"
install -d "$activate_dir" "$deactivate_dir"

cat >"$activate_dir/zz-rhel8-gcc-toolset12.sh" <<'EOF'
_RHEL8_GCC_TOOLSET12_BIN="$CONDA_PREFIX/libexec/rhel8-gcc-toolset12/bin"
_RHEL8_GCC_TOOLSET12_TARGET="x86_64-conda-linux-gnu"

export PATH="$_RHEL8_GCC_TOOLSET12_BIN:$PATH"

# Keep the same target-prefixed compiler identity exposed by conda-forge's
# compiler activation, but route compiler-driver invocations through the
# compatibility wrapper.
export CC="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-cc"
export CXX="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-c++"
export CPP="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-cpp"
export GCC="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-gcc"
export GXX="$_RHEL8_GCC_TOOLSET12_BIN/$_RHEL8_GCC_TOOLSET12_TARGET-g++"
export CC_FOR_BUILD="$CC"
export CXX_FOR_BUILD="$CXX"

# conda-forge's GCC activation adds a prefix RPATH to LDFLAGS. The wrapper
# removes the same RPATH from GCC specs; remove the environment-level copy too
# so CMake/Autoconf projects do not reintroduce it.
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

# Compiler variables and LDFLAGS are intentionally left to the conda-forge
# compiler deactivate scripts, which restore their CONDA_BACKUP_* values from
# before this environment was activated.
EOF
