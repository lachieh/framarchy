# Root filesystem (Arch Linux ARM + Omarchy)

`scripts/build-rootfs.sh` builds `build/rootfs/frame157-rootfs.ext4` (ext4,
label `FRAME157ROOT`) in Docker from the verified ALARM aarch64 tarball:

- every package in `port/packages.txt`, plus sudo, openssh, git; no ALARM
  kernel (`linux-aarch64` is removed and ignored; ours is on the FAT partition)
- our kernel modules from `build/kernel/modules.tar.gz`
- user `frame` (uid 1000; wheel, video, input, audio, render, seat),
  **password `frame`**: change it with `passwd` after the first login.
  Passwordless sudo. Root is locked.
- Omarchy at the pinned commit, with `port/apply.sh` run offline. Three of its
  commands need a running session and run once at the first Hyprland start
  (`~/.local/bin/frame-first-session`).
- `frame-hyprland.service` starts the Omarchy session on tty1.
- USB console on the USB-C port (`frame-usb-gadget.service`): a serial login
  on `ttyGS0` (Mac: `/dev/cu.usbmodem*`) and a CDC-NCM network link `usb0`
  with IPv4 link-local + mDNS, so `ssh frame@frame157.local` works from the Mac.
- root grows to fill the SD partition on first boot (`x-systemd.growfs`).

It goes on the SD card's partition 2 (`/dev/mmcblk0p2`, created on the frame
with BusyBox fdisk: start sector 196608 to the end). From Android with root:

```sh
gzip -1 -c build/rootfs/frame157-rootfs.ext4 > build/rootfs/frame157-rootfs.ext4.gz
adb push build/rootfs/frame157-rootfs.ext4.gz /data/local/tmp/
adb shell su -c 'gunzip -c /data/local/tmp/rootfs.ext4.gz | dd of=/dev/block/mmcblk0p2 bs=1048576'
```

Rebuilding: the package install is the slow part. `IMAGE=<snapshot>` reuses a
`docker commit` of an earlier build container whose packages are installed.
