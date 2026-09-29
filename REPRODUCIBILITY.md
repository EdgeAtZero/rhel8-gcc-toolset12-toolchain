# Reproducibility

This project separates two concepts:

1. **deterministic dependency resolution**  release builds must use exactly the committed inputs;
2. **byte-for-byte archive reproducibility**  repeated packaging should produce the same bytes when the assembled prefix and packaging tool versions are the same.

## Pinned inputs

The release build consumes:

- a SHA-256-pinned micromamba binary from `manifests/toolchain.json`;
- `manifests/conda-linux-64.lock`, an `@EXPLICIT` conda lock containing exact URLs/build strings and package SHA-256 values;
- fixed AlmaLinux 8.10 RPM URLs and SHA-256 values from `manifests/toolchain.json`.

No conda solver is run in the release assembly path.

## Prefix normalization

micromamba normally writes machine-specific data to `conda-meta`, including transaction timestamps, package cache paths, and the original command line.

`scripts/normalize-conda-metadata.py` removes those volatile fields while preserving package identity, build, URL, hashes, dependency records, installed file records, and license metadata. `conda-meta/history` is replaced with a deterministic pointer to the embedded explicit lock.

The release prefix also embeds:

```text
TOOLCHAIN-MANIFEST.json
CONDA-EXPLICIT.lock
TOOLCHAIN-METADATA.txt
```

## Archive normalization

`scripts/package-toolchain.sh` uses:

- sorted tar member order;
- `SOURCE_DATE_EPOCH` for all archive mtimes;
- uid/gid 0 with numeric ownership;
- GNU tar format;
- single-threaded zstd compression.

The release metadata records the source commit, epoch, manifest/lock hashes, artifact hashes, and host tar/zstd versions.

## Current non-hermetic boundary

The repository does not yet pin the complete build container/OS image. In particular, `tar`, `zstd`, `rpm2cpio`, `cpio`, the kernel, and filesystem implementation are provided by the host runner.

Therefore the current guarantee is intentionally narrower than bit-identical on every Linux machine forever. The CI pipeline aims to make input resolution deterministic and package output reproducible under equivalent host packaging tools.

A future stronger model could build inside a digest-pinned OCI image or use a Nix/Guix-style fully pinned host environment, but that is not required for the current ABI toolchain distribution model.
