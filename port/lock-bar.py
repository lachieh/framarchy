#!/usr/bin/env python3
"""Add an opt-in bar layout lock to the pinned Omarchy shell."""
import json
from pathlib import Path
import sys

omarchy = Path(sys.argv[1])
path = omarchy / "shell/plugins/bar/Bar.qml"
text = path.read_text()
changes = [
    ('  property var barConfig: ({})',
     '  property var barConfig: ({})\n  readonly property bool layoutLocked: barConfig.locked === true'),
    ('  function beginBarMove(window) {\n',
     '  function beginBarMove(window) {\n    if (root.layoutLocked) return\n'),
    ('    if (!barMoveActive || !edge || edge === position) {',
     '    if (root.layoutLocked || !barMoveActive || !edge || edge === position) {'),
    ('      if (dragging) return\n      dragging = true',
     '      if (root.layoutLocked || dragging) return\n      dragging = true'),
    ('readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"',
     'readonly property bool canReorder: !root.layoutLocked && root.shell && typeof root.shell.mutateShellConfig === "function"'),
    ('    onDoubleClicked: function(mouse) {\n      if (suppressClick)',
     '    onDoubleClicked: function(mouse) {\n      if (root.layoutLocked) return\n      if (suppressClick)'),
]
for before, after in changes:
    if after in text:
        continue
    if text.count(before) != 1:
        raise SystemExit(f"Bar gesture code changed upstream; review before patching: {before}")
    text = text.replace(before, after)
if text != path.read_text():
    backup = path.with_name("Bar.qml.before-frame-lock")
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
    path.write_text(text)

config_path = Path.home() / ".config/omarchy/shell.json"
config = json.loads(config_path.read_text()) if config_path.exists() else {"version": 1}
bar = config.setdefault("bar", {})
if "locked" not in bar:
    bar["position"] = "top"
    bar["locked"] = True
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config, indent=2) + "\n")
