"""Doom MD2/MD3 importer. Manual reimport of the live monsters."""

from __future__ import annotations

import math
import struct
from pathlib import Path

# MD2/MD3 are Z-up, X right, Y forward.
# 0.75 keeps the baron under the stick's ±127.
DOOM_IMPORT_SCALE = 0.75
DOOM_DIR = Path(__file__).resolve().parents[1] / "ref" / "doom" / "monsters"
MAX_OVERLAY_TRIS = 600

# Per-part source frame index. Parts stay in this order so joint indices hold.
# Possessed shoot is fire01..03 (body 8..10); MODELDEF only tags the last one.
# Pain/death head frames are the MODELDEF indices (the head mesh is shorter).
DOOM_PARTS = {
    "Possessed": [
        "possessed/doom_body.md2",
        "possessed/head_fodder.md2",
        "possessed/weapon_rifle.md2",
    ],
    "Imp": ["imp/Imp.md2", "imp/Imp-Hand.md2"],
    "Pinky": ["pinky/Pinky.md3"],
    "Baron": ["baron/bruiser_body.md2", "baron/bruiser_head.md2"],
}
DOOM_CLIPS = {
    "Possessed": [
        ("stand", [(0, 0, 0)]),
        ("walk", [(0, 0, 0), (2, 2, 2), (4, 4, 4), (6, 6, 6)]),
        ("pain", [(54, 22, 0), (55, 22, 0), (56, 22, 0)]),
        ("missile", [(8, 8, 8), (9, 9, 9), (10, 10, 10)]),
        ("death", [(57, 26, 0), (58, 26, 0), (60, 28, 0), (62, 30, 0), (64, 32, 0)]),
    ],
    "Imp": [
        ("stand", [(1, 1)]),
        ("walk", [(1, 1), (3, 3), (5, 5), (7, 7)]),
        ("pain", [(23, 23)]),
        ("melee", [(10, 10), (13, 13)]),
        ("missile", [(10, 10), (12, 12)]),
        ("death", [(23, 23)]),
    ],
    "Pinky": [
        ("stand", [(0,)]),
        ("walk", [(0,), (4,), (8,), (12,)]),
        ("pain", [(24,)]),
        ("melee", [(20,), (22,)]),
        ("death", [(28,), (35,), (36,), (37,), (40,), (41,), (42,), (46,)]),
    ],
    "Baron": [
        ("stand", [(2, 2)]),
        ("walk", [(2, 2), (4, 4), (6, 6), (8, 8)]),
        ("pain", [(18, 18)]),
        ("melee", [(13, 13), (14, 14)]),
        ("missile", [(13, 13), (14, 14)]),
        ("death", [(18, 18)]),
    ],
}

def js_round(n: float) -> int:
    """Math.round: halves go toward +inf."""
    return math.floor(n + 0.5)


def _quake_xyz(x: float, y: float, z: float) -> tuple[float, float, float]:
    s = DOOM_IMPORT_SCALE
    return (y * s, -x * s, z * s)


def _stride_tris(tris: list[list[int]]) -> list[list[int]]:
    n = len(tris)
    if n <= MAX_OVERLAY_TRIS:
        return tris
    step = (n + MAX_OVERLAY_TRIS - 1) // MAX_OVERLAY_TRIS
    return tris[::step]


def _parse_md2(data: bytes) -> dict:
    if data[:4] != b"IDP2":
        raise SystemExit("Not an IDP2 MD2")
    hdr = struct.unpack_from("<17i", data, 0)
    version, fsize, nverts, ntris, nframes, ofs_tris, ofs_frames = (
        hdr[1], hdr[4], hdr[6], hdr[8], hdr[10], hdr[13], hdr[14]
    )
    if version != 8 or nverts <= 0 or nframes <= 0 or fsize < 40 + nverts * 4:
        raise SystemExit("MD2 header invalid")
    tris = []
    o = ofs_tris
    for _ in range(ntris):
        a, b, c = struct.unpack_from("<3H", data, o)
        tris.append([a, b, c])
        o += 12
    frames = []
    for fi in range(nframes):
        base = ofs_frames + fi * fsize
        sx, sy, sz, tx, ty, tz = struct.unpack_from("<6f", data, base)
        xyz = []
        vo = base + 40
        for _ in range(nverts):
            vx, vy, vz = data[vo], data[vo + 1], data[vo + 2]
            vo += 4
            xyz.extend(_quake_xyz(vx * sx + tx, vy * sy + ty, vz * sz + tz))
        frames.append(xyz)
    return {"numVerts": nverts, "frames": frames, "tris": tris}


def _parse_md3(data: bytes) -> dict:
    if data[:4] != b"IDP3":
        raise SystemExit("Not an IDP3 MD3")
    nframes = struct.unpack_from("<i", data, 76)[0]
    ofs_surf = struct.unpack_from("<i", data, 100)[0]
    # surface: ident+name+flags, then numFrames, numShaders, numVerts, numTris
    nfr, _nsh, nverts, ntris = struct.unpack_from("<4i", data, ofs_surf + 72)
    ofs_tri = struct.unpack_from("<i", data, ofs_surf + 88)[0]
    ofs_xyz = struct.unpack_from("<i", data, ofs_surf + 100)[0]
    if nfr != nframes or nverts <= 0 or nframes <= 0:
        raise SystemExit("MD3 surface invalid")
    tris = []
    o = ofs_surf + ofs_tri
    for _ in range(ntris):
        a, b, c = struct.unpack_from("<3I", data, o)
        tris.append([a, b, c])
        o += 12
    frames = []
    base = ofs_surf + ofs_xyz
    for fi in range(nframes):
        xyz = []
        vo = base + fi * nverts * 8
        for _ in range(nverts):
            x, y, z, _n = struct.unpack_from("<hhhH", data, vo)
            vo += 8
            xyz.extend(_quake_xyz(x / 64.0, y / 64.0, z / 64.0))
        frames.append(xyz)
    return {"numVerts": nverts, "frames": frames, "tris": tris}


def _load_part(rel: str) -> dict:
    path = DOOM_DIR / rel
    data = path.read_bytes()
    if rel.lower().endswith(".md3"):
        return _parse_md3(data)
    return _parse_md2(data)


def load_doom_enemy(name: str) -> dict:
    parts = [_load_part(rel) for rel in DOOM_PARTS[name]]
    clips_spec = DOOM_CLIPS[name]
    frames = []
    clips = []
    start = 0
    bases = []
    acc = 0
    for part in parts:
        bases.append(acc)
        acc += part["numVerts"]
    tris: list[list[int]] = []
    for part, base in zip(parts, bases):
        for tri in part["tris"]:
            tris.append([tri[0] + base, tri[1] + base, tri[2] + base])
    for clip_name, samples in clips_spec:
        clip_frames = []
        for sample in samples:
            if len(sample) != len(parts):
                raise SystemExit(f"{name} {clip_name}: part count")
            xyz: list[float] = []
            for part, fi in zip(parts, sample):
                if fi < 0 or fi >= len(part["frames"]):
                    raise SystemExit(f"{name} {clip_name}: frame {fi} out of range")
                xyz.extend(part["frames"][fi])
            idx = len(frames)
            frames.append({"name": f"{clip_name}{len(clip_frames)}", "xyz": xyz})
            clip_frames.append({"name": frames[-1]["name"], "index": idx})
        clips.append({"name": clip_name, "frames": clip_frames, "start": start, "len": len(clip_frames)})
        start += len(clip_frames)
    weapon_base = bases[-1] if name == "Possessed" else 0
    return {
        "numVerts": acc,
        "scale": (1.0, 1.0, 1.0),
        "origin": (0.0, 0.0, 0.0),
        "floatFrames": True,
        "frames": frames,
        "clips": clips,
        "tris": _stride_tris(tris),
        "weaponBase": weapon_base,
    }


def seed_joint_verts(verts: list[dict], weapon_base: int) -> list[list[int]]:
    """One mesh vert per stick joint, from a stand-frame bbox."""
    n = len(verts)
    ys = [p["y"] for p in verts]
    y0, y1 = min(ys), max(ys)
    span = max(y1 - y0, 1e-3)

    def band(a: float, b: float) -> list[int]:
        lo, hi = y0 + span * a, y0 + span * b
        return [i for i in range(n) if lo <= verts[i]["y"] <= hi]

    head = max(range(n), key=lambda i: (verts[i]["y"], -abs(verts[i]["x"])))
    low = [i for i in range(n) if verts[i]["y"] <= y0 + span * 0.12]
    if len(low) < 2:
        low = sorted(range(n), key=lambda i: verts[i]["y"])[:8]
    ankle_l = min(low, key=lambda i: verts[i]["x"])
    ankle_r = max(low, key=lambda i: verts[i]["x"])
    midlow = band(0.18, 0.42) or low
    knee_l = min(midlow, key=lambda i: verts[i]["x"])
    knee_r = max(midlow, key=lambda i: verts[i]["x"])
    hips = band(0.42, 0.62) or band(0.30, 0.70)
    hip_l = min(hips, key=lambda i: verts[i]["x"])
    hip_r = max(hips, key=lambda i: verts[i]["x"])
    neck_band = band(0.72, 0.88) or [head]
    neck = min(neck_band, key=lambda i: abs(verts[i]["x"]))
    arms = band(0.45, 0.82) or band(0.30, 0.90)
    wrist_l = min(arms, key=lambda i: verts[i]["x"])
    wrist_r = max(arms, key=lambda i: verts[i]["x"])

    def between(a: int, b: int) -> int:
        mx = (verts[a]["x"] + verts[b]["x"]) * 0.5
        my = (verts[a]["y"] + verts[b]["y"]) * 0.5
        pool = arms or hips
        return min(pool, key=lambda i: (verts[i]["x"] - mx) ** 2 + (verts[i]["y"] - my) ** 2)

    elbow_l = between(hip_l, wrist_l)
    elbow_r = between(hip_r, wrist_r)
    if 0 < weapon_base < n:
        weapon = max(range(weapon_base, n), key=lambda i: verts[i]["z"])
    else:
        chest = band(0.50, 0.75) or [neck]
        weapon = max(chest, key=lambda i: verts[i]["z"])
    order = [
        hip_l, hip_r, neck, head, elbow_l, wrist_l, elbow_r, wrist_r,
        knee_l, ankle_l, knee_r, ankle_r, weapon,
    ]
    return [[i] for i in order]
