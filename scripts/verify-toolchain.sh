#!/usr/bin/env bash
set -euo pipefail

TOOLCHAIN_NAME="linux-x86_64-rhel8-gcc-toolset12"
PREFIX="${PREFIX:-/opt/toolchains/$TOOLCHAIN_NAME}"
CXX="$PREFIX/bin/c++"
READELF="$PREFIX/bin/readelf"

[[ -x "$CXX" ]] || {
  echo "C++ compiler not found: $CXX" >&2
  exit 1
}
[[ -x "$READELF" ]] || READELF="$(command -v readelf)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/probe.cpp" <<'EOF'
#include <version>
#include <span>
#include <ranges>
#include <vector>
#include <condition_variable>
#include <mutex>
#include <chrono>
#include <string>

int main() {
    std::vector<int> values{1, 2, 3};
    std::span<int> span(values);
    auto range = values | std::views::all;

    std::condition_variable cv;
    std::mutex mutex;
    std::unique_lock<std::mutex> lock(mutex);
    cv.wait_for(lock, std::chrono::milliseconds(1));

    std::string text = "toolchain";
    return span.front() + *range.begin() + static_cast<int>(text.size());
}
EOF

"$CXX" -std=c++20 "$WORK_DIR/probe.cpp" -o "$WORK_DIR/probe"

version_max() {
  local prefix="$1"
  "$READELF" --version-info -W "$WORK_DIR/probe" |
    grep -oE "Name: ${prefix}_[0-9.]+" |
    sed 's/Name: //' |
    sort -V |
    tail -n 1
}

version_le() {
  local actual="$1"
  local maximum="$2"
  local a="${actual#*_}"
  local m="${maximum#*_}"
  [[ "$(printf '%s\n%s\n' "$a" "$m" | sort -V | tail -n 1)" == "$m" ]]
}

glibc="$(version_max GLIBC || true)"
glibcxx="$(version_max GLIBCXX || true)"
gccabi="$(version_max GCC || true)"
cxxabi="$(version_max CXXABI || true)"

echo "Compiler : $("$CXX" --version | head -n 1)"
echo "Prefix   : $PREFIX"
echo "GLIBC    : ${glibc:-none}"
echo "GLIBCXX  : ${glibcxx:-none}"
echo "GCC ABI  : ${gccabi:-none}"
echo "CXXABI   : ${cxxabi:-none}"

if [[ -n "$glibc" ]] && ! version_le "$glibc" "GLIBC_2.28"; then
  echo "GLIBC compatibility regression: $glibc > GLIBC_2.28" >&2
  exit 1
fi

if [[ -n "$glibcxx" ]] && ! version_le "$glibcxx" "GLIBCXX_3.4.25"; then
  echo "GLIBCXX compatibility regression: $glibcxx > GLIBCXX_3.4.25" >&2
  exit 1
fi

if "$READELF" -dW "$WORK_DIR/probe" | grep -Eq 'RPATH|RUNPATH'; then
  echo "Unexpected RPATH/RUNPATH in verification probe:" >&2
  "$READELF" -dW "$WORK_DIR/probe" | grep -E 'RPATH|RUNPATH' >&2
  exit 1
fi

runtime="$PREFIX/x86_64-conda-linux-gnu/sysroot/usr/lib64/libstdc++.so.6"
runtime_max="$(strings "$runtime" | grep -oE 'GLIBCXX_[0-9.]+' | sort -V | tail -n 1)"
if [[ "$runtime_max" != "GLIBCXX_3.4.25" ]]; then
  echo "Unexpected target libstdc++ ABI ceiling: $runtime_max" >&2
  exit 1
fi

echo
echo "Toolchain ABI verification passed."
