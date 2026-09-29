#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

TOOLCHAIN_NAME="linux-x86_64-rhel8-gcc-toolset12"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$("$SCRIPT_DIR/resolve-toolchain-prefix.sh")}"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PREFIX/TOOLCHAIN-MANIFEST.json" ]]; then
  MANIFEST="$PREFIX/TOOLCHAIN-MANIFEST.json"
else
  MANIFEST="$REPO_ROOT/manifests/toolchain.json"
fi

for cmd in python3 grep sed sort tail readlink find cmp; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Required command not found: $cmd" >&2
    exit 1
  }
done

mapfile -d '' -t values < <(
  python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

for value in (
    data["name"],
    data["target"],
    data["compiler"]["gcc_version"],
    data["abi"]["glibc_max"],
    data["abi"]["glibcxx_max"],
    data["abi"]["cxxabi_max"],
    data["abi"]["gcc_max"],
    data["abi"]["interpreter"],
    data["abi"]["libstdcxx_runtime"],
):
    print(value, end="\0")
PY
)

(("${#values[@]}" == 9)) || {
  echo "Invalid toolchain manifest." >&2
  exit 1
}

EXPECTED_NAME="${values[0]}"
TARGET="${values[1]}"
GCC_VERSION="${values[2]}"
GLIBC_MAX="${values[3]}"
GLIBCXX_MAX="${values[4]}"
CXXABI_MAX="${values[5]}"
GCC_ABI_MAX="${values[6]}"
EXPECTED_INTERPRETER="${values[7]}"
LIBSTDCXX_RUNTIME_NAME="${values[8]}"

[[ "$EXPECTED_NAME" == "$TOOLCHAIN_NAME" ]] || {
  echo "Unexpected toolchain identity in manifest: $EXPECTED_NAME" >&2
  exit 1
}

CXX="$PREFIX/bin/c++"
CC="$PREFIX/bin/cc"
READELF="$PREFIX/bin/readelf"
STRINGS="$PREFIX/bin/strings"
COMPAT="$PREFIX/lib/rhel8-gcc-toolset12"
SPEC="$PREFIX/share/rhel8-gcc-toolset12/link.specs"

for tool in "$CXX" "$CC" "$READELF" "$STRINGS"; do
  [[ -x "$tool" ]] || {
    echo "Required tool not found: $tool" >&2
    exit 1
  }
done

for path in "$SPEC" "$COMPAT/libstdc++.so" "$COMPAT/libstdc++.so.6" "$COMPAT/$LIBSTDCXX_RUNTIME_NAME" "$COMPAT/libgcc_s.so" "$COMPAT/libgcc_s.so.1" "$COMPAT/libstdc++_nonshared.a"; do
  [[ -e "$path" ]] || {
    echo "Required compatibility path missing: $path" >&2
    exit 1
  }
done

actual_target="$("$CXX" -dumpmachine)"
actual_gcc="$("$CXX" -dumpfullversion)"
actual_sysroot="$(readlink -f "$("$CXX" -print-sysroot)")"
expected_sysroot="$(readlink -f "$PREFIX/$TARGET/sysroot")"

[[ "$actual_target" == "$TARGET" ]] || {
  echo "Compiler target mismatch: $actual_target != $TARGET" >&2
  exit 1
}
[[ "$actual_gcc" == "$GCC_VERSION" ]] || {
  echo "Compiler version mismatch: $actual_gcc != $GCC_VERSION" >&2
  exit 1
}
[[ "$actual_sysroot" == "$expected_sysroot" ]] || {
  echo "Compiler sysroot mismatch: $actual_sysroot != $expected_sysroot" >&2
  exit 1
}

assert_prefix_path() {
  local label="$1"
  local path="$2"
  local resolved

  [[ "$path" == /* ]] || {
    echo "$label did not resolve to an absolute path: $path" >&2
    exit 1
  }

  resolved="$(readlink -f "$path")"
  case "$resolved" in
    "$PREFIX"|"$PREFIX"/*) ;;
    *)
      echo "$label escaped the toolchain prefix: $resolved" >&2
      exit 1
      ;;
  esac
}

assert_prefix_path "libstdc++ linker input" "$("$CXX" -print-file-name=libstdc++.so)"
assert_prefix_path "libgcc_s linker input" "$("$CXX" -print-file-name=libgcc_s.so)"
assert_prefix_path "linker program" "$("$CXX" -print-prog-name=ld)"

if "$CXX" -dumpspecs | grep -F -- "-rpath $PREFIX/lib" >/dev/null; then
  echo "Conda prefix RPATH is still present in effective GCC specs." >&2
  exit 1
fi

# Capture the compiler include search path and ensure it stays inside the prefix.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
"$CXX" -std=c++20 -E -x c++ - </dev/null >/dev/null 2>"$WORK_DIR/include-trace.txt" -v

while IFS= read -r include_dir; do
  include_dir="${include_dir# }"
  [[ -n "$include_dir" ]] || continue
  assert_prefix_path "include search path" "$include_dir"
done < <(
  sed -n '/#include <...> search starts here:/,/End of search list./p' "$WORK_DIR/include-trace.txt" |
    sed '1d;$d'
)

cat >"$WORK_DIR/probe.cpp" <<'EOF'
#include <version>
#include <span>
#include <ranges>
#include <vector>
#include <condition_variable>
#include <mutex>
#include <chrono>
#include <string>
#include <atomic>

int main() {
    std::vector<int> values{1, 2, 3};
    std::span<int> span(values);
    auto range = values | std::views::all;

    std::condition_variable cv;
    std::mutex mutex;
    std::unique_lock<std::mutex> lock(mutex);
    cv.wait_for(lock, std::chrono::milliseconds(1));

    int raw = 7;
    std::atomic_ref<int> atomic(raw);
    atomic.fetch_add(1);

    std::erase_if(values, [](int value) { return value == 99; });
    std::string text = "toolchain";
    return span.front() + *range.begin() + atomic.load() + static_cast<int>(text.size());
}
EOF

"$CXX" -std=c++20 "$WORK_DIR/probe.cpp" -o "$WORK_DIR/probe"
"$CXX" -std=c++20 "$WORK_DIR/probe.cpp" -Wl,-t -o "$WORK_DIR/probe-trace" >"$WORK_DIR/link-trace.txt" 2>&1

for expected in "$COMPAT/libstdc++.so" "$COMPAT/libstdc++.so.6" "$COMPAT/libstdc++_nonshared.a" "$COMPAT/libgcc_s.so" "$COMPAT/libgcc_s.so.1"; do
  grep -F "$expected" "$WORK_DIR/link-trace.txt" >/dev/null || {
    echo "Linker did not select compatibility input: $expected" >&2
    cat "$WORK_DIR/link-trace.txt" >&2
    exit 1
  }
done

version_max() {
  local file="$1"
  local prefix="$2"
  "$READELF" --version-info -W "$file" |
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

require_version_at_most() {
  local label="$1"
  local actual="$2"
  local maximum="$3"

  [[ -n "$actual" ]] || {
    echo "$label version requirement was not found." >&2
    exit 1
  }

  if ! version_le "$actual" "$maximum"; then
    echo "$label compatibility regression: $actual > $maximum" >&2
    exit 1
  fi
}

glibc="$(version_max "$WORK_DIR/probe" GLIBC || true)"
glibcxx="$(version_max "$WORK_DIR/probe" GLIBCXX || true)"
gccabi="$(version_max "$WORK_DIR/probe" GCC || true)"
cxxabi="$(version_max "$WORK_DIR/probe" CXXABI || true)"

require_version_at_most "GLIBC" "$glibc" "$GLIBC_MAX"
require_version_at_most "GLIBCXX" "$glibcxx" "$GLIBCXX_MAX"
require_version_at_most "GCC ABI" "$gccabi" "$GCC_ABI_MAX"
require_version_at_most "CXXABI" "$cxxabi" "$CXXABI_MAX"

if "$READELF" -dW "$WORK_DIR/probe" | grep -Eq '\((RPATH|RUNPATH)\)'; then
  echo "Unexpected RPATH/RUNPATH in verification probe:" >&2
  "$READELF" -dW "$WORK_DIR/probe" | grep -E '\((RPATH|RUNPATH)\)' >&2
  exit 1
fi

interpreter="$(
  "$READELF" -lW "$WORK_DIR/probe" |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
)"
[[ "$interpreter" == "$EXPECTED_INTERPRETER" ]] || {
  echo "Unexpected ELF interpreter: $interpreter" >&2
  echo "Expected: $EXPECTED_INTERPRETER" >&2
  exit 1
}

mapfile -t needed < <(
  "$READELF" -dW "$WORK_DIR/probe" |
    sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' |
    sort
)
expected_needed=(libc.so.6 libgcc_s.so.1 libm.so.6 libstdc++.so.6)
mapfile -t expected_needed_sorted < <(printf '%s\n' "${expected_needed[@]}" | sort)

if [[ "$(printf '%s\n' "${needed[@]}")" != "$(printf '%s\n' "${expected_needed_sorted[@]}")" ]]; then
  echo "Unexpected DT_NEEDED set:" >&2
  printf '  %s\n' "${needed[@]}" >&2
  echo "Expected:" >&2
  printf '  %s\n' "${expected_needed_sorted[@]}" >&2
  exit 1
fi

runtime="$COMPAT/libstdc++.so.6"
libgcc_runtime="$COMPAT/libgcc_s.so.1"

[[ "$(readlink "$runtime")" == "$LIBSTDCXX_RUNTIME_NAME" ]] || {
  echo "Unexpected libstdc++.so.6 target: $(readlink "$runtime")" >&2
  exit 1
}

runtime_glibcxx="$(version_max "$runtime" GLIBCXX || true)"
runtime_cxxabi="$(version_max "$runtime" CXXABI || true)"
runtime_glibc="$(version_max "$runtime" GLIBC || true)"
libgcc_abi="$(version_max "$libgcc_runtime" GCC || true)"
libgcc_glibc="$(version_max "$libgcc_runtime" GLIBC || true)"

[[ "$runtime_glibcxx" == "$GLIBCXX_MAX" ]] || {
  echo "Unexpected compatibility libstdc++ GLIBCXX ceiling: $runtime_glibcxx" >&2
  exit 1
}
[[ "$runtime_cxxabi" == "$CXXABI_MAX" ]] || {
  echo "Unexpected compatibility libstdc++ CXXABI ceiling: $runtime_cxxabi" >&2
  exit 1
}
[[ "$libgcc_abi" == "$GCC_ABI_MAX" ]] || {
  echo "Unexpected compatibility libgcc_s GCC ABI ceiling: $libgcc_abi" >&2
  exit 1
}
require_version_at_most "compatibility libstdc++ GLIBC" "$runtime_glibc" "$GLIBC_MAX"
require_version_at_most "compatibility libgcc_s GLIBC" "$libgcc_glibc" "$GLIBC_MAX"

absolute_symlink="$(
  find "$PREFIX" -type l -printf '%p\0%l\0' |
    python3 -c 'import sys
items = sys.stdin.buffer.read().split(b"\0")
for i in range(0, len(items) - 1, 2):
    path = items[i].decode(errors="surrogateescape")
    target = items[i + 1].decode(errors="surrogateescape")
    if target.startswith("/"):
        print(f"{path} -> {target}")
        break'
)"
[[ -z "$absolute_symlink" ]] || {
  echo "Absolute symlink found in toolchain prefix: $absolute_symlink" >&2
  exit 1
}

if grep -R -E '"(extracted_package_dir|package_tarball_full_path)"[[:space:]]*:' "$PREFIX/conda-meta" >/dev/null; then
  echo "Volatile conda package-cache paths remain in conda-meta." >&2
  exit 1
fi
if grep -R -E '"source"[[:space:]]*:[[:space:]]*"/' "$PREFIX/conda-meta" >/dev/null; then
  echo "Absolute conda link source remains in conda-meta." >&2
  exit 1
fi
if grep -E '^==> .* <==$|^# cmd:' "$PREFIX/conda-meta/history" >/dev/null; then
  echo "Non-deterministic conda history remains in the prefix." >&2
  exit 1
fi

if [[ -f "$PREFIX/TOOLCHAIN-MANIFEST.json" && -f "$REPO_ROOT/manifests/toolchain.json" ]]; then
  cmp -s "$PREFIX/TOOLCHAIN-MANIFEST.json" "$REPO_ROOT/manifests/toolchain.json" || {
    echo "Installed manifest does not match repository manifest." >&2
    exit 1
  }
fi

echo "Compiler : $("$CXX" --version | head -n 1)"
echo "Prefix   : $PREFIX"
echo "Sysroot  : $actual_sysroot"
echo "Interp   : $interpreter"
echo "NEEDED   : ${needed[*]}"
echo "GLIBC    : $glibc"
echo "GLIBCXX  : $glibcxx"
echo "GCC ABI  : $gccabi"
echo "CXXABI   : $cxxabi"
echo
echo "Toolchain ABI verification passed."
