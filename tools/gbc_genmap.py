#!/usr/bin/env python3
"""GBC map cooker back-end.

Reuses genmap.cook_one (the A8 packed map: header + name + SoA columns) and adds, per level:
  - field offsets: where each SoA column starts inside the payload (bind table from src/overlay.asm)
  - per-room render mesh in the renderer's format (box rooms are synthesized from their AABB)

Writes <outdir>/maps.inc (ROM banks 2.. one per level) and <outdir>/map_fields.inc (field ids).
Mesh record per room: nux, nuz, nc, nv, ne, ux[], uz[], cols (xid,zid)[], verts (col,y)[], edges (a,b)[].
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import genmap as gm  # noqa: E402

ROOT = os.path.dirname(HERE)
FIRST_MAP_BANK = 2

HDR_COUNTS = ["map_nrooms", "map_ndoors", "map_ncrates", "map_nslopes", "map_nplats",
              "map_nswitches", "map_nelevs", "map_nenemies", "map_ntrigs", "map_nthings",
              "map_type0", "map_type1", "map_type2", "map_nux", "map_nuz", "map_nvert", "map_nedge"]


def parse_bind_table():
    """[(field, count_source)] from src/overlay.asm; count_source is a header name or 'x3'/'x2'/'+1'."""
    text = open(os.path.join(ROOT, "src", "overlay.asm")).read()
    text = text[text.index("bind_tab\n"):]
    mode = "bind_n"
    fields = []
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"\+bind_add\s+(\w+),\s*(\w+)", line)
        if m:
            fld, src = m.groups()
            if src == "bind_n":
                src = mode
            fields.append((fld, src))
        elif line.startswith("+bind_set_n3"):
            mode = "x3"
        elif line.startswith("+bind_set_n2"):
            mode = "x2"
        elif line.startswith("+bind_set_n1"):
            mode = "+1"
        elif line.startswith("!byte $ff"):
            break
    return fields


def field_offsets(payload, fields):
    hdr = list(payload[:23])
    counts = dict(zip(HDR_COUNTS, hdr))
    nrooms = counts["map_nrooms"]
    cur = 23
    while payload[cur] != 0:
        cur += 1
    cur += 1                                   # past the name NUL
    offs = []
    for fld, src in fields:
        if src == "x3":
            n = nrooms * 3
        elif src == "x2":
            n = nrooms * 2
        elif src == "+1":
            n = nrooms + 1
        else:
            n = counts[src]
        offs.append((fld, cur, n))
        cur += n
    return hdr, offs, cur


def unique(vals):
    out = []
    for v in vals:
        if v not in out:
            out.append(v)
    return out


def room_mesh(room):
    """(ux, uz, cols[(xi,zi)], verts[(col,y)], edges[(a,b)]) in the renderer's format."""
    geo = gm.room_geometry(room)
    if geo["verts"]:
        pts = [(int(v["x"]), int(v["y"]), int(v["z"])) for v in geo["verts"]]
        edges = [(int(e["a"]), int(e["b"])) for e in geo["edges"]]
    else:
        o = geo["outer"]
        x0, x1 = int(o["x"]), int(o["x"]) + int(o["sx"])
        y0, y1 = int(o["y"]), int(o["y"]) + int(o["sy"])
        z0, z1 = int(o["z"]), int(o["z"]) + int(o["sz"])
        pts = [(x, y, z) for y in (y0, y1) for (x, z) in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
        edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4),
                 (0, 4), (1, 5), (2, 6), (3, 7)]
    ux = unique([p[0] for p in pts])
    uz = unique([p[2] for p in pts])
    cols = []
    verts = []
    for (x, y, z) in pts:
        c = (ux.index(x), uz.index(z))
        if c not in cols:
            cols.append(c)
        verts.append((cols.index(c), y))
    return ux, uz, cols, verts, edges


def db(vals, per=16):
    out = []
    for i in range(0, len(vals), per):
        out.append("    db " + ",".join(str(v & 255) for v in vals[i:i + per]))
    return "\n".join(out)


def map_tests(levels_filter=None):
    """[(level_idx, room_idx, camx, camz, camy, yaw)]: every room of every level from its
    centre (8.8, with fractional offsets) at two yaws. Used by MAPTEST and gbc_maptest.py."""
    out = []
    li = 0
    for key in gm.LEVEL_NAMES:
        lv = gm.load_level(key)
        objs = lv.get("objects") or []
        if not any(o.get("kind") == "spawn" for o in objs):
            continue
        rooms = [o for o in objs if o.get("kind") == "room"]
        for ri, r in enumerate(rooms):
            geo = gm.room_geometry(r)
            o = geo["outer"]
            camx = int(o["x"]) * 256 + int(o["sx"]) * 128 + 77
            camz = int(o["z"]) * 256 + int(o["sz"]) * 128 + 131
            camy = (int(o["y"]) + 3) * 256 + 40
            for yaw in (13, 141):
                out.append((li, ri, camx, camz, camy, yaw))
        li += 1
    return out


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    fields = parse_bind_table()
    levels = []
    for key in gm.LEVEL_NAMES:
        lv = gm.load_level(key)
        objs = lv.get("objects") or []
        if not any(o.get("kind") == "spawn" for o in objs):
            continue
        payload = gm.cook_one(lv, key)
        hdr, offs, end = field_offsets(payload, fields)
        assert end <= len(payload), (key, end, len(payload))
        rooms = [o for o in objs if o.get("kind") == "room"]
        meshes = [room_mesh(r) for r in rooms]
        assert len(rooms) == hdr[0], (key, len(rooms), hdr[0])
        levels.append((key, payload, hdr, offs, meshes))

    mc = []
    for i, (key, payload, hdr, offs, meshes) in enumerate(levels):
        bank = FIRST_MAP_BANK + i
        n = key
        mc.append("; ---- %s ----" % key)
        mc.append('SECTION "map_%s", ROMX, BANK[%d]' % (n, bank))
        mc.append("Map%s_Payload::" % n)
        mc.append(db(list(payload)))
        mc.append("Map%s_PayloadEnd::" % n)
        mc.append("Map%s_FieldOffs::" % n)
        mc.append("    dw " + ",".join(str(o) for (_, o, _) in offs))
        mc.append("Map%s_RoomTab::" % n)
        for r in range(len(meshes)):
            mc.append("    dw Map%s_Room%d" % (n, r))
        for r, (ux, uz, cols, verts, edges) in enumerate(meshes):
            mc.append("Map%s_Room%d:" % (n, r))
            mc.append("    db %d, %d, %d, %d, %d" % (len(ux), len(uz), len(cols), len(verts), len(edges)))
            mc.append(db(ux + uz))
            mc.append(db([v for c in cols for v in c]))
            mc.append(db([v for c in verts for v in c]))
            mc.append(db([v for c in edges for v in c]))
        mc.append("")
    mc.append('SECTION "map_index", ROM0')
    mc.append("NumLevels:: db %d" % len(levels))
    mc.append("LevelBank:: db " + ",".join(str(FIRST_MAP_BANK + i) for i in range(len(levels))))
    mc.append("LevelPayload:: dw " + ",".join("Map%s_Payload" % l[0] for l in levels))
    mc.append("LevelPayloadLen:: dw " + ",".join(str(len(l[1])) for l in levels))
    mc.append("LevelFieldOffs:: dw " + ",".join("Map%s_FieldOffs" % l[0] for l in levels))
    mc.append("LevelRoomTab:: dw " + ",".join("Map%s_RoomTab" % l[0] for l in levels))
    with open(os.path.join(outdir, "maps.inc"), "w", newline="\n") as f:
        f.write("; Generated by tools/gbc_genmap.py - do not edit.\n")
        f.write("\n".join(mc) + "\n")

    with open(os.path.join(outdir, "map_fields.inc"), "w", newline="\n") as f:
        f.write("; Generated by tools/gbc_genmap.py - do not edit.\n")
        f.write("; Map header byte offsets (first 23 payload bytes, copied to wMapHdr).\n")
        for i, name in enumerate(HDR_COUNTS):
            f.write("DEF H_%s EQU %d\n" % (name[4:].upper(), i))
        for i, name in enumerate(["spawn_x", "spawn_y", "spawn_z", "spawn_rot", "spawn_room", "spawn_id"]):
            f.write("DEF H_%s EQU %d\n" % (name.upper(), 17 + i))
        f.write("; Field ids: index into the per-level FieldOffs table / wFieldPtr.\n")
        for i, (fld, _) in enumerate(fields):
            f.write("DEF F_%s EQU %d\n" % (fld.upper(), i))
        f.write("DEF NUM_FIELDS EQU %d\n" % len(fields))
    tests = map_tests()
    with open(os.path.join(outdir, "maptest.inc"), "w", newline="\n") as f:
        f.write("; Generated by tools/gbc_genmap.py - do not edit.\n")
        f.write("DEF NumMapTests EQU %d\nEXPORT NumMapTests\nMapTestTab::\n" % len(tests))
        for (lv_, rm, cx, cz, cy, yaw) in tests:
            f.write("    db %d, %d\n    dw %d, %d, %d\n    db %d, 0\n" % (lv_, rm, cx, cz, cy, yaw))
    for key, payload, hdr, offs, meshes in levels:
        print("%s: payload %d B, %d rooms, %d fields, spawn=%s" % (key, len(payload), hdr[0], len(offs), hdr[17:23]))


if __name__ == "__main__":
    main()
