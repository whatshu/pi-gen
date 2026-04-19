#!/usr/bin/env bash
# Note: Avoid usage of arrays as MacOS users have an older version of bash (v3.x) which does not supports arrays
set -eu

DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

BUILD_OPTS="$*"

# Allow user to override docker command
DOCKER=${DOCKER:-docker}

# Ensure that default docker command is not set up in rootless mode
if \
  ! ${DOCKER} ps    >/dev/null 2>&1 || \
    ${DOCKER} info 2>/dev/null | grep -q rootless \
; then
	DOCKER="sudo ${DOCKER}"
fi
if ! ${DOCKER} ps >/dev/null; then
	echo "error connecting to docker:"
	${DOCKER} ps
	exit 1
fi

CONFIG_FILE=""
if [ -f "${DIR}/config" ]; then
	CONFIG_FILE="${DIR}/config"
fi

while getopts "c:" flag
do
	case "${flag}" in
		c)
			CONFIG_FILE="${OPTARG}"
			;;
		*)
			;;
	esac
done

# Ensure that the configuration file is an absolute path
if test -x /usr/bin/realpath; then
	CONFIG_FILE=$(realpath -s "$CONFIG_FILE" || realpath "$CONFIG_FILE")
fi

# Ensure that the confguration file is present
if test -z "${CONFIG_FILE}"; then
	echo "Configuration file need to be present in '${DIR}/config' or path passed as parameter"
	exit 1
else
	# shellcheck disable=SC1090
	source ${CONFIG_FILE}
fi

CONTAINER_NAME=${CONTAINER_NAME:-pigen_work}
CONTINUE=${CONTINUE:-0}
PRESERVE_CONTAINER=${PRESERVE_CONTAINER:-0}
PIGEN_DOCKER_OPTS=${PIGEN_DOCKER_OPTS:-""}

# Kernel source directory mapping for stage-kernel
KERNEL_SRC=${KERNEL_SRC:-""}
KERNEL_DEBS_DIR=${KERNEL_DEBS_DIR:-""}
KERNEL_CONFIG_FILE=${KERNEL_CONFIG_FILE:-""}
KERNEL_DEB_FILES=${KERNEL_DEB_FILES:-""}

if [ -z "${IMG_NAME}" ]; then
	echo "IMG_NAME not set in 'config'" 1>&2
	echo 1>&2
exit 1
fi

# Ensure the Git Hash is recorded before entering the docker container
GIT_HASH=${GIT_HASH:-"$(git rev-parse HEAD)"}

CONTAINER_EXISTS=$(${DOCKER} ps -a --filter name="${CONTAINER_NAME}" -q)
CONTAINER_RUNNING=$(${DOCKER} ps --filter name="${CONTAINER_NAME}" -q)
if [ "${CONTAINER_RUNNING}" != "" ]; then
	echo "The build is already running in container ${CONTAINER_NAME}. Aborting."
	exit 1
fi
if [ "${CONTAINER_EXISTS}" != "" ] && [ "${CONTINUE}" != "1" ]; then
	echo "Container ${CONTAINER_NAME} already exists and you did not specify CONTINUE=1. Aborting."
	echo "You can delete the existing container like this:"
	echo "  ${DOCKER} rm -v ${CONTAINER_NAME}"
	exit 1
fi

# Modify original build-options to allow config file to be mounted in the docker container
BUILD_OPTS="$(echo "${BUILD_OPTS:-}" | sed -E 's@\-c\s?([^ ]+)@-c /config@')"

DOCKER_BUILD_ARGS="--build-arg BASE_IMAGE=debian:trixie"
for proxy_var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY
do
  if [ -n "${!proxy_var:-}" ]; then
    DOCKER_BUILD_ARGS="${DOCKER_BUILD_ARGS} --build-arg ${proxy_var}=${!proxy_var}"
  fi
done

${DOCKER} build ${DOCKER_BUILD_ARGS} -t pi-gen "${DIR}"

if [ "${CONTAINER_EXISTS}" != "" ]; then
  DOCKER_CMDLINE_NAME="${CONTAINER_NAME}_cont"
  DOCKER_CMDLINE_PRE="--rm"
  DOCKER_CMDLINE_POST="--volumes-from=${CONTAINER_NAME}"
else
  DOCKER_CMDLINE_NAME="${CONTAINER_NAME}"
  DOCKER_CMDLINE_PRE=""
  DOCKER_CMDLINE_POST=""
fi

# Check if binfmt_misc is required
binfmt_misc_required=1
case $(uname -m) in
  aarch64)
    binfmt_misc_required=0
    ;;
  arm*)
    binfmt_misc_required=0
    ;;
esac

# Check if qemu-aarch64-static and /proc/sys/fs/binfmt_misc are present
if [[ "${binfmt_misc_required}" == "1" ]]; then
  if ! qemu_arm=$(which qemu-aarch64-static) ; then
    echo "qemu-aarch64-static not found (please install qemu-user-static)"
    exit 1
  fi
  if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
    echo "binfmt_misc required but not mounted, trying to mount it..."
    if ! mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc ; then
        echo "mounting binfmt_misc failed"
        exit 1
    fi
    echo "binfmt_misc mounted"
  fi
  if ! grep -q "^interpreter ${qemu_arm}" /proc/sys/fs/binfmt_misc/qemu-aarch64* ; then
    # Register qemu-aarch64 for binfmt_misc
    reg="echo ':qemu-aarch64-rpi:M::"\
"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:"\
"\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:"\
"${qemu_arm}:F' > /proc/sys/fs/binfmt_misc/register"
    echo "Registering qemu-aarch64 for binfmt_misc..."
    sudo bash -c "${reg}" 2>/dev/null || true
  fi
fi

# Prepare kernel source/debs volume mounts
KERNEL_VOLUME_OPTS=""
KERNEL_ENV_OPTS=""

if [ -n "${KERNEL_SRC}" ]; then
  if [ ! -d "${KERNEL_SRC}" ]; then
    echo "ERROR: KERNEL_SRC directory not found: ${KERNEL_SRC}" 1>&2
    exit 1
  fi
  # Get absolute path
  KERNEL_SRC=$(realpath -s "$KERNEL_SRC" || realpath "$KERNEL_SRC")
  KERNEL_VOLUME_OPTS="--volume ${KERNEL_SRC}:/kernel-src"
  KERNEL_ENV_OPTS="-e KERNEL_SRC=/kernel-src"
  echo "Kernel source will be mounted: ${KERNEL_SRC} -> /kernel-src"
fi

if [ -n "${KERNEL_DEBS_DIR}" ]; then
  if [ ! -d "${KERNEL_DEBS_DIR}" ]; then
    echo "ERROR: KERNEL_DEBS_DIR directory not found: ${KERNEL_DEBS_DIR}" 1>&2
    exit 1
  fi
  KERNEL_DEBS_DIR=$(realpath -s "$KERNEL_DEBS_DIR" || realpath "$KERNEL_DEBS_DIR")
  KERNEL_VOLUME_OPTS="${KERNEL_VOLUME_OPTS} --volume ${KERNEL_DEBS_DIR}:/kernel-debs:ro"
  KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_DEBS_DIR=/kernel-debs"
  echo "Kernel debs will be mounted: ${KERNEL_DEBS_DIR} -> /kernel-debs"
fi

if [ -n "${KERNEL_CONFIG_FILE}" ]; then
  if [ -f "${KERNEL_CONFIG_FILE}" ]; then
    KERNEL_CONFIG_FILE=$(realpath -s "$KERNEL_CONFIG_FILE" || realpath "$KERNEL_CONFIG_FILE")
    KERNEL_CONFIG_CONTAINER_PATH="/kernel-config-file/$(basename "${KERNEL_CONFIG_FILE}")"
    KERNEL_VOLUME_OPTS="${KERNEL_VOLUME_OPTS} --volume ${KERNEL_CONFIG_FILE}:${KERNEL_CONFIG_CONTAINER_PATH}:ro"
    KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_CONFIG_FILE=${KERNEL_CONFIG_CONTAINER_PATH}"
    echo "Kernel config file will be mounted: ${KERNEL_CONFIG_FILE} -> ${KERNEL_CONFIG_CONTAINER_PATH}"
  else
    KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_CONFIG_FILE=$(printf '%q' "${KERNEL_CONFIG_FILE}")"
  fi
fi

if [ -n "${KERNEL_DEB_FILES}" ]; then
  KERNEL_DEB_FILES_IN_CONTAINER=""
  deb_index=0
  for deb_file in ${KERNEL_DEB_FILES}; do
    if [ -f "${deb_file}" ]; then
      deb_file=$(realpath -s "$deb_file" || realpath "$deb_file")
      deb_index=$((deb_index + 1))
      deb_container_path="/kernel-deb-files/${deb_index}-$(basename "${deb_file}")"
      KERNEL_VOLUME_OPTS="${KERNEL_VOLUME_OPTS} --volume ${deb_file}:${deb_container_path}:ro"
      echo "Kernel deb file will be mounted: ${deb_file} -> ${deb_container_path}"
    else
      deb_container_path="${deb_file}"
    fi
    if [ -n "${KERNEL_DEB_FILES_IN_CONTAINER}" ]; then
      KERNEL_DEB_FILES_IN_CONTAINER="${KERNEL_DEB_FILES_IN_CONTAINER} "
    fi
    KERNEL_DEB_FILES_IN_CONTAINER="${KERNEL_DEB_FILES_IN_CONTAINER}${deb_container_path}"
  done
  KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_DEB_FILES=$(printf '%q' "${KERNEL_DEB_FILES_IN_CONTAINER}")"
fi

# Pass KERNEL_MODEL if set
if [ -n "${KERNEL_STAGE_MODE:-}" ]; then
  KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_STAGE_MODE=${KERNEL_STAGE_MODE}"
fi
if [ -n "${KERNEL_MODEL:-}" ]; then
  KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_MODEL=${KERNEL_MODEL}"
fi
if [ -n "${KERNEL_DEFCONFIG:-}" ]; then
  KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_DEFCONFIG=${KERNEL_DEFCONFIG}"
fi
if [ -n "${KERNEL_LLVM:-}" ]; then
  KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_LLVM=${KERNEL_LLVM}"
fi
if [ -n "${KERNEL_CONFIG_FRAGMENTS:-}" ]; then
  KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e KERNEL_CONFIG_FRAGMENTS=$(printf '%q' "${KERNEL_CONFIG_FRAGMENTS}")"
fi
for proxy_var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY
do
  if [ -n "${!proxy_var:-}" ]; then
    KERNEL_ENV_OPTS="${KERNEL_ENV_OPTS} -e ${proxy_var}=$(printf '%q' "${!proxy_var}")"
  fi
done

trap 'echo "got CTRL+C... please wait 5s" && ${DOCKER} stop -t 5 ${DOCKER_CMDLINE_NAME}' SIGINT SIGTERM
time ${DOCKER} run \
  $DOCKER_CMDLINE_PRE \
  --name "${DOCKER_CMDLINE_NAME}" \
  --privileged \
  ${PIGEN_DOCKER_OPTS} \
  --volume "${CONFIG_FILE}":/config:ro \
  ${KERNEL_VOLUME_OPTS} \
  -e "GIT_HASH=${GIT_HASH}" \
  ${KERNEL_ENV_OPTS} \
  $DOCKER_CMDLINE_POST \
  pi-gen \
  bash -e -o pipefail -c "
    dpkg-reconfigure qemu-user-static &&
    # binfmt_misc is sometimes not mounted with debian trixie image
    (mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc || true) &&
    cd /pi-gen; ./build.sh ${BUILD_OPTS} &&
    rsync -av work/*/build.log deploy/
  " &
  wait "$!"

# Ensure that deploy/ is always owned by calling user
echo "copying results from deploy/"
TMP_DEPLOY_DIR=$(mktemp -d)
cleanup_tmp_deploy() {
	rm -rf "${TMP_DEPLOY_DIR}"
}
trap cleanup_tmp_deploy EXIT

${DOCKER} cp "${CONTAINER_NAME}":/pi-gen/deploy/. "${TMP_DEPLOY_DIR}/"
HOST_DEPLOY_DIR="${DIR}/deploy"
mkdir -p "${HOST_DEPLOY_DIR}"
if [ ! -w "${HOST_DEPLOY_DIR}" ]; then
	HOST_DEPLOY_DIR="${DIR}/deploy-recovered-$(date +%Y%m%d-%H%M%S)"
	echo "deploy/ is not writable, copying results to ${HOST_DEPLOY_DIR}"
	mkdir -p "${HOST_DEPLOY_DIR}"
fi
# Sync through a temp directory so old root-owned logs do not block fresh results.
rsync -a "${TMP_DEPLOY_DIR}/" "${HOST_DEPLOY_DIR}/"

echo "copying log from container ${CONTAINER_NAME} to ${HOST_DEPLOY_DIR}/"
${DOCKER} logs --timestamps "${CONTAINER_NAME}" &>"${HOST_DEPLOY_DIR}/build-docker.log"

ls -lah "${HOST_DEPLOY_DIR}"

# cleanup
if [ "${PRESERVE_CONTAINER}" != "1" ]; then
	${DOCKER} rm -v "${CONTAINER_NAME}"
fi

echo "Done! Your image(s) should be in deploy/"
