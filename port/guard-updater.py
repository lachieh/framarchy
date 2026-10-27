#!/usr/bin/env python3
"""Stop Omarchy helpers that would bulk-install packages or replace the
kernel on this frame. Safe to run again. Needs root for the pacman hook."""
import pathlib
import sys

omarchy = pathlib.Path(sys.argv[1])
guard = ('# FRAME157 guard\n'
         'echo "STOP: bulk Omarchy installs are disabled on this frame (see port/packages.txt)"; exit 1\n')

for name in ("omarchy-reinstall-pkgs", "omarchy-pkg-defaults", "omarchy-apply-system",
             "omarchy-provision-owner", "omarchy-update"):
    path = omarchy / "bin" / name
    if not path.is_file() or "FRAME157 guard" in path.read_text():
        continue
    lines = path.read_text().splitlines(keepends=True)
    at = 1 if lines and lines[0].startswith("#!") else 0
    lines.insert(at, guard)
    backup = path.with_name(name + ".before-frame-guard")
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
    path.write_text("".join(lines))
    print("Guarded", name)

hook = pathlib.Path("/etc/pacman.d/hooks/90-frame157-kernel.hook")
hook.parent.mkdir(parents=True, exist_ok=True)
hook.write_text("""[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = linux-aarch64
Target = linux-aarch64-headers

[Action]
Description = FRAME157: the kernel comes from the framarchy repo, not pacman
When = PreTransaction
Exec = /usr/bin/false
AbortOnFail
""")
print("Wrote", hook)
