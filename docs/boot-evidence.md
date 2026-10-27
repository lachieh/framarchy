# Test-booting Linux from the recovery partition

How a Linux image is tried on the frame without touching the stock `boot`
partition or needing a serial console.

## Why recovery

- **Size:** the kernel `Image` alone is about 41 MB. `boot` holds 39,845,888
  bytes, while `recovery` holds 73,400,320.
- **Selection:** stock U-Boot boots `recovery` when Android reboots with
  `adb reboot recovery`. Any later reboot that isn't marked recovery boots
  the untouched stock `boot` again, so Android comes back by itself.
- **No Loader mode:** `recovery` is written from Android with root `dd`
  (`scripts/write-partition.sh`).

## Image format

`scripts/build-boot-img.sh` builds `build/frame157-recovery/frame157-recovery.img`
with the stock layout: an Android boot image header v0, page 2048, and the stock
load addresses and `os_version`. Stock U-Boot takes the kernel DTB from the
image's "second" area, which holds a Rockchip resource image (`RSCE`) whose
entry `rk-kernel.dtb` is our DTB. The stock `logo.bmp` and `logo_pcba.bmp`
entries are copied in next to it. The kernel command line is in the header.
Stock U-Boot appends `androidboot.*` arguments to it.

The earlier image (`frame157-boot.img`, deleted) had a corrupt kernel load
address (`0xf8993`), non-resource bytes in "second", and stock's command
line. It was also too big for `boot`. Its test results said nothing about
our kernel.

## Evidence without a console: pstore

The stock DT reserves `0xf0000` bytes at `0x110000` for ramoops: one 128 KiB
dump record, a 512 KiB console zone, and a 320 KiB pmsg zone. Our DTS
reserves the same region with the same zone sizes, and the kernel has
`CONFIG_PSTORE_RAM`, `CONFIG_PSTORE_CONSOLE` and `CONFIG_PSTORE_PMSG` built
in. RAM survives a warm reboot, so after our kernel runs, stock Android finds
its console log (and any panic record) in `/sys/fs/pstore/`.

How each attempt ends:

| What happens | Ends with | Evidence |
| --- | --- | --- |
| U-Boot rejects the image | U-Boot's fallback, possibly Loader mode | pstore holds stock Android's previous log, not ours |
| Kernel panics | `panic=-1 oops=panic`: immediate warm reboot | `console-ramoops-0` (and `dmesg-ramoops-0`) |
| `init` fails a step | `FRAME157_FIRSTBOOT_ERROR stage=…`, then `reboot -f` | `console-ramoops-0` |
| Everything works | USB ACM console on the Mac; reboot after 3 minutes unless `touch /tmp/keep` | the console itself |

`ignore_loglevel` sends every message to the pstore console.

## Running it

```sh
scripts/build-kernel.sh && scripts/build-initramfs.sh && scripts/build-boot-img.sh
scripts/try-recovery-boot.sh
```

The script writes `recovery`, reboots into it, watches for the ACM console,
waits for Android, and saves `/sys/fs/pstore/*` and Android's `dmesg` under
`build/logs/recovery-boot-<time>/`.

## Android restores `recovery` at boot

Stock Android rewrites `recovery` with the factory image at every boot if it
differs (AOSP `flash_recovery` / `install-recovery.sh`). Our image therefore
only survives until Android's next boot: write it and reboot straight away, as
`scripts/try-recovery-boot.sh` does. If the frame shows the green robot with
"No command", that is stock recovery: hold PWR to restart into Android.

## Unverified so far

- Whether stock Android exposes the console zone at all. Check this first with
  stock software only: `adb reboot`, then `adb shell su -c 'ls /sys/fs/pstore'`.
  `console-ramoops-0` should hold the previous Android boot's kernel log.
- Whether stock U-Boot accepts a DTB with the eMMC node disabled. The pstore
  result will show it: if U-Boot never starts our kernel, there is no
  `Linux version 6.18` line.
- Whether U-Boot clears the recovery boot flag after reading it. If it
  doesn't, the frame boots our image on every reboot. Enter Loader mode with
  the UPDATE button and rewrite `recovery` from the backup
  ([recovery.md](recovery.md)).
