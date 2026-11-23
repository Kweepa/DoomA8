#!/usr/bin/env python3
"""Per-level static object meshes and per-room instance lists (ROM bank OBJ_BANK0 + level).

Static objects are entity instances (gbc_entity format, quarter-unit local verts, origin in 8.8):
crates, platforms, slopes, switches, elevators (at their home height) and doors.
Things (pickups, barrels, lightposts) reference shared item meshes in the entity bank.

Per room (ObjTab[room] -> list):
  db n_static ; n * 12 bytes: dw mesh_ptr, dw ox, dw oy, dw oz, db yaw, db kind, db aux
       kind 0 plain, 1 door (aux = global door index, hidden state read at draw time),
            2 elevator (aux = elevator index)
  db n_things ; n * 6 bytes: db thing_index, type, x, y, z, 0
Mesh record: db nv, ne, shift, radius ; verts (x,y,z)*nv ; edges (a,b)*ne
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gbc_entity as ge  # noqa: E402
import gbc_genmap as gmap  # noqa: E402
import gbc_world as gw  # noqa: E402

OBJ_BANK0 = 11

BOX_EDGES = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
FACE_YAW = [0, 128, 192, 64]          # PZ, MZ, PX, MX: local +Z points out of the face


def q(v):
    return int(round(v * 4))


def box_verts(sx, sy, sz):
    hx, hz = q(sx / 2.0), q(sz / 2.0)
    h = q(sy)
    return [(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz),
            (-hx, h, -hz), (hx, h, -hz), (hx, h, hz), (-hx, h, hz)]


def switch_tri(sx, sy, sz, face):
    """Up-pointing triangle on the switch's face (A8: mesh.asm fill_switch_verts): apex at the top
    centre, base across the middle. Faces: 0 +Z, 1 -Z, 2 +X, 3 -X. Origin = box centre at the floor."""
    hx, hz, top, mid = q(sx / 2.0), q(sz / 2.0), q(sy), q(sy / 2.0)
    if face < 2:
        zf = hz if face == 0 else -hz
        verts = [(0, top, zf), (-hx, mid, zf), (hx, mid, zf)]
    else:
        xf = hx if face == 2 else -hx
        verts = [(xf, top, 0), (xf, mid, -hz), (xf, mid, hz)]
    return verts, [(0, 1), (1, 2), (2, 0)]


class Pool:
    def __init__(self, label):
        self.label = label
        self.meshes = []
        self.index = {}

    def add(self, verts, edges, radius=None):
        key = (tuple(verts), tuple(edges))
        if key not in self.index:
            self.index[key] = len(self.meshes)
            self.meshes.append(ge.Mesh("m", list(verts), list(edges), radius=radius))
        return "%s_M%d" % (self.label, self.index[key])


def door_mesh(items, dtype, width):
    names = ["Tech", "Arch", "Tri"]
    m = items[names[dtype if dtype < 3 else 0]]
    scale = 1.0 if width < 5 else (1.5 if width < 7 else 2.0)
    verts = [(int(round(x * scale)), int(round(y * scale)), int(round(z * scale))) for (x, y, z) in m.verts]
    return verts, list(m.edges)


def level_objects(L, lv_objs, pool, items):
    """Returns (static_by_room, things_by_room)."""
    nrooms = L.nrooms
    static = [[] for _ in range(nrooms)]
    things = [[] for _ in range(nrooms)]

    def add(room, mesh_label, ox, oy, oz, yaw, kind=0, aux=0):
        static[room].append((mesh_label, ox, oy, oz, yaw, kind, aux))

    for x in range(L.ncrates):
        sx, sy, sz = L.f("crate_sx", x), L.f("crate_sy", x), L.f("crate_sz", x)
        lab = pool.add(box_verts(sx, sy, sz), BOX_EDGES)
        add(L.f("crate_room", x), lab, L.f("crate_x", x) * 256 + sx * 128, L.f("crate_y", x) * 256,
            L.f("crate_z", x) * 256 + sz * 128, 0)
    for r in range(nrooms):
        lo, hi = gw.slice_of(L, "room_plat_o", r)
        for x in range(lo, hi):
            sx, sz = L.f("plat_sx", x), L.f("plat_sz", x)
            hx, hz = q(sx / 2.0), q(sz / 2.0)
            lab = pool.add([(-hx, 0, -hz), (hx, 0, -hz), (hx, 0, hz), (-hx, 0, hz)],
                           [(0, 1), (1, 2), (2, 3), (3, 0)])
            add(r, lab, L.f("plat_x", x) * 256 + sx * 128, L.f("plat_y", x) * 256, L.f("plat_z", x) * 256 + sz * 128, 0)
        lo, hi = gw.slice_of(L, "room_slope_o", r)
        for x in range(lo, hi):
            sx, sy, sz = L.f("slope_sx", x), L.f("slope_sy", x), L.f("slope_sz", x)
            axis, dirn, flags = L.f("slope_axis", x), L.f("slope_dir", x), L.f("slope_flags", x)
            hx, hz, h = q(sx / 2.0), q(sz / 2.0), q(sy)
            if axis == 0:                       # run along X
                lowx, highx = (-hx, hx) if dirn else (hx, -hx)
                verts = [(lowx, 0, -hz), (lowx, 0, hz), (highx, h, hz), (highx, h, -hz)]
            else:                               # run along Z
                lowz, highz = (-hz, hz) if dirn else (hz, -hz)
                verts = [(-hx, 0, lowz), (hx, 0, lowz), (hx, h, highz), (-hx, h, highz)]
            edges = [(0, 3), (1, 2)]
            if flags & 1:
                edges.append((0, 1))
            if flags & 2:
                edges.append((3, 2))
            lab = pool.add(verts, edges)
            add(r, lab, L.f("slope_x", x) * 256 + sx * 128, L.f("slope_y", x) * 256, L.f("slope_z", x) * 256 + sz * 128, 0)
    for x in range(L.p[5]):
        sx, sy, sz = L.f("sw_sx", x), L.f("sw_sy", x), L.f("sw_sz", x)
        lab = pool.add(*switch_tri(sx, sy, sz, L.f("sw_face", x)))
        add(L.f("sw_room", x), lab, L.f("sw_x", x) * 256 + sx * 128, L.f("sw_y", x) * 256, L.f("sw_z", x) * 256 + sz * 128, 0)
    for x in range(L.p[6]):
        sx, sy, sz = L.f("elev_sx", x), L.f("elev_sy", x), L.f("elev_sz", x)
        lab = pool.add(box_verts(sx, sy, sz), BOX_EDGES)
        add(L.f("elev_room", x), lab, L.f("elev_x", x) * 256 + sx * 128, L.f("elev_home", x) * 256,
            L.f("elev_z", x) * 256 + sz * 128, 0, 2, x)
    # doors: type mesh scaled by face width, at the outward face's bottom centre
    for d in range(L.p[1]):
        dtype = L.f("door_type", d) & 0x7F
        if dtype >= 3:
            continue
        face = L.f("door_face", d)
        x0, z0, sx, sz = L.f("door_x", d), L.f("door_z", d), L.f("door_sx", d), L.f("door_sz", d)
        width = sz if face >= 2 else sx
        verts, edges = door_mesh(items, dtype, width)
        lab = pool.add(verts, edges)
        if face == 0:
            ox, oz = x0 * 256 + sx * 128, (z0 + sz) * 256
        elif face == 1:
            ox, oz = x0 * 256 + sx * 128, z0 * 256
        elif face == 2:
            ox, oz = (x0 + sx) * 256, z0 * 256 + sz * 128
        else:
            ox, oz = x0 * 256, z0 * 256 + sz * 128
        # the door instance belongs to the room that owns it: find it from the room door slices
        for r in range(nrooms):
            lo = L.f("room_door_o", r)
            if lo <= d < lo + L.f("room_ndoor", r):
                add(r, lab, ox, L.f("door_y", d) * 256, oz, FACE_YAW[face & 3], 1, d)
                break
    for t in range(L.p[9]):
        things[L.f("th_room", t)].append((t, L.f("th_type", t), L.f("th_x", t), L.f("th_y", t), L.f("th_z", t)))
    return static, things


def db(vals, per=16):
    return "\n".join("    db " + ",".join(str(v & 255) for v in vals[i:i + per]) for i in range(0, len(vals), per))


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    items = ge.load_items()
    out = ["; Generated by tools/gbc_genobj.py - do not edit."]
    li = 0
    keys = []
    for key in gmap.gm.LEVEL_NAMES:
        lv = gmap.gm.load_level(key)
        if not any(o.get("kind") == "spawn" for o in (lv.get("objects") or [])):
            continue
        L = gw.Level(gmap.gm.cook_one(lv, key))
        pool = Pool("Obj%s" % key)
        static, things = level_objects(L, lv.get("objects") or [], pool, items)
        out.append('SECTION "obj_%s", ROMX, BANK[%d]' % (key, OBJ_BANK0 + li))
        out.append("Obj%s_Tab::" % key)
        out.append("    dw " + ",".join("Obj%s_R%d" % (key, r) for r in range(L.nrooms)))
        for r in range(L.nrooms):
            out.append("Obj%s_R%d:" % (key, r))
            out.append("    db %d" % len(static[r]))
            for (lab, ox, oy, oz, yaw, kind, aux) in static[r]:
                out.append("    dw %s, %d, %d, %d\n    db %d, %d, %d" % (lab, ox, oy, oz, yaw, kind, aux))
            out.append("    db %d" % len(things[r]))
            for (t, ty, x, y, z) in things[r]:
                out.append("    db %d, %d, %d, %d, %d, 0" % (t, ty, x, y, z))
        for i, m in enumerate(pool.meshes):
            out.append("%s_M%d:" % (pool.label, i))
            out.append("    db %d, %d, %d, %d" % (len(m.verts), len(m.edges), m.shift, m.radius))
            out.append(db([c for v in m.verts for c in v]))
            out.append(db([c for e in m.edges for c in e]))
        keys.append(key)
        li += 1
    out.append('SECTION "obj_index", ROM0')
    out.append("ObjBank0:: db %d" % OBJ_BANK0)
    out.append("LevelObjTab:: dw " + ",".join("Obj%s_Tab" % k for k in keys))
    open(os.path.join(outdir, "objects.inc"), "w", newline="\n").write("\n".join(out) + "\n")
    print("object banks: %d levels" % len(keys))


if __name__ == "__main__":
    main()
