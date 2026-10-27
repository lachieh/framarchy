# FRAME157 first boot

This unit builds an offline diagnostic artifact: Linux v6.18, the minimal
FRAME157 device tree, a RAM-only BusyBox initramfs with one USB ACM console,
and a partitioned FAT image containing one extlinux entry. It does not install
anything, expose eMMC to Linux, mount block filesystems, reboot automatically,
or access the frame during construction.

## Build and audit

Docker must be running with ARM64 container support. The kernel source of truth
is the case-sensitive `frame157-linux` Docker volume at `/src/linux`; the host
checkout under `build/src/linux` is not used. Run:

```sh
scripts/build-kernel.sh 2>&1 | tee build/logs/first-boot/kernel-build.log
scripts/build-initramfs.sh 2>&1 | tee build/logs/first-boot/initramfs-build.log
scripts/build-first-boot.sh 2>&1 | tee build/logs/first-boot/artifact-build.log
```

The kernel script hard-resets only the dedicated source volume to Linux v6.18
commit `7d0a66e4bb9081d75c82ec4957c50034cb0ea449`, removes stale source products,
and builds only `Image` and `rockchip-rk3326-frame157.dtb`. It saves the merged
configuration, input hashes, toolchain provenance, the board-binding check, and
targeted `CHECK_DTBS` output. The display patch and driver are deliberately not
part of this first-boot dependency chain.

The initramfs script downloads Debian trixie's AArch64 `busybox-static`
`1:1.37.0-6+b9` package and requires SHA-256
`c833be48abfa16bc19c4966ec93e289ff1ce5d2f1476cad3a57bd105378cd15c`.
Provenance records its upstream BusyBox version, Debian source package, exact
binary package, archive URL, and `Built-Using` glibc version. All packaged
applets are installed; applets are not pruned. Only BusyBox, its links, `/init`,
and required empty directories enter the archive. `/init` mounts devtmpfs and
the proc, sysfs, and configfs
pseudo-filesystems; it creates one ACM gadget and executes a controlling-
terminal shell on `ttyGS0` after printing:

```text
FRAME157_FIRSTBOOT_OK kernel=<release> dt=rockchip-rk3326-frame157
```

The artifact script writes only
`build/frame157-first-boot/frame157-first-boot.img`. It never names or opens a
host physical disk. The FAT partition begins at LBA 2048, leaving LBA 64 empty.
No IDB marker, loader, or Rockchip header is included.

The final audit can also be repeated independently:

```sh
scripts/audit-first-boot.sh | tee build/logs/first-boot/offline-audit.log
```

It checks the compiled DT identity, exact RK809 input and regulator map, exact
I/O-domain supplies, SD at 25 MHz, USB peripheral mode, disabled eMMC/SDIO and
display, built-in kernel options, initramfs contents and init path, FAT image
paths, payload hashes, extlinux arguments, and schema logs. Outputs and evidence
are under:

- `build/kernel/`
- `build/initramfs/`
- `build/frame157-first-boot/`
- `build/logs/first-boot/`

Passing these checks establishes only `ArtifactReady` construction evidence.
It does not establish that this unit boots on FRAME157.

## Boot-selection limitation

The stock loader advertises extlinux scanning and `mmc1/mmc0` targets, but its
Android-first command flow may preempt removable-media scanning. The official
Rockchip `rkimgtest` implementation retained at `build/rkimgtest-vendor.c`
checks IDB signatures at SD LBA 64; that is evidence about the implementation,
not proof that this exact unit requires or accepts a loader there. Consequently
the artifact intentionally tests extlinux-only selection and does not invent a
signature or loader. A later controlled experiment may show that a separately
verified loader/header is required.

No hardware test belongs to this build unit. The current Loader-mode backup
must finish and its recovery evidence must be accepted before an attended
removable-media experiment. A blank display is expected because display is not
described. Boot success requires the host-observed ACM interface, the exact
marker, and an interactive shell; compilation alone is not boot evidence.

If a later attended experiment does not expose ACM, remove power and removable
media and preserve the observation. Do not repair, mount, or write eMMC from
this artifact.
