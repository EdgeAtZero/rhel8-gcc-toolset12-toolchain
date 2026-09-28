# Third-party components

This repository builds a toolchain from third-party packages. The repository's
MIT license does not replace the licenses of those packages.

## conda-forge

The base compiler environment is resolved from `conda-forge`, including:

- GCC / G++ 12.2.0;
- GNU binutils;
- glibc 2.28 sysroot and Linux headers;
- GCC 12 libstdc++ / libgcc development files.

Package metadata and licenses are provided by their respective conda-forge
packages and upstream projects.

## AlmaLinux 8

The RHEL 8-compatible runtime overlay uses pinned AlmaLinux 8 RPMs:

- `libstdc++-8.5.0-28.el8_10.alma.1.x86_64.rpm`;
- `libgcc-8.5.0-28.el8_10.alma.1.x86_64.rpm`;
- `gcc-toolset-12-libstdc++-devel-12.2.1-7.8.el8_10.x86_64.rpm`.

These contain GNU runtime/compiler components licensed by their upstream
projects, including the GCC Runtime Library Exception where applicable.

If publishing generated binary toolchain archives, review the redistribution
and corresponding-source obligations of every included package. The build
scripts can always be distributed independently and reproduce the toolchain
from the original package repositories.
