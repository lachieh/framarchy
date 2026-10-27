#!/usr/bin/env bash
# Compare eMMC partitions on the running stock Android with the backup.
# Each partition is hashed on the frame (root ADB) and checked against the
# backup's .sha256 sidecar. Usage: scripts/verify-partitions.sh [name...]
# With no names, checks every partition that has a backup.
set -euo pipefail

ADB=${ADB:-/opt/homebrew/bin/adb}
SERIAL=${SERIAL:-HF4A62I77N}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BACKUP=$ROOT/backup/frame157

names=("$@")
if (( ${#names[@]} == 0 )); then
  for sidecar in "$BACKUP"/*.img.sha256; do
    name=$(basename "$sidecar" .img.sha256)
    [[ $name == mmcblk2* ]] || names+=("$name")
  done
fi

bad=0
for name in "${names[@]}"; do
  expected=$(cut -d' ' -f1 "$BACKUP/$name.img.sha256")
  actual=$("$ADB" -s "$SERIAL" shell "su -c 'sha256sum /dev/block/by-name/$name'" \
    | tr -d '\r' | cut -d' ' -f1)
  if [[ $actual == "$expected" ]]; then echo "ok       $name"
  else echo "DIFFERS  $name"; bad=1; fi
done
exit $bad
