#!/usr/bin/env bash
# Package the kernel, DTB and initramfs as an Android boot image that the
# frame's stock Rockchip U-Boot accepts, for the recovery partition.
#
# Layout copied from the stock boot image (backup/frame157/boot.img):
# header v0, page 2048, same load addresses and os_version, and the DTB in
# the "second" area as a Rockchip resource image (RSCE) entry named
# rk-kernel.dtb, alongside the stock boot logos.
# Output: build/frame157-recovery/frame157-recovery.img
# KERNEL=<file>, DTB=<file> and NAME=<basename> override the kernel, device
# tree and output name (diagnostic and chain-load images).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/frame157-recovery
CMDLINE=${CMDLINE:-"rdinit=/init earlycon=uart8250,mmio32,0xff160000,1500000n8 ignore_loglevel panic=-1 oops=panic"}
KERNEL=${KERNEL:-$ROOT/build/kernel/Image}
DTB=${DTB:-$ROOT/build/kernel/rk3326-frame157.dtb}
NAME=${NAME:-frame157-recovery}
mkdir -p "$OUT"

python3 -I - "$ROOT" "$OUT/$NAME.img" "$CMDLINE" "$DTB" "$KERNEL" <<'EOF'
import hashlib, struct, sys

root, out, cmdline, dtb, kernel_path = sys.argv[1], sys.argv[2], sys.argv[3].encode(), sys.argv[4], sys.argv[5]
PAGE = 2048
RECOVERY_BYTES = 71680 * 1024  # recovery partition, docs/hardware.md

def pad(data, size):
    return data + b'\0' * (-len(data) % size)

stock = open(f'{root}/backup/frame157/boot.img', 'rb').read()
assert stock[:8] == b'ANDROID!'
ks, ka, rs, ra, ss, sa, ta, ps, ver, osv = struct.unpack_from('<10I', stock, 8)
assert ps == PAGE and ver == 0

def resource_entries(rsce):
    assert rsce[:4] == b'RSCE'
    count = struct.unpack_from('<I', rsce, 12)[0]
    for i in range(count):
        e = rsce[512 * (1 + i):512 * (2 + i)]
        assert e[:4] == b'ENTR'
        name = e[4:260].split(b'\0')[0].decode()
        blk, size = struct.unpack_from('<II', e, 260)
        yield name, rsce[blk * 512:blk * 512 + size]

stock_second = stock[PAGE + len(pad(stock[PAGE:PAGE + ks], PAGE)) +
                     len(pad(b'\0' * rs, PAGE)):][:ss]
entries = dict(resource_entries(stock_second))
assert set(entries) == {'rk-kernel.dtb', 'logo.bmp', 'logo_pcba.bmp'}, entries.keys()
entries['rk-kernel.dtb'] = open(dtb, 'rb').read()
assert entries['rk-kernel.dtb'][:4] == b'\xd0\x0d\xfe\xed'

# RSCE: 512-byte header block, one 512-byte entry per file, then the data,
# each file starting on a 512-byte block.
names = ['rk-kernel.dtb', 'logo.bmp', 'logo_pcba.bmp']
table, data = b'', b''
blk = 1 + len(names)
for name in names:
    blob = entries[name]
    table += pad(b'ENTR' + name.encode().ljust(256, b'\0') +
                 struct.pack('<II', blk, len(blob)), 512)
    data += pad(blob, 512)
    blk += len(pad(blob, 512)) // 512
header = pad(b'RSCE' + struct.pack('<HHBBBBI', 0, 0, 1, 1, 1, 0, len(names)), 512)
second = header + table + data

kernel = open(kernel_path, 'rb').read()
assert kernel[56:60] == b'ARMd', 'not an arm64 Image'
ramdisk = open(f'{root}/build/initramfs/initramfs.cpio.gz', 'rb').read()
assert len(cmdline) < 512

sha = hashlib.sha1()
for blob in (kernel, ramdisk, second):
    sha.update(blob)
    sha.update(struct.pack('<I', len(blob)))

hdr = b'ANDROID!' + struct.pack('<10I', len(kernel), ka, len(ramdisk), ra,
                                len(second), sa, ta, PAGE, 0, osv)
hdr += b'\0' * 16 + cmdline.ljust(512, b'\0') + sha.digest().ljust(32, b'\0')
image = pad(hdr, PAGE) + pad(kernel, PAGE) + pad(ramdisk, PAGE) + pad(second, PAGE)
assert len(image) <= RECOVERY_BYTES, f'{len(image)} bytes > recovery {RECOVERY_BYTES}'
open(out, 'wb').write(image)
print(f'kernel {len(kernel)} @{ka:#x}, ramdisk {len(ramdisk)} @{ra:#x}, '
      f'second {len(second)} @{sa:#x}, image {len(image)} of {RECOVERY_BYTES}')
print('cmdline', cmdline.decode())
EOF
(cd "$OUT" && shasum -a 256 "$NAME.img" > "$NAME.img.sha256")
cat "$OUT/$NAME.img.sha256"
