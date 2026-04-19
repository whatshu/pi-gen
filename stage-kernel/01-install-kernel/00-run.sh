#!/bin/bash -e

DEBS_DIR="${STAGE_WORK_DIR}/kernel-debs"
METADATA_FILE="${STAGE_WORK_DIR}/kernel-release.env"
SYSCTL_FILE="${ROOTFS_DIR}/etc/sysctl.d/99-stage-kernel-network-tuning.conf"

install -d "${ROOTFS_DIR}/opt/kernel-debs"
install -d "${ROOTFS_DIR}/usr/share/stage-kernel" "${ROOTFS_DIR}/etc/sysctl.d"

# Copy only the latest version of each package
for pkg_pattern in "linux-image-*_arm64.deb" "linux-headers-*_arm64.deb" "linux-libc-dev_*_arm64.deb"; do
  latest=$(ls -t "${DEBS_DIR}/"${pkg_pattern} 2>/dev/null | head -1)
  if [ -n "$latest" ]; then
    cp -a "$latest" "${ROOTFS_DIR}/opt/kernel-debs/"
  fi
done

if compgen -G "${DEBS_DIR}/*.sha256" >/dev/null; then
  cp -a "${DEBS_DIR}/"*.sha256 "${ROOTFS_DIR}/opt/kernel-debs/"
fi

if [ -f "${METADATA_FILE}" ]; then
  install -m 0644 "${METADATA_FILE}" "${ROOTFS_DIR}/usr/share/stage-kernel/kernel-release.env"
fi

cat > "${SYSCTL_FILE}" <<'EOF'
# Prefer fq + BBR in images that opt into the custom kernel stage.
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

on_chroot << 'EOF'
set -e
cd /opt/kernel-debs

# Install kernel image
if ls ./linux-image-*.deb 1>/dev/null 2>&1; then
  # Keep the stock Raspberry Pi kernel packages installed as a rollback option.
  dpkg -i ./linux-image-*.deb || {
      apt-get update
      apt-get -f install -y
      dpkg -i ./linux-image-*.deb
  }
fi

# Install headers (optional)
if ls ./linux-headers-*.deb 1>/dev/null 2>&1; then
  dpkg -i ./linux-headers-*.deb 2>/dev/null || apt-get -f install -y || true
fi

# Install libc-dev (optional)
if ls ./linux-libc-dev_*.deb 1>/dev/null 2>&1; then
  dpkg -i ./linux-libc-dev_*.deb 2>/dev/null || true
fi

mkdir -p /boot/firmware
EOF
