# Recovery: restoring the stock firmware

The valid backup is the **per-partition ADB backup** in `backup/frame157/`
(`<name>.img` plus a `.sha256` sidecar for each partition). Two other images
must never be written:

- `backup/frame157-loader/` (`INVALID-mmcblk2-full.img`): taken in Loader
  mode, it is 99.9% `0xCC` filler. On this frame, Loader-mode reads past
  32 MiB return filler while reporting success. See
  [operations.md](operations.md).
- `backup/frame157/mmcblk2-full.img.part`: the ADB whole-disk copy, which
  stopped halfway.

Restore partition by partition, never as a whole disk.

## While Android still boots (the normal case)

Rewrite a partition from Android with root, checked against the backup:

```sh
scripts/write-partition.sh recovery backup/frame157/recovery.img
scripts/verify-partitions.sh             # every partition vs. its backup hash
```

## When Android does not boot: Loader mode

1. Enter Loader mode: hold the **UPDATE** button on the back of the board while
   connecting power (or run `adb reboot loader` while Android is up).
   `build/src/rkdeveloptool/rkdeveloptool ld` should report `Mode=Loader`.
2. Write the partitions that changed, for example:
   ```sh
   scripts/flash-partition.sh boot backup/frame157/boot.img
   ```
   This reads the GPT and refuses files bigger than the partition. Plain
   `rkdeveloptool wlx` does not check sizes, and an oversized file overwrites
   the next partition.
3. `build/src/rkdeveloptool/rkdeveloptool rd`, then once Android is up run
   `scripts/verify-partitions.sh`. Loader-mode reads can't be trusted for
   verification here, so verify from Android.

The BootROM is mask ROM. If `uboot`/`trust` were ever damaged, it falls back to
**maskrom** mode, where `rkdeveloptool db build/src/rkbin/rk3326_loader_v2.12.140.bin`
loads a USB loader before step 2. Nothing in this project writes `uboot`,
`trust`, or `mmcblk2boot0/1`.

## Earlier oversized flash

The two boot-image tests on 2026-10-15 flashed a 42,082,304-byte image to
`boot`, a 39,845,888-byte partition, with `rkdeveloptool wlx`, which does not
check sizes. Afterwards `scripts/verify-partitions.sh` found `recovery`, `boot`,
`kernel` and `resource` all matching the backup, so the overrun did not land.
Don't count on that next time: use `scripts/flash-partition.sh`.
