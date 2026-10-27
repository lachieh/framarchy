#!/usr/bin/env python3
"""Build the dashboard's floorplan.json from a UniFi Innerspace project.

Usage: floorplan-from-unifi.py PROJECT_JSON ROOMS_JSON > floorplan.json

PROJECT_JSON is the console's reply to
  GET https://<console>/proxy/innerspace/api/project?mode=2D
(see dashboard/README.md for fetching it). Innerspace has walls but no rooms,
so ROOMS_JSON names each floor and outlines its rooms in Innerspace plan units
(the same units and y-up axes as the walls):

  {"floors": [{"plan": "Ground", "id": "ground", "name": "Ground",
               "rooms": [{"name": "Living room", "area": "lounge_room",
                          "points": [[x, y], ...]}]}]}

`plan` is the Innerspace floor title or id. `area` is a Home Assistant area id;
leave it out for rooms that are drawn only. Output is in metres, y down.
"""
import json
import sys


def main(project_path, rooms_path):
    data = json.load(open(project_path))["data"]
    spec = json.load(open(rooms_path))
    plans = {p["title"]: p["id"] for p in data["plans"]}
    floors = []
    for floor in spec["floors"]:
        plan_id = plans.get(floor["plan"], floor["plan"])
        if plan_id not in data["planScales"]:
            sys.exit(f"no Innerspace plan {floor['plan']!r}; have {sorted(plans)}")
        scale = data["planScales"][plan_id]["scale"]  # plan units per metre

        def metres(x, y):
            return [round(x / scale, 3), round(-y / scale, 3)]

        walls = []
        for shape in data["shapes"]:
            if shape["planId"] != plan_id or shape["type"] != "wall":
                continue
            a, b = shape["position"][0], shape["position"][1]
            walls.append(metres(a["x"], a["y"]) + metres(b["x"], b["y"]))
        rooms = []
        for room in floor["rooms"]:
            out = {"name": room["name"], "points": [metres(x, y) for x, y in room["points"]]}
            if room.get("area"):
                out["area"] = room["area"]
            rooms.append(out)
        floors.append({
            "id": floor["id"],
            "name": floor["name"],
            "height": data["planScales"][plan_id]["height"],
            "walls": walls,
            "rooms": rooms,
        })
    json.dump({"source": "UniFi Innerspace", "floors": floors}, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
