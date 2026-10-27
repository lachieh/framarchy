# FRAME157 hardware

Read from the running stock firmware over root ADB on 2026-10-15. Nothing was
written to the frame to collect this.

| Item | Value | Source |
| --- | --- | --- |
| Product | "DPF Frame 157", Frameo v1.29.16 (60080) | Settings → About |
| Board | C-Link `CL-RK3326-DP105F` V1.3, sticker `DP105F 1+32 2.4GWIFI M15R5 20251106` | PCB, [front](img/board-front.jpg) / [back](img/board-back.jpg) photos |
| Board chips seen | TWSC `TEMBG104T1.0` eMMC, Lontium `LT8911EXB`, Silead touch controller, Wi-Fi module with U.FL antenna | photos |
| Debug console | UART2 at 1,500,000 baud on labelled GND/RX/TX pads (also SD DAT0/DAT1); see [debug-uart.md](debug-uart.md) | PCB silkscreen, live DT, U-Boot PX30 pin-mux |
| Buttons | PWR, RST, UPDATE (Rockchip recovery key → Loader mode), ESC/LEFT/UP/DOWN/PLAY | PCB silkscreen |
| Connectors | USB-C, USB-A host, DC jack, 3.5 mm audio, full-size SD, MIPI, eDP, LVDS, TP-COB, IR/UART, PIR, SPK-L/R | PCB silkscreen |
| USB | `2211:0012`, manufacturer "rockchip", product `FRAME157`, serial `HF4A62I77N` | macOS System Information |
| SoC | Rockchip RK3326, 4x Cortex-A35 (CPU part `0xd04`, ARMv8) | `/proc/cpuinfo`, `ro.board.platform` |
| RAM | 1 GB (`MemTotal: 973968 kB`) | `/proc/meminfo` |
| Storage | 32 GB eMMC, `mmcblk2` on `dwmmc@ff390000`, 31,272,730,624 bytes | `/proc/partitions`, `blockdev` |
| Stock OS | Android 8.1, 32-bit userspace (`armeabi-v7a`), kernel 4.4.138 | `getprop`, `uname` |
| Fingerprint | `rockchip/rk3326_32bit/rk3326_32bit:8.1.0/OC/150203:user/release-keys` | `getprop` |
| Vendor DT | model "Rockchip rk3326 ai voice assistant evb v11 board", compatible `rockchip,rk3326-evb-ai-va-v11` | `/sys/firmware/devicetree` |
| Display | 1920x1080, density 170; DSI (`dsi@ff450000`) into a Lontium LT8911EXB DSI→eDP bridge on i2c-2 `0x29` | `wm size`, i2c devices |
| PMIC | RK809 on i2c-0 `0x20` | i2c devices |
| RTC | HYM8563 on i2c-1 `0x51` | i2c devices |
| Touch | Silead `gslX680-pad` bound at i2c-1 `0x40`, input `event2`; Ilitek node at `0x41` is unbound. DT firmware name `Kingvina_FG1509_2_GSL3676_HuiY` | `/proc/bus/input/devices`, driver symlinks, live DT |
| Accelerometer | DT nodes for sc7a20 `0x18`, mir3da `0x27`, mc3230 `0x4c` (auto-detect list) | i2c devices |
| Wi-Fi | Rockchip RK915 SDIO, module `rk915.ko`, SDIO ID `0296:5348` | `lsmod`, `/sys/bus/sdio` |
| GPU | Mali-G31 (Bifrost), vendor `mali_kbase.ko` | `/vendor/lib/modules` |
| Root | `/system/xbin/su` gives uid 0; SELinux permissive | `su 0 id` |

## eMMC layout

Standard Rockchip GPT. Sizes in KiB from `/proc/partitions`.

| Partition | Device | Size |
| --- | --- | --- |
| uboot | mmcblk2p1 | 4096 |
| trust | mmcblk2p2 | 4096 |
| misc | mmcblk2p3 | 4096 |
| resource | mmcblk2p4 | 16384 |
| kernel | mmcblk2p5 | 32768 |
| boot | mmcblk2p6 | 38912 |
| recovery | mmcblk2p7 | 71680 |
| backup | mmcblk2p8 | 114688 |
| security | mmcblk2p9 | 4096 |
| cache | mmcblk2p10 | 393216 |
| system | mmcblk2p11 | 1572864 |
| metadata | mmcblk2p12 | 16384 |
| vendor | mmcblk2p13 | 393216 |
| oem | mmcblk2p14 | 131072 |
| frp | mmcblk2p15 | 512 |
| userdata | mmcblk2p16 | 27733472 |

Also present: `mmcblk2boot0`, `mmcblk2boot1` (4 MiB each) and `mmcblk2rpmb`.

## Enabling ADB

Settings → About → enable the Beta program, then toggle ADB. Connect with a
USB-A → USB-C data cable. The first connection needs "Allow USB debugging" on
the frame; on this unit the prompt only appeared after ADB was toggled off and
on again.
