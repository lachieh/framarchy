#!/usr/bin/env bash
# Build the pinned FRAME157 kernel from the case-sensitive Docker volume.
set -euo pipefail

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/kernel"
LOGS="$ROOT/build/logs/first-boot"
KERNEL_COMMIT=7d0a66e4bb9081d75c82ec4957c50034cb0ea449
CONTAINER=framarchy-kernel-build

mkdir -p "$OUT" "$LOGS"
find "$OUT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
docker volume create frame157-linux >/dev/null
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run --name "$CONTAINER" --platform linux/arm64 \
  -v frame157-linux:/src -v "$ROOT":/repo \
  -e KERNEL_COMMIT="$KERNEL_COMMIT" \
  debian:trixie-slim bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
export KBUILD_BUILD_USER=framarchy
export KBUILD_BUILD_HOST=builder
export KBUILD_BUILD_TIMESTAMP=@1764542530
export LOCALVERSION=
apt-get update -qq
apt-get install -y -qq git build-essential bc bison flex libssl-dev libelf-dev \
  python3 python3-dev python3-venv swig device-tree-compiler >/dev/null
python3 -m venv /tmp/dtschema
/tmp/dtschema/bin/pip install -q dtschema yamllint
export PATH=/tmp/dtschema/bin:$PATH

if [[ ! -d /src/linux/.git ]]; then
  git clone -q --filter=blob:none --no-checkout \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git /src/linux
fi
cd /src/linux
if ! git cat-file -e "$KERNEL_COMMIT^{commit}" 2>/dev/null; then
  git fetch -q --depth 1 origin tag v6.18
fi
git reset -q --hard "$KERNEL_COMMIT"
git clean -qffdx
[[ $(git rev-parse HEAD) == "$KERNEL_COMMIT" ]]
[[ $(git describe --tags --exact-match HEAD) == v6.18 ]]

for patch in /repo/kernel/dts/*.patch /repo/kernel/patches/*.patch; do
  [[ -e $patch ]] && git apply "$patch"
done
cp /repo/kernel/dts/rk3326-frame157.dts arch/arm64/boot/dts/rockchip/
printf "\ndtb-\$(CONFIG_ARCH_ROCKCHIP) += rk3326-frame157.dtb\n" \
  >> arch/arm64/boot/dts/rockchip/Makefile

make -s mrproper
make -s defconfig
scripts/kconfig/merge_config.sh -m .config /repo/kernel/frame157.config
scripts/config --set-str LOCALVERSION -frame157 --disable LOCALVERSION_AUTO
make -s olddefconfig

required="ARCH_ROCKCHIP BLK_DEV_INITRD DEVTMPFS DEVTMPFS_MOUNT TMPFS CONFIGFS_FS MFD_RK8XX_I2C REGULATOR_RK808 MMC_DW_ROCKCHIP USB_DWC2 USB_DWC2_PERIPHERAL USB_GADGET USB_LIBCOMPOSITE USB_CONFIGFS USB_CONFIGFS_ACM PSTORE PSTORE_RAM PSTORE_CONSOLE PSTORE_PMSG USB_CONFIGFS_NCM ROCKCHIP_VOP ROCKCHIP_DW_MIPI_DSI"
for symbol in $required; do
  grep -qx "CONFIG_${symbol}=y" .config || {
    echo "required built-in missing: CONFIG_${symbol}" >&2
    exit 1
  }
done
grep -qx "# CONFIG_USB_G_SERIAL is not set" .config

make -j"$(nproc)" Image modules rockchip/rk3326-frame157.dtb
for module in DRM_LONTIUM_LT8911EXB DRM_PANFROST TOUCHSCREEN_SILEAD DRM_ROCKCHIP; do
  grep -qx "CONFIG_${module}=m" .config || {
    echo "required module missing: CONFIG_${module}" >&2
    exit 1
  }
done
make -s dt_binding_check \
  DT_SCHEMA_FILES=Documentation/devicetree/bindings/arm/rockchip.yaml \
  2>&1 | tee /repo/build/logs/first-boot/dt-binding-check.log
rm arch/arm64/boot/dts/rockchip/rk3326-frame157.dtb
make -j1 CHECK_DTBS=y rockchip/rk3326-frame157.dtb \
  2>&1 | tee /repo/build/logs/first-boot/dtbs-check.log

out=/repo/build/kernel
cp arch/arm64/boot/Image "$out/Image"
rm -rf /tmp/modules /tmp/rk915
make -s modules_install INSTALL_MOD_PATH=/tmp/modules INSTALL_MOD_STRIP=1
# Out-of-tree RK915 Wi-Fi driver (build/src/rk915, pinned in the README),
# built in /tmp because the repository sits on a case-insensitive volume.
cp -a /repo/build/src/rk915 /tmp/rk915
make -s M=/tmp/rk915 modules
make -s M=/tmp/rk915 modules_install INSTALL_MOD_PATH=/tmp/modules INSTALL_MOD_STRIP=1
tar -C /tmp/modules -czf "$out/modules.tar.gz" --owner=0 --group=0 \
  --mtime=@1764542530 --sort=name lib
cp arch/arm64/boot/dts/rockchip/rk3326-frame157.dtb "$out/"
cp .config "$out/.config"
make -s kernelrelease > "$out/release"
{
  echo "kernel_tag=v6.18"
  echo "kernel_commit=$(git rev-parse HEAD)"
  echo "kernel_source_commit_time=$(git show -s --format=%ct HEAD)"
  echo "kernel_release=$(cat "$out/release")"
  echo "container_image=debian:trixie-slim"
  echo "container_os=$(cat /etc/debian_version)"
  echo "compiler=$(gcc --version | head -n1)"
  echo "dtc=$(dtc --version)"
  echo "dtschema=$(pip show dtschema | sed -n "s/^Version: //p")"
} > "$out/provenance.txt"
{
  sha256sum /repo/kernel/frame157.config /repo/kernel/dts/rk3326-frame157.dts
  for patch in /repo/kernel/dts/*.patch; do
    [[ -e $patch ]] && sha256sum "$patch"
  done
} > "$out/input-sha256.txt"
sha256sum "$out/Image" "$out/rk3326-frame157.dtb" "$out/.config" "$out/modules.tar.gz" \
  > "$out/SHA256SUMS"
'

docker rm "$CONTAINER" >/dev/null
docker image inspect --format 'docker_image_id={{.Id}}' debian:trixie-slim \
  >> "$OUT/provenance.txt"
echo "kernel $(cat "$OUT/release") built in $OUT"
