# Conda channel

This directory contains the conda packaging model for the toolchain. It supports local `file://` validation and, after successful `main` validation, direct publication through GitHub Pages.

The packages are split by ownership:

- `rhel8-gcc-toolset12-compat` owns only the RHEL 8 compatibility runtime overlay under `lib/rhel8-gcc-toolset12/`;
- `rhel8-gcc-toolset12-activate` owns wrappers, a patched copy of the GCC link spec, and conda activation scripts;
- `rhel8-gcc-toolset12-toolchain` is the user-facing meta package that pins the tested conda-forge package set.

The wrappers deliberately do not modify files owned by conda-forge. In particular, the original GCC `specs` file remains untouched; the wrapper loads a project-owned `link.specs` override that removes the conda prefix RPATH and adds the compatibility runtime search directory.

Install from the public channel with micromamba:

```bash
micromamba create -y -n rhel8-gcc-toolset12 \
  --override-channels \
  -c https://edgeatzero.github.io/rhel8-gcc-toolset12-toolchain/conda \
  -c conda-forge \
  --strict-channel-priority \
  rhel8-gcc-toolset12-toolchain=1.0.0

micromamba activate rhel8-gcc-toolset12
```

The named environment uses micromamba's normal environment location; no `/opt/toolchains` prefix is required for channel users.

Build and validate the local channel:

```bash
./scripts/build-conda-channel.sh
```

The script creates the channel under `~/.cache/rhel8-gcc-toolset12-toolchain/conda-channel`, mirrors the exact corresponding source RPMs under `sources/`, installs the meta package into a temporary prefix, then runs source-bundle, ABI, package-ownership, and activation/deactivation checks. The activation layer runs after the conda-forge compiler scripts, routes `CC`/`CXX` through the target-prefixed compatibility compiler wrappers, preserves conda-forge's target-prefixed binutils behavior, and removes conda-forge's prefix RPATH from `LDFLAGS`.

A local install can be tested directly with the `file://` channel printed by the build script.

CI runs the same path in `.github/workflows/conda-channel.yml` on a clean Ubuntu runner and uploads the complete validated channel as a short-lived workflow artifact.

For successful `main` runs, a publish job downloads that exact validated artifact, prepares `.nojekyll`, `conda/`, and a small landing page, then deploys the snapshot directly through GitHub Pages. No generated Git branch is created or retained.

The resulting local channel remains useful for engineering validation, while GitHub Pages is the public distribution surface after Pages is enabled with **Source: GitHub Actions**. Its `sources/` directory contains the two SHA-256-pinned AlmaLinux source RPMs corresponding to all three redistributed GCC runtime payloads, together with machine-readable mapping metadata. See `THIRD_PARTY.md` for the redistribution model and provenance details.
