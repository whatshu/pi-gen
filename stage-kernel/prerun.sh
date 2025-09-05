#!/bin/bash -e

DEBS_DIR="${STAGE_DIR}/files"
mkdir -p "${DEBS_DIR}"

if [[ -n "${KERNEL_SRC:-}" ]]; then
  echo "Building kernel from source: ${KERNEL_SRC}"
  
  KERNEL_MODEL="${KERNEL_MODEL:-pi5}"
  BUILD_SCRIPT="${STAGE_DIR}/tools/build_kernel_debs.sh"
  
  if [[ ! -d "${KERNEL_SRC}" ]]; then
    echo "ERROR: KERNEL_SRC not found: ${KERNEL_SRC}"
    exit 1
  fi
  
  if [[ ! -x "${BUILD_SCRIPT}" ]]; then
    echo "ERROR: Build script not found or not executable: ${BUILD_SCRIPT}"
    exit 1
  fi
  
  echo "Kernel model: ${KERNEL_MODEL}"
  
  rm -f "${DEBS_DIR}"/*.deb "${DEBS_DIR}"/*.sha256
  
  "${BUILD_SCRIPT}" \
    --src "${KERNEL_SRC}" \
    --out "${DEBS_DIR}" \
    --model "${KERNEL_MODEL}"

./build_kernel_debs.sh -s /home/whatshu/develop/project/raspi/linux -o ../files -m pi5
  
  echo "Kernel debs built successfully"
fi

if ! compgen -G "${DEBS_DIR}/*.deb" >/dev/null; then
  echo "ERROR: No kernel debs found in ${DEBS_DIR}/"
  echo "Either provide pre-built debs or set KERNEL_SRC environment variable"
  exit 1
fi

echo "Kernel debs ready: $(ls ${DEBS_DIR}/*.deb | wc -l) packages"
