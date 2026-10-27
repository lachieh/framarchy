.pragma library

// Pure data shaping for the dashboard. No QML types here, so Node can test it
// (dashboard/test/model.test.mjs).

// Font Awesome 7 solid glyphs.
var ICON = {
  sun: "\uf185", moon: "\uf186", cloudSun: "\uf6c4", cloudMoon: "\uf6c3", cloud: "\uf0c2",
  smog: "\uf75f", rain: "\uf73d", showers: "\uf740", snow: "\uf2dc", storm: "\uf76c",
  umbrella: "\uf0e9", jacket: "\uf553", sunscreen: "\uf5ba", hot: "\uf769", warning: "\uf071",
  bulb: "\uf0eb", power: "\uf011", check: "\uf00c", circle: "\uf111", house: "\uf015",
  today: "\uf783", car: "\uf5e4", plug: "\uf1e6", bolt: "\uf0e7", lock: "\uf023",
  lockOpen: "\uf3c1", garage: "\uf494", doorOpen: "\uf52b", doorClosed: "\uf52a", droplet: "\uf043",
  broom: "\uf51a", wind: "\uf72e", utensils: "\uf2e7", tempLow: "\uf76b", thermometer: "\uf2c9",
  fire: "\uf06d", fan: "\uf863", shield: "\uf3ed", location: "\uf3c5", road: "\uf018",
  plus: "\uf067", minus: "\uf068", rotate: "\uf2f1", gauge: "\uf625", leaf: "\uf06c", close: "\uf00d"
}

var DEFAULT_CONFIG = {
  location: { name: "", latitude: null, longitude: null },
  units: "us",
  clock: "12h",
  clocks: [],
  homeAssistant: { url: "", token: "", todo: "todo.shopping_list" },
  night: { start: "21:00", end: "06:30", brightness: 10, dayBrightness: 78 },
  // Hyprland workspaces that show a dashboard page. Others are plain desktops.
  spaces: [
    { workspace: 1, page: "today" },
    { workspace: 2, page: "home" },
    { workspace: 3, page: "car" },
    { workspace: 4, page: "devices" }
  ],
  home: {}
}

var PAGES = {
  today: { label: "Today", icon: ICON.today },
  home: { label: "Home", icon: ICON.house },
  car: { label: "Car", icon: ICON.car },
  devices: { label: "Devices", icon: ICON.plug }
}

function pageFor(config, workspace) {
  var spaces = config.spaces || []
  for (var i = 0; i < spaces.length; i++) if (spaces[i].workspace === workspace && PAGES[spaces[i].page]) return spaces[i].page
  return ""
}

// The next or previous workspace that has a page, wrapping around.
function neighbourSpace(config, workspace, step) {
  var ids = (config.spaces || []).filter(function(s) { return PAGES[s.page] }).map(function(s) { return s.workspace }).sort(function(a, b) { return a - b })
  if (ids.length === 0) return workspace
  var i = ids.indexOf(workspace)
  if (i === -1) return ids[0]
  return ids[(i + step + ids.length) % ids.length]
}

function mergeConfig(raw) {
  var parsed = {}
  try { parsed = JSON.parse(raw || "{}") } catch (e) { return { config: clone(DEFAULT_CONFIG), error: "config.json is not valid JSON" } }
  var out = clone(DEFAULT_CONFIG)
  for (var key in parsed) {
    var value = parsed[key]
    if (value && typeof value === "object" && !Array.isArray(value) && out[key] && typeof out[key] === "object" && !Array.isArray(out[key])) {
      for (var sub in value) out[key][sub] = value[sub]
    } else {
      out[key] = value
    }
  }
  return { config: out, error: "" }
}

function clone(value) { return JSON.parse(JSON.stringify(value)) }

function hasLocation(config) {
  return typeof config.location.latitude === "number" && typeof config.location.longitude === "number"
}

function weatherUrl(config) {
  var us = config.units === "us"
  return "https://api.open-meteo.com/v1/forecast"
    + "?latitude=" + config.location.latitude
    + "&longitude=" + config.location.longitude
    + "&current=temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"
    + "&hourly=temperature_2m,precipitation_probability,weather_code,is_day"
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max,apparent_temperature_min"
    + "&forecast_days=6&forecast_hours=13&timezone=auto"
    + (us ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "")
}

function alertsUrl(config) {
  return "https://api.weather.gov/alerts/active?point="
    + Number(config.location.latitude).toFixed(4) + "," + Number(config.location.longitude).toFixed(4)
}

// WMO weather interpretation codes, as used by Open-Meteo.
function describe(code, isDay) {
  var day = isDay !== 0 && isDay !== false
  if (code === 0) return { label: "Clear", icon: day ? ICON.sun : ICON.moon }
  if (code === 1) return { label: "Mostly clear", icon: day ? ICON.cloudSun : ICON.cloudMoon }
  if (code === 2) return { label: "Partly cloudy", icon: day ? ICON.cloudSun : ICON.cloudMoon }
  if (code === 3) return { label: "Overcast", icon: ICON.cloud }
  if (code === 45 || code === 48) return { label: "Fog", icon: ICON.smog }
  if (code >= 51 && code <= 57) return { label: "Drizzle", icon: ICON.rain }
  if (code === 61 || code === 80) return { label: "Light rain", icon: ICON.rain }
  if (code === 63 || code === 81) return { label: "Rain", icon: ICON.showers }
  if (code === 65 || code === 82) return { label: "Heavy rain", icon: ICON.showers }
  if (code === 66 || code === 67) return { label: "Freezing rain", icon: ICON.showers }
  if (code >= 71 && code <= 77 || code === 85 || code === 86) return { label: "Snow", icon: ICON.snow }
  if (code >= 95) return { label: "Thunderstorms", icon: ICON.storm }
  return { label: "—", icon: ICON.cloud }
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

// Open-Meteo local times look like "2026-10-24T07:52". Read them as wall-clock
// fields rather than through Date, which would apply the frame's timezone.
function wallClock(iso) {
  var m = /T(\d\d):(\d\d)/.exec(iso || "")
  return m ? { h: Number(m[1]), m: Number(m[2]) } : null
}

function formatClock(h, m, mode) {
  if (mode === "24h") return pad2(h) + ":" + pad2(m)
  var hh = h % 12 === 0 ? 12 : h % 12
  return hh + ":" + pad2(m) + (h < 12 ? "a" : "p")
}

function formatHour(h, mode) {
  if (mode === "24h") return pad2(h)
  return (h % 12 === 0 ? 12 : h % 12) + (h < 12 ? "a" : "p")
}

var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function dayName(isoDate, index) {
  if (index === 0) return "Today"
  var p = isoDate.split("-")
  return DAY_NAMES[new Date(Date.UTC(Number(p[0]), Number(p[1]) - 1, Number(p[2]))).getUTCDay()]
}

function parseForecast(json, clockMode) {
  var c = json.current, h = json.hourly, d = json.daily
  var now = describe(c.weather_code, c.is_day)
  var hourly = []
  // forecast_hours starts at the current hour; skip it, the "now" card covers it.
  for (var i = 1; i < h.time.length; i++) {
    var t = wallClock(h.time[i])
    hourly.push({
      label: formatHour(t.h, clockMode),
      temp: Math.round(h.temperature_2m[i]),
      rain: h.precipitation_probability[i] || 0,
      icon: describe(h.weather_code[i], h.is_day[i]).icon
    })
  }
  var daily = []
  for (var j = 0; j < d.time.length; j++) {
    daily.push({
      label: dayName(d.time[j], j),
      hi: Math.round(d.temperature_2m_max[j]),
      lo: Math.round(d.temperature_2m_min[j]),
      rain: d.precipitation_probability_max[j] || 0,
      icon: describe(d.weather_code[j], 1).icon
    })
  }
  var sunrise = wallClock(d.sunrise[0]), sunset = wallClock(d.sunset[0])
  return {
    temp: Math.round(c.temperature_2m),
    feels: Math.round(c.apparent_temperature),
    label: now.label,
    icon: now.icon,
    humidity: Math.round(c.relative_humidity_2m),
    wind: Math.round(c.wind_speed_10m),
    windUnit: (json.current_units && json.current_units.wind_speed_10m || "").replace("mp/h", "mph"),
    hi: daily[0].hi,
    lo: daily[0].lo,
    rainToday: daily[0].rain,
    uv: Math.round(d.uv_index_max[0] || 0),
    feelsMin: Math.round(d.apparent_temperature_min[0]),
    sunrise: sunrise ? formatClock(sunrise.h, sunrise.m, clockMode) : "",
    sunset: sunset ? formatClock(sunset.h, sunset.m, clockMode) : "",
    hourly: hourly,
    daily: daily.slice(1)
  }
}

// One-line hints for getting out the door. Thresholds are in the forecast's
// units: Fahrenheit when units is "us", Celsius otherwise.
function advice(forecast, units) {
  var us = units === "us"
  var out = []
  var rainSoon = 0
  for (var i = 0; i < forecast.hourly.length; i++) rainSoon = Math.max(rainSoon, forecast.hourly[i].rain)
  if (rainSoon >= 50) out.push({ icon: ICON.umbrella, text: "Umbrella: " + rainSoon + "% chance of rain" })
  if (forecast.feelsMin <= (us ? 50 : 10)) out.push({ icon: ICON.jacket, text: "Jacket: feels like " + forecast.feelsMin + "° at the coldest" })
  if (forecast.hi >= (us ? 90 : 32)) out.push({ icon: ICON.hot, text: "Hot: high of " + forecast.hi + "°, take water" })
  if (forecast.uv >= 6) out.push({ icon: ICON.sunscreen, text: "Sunscreen: UV " + forecast.uv })
  return out
}

var SEVERITY_RANK = { Extreme: 0, Severe: 1, Moderate: 2, Minor: 3, Unknown: 4 }

function parseAlerts(json) {
  var features = (json && json.features) || []
  var out = []
  for (var i = 0; i < features.length; i++) {
    var p = features[i].properties || {}
    if (p.status && p.status !== "Actual") continue
    out.push({ event: p.event || "Alert", headline: p.headline || "", severity: p.severity || "Unknown" })
  }
  out.sort(function(a, b) { return (SEVERITY_RANK[a.severity] || 4) - (SEVERITY_RANK[b.severity] || 4) })
  return out
}

var DEMO_TODO = ["Milk", "Bread", "Bananas", "Dishwasher tablets", "Birthday candles"].map(function(summary, i) {
  return { uid: "demo-" + i, summary: summary }
})

function parseTodo(json, entityId) {
  var response = json && json.service_response && json.service_response[entityId]
  var items = (response && response.items) || []
  var out = []
  for (var i = 0; i < items.length; i++) {
    if (items[i].status !== "needs_action") continue
    out.push({ uid: items[i].uid, summary: items[i].summary })
  }
  return out
}

function minutesOf(hhmm) {
  var p = String(hhmm).split(":")
  return Number(p[0]) * 60 + Number(p[1] || 0)
}

// The night window may wrap midnight (21:00-06:30).
function isNight(hours, minutes, night) {
  var now = hours * 60 + minutes
  var start = minutesOf(night.start), end = minutesOf(night.end)
  return start <= end ? (now >= start && now < end) : (now >= start || now < end)
}

// Cards show their state rather than going blank.
function ageText(fetchedAtMs, nowMs) {
  if (!fetchedAtMs) return ""
  var minutes = Math.floor((nowMs - fetchedAtMs) / 60000)
  if (minutes < 2) return "just now"
  if (minutes < 60) return minutes + " min ago"
  return Math.floor(minutes / 60) + " h ago"
}
