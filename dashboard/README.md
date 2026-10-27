# Home dashboard plugin

`frame.dashboard` is an Omarchy shell plugin. Its service draws the home screen
on the frame's `Bottom` layer: below app windows, above the wallpaper, clear of
the bar. Design and feature plan: [docs/dashboard.md](../docs/dashboard.md).

## Spaces

Dashboard pages live on Hyprland workspaces, so the usual Omarchy moves still
work: Super+1…4, the bar, and apps opened on a space cover that page until they
close.

| Workspace | Page | Shows |
| --- | --- | --- |
| 1 | Today | Clock, weather and alerts, the house at a glance, shopping list, room lights |
| 2 | Home | 3D floor plan from UniFi Innerspace, ground and basement (tap a room for its lights, drag to turn the house), AC, the room's temperature and Hue scenes |
| 3 | Car | Tesla battery, range and charging, location, lock, climate, charge port, sentry |
| 4 | Devices | Washer, dryer, dishwasher, fridge, doors, garage, leak sensor, vacuum |
| 5+ | — | Plain desktops |

The plugin's bar widget replaces `omarchy.workspaces` with a tab strip: the
focused space shows its name, the others their icon, and a dot marks a space
with windows open. Swipe sideways on a page to move to the next one. While
the focused space has a window open, a ✕ after the tabs closes it; with no
keyboard attached, that replaces Esc.
`omarchy plugin enable omarchy.workspaces` brings the numbered widget back.

## Demo mode

With no Home Assistant token, every Home Assistant view runs on demo state and
says "Demo data" in its header. The demo is built as Home Assistant states
(`home.js` `demoRaw`), and taps change it the way Home Assistant would, so the
live path uses the same mapping code. Add the token and the views switch to the
real house within seconds.

## Files

| Path | What |
| --- | --- |
| `plugin/Dashboard.qml` | The store: config, weather, Home Assistant (live or demo), actions, night mode, current workspace; hosts the pages |
| `plugin/TodayPage.qml`, `HomePage.qml`, `CarPage.qml`, `DevicesPage.qml` | The pages |
| `plugin/FloorPlan.qml` | The 3D floor plan: shapes built once, turned by one matrix from `home.js` |
| `plugin/SpacesWidget.qml` | Bar tab strip and close button |
| `plugin/model.js` | Weather, alerts, clock, night window, spaces |
| `plugin/home.js` | Entity mapping, demo state, floor plan view matrix and hit testing |
| `plugin/Card.qml`, `ActionButton.qml`, `PlainText.qml`, `Glyph.qml` | Shared UI in Omarchy's style (see Style); `ActionButton` can require a 0.9 s hold |
| `config.example.json` | Settings template; the live copy is `~/.config/frame-dashboard/config.json` on the frame |
| `system/90-frame-backlight.rules` | Lets the `video` group set the backlight for night dimming |
| `install.sh` | Runs on the frame: copies the plugin, creates the config once, places the bar widget, sets the bar clock to the dashboard's 12h/24h setting, turns off unused Omarchy parts |
| `deploy.sh` | Runs on the Mac: checks QML syntax on the frame, runs `install.sh`, sends `private/floorplan.json` |
| `tools/floorplan-from-unifi.py` | Builds `floorplan.json` from an Innerspace project and `rooms.json` |
| `test/` | `node --test dashboard/test/*.test.mjs` |

## Style

The dashboard follows Omarchy's own panels, and the theme drives it the same
way. There is no Omarchy design document; the reference is the shell itself:
`shell/Commons/Style.qml` (tokens), `Commons/Color.qml` (palette and surface
colours), the `shell/Ui` components, and "Theme tokens" in Omarchy's
`docs/omarchy-shell.md`.

- Font, sizes and spacing: `Style.font.*`, `Style.spacing.*` and `Style.space(px)`.
  The theme's `[font] base-size` scales all of them; the frame uses 18, which
  is 1.5 times Omarchy's default of 12.
- Corners: `Style.cornerRadius`, which copies Hyprland's rounding (0 on the
  frame, so everything is square).
- Cards and device tiles are popup surfaces (`Commons.Color.popups`, border
  `Style.space(2)` wide) with a `PanelSectionHeader` title.
- Buttons use the fills and borders of Omarchy's bordered `Button` (normal,
  pressed, selected). Room lights are Omarchy's `Toggle`.
- Colour: foreground, and Omarchy's darker foreground for secondary text.
  Lit rooms, running appliances and anything needing a look use the theme
  accent; alerts use urgent. The frame runs the Retro 82 theme (`omarchy theme
  set retro-82`, 2026-10-26): navy background, cream text, orange accent.
- The focused space's tab carries the bar's open-panel underline; empty
  spaces are dimmed, as in `omarchy.workspaces`.

Text goes through `PlainText.qml`, which never interprets markup, as Omarchy's
plugin guide asks for text that comes from the network.

## Floor plan

The Home page draws `~/.config/frame-dashboard/floorplan.json`: the walls of
each floor from UniFi Innerspace, extruded as a low cut-away, and room
outlines tagged with Home Assistant areas. Innerspace stores walls but not
rooms, so the room outlines are written by hand in `dashboard/private/rooms.json`
in Innerspace plan units. The house's files live in `dashboard/private/`,
which git ignores; `deploy.sh` copies `floorplan.json` to the frame.

To rebuild it after changing the plan in UniFi:

1. Open the floor plan at `https://<console>/network/default/innerspace/…`,
   signed in to the console, and save the reply to
   `/proxy/innerspace/api/project?mode=2D` (browser dev tools, Network tab) as
   `dashboard/private/innerspace-project.json`. Over unifi.ui.com this request
   is not visible: remote access tunnels console traffic over WebRTC.
2. Run:
   ```sh
   dashboard/tools/floorplan-from-unifi.py dashboard/private/innerspace-project.json \
     dashboard/private/rooms.json > dashboard/private/floorplan.json
   dashboard/deploy.sh
   ```

Rooms without an `area` (kitchen, hall, closets) are drawn but can't be
tapped for lights. Every Home Assistant area with lights still appears in
Today's light switches, whether or not it's on the plan.

## Deploy

```sh
dashboard/deploy.sh            # frame@frame157.local
```

An update restarts the Omarchy shell. The shell keeps a running service plugin
and Qt's cached component across hot reloads, so new QML only loads in a fresh
shell.

## Trimmed Omarchy

The frame has 1 GB of RAM and a single-core Mali-G31, so `install.sh` turns
off the Omarchy parts a wall dashboard doesn't use:

- Shell plugins: agents, battery, bluetooth, clipboard, dev gallery, disk and
  network speed tests, elsewhen, emojis, image picker, indicators, keyboard
  layout, night light, power, reminders, remote session, system update, tray,
  weather, Wi-Fi QR, and `frame.keyboard`. `omarchy plugin enable <id>` brings
  one back.
- Squeekboard (`frame-keyboard.service`), through a drop-in that only starts
  it if `~/.config/frame-keyboard-on` exists. Touch that file and log in again
  to get the keyboard back.

Two of those caused the stray shells: Indicators' hidden buttons overlap the
tab strip on a touch screen, so taps near the tabs opened the passwordless-sudo
terminal or toggled night light, whose `hyprsunset` isn't installed.

The wallpaper (`omarchy.background`) stays on. Disabling or suspending it in a
running shell makes Omarchy's `BackgroundIntro` poll the absent `owe` binary
every 16 ms until the shell restarts, which takes a third of a core and can
starve shell IPC.

Measured on 2026-10-26, settled after visiting every page:

| | Before | After |
| --- | --- | --- |
| Shell PSS | 238 MB | 204 MB |
| `MemAvailable` | 265 MB | 354 MB |
| Floor plan while turning | about 4 fps | about 29 fps |
| First visit to Home | 0.9 s CPU | 0.25 s |

The floor plan was a `Canvas` repainted on the CPU every frame. It is now
`Shape` geometry built once and moved by a transform. While it turns, the GPU
is the limit, mostly Hyprland compositing the full screen.

## Configure

Edit `~/.config/frame-dashboard/config.json` on the frame. Changes apply without
a restart.

- `location`, `units` (`us` or `metric`), `clock` (`12h`/`24h`), `clocks`
  (extra zones), `night` (dim window and backlight levels): see
  `config.example.json`.
- `homeAssistant`: `url`, a long-lived access token (profile page, Security
  tab) and the shopping list's to-do entity. The file is mode 600.
- `spaces`: which workspace shows which page (`today`, `home`, `car`,
  `devices`).
- `home`: the house. Every key is optional; defaults are in `home.js`.
  - `rooms`: per-area entity overrides, such as
    `{ "garage": { "temperature": "sensor.workshop_temperature" } }`. By
    default an area's sensors are `sensor.<area>_temperature` and
    `_humidity`, and its scene is Hue's `select.<area>_<area>_scene`.
  - `climate`: the AC's climate entity (default `climate.house`).
  - `devices`: `[{ "name", "kind", "entity", "remaining", "second" }]`, where
    `kind` is one of `washer`, `dryer`, `dishwasher` (`remaining`: minutes or
    a finish-time sensor), `fridge` (`second`: freezer sensor), `lock`,
    `garage`, `door`, `leak` or `vacuum`.
  - `car`: `{ "name", "prefix", "entities" }`. With the Tesla Fleet or
    Teslemetry integration, `prefix` is the vehicle's entity prefix
    (`model_y` gives `sensor.model_y_battery_level` and so on); `entities`
    overrides single ids (see `CAR_ENTITIES` in `home.js`).

## Status (2026-10-26)

Omarchy style, checked on the frame with live Home Assistant data: Today,
Home, Devices and the car page's not-set-up state fit 960x501 at base size 18.
The car page with a car and the weather alert banner were not seen, since
neither had data. Idle CPU stayed at 0%, and shell PSS was 208 MB after all
pages loaded.

Performance work, verified on the frame with injected touch: the numbers in
"Trimmed Omarchy". The close button closed a terminal from a real tap, and
taps across the tab strip no longer launch anything. Room hit testing is
covered by tests; real lights were not toggled from the plan.

## Status (2026-10-24)

Floor plan, verified on the frame: the ground floor (136 Innerspace walls,
14 rooms) and the basement (35 walls, 2 rooms) render. The floor switch works,
and tapping the Sitting room on the plan turned on its demo lights. Room
outlines were checked by drawing them over the Innerspace background image.

Verified on the frame with demo data and real touch events:

- The tab strip switched workspaces, and each workspace showed its page.
  A sideways swipe moved to the next space.
- Floor plan: rendered in 3D. A tap on Sitting Room turned it on and selected
  it, a drag turned the house about 110°, and the reset button appeared.
- Car and Devices pages rendered. A quick tap on Unlock did nothing, a 1.3 s
  hold unlocked, and a tap closed the garage.

Verified live against a throwaway Home Assistant 2026.10 (demo integration):

- The live template returned real climate, lock, cover, moisture and vacuum
  states, and missing entities read as "Not set up".
- From the touchscreen, AC + raised the thermostat target from 21 to 22, and
  Clean started the vacuum.
- Earlier (version 0.1): room lights, "All off" and the shopping list.

Memory: shell PSS was 225 MB with the Today page, 237 MB after visiting all
four pages. The shell alone was 205 MB. Single runs.

Live with the household's Home Assistant (2026-10-24): the frame reaches it at
its LAN address (core serves on port 80) with a token for a dedicated,
local-only "Frame dashboard" user. Real light state shows on the plan and in
the light switches, with the rooms' Hue scenes. Lights were not toggled from
the frame in the evening; toggling was verified against the test instance.

Not yet verified: real Tesla, AC, temperature or appliance entities (none in
Home Assistant yet), and behaviour across a reboot.
