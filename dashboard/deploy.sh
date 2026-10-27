#!/bin/bash
# Copy the dashboard to the frame over SSH and install it.
# Usage: dashboard/deploy.sh [host]   (default frame@frame157.local)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
host=${1:-frame@frame157.local}
ssh_opts=(-o UserKnownHostsFile=/tmp/frame157_known -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=8)

COPYFILE_DISABLE=1 tar --no-xattrs -C "$here" -cf - install.sh config.example.json plugin system \
  | ssh "${ssh_opts[@]}" "$host" 'rm -rf ~/.cache/frame-dashboard-src && mkdir -p ~/.cache/frame-dashboard-src && tar -C ~/.cache/frame-dashboard-src -xf -'
# A QML syntax error only shows up as a blank page and a line in the shell
# log, so check syntax with the frame's own Qt before installing.
ssh "${ssh_opts[@]}" "$host" 'cd ~/.cache/frame-dashboard-src/plugin && ! /usr/lib/qt6/bin/qmllint --compiler disable --unqualified disable --import disable *.qml 2>&1 | grep -A2 "\[syntax\]"' \
  || { echo "QML syntax errors; not installing." >&2; exit 1; }
ssh "${ssh_opts[@]}" "$host" \
  'export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/$(id -u)/hypr | head -1); ~/.cache/frame-dashboard-src/install.sh'
# The house's floor plan stays out of git (dashboard/private/); send it if present.
if [[ -f $here/private/floorplan.json ]]; then
  ssh "${ssh_opts[@]}" "$host" 'umask 077 && cat > ~/.config/frame-dashboard/floorplan.json' < "$here/private/floorplan.json"
fi
