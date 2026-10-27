#!/usr/bin/env bash
# Audit only generated host artifacts; never inspect or write a physical device.
set -euo pipefail

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/frame157-first-boot"
KERNEL="$ROOT/build/kernel"
INITRAMFS="$ROOT/build/initramfs/initramfs.cpio.gz"
LOGS="$ROOT/build/logs/first-boot"
CONTAINER=framarchy-first-boot-audit

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run --name "$CONTAINER" --platform linux/arm64 -v "$ROOT":/repo \
  debian:trixie-slim bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq cpio device-tree-compiler file gzip mtools >/dev/null

out=/repo/build/frame157-first-boot
kernel=/repo/build/kernel
dtb="$kernel/rk3326-frame157.dtb"
image="$out/frame157-first-boot.img"
offset=1048576
work=$(mktemp -d)
trap "rm -rf \"$work\"" EXIT
audit="$out/audit"
rm -rf "$audit"
mkdir -p "$audit"

pass() { echo "PASS $*"; }
eq() {
  actual=$(fdtget "$dtb" "$1" "$2")
  [[ $actual == "$3" ]] || {
    echo "FAIL $1:$2 expected [$3], got [$actual]" >&2
    exit 1
  }
}
exists() { fdtget "$dtb" "$1" "$2" >/dev/null 2>&1; }
phandle() { fdtget "$dtb" "$1" phandle; }
supply_eq() {
  actual=$(fdtget "$dtb" "$1" "$2")
  expected=$(phandle "$3")
  [[ $actual == "$expected" ]] || {
    echo "FAIL $1:$2 does not reference $3" >&2
    exit 1
  }
}

eq / model "FRAME157 first-boot board"
eq / compatible "rockchip,rk3326-evb-ai-va-v11 rockchip,rk3326"
pmic=/i2c@ff180000/pmic@20
eq "$pmic" compatible rockchip,rk809
eq "$pmic" reg 32
eq /i2c@ff180000 clock-frequency 400000
eq /i2c@ff180000 i2c-scl-rising-time-ns 280
eq /i2c@ff180000 i2c-scl-falling-time-ns 16
irq=$(fdtget "$dtb" "$pmic" interrupts)
[[ $irq == "10 8" ]] || { echo "FAIL PMIC interrupt: $irq" >&2; exit 1; }
! exists "$pmic" wakeup-source
! exists "$pmic" system-power-controller
! exists "$pmic" rockchip,system-power-controller

regroot="$pmic/regulators"
check_regulator() {
  node="$regroot/$1"
  eq "$node" regulator-name "$2"
  if [[ $3 != none ]]; then
    eq "$node" regulator-min-microvolt "$3"
    eq "$node" regulator-max-microvolt "$4"
  else
    ! exists "$node" regulator-min-microvolt
    ! exists "$node" regulator-max-microvolt
  fi
  if [[ $5 == *always* ]]; then
    exists "$node" regulator-always-on
  else
    ! exists "$node" regulator-always-on
  fi
  if [[ $5 == *boot* ]]; then
    exists "$node" regulator-boot-on
  else
    ! exists "$node" regulator-boot-on
  fi
}
check_regulator DCDC_REG1 vdd_logic 850000 1350000 always,boot
eq "$regroot/DCDC_REG1" regulator-ramp-delay 6001
check_regulator DCDC_REG2 vdd_arm 850000 1350000 always,boot
eq "$regroot/DCDC_REG2" regulator-ramp-delay 6001
check_regulator DCDC_REG3 vcc_ddr none none always,boot
check_regulator DCDC_REG4 vcc_3v0 3000000 3000000 always,boot
check_regulator DCDC_REG5 vcc3v3_sys 3300000 3300000 always,boot
check_regulator LDO_REG1 vcc_1v0 1000000 1000000 always,boot
check_regulator LDO_REG2 vcc1v8_soc 1800000 1800000 always,boot
check_regulator LDO_REG3 vcc1v0_soc 1000000 1000000 always,boot
check_regulator LDO_REG4 vcc3v0_pmu 3000000 3000000 always,boot
check_regulator LDO_REG5 vccio_sd 1800000 3300000 always,boot
check_regulator LDO_REG6 vcc_sd 3300000 3300000 always,boot
check_regulator LDO_REG7 vcc2v8_dvp 2800000 2800000 always,boot
check_regulator LDO_REG8 vcc1v8_dvp 1800000 1800000 always,boot
check_regulator LDO_REG9 lcd_vio 1850000 1850000 always,boot
check_regulator SWITCH_REG1 vcc5v0_host none none none
check_regulator SWITCH_REG2 vcc3v3_lcd none none boot
! grep -q "regulator-state-mem" <(dtc -q -I dtb -O dts "$dtb")
! grep -q "regulator-initial-mode" <(dtc -q -I dtb -O dts "$dtb")

v5=/regulator-vcc5v0-sys
v33="$regroot/DCDC_REG5"
for input in vcc1-supply vcc2-supply vcc3-supply vcc4-supply vcc9-supply; do
  supply_eq "$pmic" "$input" "$v5"
done
for input in vcc5-supply vcc6-supply vcc7-supply vcc8-supply; do
  supply_eq "$pmic" "$input" "$v33"
done

pmu=/syscon@ff010000/io-domains
io=/syscon@ff140000/io-domains
eq "$pmu" status okay
supply_eq "$pmu" pmuio1-supply "$regroot/LDO_REG4"
supply_eq "$pmu" pmuio2-supply "$regroot/LDO_REG4"
eq "$io" status okay
supply_eq "$io" vccio1-supply "$regroot/DCDC_REG4"
supply_eq "$io" vccio2-supply "$regroot/LDO_REG5"
supply_eq "$io" vccio3-supply "$regroot/LDO_REG8"
supply_eq "$io" vccio4-supply "$regroot/DCDC_REG4"
supply_eq "$io" vccio5-supply "$regroot/DCDC_REG4"
! exists "$io" vccio6-supply

sd=/mmc@ff370000
eq "$sd" status okay
eq "$sd" max-frequency 25000000
exists "$sd" no-sdio
supply_eq "$sd" vmmc-supply "$regroot/LDO_REG6"
supply_eq "$sd" vqmmc-supply "$regroot/LDO_REG5"
eq /mmc@ff380000 status disabled
eq /mmc@ff390000 status disabled
eq /usb@ff300000 status okay
eq /usb@ff300000 dr_mode peripheral
eq /syscon@ff2c0000/usb2phy@100 status okay
eq /syscon@ff2c0000/usb2phy@100/otg-port status okay
eq /syscon@ff2c0000/usb2phy@100/host-port status disabled
eq /usb@ff340000 status disabled
eq /usb@ff350000 status disabled
eq /serial@ff160000 status disabled
eq /display-subsystem status disabled
eq /dsi@ff450000 status disabled
eq /vop@ff460000 status disabled
! dtc -q -I dtb -O dts "$dtb" | grep -q "lontium,lt8911exb"
pass "compiled DT identity, PMIC inputs/rails, I/O domains, SD, USB, and disabled eMMC/SDIO/display"

dtc -q -I dtb -O dts "$dtb" > "$audit/compiled.dts"
{
  for node in /mmc@ff370000 /mmc@ff380000 /mmc@ff390000 \
    /usb@ff300000 /syscon@ff2c0000/usb2phy@100/otg-port \
    /syscon@ff2c0000/usb2phy@100/host-port /usb@ff340000 /usb@ff350000 \
    /serial@ff160000 /display-subsystem /dsi@ff450000 /vop@ff460000; do
    printf "%s status=%s\n" "$node" "$(fdtget "$dtb" "$node" status)"
  done
  printf "/mmc@ff370000 max-frequency=%s dr_mode=n/a\n" \
    "$(fdtget "$dtb" /mmc@ff370000 max-frequency)"
  printf "/usb@ff300000 dr_mode=%s\n" \
    "$(fdtget "$dtb" /usb@ff300000 dr_mode)"
} > "$audit/dt-statuses.txt"
{
  printf "PMIC input phandles:\n"
  for input in vcc1-supply vcc2-supply vcc3-supply vcc4-supply vcc5-supply \
    vcc6-supply vcc7-supply vcc8-supply vcc9-supply; do
    printf "%s=%s\n" "$input" "$(fdtget "$dtb" "$pmic" "$input")"
  done
  printf "\nRegulators:\n"
  for regulator in $(fdtget -l "$dtb" "$regroot"); do
    node="$regroot/$regulator"
    printf "%s name=%s min=%s max=%s always=%s boot=%s\n" \
      "$regulator" "$(fdtget "$dtb" "$node" regulator-name)" \
      "$(fdtget -d none "$dtb" "$node" regulator-min-microvolt 2>/dev/null)" \
      "$(fdtget -d none "$dtb" "$node" regulator-max-microvolt 2>/dev/null)" \
      "$(exists "$node" regulator-always-on && echo yes || echo no)" \
      "$(exists "$node" regulator-boot-on && echo yes || echo no)"
  done
  printf "\nI/O domain supply phandles:\n"
  for property in pmuio1-supply pmuio2-supply; do
    printf "%s=%s\n" "$property" "$(fdtget "$dtb" "$pmu" "$property")"
  done
  for property in vccio1-supply vccio2-supply vccio3-supply vccio4-supply vccio5-supply; do
    printf "%s=%s\n" "$property" "$(fdtget "$dtb" "$io" "$property")"
  done
} > "$audit/rails.txt"

required="ARCH_ROCKCHIP BLK_DEV_INITRD DEVTMPFS DEVTMPFS_MOUNT TMPFS CONFIGFS_FS MFD_RK8XX_I2C REGULATOR_RK808 MMC_DW_ROCKCHIP USB_DWC2 USB_DWC2_PERIPHERAL USB_GADGET USB_LIBCOMPOSITE USB_CONFIGFS USB_CONFIGFS_ACM"
for symbol in $required; do
  grep -qx "CONFIG_${symbol}=y" "$kernel/.config"
done
grep -qx "# CONFIG_USB_CONFIGFS_NCM is not set" "$kernel/.config"
grep -qx "# CONFIG_USB_G_SERIAL is not set" "$kernel/.config"
grep -E "^CONFIG_($(echo "$required" | tr " " "|"))=y$|^# CONFIG_USB_(CONFIGFS_NCM|G_SERIAL) is not set$" \
  "$kernel/.config" > "$audit/kernel-critical.config"
pass "boot-critical kernel configuration is built in; NCM and g_serial are absent"

mkdir "$work/archive"
gzip -dc /repo/build/initramfs/initramfs.cpio.gz | \
  (cd "$work/archive" && cpio -id --quiet --no-absolute-filenames)
(cd "$work/archive" && find . -print | LC_ALL=C sort) > "$audit/initramfs-files.txt"
test -x "$work/archive/init"
sh -n "$work/archive/init"
grep -q "FRAME157_FIRSTBOOT_OK" "$work/archive/init"
grep -q "exec setsid cttyhack sh -i" "$work/archive/init"
! grep -Eq "(/dev/mmc|mkfs|fdisk|flashcp|reboot|poweroff|halt|mount[[:space:]].*(ext|vfat|/dev/))" "$work/archive/init"
file "$work/archive/bin/busybox" | grep -q "statically linked"
pass "static BusyBox archive, automatic init safety, marker, and controlling-terminal shell"

mkdir -p "$work/image/dtbs" "$work/image/extlinux"
for path in Image initramfs.cpio.gz MANIFEST.sha256; do
  mcopy -i "$image@@$offset" "::/$path" "$work/image/$path"
done
mcopy -i "$image@@$offset" ::/dtbs/rockchip-rk3326-frame157.dtb "$work/image/dtbs/"
mcopy -i "$image@@$offset" ::/extlinux/extlinux.conf "$work/image/extlinux/"
(cd "$work/image" && sha256sum -c MANIFEST.sha256)
cmp "$work/image/Image" "$kernel/Image"
cmp "$work/image/initramfs.cpio.gz" /repo/build/initramfs/initramfs.cpio.gz
cmp "$work/image/dtbs/rockchip-rk3326-frame157.dtb" "$dtb"
cmp "$work/image/extlinux/extlinux.conf" /repo/first-boot/extlinux.conf
grep -qx "  LINUX /Image" "$work/image/extlinux/extlinux.conf"
grep -qx "  INITRD /initramfs.cpio.gz" "$work/image/extlinux/extlinux.conf"
grep -qx "  FDT /dtbs/rockchip-rk3326-frame157.dtb" "$work/image/extlinux/extlinux.conf"
grep -qx "  APPEND rdinit=/init loglevel=7 panic=-1" "$work/image/extlinux/extlinux.conf"
! grep -Eq "root=|rootwait|resume=" "$work/image/extlinux/extlinux.conf"
[[ $(od -An -tx1 -N4 -j32768 "$image" | tr -d " \n") == 00000000 ]]
pass "partitioned FAT image paths, manifest, payload identity, extlinux contract, and empty LBA64 header"

(cd "$kernel" && sha256sum -c SHA256SUMS)
(cd /repo/build/initramfs && sha256sum -c SHA256SUMS)
(cd "$out" && sha256sum -c IMAGE.sha256)
[[ ! -s /repo/build/logs/first-boot/dt-binding-check.log ]]
! grep -Eqi "warning:|error:" /repo/build/logs/first-boot/dtbs-check.log
cp "$out/image-files.txt" "$out/partition-table.txt" "$out/boot/MANIFEST.sha256" \
  "$audit/"
sha256sum "$kernel/Image" "$dtb" /repo/build/initramfs/initramfs.cpio.gz \
  "$image" > "$audit/artifact-sha256.txt"
pass "artifact hashes and warning-free targeted schema validation"
'
docker rm "$CONTAINER" >/dev/null
