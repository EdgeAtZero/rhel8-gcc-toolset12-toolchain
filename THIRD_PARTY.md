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
including the GCC Runtime Library Exception where applicable. The custom conda
compatibility package also installs the relevant `COPYING*` texts and a
`THIRD-PARTY-NOTICES.txt` file that maps each redistributed payload to its
source RPM.

The exact Corresponding Source is pinned in `manifests/toolchain.json`:

- `libstdc++.so.6.0.25` and `libgcc_s.so.1` map to
  `gcc-8.5.0-28.el8_10.alma.1.src.rpm`, SHA-256
  `c94dbbd2cd6d5d01a5a6822ea18f8ce34942c25a80e17b4682d547d5e652dbd0`;
- `libstdc++_nonshared.a` maps to
  `gcc-toolset-12-gcc-12.2.1-7.8.el8_10.src.rpm`, SHA-256
  `0998437c0b6f38e0fa2cf545ae6701f175c32d220018567f06307fe442c6b3a0`.

For the conda-channel distribution model, `scripts/prepare-conda-sources.sh`
mirrors those exact SRPM bytes into the channel's `sources/` directory and
generates `SOURCE-METADATA.json` plus `SHA256SUMS`.
`scripts/verify-conda-sources.sh` checks their size/hash, verifies every binary
RPM has a declared source mapping, and confirms each SRPM contains `gcc.spec`
and a GCC source tarball.

## Conda channel redistribution

The `main` channel workflow publishes the complete validated channel snapshot,
including the generated `sources/` directory next to the custom binary packages,
so the pinned Corresponding Source is distributed with the redistributed GCC
runtime objects. The validated snapshot is deployed directly through GitHub Pages
without storing a generated channel snapshot in a Git branch.

A monolithic binary toolchain archive remains a separate redistribution surface
and requires its own complete license/source review before public publication.

An SPDX SBOM is useful inventory/provenance data, but it is not a substitute
for those redistribution obligations.
