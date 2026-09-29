#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export TZ=UTC
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/manifests/toolchain.json"

PREFIX="${PREFIX:-${1:-}}"
if [[ -z "$PREFIX" ]]; then
  PREFIX="$("$REPO_ROOT/scripts/resolve-toolchain-prefix.sh")"
fi

command -v docker >/dev/null 2>&1 || {
  echo "docker is required for the AlmaLinux 8 runtime verification." >&2
  exit 1
}

TARGET="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["target"])' "$MANIFEST"
)"
IMAGE="$(
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime_test"]["almalinux8_image"])' "$MANIFEST"
)"

WRAPPER_BIN="$PREFIX/libexec/rhel8-gcc-toolset12/bin"
CC="$WRAPPER_BIN/$TARGET-cc"
CXX="$WRAPPER_BIN/$TARGET-c++"

[[ -x "$CC" && -x "$CXX" ]] || {
  echo "Compatibility compiler wrappers are missing under: $WRAPPER_BIN" >&2
  exit 1
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/probe.c" <<'EOF'
#include <dlfcn.h>
#include <stdio.h>

int main(void) {
    void *handle = dlopen("libm.so.6", RTLD_NOW);
    if (handle == NULL) {
        return 2;
    }
    dlclose(handle);
    puts("c-runtime-ok");
    return 0;
}
EOF

cat >"$WORK_DIR/probe.cpp" <<'EOF'
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <mutex>
#include <span>
#include <thread>
#include <vector>

int main() {
    std::vector<int> values{1, 2, 3};
    std::span<int> view(values);
    std::atomic_ref<int> atom(values[0]);

    std::mutex mutex;
    std::condition_variable condition;
    bool ready = false;
    std::thread worker([&] {
        {
            std::lock_guard<std::mutex> lock(mutex);
            ready = true;
        }
        condition.notify_one();
    });

    {
        std::unique_lock<std::mutex> lock(mutex);
        if (!condition.wait_for(lock, std::chrono::seconds(2), [&] { return ready; })) {
            return 3;
        }
    }
    worker.join();

    if (!std::filesystem::exists("/etc/os-release")) {
        return 4;
    }
    return view.front() == atom.load() ? 0 : 5;
}
EOF

"$CC" ${CFLAGS:-} "$WORK_DIR/probe.c" ${LDFLAGS:-} -ldl -o "$WORK_DIR/c-probe"
"$CXX" ${CXXFLAGS:-} "$WORK_DIR/probe.cpp" ${LDFLAGS:-} \
  -std=c++20 -pthread -ldl -o "$WORK_DIR/cxx-probe"

docker run --rm --platform linux/amd64 \
  -v "$WORK_DIR:/probe:ro" \
  "$IMAGE" /probe/c-probe

docker run --rm --platform linux/amd64 \
  -v "$WORK_DIR:/probe:ro" \
  "$IMAGE" /probe/cxx-probe

echo "AlmaLinux 8 runtime verification passed."
