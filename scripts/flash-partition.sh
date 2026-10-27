#!/usr/bin/env bash
# Write one file into one eMMC partition over Rockchip Loader mode, safely.
# rkdeveloptool's own "wlx" writes the whole file from the partition start
# without checking its size, so an oversized file silently overwrites the next
# partition. This script reads the GPT from the frame, refuses files larger
# than the partition, then writes. Loader-mode reads past 32 MiB return 0xCC
# filler on this frame, so verify from Android instead:
# scripts/verify-partitions.sh.
# Usage: scripts/flash-partition.sh <partition-name> <file>
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RKDT=${RKDT:-$ROOT/build/src/rkdeveloptool/rkdeveloptool}
PART=${1:?usage: flash-partition.sh <partition-name> <file>}
FILE=${2:?usage: flash-partition.sh <partition-name> <file>}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

"$RKDT" ld | grep -q 'Mode=Loader' || { echo "STOP: frame is not in Loader mode" >&2; exit 1; }

"$RKDT" rl 0 34 "$WORK/gpt.bin" > /dev/null
read -r first sectors < <(python3 -I - "$WORK/gpt.bin" "$PART" <<'EOF'
import struct, sys
gpt = open(sys.argv[1], 'rb').read()
assert gpt[512:520] == b'EFI PART', 'no GPT header at LBA 1'
entries, count, size = struct.unpack_from('<QII', gpt, 512 + 72)
for i in range(count):
    e = gpt[entries * 512 + i * size:][:size]
    name = e[56:128].decode('utf-16-le').rstrip('\0')
    if name == sys.argv[2]:
        first, last = struct.unpack_from('<QQ', e, 32)
        print(first, last - first + 1)
        sys.exit(0)
sys.exit('partition not found: ' + sys.argv[2])
EOF
)

bytes=$(stat -f %z "$FILE")
capacity=$((sectors * 512))
if (( bytes > capacity )); then
  echo "STOP: $FILE is $bytes bytes, partition $PART holds $capacity" >&2
  exit 1
fi
echo "write $FILE ($bytes bytes) to $PART (LBA $first, $capacity bytes)"
"$RKDT" wl "$first" "$FILE"

echo "written; verify from Android with scripts/verify-partitions.sh"
