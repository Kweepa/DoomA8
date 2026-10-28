#!/usr/bin/env python3
"""Export per-type pose PRGs + slim enemy_data.asm metadata."""

from __future__ import annotations

import json
import random
import re
import struct
from copy import deepcopy
from pathlib import Path

from doommdl import js_round
from gensounds import ENEMY_CUES

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "doom64.json"
OUT = ROOT / "src" / "enemy_data.asm"
BLOB_OUT = ROOT / "src" / "enemy_data_blob.asm"
SIZES_OUT = ROOT / "src" / "enemy_sizes.asm"
ENEMY_DIR = ROOT / "enemies"

NVERTS = 13
SKEL_MAX_VERTS = 48
SKEL_MAX_EDGES = 64
MESH_BATCH_VERTS = 16  # mesh.asm MESH_MAX_VERTS
MESH_BATCH_EDGES = 32
TYPES = ["Possessed", "Baron", "Pinky", "Imp"]
DOS_NAME = ["poss", "baron", "pinky", "imp"]
ENEMY_POSE_MAX = 7680
ENEMY_DATA_BASE = 0x0701  # mem.asm asserts its ENEMY_DATA_BASE == $0701
META_ROW = 41  # mem.asm META_ROW; prepended to every .pose
PAIN_MAX = 4
PAIN_KEY = re.compile(r"^pain[a-z]?$")
DEATH_KEY = re.compile(r"^(bdeath|death[a-z]?)$")
# Clip-local fire frames (matches the pose-row fire byte).
FIRE_FRAME = [1, 1, 1, 1]
# Mid-distance stick LOD threshold (CAM_ZH).
DEFAULT_LOD_Z = {
    "Possessed": 4,
    "Baron": 8,
    "Pinky": 4,
    "Imp": 4,
}

# Game byte (Doom health / 5). editor/doom64.json "hp" overrides this.
DEFAULT_HP = {
    "Possessed": 4,
    "Baron": 200,
    "Pinky": 30,
    "Imp": 12,
}

# Resident only while the type's bank is loaded. Two slots, not N columns.
RANGE = {
    "Possessed": 30,
    "Baron": 12,
    "Pinky": 4,
    "Imp": 12,
}
# Used when the enemy record has no painChance. Editor value wins.
DEFAULT_PAIN_CHANCE = 0x80
PAIN_CHANCE = {"Imp": 0xFF, "Pinky": 0xFF, "Baron": 0}
ENEMY_CLASS = {}

# Single roles: (clip_name, len_override|None). Attack: list of candidate names
# present after exportClips — all matching clips become variants (like pain/death).
ROLE_CLIPS = {
    "Possessed": {
        "stand": ("stand", None),
        "alert": ("stand", None),
        "run": ("walk", None),
        "walk": ("walk", None),
        "attack": ["missile"],
    },
    "Baron": {
        "stand": ("stand", None),
        "alert": ("stand", None),
        "run": ("walk", None),
        "walk": ("walk", None),
        "attack": ["attack"],
    },
    "Pinky": {
        "stand": ("stand", None),
        "alert": ("stand", None),
        "run": ("walk", None),
        "walk": ("walk", None),
        "attack": ["melee"],
    },
    "Imp": {
        "stand": ("stand", None),
        "alert": ("stand", None),
        "run": ("walk", None),
        "walk": ("walk", None),
        "attack": ["attack"],
    },
}


def clip_key(name: str) -> str:
    return str(name).rstrip("_").lower()


def clip_sound_stem(raw) -> str:
    stem = str(raw or "").strip().upper()
    if stem.startswith("SOUND_"):
        stem = stem[6:]
    return stem


def clip_with_sound(dst: dict, src: dict) -> dict:
    stem = clip_sound_stem(src.get("sound"))
    if not stem:
        return dst
    length = max(1, int(dst["len"]))
    frame = int(src.get("soundFrame") or 0)
    if frame < 0:
        frame = 0
    if frame >= length:
        frame = length - 1
    dst["sound"] = stem
    dst["soundFrame"] = frame
    return dst


CUE_ORDER = ["sight", "wince", "melee", "shoot", "death"]  # fixed: CUE_* indices in enemy.asm
CUE_REQUIRED = ("sight", "wince", "death")
CUE_NONE = 0xFF


def cue_ident(path) -> str:
    """sound/dog/ddeath.wav -> DOG_DDEATH (same ident gensounds.py exports)."""
    rest = str(path or "").strip().replace("\\", "/")
    if rest.lower().startswith("sound/"):
        rest = rest[6:]
    if rest.lower().endswith(".wav"):
        rest = rest[:-4]
    return re.sub(r"[^A-Za-z0-9]+", "_", rest).strip("_").upper()


def apply_tool_cues(enemy: dict) -> None:
    """Shipped types play the fixed Doom cues. JSON cue paths are not consulted."""
    mapped = ENEMY_CUES.get(enemy.get("name"))
    if mapped:
        enemy["cues"] = dict(mapped)


def pack_cues(enemy: dict, ids: dict[str, int]) -> bytes:
    """Five sound ids [sight, wince, melee, shoot, death]; $FF = none ($00 is a real sound)."""
    name = enemy.get("name", "?")
    cues = enemy.get("cues") or {}
    for k in cues:
        if k not in CUE_ORDER:
            raise SystemExit(f"{name}: unknown cue {k!r}")
    out = bytearray()
    for cue in CUE_ORDER:
        path = cues.get(cue)
        if not path:
            if cue in CUE_REQUIRED:
                raise SystemExit(f"{name}: required cue '{cue}' is not set")
            out.append(CUE_NONE)
            continue
        ident = cue_ident(path)
        if ident not in ids:
            if cue in CUE_REQUIRED:
                raise SystemExit(f"{name} cue {cue}: SOUND_{ident} not in bank (run gensounds.py first)")
            out.append(CUE_NONE)
            continue
        sid = ids[ident]
        if sid >= CUE_NONE:
            raise SystemExit(f"{name} cue {cue}: sound id {sid} overflow")
        out.append(sid)
    return bytes(out)


def resolve_clip_sound(enemy: dict, clip: dict) -> str | None:
    """Bank ident for a clip sound. melee/shoot names the cue. A legacy stem must match one."""
    stem = clip_sound_stem(clip.get("sound"))
    if not stem:
        return None
    name = enemy.get("name", "?")
    clip_name = clip.get("name", "?")
    cues = enemy.get("cues") or {}
    key = stem.lower()
    if key in ("melee", "shoot"):
        path = cues.get(key)
        if not path:
            raise SystemExit(f"{name} clip {clip_name}: {key} cue has no sound")
        return cue_ident(path)
    for cue in ("melee", "shoot"):
        path = cues.get(cue)
        if path and cue_ident(path) == stem:
            return stem
    raise SystemExit(
        f"{name} clip {clip_name}: {stem} is not this enemy's melee or shoot cue "
        f"(sight/wince/death play generically)"
    )


def pack_clip_events(enemy: dict, ids: dict[str, int]) -> bytes:
    """One {logical_frame, id} per clip carrying a melee/shoot sound. logical = clip.start + soundFrame."""
    name = enemy.get("name", "?")
    out: list[int] = []
    seen: set[tuple[int, int]] = set()
    for c in enemy.get("clips") or []:
        stem = resolve_clip_sound(enemy, c)
        if not stem:
            continue
        if stem not in ids:
            raise SystemExit(f"{name} clip {c.get('name')}: SOUND_{stem} not in bank (run gensounds.py first)")
        start = int(c["start"])
        length = max(1, int(c["len"]))
        frame = int(c.get("soundFrame") or 0)
        if frame < 0:
            frame = 0
        if frame >= length:
            frame = length - 1
        frames = [start + frame]
        sid = ids[stem]
        for logical in frames:
            if logical > 255 or sid > 255:
                raise SystemExit(f"{name} clip {c.get('name')}: event byte overflow")
            key = (logical, sid)
            if key in seen:
                continue
            seen.add(key)
            out.extend([logical, sid])
    n = len(out) // 2
    if n > 255:
        raise SystemExit(f"{name}: {n} clip events > 255")
    return bytes([n, *out])


def find_clip(enemy: dict, *names: str) -> tuple[int, int] | None:
    clips = enemy.get("clips") or []
    for want in names:
        for c in clips:
            if clip_key(c.get("name", "")) == want:
                return int(c["start"]), int(c["len"])
    return None


def find_role(enemy: dict, role: str) -> tuple[int, int] | None:
    """Single-window roles only (stand/alert/run/walk). Attack uses find_attack_clips."""
    if role == "attack":
        return None
    spec = ROLE_CLIPS.get(enemy["name"], {}).get(role)
    if spec is None or not isinstance(spec, tuple):
        return None
    name, len_override = spec
    found = find_clip(enemy, name)
    if found is None:
        return None
    start, length = found
    if len_override is not None:
        length = min(length, int(len_override))
    return start, length


def require_role(enemy: dict, role: str) -> tuple[int, int]:
    found = find_role(enemy, role)
    if found is not None:
        return found
    found = find_clip(enemy, "stand", "walk", "hover")
    if found is not None:
        return found
    clips = enemy.get("clips") or []
    if clips:
        return int(clips[0]["start"]), max(1, int(clips[0]["len"]))
    raise SystemExit(f"{enemy['name']}: no {role} clip (and no fallback)")


def find_attack_clips(enemy: dict) -> list[tuple[int, int]]:
    """All ROLE attack candidate names present in clips (export order), up to PAIN_MAX."""
    names = ROLE_CLIPS.get(enemy["name"], {}).get("attack") or []
    want = {clip_key(n) for n in names if isinstance(n, str)}
    out: list[tuple[int, int]] = []
    for c in enemy.get("clips") or []:
        if clip_key(c.get("name", "")) not in want:
            continue
        out.append((int(c["start"]), int(c["len"])))
        if len(out) >= PAIN_MAX:
            break
    if not out:
        stand = find_clip(enemy, "stand", "walk", "hover")
        if stand is None:
            clips = enemy.get("clips") or []
            if not clips:
                raise SystemExit(f"{enemy['name']}: no attack clip")
            out.append((int(clips[0]["start"]), 1))
        else:
            out.append((stand[0], 1))
    return out


def apply_export_clips(enemy: dict) -> None:
    """Keep only exportClips, remapping stick frames/starts. Missing list → all clips."""
    names = enemy.get("exportClips")
    if not isinstance(names, list):
        return
    clips = enemy.get("clips") or []
    frames = enemy.get("frames") or []
    by_name = {c.get("name", ""): c for c in clips}
    by_key = {clip_key(c.get("name", "")): c for c in clips}
    new_frames: list = []
    new_clips: list[dict] = []
    start = 0
    for name in names:
        c = by_name.get(name) or by_key.get(clip_key(name))
        if c is None:
            continue
        a, n = int(c["start"]), int(c["len"])
        sl = frames[a : a + n]
        if not sl:
            continue
        new_clips.append(clip_with_sound({"name": c.get("name", name), "start": start, "len": len(sl)}, c))
        new_frames.extend(sl)
        start += len(sl)
    enemy["frames"] = new_frames
    enemy["clips"] = new_clips


def variant_key(what: str) -> re.Pattern:
    return PAIN_KEY if what == "pain" else DEATH_KEY


def find_variant_clips(enemy: dict, key_re: re.Pattern, what: str) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for c in enemy.get("clips") or []:
        if key_re.match(clip_key(c.get("name", ""))):
            out.append((int(c["start"]), int(c["len"])))
            if len(out) >= PAIN_MAX:
                break
    if not out:
        stand = find_clip(enemy, "stand", "walk", "hover")
        if stand is None:
            clips = enemy.get("clips") or []
            if not clips:
                raise SystemExit(f"{enemy['name']}: no {what} clip")
            out.append((int(clips[0]["start"]), 1))
        else:
            out.append((stand[0], 1))
    return out


def pad_variants(clips: list[tuple[int, int]]) -> tuple[int, list[int], list[int]]:
    starts: list[int] = []
    lens: list[int] = []
    for i in range(PAIN_MAX):
        if i < len(clips):
            starts.append(clips[i][0])
            lens.append(clips[i][1])
        else:
            starts.append(0)
            lens.append(0)
    return len(clips), starts, lens


def build_meta_row(name: str, enemy: dict, nframes: int, n_stored: int, lod: int) -> bytes:
    """41-byte pose prefix. Offsets match copy_meta_row in loader.asm."""
    row = bytearray(META_ROW)
    o = 0
    for role in ("stand", "alert", "run", "walk"):
        start, length = require_role(enemy, role)
        if start + length > nframes:
            length = max(1, nframes - start)
        row[o] = start & 0xFF
        row[o + 1] = length & 0xFF
        o += 2
    atk: list[tuple[int, int]] = []
    for s, ln in find_attack_clips(enemy):
        if s >= nframes or ln <= 0:
            continue
        atk.append((s, min(ln, nframes - s)))
    if not atk:
        atk = [(0, 1)]
    n, starts, lens = pad_variants(atk)
    row[o] = n
    o += 1
    for b in starts + lens:
        row[o] = b & 0xFF
        o += 1
    for what in ("pain", "death"):
        n, starts, lens = pad_variants(find_variant_clips(enemy, variant_key(what), what))
        row[o] = n
        o += 1
        for b in starts + lens:
            row[o] = b & 0xFF
            o += 1
    row[o] = RANGE[name]
    o += 1
    row[o] = enemy_pain_chance_byte(enemy, name)
    o += 1
    row[o] = FIRE_FRAME[TYPES.index(name)] & 0xFF
    o += 1
    row[o] = ENEMY_CLASS.get(name, 0)
    o += 1
    row[o] = lod & 0xFF
    o += 1
    row[o] = n_stored & 0xFF
    o += 1
    if o != META_ROW:
        raise SystemExit(f"{name}: meta row wrote {o} bytes, expected {META_ROW}")
    return bytes(row)


def s8(n: int) -> int:
    n = int(n)
    if n < -128 or n > 127:
        raise ValueError(f"vert coord out of signed byte range: {n}")
    return n & 0xFF


DEFAULT_EDGES = [
    [0, 1],
    [1, 2],
    [2, 0],
    [2, 3],
    [2, 4],
    [4, 5],
    [2, 6],
    [6, 7],
    [0, 8],
    [8, 9],
    [1, 10],
    [10, 11],
    [7, 12],
]


def enemy_nv(enemy: dict) -> int:
    if not enemy.get("customSkeleton"):
        return NVERTS
    joints = (enemy.get("mdlRig") or {}).get("jointVerts") or []
    nv = len(joints) if joints else int(enemy.get("verts") or 0)
    if not 0 <= nv <= SKEL_MAX_VERTS:
        raise SystemExit(f"{enemy['name']}: custom skeleton vert count {nv} not in 0..{SKEL_MAX_VERTS}")
    return nv


SKEL_PFX = 7  # size.w, nv, ne, entry.w (entry patched by genaibanks), shift
SKEL_SHIFT_MAX = 2


def shift_round(v: int, shift: int) -> int:
    return (int(v) + ((1 << shift) >> 1)) >> shift


SPRITE_Q = 4


def enemy_fine(enemy: dict) -> bool:
    """Hand-posed sticks store quarter-units. Packed byte is round(v*4)."""
    for c in enemy.get("clips") or []:
        sp = c.get("sprites")
        if isinstance(sp, list) and sp:
            return True
    return False


def pose_int(v, fine: bool) -> int:
    n = js_round(float(v) * SPRITE_Q) if fine else js_round(float(v))
    return int(n)


def pick_skel_shift(enemy: dict, frames: list) -> int:
    """Smallest shift so every coord >> shift fits a signed byte. Never clamps."""
    coords = [int(v[a]) for fr in frames for v in fr for a in ("x", "y", "z")]
    for shift in range(SKEL_SHIFT_MAX + 1):
        if all(-128 <= shift_round(c, shift) <= 127 for c in coords):
            return shift
    peak = max((abs(c) for c in coords), default=0)
    raise SystemExit(
        f"{enemy['name']}: custom skeleton coord {peak} needs shift > {SKEL_SHIFT_MAX}; "
        "lower the MDL scale in the editor"
    )


def batch_cost(order: list[list[int]]) -> tuple[int, int]:
    """(batches, vert slots) as baked_batches packs them: a batch closes at the first misfit."""
    batches = slots = 0
    i = 0
    while i < len(order):
        verts: set[int] = set()
        n = 0
        while i < len(order) and n < MESH_BATCH_EDGES:
            a, b = order[i]
            if len(verts) + (a not in verts) + (b not in verts) > MESH_BATCH_VERTS:
                break
            verts.update((a, b))
            n += 1
            i += 1
        batches += 1
        slots += len(verts)
    return batches, slots


def baked_batches(order: list[list[int]]) -> bytes:
    """Per batch: nslot, nedge, slot→vert, starts, ends. nslot = 0 ends. Packs like batch_cost."""
    out = bytearray()
    i = 0
    while i < len(order):
        slots: list[int] = []
        starts: list[int] = []
        ends: list[int] = []
        while i < len(order) and len(starts) < MESH_BATCH_EDGES:
            a, b = order[i]
            if len(slots) + (a not in slots) + (b not in slots) > MESH_BATCH_VERTS:
                break
            for v in (a, b):
                if v not in slots:
                    slots.append(v)
            starts.append(slots.index(a))
            ends.append(slots.index(b))
            i += 1
        out += bytes([len(slots), len(starts)]) + bytes(slots) + bytes(starts) + bytes(ends)
    out.append(0)
    return bytes(out)


def greedy_edges(lines: list[tuple[int, int]], rng: random.Random | None) -> list[list[int]]:
    left = list(lines)
    out: list[list[int]] = []
    while left:
        verts: set[int] = set()
        n = 0
        while left and n < MESH_BATCH_EDGES:
            cands = []
            for i, (a, b) in enumerate(left):
                need = (a not in verts) + (b not in verts)
                if len(verts) + need <= MESH_BATCH_VERTS:
                    cands.append((need, i))
            if not cands:
                break
            low = min(c[0] for c in cands)
            pool = [i for need, i in cands if need == low]
            a, b = left.pop(pool[0] if rng is None else rng.choice(pool))
            verts.update((a, b))
            out.append([a, b])
            n += 1
    return out


def cluster_edges(lines: list[list[int]]) -> tuple[list[list[int]], int, int]:
    """Edge order that minimises batches then vert slots. Deterministic (fixed seeds)."""
    src = [(int(a), int(b)) for a, b in lines]
    best = [list(e) for e in src]
    cost = batch_cost(best)
    for seed in range(1000):
        order = greedy_edges(src, random.Random(seed))
        c = batch_cost(order)
        if c < cost:
            best, cost = order, c
    return best, cost[0], cost[1]


def pin_feet_slot(body: bytearray, feet: int) -> bool:
    """One batch of 12..16 slots: put the feet vertex in slot 11 and remap pairs.
    Slot 11 is the far-LOD anchor (ent_far_project)."""
    if not body or body[0] < 12 or body[0] > MESH_BATCH_VERTS:
        return False
    nslot = body[0]
    nedge = body[1]
    end = 2 + nslot + nedge * 2
    if end >= len(body) or body[end] != 0:
        return False
    slots = bytearray(body[2:2 + nslot])
    try:
        src = slots.index(feet)
    except ValueError:
        return False
    anchor = 11
    if src != anchor:
        slots[src], slots[anchor] = slots[anchor], slots[src]
        body[2:2 + nslot] = slots
        pair_at = 2 + nslot
        for i in range(nedge * 2):
            p = body[pair_at + i]
            if p == src:
                body[pair_at + i] = anchor
            elif p == anchor:
                body[pair_at + i] = src
    return True


def skel_prefix(nv: int, lines: list[list[int]], shift: int, name: str, feet: int = 0) -> bytes:
    ne = len(lines)
    lines, batches, slots = cluster_edges(lines)
    print(f"{name}: edge order {batches} batches, {slots} vert slots")
    body = bytearray(baked_batches(lines))
    if shift == 0 and pin_feet_slot(body, feet):
        print(f"{name}: feet vert {feet} in slot 11")
    size = SKEL_PFX + len(body)
    out = bytearray(size)
    out[0] = size & 0xFF
    out[1] = (size >> 8) & 0xFF
    out[2] = nv & 0xFF
    out[3] = ne & 0xFF
    out[6] = shift
    out[SKEL_PFX:] = body
    return bytes(out)


def export_type(enemy: dict) -> tuple[list[int], list[int], list[int], list[list[int]], list[dict], int, int]:
    lines = enemy["lines"]
    frames = enemy["frames"]
    clips = enemy.get("clips") or []
    nv = enemy_nv(enemy)
    custom = bool(enemy.get("customSkeleton"))
    if custom:
        if nv == 0:
            lines = []
        elif not 1 <= len(lines) <= SKEL_MAX_EDGES:
            raise SystemExit(f"{enemy['name']}: custom skeleton line count {len(lines)} not in 1..{SKEL_MAX_EDGES}")
        else:
            for a, b in lines:
                ai, bi = int(a), int(b)
                if ai == bi or not 0 <= ai < nv or not 0 <= bi < nv:
                    raise SystemExit(f"{enemy['name']}: bad custom line {a}-{b}")
    elif len(lines) != NVERTS:
        raise SystemExit(f"{enemy['name']}: expected {NVERTS} lines, got {len(lines)}")
    if not frames:
        raise SystemExit(f"{enemy['name']}: no frames")
    fine = enemy_fine(enemy)
    if fine:
        # Quarter-units are already inside a signed byte. Do not shift them down.
        shift = 0
    else:
        shift = pick_skel_shift(enemy, frames) if custom else 0
    gx: list[int] = []
    gy: list[int] = []
    gz: list[int] = []
    for fi, fr in enumerate(frames):
        if len(fr) != nv:
            raise SystemExit(f"{enemy['name']} frame {fi}: bad vert count")
        for v in fr:
            gx.append(s8(shift_round(pose_int(v["x"], fine), shift)))
            gy.append(s8(shift_round(pose_int(v["y"], fine), shift)))
            gz.append(s8(shift_round(pose_int(v["z"], fine), shift)))
    return gx, gy, gz, lines, clips, nv, shift


def trim_to_budget(gx: list[int], gy: list[int], gz: list[int], enemy: dict, nv: int) -> int:
    """Keep authored logical frames; packed .pose size is the real budget."""
    del gy, gz
    if nv <= 0:
        return max(1, len(enemy.get("frames") or [None]))
    return len(gx) // nv


def load_doc() -> dict:
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    enemies = []
    edir = ROOT / "editor" / "enemies"
    for dos in DOS_NAME:
        path = edir / f"{dos}.json"
        if not path.is_file():
            raise SystemExit(f"missing {path}")
        enemies.append(json.loads(path.read_text(encoding="utf-8")))
    doc["enemies"] = enemies
    return doc


def pack_kept(
    gx: list[int], gy: list[int], gz: list[int], kept: list[int], nv: int, name: str
) -> tuple[list[int], list[int], list[int], list[int], int]:
    """Alias identical XYZ, then pack stored axes. pose_map indexes stored slots."""
    seen: dict[tuple[int, ...], int] = {}
    unique: list[int] = []
    alias = [0] * len(kept)
    for old_i, fi in enumerate(kept):
        off = fi * nv
        key = tuple(gx[off : off + nv] + gy[off : off + nv] + gz[off : off + nv])
        slot = seen.get(key)
        if slot is None:
            slot = len(unique)
            seen[key] = slot
            unique.append(fi)
        alias[old_i] = slot
    n_stored = len(unique)
    if n_stored > 127:
        raise SystemExit(f"{name}: {n_stored} stored poses > 127")

    def pack_axis(src: list[int]) -> list[int]:
        out: list[int] = []
        for fi in unique:
            off = fi * nv
            out.extend(src[off : off + nv])
        return out

    return pack_axis(gx), pack_axis(gy), pack_axis(gz), alias, n_stored


def pack_poses(
    gx: list[int],
    gy: list[int],
    gz: list[int],
    enemy: dict,
    nframes: int,
    nv: int,
) -> tuple[list[int], list[int], list[int], list[int], int]:
    """Store every authored frame. pose_map indexes stored slots."""
    return pack_kept(gx, gy, gz, list(range(nframes)), nv, str(enemy.get("name", "?")))


def enemy_hp_byte(enemy: dict, name: str) -> int:
    raw = enemy.get("hp", DEFAULT_HP[name])
    try:
        v = int(raw)
    except (TypeError, ValueError):
        v = DEFAULT_HP[name]
    return max(1, min(255, v))


def enemy_pain_chance_byte(enemy: dict, name: str) -> int:
    raw = enemy.get("painChance", PAIN_CHANCE.get(name, DEFAULT_PAIN_CHANCE))
    try:
        v = int(raw)
    except (TypeError, ValueError):
        v = PAIN_CHANCE.get(name, DEFAULT_PAIN_CHANCE)
    return max(0, min(255, v))


def main() -> None:
    doc = load_doc()
    by_name = {e["name"]: e for e in doc["enemies"]}
    ids_path = ENEMY_DIR / "sound_ids.json"
    if not ids_path.is_file():
        raise SystemExit(f"missing {ids_path}; run gensounds.py first")
    ids_raw = json.loads(ids_path.read_text(encoding="utf-8"))
    if not isinstance(ids_raw, dict):
        raise SystemExit(f"{ids_path}: expected object")
    sound_ids = {str(k).upper(): int(v) for k, v in ids_raw.items()}
    ENEMY_DIR.mkdir(exist_ok=True)
    parts = [
        "; Generated by tools/genenemies.py — metadata only; poses load from disk",
        "PAIN_MAX	= 4		; variants per type; pain_var_off uses ASL×2",
        "",
    ]
    pose_sizes: list[int] = []
    max_nframes = 0
    nframes_list: list[int] = []
    stored_list: list[int] = []

    for ti, name in enumerate(TYPES):
        if name not in by_name:
            raise SystemExit(f"missing enemy {name}")
        enemy = deepcopy(by_name[name])
        apply_tool_cues(enemy)
        if not (isinstance(enemy.get("frames"), list) and enemy["frames"]):
            raise SystemExit(f"{name}: no authored frames")
        apply_export_clips(enemy)
        gx, gy, gz, lines, _clips, nv, shift = export_type(enemy)
        nframes = trim_to_budget(gx, gy, gz, enemy, nv)
        dos = DOS_NAME[ti]
        custom = bool(enemy.get("customSkeleton"))
        if nv and lines:
            feet = min(range(nv), key=lambda i: ((gy[i] - 256) if gy[i] >= 128 else gy[i], i))
            prefix = skel_prefix(nv, lines, shift, name, feet)
        else:
            prefix = b""
        raw_lod = enemy.get("lodZ", DEFAULT_LOD_Z.get(name, 4))
        try:
            lod = int(raw_lod)
        except (TypeError, ValueError):
            lod = DEFAULT_LOD_Z.get(name, 4)
        lod = max(0, min(255, lod))
        while True:
            pgx, pgy, pgz, pose_map, n_stored = pack_poses(
                gx, gy, gz, enemy, nframes, nv
            )
            row = build_meta_row(name, enemy, nframes, n_stored, lod)
            payload = (
                prefix
                + row
                + bytes([n_stored, nframes])
                + bytes(pose_map)
                + bytes(pgx)
                + bytes(pgy)
                + bytes(pgz)
            )
            payload += pack_cues(enemy, sound_ids)
            payload += pack_clip_events(enemy, sound_ids)
            if len(payload) <= ENEMY_POSE_MAX:
                gx, gy, gz = pgx, pgy, pgz
                break
            raise SystemExit(f"{name} pose {len(payload)} exceeds {ENEMY_POSE_MAX}")
        (ENEMY_DIR / f"{dos}.pose").write_bytes(payload)
        (ENEMY_DIR / f"{dos}.skel").write_bytes(bytes([1 if prefix else 0]))
        (ENEMY_DIR / f"{dos}.prg").write_bytes(struct.pack("<H", 0) + payload)
        pose_sizes.append(len(payload))
        nframes_list.append(nframes)
        stored_list.append(n_stored)
        n_lerp = sum(1 for v in pose_map if v == 0xFF)
        shift_note = f" shift={shift}" if custom else ""
        print(
            f"{name}: logical={nframes} stored={n_stored} lerp={n_lerp} bytes={len(payload)} "
            f"lodZ={lod}{shift_note}"
        )
        if nframes > max_nframes:
            max_nframes = nframes

    hp_bytes = ", ".join(str(enemy_hp_byte(by_name[t], t)) for t in TYPES)
    parts.append(f"enemy_hp_init\t!byte {hp_bytes}")
    parts.append("")
    parts.append("; Two resident rows, copied from the loaded bank. Width 2; variants are slot*4.")
    parts.append("; Zeros until patch_enemy_bank. meta_slot_type $ff = empty.")
    slot2 = "0, 0"
    slot8 = "0, 0, 0, 0, 0, 0, 0, 0"
    for label in (
        "enemy_stand_start",
        "enemy_stand_len",
        "enemy_alert_start",
        "enemy_alert_len",
        "enemy_run_start",
        "enemy_run_len",
        "enemy_walk_start",
        "enemy_walk_len",
        "enemy_attack_n",
    ):
        parts.append(f"{label}\t!byte {slot2}")
    parts.append(f"enemy_attack_start\t!byte {slot8}")
    parts.append(f"enemy_attack_len\t!byte {slot8}")
    parts.append(f"enemy_pain_n\t!byte {slot2}")
    parts.append(f"enemy_pain_start\t!byte {slot8}")
    parts.append(f"enemy_pain_len\t!byte {slot8}")
    parts.append(f"enemy_death_n\t!byte {slot2}")
    parts.append(f"enemy_death_start\t!byte {slot8}")
    parts.append(f"enemy_death_len\t!byte {slot8}")
    for label in (
        "enemy_range",
        "enemy_pain_chance",
        "enemy_fire_frame",
        "enemy_class",
        "enemy_lod_z",
        "enemy_nframes",
    ):
        parts.append(f"{label}\t!byte {slot2}")
    parts.append("meta_slot_type\t!byte $ff, $ff")
    parts.append("meta_scratch\t!byte 0")
    parts.append("")

    data_text = "\n".join(parts) + "\n"
    BLOB_OUT.write_text(
        '; Generated by tools/genenemies.py — boot-loaded enemy metadata\n'
        '!cpu 6502\n'
        '!to "enemydata.prg", cbm\n'
        '!source "mem.asm"\n'
        '*= ENEMY_DATA_BASE\n'
        + data_text
        + 'enemy_data_end = *\n'
        + '!if enemy_data_end > ENEMY_DATA_LIMIT {\n'
        + '\t!error "Enemy metadata overlaps streamed AI pointers"\n'
        + '}\n',
        encoding="utf-8",
    )

    # GAME sees the same absolute labels, but emits no copy of the data.
    # Keep the generated blob and these aliases mechanically locked together.
    aliases: list[tuple[str, int]] = []
    addr = ENEMY_DATA_BASE
    pending: str | None = None
    for raw in data_text.splitlines():
        line = raw.split(";", 1)[0].strip()
        if not line or line.startswith("PAIN_MAX"):
            continue
        inline = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s+!byte\s+(.+)$", line)
        if inline:
            label, values = inline.groups()
            aliases.append((label, addr))
            addr += len(values.split(","))
            pending = None
            continue
        label_only = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)$", line)
        if label_only:
            pending = label_only.group(1)
            continue
        byte_row = re.match(r"^!byte\s+(.+)$", line)
        if byte_row:
            if pending is None:
                raise SystemExit(f"enemy metadata byte row without label: {raw}")
            aliases.append((pending, addr))
            addr += len(byte_row.group(1).split(","))
            pending = None
    if pending is not None:
        raise SystemExit(f"enemy metadata label without bytes: {pending}")
    alias_lines = [
        "; Generated by tools/genenemies.py — labels for boot-loaded enemy metadata",
        "PAIN_MAX\t= 4\t\t; variants per type; pain_var_off uses ASL×2",
        "",
    ]
    alias_lines.extend(f"{name}\t= ${value:04x}" for name, value in aliases)
    alias_lines.extend(
        [
            f"ENEMY_DATA_BYTES\t= {addr - ENEMY_DATA_BASE}",
            f"ENEMY_DATA_END\t= ${addr:04x}",
            "",
        ]
    )
    OUT.write_text("\n".join(alias_lines), encoding="utf-8")
    size_lo = ",".join(str(s & 0xFF) for s in pose_sizes)
    size_hi = ",".join(str((s >> 8) & 0xFF) for s in pose_sizes)
    SIZES_OUT.write_text(
        "; Generated by tools/genenemies.py — pose payload bytes per type (sfx blob + cue ids + clip events)\n"
        f"enemy_size_lo	!byte {size_lo}\n"
        f"enemy_size_hi	!byte {size_hi}\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {OUT.relative_to(ROOT)} + {BLOB_OUT.relative_to(ROOT)} "
        f"+ enemy PRGs sizes={pose_sizes} "
        f"logical={nframes_list} stored={stored_list}"
    )


if __name__ == "__main__":
    main()
