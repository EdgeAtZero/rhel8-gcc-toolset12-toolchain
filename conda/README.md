# Experimental local conda channel

This directory contains the first local-only conda packaging model for the toolchain. It is intentionally not published yet.

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

CI runs the same path in `.github/workflows/conda-channel.yml` on a clean Ubuntu runner and uploads the complete validated channel as a single workflow artifact. The workflow does not deploy GitHub Pages or otherwise publish a permanent channel.

The resulting channel is still for local engineering validation only. Its `sources/` directory contains the two SHA-256-pinned AlmaLinux source RPMs corresponding to all three redistributed GCC runtime payloads, together with machine-readable mapping metadata. See `THIRD_PARTY.md` for the redistribution model and provenance details.
