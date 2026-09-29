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

Release builds do not run the conda solver.

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

Release archives are intentionally built for the default `/opt/toolchains/...` prefix. The conda compiler packages contain prefix-aware content, so the archive is not advertised as arbitrarily relocatable.

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

## Package

```bash
./scripts/package-toolchain.sh
```

Release output under `dist/` includes:

```text
linux-x86_64-rhel8-gcc-toolset12.tar.zst
linux-x86_64-rhel8-gcc-toolset12.tar.zst.sha256
linux-x86_64-rhel8-gcc-toolset12.spdx.json
RELEASE-METADATA.json
SHA256SUMS
```

The SPDX 2.3 SBOM describes the exact conda package records plus the AlmaLinux RPM compatibility components.

## GitHub Action

Consumers can install the matching release directly:

```yaml
- name: Set up RHEL 8 GCC Toolset 12
  id: toolchain
  uses: EdgeAtZero/rhel8-gcc-toolset12-toolchain@v1.0.0
```

The Action tag and toolchain Release tag are intentionally identical. It downloads the release through the GitHub Releases API, verifies SHA-256, extracts into an unprivileged temporary directory, rejects escaping/absolute symlinks, verifies the embedded manifest, and only then installs the fixed prefix under `/opt/toolchains`.

It exports `PATH`, `CC`, `CXX`, `CPP`, `GCC`, `GXX`, and the common binutils variables, then runs the ABI verification gate by default.

Outputs:

```text
prefix
version
identity
```

The `identity` output is intended for consumer cache keys:

```yaml
key: native-linux-x86_64-${{ steps.toolchain.outputs.identity }}-${{ hashFiles('your-inputs.json') }}
```

Optional inputs:

```yaml
- uses: EdgeAtZero/rhel8-gcc-toolset12-toolchain@v1.0.0
  with:
    version: v1.0.0
    repository: EdgeAtZero/rhel8-gcc-toolset12-toolchain
    verify: 'true'
```

For a private release repository, pass `github-token` with `contents:read` access to that repository.

There is intentionally no arbitrary `install-prefix` input today because the release prefix is not generally relocatable. There is also no final-toolchain Action cache input: Release assets are already immutable distribution objects, while consumers can use the stable `identity` output to cache their own build products.

## GitHub Actions and supply chain

The repository workflow:

1. caches only source/package downloads, not the assembled final toolchain;
2. installs a SHA-256-pinned micromamba binary;
3. builds from the explicit conda lock and pinned RPMs;
4. runs ABI verification;
5. creates deterministic archive metadata, checksums, SPDX SBOM, and release metadata;
6. uploads workflow artifacts;
7. on `v*` tags, creates GitHub artifact attestations for both SLSA build provenance and the SBOM;
8. publishes the already-built files to the matching GitHub Release.

Third-party GitHub Actions are pinned to commit SHAs rather than mutable major tags.

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

The GitHub Release tarball remains the primary distribution model for now.

A future channel should not overwrite files owned by conda-forge packages in-place. A plausible model is:

```text
meta package
+
compat runtime package
+
compiler wrapper / activation package
```

That design needs explicit package ownership, uninstall/update behavior, solver constraints, prefix relocation rules, sysroot behavior, activation semantics, and licensing before it is suitable for publication.

## Licensing and provenance

The MIT license covers the repository's scripts and documentation only.

Generated toolchains contain GCC, glibc/sysroot content, libstdc++, libgcc, binutils, conda-forge packages, and AlmaLinux RPM contents under their own licenses and redistribution terms. The SPDX SBOM is inventory/provenance data and is not a substitute for satisfying those licenses or corresponding-source obligations.

See [THIRD_PARTY.md](THIRD_PARTY.md).
