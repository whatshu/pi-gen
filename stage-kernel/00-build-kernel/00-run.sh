#!/bin/bash -e

DEBS_DIR="${STAGE_WORK_DIR}/kernel-debs"
METADATA_FILE="${STAGE_WORK_DIR}/kernel-release.env"
mkdir -p "${DEBS_DIR}"

KERNEL_MODEL="${KERNEL_MODEL:-pi5}"
KERNEL_LLVM="${KERNEL_LLVM:-1}"

case "${KERNEL_MODEL}" in
  pi1|zero)
    DEFAULT_DEFCONFIG="bcmrpi_defconfig"
    ;;
  pi2|pi3)
    DEFAULT_DEFCONFIG="bcm2709_defconfig"
    ;;
  pi4|pi400|cm4)
    DEFAULT_DEFCONFIG="bcm2711_defconfig"
    ;;
  pi5|cm5)
    DEFAULT_DEFCONFIG="bcm2712_defconfig"
    ;;
  *)
    echo "ERROR: Unsupported KERNEL_MODEL: ${KERNEL_MODEL}"
    exit 1
    ;;
esac

KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-${DEFAULT_DEFCONFIG}}"
if [[ -z "${KERNEL_CONFIG_FRAGMENTS:-}" ]] && [[ "${KERNEL_MODEL}" =~ ^(pi5|cm5)$ ]]; then
  KERNEL_CONFIG_FRAGMENTS="${STAGE_DIR}/configs/pi5-network-tuning.conf"
fi
if [[ -n "${KERNEL_CONFIG_FRAGMENTS:-}" ]]; then
  # Resolve relative fragment paths before the helper switches into the kernel tree.
  RESOLVED_CONFIG_FRAGMENTS=()
  for fragment in ${KERNEL_CONFIG_FRAGMENTS}; do
    if [[ "${fragment}" = /* ]]; then
      RESOLVED_CONFIG_FRAGMENTS+=("${fragment}")
    elif [[ -n "${BASE_DIR:-}" && -e "${BASE_DIR}/${fragment}" ]]; then
      RESOLVED_CONFIG_FRAGMENTS+=("${BASE_DIR}/${fragment}")
    elif [[ -e "${STAGE_DIR}/${fragment}" ]]; then
      RESOLVED_CONFIG_FRAGMENTS+=("${STAGE_DIR}/${fragment}")
    else
      RESOLVED_CONFIG_FRAGMENTS+=("${fragment}")
    fi
  done
  KERNEL_CONFIG_FRAGMENTS="${RESOLVED_CONFIG_FRAGMENTS[*]}"
fi

# Determine which mode to use: build from source or use pre-built debs
if [[ -n "${KERNEL_DEBS_DIR:-}" ]] && [[ -n "${KERNEL_SRC:-}" ]]; then
  echo "ERROR: Both KERNEL_DEBS_DIR and KERNEL_SRC are set. Please use only one."
  echo "  - Set KERNEL_SRC to build kernel from source"
  echo "  - Set KERNEL_DEBS_DIR to use pre-built deb packages"
  exit 1
fi

# Mode 1: Use pre-built deb packages
if [[ -n "${KERNEL_DEBS_DIR:-}" ]]; then
  echo "Using pre-built kernel debs from: ${KERNEL_DEBS_DIR}"
  
  if [[ ! -d "${KERNEL_DEBS_DIR}" ]]; then
    echo "ERROR: KERNEL_DEBS_DIR not found: ${KERNEL_DEBS_DIR}"
    exit 1
  fi
  
  if ! compgen -G "${KERNEL_DEBS_DIR}/*.deb" >/dev/null; then
    echo "ERROR: No .deb files found in ${KERNEL_DEBS_DIR}"
    exit 1
  fi
  
  # Copy pre-built debs to working directory
  cp -a "${KERNEL_DEBS_DIR}"/*.deb "${DEBS_DIR}/"
  if compgen -G "${KERNEL_DEBS_DIR}/*.sha256" >/dev/null; then
    cp -a "${KERNEL_DEBS_DIR}"/*.sha256 "${DEBS_DIR}/"
  fi
  
  echo "Copied $(ls -1 "${DEBS_DIR}"/*.deb | wc -l) deb package(s)"
fi

# Mode 2: Build kernel from source
if [[ -n "${KERNEL_SRC:-}" ]]; then
  echo "Building kernel from source: ${KERNEL_SRC}"
  BUILD_SCRIPT="${STAGE_DIR}/tools/build_kernel_debs.sh"

  if [[ ! -d "${KERNEL_SRC}" ]]; then
    echo "ERROR: KERNEL_SRC not found: ${KERNEL_SRC}"
    exit 1
  fi

  if [[ ! -x "${BUILD_SCRIPT}" ]]; then
    echo "ERROR: Build script not found: ${BUILD_SCRIPT}"
    exit 1
  fi

  rm -f "${DEBS_DIR}"/*.deb "${DEBS_DIR}"/*.sha256

  "${BUILD_SCRIPT}" \
    --src "${KERNEL_SRC}" \
    --out "${DEBS_DIR}" \
    --model "${KERNEL_MODEL}" \
    --defconfig "${KERNEL_DEFCONFIG}" \
    --config-fragments "${KERNEL_CONFIG_FRAGMENTS:-}" \
    --llvm "${KERNEL_LLVM}"
fi

# Verify that we have deb packages
if ! compgen -G "${DEBS_DIR}/*.deb" >/dev/null; then
  echo "ERROR: No kernel debs found in ${DEBS_DIR}/"
  echo "Please set either KERNEL_SRC (to build from source) or KERNEL_DEBS_DIR (to use pre-built debs)"
  exit 1
fi

KERNEL_IMAGE_DEB="$(ls -t "${DEBS_DIR}"/linux-image-*.deb 2>/dev/null | head -1)"
if [[ -z "${KERNEL_IMAGE_DEB}" ]]; then
  echo "ERROR: Missing linux-image package in ${DEBS_DIR}"
  exit 1
fi

KERNEL_IMAGE_PACKAGE="$(dpkg-deb -f "${KERNEL_IMAGE_DEB}" Package)"
KERNEL_RELEASE="${KERNEL_IMAGE_PACKAGE#linux-image-}"
cat > "${METADATA_FILE}" <<EOF
KERNEL_RELEASE=${KERNEL_RELEASE}
KERNEL_IMAGE_PACKAGE=${KERNEL_IMAGE_PACKAGE}
EOF

echo "Kernel deb packages ready in ${DEBS_DIR}"
echo "Kernel release metadata written to ${METADATA_FILE}"
