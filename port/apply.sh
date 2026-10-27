#!/bin/bash
# Frame-specific Omarchy setup. Idempotent; called by bootstrap.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"
export LANG=C.UTF-8 OMARCHY_SHELL_IPC_TIMEOUT=5s
[[ -f $OMARCHY_PATH/shell/shell.qml ]]

python3 "$here/patch-first-run.py" "$OMARCHY_PATH"
python3 "$here/lock-bar.py" "$OMARCHY_PATH"
sudo python3 "$here/guard-updater.py" "$OMARCHY_PATH"

# Low-RAM look through Omarchy's own toggles.
mkdir -p "$HOME/.local/state/omarchy/toggles/hypr"
cp "$OMARCHY_PATH"/default/hypr/toggles/{no-animations,window-opaque}.lua \
  "$HOME/.local/state/omarchy/toggles/hypr/"
python3 "$here/tune-hypr.py"

# Touch keyboard (squeekboard over D-Bus, bar button).
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" \
  "$HOME/.config/omarchy/plugins/frame.keyboard" "$HOME/.local/share/fonts"
install -m 755 "$here/frame-keyboard-toggle" "$HOME/.local/bin/"
install -m 644 "$here/frame-keyboard.service" "$HOME/.config/systemd/user/"
cp "$here"/keyboard/{manifest.json,Widget.qml} "$HOME/.config/omarchy/plugins/frame.keyboard/"
cp "$OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf" "$HOME/.local/share/fonts/"
fc-cache -f "$HOME/.local/share/fonts"
[[ -f $HOME/.config/xdg-terminals.list ]] || printf 'foot.desktop\n' > "$HOME/.config/xdg-terminals.list"
mkdir -p "$HOME/.local/state/omarchy/defaults"
[[ -f $HOME/.local/state/omarchy/defaults/editor ]] || printf 'nano\n' > "$HOME/.local/state/omarchy/defaults/editor"
python3 - "$HOME/.config/hypr/autostart.lua" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text() if p.exists() else ""
m = "-- FRAME157 touch keyboard"
if m not in t:
    p.write_text(t + f'\n{m}\no.launch_on_start("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP && systemctl --user start frame-keyboard.service")\n')
PY

# Memory: no X11 apps on the frame, so no Xwayland (~45 MB) and no GTK portal
# (~20 MB; file dialogs fall back to the Hyprland portal).
python3 - "$HOME/.config/hypr/looknfeel.lua" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
t = p.read_text() if p.exists() else ""
m = "-- FRAME157 low memory"
if m not in t:
    p.write_text(t + f"\n{m}\nhl.config({{ xwayland = {{ enabled = false }} }})\n")
PY
systemctl --user mask xdg-desktop-portal-gtk.service

# System: memory, journald, session unit.
sudo install -Dm644 "$here/system/zram-generator.conf" /etc/systemd/zram-generator.conf
sudo install -Dm644 "$here/system/sysctl.conf" /etc/sysctl.d/90-frame.conf
sudo install -Dm644 "$here/system/journald.conf" /etc/systemd/journald.conf.d/frame.conf
sudo install -Dm644 "$here/system/earlyoom" /etc/default/earlyoom
sudo install -Dm644 "$here/system/zswap-off.conf" /etc/tmpfiles.d/frame-zswap.conf
sudo install -Dm644 "$here/system/cpufreq.conf" /etc/tmpfiles.d/frame-cpufreq.conf
sudo install -Dm644 "$here/system/hugepages.conf" /etc/tmpfiles.d/frame-hugepages.conf
sudo systemd-tmpfiles --create /etc/tmpfiles.d/frame-hugepages.conf
sudo mkdir -p /etc/NetworkManager/conf.d
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' | sudo tee /etc/NetworkManager/conf.d/10-frame-usb.conf >/dev/null
sudo install -m644 "$here/frame-hyprland.service" /etc/systemd/system/
sudo install -Dm644 "$here/omarchy.conf" /etc/systemd/system/frame-hyprland.service.d/omarchy.conf
sudo systemctl daemon-reload
sudo systemctl enable --now earlyoom NetworkManager seatd
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo systemctl enable frame-hyprland.service

systemctl --user daemon-reload
systemctl --user enable --now pipewire.socket wireplumber.service
xdg-user-dirs-update
omarchy-toggle-idle stay-awake
omarchy-display-text-size 18
omarchy-plugin-enable frame.keyboard --section right --index 0
echo "Frame desktop configured."
