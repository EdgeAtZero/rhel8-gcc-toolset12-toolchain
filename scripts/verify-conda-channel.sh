#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

PREFIX="${PREFIX:-${1:-}}"
[[ -n "$PREFIX" ]] || {
  echo "Usage: PREFIX=/path/to/env $0" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/manifests/toolchain.json"

mapfile -d '' -t values < <(
  python3 - "$MANIFEST" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for value in (
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

TARGET="${values[0]}"
GCC_VERSION="${values[1]}"
GLIBC_MAX="${values[2]}"
GLIBCXX_MAX="${values[3]}"
CXXABI_MAX="${values[4]}"
GCC_ABI_MAX="${values[5]}"
EXPECTED_INTERPRETER="${values[6]}"
LIBSTDCXX_RUNTIME_NAME="${values[7]}"

WRAPPER_BIN="$PREFIX/libexec/rhel8-gcc-toolset12/bin"
COMPAT="$PREFIX/lib/rhel8-gcc-toolset12"
CXX="$WRAPPER_BIN/$TARGET-c++"
CC="$WRAPPER_BIN/$TARGET-cc"
READELF="$PREFIX/bin/$TARGET-readelf"
SPEC="$PREFIX/share/rhel8-gcc-toolset12/link.specs"

for path in "$CXX" "$CC" "$READELF" "$SPEC"   "$COMPAT/libstdc++.so" "$COMPAT/libstdc++.so.6" "$COMPAT/$LIBSTDCXX_RUNTIME_NAME"   "$COMPAT/libgcc_s.so" "$COMPAT/libgcc_s.so.1" "$COMPAT/libstdc++_nonshared.a"; do
  [[ -e "$path" ]] || {
    echo "Required channel toolchain path missing: $path" >&2
    exit 1
  }
done

if find "$PREFIX/bin" -maxdepth 1 -name 'x86_64-conda_cos6-linux-gnu-*' -print -quit | grep -q .; then
  echo "Modern conda-forge compiler stack unexpectedly contains cos6 compatibility aliases." >&2
  exit 1
fi

[[ "$(readlink "$WRAPPER_BIN/gcc")" == "$TARGET-gcc" ]] || {
  echo "Short gcc wrapper does not follow the conda-forge target-prefixed layout." >&2
  exit 1
}
[[ "$(readlink "$WRAPPER_BIN/g++")" == "$TARGET-g++" ]] || {
  echo "Short g++ wrapper does not follow the conda-forge target-prefixed layout." >&2
  exit 1
}

[[ "$("$CXX" -dumpmachine)" == "$TARGET" ]] || {
  echo "Unexpected compiler target." >&2
  exit 1
}
[[ "$("$CXX" -dumpfullversion)" == "$GCC_VERSION" ]] || {
  echo "Unexpected GCC version." >&2
  exit 1
}

actual_sysroot="$(readlink -f "$("$CXX" -print-sysroot)")"
expected_sysroot="$(readlink -f "$PREFIX/$TARGET/sysroot")"
[[ "$actual_sysroot" == "$expected_sysroot" ]] || {
  echo "Compiler sysroot mismatch: $actual_sysroot != $expected_sysroot" >&2
  exit 1
}

if grep -F -- "-rpath $PREFIX/lib" "$SPEC" >/dev/null; then
  echo "Compatibility specs still inject the conda prefix RPATH." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

"$CXX" -std=c++20 -E -x c++ - </dev/null >/dev/null 2>"$WORK_DIR/include-trace.txt" -v
while IFS= read -r include_dir; do
  include_dir="${include_dir# }"
  [[ -n "$include_dir" ]] || continue
  resolved="$(readlink -f "$include_dir")"
  case "$resolved" in
    "$PREFIX"|"$PREFIX"/*) ;;
    *)
      echo "Include path escaped channel environment: $resolved" >&2
      exit 1
      ;;
  esac
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
"$CXX" -std=c++20 "$WORK_DIR/probe.cpp" -Wl,-t -o "$WORK_DIR/probe-trace"   >"$WORK_DIR/link-trace.txt" 2>&1

for expected in   "$COMPAT/libstdc++.so"   "$COMPAT/libstdc++.so.6"   "$COMPAT/libstdc++_nonshared.a"   "$COMPAT/libgcc_s.so"   "$COMPAT/libgcc_s.so.1"; do
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
  version_le "$actual" "$maximum" || {
    echo "$label compatibility regression: $actual > $maximum" >&2
    exit 1
  }
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
  echo "Unexpected RPATH/RUNPATH in channel verification probe:" >&2
  "$READELF" -dW "$WORK_DIR/probe" | grep -E '\((RPATH|RUNPATH)\)' >&2
  exit 1
fi

interpreter="$(
  "$READELF" -lW "$WORK_DIR/probe" |
    sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p'
)"
[[ "$interpreter" == "$EXPECTED_INTERPRETER" ]] || {
  echo "Unexpected ELF interpreter: $interpreter" >&2
  exit 1
}

mapfile -t needed < <(
  "$READELF" -dW "$WORK_DIR/probe" |
    sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' |
    sort
)
expected_needed=(libc.so.6 libgcc_s.so.1 libm.so.6 libstdc++.so.6)
mapfile -t expected_needed_sorted < <(printf '%s\n' "${expected_needed[@]}" | sort)
[[ "$(printf '%s\n' "${needed[@]}")" == "$(printf '%s\n' "${expected_needed_sorted[@]}")" ]] || {
  echo "Unexpected DT_NEEDED set: ${needed[*]}" >&2
  exit 1
}

[[ "$(readlink "$COMPAT/libstdc++.so.6")" == "$LIBSTDCXX_RUNTIME_NAME" ]] || {
  echo "Unexpected compatibility libstdc++.so.6 target." >&2
  exit 1
}

runtime_glibcxx="$(version_max "$COMPAT/libstdc++.so.6" GLIBCXX || true)"
runtime_cxxabi="$(version_max "$COMPAT/libstdc++.so.6" CXXABI || true)"
runtime_glibc="$(version_max "$COMPAT/libstdc++.so.6" GLIBC || true)"
libgcc_abi="$(version_max "$COMPAT/libgcc_s.so.1" GCC || true)"
libgcc_glibc="$(version_max "$COMPAT/libgcc_s.so.1" GLIBC || true)"

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

python3 - "$PREFIX" <<'PY'
import json
import pathlib
import sys

prefix = pathlib.Path(sys.argv[1])
records = []
for meta_path in sorted((prefix / "conda-meta").glob("*.json")):
    with meta_path.open(encoding="utf-8") as f:
        meta = json.load(f)
    records.append((meta.get("name", meta_path.stem), set(meta.get("files", []))))

custom = {
    "rhel8-gcc-toolset12-compat",
    "rhel8-gcc-toolset12-activate",
    "rhel8-gcc-toolset12-toolchain",
}

owners = {}
for name, files in records:
    for path in files:
        owners.setdefault(path, []).append(name)

conflicts = []
for path, names in owners.items():
    if len(names) > 1 and custom.intersection(names):
        conflicts.append((path, names))

if conflicts:
    for path, names in conflicts:
        print(f"custom package ownership conflict: {path}: {', '.join(names)}", file=sys.stderr)
    raise SystemExit(1)

by_name = dict(records)
expected_prefixes = {
    "rhel8-gcc-toolset12-compat": (
        "lib/rhel8-gcc-toolset12/",
        "share/licenses/rhel8-gcc-toolset12-compat/",
        "share/doc/rhel8-gcc-toolset12-compat/",
    ),
    "rhel8-gcc-toolset12-activate": (
        "libexec/rhel8-gcc-toolset12/",
        "share/rhel8-gcc-toolset12/link.specs",
        "etc/conda/activate.d/",
        "etc/conda/deactivate.d/",
    ),
}

for package, prefixes in expected_prefixes.items():
    files = by_name.get(package)
    if files is None:
        raise SystemExit(f"missing installed package record: {package}")
    bad = [
        path for path in files
        if not any(path == allowed or path.startswith(allowed) for allowed in prefixes)
    ]
    if bad:
        raise SystemExit(f"{package} owns unexpected paths: {bad}")
PY

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
echo "Local conda channel ABI and ownership verification passed."
