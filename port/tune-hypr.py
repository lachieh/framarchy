#!/usr/bin/env python3
"""FRAME157 display and touch settings for Hyprland.

1920x1080 panel at 1.5 scale (1280x720 logical) and GTK scale 1.
Touch is mapped to the DSI output; set FRAME_TOUCH_TRANSFORM once measured
with `evtest` / `wev -f wl_touch`.
"""
import os
import pathlib
import re

hypr = pathlib.Path.home() / ".config/hypr"


def set_local(path, name, value):
    text = path.read_text()
    new, n = re.subn(rf"^(local {name}\s*=\s*).*$", rf"\g<1>{value}", text, flags=re.M)
    if n != 1:
        raise SystemExit(f"{name} not found once in {path}; review upstream change")
    if new != text:
        backup = path.with_name(path.name + ".before-frame")
        if not backup.exists():
            backup.write_text(text)
        path.write_text(new)


monitors = hypr / "monitors.lua"
set_local(monitors, "omarchy_monitor_scale", os.environ.get("FRAME_SCALE", "1.5"))
set_local(monitors, "omarchy_gdk_scale", "1")

inp = hypr / "input.lua"
marker = "-- FRAME157 touch"
text = inp.read_text()
if marker not in text:
    transform = os.environ.get("FRAME_TOUCH_TRANSFORM", "0")
    output = os.environ.get("FRAME_OUTPUT", "DPI-1")
    inp.write_text(text + f'\n{marker}\nhl.config({{\n  input = {{ touchdevice = {{ transform = {transform}, output = "{output}" }} }},\n}})\n')
