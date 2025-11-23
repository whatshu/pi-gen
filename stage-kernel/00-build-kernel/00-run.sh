#!/bin/bash -e

DEBS_DIR="${STAGE_WORK_DIR}/kernel-debs"
mkdir -p "${DEBS_DIR}"

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
  
  # Check for required build tools on host
  for tool in make gcc bc bison flex; do
    if ! command -v "$tool" &>/dev/null; then
      echo "ERROR: Required tool '$tool' not found on host system"
      exit 1
    fi
  done
  
  KERNEL_MODEL="${KERNEL_MODEL:-pi5}"
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
    --model "${KERNEL_MODEL}"
fi

# Verify that we have deb packages
if ! compgen -G "${DEBS_DIR}/*.deb" >/dev/null; then
  echo "ERROR: No kernel debs found in ${DEBS_DIR}/"
  echo "Please set either KERNEL_SRC (to build from source) or KERNEL_DEBS_DIR (to use pre-built debs)"
  exit 1
fi

echo "Kernel deb packages ready in ${DEBS_DIR}"

