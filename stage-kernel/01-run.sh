#!/bin/bash -e

install -d "${ROOTFS_DIR}/opt/kernel-debs"
cp -a "${STAGE_DIR}/files/"*.deb "${ROOTFS_DIR}/opt/kernel-debs/"

on_chroot << 'EOF'
set -euo pipefail

cd /opt/kernel-debs

set +e
dpkg -i ./linux-image-*.deb
dpkg -i ./linux-headers-*.deb
dpkg -i ./linux-libc-dev-*.deb 2>/dev/null || true
set -e

apt-get update || true
apt-get -f install -y || true

mkdir -p /boot/firmware

uname -r || true
ls -l /lib/modules || true
EOF

if compgen -G "${STAGE_DIR}/files/*.sha256" >/dev/null; then
  cp -a "${STAGE_DIR}/files/"*.sha256 "${ROOTFS_DIR}/opt/kernel-debs/"
fi
