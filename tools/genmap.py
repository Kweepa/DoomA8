#!/usr/bin/env python3
"""Cook editor/maps/e1mN.json → packed PRGs (maps/e1mN.prg) + map_counts.asm + map_sizes.asm."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from roomgeom import clamp_room_shape, nudge_door_outside, room_geometry

ROOT = Path(__file__).resolve().parents[1]
EDITOR_MAPS = ROOT / "editor" / "maps"
MAP_DIR = ROOT / "maps"
COUNTS_OUT = ROOT / "src" / "map_counts.asm"
SIZES_OUT = ROOT / "src" / "map_sizes.asm"

LEVEL_NAMES = ["E1M1", "E1M2", "E1M3", "E1M4", "E1M5", "E1M6", "E1M7", "E1M8"]
ENEMY_TYPE = {
    "Possessed": 0,
    "Baron": 1,
    "Pinky": 2,
    "Imp": 3,
}
MAP_MAX_BYTES = 4096
ROOM_MAX_TYPES = 2
HDR_TYPE_SLOTS = 2  # packed header pad after map_type0; unused by streaming
ROOM_MAX = 24  # keep in sync with editor/js/model.js
CRATE_MAX = 16
SLOPE_MAX = 16
PLAT_MAX = 20
SWITCH_MAX = 16
ELEV_MAX = 4
ENEMY_MAX = 24  # keep in sync with src/mem.asm and editor/js/model.js
TRIG_MAX = 16
TRIG_ROOM_MAX = 8
TH_MAX = 32
FACE = {"+z": 0, "-z": 1, "+x": 2, "-x": 3}
# Width × height × thickness; keep in sync with editor/js/model.js doorSizeForScale.
DOOR_SIZE_BY_SCALE = {1: (4, 5, 1), 1.5: (6, 8, 1), 2: (8, 10, 1)}
# Room colour is one Atari byte (hue<<4 | lum, bit 0 unused) written by the editor
# as "a8Bg"; keep in sync with editor/js/model.js normalizeBg.
ROOM_BG_DEFAULT = 0x24  # brown
ROOM_BG_GREY_DARK = 0x04
ROOM_BG_GREY_LIGHT = 0x0A


def norm_bg(val) -> int:
    """A8 paper byte. Black / white paper (ink == paper, or black gutters) → grey."""
    try:
        b = int(val) & 0xFE
    except (TypeError, ValueError):
        return ROOM_BG_DEFAULT
    if b & 0xF0 == 0:
        if b < 0x04:
            return ROOM_BG_GREY_DARK
        if b >= 0x0E:
            return ROOM_BG_GREY_LIGHT
    return b


def clamp_door_scale(val) -> float:
    try:
        n = float(val)
    except (TypeError, ValueError):
        return 1.0
    if n == 2:
        return 2.0
    if n == 1.5:
        return 1.5
    return 1.0


def door_size_for_scale(scale) -> tuple[int, int, int]:
    return DOOR_SIZE_BY_SCALE[clamp_door_scale(scale)]


def apply_door_scale_aabb(d: dict) -> None:
    """Bake doorScale + face into sx/sy/sz. Keep floor Y and grow width about centre."""
    w, h, t = door_size_for_scale(d.get("doorScale"))
    face = d.get("face") or "+z"
    old_sx = int(d.get("sx") or w)
    old_sz = int(d.get("sz") or t)
    if face in ("+x", "-x"):
        sx, sy, sz = t, h, w
        d["z"] = int(d.get("z") or 0) + (old_sz - sz) // 2
    else:
        sx, sy, sz = w, h, t
        d["x"] = int(d.get("x") or 0) + (old_sx - sx) // 2
    if int(d["x"]) < 0:
        d["x"] = 0
    if int(d.get("z") or 0) < 0:
        d["z"] = 0
    d["sx"], d["sy"], d["sz"] = sx, sy, sz


def aabb_overlap(a: dict, b: dict) -> bool:
    """Inclusive face-touch counts as overlap (editor model.js)."""
    return (
        a["x"] <= b["x"] + b["sx"]
        and b["x"] <= a["x"] + a["sx"]
        and a["y"] <= b["y"] + b["sy"]
        and b["y"] <= a["y"] + a["sy"]
        and a["z"] <= b["z"] + b["sz"]
        and b["z"] <= a["z"] + a["sz"]
    )


def aabb_volume(box: dict) -> int:
    return int(box["sx"]) * int(box["sy"]) * int(box["sz"])


def room_index(rooms: list[dict], obj: dict, kind: str) -> int:
    rid = obj.get("roomId")
    id_to_i = {r.get("id"): i for i, r in enumerate(rooms)}
    if rid in id_to_i:
        return id_to_i[rid]
    raise SystemExit(f"{kind} at {obj.get('x')},{obj.get('y')},{obj.get('z')} has no room")


def unique_u8(vals: list[int], cap: int, what: str, name: str) -> tuple[list[int], list[int]]:
    seen: list[int] = []
    idx: list[int] = []
    for v in vals:
        v = v & 0xFF
        if v not in seen:
            if len(seen) >= cap:
                raise SystemExit(f"room {name!r} has >{cap} unique {what}")
            seen.append(v)
        idx.append(seen.index(v))
    return seen, idx


def assign_missing_parents(objs: list[dict], rooms: list[dict]) -> None:
    """JSON v6 fallback: smallest overlapping room, like the old editor tree."""
    for obj in objs:
        if obj.get("kind") == "room":
            continue
        if obj.get("kind") == "doorway":
            hits = [r for r in rooms if aabb_overlap(obj, r)]
            hits.sort(key=lambda r: aabb_volume(r))
            if not obj.get("roomId") and hits:
                obj["roomId"] = hits[0].get("id")
            if not obj.get("otherRoomId"):
                other = next((r for r in hits if r.get("id") != obj.get("roomId")), None)
                if other:
                    obj["otherRoomId"] = other.get("id")
            continue
        if obj.get("roomId"):
            continue
        hits = [r for r in rooms if aabb_overlap(obj, r)]
        hits.sort(key=lambda r: aabb_volume(r))
        if hits:
            obj["roomId"] = hits[0].get("id")


def door_rooms(rooms: list[dict], d: dict) -> tuple[int, int]:
    id_to_i = {r.get("id"): i for i, r in enumerate(rooms)}
    ra = id_to_i.get(d.get("roomId"), 255)
    rb = id_to_i.get(d.get("otherRoomId"), 255)
    if ra == 255:
        raise SystemExit(f"doorway at {d.get('x')},{d.get('y')},{d.get('z')} has no owner room")
    return ra, rb


def _xz_overlap(ax: int, asx: int, bx: int, bsx: int) -> bool:
    """Strict overlap matching door.asm .oo_ovx / .oo_ovz (face-touch alone = no)."""
    return ax + asx > bx and bx + bsx > ax


def bake_door_face(door: dict, cols: list[dict]) -> int:
    """Nearer slab plane toward room collider centre (matches door.asm orient_one_door)."""
    dx, dz = int(door["x"]), int(door["z"])
    dsx, dsz = int(door["sx"]), int(door["sz"])
    if dsz <= dsx:
        chosen = None
        for c in cols:
            if int(c["sx"]) == 0:
                continue
            if _xz_overlap(int(c["x"]), int(c["sx"]), dx, dsx):
                chosen = c
                break
        if chosen is None:
            for c in cols:
                if int(c["sx"]) != 0:
                    chosen = c
                    break
        if chosen is None:
            return FACE["+z"]
        cz = int(chosen["z"]) + (int(chosen["sz"]) >> 1)
        d0 = abs(cz - dz)
        d1 = abs(cz - (dz + dsz))
        return FACE["+z"] if d1 < d0 else FACE["-z"]
    chosen = None
    for c in cols:
        if int(c["sx"]) == 0:
            continue
        if _xz_overlap(int(c["z"]), int(c["sz"]), dz, dsz):
            chosen = c
            break
    if chosen is None:
        for c in cols:
            if int(c["sx"]) != 0:
                chosen = c
                break
    if chosen is None:
        return FACE["+x"]
    cx = int(chosen["x"]) + (int(chosen["sx"]) >> 1)
    d0 = abs(cx - dx)
    d1 = abs(cx - (dx + dsx))
    return FACE["+x"] if d1 < d0 else FACE["-x"]


def xz_aabb_gap(a: dict, b: dict) -> int:
    """XZ separation between AABBs; 0 if footprints overlap or touch on an edge."""
    ax0, ax1 = a["x"], a["x"] + a["sx"]
    bx0, bx1 = b["x"], b["x"] + b["sx"]
    if ax1 < bx0:
        dx = bx0 - ax1
    elif bx1 < ax0:
        dx = ax0 - bx1
    else:
        dx = 0
    az0, az1 = a["z"], a["z"] + a["sz"]
    bz0, bz1 = b["z"], b["z"] + b["sz"]
    if az1 < bz0:
        dz = bz0 - az1
    elif bz1 < az0:
        dz = az0 - bz1
    else:
        dz = 0
    return dx + dz


def nearest_floor_home(elev: dict, room: dict, floor_y: int) -> int | None:
    """Upper stop so elev top meets another collider floor in this room, or None."""
    elev_sy = int(elev["sy"])
    elev_top = int(elev["y"]) + elev_sy
    best_key: tuple[int, int] | None = None
    best_home: int | None = None
    for c in room_geometry(room).get("colliders") or []:
        if int(c.get("sx") or 0) <= 0:
            continue
        cy = int(c["y"])
        if cy <= floor_y:
            continue
        home = cy - elev_sy
        if home <= floor_y:
            continue
        key = (xz_aabb_gap(elev, c), abs(cy - elev_top))
        if best_key is None or key < best_key:
            best_key = key
            best_home = home
    return best_home


def nearest_plat_home(
    elev: dict, room_i: int, plats: list[dict], plat_rooms: list[int], floor_y: int
) -> int | None:
    """Upper stop so elev top meets nearest same-room platform top, or None."""
    elev_sy = int(elev["sy"])
    elev_top = int(elev["y"]) + elev_sy
    best_key: tuple[int, int] | None = None
    best_home: int | None = None
    for pi, p in enumerate(plats):
        if plat_rooms[pi] != room_i:
            continue
        surface = int(p["y"]) + int(p.get("sy") or 1)
        home = surface - elev_sy
        if home <= floor_y:
            continue
        key = (xz_aabb_gap(elev, p), abs(surface - elev_top))
        if best_key is None or key < best_key:
            best_key = key
            best_home = home
    return best_home


def btable(name: str, vals: list[int]) -> str:
    if not vals:
        return f"{name}\n"
    lines = [name]
    for i in range(0, len(vals), 16):
        chunk = vals[i : i + 16]
        lines.append("\t!byte " + ",".join(str(v & 0xFF) for v in chunk))
    return "\n".join(lines) + "\n"


def obj_tag(o) -> str:
    return (o.get("tag") or "").strip()


def door_lock_key(d) -> int:
    lk = str(d.get("lockKey") or "").strip().lower()
    if lk in ("blue", "gold"):
        return 2
    if lk in ("yellow", "silver"):
        return 1
    if lk == "red":
        return 4
    if lk == "remote":
        return 3
    if d.get("locked"):
        tag = str(d.get("keyTag") or "").lower()
        if "red" in tag:
            return 4
        return 2 if "gold" in tag or "blue" in tag else 1
    return 0


def ascii_screen(s: str, maxlen: int = 40) -> list[int]:
    """ASCII screen codes for the UI font (mixed case, 32..126)."""
    line = s.replace("\r\n", "\n").split("\n", 1)[0]
    out = []
    for ch in line[:maxlen]:
        o = ord(ch)
        out.append(o if 32 <= o <= 126 else 32)
    return out


def cook_one(level: dict, map_key: str) -> bytes:
    objs = level["objects"]

    rooms = [o for o in objs if o["kind"] == "room"]
    assign_missing_parents(objs, rooms)
    id_to_room = {r.get("id"): r for r in rooms}
    doors = [o for o in objs if o["kind"] == "doorway"]
    for d in doors:
        apply_door_scale_aabb(d)
        room = id_to_room.get(d.get("roomId")) or id_to_room.get(d.get("otherRoomId"))
        if room:
            nudge_door_outside(d, room)
    crates = [o for o in objs if o["kind"] == "crate"]
    slopes = [o for o in objs if o["kind"] == "slope"]
    plats = [o for o in objs if o["kind"] == "platform"]
    switches = [o for o in objs if o["kind"] == "switch"]
    elevs = [o for o in objs if o["kind"] == "elevator"]
    enemies = [o for o in objs if o["kind"] == "enemy"]
    triggers = [o for o in objs if o["kind"] == "trigger"]
    things = [o for o in objs if o["kind"] in ("pickup", "backpack", "key")]
    spawns = [o for o in objs if o["kind"] == "spawn"]

    # Room-sorted (stable): runtime loops walk one room slice via room_*_o.
    for lst, kind in ((slopes, "slope"), (plats, "platform"), (triggers, "trigger"), (things, "pickup")):
        lst.sort(key=lambda o: room_index(rooms, o, kind))

    if not spawns:
        raise SystemExit(f"{map_key} needs a spawn")
    enabled = [o for o in spawns if o.get("enabled")]
    spawn = enabled[0] if enabled else spawns[0]

    if len(objs) > 256:
        raise SystemExit(f"{map_key} has {len(objs)} objects; map id is u8")
    # Unique id per world object (order in level.objects)
    map_id = {id(o): i for i, o in enumerate(objs)}

    TH_TYPE = {
        "small health": 0,
        "large health": 1,
        "green armor": 2,
        "blue armor": 3,
        "ammo box": 4,
        "shells": 5,
        "box of rockets": 6,
        "shotgun": 7,
        "chaingun": 8,
        "chainsaw": 9,
        "rocket launcher": 10,
        "backpack": 11,
        "red keycard": 12,
        "yellow keycard": 13,
        "blue keycard": 14,
        "soulsphere": 15,
        "radsuit": 16,
        "lightpost": 17,
        "barrel": 18,
        "health 25%": 0,
        "health 50%": 1,
        "armour": 2,
        "grenades": 6,
        "grenade launcher": 10,
        "quad damage": 16,
        "pentagram of protection": 15,
        "ring of shadows": 16,
        "silver key": 13,
        "gold key": 14,
        "rune of earth magic": 12,
    }

    # Tag → elevator index
    elev_by_tag: dict[str, int] = {}
    for i, e in enumerate(elevs):
        tag = (e.get("tag") or "").strip()
        if tag:
            elev_by_tag[tag] = i

    TRIG_MSG = 0
    TRIG_END = 1
    TRIG_HURT = 2
    # 3 unused (was teleport). Do not renumber.
    TRIG_ELEV = 4
    TRIG_SUMMON = 5
    TRIG_UNLOCK = 6
    TRIG_HURT_SM = 9
    TRIG_PURPOSE = {
        "message": TRIG_MSG,
        "end_level": TRIG_END,
        "hurt": TRIG_HURT,
        "hurt_small": TRIG_HURT_SM,
        "elevator": TRIG_ELEV,
        "summon": TRIG_SUMMON,
        "unlock": TRIG_UNLOCK,
    }
    SW_DEST_DOOR = 0
    SW_DEST_ELEV = 1
    SW_DEST_TRIG = 2
    SW_SHOOT = 0x80
    TRIG_ENABLE_SHIFT = 4
    TRIG_ENABLE_MAX = 15

    doors_by_tag: dict[str, list] = {}
    for d in doors:
        tag = obj_tag(d)
        if tag:
            doors_by_tag.setdefault(tag, []).append(d)

    door_tag_ids: dict[str, int] = {}
    for d in doors:
        if door_lock_key(d) != 3:
            continue
        tag = obj_tag(d)
        if not tag:
            raise SystemExit(f"{map_key} remote door has empty tag")
        if tag not in door_tag_ids:
            n = len(door_tag_ids) + 1
            if n > 255:
                raise SystemExit(f"{map_key} has too many remote door tags")
            door_tag_ids[tag] = n

    remote_ctrl = {tag: False for tag in door_tag_ids}
    for s in switches:
        tag = obj_tag(s)
        if tag in remote_ctrl:
            remote_ctrl[tag] = True
    for t in triggers:
        if (t.get("purpose") or "") == "unlock":
            tag = obj_tag(t)
            if tag in remote_ctrl:
                remote_ctrl[tag] = True
    for tag, ok in remote_ctrl.items():
        if not ok:
            raise SystemExit(
                f"{map_key} remote door tag {tag!r} has no switch or unlock trigger"
            )

    enable_tag_ids: dict[str, int] = {}
    for t in triggers:
        et = (t.get("enableTag") or "").strip()
        if not et:
            continue
        if et not in enable_tag_ids:
            n = len(enable_tag_ids) + 1
            if n > TRIG_ENABLE_MAX:
                raise SystemExit(
                    f"{map_key} has too many trigger enable tags (max {TRIG_ENABLE_MAX})"
                )
            enable_tag_ids[et] = n
    enable_ctrl = {tag: False for tag in enable_tag_ids}
    for s in switches:
        tag = obj_tag(s)
        if tag in enable_ctrl:
            enable_ctrl[tag] = True
    for tag, ok in enable_ctrl.items():
        if not ok:
            raise SystemExit(f"{map_key} trigger enable tag {tag!r} has no switch")

    # Rooms SoA
    room_x = [r["x"] for r in rooms]
    room_y = [r["y"] for r in rooms]
    room_z = [r["z"] for r in rooms]
    room_sx = [r["sx"] for r in rooms]
    room_sy = [r["sy"] for r in rooms]
    room_sz = [r["sz"] for r in rooms]
    room_bg = [norm_bg(r["a8Bg"]) if "a8Bg" in r else ROOM_BG_DEFAULT for r in rooms]
    room_id = [map_id[id(r)] for r in rooms]

    col_x: list[int] = []
    col_y: list[int] = []
    col_z: list[int] = []
    col_sx: list[int] = []
    col_sy: list[int] = []
    col_sz: list[int] = []
    cut_x: list[int] = []
    cut_y: list[int] = []
    cut_z: list[int] = []
    cut_sx: list[int] = []
    cut_sy: list[int] = []
    cut_sz: list[int] = []
    room_nv: list[int] = []
    room_ne: list[int] = []
    room_vo: list[int] = []
    room_eo: list[int] = []
    room_nx: list[int] = []
    room_nz: list[int] = []
    room_uo: list[int] = []
    room_zo: list[int] = []
    mesh_ux: list[int] = []
    mesh_uz: list[int] = []
    mesh_vy: list[int] = []
    mesh_xid: list[int] = []
    mesh_zid: list[int] = []
    mesh_col: list[int] = []
    mesh_e0: list[int] = []
    mesh_e1: list[int] = []
    mesh_efaces: list[int] = []

    for r in rooms:
        geom = room_geometry(r)
        cols = geom["colliders"]
        if len(cols) > 3:
            raise SystemExit(f"room {r.get('name') or '?'} has {len(cols)} floor areas (max 3)")
        while len(cols) < 3:
            cols.append({"x": 0, "y": 0, "z": 0, "sx": 0, "sy": 0, "sz": 0})
        for c in cols:
            col_x.append(int(c["x"]) & 0xFF)
            col_y.append(int(c["y"]) & 0xFF)
            col_z.append(int(c["z"]) & 0xFF)
            col_sx.append(int(c["sx"]) & 0xFF)
            col_sy.append(int(c["sy"]) & 0xFF)
            col_sz.append(int(c["sz"]) & 0xFF)
        cuts = geom.get("cutouts", [])[:2]
        while len(cuts) < 2:
            cuts.append({"x": 0, "y": 0, "z": 0, "sx": 0, "sy": 0, "sz": 0})
        for c in cuts:
            cut_x.append(int(c["x"]) & 0xFF)
            cut_y.append(int(c["y"]) & 0xFF)
            cut_z.append(int(c["z"]) & 0xFF)
            cut_sx.append(int(c["sx"]) & 0xFF)
            cut_sy.append(int(c["sy"]) & 0xFF)
            cut_sz.append(int(c["sz"]) & 0xFF)
        if clamp_room_shape(r.get("shape")) == "box":
            room_nv.append(0)
            room_ne.append(0)
            room_vo.append(0)
            room_eo.append(0)
            room_nx.append(0)
            room_nz.append(0)
            room_uo.append(0)
            room_zo.append(0)
            continue
        verts = geom["verts"]
        edges = geom["edges"]
        rname = r.get("name") or "?"
        if len(verts) > 16:
            raise SystemExit(f"room {rname!r} has {len(verts)} verts (max 16)")
        if len(edges) > 32:
            raise SystemExit(f"room {rname!r} has {len(edges)} edges (max 32)")
        ux, xid = unique_u8([int(v["x"]) for v in verts], 4, "X", rname)
        uz, zid = unique_u8([int(v["z"]) for v in verts], 4, "Z", rname)
        pairs: list[tuple[int, int]] = []
        col: list[int] = []
        for xi, zi in zip(xid, zid):
            p = (xi, zi)
            if p not in pairs:
                if len(pairs) >= 16:
                    raise SystemExit(f"room {rname!r} has >16 unique XZ columns")
                pairs.append(p)
            col.append(pairs.index(p))
        room_nv.append(len(verts))
        room_ne.append(len(edges))
        room_vo.append(len(mesh_vy))
        room_eo.append(len(mesh_e0))
        room_nx.append(len(ux))
        room_nz.append(len(uz))
        room_uo.append(len(mesh_ux))
        room_zo.append(len(mesh_uz))
        mesh_ux.extend(ux)
        mesh_uz.extend(uz)
        for v, xi, zi, ci in zip(verts, xid, zid, col):
            mesh_vy.append(int(v["y"]) & 0xFF)
            mesh_xid.append(xi)
            mesh_zid.append(zi)
            mesh_col.append(ci)
        for e in edges:
            mesh_e0.append(int(e["a"]) & 0xFF)
            mesh_e1.append(int(e["b"]) & 0xFF)
            mesh_efaces.append(int(e["faces"]) & 0xFF)

    # Doors — one baked instance per owning room, face toward that room
    room_cols: list[list[dict]] = []
    for r in rooms:
        cols = room_geometry(r)["colliders"]
        while len(cols) < 3:
            cols.append({"x": 0, "y": 0, "z": 0, "sx": 0, "sy": 0, "sz": 0})
        room_cols.append(cols[:3])

    by_room: list[list[dict]] = [[] for _ in rooms]
    for d in doors:
        ra, rb = door_rooms(rooms, d)
        key = door_lock_key(d)
        dt = str(d.get("doorType") or "Tech").strip()
        dtype = {
            "Tech": 0,
            "Arch": 1,
            "Tri": 2,
            "Crack": 3,
            "tech": 0,
            "arch": 1,
            "tri": 2,
            "crack": 3,
        }.get(dt, 0)
        if d.get("hidden"):
            dtype |= 0x80
        did = map_id[id(d)]
        tag_id = door_tag_ids.get(obj_tag(d), 0) if key == 3 else 0
        base = {
            "x": d["x"],
            "y": d["y"],
            "z": d["z"],
            "sx": d["sx"],
            "sy": d["sy"],
            "sz": d["sz"],
            "key": key,
            "type": dtype,
            "id": did,
            "tag": tag_id,
        }
        by_room[ra].append({**base, "face": bake_door_face(d, room_cols[ra]), "other": rb})
        if rb != 255:
            by_room[rb].append({**base, "face": bake_door_face(d, room_cols[rb]), "other": ra})

    door_x: list[int] = []
    door_y: list[int] = []
    door_z: list[int] = []
    door_sx: list[int] = []
    door_sy: list[int] = []
    door_sz: list[int] = []
    door_face: list[int] = []
    door_key: list[int] = []
    door_type: list[int] = []
    door_id: list[int] = []
    door_other: list[int] = []
    door_tag: list[int] = []
    room_door_o: list[int] = []
    room_ndoor: list[int] = []
    for lst in by_room:
        room_door_o.append(len(door_x))
        room_ndoor.append(len(lst))
        for inst in lst:
            door_x.append(inst["x"])
            door_y.append(inst["y"])
            door_z.append(inst["z"])
            door_sx.append(inst["sx"])
            door_sy.append(inst["sy"])
            door_sz.append(inst["sz"])
            door_face.append(inst["face"])
            door_key.append(inst["key"])
            door_type.append(inst["type"])
            door_id.append(inst["id"])
            door_other.append(inst["other"])
            door_tag.append(inst["tag"])

    if len(door_x) > 255:
        raise SystemExit(f"{map_key} has {len(door_x)} baked doors (max 255)")

    # Crates
    crate_x, crate_y, crate_z = [], [], []
    crate_sx, crate_sy, crate_sz, crate_room = [], [], [], []
    crate_flags = []
    crate_id = []
    for c in crates:
        ri = room_index(rooms, c, "crate")
        crate_x.append(c["x"])
        crate_y.append(c["y"])
        crate_z.append(c["z"])
        crate_sx.append(c["sx"])
        crate_sy.append(c["sy"])
        crate_sz.append(c["sz"])
        crate_room.append(ri)
        crate_flags.append(1 if c.get("allEdges") else 0)
        crate_id.append(map_id[id(c)])

    # Slopes
    slope_x, slope_y, slope_z = [], [], []
    slope_sx, slope_sy, slope_sz = [], [], []
    slope_axis, slope_dir, slope_room = [], [], []
    slope_id, slope_flags = [], []
    for s in slopes:
        ri = room_index(rooms, s, "slope")
        slope_x.append(s["x"])
        slope_y.append(s["y"])
        slope_z.append(s["z"])
        slope_sx.append(s["sx"])
        slope_sy.append(s["sy"])
        slope_sz.append(s["sz"])
        slope_axis.append(0 if s.get("axis") == "x" else 1)
        slope_dir.append(1 if s.get("dir", 1) >= 0 else 0)  # 1=+ 0=-
        slope_room.append(ri)
        slope_id.append(map_id[id(s)])
        slope_flags.append(int(s.get("flags") or 0) & 3)

    # Platforms (horizontal floor quads)
    plat_x, plat_y, plat_z = [], [], []
    plat_sx, plat_sz, plat_room, plat_solid = [], [], [], []
    plat_id = []
    for p in plats:
        ri = room_index(rooms, p, "platform")
        plat_x.append(p["x"])
        plat_y.append(int(p["y"]) + int(p.get("sy") or 1))
        plat_z.append(p["z"])
        plat_sx.append(p["sx"])
        plat_sz.append(p["sz"])
        plat_room.append(ri)
        plat_solid.append(0 if p.get("collide") is False else 1)
        plat_id.append(map_id[id(p)])

    # Elevators (toggle only)
    elev_x, elev_y, elev_z = [], [], []
    elev_sx, elev_sy, elev_sz = [], [], []
    elev_home, elev_dest, elev_room = [], [], []
    elev_id = []
    for e in elevs:
        ri = room_index(rooms, e, "elevator")
        floor_y = rooms[ri]["y"]
        elev_x.append(e["x"])
        elev_y.append(e["y"])
        elev_z.append(e["z"])
        elev_sx.append(e["sx"])
        elev_sy.append(e["sy"])
        elev_sz.append(e["sz"])
        auto = e.get("elevAuto") is not False
        if auto:
            home = e["y"]
            dest = floor_y
            if e["y"] <= floor_y:
                dest = e["y"]
                raised = nearest_floor_home(e, rooms[ri], floor_y)
                if raised is None:
                    raised = nearest_plat_home(e, ri, plats, plat_room, floor_y)
                if raised is not None:
                    home = raised
        else:
            low = int(e.get("elevLow") or 0)
            high = int(e.get("elevHigh") or 1)
            if high <= low:
                high = low + 1
            dest = floor_y + low
            home = floor_y + high
        elev_home.append(home)
        elev_dest.append(dest)
        elev_room.append(ri)
        elev_id.append(map_id[id(e)])

    # Switches
    sw_x, sw_y, sw_z = [], [], []
    sw_sx, sw_sy, sw_sz = [], [], []
    sw_kind, sw_tag, sw_room, sw_face = [], [], [], []
    sw_id = []
    for s in switches:
        ri = room_index(rooms, s, "switch")
        tag = obj_tag(s)
        tagged_doors = doors_by_tag.get(tag, [])
        in_elev = tag in elev_by_tag
        in_trig = tag in enable_tag_ids
        hits = int(in_elev) + int(bool(tagged_doors)) + int(in_trig)
        if not tag:
            kind, arg = 255, 0
        elif hits > 1:
            raise SystemExit(
                f"{map_key} switch tag {tag!r} matches more than one of elevator, doorway, trigger"
            )
        elif in_elev:
            kind, arg = SW_DEST_ELEV, elev_by_tag[tag]
        elif tagged_doors:
            for d in tagged_doors:
                if door_lock_key(d) != 3:
                    raise SystemExit(
                        f"{map_key} switch tag {tag!r} matches a non-remote doorway"
                    )
            kind, arg = SW_DEST_DOOR, door_tag_ids[tag]
        elif in_trig:
            kind, arg = SW_DEST_TRIG, enable_tag_ids[tag]
        else:
            raise SystemExit(f"{map_key} switch tag {tag!r} has no destination")
        if s.get("shootable") and kind <= SW_DEST_TRIG:
            kind |= SW_SHOOT
        sw_x.append(s["x"])
        sw_y.append(s["y"])
        sw_z.append(s["z"])
        sw_sx.append(s["sx"])
        sw_sy.append(s["sy"])
        sw_sz.append(s["sz"])
        sw_kind.append(kind)
        sw_tag.append(arg)
        sw_room.append(ri)
        sw_face.append(FACE.get(s.get("face") or "+z", 0))
        sw_id.append(map_id[id(s)])

    # Enemies
    en_x, en_y, en_z = [], [], []
    en_type, en_rot, en_room = [], [], []
    en_id = []
    for e in enemies:
        ri = room_index(rooms, e, "enemy")
        name = e.get("enemy") or "Possessed"
        if name not in ENEMY_TYPE:
            raise SystemExit(f"unknown enemy type {name}")
        # Center of placement box (feet on y)
        en_x.append(e["x"] + e["sx"] // 2)
        en_y.append(e["y"])
        en_z.append(e["z"] + e["sz"] // 2)
        en_type.append(ENEMY_TYPE[name])
        en_rot.append(int(e.get("rot") or 0) & 7)
        en_room.append(ri)
        en_id.append(map_id[id(e)])

    # Triggers
    tr_x, tr_y, tr_z = [], [], []
    tr_sx, tr_sy, tr_sz, tr_room = [], [], [], []
    tr_purpose, tr_arg, tr_id = [], [], []
    text_blob: list[int] = []
    for t in triggers:
        ri = room_index(rooms, t, "trigger")
        purpose_s = t.get("purpose") or "message"
        if purpose_s not in TRIG_PURPOSE:
            raise SystemExit(f"unknown trigger purpose {purpose_s!r}")
        purpose = TRIG_PURPOSE[purpose_s]
        arg = 0
        if purpose == TRIG_MSG:
            text = t.get("text") or ""
            arg = len(text_blob)
            chars = ascii_screen(text)
            text_blob.extend(chars)
            text_blob.append(0)  # NUL
        elif purpose in (TRIG_ELEV, TRIG_SUMMON):
            tag = (t.get("tag") or "").strip()
            kind = "elevator" if purpose == TRIG_ELEV else "summon"
            if tag not in elev_by_tag:
                raise SystemExit(f"{kind} trigger tag {tag!r} has no elevator")
            arg = elev_by_tag[tag]
        elif purpose == TRIG_UNLOCK:
            tag = obj_tag(t)
            if tag in door_tag_ids:
                arg = door_tag_ids[tag]
            elif tag in elev_by_tag:
                raise SystemExit(
                    f"{map_key} unlock trigger tag {tag!r} is an elevator (use elevator/summon)"
                )
            elif tag in doors_by_tag:
                raise SystemExit(
                    f"{map_key} unlock trigger tag {tag!r} matches a non-remote doorway"
                )
            else:
                raise SystemExit(
                    f"{map_key} unlock trigger tag {tag!r} has no remote door"
                )
        tr_x.append(t["x"])
        tr_y.append(t["y"])
        tr_z.append(t["z"])
        tr_sx.append(t["sx"])
        tr_sy.append(t["sy"])
        tr_sz.append(t["sz"])
        et = (t.get("enableTag") or "").strip()
        gated = (enable_tag_ids[et] << TRIG_ENABLE_SHIFT) if et else 0
        tr_room.append(ri)
        tr_purpose.append(purpose | gated)
        tr_arg.append(arg)
        tr_id.append(map_id[id(t)])

    by_room_tr: dict[int, int] = {}
    for ri in tr_room:
        by_room_tr[ri] = by_room_tr.get(ri, 0) + 1
    for ri, n in by_room_tr.items():
        if n > TRIG_ROOM_MAX:
            raise SystemExit(
                f"{map_key} room {ri} has {n} triggers (max {TRIG_ROOM_MAX})"
            )

    # Things
    th_x, th_y, th_z, th_type, th_room = [], [], [], [], []
    th_id = []
    for b in things:
        kind = b.get("kind")
        ri = room_index(rooms, b, "pickup")
        if kind == "key":
            tag = f"{b.get('tag') or ''} {b.get('keyTag') or ''} {b.get('pickup') or ''}".lower()
            if "red" in tag:
                bt = 12
            elif "blue" in tag or "gold" in tag:
                bt = 14
            else:
                bt = 13
        else:
            name = (b.get("pickup") or b.get("backpack") or "shells").strip()
            bt = TH_TYPE.get(name, 0)
        th_x.append(b["x"])
        th_y.append(b["y"])
        th_z.append(b["z"])
        th_type.append(bt)
        th_room.append(ri)
        th_id.append(map_id[id(b)])

    spawn_room = room_index(rooms, spawn, "spawn")
    spawn_id = map_id[id(spawn)]

    caps = [
        (rooms, ROOM_MAX, "rooms"),
        (crates, CRATE_MAX, "crates"),
        (slopes, SLOPE_MAX, "slopes"),
        (plats, PLAT_MAX, "platforms"),
        (switches, SWITCH_MAX, "switches"),
        (elevs, ELEV_MAX, "elevators"),
        (enemies, ENEMY_MAX, "enemies"),
        (triggers, TRIG_MAX, "triggers"),
        (things, TH_MAX, "things"),
    ]
    for lst, cap, what in caps:
        if len(lst) > cap:
            raise SystemExit(f"{map_key} has {len(lst)} {what} (max {cap})")

    type_ids: list[int] = []
    for t in en_type:
        if t not in type_ids:
            type_ids.append(t)
    # Per-room cap (streaming holds at most ROOM_MAX_TYPES banks).
    by_room: dict[int, set[int]] = {}
    for r, t in zip(en_room, en_type):
        by_room.setdefault(r, set()).add(t)
    for r, ts in sorted(by_room.items()):
        if len(ts) > ROOM_MAX_TYPES:
            raise SystemExit(
                f"{map_key} room {r} uses {len(ts)} enemy types "
                f"(max {ROOM_MAX_TYPES})"
            )
    # Header still has HDR_TYPE_SLOTS bytes; truncate/pad, no map-wide cap.
    type_ids = type_ids[:HDR_TYPE_SLOTS]
    while len(type_ids) < HDR_TYPE_SLOTS:
        type_ids.append(0xFF)

    n_ux, n_uz = len(mesh_ux), len(mesh_uz)
    n_vert, n_edge = len(mesh_vy), len(mesh_e0)
    for n, what in (
        (n_ux, "unique X"),
        (n_uz, "unique Z"),
        (n_vert, "mesh verts"),
        (n_edge, "mesh edges"),
    ):
        if n > 255:
            msg = f"{map_key} {what} length {n} > 255"
            if what == "mesh edges":
                msg += (
                    "\nBox rooms cost 0 edges; L is 18, T and S are 24. "
                    "Turn one into a box (T or S to L only saves 6)."
                )
            raise SystemExit(msg)

    payload = bytearray()
    payload.extend(
        [
            len(rooms),
            len(door_x),
            len(crates),
            len(slopes),
            len(plats),
            len(switches),
            len(elevs),
            len(enemies),
            len(triggers),
            len(things),
            0,  # map_type0 unused
        ]
    )
    payload.extend(type_ids)
    payload.extend([n_ux, n_uz, n_vert, n_edge])
    payload.extend(
        [
            spawn["x"] & 0xFF,
            spawn["y"] & 0xFF,
            spawn["z"] & 0xFF,
            int(spawn.get("rot") or 0) & 7,
            spawn_room,
            spawn_id,
        ]
    )
    payload.extend(ascii_screen(level.get("name") or ""))
    payload.append(0)

    def add(vals: list[int]) -> None:
        payload.extend(v & 0xFF for v in vals)

    add(room_x)
    add(room_y)
    add(room_z)
    add(room_sx)
    add(room_sy)
    add(room_sz)
    add(room_bg)
    add(col_x)
    add(col_y)
    add(col_z)
    add(col_sx)
    add(col_sy)
    add(col_sz)
    add(cut_x)
    add(cut_y)
    add(cut_z)
    add(cut_sx)
    add(cut_sy)
    add(cut_sz)
    add(room_nv)
    add(room_ne)
    add(room_vo)
    add(room_eo)
    add(room_nx)
    add(room_nz)
    add(room_uo)
    add(room_zo)
    add(room_door_o)
    add(room_ndoor)
    add(mesh_ux)
    add(mesh_uz)
    add(mesh_vy)
    add(mesh_xid)
    add(mesh_zid)
    add(mesh_col)
    add(mesh_e0)
    add(mesh_e1)
    add(mesh_efaces)
    add(door_x)
    add(door_y)
    add(door_z)
    add(door_sx)
    add(door_sy)
    add(door_sz)
    add(door_face)
    add(door_key)
    add(door_type)
    add(door_id)
    add(door_other)
    add(door_tag)
    add(crate_x)
    add(crate_y)
    add(crate_z)
    add(crate_sx)
    add(crate_sy)
    add(crate_sz)
    add(crate_room)
    add(crate_flags)
    add(slope_x)
    add(slope_y)
    add(slope_z)
    add(slope_sx)
    add(slope_sy)
    add(slope_sz)
    add(slope_axis)
    add(slope_dir)
    add(slope_room)
    add(slope_flags)
    add(plat_x)
    add(plat_y)
    add(plat_z)
    add(plat_sx)
    add(plat_sz)
    add(plat_room)
    add(plat_solid)
    add(elev_x)
    add(elev_y)
    add(elev_z)
    add(elev_sx)
    add(elev_sy)
    add(elev_sz)
    add(elev_home)
    add(elev_dest)
    add(elev_room)
    add(elev_id)
    add(sw_x)
    add(sw_y)
    add(sw_z)
    add(sw_sx)
    add(sw_sy)
    add(sw_sz)
    add(sw_kind)
    add(sw_tag)
    add(sw_room)
    add(sw_face)
    add(en_x)
    add(en_y)
    add(en_z)
    add(en_type)
    add(en_rot)
    add(en_room)
    add(tr_x)
    add(tr_y)
    add(tr_z)
    add(tr_sx)
    add(tr_sy)
    add(tr_sz)
    add(tr_room)
    add(tr_purpose)
    add(tr_arg)
    add(th_x)
    add(th_y)
    add(th_z)
    add(th_type)
    add(th_room)
    # room_<type>_o: first index of each room's slice (nrooms+1; last = count)
    for lst in (slope_room, plat_room, tr_room, th_room):
        add([sum(1 for r in lst if r < i) for i in range(len(rooms) + 1)])
    payload.extend(text_blob if text_blob else [0])

    if len(payload) > MAP_MAX_BYTES:
        raise SystemExit(
            f"{map_key} packed size {len(payload)} exceeds {MAP_MAX_BYTES}"
        )
    return bytes(payload)


ENUMS = """; Generated by tools/genmap.py — counts / types (runtime n* live in BSS)
ROOM_MAX	= 24
CRATE_MAX	= 16
SLOPE_MAX	= 16
PLAT_MAX	= 20
SWITCH_MAX	= 16
ELEV_MAX	= 4
TRIG_MAX	= 16
TRIG_ROOM_MAX	= 8
ROOM_MAX_TYPES	= 2
MAP_MAX_BYTES	= 4096
ENEMY_POSE_MAX	= 7680
MAP_NLEVELS	= 8
TRIG_MSG	= 0
TRIG_END	= 1
TRIG_HURT	= 2
; 3 unused (was teleport). 7 and 8 unused (were electrode). Do not renumber.
TRIG_ELEV	= 4
TRIG_SUMMON	= 5
TRIG_UNLOCK	= 6
TRIG_HURT_SM	= 9
TRIG_PURPOSE_MASK	= $0F
TRIG_GATED_MASK	= $F0
SW_DEST_DOOR	= 0
SW_DEST_ELEV	= 1
SW_DEST_TRIG	= 2
SW_SHOOT	= $80
FACE_PZ	= 0
FACE_MZ	= 1
FACE_PX	= 2
FACE_MX	= 3
TH_HEALTH_SM	= 0
TH_HEALTH_LG	= 1
TH_ARMOR_G	= 2
TH_ARMOR_B	= 3
TH_BULLETS	= 4
TH_SHELLS	= 5
TH_ROCKETS	= 6
TH_SHOTGUN	= 7
TH_CHAINGUN	= 8
TH_CHAINSAW	= 9
TH_ROCKETLAUNCHER	= 10
TH_BACKPACK	= 11
TH_KEY_RED	= 12
TH_KEY_YELLOW	= 13
TH_KEY_BLUE	= 14
TH_SOUL	= 15
TH_RADSUIT	= 16
TH_LIGHTPOST	= 17
TH_BARREL	= 18
TH_NTYPES	= 19
DOOR_KEY_NONE	= 0
DOOR_KEY_YELLOW	= 1
DOOR_KEY_BLUE	= 2
DOOR_KEY_REMOTE	= 3
DOOR_KEY_RED	= 4
DOOR_TECH	= 0
DOOR_ARCH	= 1
DOOR_TRI	= 2
DOOR_CRACK	= 3
DOOR_NTYPES	= 4
DOOR_HIDDEN	= $80
ENT_POSS	= 0
ENT_BARON	= 1
ENT_PINKY	= 2
ENT_IMP	= 3
ENEMY_NTYPES	= 4
ENEMY_CLASS_HUM	= 0
"""


def load_level(key: str) -> dict:
    path = EDITOR_MAPS / f"{key.lower()}.json"
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    level = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(level, dict):
        raise SystemExit(f"{path}: expected object")
    return level


def main() -> None:
    import struct

    MAP_DIR.mkdir(exist_ok=True)
    sizes: list[int] = []
    cooked: list[str] = []
    for key in LEVEL_NAMES:
        level = load_level(key)
        objs = level.get("objects") or []
        has_spawn = any(o.get("kind") == "spawn" for o in objs)
        out = MAP_DIR / f"{key.lower()}.prg"
        if not has_spawn:
            if out.exists():
                out.unlink()
            sizes.append(0)
            continue
        payload = cook_one(level, key)
        out.write_bytes(struct.pack("<H", 0) + payload)
        sizes.append(len(payload))
        cooked.append(f"{key} {len(payload)}B")

    # Editor activeLevel is which map is open. The game always boots E1M1.
    start_idx = 0
    start_level = 1
    counts = ENUMS.replace(
        "MAP_NLEVELS\t= 8\n",
        f"MAP_NLEVELS\t= 8\nSTART_LEVEL\t= {start_level}\n",
        1,
    )
    COUNTS_OUT.write_text(counts, encoding="utf-8")
    size_lo = ",".join(str(s & 0xFF) for s in sizes)
    size_hi = ",".join(str((s >> 8) & 0xFF) for s in sizes)
    SIZES_OUT.write_text(
        "; Generated by tools/genmap.py — payload bytes per E1M1..E1M8\n"
        f"map_size_lo\t!byte {size_lo}\n"
        f"map_size_hi\t!byte {size_hi}\n",
        encoding="utf-8",
    )
    extra = f": {', '.join(cooked)}" if cooked else ""
    print(f"Wrote map_counts.asm + map_sizes.asm{extra} START_LEVEL {LEVEL_NAMES[start_idx]}")


if __name__ == "__main__":
    main()
