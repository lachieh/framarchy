import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "model.js" as Model
import "home.js" as Home

// Home dashboard: a layer surface under app windows, so it is the home screen
// whenever nothing else is open. Each Hyprland workspace listed in
// config.spaces shows its own page; the bar's tab strip (SpacesWidget) and
// Super+number switch between them. Runs as an Omarchy service plugin inside
// the existing shell process. See docs/dashboard.md.
//
// This item is also the store the pages read from (`s` in each page).
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string configPath: Quickshell.env("HOME") + "/.config/frame-dashboard/config.json"
  property var config: Model.mergeConfig("{}").config
  property string configError: ""
  // Everything visual comes from Omarchy's theme, as in its own panels: the
  // palette from Commons.Color, and font, sizes, spacing and corners from
  // Style. Lit and running things take the accent, problems the urgent colour.
  readonly property color fg: Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.5)
  readonly property color bg: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property color alertColor: Commons.Color.urgent

  function toneColor(tone) {
    return tone === "alert" ? root.alertColor : tone === "ok" ? root.fg : root.accent
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text(), "")
    onLoadFailed: root.applyConfig("{}", "No config at ~/.config/frame-dashboard/config.json")
    onFileChanged: reload()
  }

  // Walls and room outlines from UniFi Innerspace (tools/floorplan-from-unifi.py).
  property var floorplan: null

  FileView {
    path: Quickshell.env("HOME") + "/.config/frame-dashboard/floorplan.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.floorplan = JSON.parse(text()) } catch (e) { root.floorplan = null; console.warn("frame.dashboard: floorplan.json:", e) }
      root.demoRaw = Home.demoRaw(root.config, Date.now(), root.floorplan)
      root.fetchHome()
    }
    onLoadFailed: root.floorplan = null
    onFileChanged: reload()
  }

  function applyConfig(raw, missing) {
    var merged = Model.mergeConfig(raw)
    root.config = merged.config
    root.configError = missing || merged.error
    root.demoRaw = Home.demoRaw(root.config, Date.now(), root.floorplan)
    root.refreshAll()
    root.applyBacklight()
  }

  function refreshAll() {
    root.fetchWeather()
    root.fetchAlerts()
    root.fetchHome()
    root.fetchTodo()
    root.fetchClocks()
  }

  // ---------------------------------------------------------------- HTTP

  // QML's XMLHttpRequest has no timeout, so a watchdog aborts stalled calls.
  property var inflight: []

  function request(method, url, headers, body, timeoutMs, done) {
    var xhr = new XMLHttpRequest()
    var entry = { xhr: xhr, deadline: Date.now() + timeoutMs, finished: false, done: done }
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || entry.finished) return
      entry.finished = true
      if (xhr.status >= 200 && xhr.status < 300) {
        var json = null
        try { json = xhr.responseText ? JSON.parse(xhr.responseText) : null } catch (e) { json = null }
        done(true, json, "", xhr.responseText)
      } else {
        done(false, null, xhr.status === 0 ? "unreachable" : "HTTP " + xhr.status, xhr.responseText)
      }
    }
    xhr.open(method, url)
    for (var name in headers) xhr.setRequestHeader(name, headers[name])
    if (body === undefined) xhr.send()
    else xhr.send(body)
    root.inflight = root.inflight.concat([entry])
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.inflight.length > 0
    onTriggered: {
      var now = Date.now()
      var keep = []
      for (var i = 0; i < root.inflight.length; i++) {
        var entry = root.inflight[i]
        if (entry.finished) continue
        if (now < entry.deadline) { keep.push(entry); continue }
        entry.finished = true
        entry.xhr.abort()
        entry.done(false, null, "timed out", "")
      }
      root.inflight = keep
    }
  }

  // ---------------------------------------------------------------- clock

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.fetchClocks()
  }

  readonly property date now: clock.date
  readonly property bool nightTime: Model.isNight(clock.date.getHours(), clock.date.getMinutes(), root.config.night)
  property bool awake: false
  readonly property bool nightView: root.nightTime && !root.awake

  Timer {
    id: wakeTimer
    interval: 60000
    onTriggered: root.awake = false
  }

  function wake() {
    root.awake = true
    wakeTimer.restart()
  }

  onNightTimeChanged: root.applyBacklight()
  // Home Assistant isn't polled behind the night view; catch up on waking.
  onNightViewChanged: if (!root.nightView) root.fetchHome()

  // Needs write access to the backlight; install.sh adds a udev rule for the
  // video group.
  Process { id: backlight }

  function applyBacklight() {
    var level = root.nightTime ? root.config.night.brightness : root.config.night.dayBrightness
    if (typeof level !== "number") return
    backlight.command = ["brightnessctl", "-q", "set", level + "%"]
    backlight.running = true
  }

  // QML has no Intl, so other zones come from `date` (as omarchy.elsewhen does).
  property var otherClocks: []

  Process {
    id: clockProbe
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        var out = []
        for (var i = 0; i < root.config.clocks.length && i < lines.length; i++) {
          var f = lines[i].split(" ")
          out.push({ label: root.config.clocks[i].label, time: Model.formatClock(Number(f[0]), Number(f[1]), root.config.clock), day: f[2] })
        }
        root.otherClocks = out
      }
    }
  }

  function fetchClocks() {
    var zones = (root.config.clocks || []).map(function(c) { return c.zone })
    if (zones.length === 0) { root.otherClocks = []; return }
    if (clockProbe.running) return
    clockProbe.command = ["sh", "-c", "for z in \"$@\"; do TZ=\"$z\" date '+%-H %-M %a'; done", "sh"].concat(zones)
    clockProbe.running = true
  }

  // ---------------------------------------------------------------- spaces

  readonly property int workspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
  readonly property string page: Model.pageFor(root.config, root.workspace)

  function goToSpace(id) {
    Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  // ---------------------------------------------------------------- weather

  property var weather: null
  property double weatherAt: 0
  property string weatherError: ""
  property var alerts: []

  function fetchWeather() {
    if (!Model.hasLocation(root.config)) { root.weatherError = "Set location in config.json"; return }
    root.request("GET", Model.weatherUrl(root.config), {}, undefined, 20000, function(ok, json, error) {
      if (!ok || !json) { root.weatherError = error || "bad response"; return }
      try {
        root.weather = Model.parseForecast(json, root.config.clock)
        root.weatherAt = Date.now()
        root.weatherError = ""
      } catch (e) {
        root.weatherError = "could not read forecast"
        console.warn("frame.dashboard: forecast parse failed:", e)
      }
    })
  }

  // NWS covers the US only; elsewhere the request fails and no banner shows.
  function fetchAlerts() {
    if (!Model.hasLocation(root.config) || root.config.units !== "us") { root.alerts = []; return }
    root.request("GET", Model.alertsUrl(root.config), { "Accept": "application/geo+json", "User-Agent": "frame157-dashboard" }, undefined, 20000,
      function(ok, json) { if (ok && json) root.alerts = Model.parseAlerts(json) })
  }

  Timer { interval: 15 * 60000; repeat: true; running: true; onTriggered: root.fetchWeather() }
  Timer { interval: 5 * 60000; repeat: true; running: true; onTriggered: root.fetchAlerts() }

  // ---------------------------------------------------------------- Home Assistant

  // Without a token the pages run on demo state in Home Assistant's own shape
  // (home.js demoRaw), and actions change it as Home Assistant would.
  readonly property var ha: root.config.homeAssistant
  readonly property bool demo: !(root.ha.url && root.ha.token)
  property var demoRaw: Home.demoRaw(Model.DEFAULT_CONFIG, Date.now(), null)
  property var liveRaw: null
  property string haError: ""
  property string pending: ""
  readonly property var home: Home.buildHome(root.config, root.demo ? root.demoRaw : (root.liveRaw || { lights: {}, states: {} }), clock.date.getTime(), root.floorplan)
  // Shown on every Home Assistant card so demo data is never mistaken for the house.
  readonly property string haStatus: root.demo ? "Demo data" : root.haError ? "Home Assistant " + root.haError : root.liveRaw ? "" : "Connecting…"

  property var todoItems: Model.DEMO_TODO
  property string todoError: ""
  property double todoAt: 0

  function haRequest(path, body, done) {
    var base = String(root.ha.url).replace(/\/+$/, "")
    root.request("POST", base + path, { "Authorization": "Bearer " + root.ha.token, "Content-Type": "application/json" },
      JSON.stringify(body), 10000, done)
  }

  function fetchHome() {
    if (root.demo) return
    var ids = Home.entityIds(Home.homeConfig(root.config, root.floorplan))
    root.haRequest("/api/template", { template: Home.liveTemplate(ids) }, function(ok, json, error, text) {
      if (!ok) { root.haError = error; return }
      try {
        root.liveRaw = Home.parseLive(text)
        root.haError = ""
      } catch (e) {
        root.haError = "sent an unexpected reply"
        console.warn("frame.dashboard: home parse failed:", e, text)
      }
    })
  }

  // Every action goes through here: a service call live, a state change in demo.
  function call(service, data) {
    if (root.demo) {
      root.demoRaw = Home.applyDemo(root.demoRaw, { service: service, data: data })
      return
    }
    root.pending = service + JSON.stringify(data)
    root.haRequest("/api/services/" + service, data, function(ok, json, error) {
      root.pending = ""
      if (!ok) root.haError = error
      root.fetchHome()
    })
  }

  function toggleRoom(room) {
    var action = Home.roomToggle(room)
    root.call(action.service, action.data)
  }

  function allOff() { root.call("light/turn_off", { entity_id: "all" }) }

  function fetchTodo() {
    if (root.demo) { root.todoAt = Date.now(); return }
    root.haRequest("/api/services/todo/get_items?return_response", { entity_id: root.ha.todo, status: "needs_action" },
      function(ok, json, error) {
        if (!ok) { root.todoError = error; return }
        root.todoItems = Model.parseTodo(json, root.ha.todo)
        root.todoAt = Date.now()
        root.todoError = ""
      })
  }

  function completeItem(item) {
    root.todoItems = root.todoItems.filter(function(i) { return i.uid !== item.uid })
    if (root.demo) return
    root.haRequest("/api/services/todo/update_item", { entity_id: root.ha.todo, item: item.uid, status: "completed" },
      function(ok, json, error) {
        if (!ok) root.todoError = error
        root.fetchTodo()
      })
  }

  onDemoChanged: {
    root.liveRaw = null
    root.todoItems = root.demo ? Model.DEMO_TODO : []
    root.fetchTodo()
  }

  Timer { interval: 20000; repeat: true; running: !root.demo && !root.nightView; onTriggered: root.fetchHome() }
  Timer { interval: 60000; repeat: true; running: !root.demo; onTriggered: root.fetchTodo() }

  // ---------------------------------------------------------------- surface

  PanelWindow {
    id: surface
    screen: Quickshell.screens[0]
    // Workspaces without a page are plain desktops showing the wallpaper.
    visible: root.page !== "" || root.nightView
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    // Opaque, so the compositor does less blending of the wallpaper under it
    // on every frame; compositing is the bottleneck while the plan turns.
    color: root.nightView ? "black" : root.bg
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "frame-dashboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      id: pages
      anchors { fill: parent; margins: Style.gapsOut * 2 }
      visible: !root.nightView

      // The current page loads first; the rest build in the background once
      // the shell has settled, so a first visit doesn't stall for the
      // second or so a page takes to compile on this CPU. A page that's
      // opened while still building finishes synchronously.
      Timer { id: preload; interval: 8000; running: true }

      Repeater {
        model: ["today", "home", "car", "devices"]
        Loader {
          required property string modelData
          property bool visited: false
          readonly property bool current: root.page === modelData
          onCurrentChanged: if (current) visited = true
          Component.onCompleted: if (current) visited = true
          anchors.fill: parent
          active: visited || !preload.running
          asynchronous: !current
          visible: current
          source: ({ today: "TodayPage.qml", home: "HomePage.qml", car: "CarPage.qml", devices: "DevicesPage.qml" })[modelData]
          onLoaded: item.s = root
        }
      }

      // Swipe sideways to move between paged workspaces.
      DragHandler {
        target: null
        yAxis.enabled: false
        grabPermissions: PointerHandler.CanTakeOverFromItems
        property real lastX: 0
        onTranslationChanged: lastX = translation.x
        onActiveChanged: {
          if (active || Math.abs(lastX) < 90) return
          root.goToSpace(Model.neighbourSpace(root.config, root.workspace, lastX < 0 ? 1 : -1))
          lastX = 0
        }
      }
    }

    // ------------------------------------------------------------ night

    Item {
      anchors.fill: parent
      visible: root.nightView

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.md
        opacity: 0.4

        PlainText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Model.formatClock(clock.date.getHours(), clock.date.getMinutes(), root.config.clock).replace(/[ap]$/, "")
          font { pixelSize: Style.font.display * 3.5; bold: true }
        }
        PlainText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Qt.formatDate(clock.date, "dddd d MMMM")
          font { pixelSize: Style.font.heading; bold: true }
        }
        PlainText {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.weather !== null
          text: root.weather ? root.weather.temp + "° now · tomorrow " + root.weather.daily[0].hi + "° / " + root.weather.daily[0].lo + "°" : ""
          font.pixelSize: Style.font.body
        }
      }

      MouseArea { anchors.fill: parent; onClicked: root.wake() }
    }
  }
}
