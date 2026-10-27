# 02 — Omarchy on an aarch64 Arch Linux ARM photo frame (RK3326, 1 GB)

Researched 2026-10-15. Target: Rockchip RK3326 photo frame. It has 4x Cortex-A35 cores (aarch64), a Mali-G31 MP2 GPU driven by Panfrost, 1 GB RAM, a 1920x1080 panel and a touchscreen. The base OS is Arch Linux ARM (ALARM) aarch64.

Tags: **[V]** = I read it in a primary source (repo file at a named commit, a repo database, or an upstream doc). **[R]** = taken from the armv7 reference port at `vendor/ormarch-picture-frame` @ `a3d8387` (its own claims, measured on its frame). **[I]** = my inference, not tested.

Primary sources used (all fetched 2026-10-15):

- `github.com/basecamp/omarchy`. The default branch is `quattro`, HEAD `246f33a2` (2026-10-15 01:28 -04:00). Release tags `v4.0.4` (`c668141e`, 2026-09-14) and `v3.8.4`. I read it from a temp clone. Paths below are relative to the repo.
- `github.com/omacom/omarchy-iso` @ `af820ef`: `plans/aarch64-support.md`, `builder/archinstall.packages`, `configs/airootfs/root/configurator`.
- `github.com/omacom/omarchy-pkgs` @ `c68e09c`: `pkgbuilds/omarchy/PKGBUILD`.
- Omarchy's aarch64 package repo database: `https://pkgs.omarchy.org/edge/aarch64/omarchy.db` (196 packages).
- The Arch Linux ARM aarch64 repo databases: `http://mirror.archlinuxarm.org/aarch64/{core,extra,alarm,aur}/*.db.tar.gz` (313 / 12,987 / 75 / 12 packages). Omarchy's mirror `arm-mirror.omarchy.org/aarch64/*` serves byte-identical DB sizes. I used the databases instead of the archlinuxarm.org web pages because they are the authoritative package index that pacman reads.
- ALARM kernel config: `https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/linux-aarch64/config` (linux-aarch64 7.2.10-1).
- Mesa Panfrost docs: `https://docs.mesa3d.org/drivers/panfrost.html`.

---

## TL;DR

1. **Today's Omarchy (v4, branch `quattro`) has no `boot.sh` or `install.sh`.** Commit `75cb4f71` "Make setup ISO-only" (2026-06-04) removed them. The only supported install is an **x86_64 UEFI ISO**: archinstall, Limine, LUKS2, btrfs plus snapper. That path cannot target a U-Boot SBC. The aarch64 ISO plan puts SBCs explicitly **out of scope** [V].
2. **Upstream Omarchy now supports aarch64 natively.** Platform code merged on 2026-10-09 in `e1b0e5e9` (#14431). `bin/omarchy-hw-platform` maps an RK3326 to the generic `aarch64` platform. Omarchy publishes an aarch64 package repo (edge channel only) and an ALARM mirror. The **release line (v4.0.4) predates this**, so for aarch64 you must use a `quattro` commit, not a tag [V].
3. **Almost every package exists for aarch64.** Of the 164 names in `omarchy-base.packages` plus `omarchy-aarch64.packages`, 161 resolve from ALARM aarch64 plus Omarchy's edge repo. Only `nvim` and `vi` are missing (use `neovim` and `ex-vi-compat`), and `dotnet-runtime` resolves only through `dotnet-runtime-bin` [V]. Hyprland 0.56.2, Quickshell 0.3.2, uwsm, foot, squeekboard, zram-generator, earlyoom, chromium and firefox are all in ALARM `extra`. You do not need the AUR for a frame-sized install. `wvkbd` and `hyprgrass` are the only touch extras missing [V].
4. **The GPU is not a blocker here, unlike the armv7 reference.** Panfrost gives the Mali-G31 OpenGL ES 3.1 [V Mesa docs], and Hyprland needs ES 3.0 or higher. Drop the reference's `MESA_GLES_VERSION_OVERRIDE` hack. **RAM is the constraint.** The armv7 frame measured Hyprland at about 110 MB RSS and Quickshell at about 185 MB, with 345–491 MB used at idle [R]. 64-bit will be heavier [I].
5. **Recommendation:** use the reference's *source-backed* approach. Pin an Omarchy tree in `~/.local/share/omarchy`, install a trimmed package set from ALARM only, autologin straight into Hyprland (no SDDM), and turn on Omarchy's own `no-animations` and `window-opaque` toggles. Use zram at `ram/2` with **lzo-rle**, because linux-aarch64 has no zstd zram backend [V], plus earlyoom. Pin Omarchy at **`defbf90e893e741067e48f4a27d2ec694c71358e`** (the reference's tested commit, already aarch64-aware). The alternative is **`b7e900cedd0c98e843aba4ae3ec301172044238a`**, which matches the published aarch64 `omarchy-dev` package.

---

## 1. Current Omarchy install mechanism, and what blocks aarch64

### 1.1 State of the repo

| Fact | Evidence |
|---|---|
| Default branch `quattro`, HEAD `246f33a2` "Support the NVIDIA N1x laptops (#14820)", 2026-10-15 | `git ls-remote` / clone [V] |
| 7,024 commits on `quattro`; the `version` file still says `4.0.0.alpha` | `version` [V] |
| Latest tag `v4.0.4` = `c668141e` (2026-09-14). It is on branch `v4-0-4` and is **not an ancestor of `quattro`** | `git merge-base --is-ancestor` [V] |
| `boot.sh` / `install.sh` were deleted in `75cb4f71` "Make setup ISO-only" (2026-06-04) | `git log -- install.sh boot.sh` [V] |
| "Omarchy is installed using an ISO … You must turn off Secure Boot" | `manual/02-getting-started.md` [V] |

### 1.2 How the v4 ISO installs (x86_64)

[V] (`omarchy-iso/configs/airootfs/root/configurator`, `builder/archinstall.packages`, Omarchy `install/*/all.sh`):

1. **Configurator plus archinstall.** It creates a FAT32 ESP and a **LUKS2** root (`cryptsetup luksFormat --type luks2`, configurator l.737). The root is **btrfs** with subvolumes `@ @home @log @pkg`, mounted `noatime,compress=zstd` (l.751–763).
2. **Packages pacstrapped by archinstall:** `alsa-firmware amd-ucode base base-devel efibootmgr intel-ucode linux-firmware linux limine omarchy-keyring openssh pipewire snapper sof-firmware tailscale`. Then `install/omarchy-base.packages` (~160 names) comes from the ISO's offline mirror.
3. **In the chroot, `omarchy-apply-system --install-user USER --first-install`** (`bin/omarchy-apply-system`) runs:
   - `install/config/all.sh`: theme, browser policy, PAM, docker, locale, **snapper**, enable-services, firewall.
   - `install/hardware/all.sh`: about 55 leaves gated by PCI/DMI/device tree.
   - `install/login/all.sh` (SDDM).
   - `install/post-install/all.sh`: **overwrites `/etc/pacman.conf`** from a platform template, plus udev and localdb.

   Steps run through `run_logged`, which returns the step's exit code under `set -euo pipefail` (`install/helpers/logging.sh:41-76`).
4. **`omarchy-provision-user`** runs `install/user/all.sh`: theme, chromium, git, xcompose, input method, mise, keyring, VM no-animations, and platform-setup.
5. **The session.** SDDM starts `uwsm start … hyprland.desktop`. The desktop is **one Quickshell process** (bar, launcher, notifications, OSD, lock, idle) with a **Lua** Hyprland config, so Hyprland must be 0.55 or newer. The default terminal is **foot** [V/R `research/04` §Summary]. Waybar, walker, mako, hyprlock, hypridle and swaybg are **gone from v4** [R `research/04` l.18, citing `bin/omarchy-upgrade-to-quattro`].
6. **Hard package dependencies** (`omarchy-pkgs/pkgbuilds/omarchy/PKGBUILD`):
   - All architectures: `omarchy-keyring omarchy-settings hyprland quickshell uwsm sddm xdg-desktop-portal-hyprland wireplumber pipewire gnome-keyring gum jq git perl fakeroot pacman-contrib ttf-jetbrains-mono-nerd-basic`.
   - `depends_x86_64` adds `limine limine-mkinitcpio-hook limine-snapper-sync snapper`.
   - `depends_aarch64` adds only `networkmanager`.
   - `omarchy-settings` depends on `plymouth` [V].

For comparison, the **v3.8.4 era** worked like this: `boot.sh` did a `git clone` into `~/.local/share/omarchy` and then `source install.sh` (`v3.8.4:boot.sh` l.40–48). `install/preflight/guard.sh` aborted unless all of these held: `/etc/arch-release` present, not root, **`uname -m == x86_64`** (l.25), Secure Boot off, no GNOME/KDE, **Limine installed** (l.40), and a **btrfs root** [V]. Its config was hyprlang plus waybar/walker/mako/hyprlock/hypridle/swaybg/alacritty. Hyprland is deprecating hyprlang, so v3 is a dead end [R].

### 1.3 Official aarch64 support (new, edge-only)

[V] unless noted:

- **Platforms.** `AGENTS.md` "Platforms": "Omarchy runs on x86 and aarch64 (ARM) … `aarch64` – every ARM machine without a family of its own (Raspberry Pis and ARM VMs today)". It also lists `aarch64-apple`, `-qualcomm`, `-n1x` and `-gb10`.
- **Detection.** `bin/omarchy-hw-platform` reads the device-tree root `compatible` and only special-cases `apple,*` and `qcom,*`. An RK3326 (`rockchip,rk3326`) therefore prints **`aarch64`**. This landed in `e1b0e5e9` "Converge omarchy-mac and omarchy-mx-mac into upstream Omarchy (#14431)", 2026-10-09.
- **Package list.** `install/omarchy-aarch64.packages` adds `zram-generator` and `rtkit`. The `rtkit` line was added after `defbf90e`: "Nothing pulls rtkit in on aarch64, so PipeWire gets no realtime scheduling without it". `bin/omarchy-pkg-defaults` composes base plus aarch64, minus `omarchy-x86_64-only.packages`, which is now empty.
- **Pacman template.** `default/pacman/aarch64/pacman-edge.conf` orders the repos `[omarchy] https://pkgs.omarchy.org/edge/$arch`, then `[core] [extra] [alarm] [aur]` from `https://arm-mirror.omarchy.org/$arch/$repo` ("Omarchy's mirror of Arch Linux ARM, over HTTPS since the repository databases are unsigned"). It sets `SigLevel = Required DatabaseOptional`.
- **Edge only.** `install/helpers/pacman.sh`: "Omarchy publishes aarch64 packages on edge alone so far, and the stable and rc packages there are the release line, which has no aarch64 support".
  - This is borne out by the repo database. `omarchy-4.0.4-2` (aarch64) is built from `_commit=c668141e` (v4.0.4), which has **no `bin/omarchy-hw-platform`**.
  - The aarch64-aware build is **`omarchy-dev-4.0.0.r7022.gb7e900c-1`** plus `omarchy-settings-dev`, built from `quattro` @ `b7e900ce` (2026-10-14).
- **Keyring.** `bin/omarchy-update-keyring` trusts the Omarchy key `40DFB630FF42BCFFB047046CF0134EE680CAC571` (from keys.openpgp.org) and the ALARM key `68B3537F39A313B3E574D06777193F152BDBE6A6`.
- **Boot chain.** `docs/lifecycle-dispatch.md`: on the `aarch64` platform every boot operation is a no-op and "callers keep their generic path". Only Apple registers a boot package. This is good for U-Boot because Omarchy will not touch the boot chain.
- **ISO.** `omarchy-iso/plans/aarch64-support.md`: the target is a "generic UEFI aarch64 ISO … Apple Silicon (Asahi) and **SBCs (U-Boot/rpi-firmware) are out of scope**".

### 1.4 What blocks a stock install on this RK3326 frame

| Blocker | Why | Severity |
|---|---|---|
| No ISO or installer for SBCs | The ISO is x86_64 UEFI only; the aarch64 ISO plan excludes U-Boot boards [V] | Hard. You must install onto an existing ALARM rootfs |
| Release line has no aarch64 code | v4.0.4 lacks `omarchy-hw-platform`; aarch64 lives on `quattro` / edge only [V] | Pin a `quattro` commit |
| Limine / UKI / LUKS / btrfs / snapper | Baked into the ISO and `install/config/snapper.sh`, which runs `snapper create-config` with no platform gate [V]. aarch64 `omarchy` does not depend on snapper [V], so on a trimmed ext4 install that step fails and `run_logged` propagates the failure [V code; failure I] | Do **not** run `omarchy-apply-system` wholesale |
| `enable-services.sh` / `firewall.sh` assume the full base set | `systemctl enable docker.socket` and `ufw … allow-docker-dns` [V]. They fail if docker/ufw are trimmed [I] | Same as above |
| SDDM greeter runs its own Hyprland | `etc/sddm.conf.d/10-wayland.conf` [R `research/04` l.49]. That is a second compositor in 1 GB | Replace with autologin |
| Full base set is too heavy for 1 GB / small eMMC | It includes libreoffice-fresh, docker, fcitx5×8, noto-fonts-cjk, chromium and more [V list] | Trim (§4) |
| `nvim`, `vi` not in ALARM aarch64 | `nvim` is missing; `vi` is replaced by `ex-vi-compat` [V DB] | Cosmetic |

### 1.5 Community ARM work

All repos below are reachable via `git ls-remote` on 2026-10-15.

- **`hotschmoe/omarchy-arm`** (= `alexisraitano-myffu/omarchy-arm`, HEAD `579f15c6`). It runs a live-system `install.sh` on ALARM aarch64 with package manifests (`packages.{replace,aur,aur-required,unavailable,extra}`), never touches the boot chain, gates x86 leaves, and ships a Raspberry Pi Lua profile with animations/blur/shadows/rounding off. Its `docs/arm64-port.md` lists about 20 "first real install" failures. Two matter here: no `omarchy-*` on PATH, and no `/etc/skel` seeding for an existing user [R `research/04` l.197–218]. It predates upstream aarch64 support.
- **`omarchy-mac/omarchy-mac`** (Asahi ALARM, HEAD `ba546a61`). It was converged into upstream by #14431. Linked from `manual/49-omarchy-on.md` [V].
- **`nilszeilon/armarchy`** + **`happybigmtn/omarchy-arm-fixes`**: v2/v3 era, Asahi, Firefox-for-Chromium patches. Obsolete for v4 [R].
- **`Linux-for-Fydetab-Duo/imagebuild`** (RK3588S, ALARM aarch64). Omarchy 4.0.0 image with U-Boot plus an ext4 root. No LUKS, btrfs, snapper, Limine or Plymouth. Uses SDDM autologin, 2x scale and touchscreen mapping. This is the closest proven SBC pattern [R `research/04` l.232–238].
- **Recent upstream ARM commits** on `quattro`: `e1b0e5e9` (#14431 aarch64 platform), `492b8837` "Stop asking for a reboot after every update on ARM" (#14447), `9a10b488` "Enable Superwhisper on aarch64" (#15247), `246f33a2` N1x (#14820) [V git log].

---

## 2. Package availability on Arch Linux ARM aarch64

Method: I parsed every `desc` in the ALARM `core/extra/alarm/aur` aarch64 DBs and Omarchy's `edge/aarch64` DB (scripts in `/tmp/omx-research/scripts`, not in the repo). Versions and build dates are as of 2026-10-15 [V].

### 2.1 The names in the question

| Package | ALARM aarch64 | Omarchy edge aarch64 | Note for v4 |
|---|---|---|---|
| hyprland | extra 0.56.2-4 (2026-10-03) | 0.56.2-6 (2026-10-15, Omarchy patches) | Required. Lua config needs 0.55 or newer |
| quickshell | extra 0.3.2-1 (2026-10-09) | 0.3.2-6 | **The v4 shell** (bar, launcher, notifications, lock, idle) |
| uwsm | extra 0.27.0-1 | — | Used by the SDDM session; optional with direct start |
| foot | extra 1.28.0-2 | — | v4 default terminal; light |
| hypridle | extra 0.1.8-2 | — | **Not used by v4** (Quickshell does idle) |
| hyprlock | extra 0.9.6-3 | — | Not used by v4 |
| waybar | extra 0.15.0-3 | — | Not used by v4 |
| walker | — | 2.17.2-1 | Not used by v4. `elephant` missing everywhere |
| mako | extra 1.11.0-1 | — | Not used by v4 |
| swaybg | extra 1.2.2-1 | — | Not used by v4 (the shell draws the background) |
| swayosd | extra 0.3.2-1 | — | Not used by v4 |
| alacritty | extra 0.17.0-1 | — | v3 default; skip |
| ghostty | — | 1.3.1-3 | Heavy (80–100 MB [R `research/06`]); skip |
| kitty | extra 0.49.2-1 | — | Skip |
| hyprland-guiutils, xdg-desktop-portal-hyprland, hyprpm, hyprshutdown, aquamarine | extra | (some also in omarchy) | ok |
| xdg-terminal-exec | extra 0.14.3-2 | 0.14.3-1 | Required by `omarchy-launch-*` |
| zram-generator | extra 1.2.1-1 | — | — |
| earlyoom | extra 1.9.0-1 | — | — |
| squeekboard | extra 1.43.1-6 | — | OSK that the reference uses |
| wvkbd | **missing** | — | AUR, tiny C; build if wanted |
| hyprgrass | **missing** | — | Build against the exact hyprland headers (`hyprpm`) |
| chromium | extra 153.0.8010.36-1 | omarchy-chromium 148 | Exists (unlike armv7), but heavy |
| firefox | extra 157.0.1-1 | — | Heavy |
| mesa / vulkan-panfrost | extra 26.2.4-1 | — | Panfrost GL plus PanVK |
| greetd / greetd-tuigreet / seatd | extra | — | Autologin options |
| plymouth | extra 26.134.222-3 | — | Only needed if you install the `omarchy-settings*` package |
| ttf-jetbrains-mono-nerd(-basic) | extra (`-nerd`) | `-basic` 3.5.1-2 | `-nerd` from ALARM is enough |
| yaru-icon-theme, mise-bin, yay | — | yes | Omarchy repo only; optional |
| linux-aarch64 | core 7.2.10-1 | — | `ARCH_ROCKCHIP`, `DRM_ROCKCHIP`, `ROCKCHIP_DW_MIPI_DSI`, `PHY_ROCKCHIP_INNO_DSIDPHY`, `DRM_PANFROST`, `TOUCHSCREEN_GOODIX` enabled [V config] |
| archlinuxarm-keyring | core | — | — |

### 2.2 Whole Omarchy default set

`omarchy-pkg-defaults aarch64` gives 164 names:

- 161 are found.
- `nvim` is MISSING. ALARM has `neovim` 0.12.6.
- `vi` is MISSING. ALARM's `ex-vi-compat` `REPLACES=vi`.
- `dotnet-runtime` is only provided by Omarchy's `dotnet-runtime-bin`.

Notable aarch64 wins over armv7:

- `chromium`, `quickshell`, `squeekboard`, `plymouth`, `swayosd` and `hyprlock` all exist.
- Omarchy's own apps are prebuilt for aarch64: `omacalc omawrite omacut omasnap owe tzupdate ttfx hype monologue signed obsidian localsend pinta herdr`.

**Nothing in the Omarchy set needs building from AUR or source on aarch64** [V]. The only extras to build are `wvkbd` and `hyprgrass`, and only if you want them.

Caveat: ALARM is rolling with no package archive. "Pinning" means pinning the Omarchy source commit plus `IgnorePkg` for the kernel and compositor stack, or keeping a local package cache [I].

---

## 3. How the armv7 reference port adapts Omarchy, and what carries over to aarch64

Reference: `vendor/ormarch-picture-frame` @ `a3d8387`. Target: Allwinner A33, armv7h, Mali-400/lima (GLES 2.0), 1 GB RAM, 800x1280 panel rotated, Silead touch.

### 3.1 What it does

All [R], file paths under `port/frame/`:

- **Source-backed install, no packages and no installer.**
  - `bootstrap.sh` checks: user `frame`, `armv7l`, an extlinux config, kernel `7.2.10-1-armv7-ARCH`.
  - It installs only `git`, then fetches Omarchy `quattro` **pinned at `defbf90e893e741067e48f4a27d2ec694c71358e`**: `git clone --filter=blob:none --no-checkout`, `fetch --depth 1 <commit>`, `git archive … shell bin config default themes version`.
  - It copies that tree to `~/.local/share/omarchy`, writes `.pf-pinned-commit`, and seeds `~/.config` from `config/` only if `~/.config/hypr/hyprland.lua` is absent. Then it runs `apply.sh`.
  - It never runs the upstream installer or `omarchy-apply-system`.
- **`apply.sh`** (idempotent, keeps `.before-*` backups):
  - `patch-platform.py`: makes `omarchy-hw-platform` print `armv7` instead of `x86`, and makes `omarchy-default-agent` refuse Claude Code on armv7.
  - `patch-first-run.py`: comments out `hl.exec_cmd("omarchy-provision-first-run")` in `default/hypr/autostart.lua`. It looks for package-owned user units and re-fires welcome/update notices on every login.
  - Installs a fixed set (`armv7-packages.txt`):
    - Core: `hyprland quickshell uwsm foot xdg-terminal-exec git`.
    - System: `qt6-imageformats networkmanager bluez bluez-utils bluez-tools pipewire wireplumber squeekboard xdg-user-dirs adwaita-icon-theme woff2-font-awesome`.
    - Apps: `firefox nautilus mpv imv fastfetch btop ripgrep noto-fonts noto-fonts-emoji bat eza fd fzf tldr tmux slurp`.
    - Network: `wireless-regdb iwd iw`.
  - `guard-updater.py` makes `omarchy-pkg-defaults`, `omarchy-apply-system` and `omarchy-provision-owner` exit on armv7. It also adds a pacman `PreTransaction` hook (`pf-pacman-guard`) blocking `linux-armv7`, its headers and `chromium`.
  - **Touch keyboard:**
    - `squeekboard` runs as a user D-Bus service (`pf-keyboard.service`, `BusName=sm.puri.OSK0`).
    - `pf-keyboard-toggle` flips the `Visible` property via `gdbus`.
    - A local Omarchy shell plugin `frame.keyboard` (`keyboard/manifest.json` + `Widget.qml`, kind `bar-widget`) is enabled with `omarchy-plugin-enable frame.keyboard --section right --index 0`.
    - `autostart.lua` imports `WAYLAND_DISPLAY` and starts the service. No polling.
  - Copies Omarchy's `bt-agent.service` and the `omarchy.ttf` font. Uses foot via `~/.config/xdg-terminals.list`.
  - NetworkManager leaves `usb0` unmanaged. Masks `sleep/suspend/hibernate/hybrid-sleep.target`.
  - `omarchy-toggle-idle stay-awake`: no idle lock. A layer-shell OSK can't appear over the session-lock surface (`research/04` l.259).
  - `omarchy-display-text-size 18`.
- **Session without SDDM.** `pf-hyprland.service` is a system unit with `User=frame`, `PAMName=login`, `TTYPath=/dev/tty1`. It waits for `/dev/dri/card0` and `renderD128`, then `ExecStart=/usr/bin/start-hyprland`. Its env sets `MESA_GLES_VERSION_OVERRIDE=3.0`. The drop-in `omarchy.conf` sets `LANG=C.UTF-8`, `OMARCHY_SHELL_IPC_TIMEOUT=5s`, `OMARCHY_PATH` and `PATH` with `$OMARCHY_PATH/bin` first.
- **Display and performance tune (`tune-hypr.py`):**
  - `monitors.lua` scale goes from 1.6 to 1.25, and `omarchy_gdk_scale` from 2 to 1.
  - Appends to `looknfeel.lua`: `animations.enabled=false`, blur off, shadow off.
  - Sets `debug.damage_tracking = 0` (full repaint) as a **lima tearing workaround** (E057).
  - Touch: monitor `transform = 3`, `touchdevice = { transform = 6, output = "DSI-1" }`, measured with `wev` (E050).
- **Memory, from the image rootfs:**
  - `zram-generator.conf.d/10-pf1007l.conf`: `zram-size = ram / 2`, `compression-algorithm = lzo-rle`, `swap-priority = 100`.
  - `sysctl.d/10-pf1007l.conf`: `vm.swappiness = 100`, `vm.page-cluster = 0`.
  - `earlyoom` enabled (`image/README.md` l.370).
- **Media:** the wallpaper was downscaled from 6016x3384 WebP to 1280x720 (E057). YouTube goes through `mpv` + pinned `yt-dlp` at ≤480p H.264, because VP9 is too slow in software (`pf-youtube`).
- **Measured results** (`docs/experiments.md`):
  - Idle desktop after boot: 345 MiB used, 632 MiB free (E056).
  - With the menu open: 491 MB used, 486 MB available; RSS Hyprland 109.8 MB, Quickshell 185.4 MB, Squeekboard 24.1 MB (E053).
  - Two blank Firefox windows: 152 MiB available and 401 MiB swap. One Firefox tab ≈ 560 MB across 4 processes, and the first launch took over 120 s (E054/E057).
  - "The primary slowdown is browser memory pressure, not software rendering."

### 3.2 What applies to aarch64 RK3326

| Reference item | aarch64 RK3326 | Why |
|---|---|---|
| Source-backed pinned tree + `~/.config` seeding + no upstream installer | **Keep** | The upstream ISO can't target U-Boot; `omarchy-apply-system` assumes snapper/docker/full set [V] |
| `patch-platform.py` (armv7 → platform) | **Drop** | `omarchy-hw-platform` already prints `aarch64` [V] |
| Claude-agent refusal | **Drop** | Claude Code ships arm64; Omarchy edge even packages `claude-code` for aarch64 [V DB] |
| `patch-first-run.py` | **Keep**, unless you install the `omarchy-dev` package | Same source-backed reason; the autostart line still exists at HEAD (`default/hypr/autostart.lua:15`) [V] |
| `guard-updater.py` | **Adapt** | On aarch64 the helpers *work*: `omarchy-reinstall-pkgs` would install the whole 164-package set from edge [V]. Guard `omarchy-reinstall-pkgs`, `omarchy-apply-system` and `omarchy-update` on the frame. Block `linux-aarch64` (vendor/DT-pinned kernel) rather than chromium |
| `MESA_GLES_VERSION_OVERRIDE=3.0` | **Drop** | Panfrost exposes GLES 3.1 on G31 [V Mesa] |
| `damage_tracking = 0` | **Do not copy by default** | It was a lima tear workaround. Full repaint every frame costs GPU and power. Try only if tearing shows [I] |
| Animations/blur/shadow off | **Keep, via upstream toggles** | Upstream ships `default/hypr/toggles/no-animations.lua` and `window-opaque.lua`, placed in `~/.local/state/omarchy/toggles/hypr/` exactly as `install/user/hardware/vm-no-animations.sh` does for VMs [V]. Cleaner than appending to `looknfeel.lua` |
| Scale tune | **Keep idea, new values, robust edit** | Fresh `monitors.lua` has `omarchy_monitor_scale = "auto"` at both `defbf90e` and HEAD [V]. `tune-hypr.py`'s literal `= 1.6` match would abort. Set the value with a regex. Suggest 1.5 (1280x720 logical) or 1.25 (1536x864) on 1920x1080, `omarchy_gdk_scale = 1` [I] |
| Touch transform 3/6, `DSI-1` | **Re-measure** | Panel and digitizer differ; use `evtest` + `wev -f wl_touch` like E050 |
| squeekboard + D-Bus toggle + `frame.keyboard` widget | **Keep** | squeekboard is in ALARM aarch64 extra [V]. Plugin API is unchanged at the pinned commit (re-verify if you pin newer) |
| Idle lock off (`stay-awake`), text size, suspend masks | **Keep** | Same touch-lock problem |
| `pf-hyprland.service` direct tty1 session | **Keep** (minus `MESA_*`) | Saves an SDDM-Hyprland greeter in 1 GB |
| NM, PipeWire/WirePlumber, bt-agent | **Keep**; add **`rtkit`** | `omarchy-aarch64.packages` adds rtkit for PipeWire RT on aarch64 [V] |
| zram `ram/2` lzo-rle, swappiness 100, page-cluster 0, earlyoom | **Keep** | linux-aarch64 is also LZO-only: `CONFIG_ZRAM_BACKEND_FORCE_LZO=y`, `ZRAM_DEF_COMP="lzo-rle"`, no ZSTD/LZ4 backends [V config]. Omarchy's own `90-omarchy.conf` asks for `zram-size = ram`, `zstd` [V], so do not install it as-is |
| Wallpaper downscale | **Keep** | Each decoded 1920x1080 RGBA layer is about 8 MB [I] |
| mpv + yt-dlp H.264 ≤480p | **Keep** | The A35 decodes in software. The RK3326 VPU (hantro) path through mpv is untested [I] |
| AIC8800 Wi-Fi, kernel 7.2.10-armv7 pin, Bluetooth UART | **Drop** | Board-specific |
| Firefox replaces Chromium | **Optional** | Both exist on aarch64. Neither fits comfortably in 1 GB [R measurements] |

---

## 4. Recommended plan

### 4.1 Pin

- **Primary: `defbf90e893e741067e48f4a27d2ec694c71358e`** (`quattro`, 2026-10-12, "Fully revert USB and Thunderbolt device approval (#15091)").
  - It already contains the aarch64 platform code from #14431 [V].
  - It is the exact tree the reference proved on a 1 GB frame, so its plugin API, `autostart.lua` and `looknfeel.lua` patch points are known-good [R].
  - Add `rtkit` by hand; it landed after this commit [V].
- **Alternative: `b7e900cedd0c98e843aba4ae3ec301172044238a`** (2026-10-14). It matches the aarch64 binary `omarchy-dev-4.0.0.r7022.gb7e900c-1` on `pkgs.omarchy.org/edge`. Use it if you would rather install Omarchy as a package (`omarchy-dev` + `omarchy-settings-dev`).
  - That pulls in `sddm`, `plymouth` and `omarchy-themes-intros` (96 MB) as hard dependencies [V DB].
  - It adds an alpm hook that forces upgrades through `omarchy update` (`default/libalpm/hooks/00-omarchy-update-guard.hook`) [V].
- Do **not** use tag `v4.0.4`: it has no aarch64 platform code [V].

### 4.2 Package set

Everything below is from ALARM aarch64 `core/extra`. No `[omarchy]` repo or AUR is needed [V availability]. About 50 explicit packages, against the 164 in the upstream set.

```text
# compositor + shell (Omarchy v4 core)
hyprland hyprland-guiutils xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
quickshell qt6-base qt6-declarative qt6-wayland qt6-svg qt6-imageformats
uwsm xdg-terminal-exec foot
# GPU (Panfrost GL 3.1)
mesa
# scripts used by omarchy-* helpers
gum jq git perl socat inotify-tools less unzip python-gobject libnotify
wl-clipboard wtype grim slurp brightnessctl
# session services
pipewire wireplumber pipewire-pulse rtkit networkmanager gnome-keyring libsecret polkit
# fonts / icons
ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji woff2-font-awesome adwaita-icon-theme
# touch
squeekboard
# memory
zram-generator earlyoom
# frame apps (light)
imv mpv yt-dlp btop fastfetch
# optional
bluez bluez-utils bluez-tools      # only if BT is wanted
evtest wev                          # touch calibration, remove after
```

Deliberately **not** installed:

- `sddm`, `plymouth`, `limine*`, `snapper`.
- `docker*`, `cups*`, `avahi`, `nss-mdns`, `fcitx5*`, `noto-fonts-cjk`.
- `libreoffice-fresh`, `chromium`/`omarchy-chromium`/`firefox` (by default), `obsidian`, `localsend`, `pinta`/`dotnet-runtime`.
- `nautilus` + gvfs stack, `owe`, `owe-lockfeed`, `omarchy-themes-intros`, `hype`, `monologue`, `herdr`.
- `ollama`, `base-devel`, `udiskie`, `power-profiles-daemon` (cpufreq-dt has no profiles) [I], `ufw` (optional).

### 4.3 Bootstrap script outline (`port/rk3326/bootstrap.sh`, run as the frame user)

```bash
#!/bin/bash
set -euo pipefail
OMARCHY_COMMIT=defbf90e893e741067e48f4a27d2ec694c71358e
OMARCHY_PATH=$HOME/.local/share/omarchy

# 0. Preconditions (refuse, don't guess)
[[ $(uname -m) == aarch64 ]]
[[ -e /dev/dri/renderD128 ]] && grep -q panfrost /proc/modules   # GPU up
grep -q rockchip,rk3326 /proc/device-tree/compatible            # right board
(( EUID != 0 ))

# 1. pacman: keep ALARM's pacman.conf; keys; pin the fragile stack
sudo pacman-key --init && sudo pacman-key --populate archlinuxarm
sudo sed -i 's/^#\?IgnorePkg.*/IgnorePkg = linux-aarch64 linux-aarch64-headers/' /etc/pacman.conf
#   (add hyprland quickshell aquamarine hyprutils to IgnorePkg after first good boot)
sudo pacman -Syu --needed --noconfirm <package set from 4.2>

# 2. Fetch the pinned Omarchy tree (reference bootstrap.sh method)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git clone -q --filter=blob:none --no-checkout https://github.com/basecamp/omarchy.git "$tmp/o"
git -C "$tmp/o" fetch -q --depth 1 origin "$OMARCHY_COMMIT"
git -C "$tmp/o" archive FETCH_HEAD bin shell config default themes version install | tar -x -C "$tmp"
#   (skip themes/*/intro videos if present to save disk)
rm -rf "$OMARCHY_PATH"; mkdir -p "$OMARCHY_PATH"
cp -a "$tmp"/{bin,shell,config,default,themes,version,install} "$OMARCHY_PATH/"
echo "$OMARCHY_COMMIT" > "$OMARCHY_PATH/.pinned-commit"

# 3. Seed user config once (never clobber)
[[ -f ~/.config/hypr/hyprland.lua ]] || cp -a "$OMARCHY_PATH/config/." ~/.config/

# 4. Source patches (idempotent, backed up)
python3 patch-first-run.py "$OMARCHY_PATH"      # from reference, unchanged
python3 guard-updater.py   "$OMARCHY_PATH"      # adapted: block omarchy-reinstall-pkgs,
                                                # omarchy-apply-system, omarchy-update; hook on linux-aarch64

# 5. Low-RAM look: use upstream toggles, not file surgery
mkdir -p ~/.local/state/omarchy/toggles/hypr
cp "$OMARCHY_PATH"/default/hypr/toggles/{no-animations,window-opaque}.lua ~/.local/state/omarchy/toggles/hypr/
python3 tune-hypr.py --scale 1.5 --gdk 1 --transform <measured> --touch-transform <measured> --output DSI-1
#   regex-replace omarchy_monitor_scale / omarchy_gdk_scale; append touchdevice block to input.lua

# 6. System memory + services (root)
sudo install -Dm644 zram.conf     /etc/systemd/zram-generator.conf     # ram/2, lzo-rle, prio 100
sudo install -Dm644 sysctl.conf   /etc/sysctl.d/90-frame.conf          # see 4.4
sudo install -Dm644 zswap-off.conf /etc/tmpfiles.d/frame-zswap.conf    # copy of Omarchy's etc/tmpfiles.d/omarchy-zswap.conf
sudo install -Dm644 journald.conf /etc/systemd/journald.conf.d/frame.conf
sudo install -Dm644 earlyoom      /etc/default/earlyoom
sudo systemctl enable --now earlyoom NetworkManager
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo install -m644 frame-hyprland.service /etc/systemd/system/          # reference unit minus MESA_GLES_VERSION_OVERRIDE
sudo install -Dm644 omarchy.conf /etc/systemd/system/frame-hyprland.service.d/omarchy.conf  # OMARCHY_PATH, PATH, LANG, IPC timeout
sudo systemctl enable frame-hyprland.service

# 7. User services + touch keyboard (reference apply.sh, unchanged)
install keyboard plugin, pf-keyboard.service, pf-keyboard-toggle, bt-agent.service (if BT)
systemctl --user enable --now pipewire.socket wireplumber.service
fc-cache -f; xdg-user-dirs-update
omarchy-toggle-idle stay-awake
omarchy-display-text-size 18
omarchy-plugin-enable frame.keyboard --section right --index 0

# 8. Verify (not "it started")
#   hyprctl configerrors (empty) ; hyprctl binds | wc -l (>0) ; bar visible (grim)
#   free -m / zramctl (lzo-rle) ; systemctl --failed ; smem/PSS of Hyprland + quickshell
```

### 4.4 RAM settings for 1 GB

| Setting | Value | Source / reason |
|---|---|---|
| zram | `zram-size = ram / 2`, `compression-algorithm = lzo-rle`, `swap-priority = 100` | The kernel has only the LZO zram backend [V]. `ram/2` is proven on the reference [R]. Omarchy's `ram`+`zstd` is not usable here [V] |
| zswap | off (copy Omarchy's `etc/tmpfiles.d/omarchy-zswap.conf`) | linux-aarch64 builds zswap, not on by default [V]; avoids double compression [V Omarchy comment] |
| sysctl | `vm.swappiness=100` (Omarchy uses 150), `vm.page-cluster=0`, `vm.vfs_cache_pressure=50`, `vm.watermark_boost_factor=0`, `vm.watermark_scale_factor=125`, `vm.dirty_background_bytes=16777216`, `vm.dirty_bytes=67108864` | Omarchy's `etc/sysctl.d/99-omarchy-sysctl.conf` [V], with the dirty caps cut from 64M/256M (a quarter of RAM) [I, as in R `research/06`] |
| OOM | earlyoom `-m 5 -s 10 --prefer '(chromium|firefox|mpv)' --avoid '(Hyprland|quickshell|systemd)'` | [R `research/06`]. PSI and MEMCG are on in linux-aarch64 [V], so systemd-oomd is an alternative |
| journald | `Storage=volatile`, `RuntimeMaxUse=16M` | [R `research/06`] |
| Compositor | Omarchy `no-animations` + `window-opaque` toggles (animations, blur and shadow off); keep default damage tracking | [V toggles]. `damage_tracking=0` was a lima-only fix [R] |
| Session | No SDDM (direct tty1 unit), no uwsm needed, one Quickshell, foot | Avoids a second Hyprland for the greeter [R] |
| Autostart trims | Remove `udiskie` and `omarchy-powerprofiles-init` from the copied `default/hypr/autostart.lua`, or just don't install them (the commands then fail harmlessly) | `default/hypr/autostart.lua` [V]. Check `journalctl --user` after |
| Wallpaper | ≤1920x1080 JPEG/WebP | [R E057] |
| Apps to avoid | Any browser at idle (≈400–560 MB per tab [R]), LibreOffice, Electron (Obsidian), Docker, ollama, video wallpaper (`owe`), Omarchy video intros, fcitx5 | [R] + [V package list] |
| CMA | linux-aarch64 reserves `CMA_SIZE_MBYTES=64` [V]. Panfrost and the RK3326 VOP both sit behind IOMMUs, so `cma=32M` on the cmdline *may* return 32 MB | [I], test display and video before keeping |
| Budget | Expect roughly 450–700 MB used at idle on 64-bit, against 345–491 MB measured on armv7 [R]. 64-bit pointers and Qt's heap make it heavier [I]. Measure with `smem -k -c "pss name"` (smem is not in ALARM; use `/proc/*/smaps_rollup` or the reference's `port/mem-from-smaps.py`) | [I] |

### 4.5 Open risks

1. The **kernel and DT for this specific frame** (DSI panel driver, touch controller, Wi-Fi) are out of scope here. linux-aarch64 has the Rockchip DRM, DSI, DPHY and Panfrost drivers built [V]. Whether the vendor panel has a mainline driver is a separate question.
2. ALARM is rolling with no archive. After the first good boot, freeze the hyprland, aquamarine, hyprutils, quickshell and Qt set with `IgnorePkg`, or keep `/var/cache/pacman/pkg` [I].
3. `omarchy-*` helpers that call `omarchy-pkg-add` (theme hooks, the menu's "Install" entries, migrations) can pull large packages or AUR builds. Keep `guard-updater` in place and do not tap "Update System" [R E056].
4. If you pin a commit newer than `defbf90e`, re-run the reference patch scripts in check mode. They `SystemExit` when their anchors move, which is the right failure mode [R].
