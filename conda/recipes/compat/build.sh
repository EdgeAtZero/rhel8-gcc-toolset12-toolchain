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
notice_dir="$PREFIX/share/doc/rhel8-gcc-toolset12-compat"
install -d "$notice_dir"
cat >"$notice_dir/THIRD-PARTY-NOTICES.txt" <<'EOF'
This package redistributes selected GCC runtime objects from AlmaLinux RPMs.

Binary input:
  libstdc++-8.5.0-28.el8_10.alma.1.x86_64.rpm
Payload:
  libstdc++.so.6.0.25
Corresponding source:
  gcc-8.5.0-28.el8_10.alma.1.src.rpm

Binary input:
  libgcc-8.5.0-28.el8_10.alma.1.x86_64.rpm
Payload:
  libgcc_s.so.1
Corresponding source:
  gcc-8.5.0-28.el8_10.alma.1.src.rpm

Binary input:
  gcc-toolset-12-libstdc++-devel-12.2.1-7.8.el8_10.x86_64.rpm
Payload:
  libstdc++_nonshared.a
Corresponding source:
  gcc-toolset-12-gcc-12.2.1-7.8.el8_10.src.rpm

A published project channel must make those exact source RPMs available under
its accompanying sources/ directory. The original AlmaLinux vault URLs and
SHA-256 digests are recorded in SOURCE-METADATA.json in that directory.
EOF
