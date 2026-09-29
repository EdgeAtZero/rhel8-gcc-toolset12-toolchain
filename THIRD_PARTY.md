# Third-party components

This repository builds a toolchain from third-party packages. The repository's
MIT license covers the repository scripts and documentation only; it does not
replace the licenses of the packages used to assemble the toolchain.

## Distribution policy

The project does **not** publish the assembled toolchain archive as an official
GitHub Release asset.

The GitHub Action assembles the toolchain on the consumer's Linux runner from
the exact upstream package URLs and SHA-256 digests committed in this
repository. In particular:

- conda-forge compiler, sysroot, binutils, and runtime packages are downloaded
  from conda-forge;
- the compatibility runtime overlay is downloaded from AlmaLinux;
- the repository supplies only its own build/verification logic and manifests.

This avoids re-publishing the complete GCC/binutils/glibc/sysroot binary set
from this repository and therefore avoids presenting the repository's MIT
license as a license for those third-party binaries.

`scripts/package-toolchain.sh` remains available for local/internal packaging
and reproducibility work. A tarball produced by that script is **not** an
officially redistributable project Release asset by itself.

Before publishing such a binary archive to third parties, the distributor must
review the exact package set and satisfy the corresponding licenses, including
all required copyright/license notices and, where GPL/LGPL terms require it,
equivalent access to the complete corresponding source for the exact binaries.

## conda-forge

The base compiler environment is frozen in
`manifests/conda-linux-64.lock`. It includes GCC/G++, binutils, the glibc 2.28
sysroot/Linux headers, and GCC runtime/development packages.

The explicit lock records exact package URLs, build strings, and SHA-256
digests. The original conda packages retain their own metadata, recipes, source
provenance, notices, and upstream licenses.

## AlmaLinux 8

The RHEL 8-compatible runtime overlay uses SHA-256-pinned AlmaLinux 8.10 RPMs:

- `libstdc++-8.5.0-28.el8_10.alma.1.x86_64.rpm`;
- `libgcc-8.5.0-28.el8_10.alma.1.x86_64.rpm`;
- `gcc-toolset-12-libstdc++-devel-12.2.1-7.8.el8_10.x86_64.rpm`.

These contain GNU runtime/compiler components under their upstream licenses,
including the GCC Runtime Library Exception where applicable.

## Future binary redistribution

If this project later publishes a binary toolchain or a custom conda package
that contains third-party GPL/LGPL object code, the release process should
explicitly ship or provide equivalent access to the complete corresponding
source for those exact objects, together with the applicable license and
copyright notices.

An SPDX SBOM is useful inventory/provenance data, but it is not a substitute
for those redistribution obligations.
