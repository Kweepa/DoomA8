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
                            room=L.f("en_room", i), yaw=(L.f("en_rot", i) * 32) & 255, state=0))
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
        for (lab, ox, oy, oz, oyaw, kind, aux) in sd.static[room]:
            if kind == 1 and (sd.L.f("door_type", aux) & 0x80):
                continue
            m = sd.mesh(lab)
            draw(ox, oy, oz, oyaw, m.verts, m.edges, m.shift, m.radius)
    if "things" in parts:
        for (t, ty, x, y, z) in sd.things[room]:
            if t in taken:
                continue
            m = sd.items[gen.ITEM_ORDER[ty]]
            draw(x * 256 + 128, y * 256, z * 256 + 128, (spin * 2) & 255, m.verts, m.edges, m.shift, m.radius)
    if "enemies" in parts:
        for e in (enemies if enemies is not None else sd.enemy_list()):
            if e["room"] != room or e["state"] == 7:
                continue
            key = ge.ENEMY_FILES[e["type"]][0]
            en = sd.enemies[key]
            start, ln = en["clips"]["stand"]
            frame = start + ((spin >> 2) % ln)
            draw(e["x"] * 256 + 128, e["y"] * 256, e["z"] * 256 + 128, e["yaw"], en["frames"][frame], en["edges"], 4, 3)
    return fb
