#!/bin/bash -e

if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi

# Verify rootfs was properly copied
if [ ! -d "${ROOTFS_DIR}/proc" ] || [ ! -d "${ROOTFS_DIR}/sys" ]; then
	echo "ERROR: rootfs not properly initialized"
	echo "ROOTFS_DIR=${ROOTFS_DIR}"
	echo "PREV_ROOTFS_DIR=${PREV_ROOTFS_DIR}"
	ls -la "${ROOTFS_DIR}" || true
	exit 1
fi
