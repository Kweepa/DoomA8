"""Doom MDL + PAK readers. Pose decode matches editor/js/mdl.js."""

from __future__ import annotations

import math
import re
import struct
from pathlib import Path

IDPO = 0x4F504449
ALIAS_VERSION = 6
ALIAS_SINGLE = 0
HULL_FLOOR = 24
POSE_SCALE = 0.7

ENEMY_MDL_PATHS = {
    "Scrag": "progs/wizard.mdl",
    "Ogre": "progs/ogre.mdl",
    "Shambler": "progs/shambler.mdl",
    "Chthon": "progs/boss.mdl",
    "Demon": "progs/demon.mdl",
}

# MD2/MD3 are Z-up, X right, Y forward. Quake MDL (what editor_verts expects)
# is X forward, Y left, Z up. 0.75 keeps the baron under the stick's ±127.
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

_EXTRA_PAIN_DEATH = re.compile(r"^pain[b-z]|^death[b-z]|^deathc$|^bdeath$")


def js_round(n: float) -> int:
    """Math.round: halves go toward +inf."""
    return math.floor(n + 0.5)


def clip_name(frame_name: str) -> str:
    key = re.sub(r"\d+$", "", frame_name)
    return key or frame_name


def parse_pak(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    if len(data) < 12:
        raise SystemExit(f"PAK too small: {path}")
    magic, dir_ofs, dir_size = struct.unpack_from("<4sII", data, 0)
    if magic != b"PACK":
        raise SystemExit(f"not a PACK: {path}")
    if dir_ofs + dir_size > len(data):
        raise SystemExit(f"PAK directory out of range: {path}")
    files: dict[str, bytes] = {}
    for i in range(dir_size // 64):
        off = dir_ofs + i * 64
        raw = data[off : off + 56].split(b"\x00", 1)[0]
        name = raw.decode("latin1").replace("\\", "/").lower()
        foff, fsz = struct.unpack_from("<II", data, off + 56)
        if foff + fsz > len(data):
            continue
        files[name] = data[foff : foff + fsz]
    return files


def _find_pak(root: Path, stem: str) -> Path | None:
    if not root.is_dir():
        return None
    for p in root.iterdir():
        if p.is_file() and p.name.lower() == stem:
            return p
    return None


def load_id1(root: Path) -> dict[str, bytes]:
    """pak0 then pak1. Later files override."""
    pak0 = _find_pak(root, "pak0.pak")
    if pak0 is None:
        raise SystemExit(f"missing {root / 'PAK0.PAK'}")
    files = parse_pak(pak0)
    pak1 = _find_pak(root, "pak1.pak")
    if pak1 is not None:
        files.update(parse_pak(pak1))
    return files


class _R:
    def __init__(self, data: bytes):
        self.data = data
        self.o = 0

    def need(self, n: int, what: str) -> None:
        if self.o + n > len(self.data):
            raise SystemExit(f"MDL truncated ({what})")

    def i32(self) -> int:
        self.need(4, "i32")
        v = struct.unpack_from("<i", self.data, self.o)[0]
        self.o += 4
        return v

    def f32(self) -> float:
        self.need(4, "f32")
        v = struct.unpack_from("<f", self.data, self.o)[0]
        self.o += 4
        return v

    def vec3(self) -> tuple[float, float, float]:
        return (self.f32(), self.f32(), self.f32())

    def u8(self) -> int:
        self.need(1, "u8")
        v = self.data[self.o]
        self.o += 1
        return v

    def skip(self, n: int) -> None:
        self.need(n, "skip")
        self.o += n

    def name16(self) -> str:
        self.need(16, "name")
        raw = self.data[self.o : self.o + 16].split(b"\x00", 1)[0]
        self.o += 16
        return raw.decode("latin1")


def _skip_skins(r: _R, num_skins: int, skin_w: int, skin_h: int) -> None:
    skin_size = skin_w * skin_h
    if skin_size < 0 or skin_size > 2_000_000:
        raise SystemExit("MDL skin size invalid")
    for _ in range(num_skins):
        typ = r.i32()
        if typ == ALIAS_SINGLE:
            r.skip(skin_size)
        else:
            n = r.i32()
            if n < 0 or n > 256:
                raise SystemExit("MDL skin group too large")
            r.skip(n * 4 + n * skin_size)


def _read_simple_frame(r: _R, num_verts: int) -> dict:
    r.need(8 + 16 + num_verts * 4, "frame")
    r.skip(8)
    name = r.name16()
    verts = bytearray(num_verts * 3)
    for i in range(num_verts):
        verts[i * 3] = r.u8()
        verts[i * 3 + 1] = r.u8()
        verts[i * 3 + 2] = r.u8()
        r.u8()
    return {"name": name, "verts": bytes(verts)}


def parse_mdl(data: bytes) -> dict:
    r = _R(data)
    r.need(84, "header")
    ident = r.i32() & 0xFFFFFFFF
    if ident != IDPO:
        raise SystemExit("Not an IDPO MDL")
    version = r.i32()
    if version != ALIAS_VERSION:
        raise SystemExit(f"MDL version {version}, expected 6")
    scale = r.vec3()
    origin = r.vec3()
    r.f32()
    r.vec3()
    num_skins = r.i32()
    skin_w = r.i32()
    skin_h = r.i32()
    num_verts = r.i32()
    num_tris = r.i32()
    num_frames = r.i32()
    r.i32()
    r.i32()
    r.f32()
    if num_verts <= 0 or num_verts > 10000 or num_tris <= 0 or num_tris > 20000 or num_frames <= 0:
        raise SystemExit("MDL has no geometry")
    _skip_skins(r, num_skins, skin_w, skin_h)
    r.skip(num_verts * 12)
    r.need(num_tris * 16, "tris")
    r.skip(num_tris * 16)
    frames = []
    for _ in range(num_frames):
        typ = r.i32()
        if typ == ALIAS_SINGLE:
            frames.append(_read_simple_frame(r, num_verts))
        else:
            n = r.i32()
            if n < 0 or n > 256:
                raise SystemExit("MDL frame group too large")
            r.skip(8 + n * 4)
            for _j in range(n):
                frames.append(_read_simple_frame(r, num_verts))
    clips = []
    by_key: dict[str, dict] = {}
    for i, fr in enumerate(frames):
        key = clip_name(fr["name"])
        clip = by_key.get(key)
        if clip is None:
            clip = {"name": key, "frames": []}
            by_key[key] = clip
            clips.append(clip)
        clip["frames"].append({"name": fr["name"], "index": i})
    return {
        "numVerts": num_verts,
        "scale": scale,
        "origin": origin,
        "frames": frames,
        "clips": clips,
    }


def select_mdl_clips(mdl: dict, names: list[str] | None) -> list[dict]:
    clips = mdl.get("clips") or []
    if not clips:
        return []
    if names is None:
        return [c for c in clips if not _EXTRA_PAIN_DEATH.search(c["name"])]
    want = set(names)
    return [c for c in clips if c["name"] in want]


def editor_verts(mdl: dict, frame_index: int, scale: float = POSE_SCALE) -> list[dict[str, float]]:
    fr = mdl["frames"][frame_index]
    s = scale if math.isfinite(scale) else POSE_SCALE
    s = max(0.1, min(2.0, s))
    out = []
    xyz = fr.get("xyz")
    if xyz is not None:
        for i in range(mdl["numVerts"]):
            qx = xyz[i * 3]
            qy = xyz[i * 3 + 1]
            qz = xyz[i * 3 + 2]
            out.append({"x": -qy * s, "y": (qz + HULL_FLOOR) * s, "z": qx * s})
        return out
    sx, sy, sz = mdl["scale"]
    ox, oy, oz = mdl["origin"]
    packed = fr["verts"]
    for i in range(mdl["numVerts"]):
        qx = packed[i * 3] * sx + ox
        qy = packed[i * 3 + 1] * sy + oy
        qz = packed[i * 3 + 2] * sz + oz
        # Doom +X forward / +Z up → editor +Z forward / +Y up.
        x = -qy
        y = qz
        z = qx
        out.append({"x": x * s, "y": (y + HULL_FLOOR) * s, "z": z * s})
    return out


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


def load_enemy_mdls(id1: Path) -> dict[str, dict]:
    lumps = load_id1(id1)
    models: dict[str, dict] = {}
    for enemy in ("Possessed", "Baron", "Pinky", "Scrag", "Ogre", "Shambler", "Chthon", "Imp", "Demon"):
        if enemy in DOOM_PARTS:
            models[enemy] = load_doom_enemy(enemy)
            continue
        path = ENEMY_MDL_PATHS[enemy]
        blob = lumps.get(path.lower())
        if blob is None:
            raise SystemExit(f"{enemy}: {path} missing from {id1}")
        models[enemy] = parse_mdl(blob)
    return models
