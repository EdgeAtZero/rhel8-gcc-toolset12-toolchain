#!/usr/bin/env bash
set -euo pipefail

for tool in /usr/bin/rpm2cpio /usr/bin/cpio; do
  [[ -x "$tool" ]] || {
    echo "Required host tool not found: $tool" >&2
    exit 1
  }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

extract_rpm() {
  local rpm="$1"
  local out="$2"
  mkdir -p "$out"
  (
    cd "$out"
    /usr/bin/rpm2cpio "$rpm" | /usr/bin/cpio -idm --quiet
  )
}

extract_rpm "$SRC_DIR/libstdcxx.rpm" "$work/libstdcxx"
extract_rpm "$SRC_DIR/libgcc.rpm" "$work/libgcc"
extract_rpm "$SRC_DIR/libstdcxx-nonshared.rpm" "$work/nonshared"

compat="$PREFIX/lib/rhel8-gcc-toolset12"
install -d "$compat"

install -m 0755 "$work/libstdcxx/usr/lib64/libstdc++.so.6.0.25" "$compat/libstdc++.so.6.0.25"
ln -s "libstdc++.so.6.0.25" "$compat/libstdc++.so.6"
install -m 0755 "$work/libgcc/lib64/libgcc_s.so.1" "$compat/libgcc_s.so.1"
install -m 0644 "$work/nonshared/opt/rh/gcc-toolset-12/root/usr/lib/gcc/x86_64-redhat-linux/12/libstdc++_nonshared.a" "$compat/libstdc++_nonshared.a"

cat >"$compat/libstdc++.so" <<'EOF'
/* RHEL 8 / GCC Toolset 12 compatibility linker script. */
INPUT ( libstdc++.so.6 -lstdc++_nonshared )
EOF

cat >"$compat/libgcc_s.so" <<'EOF'
/* RHEL 8 compatibility linker script. */
GROUP ( libgcc_s.so.1 -lgcc )
EOF

license_dir="$PREFIX/share/licenses/rhel8-gcc-toolset12-compat"
install -d "$license_dir"
for license in "$work/libgcc/usr/share/licenses/libgcc/"COPYING*; do
  [[ -f "$license" ]] || continue
  install -m 0644 "$license" "$license_dir/$(basename "$license")"
done
