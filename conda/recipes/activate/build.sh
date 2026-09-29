#!/usr/bin/env bash
set -euo pipefail

target="x86_64-conda-linux-gnu"
gcc_version="12.2.0"
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

self_dir="$(cd "$(dirname "$0")" && pwd)"
prefix="$(cd "$self_dir/../../.." && pwd)"
name="$(basename "$0")"

case "$name" in
  gcc|cc) real="$prefix/bin/x86_64-conda-linux-gnu-gcc" ;;
  g++|c++) real="$prefix/bin/x86_64-conda-linux-gnu-g++" ;;
  cpp) exec "$prefix/bin/x86_64-conda-linux-gnu-cpp" "$@" ;;
  *)
    echo "Unsupported compiler wrapper name: $name" >&2
    exit 2
    ;;
esac

exec "$real" -specs="$prefix/share/rhel8-gcc-toolset12/link.specs" -L"$prefix/lib/rhel8-gcc-toolset12" "$@"
EOF
chmod 0755 "$wrapper_dir/compiler-wrapper"

for name in gcc g++ cpp; do
  ln -s "compiler-wrapper" "$wrapper_dir/$name"
done
ln -s "gcc" "$wrapper_dir/cc"
ln -s "g++" "$wrapper_dir/c++"

cat >"$wrapper_dir/binutils-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

self_dir="$(cd "$(dirname "$0")" && pwd)"
prefix="$(cd "$self_dir/../../.." && pwd)"
name="$(basename "$0")"

exec "$prefix/bin/x86_64-conda-linux-gnu-$name" "$@"
EOF
chmod 0755 "$wrapper_dir/binutils-wrapper"

for name in ar as ld nm objcopy objdump ranlib readelf strings strip addr2line c++filt elfedit size gprof; do
  ln -s "binutils-wrapper" "$wrapper_dir/$name"
done

activate_dir="$PREFIX/etc/conda/activate.d"
deactivate_dir="$PREFIX/etc/conda/deactivate.d"
install -d "$activate_dir" "$deactivate_dir"

cat >"$activate_dir/zz-rhel8-gcc-toolset12.sh" <<'EOF'
_RHEL8_GCC_TOOLSET12_BIN="$CONDA_PREFIX/libexec/rhel8-gcc-toolset12/bin"
export PATH="$_RHEL8_GCC_TOOLSET12_BIN:$PATH"

export CC="$_RHEL8_GCC_TOOLSET12_BIN/cc"
export CXX="$_RHEL8_GCC_TOOLSET12_BIN/c++"
export CPP="$_RHEL8_GCC_TOOLSET12_BIN/cpp"
export GCC="$_RHEL8_GCC_TOOLSET12_BIN/gcc"
export GXX="$_RHEL8_GCC_TOOLSET12_BIN/g++"
export AR="$_RHEL8_GCC_TOOLSET12_BIN/ar"
export AS="$_RHEL8_GCC_TOOLSET12_BIN/as"
export LD="$_RHEL8_GCC_TOOLSET12_BIN/ld"
export NM="$_RHEL8_GCC_TOOLSET12_BIN/nm"
export OBJCOPY="$_RHEL8_GCC_TOOLSET12_BIN/objcopy"
export OBJDUMP="$_RHEL8_GCC_TOOLSET12_BIN/objdump"
export RANLIB="$_RHEL8_GCC_TOOLSET12_BIN/ranlib"
export READELF="$_RHEL8_GCC_TOOLSET12_BIN/readelf"
export STRINGS="$_RHEL8_GCC_TOOLSET12_BIN/strings"
export STRIP="$_RHEL8_GCC_TOOLSET12_BIN/strip"
export ADDR2LINE="$_RHEL8_GCC_TOOLSET12_BIN/addr2line"
export CXXFILT="$_RHEL8_GCC_TOOLSET12_BIN/c++filt"
export ELFEDIT="$_RHEL8_GCC_TOOLSET12_BIN/elfedit"
export SIZE="$_RHEL8_GCC_TOOLSET12_BIN/size"
export GPROF="$_RHEL8_GCC_TOOLSET12_BIN/gprof"

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

# CC/CXX/binutils variables and LDFLAGS are intentionally left to the
# conda-forge compiler deactivate scripts, which restore their CONDA_BACKUP_*
# values from before this environment was activated.
EOF
