# How Linux boots on FRAME157

Verified on hardware 2026-10-15: Linux 6.18 boots with our own device tree
and gives a root shell on a USB serial console.

```
BootROM -> stock idbloader/TF-A -> stock Rockchip U-Boot (eMMC, untouched)
  -> "recovery" partition: build/frame157-recovery/frame157-chainload.img
     = mainline U-Boot v2025.10 packaged as an arm64 Linux Image, with the
       stock DTB in the resource area (stock U-Boot accepts only that)
  -> mainline U-Boot: sysboot mmc 1:1 /extlinux/extlinux.conf (SD card)
  -> Linux 6.18 + our DTB (+ initramfs or the SD root partition)
```

## Why the chain

Stock U-Boot loads the kernel DTB from the boot image and drives its own
hardware from it first. Given our mainline DTB it refuses the image and drops
to Loader mode (the kernel never runs; pstore showed only Android's log).
Given the stock DTB it starts the kernel, but mainline Linux hangs on the
vendor DT. Mainline U-Boot needs neither: stock U-Boot starts it with the
stock DTB, and it boots Linux with ours.

## Pieces

- `scripts/build-chainload-uboot.sh`, `uboot/chainload.config`: evb-px30
  U-Boot proper, position independent, with no PMIC/regulator drivers and no
  saved environment (it cannot change a rail or write the eMMC). The header's
  image_size is raised to the file size, because stock U-Boot copies only
  image_size bytes when it relocates a kernel.
- If the SD card does not boot, mainline U-Boot becomes a read-only fastboot
  device (USB 2207:0157): `fastboot oem console` prints its log,
  `fastboot oem run:<cmd>` runs commands, `fastboot reboot` returns to Android.
- `boot/extlinux.conf` on the SD card's FAT partition: `omarchy` (root on
  partition 2) by default, `firstboot` (initramfs debug shell) as fallback.

## Running it

Stock Android restores the factory `recovery` at every boot, so write the
chain-loader and reboot in one go:

```sh
scripts/write-partition.sh recovery build/frame157-recovery/frame157-chainload.img \
  && adb reboot recovery
```

After any reboot, the Mac sees the frame's USB again only after the cable is
replugged. The Linux console is then `/dev/cu.usbmodem*`;
`scripts/acm-run.py '<command>'` runs a command on it. Any reboot from Linux
returns to stock Android.

## Fixes that the first full boot needed (2026-10-16)

- **Secure RAM:** stock TF-A/OP-TEE use 0x08400000-0x0a200000. Stock U-Boot
  leaves that out of the memory node; mainline U-Boot does not, so the board
  DTS reserves it (`secure-memory@8400000`, no-map). Without it: SD "I/O
  errors" at the same file on two different cards, systemd `Caught <BUS>`,
  and hard hangs a few seconds into boot.
- **DSI mode:** the LT8911EXB only locks to burst-mode DSI with LP commands
  (stock `dsi,flags = 0x803`). In non-burst mode it measured 1410/1350 lines
  instead of 1140/1080 and the panel stayed dark. The bridge driver has a
  `test_pattern=1` module option that checks the eDP side on its own.
- **Logs without a console:** the initramfs writes the kernel log to the SD
  card's FAT partition (`/logs`), readable from Android after any restart.
- **USB network:** the frame is always at `169.254.157.157` on the USB link
  (`ssh frame@169.254.157.157`).
