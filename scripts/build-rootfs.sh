#!/usr/bin/env bash
# Build the FRAME157 root filesystem: Arch Linux ARM + pinned Omarchy with the
# frame port (port/) applied offline, our kernel modules, and a USB console
# (ACM login + NCM network with SSH) for when the display is not up.
# Output: build/rootfs/frame157-rootfs.ext4 (label FRAME157ROOT)
# Needs: build/downloads/ArchLinuxARM-aarch64-latest.tar.gz (fetch-rootfs.sh)
#        build/kernel/modules.tar.gz (build-kernel.sh)
set -euo pipefail

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/rootfs
LOGS=$ROOT/build/logs/rootfs
TARBALL=$ROOT/build/downloads/ArchLinuxARM-aarch64-latest.tar.gz
MODULES=$ROOT/build/kernel/modules.tar.gz
# IMAGE may name a snapshot of an earlier run whose packages are installed.
IMAGE=${IMAGE:-framarchy-alarm-base}
CONTAINER=framarchy-rootfs-build
SIZE=${SIZE:-7G}

for input in "$TARBALL" "$MODULES"; do
  [[ -f $input ]] || { echo "missing input: $input" >&2; exit 1; }
done
mkdir -p "$OUT" "$LOGS"
rm -f "$OUT"/frame157-rootfs.*

docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || docker import --platform linux/arm64 "$TARBALL" "$IMAGE" >/dev/null
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

# Stage 1: install and configure inside Arch Linux ARM.
docker run --name "$CONTAINER" --platform linux/arm64 -v "$ROOT":/repo:ro \
  "$IMAGE" /bin/bash -euxo pipefail -c '
export LANG=C.UTF-8
# pacman 7 sandboxes downloads with Landlock, unavailable in Docker.
grep -q "^DisableSandbox" /etc/pacman.conf \
  || sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
sed -i "s/^#\?IgnorePkg.*/IgnorePkg = linux-aarch64 linux-aarch64-headers/" /etc/pacman.conf
pacman-key --init
pacman-key --populate archlinuxarm
mapfile -t pkgs < <(grep -v "^#" /repo/port/packages.txt | tr " " "\n" | grep .)
pacman -Syu --noconfirm --needed "${pkgs[@]}" sudo openssh python git \
  fontconfig xdg-user-dirs
# Our kernel comes from this repository.
pacman -Rdd --noconfirm linux-aarch64 2>/dev/null || true
rm -rf /boot/*
rm -rf /var/cache/pacman/pkg/*

# Kernel modules.
tar -C /usr -xzf /repo/build/kernel/modules.tar.gz
for release in /usr/lib/modules/*; do depmod -b /usr "$(basename "$release")"; done

# Identity, locale, users.
echo frame157 > /etc/hostname
sed -i "s/^#en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen && locale-gen >/dev/null
echo LANG=en_US.UTF-8 > /etc/locale.conf
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
userdel -r alarm 2>/dev/null || true
id frame >/dev/null 2>&1 || useradd -m -u 1000 -G wheel,video,input,audio,render,seat -s /bin/bash frame
echo frame:frame | chpasswd
passwd -l root >/dev/null
echo "frame ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/frame
chmod 440 /etc/sudoers.d/frame

# Pinned Omarchy, the way port/bootstrap.sh installs it.
OMARCHY_COMMIT=$(sed -n "s/^OMARCHY_COMMIT=//p" /repo/port/bootstrap.sh)
# One tarball download: a blobless clone + git archive stalls fetching blobs.
runuser -u frame -- bash -euo pipefail -c "
  o=\$HOME/.local/share/omarchy; tmp=\$(mktemp -d)
  curl -fsSL https://github.com/basecamp/omarchy/archive/$OMARCHY_COMMIT.tar.gz \
    | tar -xz -C \$tmp --strip-components=1
  rm -rf \$o && mkdir -p \$o && cp -a \$tmp/{bin,shell,config,default,themes,version} \$o/
  echo $OMARCHY_COMMIT > \$o/.pinned-commit
  mkdir -p \$HOME/.config && cp -a \$o/config/. \$HOME/.config/
  rm -rf \$tmp
"

# port/apply.sh offline: systemd is not running in the build, so "--now",
# daemon-reload and per-user enables go through a shim, and the last three
# commands (they talk to a running Omarchy session) move to the first login.
shim=/tmp/frame-shim; mkdir -p $shim
cat > $shim/systemctl <<'"'"'SH'"'"'
#!/bin/bash
args=(); user=0
for a in "$@"; do
  case $a in --now) ;; --user) user=1 ;; daemon-reload) exit 0 ;; *) args+=("$a") ;; esac
done
if (( user )); then exec /usr/bin/systemctl --global "${args[@]}"; fi
exec /usr/bin/systemctl "${args[@]}"
SH
chmod 755 $shim/systemctl
# apply.sh also runs "sudo systemctl", and sudo resets PATH to secure_path,
# whose first entry is /usr/local/sbin: put the shim there for the build only.
install -m755 $shim/systemctl /usr/local/sbin/systemctl
rm -rf /tmp/port && cp -r /repo/port /tmp/port
deferred="omarchy-toggle-idle|omarchy-display-text-size|omarchy-plugin-enable"
grep -E "^($deferred) " /tmp/port/apply.sh > /tmp/port/first-session.sh
sed -i -E "/^($deferred) /d" /tmp/port/apply.sh
runuser -u frame -- env PATH=$shim:/usr/local/bin:/usr/bin HOME=/home/frame \
  bash /tmp/port/apply.sh
rm /usr/local/sbin/systemctl
install -Dm755 /tmp/port/first-session.sh /home/frame/.local/bin/frame-first-session
sed -i "1i #!/bin/bash\n# Deferred from port/apply.sh: needs a running Omarchy session.\nexport PATH=\$HOME/.local/share/omarchy/bin:\$PATH" \
  /home/frame/.local/bin/frame-first-session
cat >> /home/frame/.config/hypr/autostart.lua <<'"'"'LUA'"'"'

-- FRAME157 first session: run once, then remove the marker.
o.launch_on_start("bash -c \"[ -e ~/.local/state/frame-first-session.done ] || { ~/.local/bin/frame-first-session && touch ~/.local/state/frame-first-session.done; }\"")
LUA
chown -R frame:frame /home/frame

# USB console: ACM (login) + NCM (network, SSH) gadget.
install -Dm755 /repo/rootfs/frame-usb-gadget /usr/local/bin/frame-usb-gadget
install -Dm644 /repo/rootfs/frame-usb-gadget.service /etc/systemd/system/frame-usb-gadget.service
install -Dm644 /repo/rootfs/usb0.network /etc/systemd/network/50-usb0.network
install -Dm755 /repo/rootfs/frame-bootlog /usr/local/bin/frame-bootlog
install -Dm644 /repo/rootfs/frame-bootlog.service /etc/systemd/system/frame-bootlog.service
systemctl enable frame-bootlog.service frame-usb-gadget.service serial-getty@ttyGS0.service \
  systemd-networkd.service systemd-resolved.service sshd.service

install -Dm644 /repo/rootfs/fstab /etc/fstab
pacman -Q > /tmp/packages.txt
' 2>&1 | tee "$LOGS/build.log"

# Stage 2: pack the tree into an ext4 image (Debian has mke2fs -d).
docker export "$CONTAINER" > "$OUT/rootfs.tar"
docker cp "$CONTAINER":/tmp/packages.txt "$OUT/packages.txt"
docker rm "$CONTAINER" >/dev/null
docker run --rm --platform linux/arm64 -v "$OUT":/out -e SIZE="$SIZE" \
  debian:trixie-slim bash -euo pipefail -c '
apt-get update -qq && apt-get install -y -qq e2fsprogs >/dev/null
mkdir /tree && tar -C /tree --numeric-owner -xpf /out/rootfs.tar
rm -f /tree/.dockerenv
# Docker bind-mounts these into the build container, so docker export leaves
# them empty: write them here.
echo frame157 > /tree/etc/hostname
printf "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 frame157\n" > /tree/etc/hosts
ln -sf /run/systemd/resolve/stub-resolv.conf /tree/etc/resolv.conf
truncate -s "$SIZE" /out/frame157-rootfs.ext4
mke2fs -q -t ext4 -L FRAME157ROOT -U 15715700-0157-4000-8000-000000000157 \
  -d /tree /out/frame157-rootfs.ext4
e2fsck -fn /out/frame157-rootfs.ext4
' 2>&1 | tee -a "$LOGS/build.log"
rm "$OUT/rootfs.tar"
(cd "$OUT" && shasum -a 256 frame157-rootfs.ext4 > SHA256SUMS)
echo "rootfs: $OUT/frame157-rootfs.ext4 ($(wc -l < "$OUT/packages.txt") packages)"
