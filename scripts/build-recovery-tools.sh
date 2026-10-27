#!/usr/bin/env bash
# Build the maskrom recovery tools on macOS:
#   build/src/rkdeveloptool/rkdeveloptool   (USB flashing tool)
#   build/src/rkbin/rk3326_loader_*.bin     (loader the BootROM runs from RAM)
# Needs Homebrew and Docker (boot_merger is a Linux x86 binary).
set -euo pipefail
export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/build/src
mkdir -p "$SRC"

clone() { # <url> <dir> <commit>
  [[ -d $SRC/$2 ]] || git clone -q "$1" "$SRC/$2"
  git -C "$SRC/$2" checkout -q "$3"
}
clone https://github.com/rockchip-linux/rkdeveloptool.git rkdeveloptool 304f073
clone https://github.com/rockchip-linux/rkbin.git rkbin 3e288fe

brew install --quiet libusb automake autoconf pkgconf

cd "$SRC/rkdeveloptool"
autoreconf -i >/dev/null
./configure >/dev/null
# Recent Apple clang rejects the tool's variable-length arrays under -Werror.
make -j8 CXXFLAGS="-g -O2 -Wno-vla-cxx-extension" >/dev/null

docker run --rm --platform linux/amd64 -v "$SRC/rkbin":/rkbin -w /rkbin \
  debian:bookworm-slim ./tools/boot_merger RKBOOT/RK3326MINIALL.ini

echo "rkdeveloptool: $SRC/rkdeveloptool/rkdeveloptool"
shasum -a 256 "$SRC"/rkbin/rk3326_loader_*.bin
