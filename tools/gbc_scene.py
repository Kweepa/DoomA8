#!/usr/bin/env python3
"""Whole-scene spec: room mesh + static objects + pickups/props + enemies, as the demo draws them.
Used by gbc_check.py --live to compare a headless screenshot with the SM83 output."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gbc_entity as ge  # noqa: E402
import gbc_genent as gen  # noqa: E402
import gbc_genmap as gmap  # noqa: E402
import gbc_genobj as gobj  # noqa: E402
import gbc_room as gr  # noqa: E402
import gbc_world as gw  # noqa: E402


# A8 mesh.asm box_edge_faces: which box faces (bit0 -X, 1 +X, 2 -Y, 3 +Y, 4 -Z, 5 +Z) each edge belongs to.
CRATE_EDGE_FACES = [0x14, 0x06, 0x24, 0x05, 0x18, 0x0A, 0x28, 0x09, 0x11, 0x12, 0x22, 0x21]


class SceneData:
    def __init__(self, key):
        lv = gmap.gm.load_level(key)
        self.objs = lv.get("objects") or []
        self.L = gw.Level(gmap.gm.cook_one(lv, key))
        self.rooms = [o for o in self.objs if o.get("kind") == "room"]
        self.items = ge.load_items()
        self.enemies = ge.load_enemies()
        self.pool = gobj.Pool("X")
        self.static, self.things = gobj.level_objects(self.L, self.objs, self.pool, self.items)

    def mesh(self, label):
        return self.pool.meshes[int(label.split("_M")[1])]

    def enemy_list(self):
        L = self.L
        out = []
        for i in range(L.p[7]):
            out.append(dict(x=L.f("en_x", i), y=L.f("en_y", i), z=L.f("en_z", i), type=L.f("en_type", i),
                            room=L.f("en_room", i), rot=(L.f("en_rot", i) * 32) & 255,
                            state=8 if L.f("en_tag", i) else 0, frame=0))
        return out


def scene_pixels(sd, room, cam_x, cam_z, cam_y, yaw, spin, enemies=None, taken=(), parts=("room", "static", "things", "enemies")):
    import gbc_genlines as gl
    fb = set()
    if "room" in parts:
        gr.set_scene(*gmap.room_mesh(sd.rooms[room]))
        fb |= gr.render(cam_x, cam_z, yaw, cam_y)

    def draw(ox, oy, oz, oyaw, verts, edges, shift, radius):
        fb.update(ge.entity_pixels(cam_x, cam_z, cam_y, yaw, ox, oz, oy, oyaw, verts, edges, shift, radius))

    if "static" in parts:
        L = sd.L
        cx, cy, cz = cam_x >> 8, cam_y >> 8, cam_z >> 8

        def front(face, x, z, sx, sz):
            """A8 check_face_front: the camera cell is on the outward side of the face plane."""
            if face == 0:
                return cz >= z + sz
            if face == 1:
                return z >= cz
            if face == 2:
                return cx >= x + sx
            return x >= cx
        for (lab, ox, oy, oz, oyaw, kind, aux) in sd.static[room]:
            m = sd.mesh(lab)
            edges = m.edges
            if kind == 1:
                if L.f("door_type", aux) & 0x80:
                    continue
                if not front(L.f("door_face", aux), L.f("door_x", aux), L.f("door_z", aux), L.f("door_sx", aux), L.f("door_sz", aux)):
                    continue
            elif kind == 4:
                if front(L.f("sw_face", aux), L.f("sw_x", aux), L.f("sw_z", aux), L.f("sw_sx", aux), L.f("sw_sz", aux)):
                    continue
            elif kind == 5:
                if (not L.f("plat_solid", aux) and L.f("plat_sx", aux) < 5 and L.f("plat_sz", aux) < 5
                        and cy < L.f("plat_y", aux)):
                    continue
            elif kind == 3 and not L.f("crate_flags", aux):
                bits = 0
                for a, (pn, sn, c) in enumerate((("crate_x", "crate_sx", cx), ("crate_y", "crate_sy", cy), ("crate_z", "crate_sz", cz))):
                    lo, size = L.f(pn, aux), L.f(sn, aux)
                    if c < lo:
                        bits |= 1 << (2 * a)
                    elif c - lo >= size:
                        bits |= 2 << (2 * a)
                edges = [e for i, e in enumerate(m.edges) if CRATE_EDGE_FACES[i] & bits]
                if not edges:
                    continue
            draw(ox, oy, oz, oyaw, m.verts, edges, m.shift, m.radius)
    if "things" in parts:
        for (t, ty, x, y, z) in sd.things[room]:
            if t in taken:
                continue
            m = sd.items[gen.ITEM_ORDER[ty]]
            # A8 xform_item_spin / fill_item_verts: centre at cell + ITEM_BIAS (1); lightpost (17) and
            # barrel (18) stay put, pickups take item_spin (spin = its high byte).
            oyaw = 0 if ty in (17, 18) else spin & 255
            draw((x + 1) * 256, y * 256, (z + 1) * 256, oyaw, m.verts, m.edges, m.shift, m.radius)
    if "enemies" in parts:
        for e in (enemies if enemies is not None else sd.enemy_list()):
            if e["room"] != room or e["state"] == 8:     # EN_GONE (tagged, not spawned)
                continue
            key = ge.ENEMY_FILES[e["type"]][0]
            en = sd.enemies[key]
            start, ln = en["clips"]["stand"]
            frame = start + e.get("frame", 0)          # idle: A8 enemy_logical_frame
            # A8: enemies sit at the cell origin; bones are drawn with R(yaw - en_rot)
            draw(e["x"] * 256, e["y"] * 256, e["z"] * 256, (-e["rot"]) & 255, en["frames"][frame], en["edges"], 4, 3)
    return fb
