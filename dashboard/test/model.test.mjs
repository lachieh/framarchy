// Run: node --test dashboard/test/*.test.mjs
import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"
import vm from "node:vm"

const here = new URL(".", import.meta.url)
const source = fs.readFileSync(new URL("../plugin/model.js", here), "utf8")
const m = {}
vm.createContext(m)
vm.runInContext(source.replace(/^\.pragma library/m, ""), m)
const fixture = (name) => JSON.parse(fs.readFileSync(new URL(`fixtures/${name}`, here), "utf8"))
const plain = (value) => JSON.parse(JSON.stringify(value))

test("config merges nested sections over defaults and reports bad JSON", () => {
  const { config } = m.mergeConfig('{"location":{"latitude":1,"longitude":2},"night":{"start":"22:00"}}')
  assert.equal(config.location.latitude, 1)
  assert.equal(config.night.start, "22:00")
  assert.equal(config.night.end, "06:30")
  assert.equal(config.homeAssistant.todo, "todo.shopping_list")
  assert.match(m.mergeConfig("{nope").error, /not valid JSON/)
})

test("real Open-Meteo response parses into the cards' shape", () => {
  const raw = fixture("open-meteo.json")
  const f = m.parseForecast(raw, "12h")
  assert.equal(f.temp, Math.round(raw.current.temperature_2m))
  assert.equal(f.hourly.length, raw.hourly.time.length - 1)
  assert.equal(f.daily.length, raw.daily.time.length - 1)
  assert.equal(f.hi, Math.round(raw.daily.temperature_2m_max[0]))
  assert.match(f.sunrise, /^\d{1,2}:\d\da$/)
  assert.match(f.sunset, /^\d{1,2}:\d\dp$/)
  for (const h of f.hourly) assert.ok(h.icon && /^\d{1,2}[ap]$/.test(h.label), JSON.stringify(h))
})

test("times are read as wall clock, not shifted through the frame's timezone", () => {
  const raw = fixture("open-meteo.json")
  raw.daily.sunrise[0] = "2026-10-24T07:52"
  raw.daily.sunset[0] = "2026-10-24T18:51"
  raw.hourly.time[1] = "2026-10-24T00:00"
  const f = m.parseForecast(raw, "12h")
  assert.equal(f.sunrise, "7:52a")
  assert.equal(f.sunset, "6:51p")
  assert.equal(f.hourly[0].label, "12a")
  assert.equal(m.parseForecast(raw, "24h").sunset, "18:51")
})

test("day names come from the date, not the frame's clock", () => {
  assert.equal(m.dayName("2026-10-24", 0), "Today")
  assert.equal(m.dayName("2026-10-25", 1), "Sun")
  assert.equal(m.dayName("2026-10-30", 5), "Fri")
})

test("WMO codes map to labels and day/night icons", () => {
  assert.equal(m.describe(0, 1).icon, m.ICON.sun)
  assert.equal(m.describe(0, 0).icon, m.ICON.moon)
  assert.equal(m.describe(95, 1).label, "Thunderstorms")
  assert.equal(m.describe(73, 1).icon, m.ICON.snow)
})

test("advice flags umbrella, jacket, heat and UV at the right thresholds", () => {
  const base = { hourly: [{ rain: 10 }, { rain: 60 }], feelsMin: 48, hi: 91, uv: 7 }
  assert.deepEqual(plain(m.advice(base, "us").map((a) => a.text)), [
    "Umbrella: 60% chance of rain",
    "Jacket: feels like 48° at the coldest",
    "Hot: high of 91°, take water",
    "Sunscreen: UV 7",
  ])
  assert.equal(m.advice({ hourly: [{ rain: 40 }], feelsMin: 60, hi: 75, uv: 3 }, "us").length, 0)
  assert.equal(m.advice({ hourly: [], feelsMin: 9, hi: 20, uv: 0 }, "metric")[0].icon, m.ICON.jacket)
})

test("NWS alerts sort most severe first", () => {
  const raw = fixture("nws-alerts.json")
  raw.features.reverse()
  const alerts = m.parseAlerts(raw)
  assert.deepEqual(plain(alerts.map((a) => a.severity)), ["Severe", "Moderate", "Minor"])
  assert.ok(alerts[0].headline.length > 0)
  assert.deepEqual(plain(m.parseAlerts({ features: [] })), [])
})

test("workspaces map to pages, and swipes wrap through the paged ones", () => {
  const { config } = m.mergeConfig("{}")
  assert.equal(m.pageFor(config, 1), "today")
  assert.equal(m.pageFor(config, 3), "car")
  assert.equal(m.pageFor(config, 5), "")
  assert.equal(m.neighbourSpace(config, 1, 1), 2)
  assert.equal(m.neighbourSpace(config, 4, 1), 1)
  assert.equal(m.neighbourSpace(config, 1, -1), 4)
  assert.equal(m.neighbourSpace(config, 7, 1), 1)
  const custom = m.mergeConfig('{"spaces":[{"workspace":6,"page":"car"},{"workspace":2,"page":"nope"}]}').config
  assert.equal(m.pageFor(custom, 2), "")
  assert.equal(m.neighbourSpace(custom, 6, 1), 6)
})

test("todo response keeps only open items", () => {
  const json = { service_response: { "todo.shopping_list": { items: [
    { uid: "a", summary: "Milk", status: "needs_action" },
    { uid: "b", summary: "Eggs", status: "completed" },
  ] } } }
  assert.deepEqual(plain(m.parseTodo(json, "todo.shopping_list")), [{ uid: "a", summary: "Milk" }])
  assert.deepEqual(plain(m.parseTodo({}, "todo.shopping_list")), [])
})

test("night window wraps midnight", () => {
  const night = { start: "21:00", end: "06:30" }
  assert.equal(m.isNight(21, 0, night), true)
  assert.equal(m.isNight(2, 0, night), true)
  assert.equal(m.isNight(6, 30, night), false)
  assert.equal(m.isNight(12, 0, night), false)
  assert.equal(m.isNight(13, 0, { start: "12:00", end: "14:00" }), true)
})
