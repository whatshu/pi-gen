# stage-kernel

`stage-kernel` injects a custom Raspberry Pi kernel into the final `pi-gen` image without adding a second Docker boundary. The intended flow is:

1. `pi-gen/build-docker.sh` starts the only container used by the build.
2. `stage-kernel/00-build-kernel` either copies prebuilt `.deb` files or builds them from `KERNEL_SRC`.
3. `stage-kernel/01-install-kernel` installs the packages, keeps the stock Raspberry Pi kernel packages as fallback, and records the exact custom kernel release for export.
4. `export-image/05-finalise` copies the custom kernel, DTBs, overlays, and initramfs into `/boot/firmware`.

## Configuration

- `KERNEL_STAGE_MODE`
  Selects the stage-kernel input mode. Supported values are `fragment`, `config-file`, `current-config`, and `deb-files`.
- `KERNEL_SRC`
  Build a kernel from source inside the `pi-gen` container. Required for `fragment`, `config-file`, and `current-config` modes.
- `KERNEL_DEBS_DIR`
  Reuse prebuilt kernel packages from a directory instead of compiling during `stage-kernel`. Accepted by `deb-files` mode.
- `KERNEL_DEB_FILES`
  Space-separated list of specific kernel `.deb` files. This is the most direct way to install a custom kernel without cloning the `linux/` tree.
- `KERNEL_MODEL`
  Selects the Raspberry Pi family defaults. `pi5` and `cm5` default to `bcm2712_defconfig`.
- `KERNEL_DEFCONFIG`
  Optional override for the base defconfig used before fragment merge.
- `KERNEL_CONFIG_FEATURES`
  Space-separated list of config fragment paths that act as the default feature set. In `fragment` mode, when `KERNEL_CONFIG_FRAGMENTS` is not explicitly set, the stage falls back to `KERNEL_CONFIG_FEATURES`. This lets callers control features at a higher level (e.g. from `pi-gen/config`) while still allowing direct fragment overrides.
- `KERNEL_CONFIG_FRAGMENTS`
  Space-separated list of config fragments for `fragment` mode. Takes precedence over `KERNEL_CONFIG_FEATURES` when explicitly set. Absolute paths are used as-is; relative paths are resolved from the `pi-gen` checkout before the stage enters the kernel source tree. If neither `KERNEL_CONFIG_FEATURES` nor `KERNEL_CONFIG_FRAGMENTS` is set for `pi5/cm5`, the stage defaults to [`configs/pi5-network-tuning.conf`](./configs/pi5-network-tuning.conf).
- `KERNEL_CONFIG_FILE`
  Full kernel config file to apply before the build starts in `config-file` mode. Relative paths are resolved from the `pi-gen` checkout.
- `KERNEL_LLVM`
  Set to `1` by default so the build matches the modern Raspberry Pi kernel toolchain and Rust-capable configs.

## Mode Examples

`fragment` mode keeps the current reproducible flow of `defconfig + fragment merge`:

```bash
export STAGE_LIST="stage0 stage1 stage2 stage-kernel"
export KERNEL_STAGE_MODE="fragment"
export KERNEL_SRC="/home/whatshu/develop/project/raspi/linux"
export KERNEL_MODEL="pi5"
# Option 1: use a feature list (build.sh defaults apply when unset)
export KERNEL_CONFIG_FEATURES="stage-kernel/configs/pi5-network-tuning.conf"
# Option 2: explicit fragments (takes precedence over features)
export KERNEL_CONFIG_FRAGMENTS="stage-kernel/configs/pi5-network-tuning.conf"
```

`config-file` mode copies in a full `.config` file just before compilation:

```bash
export STAGE_LIST="stage0 stage1 stage2 stage-kernel"
export KERNEL_STAGE_MODE="config-file"
export KERNEL_SRC="/home/whatshu/develop/project/raspi/linux"
export KERNEL_CONFIG_FILE="/home/whatshu/develop/project/raspi/configs/pi5-debug.config"
```

`current-config` mode compiles the existing `${KERNEL_SRC}/.config` without replacing it:

```bash
export STAGE_LIST="stage0 stage1 stage2 stage-kernel"
export KERNEL_STAGE_MODE="current-config"
export KERNEL_SRC="/home/whatshu/develop/project/raspi/linux"
```

`deb-files` mode installs already-built packages and skips the source tree entirely:

```bash
export STAGE_LIST="stage0 stage1 stage2 stage-kernel"
export KERNEL_STAGE_MODE="deb-files"
export KERNEL_DEB_FILES="/path/linux-image-custom.deb /path/linux-headers-custom.deb /path/linux-libc-dev_custom.deb"
```

## Docker Workflow

- Use `pi-gen/build-docker.sh` as the top-level entrypoint.
- When `KERNEL_SRC` points at a host checkout, `build-docker.sh` mounts it at `/kernel-src` and passes that path into the container.
- Do not run `linux/build-docker.sh` from inside `pi-gen`; that would create nested Docker and break the stage contract.

## Release Branch Workflow

When you need to validate against a fresh Raspberry Pi kernel release:

1. Fetch upstream tags in the `linux/` checkout.
2. Create a test branch from the latest Raspberry Pi release tag.
3. Apply the kernel-side build flow changes on that branch.
4. Point `KERNEL_SRC` at that checkout and run `pi-gen/build-docker.sh`.

Keeping the `linux/` changes and the `pi-gen/` integration changes in separate commits makes it easier to review and bisect the workflow later.
