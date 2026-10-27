#!/usr/bin/env bash
# Build mainline U-Boot proper (evb-px30 + uboot/chainload.config) as an
# arm64 Linux Image, then wrap it in a recovery-partition boot image together
# with the stock DTB, which stock U-Boot accepts.
# Output: build/uboot-chainload/u-boot.bin
#         build/frame157-recovery/frame157-chainload.img
set -euo pipefail

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/uboot-chainload
LOGS=$ROOT/build/logs/uboot-chainload
UBOOT_TAG=v2025.10
CONTAINER=framarchy-uboot-build

mkdir -p "$OUT" "$LOGS"
docker volume create frame157-uboot >/dev/null
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run --name "$CONTAINER" --platform linux/arm64 \
  -v frame157-uboot:/src -v "$ROOT":/repo -e UBOOT_TAG="$UBOOT_TAG" \
  debian:trixie-slim bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
export SOURCE_DATE_EPOCH=1764542530
apt-get update -qq
apt-get install -y -qq git build-essential bc bison flex libssl-dev libgnutls28-dev \
  python3 python3-dev python3-setuptools python3-pyelftools swig \
  device-tree-compiler uuid-dev >/dev/null
if [[ ! -d /src/u-boot/.git ]]; then
  git clone -q --depth 1 --branch "$UBOOT_TAG" \
    https://source.denx.de/u-boot/u-boot.git /src/u-boot
fi
cd /src/u-boot
git reset -q --hard "$UBOOT_TAG"
git clean -qffdx
# LINUX_KERNEL_IMAGE_HEADER has no prompt (platforms select it); give it one
# so the config fragment can enable it for this chain-loaded build.
sed -i "/^config LINUX_KERNEL_IMAGE_HEADER$/,/^\tbool$/ s/^\tbool$/\tbool \"Linux kernel image header\"/" arch/arm/Kconfig
grep -q "bool \"Linux kernel image header\"" arch/arm/Kconfig
make -s evb-px30_defconfig
scripts/kconfig/merge_config.sh -m .config /repo/uboot/chainload.config
make -s olddefconfig
for want in LINUX_KERNEL_IMAGE_HEADER=y POSITION_INDEPENDENT=y ENV_IS_NOWHERE=y \
    USB_FUNCTION_FASTBOOT=y FASTBOOT_OEM_RUN=y FASTBOOT_CMD_OEM_CONSOLE=y \
    USB_GADGET_PRODUCT_NUM=0x0157 CMD_SYSBOOT=y; do
  grep -qx "CONFIG_$want" .config || { echo "missing CONFIG_$want" >&2; exit 1; }
done
# The regulator framework (DM_REGULATOR) is required by the platform; what
# must be absent are the drivers that could change a rail.
for unwanted in DM_PMIC PMIC_RK8XX REGULATOR_RK8XX REGULATOR_PWM \
    DM_REGULATOR_FIXED DM_REGULATOR_GPIO ENV_IS_IN_MMC VIDEO NET USB_EHCI_HCD FASTBOOT_FLASH; do
  grep -qx "CONFIG_$unwanted=y" .config && { echo "unwanted CONFIG_$unwanted" >&2; exit 1; }
done
make -j"$(nproc)" u-boot.bin 2>&1 | tail -20
cp u-boot.bin .config /repo/build/uboot-chainload/
' 2>&1 | tee "$LOGS/build.log"
docker rm "$CONTAINER" >/dev/null

# The header's image_size ends at _end, but with POSITION_INDEPENDENT the
# relocation table extends past it in the file. Stock U-Boot moves a kernel
# by copying image_size bytes, which would cut that table off, so raise
# image_size to cover the whole file (page-aligned).
python3 -I - "$OUT/u-boot.bin" <<'EOF'
import struct, sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
assert d[56:60] == b'ARMd', 'u-boot.bin has no arm64 Image header'
text_offset, image_size = struct.unpack_from('<QQ', d, 8)
need = (max(image_size, len(d)) + 4095) // 4096 * 4096
struct.pack_into('<Q', d, 16, need)
open(p, 'wb').write(d)
print(f'u-boot.bin {len(d)} bytes, text_offset {text_offset:#x}, '
      f'image_size {image_size} -> {need}')
EOF

# Stock DTB for stock U-Boot; mainline U-Boot ignores it and uses its own.
python3 -I - "$ROOT/backup/frame157/boot.img" "$OUT/stock.dtb" <<'EOF'
import struct, sys
x = open(sys.argv[1], 'rb').read()
ks, ka, rs, ra, ss = struct.unpack_from('<5I', x, 8)
up = lambda n: (n + 2047) // 2048 * 2048
s = x[2048 + up(ks) + up(rs):][:ss]
e = s[512:1024]
assert e[4:17] == b'rk-kernel.dtb'
blk, size = struct.unpack_from('<II', e, 260)
open(sys.argv[2], 'wb').write(s[blk * 512:blk * 512 + size])
EOF

KERNEL="$OUT/u-boot.bin" DTB="$OUT/stock.dtb" NAME=frame157-chainload \
  "$ROOT/scripts/build-boot-img.sh"
