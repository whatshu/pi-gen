# stage-kernel

`stage-kernel` injects a custom Raspberry Pi kernel into the final `pi-gen` image without adding a second Docker boundary. The intended flow is:

1. `pi-gen/build-docker.sh` starts the only container used by the build.
2. `stage-kernel/00-build-kernel` either copies prebuilt `.deb` files or builds them from `KERNEL_SRC`.
3. `stage-kernel/01-install-kernel` installs the packages, keeps the stock Raspberry Pi kernel packages as fallback, and records the exact custom kernel release for export.
4. `export-image/05-finalise` copies the custom kernel, DTBs, overlays, and initramfs into `/boot/firmware`.

## Configuration

- `KERNEL_SRC`
  Build a kernel from source inside the `pi-gen` container. This is the preferred path when iterating on config fragments.
- `KERNEL_DEBS_DIR`
  Reuse prebuilt kernel packages instead of compiling during `stage-kernel`.
- `KERNEL_MODEL`
  Selects the Raspberry Pi family defaults. `pi5` and `cm5` default to `bcm2712_defconfig`.
- `KERNEL_DEFCONFIG`
  Optional override for the base defconfig used before fragment merge.
- `KERNEL_CONFIG_FRAGMENTS`
  Space-separated list of config fragments. Absolute paths are used as-is; relative paths are resolved from the `pi-gen` checkout before the stage enters the kernel source tree. If unset for `pi5/cm5`, the stage defaults to [`configs/pi5-network-tuning.conf`](./configs/pi5-network-tuning.conf).
- `KERNEL_LLVM`
  Set to `1` by default so the build matches the modern Raspberry Pi kernel toolchain and Rust-capable configs.

Example:

```bash
export STAGE_LIST="stage0 stage1 stage2 stage-kernel"
export KERNEL_SRC="/home/whatshu/develop/project/raspi/linux"
export KERNEL_MODEL="pi5"
export KERNEL_CONFIG_FRAGMENTS="stage-kernel/configs/pi5-network-tuning.conf"
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
