#!/usr/bin/env bash
set -euo pipefail

SRC=""
OUT=""
MODEL="pi4"
DEFCONFIG=""
CONFIG_FEATURES=""
CONFIG_FRAGMENTS=""
CONFIG_FILE=""
CONFIG_MODE="fragment"
KERNEL_LLVM="1"
STAMP_FILE=""
ORIGINAL_CONFIG_BACKUP=""
REMOVE_GENERATED_CONFIG="0"

cleanup() {
  if [[ -n "${ORIGINAL_CONFIG_BACKUP}" && -f "${ORIGINAL_CONFIG_BACKUP}" ]]; then
    cp -f "${ORIGINAL_CONFIG_BACKUP}" "${SRC}/.config"
    rm -f "${ORIGINAL_CONFIG_BACKUP}"
  elif [[ "${REMOVE_GENERATED_CONFIG}" == "1" ]]; then
    rm -f "${SRC}/.config"
  fi

  if [[ -n "${STAMP_FILE}" && -f "${STAMP_FILE}" ]]; then
    rm -f "${STAMP_FILE}"
  fi
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--src) SRC="$2"; shift 2;;
    -o|--out) OUT="$2"; shift 2;;
    -m|--model) MODEL="$2"; shift 2;;
    -d|--defconfig) DEFCONFIG="$2"; shift 2;;
    --config-features) CONFIG_FEATURES="$2"; shift 2;;
    -c|--config-fragments) CONFIG_FRAGMENTS="$2"; shift 2;;
    -f|--config-file) CONFIG_FILE="$2"; shift 2;;
    --config-mode) CONFIG_MODE="$2"; shift 2;;
    -l|--llvm) KERNEL_LLVM="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

[[ -d "$SRC" ]] || { echo "ERROR: --src not found: $SRC"; exit 1; }
mkdir -p "$OUT"

case "$MODEL" in
  pi1|zero)
    ARCH="arm"
    CROSS_COMPILE="arm-linux-gnueabihf-"
    DEFAULT_DEFCONFIG="bcmrpi_defconfig"
    ;;
  pi2|pi3)
    ARCH="arm"
    CROSS_COMPILE="arm-linux-gnueabihf-"
    DEFAULT_DEFCONFIG="bcm2709_defconfig"
    ;;
  pi4|pi400|cm4)
    ARCH="arm64"
    CROSS_COMPILE="aarch64-linux-gnu-"
    DEFAULT_DEFCONFIG="bcm2711_defconfig"
    ;;
  pi5|cm5)
    ARCH="arm64"
    CROSS_COMPILE="aarch64-linux-gnu-"
    DEFAULT_DEFCONFIG="bcm2712_defconfig"
    ;;
  *)
    echo "ERROR: Unknown model: $MODEL"
    echo "Supported: pi1, zero, pi2, pi3, pi4, pi400, cm4, pi5, cm5"
    exit 1
    ;;
esac

DEFCONFIG="${DEFCONFIG:-${DEFAULT_DEFCONFIG}}"
STAMP_FILE="$(mktemp "${SRC}/.bindeb.XXXXXX")"
MAKE_ARGS=()
if [[ "${KERNEL_LLVM}" != "0" ]]; then
  MAKE_ARGS+=(LLVM=1)
fi

JOBS="$(nproc)"

pushd "$SRC" >/dev/null

export ARCH="$ARCH"
export CROSS_COMPILE="$CROSS_COMPILE"

if [[ -z "${RUST_LIB_SRC:-}" ]] && command -v rustc >/dev/null 2>&1; then
  RUST_VERSION=$(rustc --version 2>/dev/null | sed -E 's/rustc ([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true)
  if [[ -n "$RUST_VERSION" ]] && [[ -d "/usr/src/rustc-${RUST_VERSION}/library" ]]; then
    export RUST_LIB_SRC="/usr/src/rustc-${RUST_VERSION}/library"
  fi
fi

if [[ -f .config ]]; then
  ORIGINAL_CONFIG_BACKUP="$(mktemp "${SRC}/.config.stage-kernel.XXXXXX")"
  cp -f .config "${ORIGINAL_CONFIG_BACKUP}"
else
  REMOVE_GENERATED_CONFIG="1"
fi

case "${CONFIG_MODE}" in
  fragment)
    # When CONFIG_FRAGMENTS is not explicitly provided, fall back to the
    # feature list so the caller can control features at a higher level.
    if [[ -z "${CONFIG_FRAGMENTS}" && -n "${CONFIG_FEATURES}" ]]; then
      CONFIG_FRAGMENTS="${CONFIG_FEATURES}"
    fi

    echo "Generating base config from ${DEFCONFIG}"
    make "${MAKE_ARGS[@]}" "${DEFCONFIG}"

    if [[ -n "${CONFIG_FRAGMENTS}" ]]; then
      echo "Config fragments to merge:"
      for fragment in ${CONFIG_FRAGMENTS}; do
        [[ -f "${fragment}" ]] || { echo "ERROR: config fragment not found: ${fragment}"; exit 1; }
        echo "  ${fragment}"
      done

      # Always rebuild from defconfig + fragments so the stage remains reproducible across reruns.
      # shellcheck disable=SC2086
      "${SRC}/scripts/kconfig/merge_config.sh" -m .config ${CONFIG_FRAGMENTS}
    fi

    make "${MAKE_ARGS[@]}" olddefconfig
    ;;
  config-file)
    [[ -f "${CONFIG_FILE}" ]] || { echo "ERROR: --config-file not found: ${CONFIG_FILE}"; exit 1; }
    echo "Applying full kernel config from ${CONFIG_FILE}"
    cp -f "${CONFIG_FILE}" .config
    make "${MAKE_ARGS[@]}" olddefconfig
    ;;
  current-config)
    [[ -f .config ]] || { echo "ERROR: ${SRC}/.config not found for current-config mode"; exit 1; }
    echo "Using existing source tree .config without replacing it"
    ;;
  *)
    echo "ERROR: Unknown config mode: ${CONFIG_MODE}"
    echo "Supported: fragment, config-file, current-config"
    exit 1
    ;;
esac

make "${MAKE_ARGS[@]}" -j"$JOBS" DPKG_FLAGS="-d" bindeb-pkg

popd >/dev/null

PARENT_DIR="$(dirname "$(readlink -f "$SRC")")"
mapfile -t DEBS < <(find "$PARENT_DIR" -maxdepth 1 -type f -name '*.deb' -newer "$STAMP_FILE" -printf '%f\n' | sort)
if [[ "${#DEBS[@]}" -eq 0 ]]; then
  echo "ERROR: No debs produced."
  exit 1
fi

rm -f "$OUT"/*.deb "$OUT"/*.sha256
for f in "${DEBS[@]}"; do
  cp -a "$PARENT_DIR/$f" "$OUT/"
done

pushd "$OUT" >/dev/null
sha256sum *.deb > kernel-debs.sha256
popd >/dev/null 2>&1 || true

echo "Done. Debs ready in: $OUT"
