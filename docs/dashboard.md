# Home dashboard

The frame becomes the home screen for the house: a touch dashboard that sits
under app windows on the Omarchy desktop. Close an app and the dashboard is
back; there is no mode to toggle.

## Who it is for

What the home setup says about the household (Home Assistant and homelab, as of
2026-10-24):

- A family home on Eastern time, with US units.
- Hue lights in 12 areas, 34 scenes, 8 Google Cast speakers and displays, and a
  shared Home Assistant shopping list. No calendar is connected yet.
- A homelab running self-hosted services.
- Weather is the daily variable: summer storms, tornado and heat
  warnings, and pollen.

## Features

**Done** is on the frame. Home Assistant views run on demo data until a
token is set.

| Status | Feature | Why | Source |
| --- | --- | --- | --- |
| Done | Spaces: a dashboard page per Hyprland workspace, a labelled tab strip, swipe between them | Omarchy's own model: Super+number, apps on a space cover its page | Hyprland, Quickshell |
| Done | Large clock and date, sunrise/sunset, Sydney clock | Readable from across the room | Local clock (NTP-synced) |
| Done | Weather now, next 12 hours, 5 days, out-the-door hints | "Jacket or umbrella today?" | Open-Meteo |
| Done | Severe weather alert banner | Tornado, storm and heat warnings | NWS |
| Done | Home at a glance on Today: AC, car, anything open or finished | One look before leaving | Home Assistant |
| Done | 3D floor plan of both levels: tap a room for its lights, drag to turn the house, temperature per room | See the whole house at once | UniFi Innerspace walls, Home Assistant areas and sensors |
| Done | AC: current and target temperature, mode, cooling/heating state | One AC for the house | `climate` entity |
| Done | Room panel: lights and Hue scenes | Movie night, reading, bedtime | Hue `select.*_scene` |
| Done | Car: battery, range, charging, location, lock, preconditioning, charge port, sentry | The family car | Tesla Fleet / Teslemetry |
| Done | Devices: washer, dryer, dishwasher, fridge, doors, garage, leak, vacuum | "Is the dryer done? Is the garage shut?" | Home Assistant |
| Done | Shopping list: read and tick off | Shared kitchen list | `todo.shopping_list` |
| Done | Night mode | Dim clock after 21:00 | Local clock, backlight |
| Done | Close button in the bar; Omarchy trimmed to what a wall dashboard uses; floor plan on the GPU | Stray windows close without a keyboard; smoother turning, more free RAM | Bar widget, `install.sh` |
| Done | Restyled in Omarchy's style, driven by the theme | Looks like the rest of the desktop and follows theme changes | Omarchy `Style`, `Color`, `qs.Ui` |
| Next | Family calendar: today and tomorrow | Appointments and events | Google/iCloud ICS or HA calendar |
| Next | Routines: bedtime countdown, morning checklist | Readable at a glance | The household's routine |
| Later | Now playing on Cast speakers | Music around the house | `media_player` |
| Later | Photo mode when idle | It is still a photo frame | Shared album folder |
| Later | Energy use, bin day, homelab health | Weekly and background checks | HA energy, config, HTTP |

## Design

- **Runs inside the existing shell.** It is an Omarchy service plugin
  (`frame.dashboard`), so it costs QML objects, not a second Quickshell or
  browser process. 1 GB RAM rules out a browser kiosk: one Chromium tab took
  about 560 MB on the reference frame.
- **Home screen layer.** A `Bottom` layer surface: above the wallpaper, below
  windows, and clear of the bar's reserved area. Its page follows the focused
  workspace.
- **Omarchy's style.** The pages look like Omarchy's own panels and follow
  the theme the same way: palette from `Commons.Color` (lit and running in the
  accent, problems in urgent), and font, type scale, spacing, corners and
  control states from `Style`, with Omarchy's `Toggle` and section headers.
  See "Style" in [dashboard/README.md](../dashboard/README.md).
- **Touch first.** At least 40 logical pixels per target, with no hover. Only
  door, lock and garage actions need a long press. Layout is 960x540 logical pixels (2x scale).
- **Works offline.** Every card shows its own state (loading, stale, not set
  up, unreachable). Weather keeps working when Home Assistant is down.
- **Private settings stay on the frame.** Location, the Home Assistant URL and
  token live in `~/.config/frame-dashboard/config.json` (mode 600), not in the
  repository. See [`dashboard/config.example.json`](../dashboard/config.example.json).

## Layout

Each page fills the 960x501 logical pixels under the bar. See the Spaces table
in [dashboard/README.md](../dashboard/README.md) for what each page shows.

Between 21:00 and 06:30 every page gives way to a dim clock-only view and the
backlight drops. A tap brings the full view back for a minute.

## Status

See the "Status" section of [dashboard/README.md](../dashboard/README.md).
