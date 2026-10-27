#!/usr/bin/env bash
# Build a static AArch64 BusyBox initramfs without contacting a target device.
set -euo pipefail

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/initramfs"
LOGS="$ROOT/build/logs/first-boot"
CONTAINER=framarchy-initramfs-build
BUSYBOX_VERSION=1:1.37.0-6+b9
BUSYBOX_SHA256=c833be48abfa16bc19c4966ec93e289ff1ce5d2f1476cad3a57bd105378cd15c

mkdir -p "$OUT" "$LOGS"
find "$OUT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run --name "$CONTAINER" --platform linux/arm64 \
  -v "$ROOT":/repo \
  -e BUSYBOX_VERSION="$BUSYBOX_VERSION" -e BUSYBOX_SHA256="$BUSYBOX_SHA256" \
  debian:trixie-slim bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
export SOURCE_DATE_EPOCH=1764542530
apt-get update -qq
apt-get install -y -qq cpio file gzip >/dev/null
work=/tmp/frame157-initramfs
mkdir -p "$work/root" "$work/pkg"
chown _apt "$work"
cd "$work"
apt-get download "busybox-static=$BUSYBOX_VERSION" \
  2>&1 | tee /repo/build/logs/first-boot/busybox-build.log
deb=$(find . -maxdepth 1 -name "busybox-static_*_arm64.deb" -print -quit)
echo "$BUSYBOX_SHA256  $deb" | sha256sum -c -
dpkg-deb -x "$deb" "$work/pkg"
file "$work/pkg/usr/bin/busybox" | tee /repo/build/logs/first-boot/busybox-file.log
file "$work/pkg/usr/bin/busybox" | grep -q "statically linked"

root="$work/root"
mkdir -p "$root/bin"
cp "$work/pkg/usr/bin/busybox" "$root/bin/busybox"
"$root/bin/busybox" --install "$root/bin"
mkdir -p "$root/dev" "$root/proc" "$root/root" "$root/run" \
  "$root/sys/kernel/config" "$root/tmp"
cp /repo/initramfs/init "$root/init"
chmod 0755 "$root/init"
sh -n "$root/init"
touch -d "@${SOURCE_DATE_EPOCH}" "$root/init" "$root/bin/busybox"
find "$root" -print0 | xargs -0 touch -h -d "@${SOURCE_DATE_EPOCH}"
cd "$root"
find . -print0 | LC_ALL=C sort -z | cpio --null -o --format=newc \
  --owner=0:0 --reproducible 2>/dev/null | gzip -n -9 \
  > /repo/build/initramfs/initramfs.cpio.gz
cp /repo/initramfs/init /repo/build/initramfs/init
"$root/bin/busybox" --list | LC_ALL=C sort > /repo/build/initramfs/busybox-applets.txt
{
  echo "busybox_version=$BUSYBOX_VERSION"
  echo "busybox_package=busybox-static"
  echo "busybox_source_package=busybox_1.37.0-6"
  echo "busybox_url=http://deb.debian.org/debian/pool/main/b/busybox/busybox-static_1.37.0-6+b9_arm64.deb"
  echo "busybox_deb_sha256=$BUSYBOX_SHA256"
  echo "busybox_built_using=glibc_2.41-12+deb13u4"
  echo "container_image=debian:trixie-slim"
  echo "container_os=$(cat /etc/debian_version)"
  file "$root/bin/busybox"
} > /repo/build/initramfs/provenance.txt
sha256sum /repo/build/initramfs/initramfs.cpio.gz \
  /repo/build/initramfs/init /repo/build/initramfs/busybox-applets.txt \
  > /repo/build/initramfs/SHA256SUMS
'

docker rm "$CONTAINER" >/dev/null
docker image inspect --format 'docker_image_id={{.Id}}' debian:trixie-slim \
  >> "$OUT/provenance.txt"
echo "initramfs built in $OUT"
