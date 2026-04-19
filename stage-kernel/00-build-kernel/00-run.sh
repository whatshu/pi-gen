#!/bin/bash -e

DEBS_DIR="${STAGE_WORK_DIR}/kernel-debs"
METADATA_FILE="${STAGE_WORK_DIR}/kernel-release.env"
mkdir -p "${DEBS_DIR}"

KERNEL_MODEL="${KERNEL_MODEL:-pi5}"
KERNEL_LLVM="${KERNEL_LLVM:-1}"
KERNEL_STAGE_MODE="${KERNEL_STAGE_MODE:-}"

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

resolve_stage_path_list() {
  local resolved_paths=()
  local path=""
  for path in $1; do
    if [[ "${path}" = /* ]]; then
      resolved_paths+=("${path}")
    elif [[ -n "${BASE_DIR:-}" && -e "${BASE_DIR}/${path}" ]]; then
      resolved_paths+=("${BASE_DIR}/${path}")
    elif [[ -e "${STAGE_DIR}/${path}" ]]; then
      resolved_paths+=("${STAGE_DIR}/${path}")
    else
      resolved_paths+=("${path}")
    fi
  done
  printf '%s\n' "${resolved_paths[*]}"
}

KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-${DEFAULT_DEFCONFIG}}"

if [[ -z "${KERNEL_STAGE_MODE}" ]]; then
  if [[ -n "${KERNEL_DEB_FILES:-}" || -n "${KERNEL_DEBS_DIR:-}" ]]; then
    KERNEL_STAGE_MODE="deb-files"
  elif [[ -n "${KERNEL_CONFIG_FILE:-}" ]]; then
    KERNEL_STAGE_MODE="config-file"
  elif [[ -n "${KERNEL_SRC:-}" ]]; then
    KERNEL_STAGE_MODE="fragment"
  else
    echo "ERROR: No kernel stage mode could be inferred."
    echo "Set KERNEL_STAGE_MODE and the corresponding input variables."
    exit 1
  fi
fi

if [[ "${KERNEL_STAGE_MODE}" == "fragment" ]] && [[ -z "${KERNEL_CONFIG_FRAGMENTS:-}" ]] && [[ "${KERNEL_MODEL}" =~ ^(pi5|cm5)$ ]]; then
  KERNEL_CONFIG_FRAGMENTS="${STAGE_DIR}/configs/pi5-network-tuning.conf"
fi
if [[ -n "${KERNEL_CONFIG_FRAGMENTS:-}" ]]; then
  # Resolve relative fragment paths before the helper switches into the kernel tree.
  KERNEL_CONFIG_FRAGMENTS="$(resolve_stage_path_list "${KERNEL_CONFIG_FRAGMENTS}")"
fi
if [[ -n "${KERNEL_CONFIG_FILE:-}" ]]; then
  KERNEL_CONFIG_FILE="$(resolve_stage_path_list "${KERNEL_CONFIG_FILE}")"
fi
if [[ -n "${KERNEL_DEB_FILES:-}" ]]; then
  KERNEL_DEB_FILES="$(resolve_stage_path_list "${KERNEL_DEB_FILES}")"
fi

case "${KERNEL_STAGE_MODE}" in
  deb-files)
    if [[ -n "${KERNEL_SRC:-}" || -n "${KERNEL_CONFIG_FILE:-}" || -n "${KERNEL_CONFIG_FRAGMENTS:-}" ]]; then
      echo "ERROR: deb-files mode does not accept KERNEL_SRC, KERNEL_CONFIG_FILE, or KERNEL_CONFIG_FRAGMENTS."
      exit 1
    fi

    rm -f "${DEBS_DIR}"/*.deb "${DEBS_DIR}"/*.sha256

    if [[ -n "${KERNEL_DEBS_DIR:-}" ]]; then
      echo "Using pre-built kernel debs from directory: ${KERNEL_DEBS_DIR}"
      if [[ ! -d "${KERNEL_DEBS_DIR}" ]]; then
        echo "ERROR: KERNEL_DEBS_DIR not found: ${KERNEL_DEBS_DIR}"
        exit 1
      fi

      if ! compgen -G "${KERNEL_DEBS_DIR}/*.deb" >/dev/null; then
        echo "ERROR: No .deb files found in ${KERNEL_DEBS_DIR}"
        exit 1
      fi

      cp -a "${KERNEL_DEBS_DIR}"/*.deb "${DEBS_DIR}/"
      if compgen -G "${KERNEL_DEBS_DIR}/*.sha256" >/dev/null; then
        cp -a "${KERNEL_DEBS_DIR}"/*.sha256 "${DEBS_DIR}/"
      fi
    fi

    if [[ -n "${KERNEL_DEB_FILES:-}" ]]; then
      echo "Using explicitly listed kernel deb files"
      for deb_file in ${KERNEL_DEB_FILES}; do
        if [[ ! -f "${deb_file}" ]]; then
          echo "ERROR: kernel deb file not found: ${deb_file}"
          exit 1
        fi
        cp -a "${deb_file}" "${DEBS_DIR}/"
      done
    fi

    if ! compgen -G "${DEBS_DIR}/*.deb" >/dev/null; then
      echo "ERROR: deb-files mode requires KERNEL_DEBS_DIR or KERNEL_DEB_FILES."
      exit 1
    fi

    if ! compgen -G "${DEBS_DIR}/*.sha256" >/dev/null; then
      (
        cd "${DEBS_DIR}"
        sha256sum ./*.deb > kernel-debs.sha256
      )
    fi
    echo "Copied $(ls -1 "${DEBS_DIR}"/*.deb | wc -l) deb package(s)"
    ;;
  fragment|config-file|current-config)
    echo "Building kernel from source: ${KERNEL_SRC}"
    BUILD_SCRIPT="${STAGE_DIR}/tools/build_kernel_debs.sh"

    if [[ ! -d "${KERNEL_SRC:-}" ]]; then
      echo "ERROR: KERNEL_SRC not found: ${KERNEL_SRC:-}"
      exit 1
    fi

    if [[ ! -x "${BUILD_SCRIPT}" ]]; then
      echo "ERROR: Build script not found: ${BUILD_SCRIPT}"
      exit 1
    fi

    if [[ "${KERNEL_STAGE_MODE}" == "config-file" && -z "${KERNEL_CONFIG_FILE:-}" ]]; then
      echo "ERROR: config-file mode requires KERNEL_CONFIG_FILE."
      exit 1
    fi
    if [[ "${KERNEL_STAGE_MODE}" == "fragment" && -n "${KERNEL_CONFIG_FILE:-}" ]]; then
      echo "ERROR: fragment mode does not accept KERNEL_CONFIG_FILE."
      exit 1
    fi
    if [[ "${KERNEL_STAGE_MODE}" == "config-file" && -n "${KERNEL_CONFIG_FRAGMENTS:-}" ]]; then
      echo "ERROR: config-file mode does not accept KERNEL_CONFIG_FRAGMENTS."
      exit 1
    fi

    if [[ "${KERNEL_STAGE_MODE}" == "current-config" && -n "${KERNEL_CONFIG_FILE:-}" ]]; then
      echo "ERROR: current-config mode does not accept KERNEL_CONFIG_FILE."
      exit 1
    fi
    if [[ "${KERNEL_STAGE_MODE}" == "current-config" && -n "${KERNEL_CONFIG_FRAGMENTS:-}" ]]; then
      echo "ERROR: current-config mode does not accept KERNEL_CONFIG_FRAGMENTS."
      exit 1
    fi

    rm -f "${DEBS_DIR}"/*.deb "${DEBS_DIR}"/*.sha256

    BUILD_CMD=(
      "${BUILD_SCRIPT}"
      --src "${KERNEL_SRC}"
      --out "${DEBS_DIR}"
      --model "${KERNEL_MODEL}"
      --defconfig "${KERNEL_DEFCONFIG}"
      --config-mode "${KERNEL_STAGE_MODE}"
      --llvm "${KERNEL_LLVM}"
    )

    if [[ "${KERNEL_STAGE_MODE}" == "fragment" && -n "${KERNEL_CONFIG_FRAGMENTS:-}" ]]; then
      BUILD_CMD+=(--config-fragments "${KERNEL_CONFIG_FRAGMENTS}")
    fi
    if [[ "${KERNEL_STAGE_MODE}" == "config-file" ]]; then
      BUILD_CMD+=(--config-file "${KERNEL_CONFIG_FILE}")
    fi

    "${BUILD_CMD[@]}"
    ;;
  *)
    echo "ERROR: Unsupported KERNEL_STAGE_MODE: ${KERNEL_STAGE_MODE}"
    echo "Supported: fragment, config-file, current-config, deb-files"
    exit 1
    ;;
esac

# Verify that we have deb packages
if ! compgen -G "${DEBS_DIR}/*.deb" >/dev/null; then
  echo "ERROR: No kernel debs found in ${DEBS_DIR}/"
  echo "Please configure one of: fragment, config-file, current-config, or deb-files mode."
  exit 1
fi

KERNEL_IMAGE_DEB="$(ls -t "${DEBS_DIR}"/linux-image-*.deb 2>/dev/null | head -1)"
if [[ -z "${KERNEL_IMAGE_DEB}" ]]; then
  echo "ERROR: Missing linux-image package in ${DEBS_DIR}"
  exit 1
fi

if ! KERNEL_IMAGE_PACKAGE="$(dpkg-deb -f "${KERNEL_IMAGE_DEB}" Package 2>/dev/null)"; then
  echo "ERROR: Failed to read package metadata from ${KERNEL_IMAGE_DEB}"
  exit 1
fi
KERNEL_RELEASE="${KERNEL_IMAGE_PACKAGE#linux-image-}"
cat > "${METADATA_FILE}" <<EOF
KERNEL_RELEASE=${KERNEL_RELEASE}
KERNEL_IMAGE_PACKAGE=${KERNEL_IMAGE_PACKAGE}
EOF

echo "Kernel deb packages ready in ${DEBS_DIR}"
echo "Kernel release metadata written to ${METADATA_FILE}"
