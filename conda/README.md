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

The script creates the channel under `~/.cache/rhel8-gcc-toolset12-toolchain/conda-channel`, installs the meta package into a temporary prefix, then runs ABI and package-ownership checks plus a real activation/deactivation smoke test. The activation layer runs after the conda-forge compiler scripts, points `CC`/`CXX` and binutils at the compatibility wrappers, and removes conda-forge's prefix RPATH from `LDFLAGS`.

A local install can be tested directly with the `file://` channel printed by the build script.

The resulting channel is for local engineering validation only. The compatibility package contains AlmaLinux/GNU binary payloads and must not be published until the exact corresponding-source and third-party notice requirements described in `THIRD_PARTY.md` are satisfied.
