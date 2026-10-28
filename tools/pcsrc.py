#!/usr/bin/env python3
"""Resolve a Doom PC-speaker lump to Wolf inverse-freq bytes.

DP* streams in ref/DOOM.WAD are decimated 3x from 140 Hz. speaker.txt is not used.
"""
from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "ref"
DOOM_WAD = REF / "DOOM.WAD"

PC_TIMER = 1193181
DECIMATE = 3
MAX_TICKS = 255

_BANK: dict[str, list[int]] | None = None


def decimate(data: list[int]) -> list[int]:
    samples: list[int] = []
    for i in range(0, len(data), DECIMATE):
        group = data[i : i + DECIMATE]
        samples.append(next((x for x in group if x), 0))
    if len(samples) > MAX_TICKS:
        raise SystemExit(f"decimated length {len(samples)} > {MAX_TICKS}")
    return samples


def pitch_hz(pitch: int) -> float:
    if pitch <= 0:
        return 0.0
    return 175.0 * (2 ** ((pitch - 1) / 24))


def hz_to_wolf(hz: float) -> int:
    if hz <= 0:
        return 0
    return max(1, min(255, round(PC_TIMER / (hz * 60))))


def _require(path: Path) -> bytes:
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    return path.read_bytes()


def _load_doom() -> dict[str, list[int]]:
    blob = _require(DOOM_WAD)
    ident = blob[:4]
    if ident not in (b"IWAD", b"PWAD"):
        raise SystemExit(f"{DOOM_WAD.name} is not a WAD ({ident!r})")
    numlumps, dirofs = struct.unpack_from("<II", blob, 4)
    order: list[str] = []
    lumps: dict[str, bytes] = {}
    for i in range(numlumps):
        o = dirofs + i * 16
        filepos, size = struct.unpack_from("<II", blob, o)
        name = blob[o + 8 : o + 16].split(b"\0", 1)[0].decode("ascii", "replace").upper()
        if not name.startswith("DP"):
            continue
        if name not in lumps:
            order.append(name)
        lumps[name] = blob[filepos : filepos + size]
    if len(order) != 67:
        raise SystemExit(f"expected 67 unique DP lumps, got {len(order)}")
    out: dict[str, list[int]] = {}
    for name in order:
        buf = lumps[name]
        if len(buf) < 4:
            raise SystemExit(f"{name}: lump shorter than header")
        length = buf[2] | (buf[3] << 8)
        data = list(buf[4 : 4 + length])
        if len(data) != length:
            raise SystemExit(f"{name}: truncated (header {length}, got {len(data)})")
        freq = [hz_to_wolf(pitch_hz(p)) for p in decimate(data)]
        out[name] = freq
    return out


def bank() -> dict[str, list[int]]:
    global _BANK
    if _BANK is None:
        _BANK = _load_doom()
    return _BANK


def resolve(name: str) -> list[int]:
    key = name.strip().upper()
    if not key:
        raise SystemExit("sound library name is empty")
    freq = bank().get(key)
    if freq is None:
        raise SystemExit(f"unknown doom sound {key}")
    return list(freq)
