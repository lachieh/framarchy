#!/usr/bin/env bash
# Write a file into an eMMC partition from the running stock Android (root ADB).
# Refuses files larger than the partition, then hashes the written range on
# the frame and compares it with the file.
# Usage: scripts/write-partition.sh <partition-name> <file>
set -euo pipefail

ADB=${ADB:-/opt/homebrew/bin/adb}
SERIAL=${SERIAL:-HF4A62I77N}
PART=${1:?usage: write-partition.sh <partition-name> <file>}
FILE=${2:?usage: write-partition.sh <partition-name> <file>}
DEV=/dev/block/by-name/$PART
TMP=/data/local/tmp/framarchy-$PART.img

fsh() { "$ADB" -s "$SERIAL" shell "su -c '$1'" | tr -d '\r'; }

bytes=$(stat -f %z "$FILE")
capacity=$(fsh "blockdev --getsize64 $DEV")
[[ $capacity =~ ^[0-9]+$ ]] || { echo "STOP: cannot size $DEV: $capacity" >&2; exit 1; }
if (( bytes > capacity )); then
  echo "STOP: $FILE is $bytes bytes, $PART holds $capacity" >&2; exit 1
fi

"$ADB" -s "$SERIAL" push "$FILE" "$TMP" > /dev/null
want=$(shasum -a 256 "$FILE" | cut -d' ' -f1)
[[ $(fsh "sha256sum $TMP" | cut -d' ' -f1) == "$want" ]] \
  || { echo "STOP: pushed copy differs" >&2; exit 1; }

echo "write $FILE ($bytes bytes) to $PART ($capacity bytes)"
# Android 8.1 toolbox dd has no conv=; flush with sync and blockdev instead.
out=$(fsh "dd if=$TMP of=$DEV bs=1048576 2>&1 && sync && blockdev --flushbufs $DEV && echo WROTE")
fsh "rm $TMP"
[[ $out == *WROTE* ]] || { echo "STOP: dd failed: $out" >&2; exit 1; }
got=$(fsh "head -c $bytes $DEV | sha256sum" | cut -d' ' -f1)
[[ $got == "$want" ]] || { echo "STOP: $PART read-back differs" >&2; exit 1; }
echo "verified $PART"
