#!/bin/bash -e

DEBS_DIR="${STAGE_WORK_DIR}/kernel-debs"
mkdir -p "${DEBS_DIR}"

if [[ -n "${KERNEL_SRC:-}" ]]; then
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

if ! compgen -G "${DEBS_DIR}/*.deb" >/dev/null; then
  echo "ERROR: No kernel debs found in ${DEBS_DIR}/"
  exit 1
fi

