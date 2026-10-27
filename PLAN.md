# Omarchy on FRAME157 (RK3326): plan

Goal: replace the stock Frameo/Android OS with Arch Linux ARM (aarch64) and
Omarchy, with a working panel, touch and network. Hardware facts are in
[docs/hardware.md](docs/hardware.md); research with citations is in
[research/](research/).

## Safety rules

1. No replacement image is written to the eMMC until `backup/frame157/` holds
   verified partition and boot-area copies, and `backup/frame157-loader/` holds
   the complete offline disk image from `scripts/backup-loader.py` (two matching
   reads per chunk, followed by assembly and a complete local hash check).
2. Boot experiments run from microSD first, if the stock U-Boot will boot
   one (see stage 2). The eMMC is only replaced once the SD system works.
3. Recovery is Rockchip maskrom: the BootROM cannot be overwritten, and
   `rkdeveloptool` + `rk3326_loader` can rewrite the whole eMMC from the
   backup.

## Stages

Each stage ends in a check that has passed on the real frame.

| # | Stage | Done when |
| --- | --- | --- |
| 0 | Access and identification | Root ADB, hardware table, live DTB saved |
| 1 | Verified full backup | `backup-emmc.sh` completes; maskrom tool reads the eMMC |
| 2 | Boot path | A mainline kernel prints to the panel or USB gadget console from SD (or, failing that, from the eMMC `boot` partition with the stock loader kept) |
| 3 | Display | LT8911EXB driver lights the 1920x1080 panel under DRM; start from the bridge's internal test pattern |
| 4 | Input and network | Touch reports events; network via RK915 (`rei512/rk915`) or a USB Wi-Fi adapter |
| 5 | Arch Linux ARM rootfs | Boots to a login over USB gadget serial/NCM and on tty1 |
| 6 | Omarchy | `port/bootstrap.sh` installs pinned Omarchy; Hyprland + Quickshell run on the panel with touch |
| 7 | Replace eMMC | The SD system is written to the eMMC; the frame boots it without a card |

## Key decisions

- **aarch64, not armv7.** The RK3326 is ARMv8. Arch Linux ARM aarch64 carries
  161 of 164 packages in Omarchy's aarch64 set, and Omarchy's `quattro` branch
  supports aarch64 (see research/02).
- **Mainline kernel 6.18 LTS** with a board DTS derived from the vendor
  `rk3326-evb-ai-va-v11.dts` and the live DTB.
- **Omarchy pinned** to `defbf90e893e741067e48f4a27d2ec694c71358e`, installed
  from source like the armv7 reference port, without SDDM, snapper or the ISO
  installer.

## Biggest risks

- No mainline LT8911EXB driver: a new DRM bridge driver is required.
- RK915 Wi-Fi driver is out-of-tree and unstable under load.
- The stock U-Boot may not boot from SD, forcing earlier eMMC changes.

## Progress log

- 2026-10-15: Root ADB, hardware identified (docs/hardware.md).
- 2026-10-15: Recovery tools built on macOS: rkdeveloptool 1.32 and
  `rk3326_loader_v2.12.140.bin` (sha256 `eec7c509…1f8d07`). Not yet used on the frame.
- 2026-10-15: Arch Linux ARM aarch64 rootfs downloaded, GPG signature verified.
- 2026-10-15: Kernel 6.18 builds in Docker with the new LT8911EXB driver
  (`lontium-lt8911exb.ko`), Panfrost, Rockchip DRM/DSI, Silead and Ilitek
  touch. Untested on hardware.
- 2026-10-15 09:42 EDT: Frame connected over ADB. Live DTB and partitions
  through cache backed up with matching device/host hashes. System partition
  transfer in progress; full eMMC backup still pending. Android Settings is
  open, Frameo disabled, and stay-awake enabled. See
  [operations log](docs/operations.md) for commands and the launcher failure.
- Pending: finish and verify the offline full backup, check stock U-Boot SD boot,
  and build the mainline board DTB plus USB-console initramfs.
- 2026-10-15: All named partition and boot-area backups completed. ADB whole-disk
  transfer stopped at 16.6 GB. Entered Loader mode and verified first-4-MB read
  against ADB copy. Started resumable double-read offline backup with
  `scripts/backup-loader.py`. Silead touch confirmed at `1-0040`. Mainline board
  DTS, initramfs and boot-media assembly are still missing.
- 2026-10-15 evening: Loader-mode full backup found invalid (0xCC filler); the
  per-partition ADB backup is the restore source. SD boot ruled out on stock
  U-Boot. The earlier `boot` test image was malformed and oversized and
  overwrote the start of `recovery` (to be restored). New route: boot our
  image from `recovery` via `adb reboot recovery` with stock `boot` untouched,
  with a pstore crash log readable from Android afterwards
  ([boot-evidence](docs/boot-evidence.md)). Image built:
  `build/frame157-recovery/frame157-recovery.img`. Board identified as
  C-Link CL-RK3326-DP105F V1.3, with labelled UART pads and an UPDATE (Loader)
  button ([debug-uart](docs/debug-uart.md)).
- 2026-10-15 22:06: **Linux 6.18 boots on the frame with our own DTB** and gives
  a root shell on the USB ACM console. Chain: stock U-Boot -> mainline U-Boot
  (from `recovery`) -> SD card extlinux ([booting](docs/booting.md)). 4 cores,
  964 MB RAM, SD card and RK809 PMIC detected. Init bugs fixed (cttyhack,
  PID 1 exiting under setsid). SD card partition 2 (58 GB) created for the root
  filesystem. Next: kernel with display/touch/NCM + modules, display DT
  (DSI -> LT8911EXB -> eDP panel), `scripts/build-rootfs.sh`, first Omarchy boot.
- 2026-10-15 23:15: Kernel rebuilt with the display chain (VOP, DSI, LT8911EXB,
  panel-simple, Panfrost), Silead, USB host and NCM; modules packaged. Display
  DT written from the stock DT's values. `scripts/build-rootfs.sh` built the
  Arch Linux ARM + Omarchy root filesystem (521 packages, [rootfs](docs/rootfs.md));
  written to SD partition 2 and hash-verified on the frame. First Omarchy boot
  started; result pending a USB replug.
- 2026-10-16 14:19: **Omarchy desktop on the panel.** Fixes that got there:
  old 64 GB SD card had read errors (replaced with a 256 GB card); the stock
  TF-A/OP-TEE secure RAM 0x08400000-0x0a200000 must be reserved in the DTS
  (mainline U-Boot reports all RAM; using it caused bus errors, I/O errors and
  hangs); the LT8911EXB needs burst-mode DSI with LP commands, as the stock
  panel node (`dsi,flags = 0x803`). Bridge test pattern confirmed the eDP side.
  Still open: CPU frequency scaling is off (`cpufreq.off=1`, untested since
  the RAM fix), touch, Wi-Fi, booting without the Android `recovery`
  round-trip, and Linux reboots returning to Android.
- 2026-10-16 18:35: **Boots Omarchy by default**: the chain-loader is in the
  eMMC `boot` partition (stock `boot` is in the backup; restore with Loader
  mode + `scripts/flash-partition.sh boot backup/frame157/boot.img`). Touch
  works (Silead firmware extracted from the stock kernel, calibrated 1784x1160,
  both axes inverted, no swap). Wi-Fi works (out-of-tree rk915 + mmc quirks
  patch), reachable as `frame157.local`. CPU frequency scaling back on (the
  earlier hangs were the secure-RAM bug); TSADC enabled, CPU capped at
  1008 MHz like stock (85 C at 1296 MHz under load, 73 C capped).
- 2026-10-16 20:15 EDT: Changed transparent huge pages from always to madvise;
  settled Quickshell PSS fell by about 60 MiB in a fresh-shell comparison.
  Persistent tmpfiles setting installed. User chose mouse-style touch trial:
  built/loaded matching uinput module and started a small C adapter (tap on
  release, 650-ms right-click hold, slide without click). Unit and live input
  path tests passed; native touch restoration tested. Service is not enabled
  at boot pending user feedback. See [desktop tuning](docs/desktop-tuning.md).
- 2026-10-16: User rejected mouse-style touch. Stopped and disabled
  `frame-touch-mouse`, verified process exit and physical input release. Native
  touch restored; the huge-page memory improvement remains enabled.
- 2026-10-16: Fixed invisible Squeekboard by bypassing the stalled Glycin
  image-loader sandbox only in the keyboard service. Verified rendered keyboard
  in screenshots and Q/Enter touch input delivered to a disposable text client.
  Keyboard bar button enabled. See desktop tuning notes for scope and limits.
- 2026-10-16: Settings editor actions silently selected missing Neovim. Set
  installed Nano as the default, made that default part of fresh port setup,
  and verified a Hyprland config opened in Nano through the actual launcher.
- 2026-10-24: Clock fixed: the frame had never synced (2017 date). networkd
  counted the unplugged `usb0` gadget as required, so it reported "offline" and
  systemd-timesyncd never sent a packet. `rootfs/usb0.network` now sets
  `RequiredForOnline=no`; applied on the frame, synced, timezone set to
  America/New_York. Home dashboard prototype deployed as the `frame.dashboard`
  shell plugin (worktree branch `t3/cc62c58b`, `dashboard/` and
  `docs/dashboard.md`).
