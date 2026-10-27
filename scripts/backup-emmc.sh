#!/usr/bin/env bash
# Read-only backup of the FRAME157 (RK3326) eMMC over root ADB.
# Each image is hashed on the frame and on the Mac; a mismatch stops the run.
# Usage: scripts/backup-emmc.sh <out-dir>
set -euo pipefail

ADB=${ADB:-/opt/homebrew/bin/adb}
SERIAL=${SERIAL:-HF4A62I77N}
OUT=${1:?usage: backup-emmc.sh <out-dir>}
PORT=${PORT:-29999}
mkdir -p "$OUT"
# The frame connects back to a listener on the Mac (adb reverse), so the
# listener is always up before data is sent.
"$ADB" -s "$SERIAL" forward --remove tcp:$PORT 2>/dev/null || true
"$ADB" -s "$SERIAL" reverse tcp:$PORT tcp:$PORT > /dev/null

fsh() { "$ADB" -s "$SERIAL" shell "su -c '$1'" | tr -d '\r'; }

dump() { # <device> <file>
  local dev=$1 file=$OUT/$2
  if [[ -f $file.sha256 ]]; then echo "skip $2 (done)"; return; fi
  echo "dump $dev -> $2"
  # SuperSU runs root commands on a pty that turns LF into CRLF, so binary
  # data cannot come through su's stdout. Serve it over busybox nc instead.
  nc -d -l "$PORT" > "$file.part" &
  local listener=$!
  sleep 1
  fsh "busybox nc 127.0.0.1 $PORT < $dev" > /dev/null
  wait $listener
  local remote local_ size expected
  size=$(stat -f %z "$file.part")
  expected=$(fsh "wc -c < $dev" | tr -d ' ')
  if [[ $size != "$expected" ]]; then
    echo "STOP: $2 is $size bytes, $dev is $expected bytes" >&2; exit 1
  fi
  remote=$(fsh "sha256sum $dev" | awk '{print $1}')
  local_=$(shasum -a 256 "$file.part" | awk '{print $1}')
  if [[ $remote != "$local_" ]]; then
    echo "STOP: $2 hash mismatch (frame $remote, mac $local_)" >&2; exit 1
  fi
  mv "$file.part" "$file"
  echo "$local_  $2" > "$file.sha256"
}

fsh 'cat /proc/partitions; ls -l /dev/block/by-name' > "$OUT/layout.txt"
"$ADB" -s "$SERIAL" shell getprop > "$OUT/getprop.txt"
# The device tree the vendor bootloader actually passed to the kernel.
dump /sys/firmware/fdt live.dtb
fsh 'lsmod; dmesg' > "$OUT/dmesg.txt"

for name in uboot trust misc resource kernel boot recovery backup security cache system metadata vendor oem frp; do
  dump "/dev/block/by-name/$name" "$name.img"
done
for hw in mmcblk2boot0 mmcblk2boot1; do
  dump "/dev/block/$hw" "$hw.img"
done
# The whole user area last: GPT, the loader area before p1, and userdata.
dump /dev/block/mmcblk2 mmcblk2-full.img

echo "backup complete: $OUT"
