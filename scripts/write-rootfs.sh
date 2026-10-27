#!/usr/bin/env bash
# Write build/rootfs/frame157-rootfs.ext4 to the SD card's partition 2 from
# stock Android (root ADB), compressed in transit, and verify it by hash.
set -euo pipefail

ADB=${ADB:-/opt/homebrew/bin/adb}
SERIAL=${SERIAL:-HF4A62I77N}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG=$ROOT/build/rootfs/frame157-rootfs.ext4
DEV=/dev/block/mmcblk0p2
TMP=/data/local/tmp/rootfs.ext4.gz

fsh() { "$ADB" -s "$SERIAL" shell "su -c '$1'" | tr -d '\r'; }

bytes=$(stat -f %z "$IMG")
(( bytes % 1048576 == 0 )) || { echo "STOP: image size not MiB-aligned" >&2; exit 1; }
capacity=$(fsh "blockdev --getsize64 $DEV")
(( bytes <= capacity )) || { echo "STOP: image $bytes > $DEV $capacity" >&2; exit 1; }
want=$(cut -d' ' -f1 "$ROOT/build/rootfs/SHA256SUMS")

gzip -1 -c "$IMG" > "$IMG.gz"
"$ADB" -s "$SERIAL" push "$IMG.gz" "$TMP"
[[ $(fsh "sha256sum $TMP" | cut -d' ' -f1) == $(shasum -a 256 "$IMG.gz" | cut -d' ' -f1) ]] \
  || { echo "STOP: pushed copy differs" >&2; exit 1; }
fsh "gunzip -c $TMP | dd of=$DEV bs=1048576 2>&1 | tail -1; sync; blockdev --flushbufs $DEV"
fsh "rm $TMP"
got=$(fsh "dd if=$DEV bs=1048576 count=$((bytes / 1048576)) 2>/dev/null | sha256sum" | cut -d' ' -f1)
[[ $got == "$want" ]] || { echo "STOP: $DEV differs from the image" >&2; exit 1; }
echo "verified $DEV"
