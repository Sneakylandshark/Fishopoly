"""Builds one scene per building in scenes/buildings/<key>.tscn from the Kenney packs in assets/kenney.

Each scene's origin is the middle of the building's base (ground level). main.gd puts the scene on
the building's spot when the game starts and hides the old greybox box.

After this first run the scenes are yours: open them in Godot and move, swap or add pieces.
This script NEVER overwrites a scene that already exists, unless you pass --force with the building's key:
  py tools/make_buildings.py                 (makes any missing scenes)
  py tools/make_buildings.py --force bank    (rebuilds just the bank)
"""
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "scenes" / "buildings"

PACKS = {
    "pir": "res://assets/kenney/pirate-kit/",
    "sur": "res://assets/kenney/survival-kit/",
    "wat": "res://assets/kenney/watercraft-pack/",
    "gra": "res://assets/kenney/graveyard-kit/",
    "dun": "res://assets/kenney/mini-dungeon/",
    "fan": "res://assets/kenney/fantasy-town-kit/",
}


# ---------- Helpers for Fantasy Town Kit houses ----------
# The kit is built on a 1 m grid: wall panels sit on a cell's edge, roofs sit on top of the walls.
# A house is 1 cell wide and `length` cells long, running from the back to the front (+z, where the door is).

def _move(pieces, x=0.0, z=0.0, turn=0.0, size=1.0):
    # Turn, scale and shift a group of pieces (turn is around the up axis, like the pieces' own turn)
    a = math.radians(turn)
    c, s = math.cos(a), math.sin(a)
    out = []
    for m, px, py, pz, pt, ps in pieces:
        px, py, pz = px * size, py * size, pz * size
        out.append((m, c * px + s * pz + x, py, -s * px + c * pz + z, pt + turn, ps * size))
    return out


def house(length=2, floors=1, wall="wall", upper="wall-wood", roof="roof", door="wall-door",
          chimney=False, x=0.0, z=0.0, turn=0.0, size=1.5):
    pieces = []
    for f in range(floors):
        kind = wall if f == 0 else upper
        for j in range(length):
            cz = j - (length - 1) / 2
            # Long sides: windows on every other cell, plain wall between
            side = kind + ("-window-shutters" if (j + f) % 2 == 0 else "")
            pieces.append(("fan/" + side, 0, f, cz, 0, 1.0))
            pieces.append(("fan/" + side, 0, f, cz, 180, 1.0))
        back = -(length - 1) / 2
        front = (length - 1) / 2
        pieces.append(("fan/" + kind, 0, f, back, 90, 1.0))
        front_piece = door if f == 0 else kind + "-window-shutters"
        pieces.append(("fan/" + front_piece, 0, f, front, -90, 1.0))
    # Roof: hipped ends with a ridge running back to front
    top = floors
    if length == 1:
        pieces.append(("fan/" + roof + "-point", 0, top, 0, 0, 1.0))
    else:
        pieces.append(("fan/" + roof + "-gable-end", 0, top, -(length - 1) / 2, -90, 1.0))
        for j in range(1, length - 1):
            pieces.append(("fan/" + roof + "-gable", 0, top, j - (length - 1) / 2, 90, 1.0))
        pieces.append(("fan/" + roof + "-gable-end", 0, top, (length - 1) / 2, 90, 1.0))
    if chimney:
        pieces.append(("fan/chimney", -0.3, top + 0.1, -(length - 1) / 2, 0, 1.0))
    return _move(pieces, x, z, turn, size)


def tower(floors=2, wall="wall", roof="roof-high", x=0.0, z=0.0, size=1.5):
    pieces = []
    for f in range(floors):
        kind = wall + ("-window-shutters" if f > 0 else "")
        for t in (0, 90, 180):
            pieces.append(("fan/" + kind, 0, f, 0, t, 1.0))
        pieces.append(("fan/" + (wall + "-door" if f == 0 else kind), 0, f, 0, -90, 1.0))
    pieces.append(("fan/" + roof + "-point", 0, floors, 0, 0, 1.0))
    return _move(pieces, x, z, 0, size)


# Each piece: (pack/model, x, y, z, turn in degrees, size).
# Survival-kit pieces are tiny (0.5 m), so they're scaled up about 5x; graveyard pieces about 2.5x.
BUILDINGS = {
    # ---------- Avenue buildings ----------
    "deep": [  # Deep Sea Dock: a big boathouse with fuel barrels and a pennant
        ("wat/boat-house-c", 0, 0, 0, 0, 1.0),
        ("pir/barrel", 1.9, 0, 1.4, 0, 0.7),
        ("pir/barrel", 1.9, 0, 0.4, 30, 0.7),
        ("pir/flag-pennant", -1.6, 0, -1.8, 0, 1.0),
    ],
    "pearl": house(2, wall="wall-wood", roof="roof", x=-0.4) + [  # Pearl Diving: wooden cottage, chest of pearls
        ("pir/chest", 1.2, 0, 1.4, -20, 0.55),
        ("sur/bucket", 1.3, 0, 0.3, 0, 4.0),
    ],
    "crab": house(2, wall="wall-wood", roof="roof-high", x=-0.5) + [  # Crab Boats: red-roofed shed, crab stall
        ("fan/stall-red", 1.1, 0, 0.9, -90, 1.3),
        ("pir/crate", 1.2, 0, -0.8, 10, 0.6),
    ],
    "cray": house(2, wall="wall-wood", roof="roof", x=-0.5) + [  # Cray Potting: shed with a stack of pots
        ("pir/barrel", 1.1, 0, 1.0, 0, 0.5),
        ("pir/barrel", 1.1, 0, 0.2, 0, 0.5),
        ("pir/barrel", 1.1, 0.6, 0.6, 0, 0.45),
        ("pir/crate-bottles", 1.2, 0, -0.9, 0, 0.6),
    ],
    "salvage": [  # Salvage Yard: boathouse with a pile of salvaged cargo
        ("wat/boat-house-b", 0, 0, 0, 90, 0.9),
        ("wat/cargo-pile-a", 0, 0, 2.3, 0, 0.6),
    ],
    "treasure": house(2, wall="wall", roof="roof-high", x=-0.4) + [  # Treasure Hunters: stone house, chests
        ("pir/chest", 1.2, 0, 1.3, 25, 0.55),
        ("pir/chest", 1.2, 0, 0.2, -15, 0.45),
        ("pir/tool-shovel", 1.3, 0, -0.8, 70, 0.7),
    ],
    "whaling": [  # Whaling Station: tall boathouse, oil barrels, flag
        ("wat/boat-house-d", 0, 0, 0, 0, 0.9),
        ("pir/barrel", 1.8, 0, 1.2, 0, 0.7),
        ("pir/barrel", 1.8, 0, 0.1, 0, 0.7),
        ("pir/barrel", 1.8, 0.86, 0.65, 0, 0.6),
        ("pir/flag-high", -1.5, 0, -1.6, 0, 0.9),
    ],
    "smuggle": house(2, wall="wall-wood", roof="roof", door="wall-wood-doorway-square-wide", x=-0.4) + [
        # Smugglers' Cove: shabby warehouse, crates and barrels piled outside, pirate pennant
        ("pir/crate", 1.2, 0, 1.2, 15, 0.6),
        ("pir/crate", 1.2, 0.47, 1.2, -10, 0.5),
        ("pir/barrel", 1.2, 0, 0.1, 0, 0.5),
        ("pir/flag-pirate-pennant", 1.2, 0, -1.2, 0, 0.8),
    ],
    "hiding": house(2, wall="wall-wood", roof="roof", door="wall-wood-doorway-square-wide", x=-0.3) + [
        # Hidden Moorings: dark boat shed with a lantern burning outside
        ("fan/lantern", 1.0, 0, 1.4, 0, 1.2),
        ("pir/boat-row-small", 1.2, 0, -0.4, 0, 0.5),
    ],
    "piracy": [  # Pirate Haven: a watchtower with the black flag and a cannon
        ("pir/tower-base", 0, 0, 0, 0, 0.8),
        ("pir/tower-watch", 0, 1.6, 0, 0, 0.8),
        ("pir/flag-pirate-high", 0.2, 3.6, 0, 0, 0.8),
        ("pir/cannon", 1.7, 0, 1.6, 30, 0.7),
    ],
    "oil": [  # Oil Platform (at sea): deck on stilts, metal shed, derrick mast, barrels
        ("pir/structure-platform", -1.25, 0, -1.25, 0, 1.0),
        ("pir/structure-platform", 1.25, 0, -1.25, 0, 1.0),
        ("pir/structure-platform", -1.25, 0, 1.25, 0, 1.0),
        ("pir/structure-platform", 1.25, 0, 1.25, 0, 1.0),
        ("sur/structure-metal", -1.1, 0.93, -1.0, 0, 4.5),
        ("sur/structure-metal-roof", -1.1, 3.18, -1.0, 0, 4.5),
        ("pir/mast-ropes", 1.2, 0.93, 0.8, 0, 0.9),
        ("pir/barrel", 1.6, 0.93, -1.4, 0, 0.6),
        ("pir/barrel", 0.8, 0.93, -1.6, 0, 0.6),
    ],
    "lighthouse": [  # Lighthouse: the tall pirate tower
        ("pir/tower-complete-large", 0, 0, 0, 0, 1.0),
    ],
    "meteo": [  # Forecast office: a small tower with a wind pennant
        ("pir/tower-complete-small", 0, 0, 0, 0, 0.85),
        ("pir/flag-high-pennant", 0, 5.7, 0, 0, 0.6),
    ],
    # ---------- Champion buildings (one plot, only yours shows) ----------
    "bank": [  # Bank: stone crypt-style vault with columns
        ("gra/crypt-large", 0, 0, 0, 0, 1.8),
        ("gra/crypt-large-roof", 0, 1.8, 0, 0, 1.8),
        ("gra/column-large", -1.3, 0, 2.3, 0, 1.6),
        ("gra/column-large", 1.3, 0, 2.3, 0, 1.6),
    ],
    "bait_works": house(2, wall="wall-wood", roof="roof-high", chimney=True, x=-0.4) + [
        # Bait Works: red-roofed shed, barrels of bait, fish drying on a stand
        ("pir/barrel", 1.2, 0, 1.2, 0, 0.5),
        ("sur/campfire-fishing-stand", 1.2, 0, -0.3, 0, 3.0),
    ],
    "research_lab": house(2, floors=2, wall="wall", upper="wall", roof="roof-high", chimney=True, x=-0.4) + [
        # Research Lab: tall stone building, a workbench and bottles outside
        ("sur/workbench-grind", 1.2, 0, 1.2, 0, 4.0),
        ("pir/bottle-large", 1.2, 0, 0.2, 0, 1.0),
    ],
    "exchange": [  # Exchange: a little market of stalls
        ("fan/stall-red", -0.8, 0, -0.6, 0, 1.4),
        ("fan/stall-green", 0.8, 0, -0.6, 0, 1.4),
        ("fan/stall-red", 0, 0, 1.0, 180, 1.4),
        ("fan/stall-bench", -1.2, 0, 1.2, 0, 1.4),
        ("pir/flag-high", 1.4, 0, 1.3, 0, 0.8),
    ],
    "shipyard": house(2, wall="wall-wood", roof="roof-high", door="wall-wood-doorway-square-wide", x=-0.6) + [
        # Shipyard: big-doored workshop, a rowboat being built out front, an anvil
        ("pir/boat-row-large", 1.0, 0, 0.3, 0, 0.55),
        ("sur/workbench-anvil", 1.2, 0, -1.2, 0, 3.5),
    ],
    "diving_school": house(2, wall="wall", roof="roof", x=-0.4) + [  # Diving School: stone schoolhouse, rowboat
        ("pir/boat-row-small", 1.2, 0, 0.6, 0, 0.55),
        ("pir/barrel", 1.2, 0, -1.0, 0, 0.45),
    ],
    "law_office": [  # Law Office: small stone office with a lamp post
        ("gra/crypt-small", 0, 0, 0, 0, 2.2),
        ("gra/crypt-small-roof", 0, 2.2, 0, 0, 2.2),
        ("gra/lightpost-single", 1.4, 0, 1.4, 0, 1.6),
    ],
    "supply_depot": [  # Supply Depot: cargo containers and a cargo pile
        ("wat/cargo-container-a", -0.8, 0, 0, 0, 1.0),
        ("wat/cargo-container-b", 0.8, 0, 0, 0, 1.0),
        ("wat/cargo-container-c", 0, 1.1, 0, 90, 1.0),
    ],
    "refinery": house(2, wall="wall", roof="roof-high", chimney=True, x=-0.5) + tower(2, x=0.9, z=-0.9, size=1.0) + [
        # Refinery: stone works with a chimney, a little tower, and oil barrels
        ("sur/barrel", 1.1, 0, 1.0, 0, 2.6),
        ("sur/barrel", 1.1, 0, 0.3, 0, 2.6),
    ],
    "weather_station": [  # Weather Station: watchtower with a wind pennant
        ("pir/tower-base", 0, 0, 0, 0, 0.75),
        ("pir/tower-watch", 0, 1.5, 0, 0, 0.75),
        ("pir/flag-high-pennant", 0, 3.4, 0, 0, 0.6),
    ],
    # ---------- Records buildings ----------
    "harbour_office": house(2, wall="wall", roof="roof", x=-0.3, size=1.2) + [  # Harbour Office: stone office
        ("pir/flag", 0.8, 0, 0.9, 0, 0.7),
    ],
    "gazette_office": house(1, floors=2, wall="wall-wood", roof="roof-high", size=1.2) + [
        # Gazette Office: narrow two-storey print shop, bundles of papers outside
        ("pir/crate", 0.9, 0, 0.7, 10, 0.45),
    ],
    "counting_house": [  # Counting House: small stone building with a column
        ("gra/crypt-small", 0, 0, 0, 0, 1.9),
        ("gra/crypt-small-roof", 0, 1.9, 0, 0, 1.9),
    ],
    "customs_house": tower(3, wall="wall", roof="roof-high", size=1.2) + [  # Customs House: stone tower, flag
        ("pir/flag-high", 0.9, 0, 0.9, 0, 0.6),
    ],
    "watch_house": [  # Watch House: small watchtower
        ("pir/tower-base", 0, 0, 0, 0, 0.65),
        ("pir/tower-watch", 0, 1.3, 0, 0, 0.65),
    ],
    # ---------- Your house, and the oil rig boats ----------
    "house": house(2, floors=2, wall="wall", upper="wall-wood", roof="roof-high", chimney=True, x=-0.3, size=1.4) + [
        # Your House: two storeys, stone below and timber above, red roof, a lantern by the door
        ("fan/lantern", 0.9, 0, 1.6, 0, 1.0),
        ("pir/barrel", 0.9, 0, 0.3, 0, 0.45),
        ("fan/cart", 1.0, 0, -1.0, 0, 1.0),
    ],
    "rig": [  # Oil rig (a "boat" in boat.gd): small deck on stilts, derrick mast, pump shed, barrels
        ("pir/structure-platform", 0, 0, 0, 0, 1.2),
        ("pir/mast-ropes", 0.4, 1.1, 0.3, 0, 0.7),
        ("sur/structure-metal", -0.6, 1.1, -0.6, 0, 3.0),
        ("sur/structure-metal-roof", -0.6, 2.6, -0.6, 0, 3.0),
        ("pir/barrel", 0.9, 1.1, -0.9, 0, 0.4),
    ],
    # ---------- Town Hall ----------
    "town_hall": [  # Town Hall: the castle gate with a flag on top
        ("pir/castle-gate", 0, 0, 0, 0, 0.9),
        ("pir/flag-high", 0, 3.96, 0, 0, 0.8),
    ],
}


def transform(x, y, z, turn, size):
    a = math.radians(turn)
    c, s = math.cos(a) * size, math.sin(a) * size
    # .tscn writes the basis row by row, then the origin (a turn to the left around the up axis)
    return "Transform3D(%g, 0, %g, 0, %g, 0, %g, 0, %g, %g, %g, %g)" % (c, s, size, -s, c, x, y, z)


def scene(key, pieces):
    models = sorted({p[0] for p in pieces})
    ids = {m: "%d_%s" % (i + 1, m.split("/")[1]) for i, m in enumerate(models)}
    lines = ["[gd_scene format=3]", ""]
    for m in models:
        pack, name = m.split("/")
        lines.append('[ext_resource type="PackedScene" path="%s%s.glb" id="%s"]' % (PACKS[pack], name, ids[m]))
    lines += ["", '[node name="%s" type="Node3D"]' % key, ""]
    used = {}
    for m, x, y, z, turn, size in pieces:
        name = m.split("/")[1]
        used[name] = used.get(name, 0) + 1
        node = name if used[name] == 1 else "%s%d" % (name, used[name])
        lines.append('[node name="%s" parent="." instance=ExtResource("%s")]' % (node, ids[m]))
        lines.append("transform = " + transform(x, y, z, turn, size))
        lines.append("")
    return "\n".join(lines)


def main():
    force = set(sys.argv[2:]) if len(sys.argv) > 1 and sys.argv[1] == "--force" else set()
    OUT.mkdir(parents=True, exist_ok=True)
    for key, pieces in BUILDINGS.items():
        path = OUT / (key + ".tscn")
        if path.exists() and key not in force:
            print("kept   ", path.name, "(already exists)")
            continue
        path.write_text(scene(key, pieces), encoding="utf-8")
        print("made   ", path.name)


if __name__ == "__main__":
    main()
