#!/usr/bin/env python3
"""Entity meshes (items, enemies, doors, world objects): spec + cooker data model.

A mesh is local vertices (signed bytes, units of 2^-S world units; S = 2 means quarter units)
and edges. An instance has a world origin (x, y, z in 8.8), a yaw and a mesh.

View space: O = rotate(origin - cam) by the camera yaw; a local vertex adds
rot(cam_yaw + obj_yaw)(lx, lz) (sign-magnitude, >> (S-1)) and ly << (8-S). Projection and edge
clipping are shared with the room renderer (gbc_room.edge_segments), so the result is
bit-exact with the SM83 code.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gbc_room as gr  # noqa: E402

ROOT = os.path.dirname(HERE)
SHIFT = 2                       # all shipped meshes are quarter-unit quantised


class Mesh:
    def __init__(self, name, verts, edges, shift=SHIFT, radius=None):
        self.name = name
        self.verts = verts          # [(x, y, z)] signed ints, units of 2^-shift
        self.edges = edges          # [(a, b)]
        self.shift = shift
        if radius is None:
            import math
            r = max(math.hypot(x, z) for (x, _, z) in verts) / float(1 << shift)
            radius = int(math.ceil(r)) + 1
        self.radius = radius        # world units (horizontal extent incl. rotation), view cull


def quantise(v, shift=SHIFT):
    return int(round(v * (1 << shift)))


def load_items():
    d = json.load(open(os.path.join(ROOT, "editor", "doom64.json")))
    out = {}
    for name, m in d["items"].items():
        verts = [(quantise(v["x"]), quantise(v["y"]), quantise(v["z"])) for v in m["verts"]]
        edges = [(int(a), int(b)) for a, b in m["lines"]]
        out[name] = Mesh(name, verts, edges)
    out["fireball"] = fireball_mesh()
    return out


def fireball_mesh():
    """Synthetic octahedron (half a cell across) for imp / baron fireballs."""
    verts = [(2, 0, 0), (-2, 0, 0), (0, 2, 0), (0, -2, 0), (0, 0, 2), (0, 0, -2)]
    edges = [(a, b) for a in (0, 1) for b in (2, 3, 4, 5)] + [(a, b) for a in (2, 3) for b in (4, 5)]
    return Mesh("fireball", verts, edges)


ENEMY_FILES = [("poss", "Possessed"), ("baron", "Baron"), ("pinky", "Pinky"), ("imp", "Imp")]


def load_enemies():
    """{key: dict(edges, frames=[[(x,y,z)]], clips={name: (start, len)}, hp, block_r, weapon_vert)}"""
    out = {}
    for key, _ in ENEMY_FILES:
        e = json.load(open(os.path.join(ROOT, "editor", "enemies", key + ".json")))
        frames = [[(quantise(v["x"]), quantise(v["y"]), quantise(v["z"])) for v in f] for f in e["frames"]]
        out[key] = dict(
            edges=[(int(a), int(b)) for a, b in e["lines"]],
            frames=frames,
            clips={c["name"]: (int(c["start"]), int(c["len"])) for c in e["clips"]},
            hp=int(e.get("hp", 0)), block_r=int(e.get("blockR", 1)), weapon_vert=int(e.get("weaponVert", 0)),
        )
    return out


def mulsh(l, t, shift):
    """Signed byte * signed trig byte -> 8.8: sign-magnitude, >> (shift - 1)."""
    mag = (abs(l) * abs(t)) >> (shift - 1)
    return -mag if (l < 0) != (t < 0) else mag


def entity_view(cam_x, cam_z, cam_y, cam_yaw, ox, oz, oy, obj_yaw, mesh_verts, shift):
    """Origin in view space and the per-vertex view coordinates [(X, Y, Z)]."""
    sn, cs = gr.sin_of(cam_yaw), gr.cos_of(cam_yaw)
    dx, dz = ox - cam_x, oz - cam_z
    X0 = gr.smul16(dx, cs) - gr.smul16(dz, sn)
    Z0 = gr.smul16(dx, sn) + gr.smul16(dz, cs)
    Y0 = oy - cam_y
    psi = (cam_yaw + obj_yaw) & 255
    sn2, cs2 = gr.sin_of(psi), gr.cos_of(psi)
    out = []
    for (lx, ly, lz) in mesh_verts:
        X = X0 + mulsh(lx, cs2, shift) - mulsh(lz, sn2, shift)
        Z = Z0 + mulsh(lx, sn2, shift) + mulsh(lz, cs2, shift)
        Y = Y0 + (ly << (8 - shift))
        out.append((X, Y, Z))
    return (X0, Y0, Z0), out


def culled(Z0, X0, radius):
    """Cheap view cull on the origin: wholly behind the near plane or outside the 45 degree cone."""
    zt = Z0 + (radius << 8)
    if zt < gr.ZCLIP:
        return True
    return abs(X0) > zt


def entity_segments(cam_x, cam_z, cam_y, cam_yaw, ox, oz, oy, obj_yaw, mesh_verts, edges, shift, radius):
    (X0, _, Z0), vv = entity_view(cam_x, cam_z, cam_y, cam_yaw, ox, oz, oy, obj_yaw, mesh_verts, shift)
    if culled(Z0, X0, radius):
        return []
    verts = [gr.project_vert(X, Y, Z) for (X, Y, Z) in vv]
    return gr.edge_segments(verts, edges)


def entity_pixels(*args):
    import gbc_genlines as gl
    fb = set()
    for seg in entity_segments(*args):
        gl.ref_line(fb, *seg[1:])
    return fb
