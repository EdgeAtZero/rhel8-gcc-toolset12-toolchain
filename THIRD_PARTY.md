# Third-party components

This repository builds a toolchain from third-party packages. The repository's
MIT license does not replace the licenses of those packages.

## conda-forge

The base compiler environment is frozen in
`manifests/conda-linux-64.lock`. It includes GCC/G++, binutils, the glibc 2.28
sysroot/Linux headers, and GCC runtime/development packages.

The explicit lock records exact package URLs, build strings, and SHA-256
digests. Package metadata and licenses remain those of the respective
conda-forge packages and upstream projects.

## AlmaLinux 8

The RHEL 8-compatible runtime overlay uses SHA-256-pinned AlmaLinux 8.10 RPMs:

- `libstdc++-8.5.0-28.el8_10.alma.1.x86_64.rpm`;
- `libgcc-8.5.0-28.el8_10.alma.1.x86_64.rpm`;
- `gcc-toolset-12-libstdc++-devel-12.2.1-7.8.el8_10.x86_64.rpm`.

These contain GNU runtime/compiler components under their upstream licenses,
including the GCC Runtime Library Exception where applicable.

## Binary redistribution

Release archives contain the installed files from these third-party packages.
The generated SPDX SBOM is intended to make that inventory auditable, but it
does not grant additional rights and does not replace license notices,
corresponding-source obligations, written offers, or other redistribution
requirements.

Before publishing binary releases, maintainers should review the actual license
metadata and redistribution obligations for every locked package and RPM.
Repository scripts and documentation can be distributed independently under
MIT and can reproduce the toolchain from the original package repositories.
