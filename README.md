# RHEL 8 GCC Toolset 12 Toolchain

A reproducible-input Linux x86_64 release toolchain that combines a modern GCC 12 C++20 compiler/header set with a RHEL 8 runtime ABI baseline.

Installed identity:

```text
linux-x86_64-rhel8-gcc-toolset12
```

Default release prefix:

```text
/opt/toolchains/linux-x86_64-rhel8-gcc-toolset12
```

Target compatibility ceilings:

```text
GLIBC   <= 2.28
GLIBCXX <= 3.4.25
CXXABI  <= 1.3.11
GCC ABI <= 7.0.0
```

These are release gates, not promises about every application built with the toolchain. Final native artifacts must still be inspected because project code and linked third-party libraries can introduce stricter requirements.

## Why

Projects such as Node.js 24 / V8 need a modern C++20 compiler and modern libstdc++ headers. Building them with GCC 8 headers is not viable because APIs such as `<version>`, `std::span`, ranges, `std::atomic_ref`, and `std::erase_if` are required.

The compatibility model follows the RHEL 8 GCC Toolset approach:

```text
GCC 12 compiler + GCC 12 C++ headers
        +
RHEL 8 / GCC 8-era libstdc++.so.6 and libgcc_s.so.1
        +
GCC Toolset 12 libstdc++_nonshared.a
```

The target `libstdc++.so` is a linker script:

```text
INPUT ( libstdc++.so.6 -lstdc++_nonshared )
```

and the target `libgcc_s.so` is:

```text
GROUP ( libgcc_s.so.1 -lgcc )
```

The shared runtimes come from pinned AlmaLinux 8.10 RPMs. Newer implementation pieces required by GCC 12 headers can be supplied from `libstdc++_nonshared.a` without raising the target shared `GLIBCXX` ceiling.

## Reproducibility model

Pinned toolchain assembly does not run the conda solver.

The repository contains:

- `manifests/toolchain.json`: toolchain identity, ABI policy, RPM URLs/hashes, and the pinned micromamba bootstrap;
- `manifests/conda-linux-64.lock`: a complete `@EXPLICIT` conda-forge package set including exact build strings and SHA-256 hashes;
- SHA-256-pinned AlmaLinux 8.10 RPM inputs;
- a pinned micromamba release binary and SHA-256.

The build also normalizes volatile `conda-meta` fields that otherwise contain build timestamps, local cache paths, or the maintainer's checkout path.

Packaging normalizes archive ordering, mtime, uid, and gid through `SOURCE_DATE_EPOCH` and uses single-threaded zstd compression. This makes repeated packaging with the same prefix and packaging tool versions deterministic.

This is not claimed to be a fully hermetic build across arbitrary host distributions: host `tar`, `zstd`, `rpm2cpio`, and `cpio` are still supplied by the runner. `RELEASE-METADATA.json` records relevant packaging versions. See [REPRODUCIBILITY.md](REPRODUCIBILITY.md).

## Build

Required host tools:

```text
curl
cpio
rpm2cpio
python3
zstd
micromamba
```

Build the fixed-prefix release toolchain:

```bash
./scripts/build-toolchain.sh
```

Rebuild an existing prefix:

```bash
./scripts/build-toolchain.sh --force
```

A custom prefix is supported for local experiments:

```bash
./scripts/build-toolchain.sh --prefix /tmp/rhel8-gcc-toolset12
```

Local archives are intentionally built for the default `/opt/toolchains/...` prefix. The conda compiler packages contain prefix-aware content, so the archive is not advertised as arbitrarily relocatable.

## Verify

```bash
./scripts/verify-toolchain.sh
```

The verification gate checks:

- GCC version, target triple, and compiler sysroot;
- C++20 headers/features including `std::span`, ranges, `std::atomic_ref`, and `std::erase_if`;
- highest required `GLIBC`, `GLIBCXX`, `CXXABI`, and GCC symbol versions;
- target `libstdc++.so.6` / `libgcc_s.so.1` export ceilings;
- exact ELF interpreter;
- the expected `DT_NEEDED` set;
- absence of `RPATH` / `RUNPATH`;
- compiler include/linker inputs staying inside the toolchain prefix/sysroot;
- absence of absolute symlinks in the prefix;
- absence of volatile conda package-cache paths and transaction timestamps.

A typical probe currently requires substantially less than the policy ceilings, but that is only the probe's requirement. Consumers must inspect their final binaries separately.

## Local package

For local/internal reproducibility work:

```bash
./scripts/package-toolchain.sh
```

This creates an assembled toolchain archive, checksum, SPDX SBOM, and release
metadata under `dist/`.

The project does **not** publish that archive as an official GitHub Release
asset. It contains third-party GCC/binutils/glibc/sysroot/runtime binaries, so
public redistribution has license and corresponding-source obligations beyond
this repository's MIT license.

The packaging script remains useful for local deployment, archive
reproducibility testing, and private environments where the distributor has
separately reviewed those obligations. See [THIRD_PARTY.md](THIRD_PARTY.md).

## GitHub Action

Consumers can assemble the pinned toolchain directly on a Linux x86_64 runner:

```yaml
- name: Set up RHEL 8 GCC Toolset 12
  id: toolchain
  uses: EdgeAtZero/rhel8-gcc-toolset12-toolchain@v1.0.0
```

The Action no longer downloads a prebuilt project Release archive. It installs
the pinned micromamba bootstrap, downloads the exact conda-forge and AlmaLinux
inputs recorded by this repository, assembles the fixed-prefix toolchain under
`/opt/toolchains`, exports the compiler/binutils environment variables, and
runs the ABI verification gate by default.

Outputs:

```text
prefix
version
identity
```

`identity` is derived from the committed toolchain manifest and explicit conda
lock, so it is suitable for consumer build-cache keys:

```yaml
key: native-linux-x86_64-${{ steps.toolchain.outputs.identity }}-${{ hashFiles('your-inputs.json') }}
```

The only optional input is verification:

```yaml
- uses: EdgeAtZero/rhel8-gcc-toolset12-toolchain@v1.0.0
  with:
    verify: 'false'
```

There is intentionally no arbitrary `install-prefix` input because the compiler
packages contain prefix-aware content and the supported assembled prefix is
fixed. Consumers that want download caching can cache
`~/.cache/rhel8-gcc-toolset12-toolchain` in their own workflow.

## GitHub Actions and supply chain

The repository workflow:

1. caches only downloads from the original upstream package repositories;
2. installs a SHA-256-pinned micromamba binary;
3. assembles from the explicit conda lock and pinned AlmaLinux RPMs;
4. runs the ABI verification gate;
5. does not upload or publish the assembled third-party binary toolchain;
6. on `v*` tags, creates a source-only GitHub Release for this repository.

Third-party GitHub Actions are pinned to commit SHAs rather than mutable major
tags.

This keeps the project's official distribution focused on its MIT-licensed
scripts/manifests while the third-party binary inputs are obtained from their
original distributors.

## Updating inputs

Input updates are deliberate release engineering changes, not automatic patch bumps.

For conda-forge:

1. solve a candidate environment in a temporary prefix using the intended high-level compiler/sysroot requirements;
2. run the full ABI verification against that candidate;
3. export the exact package records:

```bash
./scripts/export-conda-lock.py /path/to/candidate manifests/conda-linux-64.lock
```

4. rebuild from the exported lock and verify again.

For AlmaLinux RPMs, update `manifests/toolchain.json` only after checking the new payload, SHA-256, exported ABI ceilings, and compatibility probe. An automatic updater may open a PR in the future, but it should never auto-merge an ABI baseline change.

## Future conda channel

A conda channel is a better long-term installation surface than republishing a
monolithic `/opt` archive, but it should be split deliberately.

The intended package model is:

```text
rhel8-gcc-toolset12-toolchain     meta package
        |
        +-- exact conda-forge GCC/binutils/sysroot dependencies
        +-- rhel8-gcc-toolset12-compat
        +-- rhel8-gcc-toolset12-activate
```

`rhel8-gcc-toolset12-compat` should own only the compatibility overlay files
that cannot be expressed as ordinary conda-forge dependencies. If that package
contains AlmaLinux/GNU GPL or LGPL binary payloads, its channel release must
also carry the required notices and exact corresponding-source access.

`rhel8-gcc-toolset12-activate` should contain project-owned wrapper/activation
logic and must not overwrite paths owned by conda-forge packages.

The meta package then pins the tested package set and gives users one stable
package name without copying the whole conda-forge compiler stack into this
project's channel.

## Licensing and provenance

The MIT license covers the repository's scripts and documentation only.

The official GitHub Action assembles the toolchain on the consumer's runner
from exact third-party package URLs rather than downloading a project-hosted
binary toolchain Release. The repository therefore does not currently present
its MIT license as redistribution terms for the assembled GCC, glibc/sysroot,
libstdc++, libgcc, binutils, or AlmaLinux payloads.

A locally generated `dist/*.tar.zst` still contains those third-party binaries
and must not be treated as automatically MIT-redistributable.

See [THIRD_PARTY.md](THIRD_PARTY.md).
