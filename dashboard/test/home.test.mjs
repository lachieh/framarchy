// Run: node --test dashboard/test/*.test.mjs
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import test from "node:test"
import vm from "node:vm"

const h = {}
vm.createContext(h)
vm.runInContext(fs.readFileSync(new URL("../plugin/home.js", import.meta.url), "utf8").replace(/^\.pragma library/m, ""), h)
const plain = (value) => JSON.parse(JSON.stringify(value))
const NOW = Date.parse("2026-10-24T18:00:00Z")
const config = {}

// A made-up two-floor house: an L-shaped lounge with a kitchen (no area),
// and a garage below.
const square = (x, y, w, d) => [[x, y], [x + w, y], [x + w, y + d], [x, y + d]]
const edges = (pts) => pts.map((p, i) => [...p, ...pts[(i + 1) % pts.length]])
const lounge = [[0, 0], [6, 0], [6, 4], [3, 4], [3, 6], [0, 6]]
const floorplan = {
  floors: [
    { id: "ground", name: "Ground", walls: [...edges(lounge), ...edges(square(6, 0, 3, 4))],
      rooms: [{ name: "Lounge", area: "lounge_room", points: lounge }, { name: "Kitchen", points: square(6, 0, 3, 4) }] },
    { id: "basement", name: "Basement", walls: edges(square(0, 0, 6, 6)), rooms: [{ name: "Garage", area: "garage", points: square(0, 0, 6, 6) }] },
  ],
}

test("plan rooms get Home Assistant entities by area; rooms without one get none", () => {
  const hc = h.homeConfig({ home: { rooms: { garage: { temperature: "sensor.workshop" } } } }, floorplan)
  const byName = Object.fromEntries(hc.rooms.map((r) => [r.name, r]))
  assert.equal(byName.Lounge.scene, "select.lounge_room_lounge_room_scene")
  assert.equal(byName.Lounge.floor, "ground")
  assert.equal(byName.Garage.temperature, "sensor.workshop")
  assert.equal(byName.Kitchen.area, "")
  assert.equal(byName.Kitchen.temperature, undefined)
  assert.ok(!h.entityIds(hc).includes(undefined))
})

test("demo state builds every view", () => {
  const home = h.buildHome(config, h.demoRaw(config, NOW, floorplan), NOW, floorplan)
  assert.deepEqual(plain(home.floors), [{ id: "ground", name: "Ground" }, { id: "basement", name: "Basement" }])
  const lounge = home.rooms.find((r) => r.id === "lounge_room")
  assert.deepEqual([lounge.on, lounge.total, lounge.scene.current], [2, 4, "Relax"])
  assert.equal(home.rooms.find((r) => r.name === "Kitchen").temp, null)
  // Quick switches list every area with lights, including ones not on the plan.
  assert.equal(home.areas.length, 12)
  assert.ok(home.areas.some((a) => a.id === "storage" && a.name === "Storage"))
  assert.equal(home.climate.action, "cooling")
  assert.equal(home.car.timeToFull, "1 h 35 min")
  const washer = home.devices.find((d) => d.kind === "washer")
  assert.deepEqual([washer.state, washer.detail, washer.tone], ["Running", "38 min left", "active"])
})

test("missing entities and a missing floor plan read as empty, not errors", () => {
  const home = h.buildHome(config, { lights: {}, states: {} }, NOW, null)
  assert.deepEqual(plain(home.rooms), [])
  assert.deepEqual(plain(home.floors), [])
  assert.equal(home.climate, null)
  assert.equal(home.car, null)
  assert.ok(home.devices.every((d) => d.missing && d.state === "Not set up"))
})

test("demo actions change state the way Home Assistant would", () => {
  let raw = h.demoRaw(config, NOW, floorplan)
  raw = h.applyDemo(raw, plain(h.roomToggle({ id: "office", area: "office", on: 0 })))
  assert.equal(raw.lights.office.on, raw.lights.office.total)
  raw = h.applyDemo(raw, { service: "light/turn_off", data: { entity_id: "all" } })
  assert.ok(Object.values(raw.lights).every((l) => l.on === 0))
  raw = h.applyDemo(raw, { service: "select/select_option", data: { entity_id: "select.lounge_room_lounge_room_scene", option: "Read" } })
  assert.equal(raw.lights.lounge_room.on, raw.lights.lounge_room.total)
  raw = h.applyDemo(raw, { service: "climate/set_hvac_mode", data: { entity_id: "climate.house", hvac_mode: "off" } })
  assert.equal(h.buildHome(config, raw, NOW, floorplan).climate.action, "off")
  const garage = h.buildHome(config, raw, NOW, floorplan).devices.find((d) => d.kind === "garage")
  raw = h.applyDemo(raw, plain(garage.action))
  assert.equal(h.buildHome(config, raw, NOW, floorplan).devices.find((d) => d.kind === "garage").state, "Closed")
})

test("locking asks for confirmation only to unlock", () => {
  const states = { "lock.front_door": { state: "locked", attributes: {} } }
  const locked = h.device({ name: "Front door", kind: "lock", entity: "lock.front_door" }, states, NOW)
  assert.deepEqual(plain(locked.action), { label: "Unlock", confirm: true, service: "lock/unlock", data: { entity_id: "lock.front_door" } })
  states["lock.front_door"].state = "unlocked"
  assert.equal(h.device({ name: "Front door", kind: "lock", entity: "lock.front_door" }, states, NOW).action.confirm, undefined)
})

test("remaining time accepts minutes or a finish timestamp", () => {
  const states = { a: { state: "25", attributes: {} }, b: { state: new Date(NOW + 90 * 60000).toISOString(), attributes: {} }, c: { state: "unknown", attributes: {} } }
  assert.equal(h.minutesLeft(states, "a", NOW), 25)
  assert.equal(h.minutesLeft(states, "b", NOW), 90)
  assert.equal(h.minutesLeft(states, "c", NOW), null)
  assert.equal(h.durationText(90), "1 h 30 min")
})

test("car entity names derive from the prefix and accept overrides", () => {
  const hc = h.homeConfig({ home: { car: { prefix: "rosie", entities: { lock: "lock.front_trunk" } } } }, null)
  assert.equal(hc.car.entities.battery, "sensor.rosie_battery_level")
  assert.equal(hc.car.entities.lock, "lock.front_trunk")
})

test("live template output parses into the demo's shape, with area names", () => {
  const text = JSON.stringify({ rooms: [["office", "Office", 1, 2]], states: [["climate.house", "cool", [["temperature", 70]]]] })
  const raw = h.parseLive(text)
  assert.deepEqual(plain(raw.lights), { office: { name: "Office", on: 1, total: 2 } })
  assert.equal(raw.states["climate.house"].attributes.temperature, 70)
  assert.ok(h.liveTemplate(["climate.house"]).includes("area_name(a)"))
})

test("plan view fits the frame and taps hit the right room, L-shapes included", () => {
  const ground = floorplan.floors[0]
  const rooms = h.homeConfig(config, floorplan).rooms.filter((r) => r.floor === "ground")
  for (const angle of [0, 30, 90, 200]) {
    const v = h.planView(ground, rooms, { angle, elevation: 55, wallHeight: 0.6, width: 600, height: 400, padding: 10 })
    for (const w of ground.walls) for (const z of [0, 0.6]) for (const pt of [h.toScreen(v, w[0], w[1], z), h.toScreen(v, w[2], w[3], z)]) {
      assert.ok(pt.x >= 9.9 && pt.x <= 590.1 && pt.y >= 9.9 && pt.y <= 390.1, `angle ${angle}: ${JSON.stringify(pt)}`)
    }
    for (const r of rooms) assert.equal(h.hitRoom(v, v.centers[r.id].x, v.centers[r.id].y), r.id, `angle ${angle}`)
  }
  // The lounge's missing corner belongs to no room.
  const flat = h.planView(ground, rooms, { angle: 0, elevation: 90, wallHeight: 0, width: 900, height: 600 })
  const at = (x, y) => h.toScreen(flat, x, y, 0)
  assert.equal(h.hitRoom(flat, at(4.5, 5).x, at(4.5, 5).y), "")
  assert.equal(h.hitRoom(flat, at(1, 5).x, at(1, 5).y), "lounge_room")
})

test("raised walls rise straight up the screen by their projected height", () => {
  const v = h.planView({ walls: edges(square(0, 0, 2, 2)) }, [], { angle: 25, elevation: 60, wallHeight: 1, width: 100, height: 100 })
  const base = h.toScreen(v, 2, 0, 0), top = h.toScreen(v, 2, 0, 1)
  assert.equal(top.x, base.x)
  assert.ok(Math.abs(base.y - top.y - v.scale * Math.cos(Math.PI / 3)) < 1e-9)
})

test("floorplan-from-unifi converts Innerspace units to metres, y down", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "floorplan-"))
  const project = { data: {
    plans: [{ id: "p1", title: "Ground" }],
    planScales: { p1: { scale: 50, height: 2.7 } },
    shapes: [
      { type: "wall", planId: "p1", position: [{ x: 0, y: 0, z: 0 }, { x: 100, y: -50, z: 0 }] },
      { type: "map", planId: "p1", position: [{ x: 0, y: 0, z: 0 }] },
      { type: "wall", planId: "other", position: [{ x: 1, y: 1, z: 0 }, { x: 2, y: 2, z: 0 }] },
    ] } }
  const rooms = { floors: [{ plan: "Ground", id: "ground", name: "Ground",
    rooms: [{ name: "Hall", points: [[0, 0], [50, 0], [50, -100]] }, { name: "Den", area: "den", points: [[0, 0], [1, 0], [1, 1]] }] }] }
  fs.writeFileSync(path.join(dir, "project.json"), JSON.stringify(project))
  fs.writeFileSync(path.join(dir, "rooms.json"), JSON.stringify(rooms))
  const tool = new URL("../tools/floorplan-from-unifi.py", import.meta.url).pathname
  const out = JSON.parse(execFileSync("python3", [tool, path.join(dir, "project.json"), path.join(dir, "rooms.json")]))
  const ground = out.floors[0]
  assert.deepEqual(ground.walls, [[0, 0, 2, 1]])
  assert.deepEqual(ground.rooms[0], { name: "Hall", points: [[0, 0], [1, 0], [1, 2]] })
  assert.equal(ground.rooms[1].area, "den")
  assert.equal(ground.height, 2.7)
})
