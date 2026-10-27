# Memory and mouse-style touch

## Settings editor

Settings actions displayed the editing toast but launched no editor because
Omarchy fell back to `nvim`, which this minimal installation does not include.
Nano is installed and supported by `omarchy-launch-editor`. The frame's
`~/.local/state/omarchy/defaults/editor` now contains `nano`.
`port/packages.txt` explicitly includes Nano, and `port/apply.sh` supplies that
default when none exists, preserving an existing editor choice. The real
`omarchy-launch-config-editor ~/.config/hypr/input.lua` path was exercised;
process inspection and a screenshot confirmed Nano displaying the file.
No config content was edited during verification.

## Bar layout lock

The bar originally entered repositioning after four logical pixels of movement
or a 200-ms hold. This is Omarchy's QML gesture handling, separate from
Hyprland window dragging. Accidental touch gestures moved it to the sides.

`port/lock-bar.py` adds `bar.locked` support to the pinned bar implementation.
Frame setup defaults to `locked: true` and restores the initial position to
`top`. While locked, gesture-driven edge moves, widget reordering and
double-tap background changes are blocked; ordinary widget buttons remain
active. Existing explicit `locked` settings and subsequent manual position
choices are preserved on repeated setup. `port/apply.sh` reapplies the patch
idempotently and refuses unknown upstream code instead of silently omitting
the lock. The original QML is saved as `Bar.qml.before-frame-lock`.

Hyprland's touchscreen controls cover mapping, orientation and enabling input.
`binds.drag_threshold` is for window dragging and click/drag keybind flags; it
does not change the bar's threshold. `input.touchpad.tap_to_click`,
`tap_and_drag` and `drag_lock` control touchpads, not this direct touchscreen.
The frame already uses 2x compositor scaling. Further tap/hold/scroll behavior
is largely owned by individual toolkits/applications. See the
[Hyprland variable reference](https://wiki.hypr.land/Configuring/Basics/Variables/).

## On-screen keyboard

The on-screen keyboard is Squeekboard (`frame-keyboard.service`). The
`frame.keyboard` widget is enabled at the start of the bar's right section;
tapping its keyboard icon toggles visibility through `frame-keyboard-toggle`.
On 2026-10-16, the service was verified running, the keyboard was shown through
D-Bus (`Visible=true`), and plugin IPC confirmed the widget enabled.
That did not prove the keyboard drew: the user subsequently reported it was
invisible. Squeekboard's Glycin SVG icon loader was timing out for 60 seconds
per icon inside bubblewrap. A compositor layer existed but did not initially
draw. A keyboard-service-only environment workaround,
`GLYCIN_DISABLE_SANDBOX=i-know-the-risks`, bypasses that sandbox for its packaged
SVG key icons. `port/frame-keyboard.service` now sets it. The initial test
value `1` was ignored; upstream Glycin requires the exact value above.

With the exact setting, a fresh service rendered the keyboard within the
two-second screenshot check, without the icon timeouts. A native-touch input
injection tapped its visible Q and Enter keys into a disposable Python input
client; it received `q` (no entered text was executed). Screenshots confirmed
the keyboard and typed text. The bar's underlying toggle command was also
checked for hide/show. This verifies rendering and input delivery rather than
relying on D-Bus visibility alone. The workaround is scoped to Squeekboard;
the underlying image-loader sandbox stall remains unresolved.

Measured on the running frame on 2026-10-16, using the Mac's clock. The frame's
clock currently reports an incorrect 2017 date.

## Memory

The frame exposes 933 MiB of RAM. Quickshell was the largest resident process.
Zram already helps: roughly 240 MiB of swapped pages occupies about 31-34 MiB
of physical RAM with `lzo-rle`. Keep it enabled. Cached files are reclaimable;
`MemAvailable` is more useful than the free-page count.

The kernel used transparent huge pages unconditionally (`always`). A fresh
Quickshell under that setting had PSS 263,885 KiB, including 124,928 KiB of
anonymous huge pages. Changing to `madvise` and restarting only the shell gave
a settled PSS of about 201,000-205,000 KiB with no anonymous huge pages. Shell
IPC responded and opening/closing the Omarchy menu worked. Late samples showed
about 326-338 MiB available RAM, versus 280 MiB for the fresh baseline.

This is a short idle comparison on one running desktop, not a workload or
long-term leak test. The initial 84-MiB post-restart PSS was a startup sample
and is not the settled result. The practical observed saving is about 60 MiB.

`port/system/hugepages.conf` installs as
`/etc/tmpfiles.d/frame-hugepages.conf`; `port/apply.sh` installs and applies it.
It writes `madvise` to `/sys/kernel/mm/transparent_hugepage/enabled`. It was
applied and read back on the frame. A reboot was not needed or tested for this
change; systemd-tmpfiles supplies persistence on subsequent boots. Existing
processes may retain old allocations until restarted.

Background: [kernel transparent hugepage documentation](https://docs.kernel.org/admin-guide/mm/transhuge.html).

## Mouse-style touch trial

Outcome: the user rejected the feel and requested native touch. The service was
disabled and stopped. Its process exited, and an independent input grab check
verified release of the physical touchscreen. Native touch is restored; the
persistent memory setting remains. Adapter source and module are retained for
reference, with no active input interception.

The user reported touch problems across applications and chose to try mouse
semantics instead of native touch gestures. The running touchscreen is
`silead_ts`, with ABS_X 0..1783 and ABS_Y 0..1159; kernel calibration already
inverts both axes. No second inversion is applied.

`port/touch/frame-touch-mouse.c` exclusively grabs the physical touchscreen
and creates one absolute-position mouse through uinput:

- Finger motion moves the pointer immediately, without a button down.
- A stationary tap emits one left-click on release.
- A stationary hold of 650 ms emits one right-click and suppresses the release
  left-click.
- Movement exceeding 18 physical display pixels cancels the click, even when
  the finger returns to its starting point.
- Multiple fingers cancel clicking until the contact ends.

The movement threshold uses the frame's fixed 1920x1080 panel. The adapter
does not implement native touch scrolling, pinch zoom, wheel scrolling or
left-button dragging. Multi-monitor or rotated-panel mapping has not been
tested. It provides pointer hover while a finger is touching/moving; it cannot
sense a finger hovering above the glass.

The adapter exits on dropped input events rather than continuing with stale
contact state. Closing its input descriptor releases the exclusive grab.
The service does not automatically restart or start at boot during this trial.

The custom kernel originally lacked uinput. `CONFIG_INPUT_UINPUT=m` is now in
the kernel fragment. A module was built against the existing configured Linux
6.18 source/build, installed under the running kernel's module directory,
followed by `depmod -a` and `modprobe uinput`. No kernel replacement or reboot
was required. The C process measured about 1.1 MiB RSS.

### Build and install

After building the matching kernel in Docker volume `frame157-linux`, run:

```sh
scripts/build-touch-mouse.sh
```

This produces `build/touch/frame-touch-mouse`, `uinput.ko`, the kernel release
and module metadata. It also runs gesture-state tests. Deploy the binary as
`/usr/local/bin/frame-touch-mouse`, the module under the matching kernel's
`kernel/drivers/input/misc/` directory, and
`port/touch/frame-touch-mouse.service` under `/etc/systemd/system/`.
Run `depmod -a` and `systemctl daemon-reload` after deployment. Do not install
a module built for a different kernel.

Trial controls on the frame:

```sh
sudo systemctl start frame-touch-mouse
sudo systemctl stop frame-touch-mouse
```

Stopping restores native touch. Once the user is satisfied, persistence can be
enabled with `sudo systemctl enable frame-touch-mouse`. It is now stopped and
disabled following user feedback.

### Verification

Compiled with `-Wall -Wextra -Werror`. Tests in `port/touch/test-touch.c` cover
tap, hold, no duplicate release click, motion and return, and multi-finger
cancellation. A live check injected touch events into the physical input path
and read the virtual mouse events exclusively: tap yielded only BTN_LEFT
press/release, hold only BTN_RIGHT press/release, slide no button events.
Hyprland lists `frame157-touch-mouse` as a mouse. Stopping the service allowed
another process to grab the touchscreen, proving release; the service was
then restarted for the trial. The user subsequently rejected the feel, and the
service was stopped again with release verified.
