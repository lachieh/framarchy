#!/bin/bash
# Install or update the home dashboard on the frame. Idempotent; run as the
# desktop user (frame) inside the running Omarchy session.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$PATH" OMARCHY_SHELL_IPC_TIMEOUT=10s

dest="$HOME/.config/omarchy/plugins/frame.dashboard"
config_dir="$HOME/.config/frame-dashboard"
mkdir -p "$dest" "$config_dir"
[[ -f $dest/manifest.json ]] && update=1 || update=0
rm -f "$dest"/*.qml "$dest"/*.js
cp "$here"/plugin/{manifest.json,*.qml,*.js} "$dest/"

# The config holds the Home Assistant token: create it once, never overwrite.
[[ -f $config_dir/config.json ]] || cp "$here/config.example.json" "$config_dir/config.json"
chmod 600 "$config_dir/config.json"

# Night dimming writes the backlight as the video group.
sudo install -Dm644 "$here/system/90-frame-backlight.rules" /etc/udev/rules.d/90-frame-backlight.rules
sudo udevadm control --reload
sudo udevadm trigger --action=add --subsystem-match=backlight

omarchy-shell shell rescanPlugins >/dev/null
# The plugin's tab strip takes the place of the numbered workspaces widget.
# An entry in the service-only `plugins` list (from version 0.1) stops the
# shell from adding it to the bar, so clear that first.
shell_json="$HOME/.config/omarchy/shell.json"
if ! jq -e '[.bar.layout[][]?.id] | index("frame.dashboard")' "$shell_json" >/dev/null; then
  if jq -e '[.plugins[]?.id] | index("frame.dashboard")' "$shell_json" >/dev/null; then
    omarchy-plugin-disable frame.dashboard >/dev/null
  fi
  # The manifest rescan runs in the background; wait until it knows the widget.
  for _ in $(seq 20); do
    [[ $(omarchy-shell shell putBarWidget frame.dashboard '{"section":"left","after":"omarchy.menu"}') == ok ]] && break
    sleep 1
  done
fi
omarchy-plugin-disable omarchy.workspaces >/dev/null

# The bar clock follows the dashboard's `clock` setting, using Omarchy's own
# presets. shell.json hot-reloads, so this needs no restart.
if [[ $(jq -r '.clock // "12h"' "$config_dir/config.json") == 24h ]]; then
  formats='{"format":"dddd HH:mm","verticalFormat":"HH\n—\nmm"}'
else
  formats='{"format":"dddd h:mm AP","verticalFormat":"h\n—\nmm\nAP"}'
fi
jq --argjson f "$formats" '.bar.layout |= map_values(map(if .id == "omarchy.clock" then . + $f else . end))' \
  "$shell_json" >"$shell_json.tmp" && mv "$shell_json.tmp" "$shell_json"

# A wall dashboard driven by touch and remote agents doesn't use these, and on
# 1 GB of RAM they cost about 60 MB. Indicators and Night Light also launch
# things on stray taps: Indicators' hidden buttons overlap the tab strip and
# open the passwordless-sudo terminal; Night Light needs the missing hyprsunset.
# `omarchy-plugin-enable <id>` undoes any. Not omarchy.background: disabling
# it in a running shell starts BackgroundIntro polling the absent `owe` binary
# every 16 ms, which pins a core and starves shell IPC.
unused=(agents battery bluetooth clipboard dev-gallery disk-speedtest elsewhen emojis
  image-picker indicators keyboard-layout nightlight power reminders remote-session speedtest
  system-update tray weather wifiqr)
enabled=$(omarchy-plugin-list | awk '$2 == "enabled" { print $1 }')
for id in "${unused[@]/#/omarchy.}" frame.keyboard; do
  grep -qx "$id" <<<"$enabled" && omarchy-plugin-disable "$id" >/dev/null
done
# The bar's close button replaces the on-screen keyboard's one job (Esc), and
# Squeekboard holds about 70 MB. port/apply.sh starts the service at login and
# owns its unit file, so gate it with a drop-in instead of editing or masking
# it: `touch ~/.config/frame-keyboard-on` and log in again to bring it back.
mkdir -p "$HOME/.config/systemd/user/frame-keyboard.service.d"
printf '[Unit]\nConditionPathExists=%%h/.config/frame-keyboard-on\n' \
  >"$HOME/.config/systemd/user/frame-keyboard.service.d/dashboard.conf"
systemctl --user daemon-reload
[[ -e $HOME/.config/frame-keyboard-on ]] || systemctl --user stop frame-keyboard.service

# Hot reload keeps the running instance and Qt's cached component, so an
# update only takes effect in a fresh shell.
if (( update )); then
  omarchy-restart-shell
fi
