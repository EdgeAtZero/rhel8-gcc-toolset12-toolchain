# Conda channel

This directory contains the conda packaging model for the toolchain. It supports local `file://` validation and, after successful `main` validation, publication through the generated `gh-pages` snapshot.

The packages are split by ownership:

- `rhel8-gcc-toolset12-compat` owns only the RHEL 8 compatibility runtime overlay under `lib/rhel8-gcc-toolset12/`;
- `rhel8-gcc-toolset12-activate` owns wrappers, a patched copy of the GCC link spec, and conda activation scripts;
- `rhel8-gcc-toolset12-toolchain` is the user-facing meta package that pins the tested conda-forge package set.

The wrappers deliberately do not modify files owned by conda-forge. In particular, the original GCC `specs` file remains untouched; the wrapper loads a project-owned `link.specs` override that removes the conda prefix RPATH and adds the compatibility runtime search directory.

Build and validate the local channel:

```bash
./scripts/build-conda-channel.sh
```

The script creates the channel under `~/.cache/rhel8-gcc-toolset12-toolchain/conda-channel`, mirrors the exact corresponding source RPMs under `sources/`, installs the meta package into a temporary prefix, then runs source-bundle, ABI, package-ownership, and activation/deactivation checks. The activation layer runs after the conda-forge compiler scripts, points `CC`/`CXX` and binutils at the compatibility wrappers, and removes conda-forge's prefix RPATH from `LDFLAGS`.

A local install can be tested directly with the `file://` channel printed by the build script.

CI runs the same path in `.github/workflows/conda-channel.yml` on a clean Ubuntu runner and uploads the complete validated channel as a short-lived workflow artifact.

For successful `main` runs, a publish job downloads that exact validated artifact, creates a fresh orphan `gh-pages` snapshot containing `.nojekyll`, `conda/`, and a small landing page, force-pushes it to `gh-pages`, then deploys the same snapshot through GitHub Pages. Because each snapshot is an orphan commit, the generated branch does not accumulate old SRPM history.

The resulting local channel remains useful for engineering validation, while the `gh-pages` snapshot is the public distribution surface after Pages is enabled with **Source: GitHub Actions**. Its `sources/` directory contains the two SHA-256-pinned AlmaLinux source RPMs corresponding to all three redistributed GCC runtime payloads, together with machine-readable mapping metadata. See `THIRD_PARTY.md` for the redistribution model and provenance details.
