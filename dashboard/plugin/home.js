.pragma library

// The house: floor plan, climate, appliances and car, shaped from Home
// Assistant state. Demo mode feeds the same code fake states in Home
// Assistant's own shape, so connecting a real instance only changes where
// `raw` comes from. Pure functions; tested in dashboard/test/home.test.mjs.

// The floor plan comes from ~/.config/frame-dashboard/floorplan.json, made from
// UniFi Innerspace by tools/floorplan-from-unifi.py: per floor, wall segments
// and room outlines in metres (y down, as drawn). Rooms with an `area` are
// Home Assistant areas; the rest (kitchen, hall) are drawn but not controlled.
function planRooms(floorplan) {
  var out = []
  var floors = (floorplan && floorplan.floors) || []
  floors.forEach(function(f) {
    f.rooms.forEach(function(r, i) {
      out.push({ id: r.area || f.id + ":" + i, area: r.area || "", name: r.name, floor: f.id, points: r.points })
    })
  })
  return out
}

// Entity ids follow each integration's default naming (Hue names room scenes
// select.<area>_<area>_scene); override per area in config.json home.rooms.
function areaEntities(area, overrides) {
  var o = (overrides && overrides[area]) || {}
  return {
    temperature: o.temperature || "sensor." + area + "_temperature",
    humidity: o.humidity || "sensor." + area + "_humidity",
    scene: o.scene || "select." + area + "_" + area + "_scene"
  }
}

// The household's Home Assistant areas, for demo light state.
var DEMO_AREAS = { garage: "Garage", storage: "Storage", office: "Office", sunroom: "Sunroom", dining_room: "Dining Room",
  sitting_room: "Sitting Room", entryway: "Entryway", lounge_room: "Lounge room", primary_bedroom: "Primary Bedroom",
  bathroom: "Bathroom", kids_room: "Kids' Room", guest_room: "Guest Room" }

var DEFAULT_DEVICES = [
  { name: "Washer", kind: "washer", entity: "sensor.washer_machine_state", remaining: "sensor.washer_remaining_time" },
  { name: "Dryer", kind: "dryer", entity: "sensor.dryer_machine_state", remaining: "sensor.dryer_remaining_time" },
  { name: "Dishwasher", kind: "dishwasher", entity: "sensor.dishwasher_operation_state", remaining: "sensor.dishwasher_remaining_time" },
  { name: "Fridge", kind: "fridge", entity: "sensor.fridge_temperature", second: "sensor.freezer_temperature" },
  { name: "Front door", kind: "lock", entity: "lock.front_door" },
  { name: "Garage door", kind: "garage", entity: "cover.garage_door" },
  { name: "Back door", kind: "door", entity: "binary_sensor.back_door" },
  { name: "Laundry leak", kind: "leak", entity: "binary_sensor.laundry_leak" },
  { name: "Robot vacuum", kind: "vacuum", entity: "vacuum.robot" }
]

// Tesla Fleet / Teslemetry names for a vehicle called "Model Y".
var CAR_ENTITIES = {
  battery: "sensor.{p}_battery_level",
  range: "sensor.{p}_battery_range",
  charging: "sensor.{p}_charging",
  chargerPower: "sensor.{p}_charger_power",
  timeToFull: "sensor.{p}_time_to_full_charge",
  limit: "number.{p}_charge_limit",
  cable: "binary_sensor.{p}_charge_cable",
  chargePort: "cover.{p}_charge_port_door",
  lock: "lock.{p}_lock",
  climate: "climate.{p}_climate",
  outside: "sensor.{p}_outside_temperature",
  location: "device_tracker.{p}_location",
  sentry: "switch.{p}_sentry_mode",
  odometer: "sensor.{p}_odometer"
}

function homeConfig(config, floorplan) {
  var h = config.home || {}
  var car = h.car || {}
  var prefix = car.prefix || "model_y"
  var carEntities = {}
  for (var key in CAR_ENTITIES) carEntities[key] = (car.entities && car.entities[key]) || CAR_ENTITIES[key].replace("{p}", prefix)
  return {
    climate: h.climate || "climate.house",
    rooms: planRooms(floorplan).map(function(r) {
      if (r.area) {
        var e = areaEntities(r.area, h.rooms)
        r.temperature = e.temperature; r.humidity = e.humidity; r.scene = e.scene
      }
      return r
    }),
    devices: h.devices || DEFAULT_DEVICES,
    car: { name: car.name || "Model Y", entities: carEntities }
  }
}

function entityIds(hc) {
  var ids = [hc.climate]
  hc.rooms.forEach(function(r) { ids.push(r.temperature, r.humidity, r.scene) })
  hc.devices.forEach(function(d) { ids.push(d.entity); if (d.remaining) ids.push(d.remaining); if (d.second) ids.push(d.second) })
  for (var k in hc.car.entities) ids.push(hc.car.entities[k])
  return ids.filter(function(id, i) { return id && ids.indexOf(id) === i })
}

// Attributes the views read. Everything else stays on the server.
var ATTRIBUTES = ["current_temperature", "temperature", "current_humidity", "hvac_action", "hvac_modes",
  "min_temp", "max_temp", "options", "unit_of_measurement", "fan_mode", "friendly_name"]

// One request returns light counts per area and the mapped entities' states.
// Missing entities are skipped by expand(), so a partial setup still renders.
function liveTemplate(ids) {
  return "{% set ns = namespace(rooms=[], states=[]) %}"
    + "{% for a in areas() %}"
    + "{% set lights = area_entities(a) | select('match', 'light\\\\.') | reject('is_state', 'unavailable') | list %}"
    + "{% set ns.rooms = ns.rooms + [[a, area_name(a), lights | select('is_state', 'on') | list | count, lights | count]] %}"
    + "{% endfor %}"
    + "{% for s in expand(" + JSON.stringify(ids) + ") %}"
    + "{% set at = namespace(pairs=[]) %}"
    + "{% for k in " + JSON.stringify(ATTRIBUTES) + " %}{% if s.attributes[k] is defined %}{% set at.pairs = at.pairs + [[k, s.attributes[k]]] %}{% endif %}{% endfor %}"
    + "{% set ns.states = ns.states + [[s.entity_id, s.state, at.pairs]] %}"
    + "{% endfor %}"
    + "{{ {'rooms': ns.rooms, 'states': ns.states} | tojson }}"
}

// -> { lights: {area: {name, on, total}}, states: {entity_id: {state, attributes}} }
function parseLive(text) {
  var json = JSON.parse(text)
  var lights = {}
  json.rooms.forEach(function(r) { lights[r[0]] = { name: r[1], on: r[2], total: r[3] } })
  var states = {}
  json.states.forEach(function(s) {
    var attributes = {}
    s[2].forEach(function(p) { attributes[p[0]] = p[1] })
    states[s[0]] = { state: s[1], attributes: attributes }
  })
  return { lights: lights, states: states }
}

function num(states, id) {
  var s = states[id]
  if (!s) return null
  var v = parseFloat(s.state)
  return isNaN(v) ? null : v
}

function stateOf(states, id) { return states[id] ? states[id].state : null }

// Remaining time as minutes, from either a minutes sensor or a finish timestamp.
function minutesLeft(states, id, nowMs) {
  var s = states[id]
  if (!s || s.state === "unknown" || s.state === "unavailable") return null
  var v = Number(s.state)
  if (!isNaN(v)) return Math.round(v)
  var t = Date.parse(s.state)
  return isNaN(t) ? null : Math.max(0, Math.round((t - nowMs) / 60000))
}

function durationText(minutes) {
  if (minutes === null) return ""
  if (minutes < 60) return minutes + " min"
  return Math.floor(minutes / 60) + " h " + (minutes % 60 ? (minutes % 60) + " min" : "")
}

var RUNNING = ["run", "running", "on", "wash", "washing", "rinse", "rinsing", "spin", "spinning", "dry", "drying", "cooling", "active"]
var FINISHED = ["end", "finished", "complete", "completed", "done"]

// Tone drives colour: ok (quiet), active (in use), attention, alert.
function device(d, states, nowMs) {
  var s = stateOf(states, d.entity)
  var out = { name: d.name, kind: d.kind, entity: d.entity, missing: s === null, state: "", detail: "", tone: "ok", action: null }
  if (s === null) { out.state = "Not set up"; return out }
  if (s === "unavailable" || s === "unknown") { out.state = "Unavailable"; out.tone = "attention"; return out }
  var lower = String(s).toLowerCase()
  switch (d.kind) {
  case "washer": case "dryer": case "dishwasher":
    if (RUNNING.indexOf(lower) !== -1) {
      out.state = "Running"; out.tone = "active"
      var left = minutesLeft(states, d.remaining, nowMs)
      out.detail = left !== null ? durationText(left) + " left" : ""
    } else if (FINISHED.indexOf(lower) !== -1) {
      out.state = "Done"; out.tone = "attention"; out.detail = "Ready to unload"
    } else out.state = "Idle"
    break
  case "fridge":
    out.state = Math.round(Number(s)) + "°"
    var freezer = num(states, d.second)
    out.detail = freezer !== null ? "Freezer " + Math.round(freezer) + "°" : ""
    break
  case "lock":
    out.state = lower === "locked" ? "Locked" : lower === "jammed" ? "Jammed" : "Unlocked"
    out.tone = lower === "locked" ? "ok" : lower === "jammed" ? "alert" : "attention"
    out.action = lower === "locked"
      ? { label: "Unlock", confirm: true, service: "lock/unlock", data: { entity_id: d.entity } }
      : { label: "Lock", service: "lock/lock", data: { entity_id: d.entity } }
    break
  case "garage":
    out.state = lower === "closed" ? "Closed" : lower === "open" ? "Open" : lower.charAt(0).toUpperCase() + lower.slice(1)
    out.tone = lower === "closed" ? "ok" : "attention"
    out.action = lower === "closed"
      ? { label: "Open", confirm: true, service: "cover/open_cover", data: { entity_id: d.entity } }
      : { label: "Close", service: "cover/close_cover", data: { entity_id: d.entity } }
    break
  case "door":
    out.state = lower === "on" ? "Open" : "Closed"
    out.tone = lower === "on" ? "attention" : "ok"
    break
  case "leak":
    out.state = lower === "on" ? "Leak!" : "Dry"
    out.tone = lower === "on" ? "alert" : "ok"
    break
  case "vacuum":
    out.state = lower.charAt(0).toUpperCase() + lower.slice(1)
    out.tone = lower === "cleaning" ? "active" : lower === "error" ? "alert" : "ok"
    out.action = lower === "cleaning"
      ? { label: "Dock", service: "vacuum/return_to_base", data: { entity_id: d.entity } }
      : { label: "Clean", service: "vacuum/start", data: { entity_id: d.entity } }
    break
  default:
    out.state = s
  }
  return out
}

function climate(id, states) {
  var s = states[id]
  if (!s) return null
  var a = s.attributes
  return {
    entity: id,
    mode: s.state,
    action: a.hvac_action || (s.state === "off" ? "off" : "idle"),
    current: a.current_temperature !== undefined ? Math.round(a.current_temperature) : null,
    target: a.temperature !== undefined && a.temperature !== null ? Number(a.temperature) : null,
    humidity: a.current_humidity !== undefined ? Math.round(a.current_humidity) : null,
    modes: a.hvac_modes || ["off", "cool", "heat", "heat_cool"],
    min: a.min_temp || 60,
    max: a.max_temp || 86
  }
}

var CHARGING_TEXT = { charging: "Charging", complete: "Charged", stopped: "Plugged in", disconnected: "Unplugged", starting: "Starting", no_power: "No power" }

function car(hc, states, nowMs) {
  var e = hc.car.entities
  if (!states[e.battery]) return null
  var chargingState = stateOf(states, e.charging) || "disconnected"
  var carClimate = states[e.climate]
  var location = stateOf(states, e.location)
  var left = minutesLeft(states, e.timeToFull, nowMs)
  return {
    name: hc.car.name,
    battery: Math.round(num(states, e.battery)),
    range: num(states, e.range) !== null ? Math.round(num(states, e.range)) : null,
    rangeUnit: (states[e.range] && states[e.range].attributes.unit_of_measurement) || "mi",
    charging: chargingState === "charging",
    chargingText: CHARGING_TEXT[chargingState] || chargingState,
    chargerPower: num(states, e.chargerPower),
    timeToFull: chargingState === "charging" && left !== null ? durationText(left) : "",
    limit: num(states, e.limit),
    plugged: stateOf(states, e.cable) === "on",
    portOpen: stateOf(states, e.chargePort) === "open",
    locked: stateOf(states, e.lock) === "locked",
    climateOn: carClimate ? carClimate.state !== "off" : false,
    inside: carClimate && carClimate.attributes.current_temperature !== undefined ? Math.round(carClimate.attributes.current_temperature) : null,
    outside: num(states, e.outside) !== null ? Math.round(num(states, e.outside)) : null,
    home: location === "home",
    location: location === "home" ? "Home" : location === "not_home" ? "Away" : (location || "Unknown"),
    sentry: stateOf(states, e.sentry) === "on",
    odometer: num(states, e.odometer),
    entities: e
  }
}

// raw: { lights, states } from parseLive or the demo.
function buildHome(config, raw, nowMs, floorplan) {
  var hc = homeConfig(config, floorplan)
  var states = raw.states
  var rooms = hc.rooms.map(function(r) {
    var l = (r.area && raw.lights[r.area]) || { on: 0, total: 0 }
    var scene = r.area ? states[r.scene] : null
    return {
      id: r.id, area: r.area, name: r.name, floor: r.floor, points: r.points,
      on: l.on, total: l.total,
      temp: r.area && num(states, r.temperature) !== null ? Math.round(num(states, r.temperature)) : null,
      humidity: r.area && num(states, r.humidity) !== null ? Math.round(num(states, r.humidity)) : null,
      scene: scene ? { entity: r.scene, current: scene.state, options: scene.attributes.options || [] } : null
    }
  })
  // Every area with lights, on the plan or not, for the quick light switches.
  var areas = Object.keys(raw.lights).filter(function(a) { return raw.lights[a].total > 0 }).map(function(a) {
    var l = raw.lights[a]
    return { id: a, name: l.name || a, on: l.on, total: l.total }
  }).sort(function(p, q) { return p.name.localeCompare(q.name) })
  var temps = rooms.filter(function(r) { return r.temp !== null }).map(function(r) { return r.temp })
  return {
    floors: ((floorplan && floorplan.floors) || []).map(function(f) { return { id: f.id, name: f.name } }),
    rooms: rooms,
    areas: areas,
    climate: climate(hc.climate, states),
    devices: hc.devices.map(function(d) { return device(d, states, nowMs) }),
    car: car(hc, states, nowMs),
    averageTemp: temps.length ? Math.round(temps.reduce(function(a, b) { return a + b }, 0) / temps.length) : null
  }
}

// ------------------------------------------------------------------ demo

var DEMO_SCENES = ["Bright", "Concentrate", "Dimmed", "Energize", "Nightlight", "Read", "Relax"]

function st(state, attributes) { return { state: String(state), attributes: attributes || {} } }

function demoRaw(config, nowMs, floorplan) {
  var hc = homeConfig(config, floorplan)
  var states = {}
  var lights = {}
  var lit = { lounge_room: 2, dining_room: 1, kids_room: 1, office: 1 }
  var base = { garage: 76, storage: 74, sunroom: 75, primary_bedroom: 71, kids_room: 72, guest_room: 73, bathroom: 72, office: 73 }
  Object.keys(DEMO_AREAS).forEach(function(a) {
    var total = a === "lounge_room" || a === "primary_bedroom" || a === "guest_room" ? 4 : 2
    lights[a] = { name: DEMO_AREAS[a], on: Math.min(lit[a] || 0, total), total: total }
  })
  hc.rooms.filter(function(r) { return r.area }).forEach(function(r, i) {
    states[r.temperature] = st(base[r.area] || 72, { unit_of_measurement: "°F" })
    states[r.humidity] = st(44 + (i * 3) % 9, { unit_of_measurement: "%" })
    if (lights[r.area]) states[r.scene] = st(lit[r.area] ? "Relax" : "Bright", { options: DEMO_SCENES })
  })
  states[hc.climate] = st("cool", { current_temperature: 73, temperature: 72, current_humidity: 46, hvac_action: "cooling", hvac_modes: ["off", "cool", "heat", "heat_cool", "fan_only"], min_temp: 60, max_temp: 86 })
  var finishes = new Date(nowMs + 38 * 60000).toISOString()
  var d = {}
  hc.devices.forEach(function(dev) { d[dev.kind] = dev })
  if (d.washer) { states[d.washer.entity] = st("running"); states[d.washer.remaining] = st(finishes) }
  if (d.dryer) { states[d.dryer.entity] = st("end"); states[d.dryer.remaining] = st("unknown") }
  if (d.dishwasher) { states[d.dishwasher.entity] = st("ready"); states[d.dishwasher.remaining] = st("unknown") }
  if (d.fridge) { states[d.fridge.entity] = st(37); states[d.fridge.second] = st(0) }
  if (d.lock) states[d.lock.entity] = st("locked")
  if (d.garage) states[d.garage.entity] = st("open")
  if (d.door) states[d.door.entity] = st("off")
  if (d.leak) states[d.leak.entity] = st("off")
  if (d.vacuum) states[d.vacuum.entity] = st("docked")
  var e = hc.car.entities
  states[e.battery] = st(64, { unit_of_measurement: "%" })
  states[e.range] = st(198, { unit_of_measurement: "mi" })
  states[e.charging] = st("charging")
  states[e.chargerPower] = st(11, { unit_of_measurement: "kW" })
  states[e.timeToFull] = st(new Date(nowMs + 95 * 60000).toISOString())
  states[e.limit] = st(80)
  states[e.cable] = st("on")
  states[e.chargePort] = st("open")
  states[e.lock] = st("locked")
  states[e.climate] = st("off", { current_temperature: 71 })
  states[e.outside] = st(66)
  states[e.location] = st("home")
  states[e.sentry] = st("off")
  states[e.odometer] = st(18342)
  return { lights: lights, states: states }
}

// Applies a service call to demo state, as Home Assistant would.
function applyDemo(raw, call) {
  var next = JSON.parse(JSON.stringify(raw))
  var data = call.data || {}
  var id = data.entity_id
  var set = function(state) { if (next.states[id]) next.states[id].state = state }
  switch (call.service) {
  case "light/turn_on":
  case "light/turn_off":
    var areas = data.area_id ? [data.area_id] : Object.keys(next.lights)
    areas.forEach(function(a) { if (next.lights[a]) next.lights[a].on = call.service === "light/turn_on" ? next.lights[a].total : 0 })
    break
  case "select/select_option":
    set(data.option)
    // Picking a Hue room scene also turns that room's lights on.
    var scene = /^select\.(.+)_\1_scene$/.exec(id || "")
    if (scene && next.lights[scene[1]]) next.lights[scene[1]].on = next.lights[scene[1]].total
    break
  case "climate/set_temperature": if (next.states[id]) next.states[id].attributes.temperature = data.temperature; break
  case "climate/set_hvac_mode":
    set(data.hvac_mode)
    if (next.states[id]) {
      var target = next.states[id].attributes.temperature, current = next.states[id].attributes.current_temperature
      next.states[id].attributes.hvac_action = data.hvac_mode === "off" ? "off"
        : data.hvac_mode === "cool" ? (current > target ? "cooling" : "idle")
        : data.hvac_mode === "heat" ? (current < target ? "heating" : "idle") : "idle"
    }
    break
  case "climate/turn_on": set("heat_cool"); break
  case "climate/turn_off": set("off"); break
  case "lock/lock": set("locked"); break
  case "lock/unlock": set("unlocked"); break
  case "cover/open_cover": set("open"); break
  case "cover/close_cover": set("closed"); break
  case "vacuum/start": set("cleaning"); break
  case "vacuum/return_to_base": set("returning"); break
  case "switch/turn_on": set("on"); break
  case "switch/turn_off": set("off"); break
  }
  return next
}

function roomToggle(room) {
  return { service: room.on > 0 ? "light/turn_off" : "light/turn_on", data: { area_id: room.area || room.id } }
}

// ------------------------------------------------------------------ 3D plan

// Rotates one floor about its centre, views it from `elevation` degrees above
// the horizon and fits it, walls raised to `wallHeight` included, into
// width x height. The view is orthographic, so the whole floor plane maps
// through one affine matrix: the QML draws the plan once in plan units and
// only this matrix changes as the house turns. Raising a point by z metres
// moves it `lift` pixels per metre up the screen.
function planView(floor, rooms, opts) {
  var a = opts.angle * Math.PI / 180
  var e = (opts.elevation || 55) * Math.PI / 180
  var tilt = Math.sin(e), lift = Math.cos(e)
  var wall = opts.wallHeight === undefined ? 0.9 : opts.wallHeight
  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  function grow(x, y) { minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y) }
  floor.walls.forEach(function(w) { grow(w[0], w[1]); grow(w[2], w[3]) })
  rooms.forEach(function(r) { r.points.forEach(function(p) { grow(p[0], p[1]) }) })
  var cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
  var cos = Math.cos(a), sin = Math.sin(a)
  // Unscaled, about the centre: x across the screen, y down it.
  function turn(x, y) { var dx = x - cx, dy = y - cy; return [dx * cos - dy * sin, (dx * sin + dy * cos) * tilt] }
  var bx0 = Infinity, by0 = Infinity, bx1 = -Infinity, by1 = -Infinity
  function box(x, y) {
    var q = turn(x, y)
    bx0 = Math.min(bx0, q[0]); bx1 = Math.max(bx1, q[0])
    by0 = Math.min(by0, q[1] - wall * lift); by1 = Math.max(by1, q[1])
  }
  floor.walls.forEach(function(w) { box(w[0], w[1]); box(w[2], w[3]) })
  rooms.forEach(function(r) { r.points.forEach(function(p) { box(p[0], p[1]) }) })
  var pad = opts.padding || 0
  var scale = Math.min((opts.width - pad * 2) / (bx1 - bx0), (opts.height - pad * 2) / (by1 - by0))
  var ox = opts.width / 2 - (bx0 + bx1) / 2 * scale, oy = opts.height / 2 - (by0 + by1) / 2 * scale
  // screen = [m11 m12 tx; m21 m22 ty] . [x y 1]
  var m = [scale * cos, -scale * sin, 0, scale * tilt * sin, scale * tilt * cos, 0]
  m[2] = ox - m[0] * cx - m[1] * cy
  m[5] = oy - m[3] * cx - m[4] * cy
  var view = { scale: scale, matrix: m, lift: lift * scale, rooms: rooms, centers: {} }
  rooms.forEach(function(r) { var c = centroid(r.points); view.centers[r.id] = toScreen(view, c[0], c[1], 0) })
  return view
}

function toScreen(view, x, y, z) {
  var m = view.matrix
  return { x: m[0] * x + m[1] * y + m[2], y: m[3] * x + m[4] * y + m[5] - (z || 0) * view.lift }
}

// Room whose floor is under a screen point, or "".
function hitRoom(view, x, y) {
  var m = view.matrix, det = m[0] * m[4] - m[1] * m[3]
  if (!det) return ""
  var sx = x - m[2], sy = y - m[5]
  var px = (m[4] * sx - m[1] * sy) / det, py = (m[0] * sy - m[3] * sx) / det
  for (var i = 0; i < view.rooms.length; i++) {
    if (inPolygon(view.rooms[i].points, px, py)) return view.rooms[i].id
  }
  return ""
}

// Area centroid of a simple polygon, for label placement.
function centroid(points) {
  var area = 0, x = 0, y = 0
  for (var i = 0; i < points.length; i++) {
    var p = points[i], q = points[(i + 1) % points.length]
    var cross = p[0] * q[1] - q[0] * p[1]
    area += cross; x += (p[0] + q[0]) * cross; y += (p[1] + q[1]) * cross
  }
  if (Math.abs(area) < 1e-9) return points[0]
  return [x / (3 * area), y / (3 * area)]
}

function inPolygon(pts, x, y) {
  var inside = false
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    var p = pts[i], q = pts[j]
    if ((p[1] > y) !== (q[1] > y) && x < (q[0] - p[0]) * (y - p[1]) / (q[1] - p[1]) + p[0]) inside = !inside
  }
  return inside
}
