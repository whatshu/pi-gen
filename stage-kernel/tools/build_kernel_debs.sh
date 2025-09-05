#!/usr/bin/env bash
set -euo pipefail

SRC=""
OUT=""
MODEL="pi4"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--src) SRC="$2"; shift 2;;
    -o|--out) OUT="$2"; shift 2;;
    -m|--model) MODEL="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

[[ -d "$SRC" ]] || { echo "ERROR: --src not found: $SRC"; exit 1; }
mkdir -p "$OUT"

case "$MODEL" in
  pi1|zero)
    ARCH="arm"
    CROSS_COMPILE="arm-linux-gnueabihf-"
    ;;
  pi2|pi3)
    ARCH="arm"
    CROSS_COMPILE="arm-linux-gnueabihf-"
    ;;
  pi4|pi400|cm4)
    ARCH="arm64"
    CROSS_COMPILE="aarch64-linux-gnu-"
    ;;
  pi5|cm5)
    ARCH="arm64"
    CROSS_COMPILE="aarch64-linux-gnu-"
    ;;
  *)
    echo "ERROR: Unknown model: $MODEL"
    echo "Supported: pi1, zero, pi2, pi3, pi4, pi400, cm4, pi5, cm5"
    exit 1
    ;;
esac

JOBS="$(nproc)"

pushd "$SRC" >/dev/null

export ARCH="$ARCH"
export CROSS_COMPILE="$CROSS_COMPILE"

make -j"$JOBS" bindeb-pkg

popd >/dev/null

PARENT_DIR="$(dirname "$(readlink -f "$SRC")")"
mapfile -t DEBS < <(find "$PARENT_DIR" -maxdepth 1 -type f -name '*.deb' -printf '%f\n' | sort)
if [[ "${#DEBS[@]}" -eq 0 ]]; then
  echo "ERROR: No debs produced."
  exit 1
fi

for f in "${DEBS[@]}"; do
  cp -a "$PARENT_DIR/$f" "$OUT/"
done

pushd "$OUT" >/dev/null
sha256sum *.deb > kernel-debs.sha256
popd >/dev/null 2>&1 || true

echo "Done. Debs ready in: $OUT"
