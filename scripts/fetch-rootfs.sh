#!/usr/bin/env bash
# Download the Arch Linux ARM aarch64 generic rootfs and verify it.
# Output: build/downloads/ArchLinuxARM-aarch64-latest.tar.gz
set -euo pipefail
export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DL=$ROOT/build/downloads
BASE=http://os.archlinuxarm.org/os
TAR=ArchLinuxARM-aarch64-latest.tar.gz
# Arch Linux ARM Build System <builder@archlinuxarm.org>
KEY=68B3537F39A313B3E574D06777193F152BDBE6A6

mkdir -p "$DL" && cd "$DL"
for f in $TAR.md5 $TAR.sig $TAR; do curl -fsSLO "$BASE/$f"; done
md5 -r $TAR | cut -d' ' -f1 | grep -qx "$(cut -d' ' -f1 $TAR.md5)" || { echo "STOP: md5 mismatch" >&2; exit 1; }
gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys $KEY
gpg --batch --status-fd 1 --verify $TAR.sig $TAR | grep -q "VALIDSIG $KEY" || { echo "STOP: bad signature" >&2; exit 1; }
echo "verified $DL/$TAR"
