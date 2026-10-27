#!/usr/bin/env bash
# One test boot of our Linux image from the recovery partition, then collect
# the evidence. Stock boot is never touched, so Android comes back by itself.
#
#   1. write build/frame157-recovery/frame157-recovery.img to recovery
#   2. adb reboot recovery
#   3. watch for our USB ACM console (success) or Android returning
#   4. once Android is back, save /sys/fs/pstore (our kernel's log) and dmesg
#
# Our init reboots on any failure and 3 minutes after success unless
# /tmp/keep is created on the ACM console, and the kernel reboots on panic.
# Usage: scripts/try-recovery-boot.sh [image]
set -euo pipefail

ADB=${ADB:-/opt/homebrew/bin/adb}
SERIAL=${SERIAL:-HF4A62I77N}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=${1:-$ROOT/build/frame157-recovery/frame157-recovery.img}
LOG=$ROOT/build/logs/recovery-boot-$(date +%Y%m%d-%H%M%S)
mkdir -p "$LOG"

fsh() { "$ADB" -s "$SERIAL" shell "su -c '$1'" | tr -d '\r'; }
adb_up() { "$ADB" devices | grep -q "^$SERIAL[[:space:]]*device"; }
# The frame's USB only re-enumerates on the Mac after the cable is replugged,
# so the user is asked (by macOS notification) to replug at set times.
notify() {
  echo "NOTIFY: $1"
  osascript -e "display notification \"$1\" with title \"framarchy\" sound name \"Glass\"" || true
}

adb_up || { echo "STOP: frame not on ADB" >&2; exit 1; }
"$ROOT/scripts/write-partition.sh" recovery "$IMAGE" | tee "$LOG/write.log"
shasum -a 256 "$IMAGE" > "$LOG/image.sha256"

echo "rebooting into recovery (our image)"
"$ADB" -s "$SERIAL" reboot recovery
start=$(date +%s)
sleep 10
acm=""
asked=0
while :; do
  t=$(( $(date +%s) - start ))
  # Ask at 60 s (our kernel's console should be up) and at 240 s (Android
  # back after our 3-minute timeout). Leave the frame's power alone.
  if [[ -z $acm ]] && { (( t >= 60 && asked == 0 )) || (( t >= 240 && asked == 1 )); }; then
    notify "Replug the frame's USB cable now (data cable only, not power)"
    asked=$((asked + 1))
  fi
  # Still nothing at 5 minutes: our kernel has probably hung. A warm reset
  # keeps RAM (and the pstore log); cutting power loses it.
  if [[ -z $acm ]] && (( t >= 300 && asked == 2 )); then
    notify "Frame hung? Press RST through the headphone jack (do NOT cut power), then replug USB"
    asked=3
  fi
  if [[ -z $acm ]] && ls /dev/cu.usbmodem* > /dev/null 2>&1; then
    acm=$(ls /dev/cu.usbmodem* | head -1)
    echo "$t s: ACM console $acm" | tee -a "$LOG/timeline.txt"
    notify "Linux booted: USB console is up"
    # Collect the kernel log over the console, then hand back to Android.
    sleep 2
    "$ROOT/scripts/acm-run.py" 'touch /tmp/keep; uname -a; cat /proc/cmdline; dmesg' 8 \
      > "$LOG/acm-console.txt" || true
    "$ROOT/scripts/acm-run.py" 'reboot -f' 1 > /dev/null || true
    echo "console log: $LOG/acm-console.txt ($(wc -l < "$LOG/acm-console.txt") lines)"
  fi
  # Mainline U-Boot (chain-load image) sets fastboot mode when it finds
  # nothing to boot; record that and send the frame back to Android.
  if /opt/homebrew/bin/fastboot devices 2>/dev/null | grep -q .; then
    echo "$t s: fastboot: mainline U-Boot ran but booted nothing" | tee -a "$LOG/timeline.txt"
    notify "Mainline U-Boot ran but found nothing to boot; collecting its log"
    # Our chain-loaded U-Boot (USB 2207:0157) records its console; read it
    # and probe the storage before handing back to Android.
    FB=/opt/homebrew/bin/fastboot
    for cmd in "mmc list" "mmc dev 1" "mmc info" "part list mmc 1" \
        "ls mmc 1:1 /" "ls mmc 1:1 /extlinux" "bootflow list" "bdinfo"; do
      $FB oem run:"$cmd" > /dev/null 2>&1 || true
    done
    $FB oem console > "$LOG/uboot-console.txt" 2>&1 || true
    echo "U-Boot console: $LOG/uboot-console.txt ($(wc -l < "$LOG/uboot-console.txt") lines)"
    $FB reboot || true
  fi
  if "$ROOT/build/src/rkdeveloptool/rkdeveloptool" ld 2>/dev/null | grep -q Loader; then
    echo "$t s: Loader mode: stock U-Boot refused the image" | tee -a "$LOG/timeline.txt"
    notify "Stock U-Boot refused the image (Loader mode); resetting"
    "$ROOT/build/src/rkdeveloptool/rkdeveloptool" rd || true
  fi
  if adb_up; then
    echo "$t s: Android back on ADB" | tee -a "$LOG/timeline.txt"; break
  fi
  if (( t > 1200 )); then
    echo "$t s: neither came back; power-cycle the frame" | tee -a "$LOG/timeline.txt"
    exit 1
  fi
  sleep 3
done

"$ADB" -s "$SERIAL" wait-for-device
until [[ $(fsh 'getprop sys.boot_completed') == 1 ]]; do sleep 2; done
fsh 'ls -l /sys/fs/pstore' > "$LOG/pstore-ls.txt"
for f in $(fsh 'ls /sys/fs/pstore'); do
  "$ADB" -s "$SERIAL" shell "su -c 'cat /sys/fs/pstore/$f'" | LC_ALL=C tr -d '\r' > "$LOG/$f"
done
fsh 'dmesg' > "$LOG/android-dmesg.txt"
notify "Test boot finished; evidence collected"
echo "evidence in $LOG:"
cat "$LOG/pstore-ls.txt"
grep -h 'FRAME157_\|Kernel panic\|Linux version' "$LOG"/console-ramoops* 2>/dev/null || true
