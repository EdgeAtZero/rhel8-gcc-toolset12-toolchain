#!/usr/bin/env bash
set -eo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

PREFIX="${PREFIX:-${1:-}}"
[[ -n "$PREFIX" ]] || { echo "Usage: PREFIX=/path/to/env $0" >&2; exit 2; }
command -v micromamba >/dev/null 2>&1 || { echo "micromamba is required." >&2; exit 1; }

export CC=/usr/bin/cc
export CXX=/usr/bin/c++
export AR=/usr/bin/ar
export LDFLAGS="-Wl,--as-needed"
original_cc="$CC"
original_cxx="$CXX"
original_ar="$AR"
original_ldflags="$LDFLAGS"

eval "$(micromamba shell hook --shell bash)"
micromamba activate "$PREFIX"
wrapper="$PREFIX/libexec/rhel8-gcc-toolset12/bin"
target="x86_64-conda-linux-gnu"
[[ "$(command -v gcc)" == "$wrapper/gcc" ]]
[[ "$(command -v g++)" == "$wrapper/g++" ]]
[[ "$(command -v "$target-gcc")" == "$wrapper/$target-gcc" ]]
[[ "$(command -v "$target-g++")" == "$wrapper/$target-g++" ]]
[[ "$CC" == "$wrapper/$target-cc" ]]
[[ "$CXX" == "$wrapper/$target-c++" ]]
[[ "$AR" == "$target-ar" ]]
[[ "$(command -v "$AR")" == "$PREFIX/bin/$target-ar" ]]
[[ "$(readlink "$wrapper/gcc")" == "$target-gcc" ]]
[[ "$(readlink "$wrapper/g++")" == "$target-g++" ]]
case " ${LDFLAGS:-} " in *" -Wl,-rpath,$PREFIX/lib "*) echo "prefix RPATH remained in LDFLAGS" >&2; exit 1 ;; esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat >"$work/probe.cpp" <<'EOF'
#include <version>
#include <span>
#include <vector>
#include <atomic>
int main() {
  std::vector<int> values{1, 2, 3};
  std::span<int> span(values);
  std::atomic_ref<int> atomic(values[0]);
  return span.front() + atomic.load();
}
EOF

"$CXX" ${CXXFLAGS:-} "$work/probe.cpp" ${LDFLAGS:-} -std=c++20 -o "$work/probe"
if "$READELF" -dW "$work/probe" | grep -Eq "\((RPATH|RUNPATH)\)"; then
  echo "Activated build contains RPATH/RUNPATH." >&2
  exit 1
fi

micromamba deactivate
[[ "$CC" == "$original_cc" ]]
[[ "$CXX" == "$original_cxx" ]]
[[ "$AR" == "$original_ar" ]]
[[ "$LDFLAGS" == "$original_ldflags" ]]
[[ "$(command -v gcc)" != "$wrapper/gcc" ]]

echo "Conda activation/deactivation verification passed."
