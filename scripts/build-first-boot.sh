#!/usr/bin/env bash
# Assemble a deterministic, host-only partitioned FAT first-boot image.
set -euo pipefail

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/build/kernel"
INITRAMFS="$ROOT/build/initramfs/initramfs.cpio.gz"
OUT="$ROOT/build/frame157-first-boot"
LOGS="$ROOT/build/logs/first-boot"
CONTAINER=framarchy-artifact-build

for input in "$KERNEL/Image" "$KERNEL/rk3326-frame157.dtb" "$INITRAMFS"; do
  [[ -f $input ]] || { echo "missing input: $input" >&2; exit 1; }
done
mkdir -p "$OUT" "$LOGS"
find "$OUT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
mkdir -p "$OUT/boot/dtbs" "$OUT/boot/extlinux"
cp "$KERNEL/Image" "$OUT/boot/Image"
cp "$KERNEL/rk3326-frame157.dtb" "$OUT/boot/dtbs/rockchip-rk3326-frame157.dtb"
cp "$INITRAMFS" "$OUT/boot/initramfs.cpio.gz"
cp "$ROOT/first-boot/extlinux.conf" "$OUT/boot/extlinux/extlinux.conf"

(
  cd "$OUT/boot"
  shasum -a 256 Image initramfs.cpio.gz \
    dtbs/rockchip-rk3326-frame157.dtb extlinux/extlinux.conf \
    > MANIFEST.sha256
)

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run --name "$CONTAINER" --platform linux/arm64 -v "$ROOT":/repo \
  debian:trixie-slim bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
export SOURCE_DATE_EPOCH=1764542530
apt-get update -qq
apt-get install -y -qq dosfstools faketime fdisk mtools >/dev/null
out=/repo/build/frame157-first-boot
image="$out/frame157-first-boot.img"
find "$out/boot" -print0 | xargs -0 touch -h -d "@${SOURCE_DATE_EPOCH}"
truncate -s 96M "$image"
printf "%s\n" \
  "label: dos" \
  "label-id: 0x15715700" \
  "unit: sectors" \
  "" \
  "start=2048, size=194560, type=c, bootable" | sfdisk "$image" \
  > /repo/build/logs/first-boot/sfdisk-build.log
mkfs.fat --invariant -F 32 -n FRAME157 -i 15715700 --offset 2048 "$image" 97280 \
  > /repo/build/logs/first-boot/mkfs-build.log
offset=1048576
export TZ=UTC
fixed="2025-11-30 22:42:10"
faketime -f "$fixed" mmd -i "$image@@$offset" ::/dtbs ::/extlinux
faketime -f "$fixed" mcopy -m -i "$image@@$offset" "$out/boot/Image" ::/Image
faketime -f "$fixed" mcopy -m -i "$image@@$offset" "$out/boot/initramfs.cpio.gz" ::/initramfs.cpio.gz
faketime -f "$fixed" mcopy -m -i "$image@@$offset" "$out/boot/dtbs/rockchip-rk3326-frame157.dtb" ::/dtbs/
faketime -f "$fixed" mcopy -m -i "$image@@$offset" "$out/boot/extlinux/extlinux.conf" ::/extlinux/
faketime -f "$fixed" mcopy -m -i "$image@@$offset" "$out/boot/MANIFEST.sha256" ::/MANIFEST.sha256
sfdisk --dump "$image" > "$out/partition-table.txt"
mdir -/ -i "$image@@$offset" :: > "$out/image-files.txt"
sha256sum "$image" > "$out/IMAGE.sha256"
'
docker rm "$CONTAINER" >/dev/null

"$ROOT/scripts/audit-first-boot.sh" | tee "$LOGS/offline-audit.log"
echo "first-boot artifact built in $OUT"
