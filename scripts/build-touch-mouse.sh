#!/usr/bin/env bash
# Build the mouse adapter and matching uinput module using the configured kernel.
set -euo pipefail
export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build/touch"
docker run --rm --platform linux/arm64 \
  -v frame157-linux:/src -v "$ROOT":/repo debian:trixie-slim \
  bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential bc bison flex libssl-dev libelf-dev kmod >/dev/null
cd /src/linux
test -f .config && test -f Module.symvers
scripts/config --module INPUT_UINPUT
make -s olddefconfig
make -s -j4 drivers/input/misc/uinput.ko
cp drivers/input/misc/uinput.ko /repo/build/touch/
make -s kernelrelease > /repo/build/touch/kernel-release
gcc -O2 -Wall -Wextra -Werror /repo/port/touch/frame-touch-mouse.c -o /repo/build/touch/frame-touch-mouse
gcc -O2 -Wno-unused-function -Wno-unused-variable /repo/port/touch/test-touch.c -o /repo/build/touch/test-touch
/repo/build/touch/test-touch
modinfo drivers/input/misc/uinput.ko > /repo/build/touch/module-info.txt
'
