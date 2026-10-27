# 01: RK3326 Frameo frame hardware research for mainline Linux and Arch Linux ARM (aarch64)

Researched 2026-10-15. Mainline Linux `master` was 7.3-rc7 (torvalds/linux @ `0fcb05b72344`).
Confidence: **H** = verified in primary source code or docs, **M** = strong indirect evidence, **L** = inference or unverified.

Device under study: RK3326, 1 GB RAM, 32 GB eMMC (`emmc` @ ff390000, mmcblk2). Vendor DT is `rockchip,rk3326-evb-ai-va-v11`. The display path is DSI → LT8911EXB (i2c-2 0x29) → eDP 1920x1080. The device also has an RK809 PMIC, RK915 SDIO Wi-Fi, and GSL/Ilitek touch.

---

## TL;DR go/no-go

| Area | Status | Risk |
|---|---|---|
| SoC, eMMC/SD, USB OTG, RK809 regulators and codec, VOP, DSI, Panfrost | Mainline, used daily by ROCKNIX on kernel 7.1.2 | Low |
| **LT8911EXB DSI→eDP bridge** | **No mainline driver and no lore series found.** Only a 2019 out-of-tree fbdev-era i2c driver and vendor BSP copies exist | **High. This is the display blocker; you must write a DRM bridge/panel driver** |
| **RK915 Wi-Fi** | Out-of-tree mac80211 port builds on 6.19/7.1. It is 2.4 GHz only and unstable under sustained RX; the original porter abandoned it in Oct 2026 | **High. Plan on USB Wi-Fi via OTG or a USB hub as the fallback** |
| Touch | Mainline drivers exist for both. Silead needs firmware extracted from Android | Low-Med |
| Boot | BootROM prefers eMMC. Stock vendor U-Boot *may* boot SD via `rkimgtest` + `distro_bootcmd`. Mainline U-Boot + TF-A fully open for PX30/RK3326 | Med |
| Prior art | None found for a Frameo RK3326 or the `evb-ai-va` board on mainline | Info |

---

## 1. Mainline Linux status for RK3326/PX30

### 1.1 SoC dtsi (H)
- `arch/arm64/boot/dts/rockchip/px30.dtsi` contains the following nodes:
  - `dsi: dsi@ff450000` (`"rockchip,px30-mipi-dsi", "snps,dw-mipi-dsi"`)
  - `dsi_dphy: phy@ff2e0000` (`rockchip,px30-dsi-dphy`)
  - `gpu: gpu@ff400000` (`"rockchip,px30-mali", "arm,mali-bifrost"`)
  - `usb20_otg: usb@ff300000` (dwc2, `dr_mode = "otg"`)
  - `vpu`, `lvds`, `isp`, `rga`, and vop-big/vop-lit
  - Source: https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/rockchip/px30.dtsi
- `arch/arm64/boot/dts/rockchip/rk3326.dtsi` includes px30.dtsi, deletes `vopl` (RK3326 has only VOP-big), and routes `display_subsystem` to `vopb_out`. **Use rk3326.dtsi, not px30.dtsi.**
- **PX30S/RK3326S caveat (M):** ROCKNIX carries patches for the newer "S" silicon revision, which has a different DSI D-PHY timing table, a GPU power-domain workaround, tsadc changes, and others. Examples are `025-px30s-dsi-dphy-timing-table.patch` and `026-px30s-cpuinfo-soc-detection.patch` in https://github.com/ROCKNIX/distribution/tree/next/projects/ROCKNIX/devices/RK3326/patches/linux (ROCKNIX `next` @ `5a0e41634ed4`). The S revision is detected by DDR_GRF_BASE1 bits [15:14] = 0b11. Our frame runs Android 8.1 on BSP kernel 4.4, which predates PX30S BSP support (2021+ in 4.19). That makes it *likely* (M/L) a plain RK3326. **Verify this.** The PX30S DPHY patch is required for DSI if the chip turns out to be an S revision.

### 1.2 Display: VOP + DSI (H)
- The VOP is `drivers/gpu/drm/rockchip/rockchip_vop_reg.c` (px30 vop big/lit). The DSI host is `drivers/gpu/drm/rockchip/dw-mipi-dsi-rockchip.c` (px30 compatible), and the D-PHY is `drivers/phy/rockchip/phy-rockchip-inno-dsidphy.c`. All three are mainline. In-tree boards that drive DSI panels with them include odroid-go2, anbernic rg351m/v, gameforce-chi, px30-evb, and px30-cobra.
- **Bandwidth (M):** 1920x1080@60 with a CEA pixel clock of 148.5 MHz and 24 bpp needs about 891 Mbit/s per lane on 4 lanes. The PX30 Inno D-PHY is a 1 Gbit/s-class PHY (the ROCKNIX PX30S patch describes base PX30 as "1GHz-capable"), so the link fits but has little margin. Use the vendor timings from the frame DT; the aystshen example uses a 152 MHz pclk.

### 1.3 GPU: Panfrost + Mesa (H)
- The kernel uses `drivers/gpu/drm/panfrost` and matches `arm,mali-bifrost`. Panthor is for CSF GPUs and is not relevant here. The node is in px30.dtsi; board DTS must enable `&gpu` with `mali-supply`, as px30-evb.dts does.
- Mesa: https://docs.mesa3d.org/drivers/panfrost.html lists G31 in the Bifrost v7 row as GLES 3.1, GL 3.1, Vulkan 1.3 (PanVK), and OpenCL 3.0. G31 itself is not in the Khronos conformance submission; that footnote belongs to G52.
- ROCKNIX RK3326 ships `GRAPHIC_DRIVERS="mali panfrost"`, `DISPLAYSERVER="wl"`, and `WINDOWMANAGER="swaywm-env"`. This means a wlroots/sway Wayland compositor already runs on Panfrost on this SoC (`projects/ROCKNIX/devices/RK3326/options`) (H).

### 1.4 RK809 PMIC + codec (H)
- `drivers/mfd/rk8xx-core.c`: `case RK809_ID: case RK817_ID:` uses the `rk817s[]` cell table. That table includes `rk808-regulator`, `rk808-rtc`, `rk805-pwrkey`, `rk808-clkout`, **`rk817-codec`**, and `rk817-charger`. RK809 therefore gets the codec cell; it has no charger, so expect that cell to fail or not bind harmlessly (M).
- The codec driver is `sound/soc/codecs/rk817_codec.c` (platform driver `rk817-codec`). The audio card is simple-audio-card on i2s. The BSP DT for this board uses `compatible = "rockchip,rk809-codec", "rockchip,rk817-codec"` (rockchip-linux/kernel develop-4.4 `rk3326-evb-ai-va-v11.dts` L601).
- In mainline, the RK809 regulator and PMIC node example is `px30-evb.dts` (`rk809: pmic@20`).

### 1.5 eMMC/SD/SDIO (H)
- `dw_mmc-rockchip` drives `sdmmc` (ff370000), `sdio` (ff380000), and `emmc` (ff390000). See px30-evb.dts for `emmc_pwrseq`, `sdio_pwrseq`, and aliases.

### 1.6 USB OTG gadget (H/M)
- dwc2 @ ff300000 with `u2phy_otg` is mainline. ROCKNIX carries several dwc2 gadget and role-switch robustness fixes, for example `003-usb-dwc2-gadget-fix-null-deref-on-register-restore.patch`, `010-dwc2-track-vbus-supply-state.patch`, and `038-dwc2-no-pullup-on-id-change-without-gadget.patch`. Gadget mode works in general; borrow those patches if you hit role-switch or VBUS bugs (M).
- Host mode on the same port is how a USB Wi-Fi fallback would attach (see §3).

### 1.7 Which kernel version (M/H)
- **ROCKNIX builds RK3326 on mainline 7.1.2** (`projects/ROCKNIX/packages/linux/package.mk`: `RK3326|AMD64) PKG_VERSION="7.1.2"`). It uses about 26 RK3326-specific patches, mostly for handheld input, panels, and PX30S support.
- Recommendation: target **6.18 LTS** or the current **7.1.y/7.2.y stable**. The RK915 port is tested on 6.19 and 7.1, which points to 7.1.y. Arch Linux ARM's `linux-aarch64` is a mainline kernel, but you will need a custom kernel package for the bridge driver, the RK915 out-of-tree module, and the DTB.

### 1.8 Reference board DTS to start from (H for existence, M for recommendation)
In mainline `arch/arm64/boot/dts/rockchip/`: `rk3326-odroid-go2{,-v11}.dts`, `rk3326-odroid-go3.dts`, `rk3326-odroid-go.dtsi`, `rk3326-anbernic-rg351m{.dts,.dtsi}`, `rk3326-anbernic-rg351v.dts`, `rk3326-gameforce-chi.dts`, `px30-evb.dts`, `px30-engicam-*`, `px30-firefly-jd4-*`, `px30-ringneck-*`, `px30-cobra-*`, `px30-pp1516-*`.

**Recommended base:** `px30-evb.dts` structure on top of `rk3326.dtsi`. It is the closest relative of the BSP `rk3326-evb-ai-va-v11`: RK809 at i2c0 0x20, eMMC with `mmc-pwrseq-emmc`, SDIO Wi-Fi with `mmc-pwrseq-simple`, DSI panel, PWM backlight, and the GPU enabled. Take pinctrl, regulator voltages, and GPIOs from the **frame's own vendor DT**. Odroid-go2 is a secondary reference for RK3326-specific bits such as the RK817 codec card and DSI panel on rk3326.dtsi, but it has no eMMC.

**Action:** dump the frame's live DT (`/proc/device-tree`, or decompile the `resource` partition DTB with `dtc -I fs`/`-I dtb`). It is the authoritative source for every GPIO, regulator, LT8911EXB timing, and Wi-Fi pin. A public copy of the closely related BSP DTs exists at https://github.com/rockchip-linux/kernel/blob/develop-4.4/arch/arm64/boot/dts/rockchip/rk3326-evb-ai-va-v11.dts. That file has an ST7703 720x1280 DSI panel and AP6255 Wi-Fi, so the frame's DT differs in the display and Wi-Fi nodes. Variants are also at https://github.com/54shady/qop_kernel/tree/master/arch/arm64/boot/dts/rockchip (`rk3326-evb-ai-va-v11-linux.dts`).

---

## 2. LT8911EXB (MIPI-DSI → eDP)

### 2.1 Mainline: none (H)
- Mainline `drivers/gpu/drm/bridge/Kconfig` (7.3-rc7) has LT8912B, LT9211, LT9611, LT9611UXC, and LT8713SX, but **no LT8911/LT8911EXB**.
- Web searches of lore mirrors (lkml.iu.edu, ratatoskr.run, freedesktop dri-devel archives) found **no posted LT8911EXB series**. Recent Lontium upstreaming covers other parts: LT7911EXC eDP→DSI v16 (Jul 2026), LT9611C v7, and LT9211C folded into lt9211.c. lore.kernel.org itself sits behind an Anubis bot wall and could not be queried directly. Confidence that no series exists: **M/H**.
- The Rockchip BSP kernels (rockchip-linux/kernel `develop-4.4/4.19/5.10/6.1`) have **no** lt8911 file under `drivers/gpu/drm/bridge/` (H). The frame's driver is therefore an ODM addition.

### 2.2 Open sources to port from
1. **aystshen/lontium_lt8911exb_driver** (https://github.com/aystshen/lontium_lt8911exb_driver, single push 2019-03-06, `lt8911exb/lt8911exb.c` 948 lines). (H)
   - It is a plain i2c driver meant for `drivers/video/`, from the Rockchip Android era. It is *not* a DRM bridge.
   - License is muddled: `MODULE_LICENSE("GPL V2")`, GPL text in the README body, and Apache-2.0 in the README footer.
   - DT schema, which very likely matches the frame's vendor DT (L/M):
     ```
     lt8911exb@29 { compatible = "lontium,lt8911exb"; reg = <0x29>;
       power-gpio = <...>; reset-gpio = <...>;
       lontium,pclk = <152000000>; lontium,hact = <1920>; lontium,vact = <1080>;
       lontium,hbp/hfp/hs/vbp/vfp/vs = ...;
       lontium,mipi_lane = <4>;  lontium,lane_cnt = <2>;  /* eDP lanes */
       lontium,color = <1>;      /* 0:6bit 1:8bit */
       lontium,test = <0>; };    /* 1 = internal test pattern, no MIPI input needed */
     ```
   - The README notes:
     - The I2C address is 0x29 when S_ADR is low and 0x2d when it is high.
     - **I2C must be ≤100 kHz.**
     - Reset is driven low for 100 ms, then high for 100 ms.
     - **Initialize the chip only after the DSI video stream is running.**
   - The register writes include `0x00 = mipi_lane % 4` (lane count) and `0x1a = lane_cnt` (eDP lanes). The chip performs eDP link training itself, sequenced by the host's register writes.
2. **Debug notes** (CSDN mike8825, https://blog.csdn.net/mike8825/article/details/105939211) (M):
   - The aystshen driver's burst-mode settings were unstable for that author; they recommend the Lontium FAE driver instead.
   - Enable EoTp, disable SSC, keep the backlight off during init, and initialize after the display controller is up.
   - Use `lontium,test=1` to validate the panel, backlight, and power independently of DSI. **This is very useful for bring-up.**
3. **Vendor DRM-era copies** (L, not inspected): the SpacemiT K1 BSP `linux-6.6/drivers/gpu/drm/spacemit/lt8911exb.c`, described as an "lt8911exb mipi dsi to eDP panel driver" (https://docs.bit-brick.com/docs/k1/software/peripheral_driver/Display, source at https://gitee.com/bianbu-linux), and a StarFive JH7110 SDK menuconfig entry (https://doc-en.rvspace.org/JH7110/DevKit/eDP/JH7110_DevKit_QSG/DG/kernel_menu_configuration_edp.html). These may be closer to modern DRM APIs.
4. **The frame itself** is the best reference. The Android 4.4 kernel has the exact init sequence the ODM shipped, either built in or as a module. Check `/sys/bus/i2c/devices/2-0029/driver`, `/proc/device-tree/.../lt8911*`, and `lsmod`. If it is built in, the init tables can be recovered from the boot image with strings/disassembly as a last resort.
5. NXP i.MX93 thread (https://community.nxp.com/t5/i-MX-Processors/iMX93-LT8911exb-MIPI-to-eDP-using-LT8911exb/td-p/2102708): DSI host → LT8911EXB needs OF-graph endpoints, and NXP recommends `panel-edp` downstream. It also shows the -517/-19 attach pitfalls (M).

### 2.3 What a mainline driver needs (M)
- **Two driver options:**
  - **Quick route:** a `drm_panel` + `mipi_dsi_driver` that sits on the DSI bus, takes fixed 1920x1080 timings from DT, and does the LT8911EXB I2C init in `.enable`, after DSI HS video starts. It is the fastest path to pixels.
  - **Proper route:** a `drm_bridge` (`drivers/gpu/drm/bridge/lontium-lt8911exb.c`) modelled on `lontium-lt8912b.c`/`lontium-lt9611.c`. It is an I2C client that registers a `mipi_dsi_device` on the DSI host via OF graph, with `next_bridge` → `panel-edp`/`panel-simple` holding the eDP panel mode.
- **DT inputs:** `reset-gpios` (active-low per the vendor sequence), the power/enable GPIO and/or regulator (`power-gpio`, vdd 1.8 V/3.3 V), DSI lanes (very likely 4), eDP lanes (likely 2), 8-bit colour, panel timings, and the backlight PWM plus a backlight-enable GPIO.
- **Ordering constraint:** the bridge must be configured after the DSI video stream starts. In the bridge model that means `atomic_enable`, or using `pre_enable_prev_first`.
- **DSI mode flags:** video, sync-pulse/burst per vendor (burst was reported unstable), EoTp enabled, and `MIPI_DSI_CLOCK_NON_CONTINUOUS` probably off.
- **Effort estimate:** about 400–700 lines plus a binding. It is upstreamable.

---

## 3. RK915 Wi-Fi

### 3.1 Mainline: none (H)
The RK915 is a Seekwave SV6160-family SoftMAC chip rebranded by Rockchip, per codeberg aenertia/sv6160-rk915 (M).

### 3.2 Out-of-tree options
| Source | Status | Kernel | Notes |
|---|---|---|---|
| https://github.com/rei512/rk915 (`87e2a4060af3`, 2026-09-30) | **Best current** | builds on 6.19; quirks patch for 6.19 and 7.1 | mac80211; SDIO IDs **0296:5347 and 0296:5348** (ours is 0296:5348, so it matches); 2.4 GHz only; STA (+P2P client untested). Needs `docs/mainline-linux-{6.19,7.1}-rk915-quirks.patch` (MMC card quirks), `CONFIG_PWRSEQ_SIMPLE`, `CONFIG_RESET_GPIO`. Known issue: sustained RX of tens of MB triggers repeated firmware error recovery. |
| https://github.com/stolen/rk915 (`590fe1dd3fa9`, 2025-07-08) | Original port, "not usable yet" | 6.12.29 | Disconnects after association; unload hangs. Vendor BSP patch in `docs/0001-rk915.patch`. **The author said on 2026-10-10 in ROCKNIX PR 3252 that he abandoned rk915 work.** |
| ROCKNIX PR 3252 (https://github.com/ROCKNIX/distribution/pull/3252) | Open, changes requested, labelled ai-generated | 7.1 | Adds `035-rk915-mmc-quirks.patch`: short CISTPL_FUNCE, continuous card clock, and no CMD52 while DAT busy, matched on the `rockchip,rk915` card node. Ships a module-reload watchdog. Author says traffic >~20 kB/s "causes WiFi chip to barf"; later rei512 commits claim the recovery latch fix. |
| https://codeberg.org/aenertia/sv6160-rk915 | Clean-room rewrite, **no association yet** | 6.18+ | Last activity 2026-09-05. Requires a dw_mmc host patch. |

Confidence on status: H, since the information comes from the READMEs and the PR.

### 3.3 Firmware (H)
- The driver needs `rk915_fw.bin` and `rk915_patch.bin`, installed at `/lib/firmware/rockchip/`. Copies are in rei512/rk915 `firmware/rockchip/`; they are vendor blobs with no licence statement.
- The frame's Android vendor or system partition almost certainly has the matching pair. Extract them from your backup and compare hashes (M).

### 3.4 DT needs (H/M)
On the `&sdio` node: `mmc-pwrseq` (reset/enable GPIO, plus RK809 clkout 32 kHz like the BSP `sdio_pwrseq`), `non-removable`, `keep-power-in-suspend`, and a child `wifi@1 { compatible = "rockchip,rk915"; interrupts = <host-wake GPIO> }`. **The host-wake GPIO must be correct because RX is interrupt-driven.** See `docs/mainline-linux-dts-example.dtsi` and `docs/rockchip,rk915.yaml` in rei512/rk915.

### 3.5 Verdict and fallback
**Treat on-board Wi-Fi as best-effort.** It is fine for low-rate use such as NTP, small syncs, or SSH. It is not reliable for photo sync of tens of MB.

Fallback options:
- **USB Wi-Fi on the OTG port in host mode**, via a USB-C/micro-USB OTG adapter and a powered hub if you also need gadget/power. Pick a mainline in-kernel chipset:
  - mt7601u, or mt76x2u/mt7612u, or mt7921u (firmware in linux-firmware);
  - or rtl8xxxu / rtw88 USB (RTL8821CU/8822BU) on ≥6.2.
- Check the frame's power budget, and whether the USB port is data-capable and wired for VBUS out. Many frames have only a power-only barrel jack plus a single data USB port (M).
- If the device has a free USB host header or an EHCI port (`usb_host0_ehci` exists in px30.dtsi), that is an alternative internal mod (L).

---

## 4. Touch

| Driver | File | DT compatibles | Firmware | Address |
|---|---|---|---|---|
| Silead GSL | `drivers/input/touchscreen/silead.c` | `silead,gsl1680`, `gsl1688`, `gsl3670`, `gsl3675`, `gsl3692` | **Required.** Loads `silead/<firmware-name>`, or by default `silead/<id>.fw`. Must be converted from the Android vendor driver's header/table or extracted from the vendor blob, using tooling and collections at https://github.com/onitake/gsl-firmware (`dbaac009452f`). Also set `touchscreen-size-x/y`, `silead,max-fingers`, and `power-gpios` | 0x40 |
| Ilitek ILI213x/23xx/25xx | `drivers/input/touchscreen/ilitek_ts_i2c.c` | `ilitek,ili2130/2131/2132/2316/2322/2323/2326/2520/2521` | none | 0x41 |
| Ilitek ILI210x/2117/2120/251x | `drivers/input/touchscreen/ili210x.c` | `ilitek,ili210x`, `ili2117`, `ili2120`, `ili251x` | none | 0x41 |

Confidence: H for drivers and compatibles (mainline source); M for the address mapping.

**How to pick (H/M):**
1. On Android, find the bound driver: `ls -l /sys/bus/i2c/devices/1-0040/driver /sys/bus/i2c/devices/1-0041/driver`. Then check `getevent -p` for the input device name, `dmesg | grep -i -E 'gsl|ilitek'`, and `i2cdetect -y 1` (unpopulated devices NACK). On Linux, `i2cdetect -y -r 1` gives the same answer.
2. **If it is GSL:** the Android driver embeds a panel-specific firmware table, usually in `gslX680.c`/`gsl_point_id` or a `.h` compiled into the kernel or module. Extract it from the 4.4 kernel image/module and convert it with gsl-firmware tools. The sibling ormarch PF1007L project in `vendor/` already did exactly this for an A33 frame (`PF1007L_TOUCH_FIRMWARE=gsl_m86_hd.fw`, `image/vendor/README.md`), which proves the workflow (H).
3. **If it is Ilitek:** start with `ilitek_ts_i2c.c`, which supports the newer ILI2xxx protocol 6, and fall back to `ili210x.c` if the firmware-version read fails.
4. The frame is a dual-sourced design, and either or both nodes may be enabled in a mainline DT. A non-responding device just fails its probe. Enabling both is acceptable for bring-up but not for the final DT (M).

---

## 5. Boot

### 5.1 BootROM order (M)
- Rockchip BootROM order is fixed: **SPI NOR/NAND → eMMC (NAND) → SD → USB maskrom**. There is no strap to change it. Sources:
  - 3mdeb, https://blog.3mdeb.com/2021/2021-12-03-rockchip-secure-boot/
  - megi's rk2aw ("SPI NOR flash -> eMMC -> SD card"), https://xnux.eu/rk2aw/. rk2aw itself supports only RK3399/RK3566/RK3588, not RK3326.
- RK3326 is confirmed to boot from SPI (U-Boot list, Jonas Karlman, 64 KiB offset).
- The IDB/loader is read starting at sector 64 (32 KiB), which is what vendor `rkimgtest` reads, with backup copies at further offsets.
- **Consequence:** with a valid loader on eMMC, the BootROM never looks at SD. SD boot needs one of these:
  - (a) the vendor U-Boot on eMMC choosing SD (§5.2);
  - (b) invalidating the eMMC IDB, after which the BootROM falls through to SD;
  - (c) maskrom.
- Maskrom entry, per https://opensource.rock-chips.com/wiki_Rockusb (H): short eMMC CLK to GND at power-on, or erase the bootable region.
- **Easier non-destructive route (M):** `adb reboot loader` (or `reboot bootloader` on some builds) enters Rockchip **Loader/rockusb** mode in vendor U-Boot. rkdeveloptool can then read and write the whole eMMC (`rl`/`wl`/`ppt`) without opening the case.

### 5.2 Stock Rockchip U-Boot (2017.09 next-dev) booting extlinux from microSD (M)
- In rockchip-linux/u-boot `next-dev` (`1c535d65b850`), `include/configs/rockchip-common.h` contains the following:
  - `rkimg_bootdev`: `if mmc dev 1 && rkimgtest mmc 1; then setenv devtype mmc; setenv devnum 1; echo Boot from SDcard; elif mmc dev 0; ...`
  - `RKIMG_BOOTCOMMAND` = `boot_android ${devtype} ${devnum}; boot_fit; bootrkp; run distro_bootcmd;`
  - `BOOT_TARGET_MMC` = `mmc 1` (SD) then `mmc 0`.
- `cmd/rkimgtest.c` succeeds if sector 64 of the SD card holds an IDB magic: `0xFCDC8C3B` (RC4 legacy), `RKNS`, or `RKSS`.
- **Implication:** an SD card with a valid IDB at sector 64 (for example a mainline-built `idbloader.img`) but *no* Android `boot`/`kernel` partitions will cause the following sequence:
  1. Vendor U-Boot selects SD.
  2. `boot_android`, `boot_fit`, and `bootrkp` fail.
  3. **`distro_bootcmd` scans mmc 1 and boots `/extlinux/extlinux.conf`.**
- **Caveats:**
  - `rkimgtest` was added in 2019. The frame's Android 8.1 U-Boot may predate it, and the ODM may have customised bootcmd. Check by running `strings uboot.img | grep -E 'rkimgtest|distro_bootcmd|Boot from SDcard|extlinux'` on the dumped `uboot` partition, or watch the UART console (L/M).
  - If the IDB TAG field at +104 is zero, the env adds `sdfwupdate` to bootargs. A normal mainline idbloader is unaffected as far as is known (L).
  - The vendor U-Boot's `booti` should boot a modern arm64 `Image` with an explicit `FDT`. Older vendor builds may need `Image` uncompressed and a DTB loaded at a sane address (M).
- **Backup issue:** `backup/backup.log` records the frame-side hash of `uboot.img` as `e3b0c44298fc...b855`. **That is the SHA-256 of empty input**, so the on-device read produced 0 bytes. The script is reading or hashing the wrong thing, for example a by-name symlink not followed, or permissions. It is not a corrupted transfer. Fix this before trusting any loader backup.

### 5.3 Mainline U-Boot for RK3326 (H)
- **Defconfigs:**
  - `configs/odroid-go2_defconfig` (`DEFAULT_DEVICE_TREE="rockchip/rk3326-odroid-go2"`, `SPL_ATF`, `TPL_RAM`/`SPL_RAM`, `MMC_DW_ROCKCHIP`, `CMD_ROCKUSB`, `SPL_PMIC_RK8XX`, env in MMC/SPI);
  - `evb-px30_defconfig`, `firefly-px30_defconfig`, `px30-core-*`, `ringneck-px30`.
  - The docs (`doc/board/rockchip/rockchip.rst`) list rk3326: ODROID-GO Advance and px30: EVB, Engicam, Firefly, and Ringneck.
- **DDR init is open source:** `drivers/ram/rockchip/sdram_px30.c` is the TPL DDR driver, so **no rkbin DDR blob is needed** for mainline U-Boot (H). It supports DDR3/DDR4/LPDDR2/LPDDR3, which needs checking against the frame's DRAM type (M).
- **TF-A is open source:** `plat/rockchip/px30/` exists in upstream TF-A (H). Build with `make PLAT=px30 bl31` and `export BL31=.../build/px30/release/bl31/bl31.elf`. The rkbin `rk3326_bl31_v1.37.elf` also works.
- A new board defconfig plus DTS is needed. Copy `odroid-go2_defconfig`, point it at the new DT, and drop the SPI flash and go2 ADC-key bits. Display in U-Boot is optional and can be skipped, since an LT8911EXB in U-Boot is not worth it.
- **ROCKNIX reference:** ROCKNIX builds U-Boot **v2025.10** with its own `rk3326-handheld_defconfig` and rkbin `rk3326_miniloader_v1.40.bin`, `rk3326_bl31_v1.34.elf`, `rk3326_ddr_333MHz_v2.11.bin` (`projects/ROCKNIX/devices/RK3326/packages/u-boot/package.mk`). It also has a `u-boot-legacy` dependency, so they hedge with blobs (H).
- **rkbin files** (rockchip-linux/rkbin `3e288fe814e0`, `bin/rk33/`):
  - `rk3326_ddr_333MHz_v2.12.bin`, `rk3326_miniloader_v1.40.bin`, `rk3326_usbplug_v1.42.bin`, `rk3326_bl31_v1.37.elf`, `rk3326_bl32_v2.21.bin`, plus `px30_*` equivalents. RK3326 and PX30 blobs are *not* interchangeable by name; use `rk3326_*`.
  - `RKBOOT/RK3326MINIALL.ini` → `boot_merger` produces **`rk3326_loader_v2.12.140.bin`**. Its parts are 471 = `rk3326_ddr_333MHz_v2.12.bin`, 472 = `rk3326_usbplug_v1.42.bin`, and FlashData/FlashBoot = ddr + `rk3326_miniloader_v1.40.bin`.
  - This loader is the file to pass to `rkdeveloptool db` in maskrom.

### 5.4 Maskrom recovery with rkdeveloptool on macOS arm64 (M)
- **Building:**
  - Upstream is https://github.com/rockchip-linux/rkdeveloptool. Homebrew-core has **no** `rkdeveloptool` formula (formulae.brew.sh API returned nothing; `rkflashtool` 6.1 exists).
  - The common route is the third-party tap `brew tap IgorKha/rkdeveloptool && brew install rkdeveloptool`, as recommended in Radxa docs (https://docs.radxa.com/en/rock3/rock3b/low-level-dev/maskrom/mac-os).
  - To build from source: `brew install automake autoconf libusb pkg-config; autoreconf -i; ./configure; sed -i '' 's/int nSectorSize = 512;/const int nSectorSize = 512;/' main.cpp; make`. The sed works around a clang VLA error. Homebrew libusb has arm64 bottles.
  - Use plain `make`, since macOS has no `nproc`.
  - Reports agree it works on Apple Silicon (M).
- **Flow:**
  1. Run `rkdeveloptool ld` to list devices.
  2. Run `rkdeveloptool db rk3326_loader_v2.12.140.bin` to load the usbplug into RAM (maskrom only).
  3. Run `rkdeveloptool rfi` or `ppt` to check flash info, then `rl 0 <sectors> full.img` to back up.
  4. Run `wl 64 idbloader.img` (or `ul` the loader) and `wl <lba> image` to write.
  5. Run `rd` to reset.
- In vendor Loader mode (from `reboot loader`), skip `db`.
- **macOS USB caveat (M):** the wesbos notes for another RK3326 Frameo found that USB-C↔USB-C from a Mac did not enumerate, while USB-A↔USB-C did. Have a USB-A cable and adapter ready (https://github.com/wesbos/photo-frame-dashboard/blob/main/docs/frameo-rk3326-s101.md).

### 5.5 Recommended boot plan (M)
1. Fix the backup, then take a full eMMC image via rockusb Loader mode (`rl`). Keep it, along with the `uboot`/`trust` partitions and the vendor DT.
2. **Phase A (non-destructive):** try the stock vendor U-Boot → SD `extlinux` path (§5.2). Use a serial console if one is accessible; the UART2 debug port is ttyS2 at 1500000 baud on RK3326 handhelds.
3. **Phase B:** build mainline U-Boot (TPL `sdram_px30` + TF-A px30) with a frame DT. Test by writing it to SD and temporarily invalidating the eMMC IDB at sector 64 (back it up first), *or* write it straight to eMMC sector 64 with maskrom recovery ready.
4. A long-term layout would keep Android partitions out of the way. Alternatively wipe the eMMC and put mainline U-Boot plus Arch rootfs on eMMC after SD validation.

---

## 6. Prior art

- **Frameo RK3326 or `rk3326-evb-ai-va` on mainline, Arch, or Wayland: none found (M).**
  - Searches found only Android-side work: wesbos `frameo-rk3326-s101.md` (a different board, `rk3326-s101-aic8800`, raw NAND, 1280x800, AIC8800 Wi-Fi, no Linux attempt), watercrossing/frameo-pictureframes (rooted Android), and HA Frameo integrations.
  - CNX Software (2018) identifies the EVB-VA-RK3326 as Rockchip's smart-display/voice reference: https://www.cnx-software.com/2018/04/16/rockchip-reveals-rk3308-rk3326-evaluation-boards-for-smart-speakers-and-smart-displays/
- **ROCKNIX RK3326 (H):**
  - It uses a **mainline 7.1.2** kernel plus about 26 patches covering panels, input, dwc2, PX30S support, and DMC devfreq.
  - It uses **Panfrost** (with libmali as an alternative), Vulkan via PanVK, a sway-based Wayland session, and mainline U-Boot v2025.10 + rkbin blobs.
  - It has active RK915 work (PR 3252) and esp8089 Wi-Fi.
  - This is the strongest evidence that a Wayland compositor on mainline/Panfrost is solid on this SoC.
- **ArkOS / JELOS:** ArkOS historically used the Odroid/Hardkernel 4.4 BSP kernel and JELOS evolved into ROCKNIX; neither was inspected further (L).
- **Sibling project:** `vendor/ormarch-picture-frame` (pangoleen) is an Allwinner A33 PF1007L frame running Arch Linux ARM armv7h + Hyprland on Mali-400/Lima. Its image build, touch firmware extraction, USB-gadget recovery, and guarded SD writer patterns are directly reusable. The SoC is different.

---

## Things to read off the device before writing code
1. Full live DT: `/proc/device-tree` → `dtc -I fs -O dts`. In particular check the `lt8911exb@29` properties and GPIOs, the panel/backlight enable GPIOs, `&sdio` / `wireless-wlan` (RK915 power/reset/host-wake GPIOs), touch nodes, and the RK809 regulator map.
2. Which touch driver is bound (`/sys/bus/i2c/devices/1-004{0,1}/driver`) and its firmware table.
3. `rk915_fw.bin`/`rk915_patch.bin` from `/vendor` or `/system`.
4. Whether the chip is PX30S/RK3326S: check `dmesg` for "px30s", or read DDR_GRF_BASE1 bits [15:14] (ROCKNIX patch 026).
5. DRAM type: check `dmesg` or the DDR init banner on UART.
6. `uboot` partition contents (fix the empty-hash backup), then grep for `rkimgtest`/`distro_bootcmd`.
7. Whether the USB port supports OTG host (ID pin or role switch) for the USB Wi-Fi fallback.
