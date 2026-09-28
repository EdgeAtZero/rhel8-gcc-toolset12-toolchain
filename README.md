# RHEL 8 GCC Toolset 12 Toolchain

A reproducible Linux x86_64 release toolchain built from:

- micromamba / conda-forge for GCC 12.2, binutils, and a glibc 2.28 sysroot;
- AlmaLinux 8 runtime packages for the RHEL 8 ABI baseline;
- GCC Toolset 12 libstdc++_nonshared.a for the compatibility strategy used by RHEL 8 GCC Toolset builds.

The installed toolchain name is:

```text
linux-x86_64-rhel8-gcc-toolset12
```

Its intended compatibility ceiling is:

```text
GLIBC   <= 2.28
GLIBCXX <= 3.4.25
```

Those values are a target, not an assumption: final application binaries should always be checked with `readelf --version-info`.

## Why this exists

Modern projects such as Node.js 24 need a C++20-capable compiler and modern libstdc++ headers. Simply compiling with GCC 8 headers is not viable.

RHEL 8's GCC Toolset model solves the problem differently:

1. compile with GCC 12 and GCC 12 C++ headers;
2. dynamically link the RHEL 8 / GCC 8-era `libstdc++.so.6`;
3. statically supplement newer implementation pieces from `libstdc++_nonshared.a`.

This repository reproduces that model while using a micromamba-managed GCC/sysroot as the base.

## Requirements

On Arch Linux / WSL Arch:

```bash
sudo pacman -S --needed curl cpio rpm-tools zstd
```

You also need `micromamba` available on `PATH`.

The build script uses `sudo` only when the destination prefix requires it.

## Build

```bash
./scripts/build-toolchain.sh
```

Default installation path:

```text
/opt/toolchains/linux-x86_64-rhel8-gcc-toolset12
```

To rebuild an existing prefix:

```bash
./scripts/build-toolchain.sh --force
```

A custom prefix can be supplied for experiments:

```bash
./scripts/build-toolchain.sh --prefix /tmp/rhel8-gcc-toolset12
```

The default `/opt/toolchains` location is recommended for release builds because conda compiler packages are prefix-aware.

## Verify

```bash
./scripts/verify-toolchain.sh
```

The verification probe checks:

- C++20 `<version>`, `std::span`, ranges and condition variables;
- `GLIBC <= 2.28`;
- `GLIBCXX <= 3.4.25`;
- no toolchain-prefix RPATH/RUNPATH in the probe;
- the GCC 8-era runtime and GCC Toolset compatibility layer are active.

## Use

The toolchain exposes normal short command names under its `bin` directory, including `gcc`, `g++`, `cc`, `c++`, `ld`, `ar`, and `readelf`.

Configure the toolchain manually:

```bash
export PATH=/opt/toolchains/linux-x86_64-rhel8-gcc-toolset12/bin:$PATH
export CC=/opt/toolchains/linux-x86_64-rhel8-gcc-toolset12/bin/cc
export CXX=/opt/toolchains/linux-x86_64-rhel8-gcc-toolset12/bin/c++
```

Do not use `micromamba activate` for release builds. Activation can inject prefix library paths through build flags and defeat the intended target ABI layer.

## GitHub Action

Consumers do not need to reproduce the download or environment setup logic. A release tag can be used directly as a composite action:

```yaml
- name: Set up RHEL 8 GCC Toolset 12
  id: toolchain
  uses: EdgeAtZero/rhel8-gcc-toolset12-toolchain@v1.0.0
```

The action:

1. downloads the toolchain archive and checksum from the matching GitHub Release;
2. verifies SHA-256;
3. installs the prefix at `/opt/toolchains/linux-x86_64-rhel8-gcc-toolset12`;
4. adds the toolchain `bin` directory to `GITHUB_PATH`;
5. exports `CC`, `CXX`, `AR`, `LD`, and the other binutils through `GITHUB_ENV`;
6. runs the ABI verification probe by default.

The action tag and toolchain release tag are intentionally the same. For example, `@v1.0.0` installs the `v1.0.0` Release asset.

It exposes:

```text
prefix
version
identity
```

The `identity` output is intended for build cache keys:

```yaml
- name: Restore native cache
  uses: actions/cache/restore@v4
  with:
    path: nodejs-jni/sdk/linux-x86_64
    key: libnode-linux-x86_64-${{ steps.toolchain.outputs.identity }}-${{ hashFiles('nodejs-jni/node-sdk.json') }}
```

For unusual cases, the release can be overridden explicitly:

```yaml
- uses: EdgeAtZero/rhel8-gcc-toolset12-toolchain@v1.0.0
  with:
    version: v1.0.0
    verify: 'true'
```

The action supports Linux x86_64 runners only. Because the compiler prefix is not arbitrarily relocatable, installation is intentionally fixed under `/opt/toolchains`.

## Package

After verification:

```bash
./scripts/package-toolchain.sh
```

This creates a `.tar.zst` plus SHA-256 checksum under `dist/`.

The archive is built for installation under:

```text
/opt/toolchains/linux-x86_64-rhel8-gcc-toolset12
```

It should not be treated as an arbitrary relocatable compiler prefix.

## GitHub Actions

`.github/workflows/build.yml` reproduces and verifies the toolchain on GitHub-hosted Linux runners.

- pushes and pull requests build and verify it;
- workflow dispatch can be run manually;
- tags matching `v*` additionally upload the packaged toolchain to a GitHub Release.

## Publishing for micromamba

The current repository uses micromamba as the reproducible base environment resolver and produces a ready-to-install toolchain archive.

A future conda channel is also possible, but it should be implemented as a dedicated compatibility/wrapper package rather than by blindly overwriting files owned by conda-forge compiler packages. This repository intentionally keeps the first public format simple and auditable: pinned inputs, a deterministic assembly script, ABI verification, and a packaged prefix.

## Provenance

Pinned AlmaLinux 8 packages are downloaded from the official AlmaLinux repositories and verified by SHA-256.

The repository's MIT license covers only the scripts and documentation in this repository. The generated toolchain contains third-party software under its own licenses; see [THIRD_PARTY.md](THIRD_PARTY.md).
