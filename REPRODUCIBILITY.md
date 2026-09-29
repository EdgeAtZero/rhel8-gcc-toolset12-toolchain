# Reproducibility

This project separates three concepts:

1. **deterministic dependency resolution** - assembly must use exactly the committed inputs;
2. **toolchain verification** - the assembled prefix must satisfy the committed ABI policy;
3. **byte-for-byte local archive reproducibility** - optional local packaging should produce the same bytes when the assembled prefix and packaging tool versions are the same.

## Pinned inputs

The assembly path consumes:

- a SHA-256-pinned micromamba binary from `manifests/toolchain.json`;
- `manifests/conda-linux-64.lock`, an `@EXPLICIT` conda lock containing exact URLs/build strings and package SHA-256 values;
- fixed AlmaLinux 8.10 RPM URLs and SHA-256 values from `manifests/toolchain.json`.

No conda solver is run in the pinned assembly path.

## Prefix normalization

micromamba normally writes machine-specific data to `conda-meta`, including
transaction timestamps, package cache paths, and the original command line.

`scripts/normalize-conda-metadata.py` removes those volatile fields while
preserving package identity, build, URL, hashes, dependency records, installed
file records, and license metadata. `conda-meta/history` is replaced with a
deterministic pointer to the embedded explicit lock.

The assembled prefix also embedds:

```text
TOOLCHAIN-MANIFEST.json
CONDA-EXPLICIT.lock
TOOLCHAIN-METADATA.txt
```

## Local archive normalization

`scripts/package-toolchain.sh` is retained for local/internal reproducibility
work. It uses:

- sorted tar member order;
- `SOURCE_DATE_EPOCH` for all archive mtimes;
- uid/gid 0 with numeric ownership;
- GNU tar format;
- single-threaded zstd compression.

The generated metadata records the source commit, epoch, manifest/lock hashes,
artifact hashes, and host tar/zstd versions.

The project does not currently publish this assembled archive as an official
GitHub Release asset because the archive contains third-party binaries whose
redistribution terms must be handled independently from this repository's MIT
license.

## Current non-hermetic boundary

The repository does not yet pin the complete build container/OS image. In
particular, `tar`, `zctd`, `rpm2cpio`, `cpio`, the kernel, and filesystem
implementation are supplied by the host runner.

Therefore the current guarantee is intentionally narrower than "bit-identical
on every Linux machine forever". The CI pipeline aims to make dependency
selection deterministic and the assembled toolchain verifiable under an
equivalent host environment.

A future stronger model could build inside a digest-pinned OCI image or use a
Nix/Guix-style fully pinned host environment.
