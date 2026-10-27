# FRAME157 operations log

Latest desktop changes (2026-10-16): see
[memory and mouse-style touch](desktop-tuning.md) for the huge-page comparison,
persistent memory setting, uinput module, active touch trial, tests and rollback.

Record device changes, evidence and unresolved limits here as work proceeds.
Times use the Mac's clock (America/New_York); the frame's Android logs show an
incorrect December 31 date. Device serial: `HF4A62I77N`.

## 2026-10-15: backup transfer

The backup runs with `scripts/backup-emmc.sh backup/frame157`; output is in
`backup/frame157-backup.log` (local, gitignored).

Binary output through SuperSU's PTY was unsuitable because it changes LF bytes
to CRLF. The script instead uses `adb reverse tcp:29999 tcp:29999`, starts
`nc -d -l 29999` on the Mac, then connects from root BusyBox netcat on the frame.
Removing a conflicting ADB forward and adding `-d` to the Mac listener resolved
the observed zero-byte transfers and `nc: short write` failure. A test transfer
of `/sys/firmware/fdt` produced 110,720 bytes.

The script compares each transfer's size and SHA-256 against the device before
renaming `.part` to the final filename and writing its `.sha256` file.

At 09:42 EDT, `live.dtb` and partitions `uboot`, `trust`, `misc`, `resource`,
`kernel`, `boot`, `recovery`, `backup`, `security` and `cache` have completed
with hash sidecars. `system.img.part` is still transferring. The remaining
partitions, eMMC boot areas and full disk image have not completed. No full
backup or tested restore is claimed.

## 2026-10-15: idle shutdown and fallback startup screen

The user reported that the frame powered off when idle. Earlier in this session,
Frameo was force-stopped and disabled to remove its scheduled alarms:

```sh
/opt/homebrew/bin/adb -s HF4A62I77N shell "su -c 'am force-stop net.frameo.frame; pm disable-user --user 0 net.frameo.frame'"
```

The immediate alarm check found zero `net.frameo.frame` entries and power state
`Awake`. This does not prove the cause of every possible shutdown.

The user then reported an endless **Android is starting…** screen. ADB showed
`sys.boot_completed=1`, boot animation `stopped`, and
`com.android.settings/.FallbackHome` resumed. Both `com.android.launcher3` and
`net.frameo.frame` were disabled, as was `com.android.systemui`. Android had
booted but had no working home app.

The following commands enabled the bundled launcher and system controls and
set the frame to stay awake while powered:

```sh
/opt/homebrew/bin/adb -s HF4A62I77N shell "su -c 'pm enable --user 0 com.android.launcher3; pm enable --user 0 com.android.systemui; svc power stayon true; settings put system screen_off_timeout 2147483647'"
```

Launching HOME still selected `FallbackHome`. Explicitly starting
`com.android.launcher3/.Launcher` crashed with a `NullPointerException` calling
`IWallpaperManager.registerWallpaperColorsCallback` on a null service. The
bundled launcher also does not advertise the HOME category in its resolver
table. Enabling it alone does not provide a working home screen.

To clear the crash and show Android Settings:

```sh
/opt/homebrew/bin/adb -s HF4A62I77N shell 'am force-stop com.android.launcher3; am start -a android.settings.SETTINGS'
```

At 09:42 EDT, ADB verified:

| Check | Result |
| --- | --- |
| `getprop sys.boot_completed` | `1` |
| `pm list packages -d` | Only `net.frameo.frame` disabled |
| `settings get global stay_on_while_plugged_in` | `7` |
| `settings get system screen_off_timeout` | `2147483647` milliseconds |
| Resumed activity | `com.android.settings/.Settings` |
| Power state | `mWakefulness=Awake`, `mStayOn=true` |

A screenshot confirmed Settings replaced the startup loader. This is a
temporary working screen during the backup. HOME or a reboot may return to
the fallback screen while Frameo remains disabled. Reboot behavior and long
idle behavior have not been tested. No replacement OS has been flashed.

### Restore the Frameo interface if needed

Re-enabling Frameo may restore its scheduled power behavior. The following
rollback commands have not been run because Frameo is intentionally disabled
during the backup:

```sh
/opt/homebrew/bin/adb -s HF4A62I77N shell 'su -c "pm enable --user 0 net.frameo.frame"'
/opt/homebrew/bin/adb -s HF4A62I77N shell 'am start -a android.intent.action.MAIN -c android.intent.category.HOME'
```

The original power setting values were not captured before the changes, so an
exact rollback of those values is unavailable.

## 2026-10-15: boot preparation and offline backup

All named partition backups and both eMMC boot areas completed with hash
sidecars. The ADB full-disk transfer stopped at 16,601,169,007 bytes without a
completion message. Its `.part` file is retained, not accepted as a backup.
The process was no longer running when checked at about 10:13 EDT.

The live DTB was decompiled to `build/frame157-live.dts` using the kernel's
`scripts/dtc/dtc` in Docker volume `frame157-linux`. Vendor-tree warnings are
retained in the session output; this DTS is a reference, not a mainline input.
The Silead driver is bound at `1-0040`; `1-0041` has no driver. Runtime GPIO
and display state are saved in `backup/frame157/runtime-hardware.txt`.
The running VOP reports 152.6 MHz and timings H=1920/2060/2100/2240,
V=1080/1100/1110/1140. These differ from the bridge node's nominal timings.
RK915 firmware was copied from `/vendor/firmware/` to local `build/`.

Stock U-Boot strings show version 2017.09, built December 29, 2025. Its
environment includes `rkimgtest`, `mmc1 mmc0` boot targets, and extlinux support.
Android/FIT/Rockchip boot precedes the distro fallback, so these strings do not
prove SD will take priority. No SD card is currently enumerated by Android.

The user asked about soft buttons, then deprioritized that work. Temporary
`qemu.hw.mainkeys=0` and `persist.sys.navigationbar=1` probes were reset to empty.
SystemUI was restarted; dumping its service caused a null-pointer crash, which
was cleared with `am force-stop`. Settings was reopened. Inspection of the
vendor SystemUIApplication bytecode shows the startup loop skips `SystemBars`
and `PowerUI`; framework `config_showNavigationBar` is false. No navigation APK
was installed or firmware changed for this. The temporary Android build
container was stopped.

After `sync`, `adb reboot loader` entered Rockchip Loader mode successfully.
`rkdeveloptool ld` reports `2207:330d`, and `rfi` reports Samsung eMMC with
61,079,552 sectors (31,272,730,624 bytes). Direct LBA and first-4-MB access are
enabled. A read of sectors 0..8191 produced exactly 4,194,304 bytes and matched
the first 4 MB of the earlier ADB partial copy. GPT reports 16 partitions;
userdata ends at sector 61,079,487. This proves loader read access, not a tested
restore or forced maskrom entry.

`scripts/backup-loader.py` now reads 256-MiB chunks twice in loader mode and
accepts a chunk only when both SHA-256 hashes match. It verifies completed
chunks before resuming. It assembles and rehashes the full disk only after all
chunks pass. Output: `backup/frame157-loader/`; progress:
`backup/frame157-loader.log`. The old ADB partial remains untouched. Android
is stopped during this copy, so it cannot mutate mounted filesystems.

The frame remains in Loader mode while this backup runs. Do not reset it or
run another USB loader operation concurrently. On interruption, rerun:

```sh
python3 scripts/backup-loader.py
```

At 10:20 EDT, the first two chunks (512 MiB total) passed matching double
reads; the third chunk was active. An independent local rehash also verified
all 18 existing ADB backup files against their sidecars. Script checks using a
temporary fake loader exercised complete assembly, reuse of verified chunks,
retry after local chunk corruption, and rejection of differing device reads.
These checks passed. The full offline image remains incomplete.

Boot-source cross-check: the current upstream vendor
[`cmd/rkimgtest.c`](https://github.com/rockchip-linux/u-boot/blob/next-dev/cmd/rkimgtest.c)
reads sectors 64 and 65 and accepts specific IDB header signatures. This supports
the need for an SD selection header, but does not establish that this frame's
exact U-Boot build uses the same implementation. An extlinux filesystem alone
may therefore be insufficient to select SD. The source is saved locally as
`build/rkimgtest-vendor.c`; no header or SD image has been written to hardware.

At 10:26 EDT, 5,767,168 sectors (11 chunks, 2.75 GiB) passed double-read
verification and the next chunk was active. A read-only monitoring task watches
for backup completion and will independently check the assembled image's size
and hash; it does not issue USB commands.

The first-boot design review selected the minimal USB-console payload. The
decision, corrections and reviewer-provider limitation are recorded in
[boot-design.md](boot-design.md). Offline implementation is now in progress.
No Linux payload has booted on this frame yet.

The user connected a card described as 64 GB at `/dev/disk6`. macOS reports
that device as external/removable USB `STORAGE DEVICE`, with only 127,139,840
bytes (248,320 sectors), no filesystem and no partitions. No card write or
erase was attempted. Reseating/reconnecting the reader is pending before the
physical target can be accepted.

After reseating, `/dev/disk6` reports the expected capacity: 62,534,975,488
bytes (122,138,624 sectors), external removable USB `STORAGE DEVICE`. It has
an existing GPT with six Microsoft Basic Data partitions. The reader capacity
issue cleared. No erase/write has occurred; confirm the concrete image and
target before replacing this partition layout.

The user explicitly authorized wiping the card while the build runs. Rechecked
`disk6` as external/removable `STORAGE DEVICE`, exactly 62,534,975,488 bytes,
then ran `diskutil eraseDisk FAT32 FRAME157 MBRFormat /dev/disk6` successfully.
macOS now reports `FDisk_partition_scheme` with one `DOS_FAT_32` partition,
mounted at `/Volumes/FRAME157`, starting at sector 2048 (1 MiB). The previous
GPT and six-partition layout were replaced. This is a filesystem format, not
a secure overwrite of all old data sectors.

Direct raw-device inspection failed with permission denied; `sudo -n fdisk`
requires a password in this environment. Thus the MBR active flag and reserved
header bytes have not been independently read back. No bootloader/header has
been installed. This layout prepares the FAT/extlinux path; it does not prove
the stock U-Boot will select the card. The remaining image build/audit continues.

## 11:37 EDT — the loader-mode backup is invalid; do not flash it

The loader-mode backup reported completion: 117 of 117 chunks "read twice" and
verified, 31,272,730,624 bytes assembled at
`backup/frame157-loader/mmcblk2-full.img`, SHA-256 `02f74eb0…` matching its
sidecar on an independent rehash.

It is not a usable recovery image. A 4 KiB sample every 8 MiB finds **99.9% of
the file filled with `0xCC`**, the erased-state byte of this Samsung eMMC. Only
`uboot`, `trust`, `misc` and part of `resource` hold real data. `kernel`, `boot`,
`recovery`, `backup`, `cache`, `system` and `userdata` read back as erased
entirely. The GPT itself is intact and correct, and it shows partitions begin at
LBA 16384 rather than 0.

`boot` at LBA 139264 in that file is `cc cc cc …`; the same partition in the
earlier ADB backup is the real `ANDROID!` boot image.

The cause is the verification method, not the transport. `scripts/backup-loader.py`
read each chunk twice with `rkdeveloptool rl` and accepted it when both reads
matched. The device returned `0xCC` every time, so every chunk passed. Double-read
verification proves the USB link is stable. It cannot prove the device returned
its contents. Timing looked plausible throughout, so the duration was not a
signal either.

The file has been renamed `INVALID-mmcblk2-full.img`, the sidecar renamed to
match, and `backup/frame157-loader/INVALID-README.md` records the evidence. It
has not been deleted. **Flashing it would produce an unbootable frame.**

### The backup that is valid

`backup/frame157/`, the earlier ADB-level copy, is the recovery image that can be
trusted. All 18 files re-hash to their sidecars, and 13 of 14 partitions
cross-verify byte-for-byte against the independent ADB full-device dump read at
the correct GPT offsets. `oem` differs because Android was live when it was
captured. The ADB full-device dump is itself truncated at 15.46 GiB of 29.12 GiB,
so the per-partition dumps, not that file, are the usable form.

### Lesson to encode

A backup is verified only against evidence it cannot fabricate. A self-consistent
hash over self-consistent blank reads is not a backup. Any future device-side
read must assert that the payload contains known-good markers — the `ANDROID!`
header at the `boot` partition, the GPT signature at LBA 1, partition names at
LBA 2 — rather than only that two reads agree.

## 12:05 EDT — SD boot selection is resolved against the extlinux-only card

An independent review of the first-boot artifact examined the frame's own stock
U-Boot in `backup/frame157/uboot.img` rather than only the vendor source. Its
environment is decisive:

```text
rkimg_bootdev=if mmc dev 1 && rkimgtest mmc 1; then setenv devtype mmc; setenv devnum 1; echo Boot from SDcard;
               elif mmc dev 0; then setenv devtype mmc; setenv devnum 0; …
bootcmd=boot_android ${devtype} ${devnum};boot_fit;bootrkp;run distro_bootcmd;
```

`rkimgtest` reads sectors 64 and 65 and accepts only the IDB tags `0xFCDC8C3B`,
`0x534E4B52` or `0x534E5252` (`build/rkimgtest-vendor.c`). The first-boot image
leaves LBA 64 zeroed by design, so `rkimgtest mmc 1` fails, `devtype`/`devnum`
fall through to mmc 0, and `bootcmd` runs `boot_android` against eMMC. The
`distro_bootcmd` scan that would read `extlinux/extlinux.conf` comes after
`boot_android` and is never reached. U-Boot does contain
`scan_dev_for_boot_part`, but nothing routes to it while `boot_android` succeeds.

**The card as prepared will not boot.** This is now evidence about this frame's
own U-Boot binary, not an inference from vendor source. Adding a fabricated IDB
signature stays rejected: it would satisfy the test without describing anything
real about the card.

### Other review findings, for the record

- `scripts/audit-first-boot.sh` does not assert `CONFIG_USB_U_SERIAL`,
  `CONFIG_USB_F_ACM` or `CONFIG_USB_PHY`, and does not check the USB controller's
  `power-domains`, `phys` or assigned 480 MHz clock. All are correct today.
- Its `/init` check is syntactic: a much simpler init would also pass.
- The LBA 64 check reads 4 bytes rather than the full 512-byte sector.
- `build-kernel.sh` pins the kernel but not the `debian:trixie-slim` image digest.

### Evidence gathered that narrows the risk

- The USB gadget path in the compiled DTB is structurally correct: `usb@ff300000`
  is DWC2 in `dr_mode = "peripheral"`, `status = "okay"`, `phys` resolves to the
  enabled `u2phy@100/otg-port`, with the host port and EHCI/OHCI disabled.
- USB device mode is proven on this board, not assumed: stock Android enumerated
  the same controller as `dwc2 ff300000.usb` and macOS sees the frame as
  `2211:0012` / rockchip / `FRAME157`. Missing `vusb_a`/`vusb_d`/VBUS regulator
  warnings appear in stock dmesg too and are benign.
- All four payloads inside `frame157-first-boot.img` were read back out of the
  FAT filesystem and hash-match their sources; `Image` additionally verified
  byte-identical across all 80,109 clusters. The image still hashes to
  `749c172f…`.
- On stock Android, mmc0 (`ff370000`, the SD slot this DTS enables at 25 MHz) was
  initialised but no card was ever detected; mmc1 is the RK915 SDIO Wi-Fi and
  mmc2 is the eMMC. Whether the frame has a usable SD slot is untested — the
  stock dmesg shows `cd-gpios`/`wp-gpios` lookups failing for `ff370000`, which
  is consistent with a removable slot. One insert-and-boot test settles it.

Two read-only inspection tools were added under `build/tools/` (gitignored) to
settle these questions on a host without `dtc` or `mtools`:
`fdt-dump.py` (DTB with phandles resolved) and `fat-verify.py` (read and hash
files from a FAT filesystem inside an image). `fat-verify.py` still mis-walks
long FAT chains and should not be trusted for files above a few hundred KiB; the
kernel `Image` was verified by direct cluster comparison instead.
