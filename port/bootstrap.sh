#!/bin/bash
# Install pinned Omarchy on FRAME157. Run on the frame as user "frame",
# from a checkout of this repository, once the board boots with working
# display (DRM card + Panfrost) and network.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OMARCHY_COMMIT=defbf90e893e741067e48f4a27d2ec694c71358e
OMARCHY_PATH=$HOME/.local/share/omarchy

[[ $(uname -m) == aarch64 ]] || { echo "STOP: needs aarch64"; exit 1; }
[[ $(id -un) == frame ]] || { echo "STOP: run as user frame"; exit 1; }
grep -qa rockchip,rk3326 /proc/device-tree/compatible || { echo "STOP: not an RK3326"; exit 1; }
[[ -e /dev/dri/card0 && -e /dev/dri/renderD128 ]] || { echo "STOP: no DRM/GPU device yet"; exit 1; }
if [[ -f $HOME/.config/hypr/hyprland.lua ]]; then
  echo "STOP: ~/.config/hypr already exists; move it away to reinstall"; exit 1
fi

sudo pacman-key --init
sudo pacman-key --populate archlinuxarm
# The kernel and DTB come from this repository, not from pacman.
sudo sed -i 's/^#\?IgnorePkg.*/IgnorePkg = linux-aarch64 linux-aarch64-headers/' /etc/pacman.conf
mapfile -t pkgs < <(grep -v '^#' "$here/packages.txt" | tr ' ' '\n' | grep .)
sudo pacman -Syu --needed --noconfirm "${pkgs[@]}"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git clone -q --filter=blob:none --no-checkout https://github.com/basecamp/omarchy.git "$tmp/o"
git -C "$tmp/o" fetch -q --depth 1 origin "$OMARCHY_COMMIT"
git -C "$tmp/o" archive FETCH_HEAD bin shell config default themes version | tar -x -C "$tmp"
rm -rf "$OMARCHY_PATH"; mkdir -p "$OMARCHY_PATH"
cp -a "$tmp"/{bin,shell,config,default,themes,version} "$OMARCHY_PATH/"
echo "$OMARCHY_COMMIT" > "$OMARCHY_PATH/.pinned-commit"
mkdir -p "$HOME/.config"
cp -a "$OMARCHY_PATH/config/." "$HOME/.config/"

bash "$here/apply.sh"
echo "Omarchy installed. Reboot to start the session on the panel."
