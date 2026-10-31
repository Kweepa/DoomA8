#!/usr/bin/env python3
"""Pack view-model PNGs → one mode-E rect each in src/weapon_spr.asm.

X is clipped to a multiple of 8 hires (phase 0). Two hires bits are one
colour-clock pixel, stored row-major. Bodies are inverted (ink %00, clear
%11) and ANDed on, so the gun is black. Flashes are ink %11 / clear %00.

    python tools/genweapons.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from sprmask import (  # noqa: E402
    H,
    W,
    bchunk,
    load_png_1bit,
    pack_clipped,
)

DOC = ROOT / "editor" / "doom64.json"
PNG_DIR = ROOT / "assets" / "weapons"
OUT = ROOT / "src" / "weapon_spr.asm"
SHEET = PNG_DIR / "sheet.png"

EDIT_RE = re.compile(r"^([a-z0-9]+)_(\d+)_edit\.png$", re.I)

# label, png, viewport-relative hires x (VIC x − 88), dy added to weapon y.
FLASHES = [
    ("spr_muzzle_b", "muzzle_flash.png", 172 - 88, -20),
]

# Weapon order in tables: fist, shot, chain, rocket, pistol, saw.
# pistol_lines.png and shotgun_lines.png are 2×1 pixels. Even origin,
# so each pair lands on one mode-E pixel. Pistol columns 12–13 and
# shotgun columns 20–21 sit on the muzzle stem (clock 47).
PISTOL_OX = 10
SHOT_OX = 2
COCK_OX = 18


def glob_edit_frames(key: str) -> list[int]:
    found: list[int] = []
    if not PNG_DIR.is_dir():
        return found
    for p in PNG_DIR.iterdir():
        m = EDIT_RE.match(p.name)
        if not m or m.group(1).lower() != key:
            continue
        found.append(int(m.group(2)))
    return sorted(set(found))


def item_frames(weapons: dict, key: str) -> list[int]:
    items = weapons.get("items") or weapons
    item = items.get(key) or {}
    raw = item.get("frames")
    if isinstance(raw, list) and raw:
        seen: set[int] = set()
        out: list[int] = []
        for f in raw:
            n = int(f)
            if n < 0 or n in seen:
                continue
            seen.add(n)
            out.append(n)
        return out
    found = glob_edit_frames(key)
    if found:
        return found
    return [0]


def edit_png(key: str, frame: int) -> Path:
    return PNG_DIR / f"{key}_{frame}_edit.png"


def pix_from_png(key: str, frame: int) -> list[list[int]] | None:
    path = edit_png(key, frame)
    if path.is_file():
        return load_png_1bit(path, W, H)
    return None


def load_pix(key: str, frame: int) -> list[list[int]]:
    path = edit_png(key, frame)
    pix = pix_from_png(key, frame)
    if pix is not None:
        print(f"  occupancy {key}: {path.name}")
        return pix
    raise SystemExit(f"occupancy needs {path} (not packed asm / unedited png)")


def line_canvas(name: str, ox: int, width: int, height: int | None = None) -> list[list[int]]:
    """Line-art PNG copied at ox. Even origin pairs the 2×1 pixels.

    height set: the PNG must be exactly that tall. Otherwise any h≤H is accepted.
    """
    path = PNG_DIR / name
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    from PIL import Image

    im = Image.open(path).convert("RGB")
    iw, ih = im.size
    bad_h = ih != height if height is not None else ih > H
    if iw != width or bad_h or ox + iw > W:
        want_h = str(height) if height is not None else f"h≤{H}"
        raise SystemExit(
            f"{path.name}: expected {width}×{want_h} at x={ox}, got {iw}×{ih}"
        )
    pix = [[0] * W for _ in range(H)]
    src = im.load()
    for y in range(ih):
        for x in range(iw):
            r, g, b = src[x, y][:3]
            if r > 16 or g > 16 or b > 16:
                pix[y][ox + x] = 1
    print(f"  occupancy {path.stem}: {path.name} at x={ox}")
    return pix


def line_png(name: str) -> list[list[int]]:
    """Native-size line art. Wider than the old 48-wide canvas."""
    path = PNG_DIR / name
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    from PIL import Image

    im = Image.open(path).convert("RGB")
    iw, ih = im.size
    if iw <= 0 or ih <= 0 or iw > 256 or ih > 127:
        raise SystemExit(f"{path.name}: {iw}×{ih} outside a mode-E rect")
    pix = [[0] * iw for _ in range(ih)]
    src = im.load()
    for y in range(ih):
        for x in range(iw):
            r, g, b = src[x, y][:3]
            if r > 16 or g > 16 or b > 16:
                pix[y][x] = 1
    print(f"  occupancy {path.stem}: {path.name} {iw}×{ih}")
    return pix


def pistol_canvas() -> list[list[int]]:
    return line_canvas("pistol_lines.png", PISTOL_OX, 24)


def shotgun_canvas() -> list[list[int]]:
    return line_canvas("shotgun_lines.png", SHOT_OX, 40, 32)


def cock_canvas() -> list[list[int]]:
    return line_canvas("shotgun_cock_lines.png", COCK_OX, 24, 42)


def flash_pix(png_name: str) -> list[list[int]]:
    path = PNG_DIR / png_name
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    return load_png_1bit(path, 24, 21)


def write_sheet(rows: list[list[tuple[str, list[list[int]], list[int]]]]) -> None:
    """Contact sheet. Ink from the canvas; the outline is the packed rect."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow not installed; skip PNG sheet")
        return
    pad = 8
    label_h = 16
    cell_w = max((len(pix[0]) for row in rows for _, pix, _ in row), default=W)
    cell_h = max((len(pix) for row in rows for _, pix, _ in row), default=H)
    cols = max((len(row) for row in rows), default=1)
    img_w = cols * (cell_w + pad) + pad
    img_h = len(rows) * (cell_h + label_h + pad) + pad
    im = Image.new("RGB", (img_w, img_h), (12, 12, 14))
    draw = ImageDraw.Draw(im)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    y = pad
    for row in rows:
        x = pad
        for name, pix, packed in row:
            draw.text((x, y), name, fill=(212, 160, 23), font=font)
            cell_im = Image.new("RGB", (cell_w, cell_h), (10, 10, 12))
            px = cell_im.load()
            for yy in range(len(pix)):
                row_px = pix[yy]
                for xx in range(len(row_px)):
                    if row_px[xx]:
                        px[xx, yy] = (232, 228, 216)
            cy = y + label_h
            im.paste(cell_im, (x, cy))
            xb, yb, bw, bh = packed[:4]
            if yb >= 128:
                yb -= 256
            rx0 = x + xb * 8
            ry0 = cy + yb
            draw.rectangle((rx0, ry0, rx0 + bw * 8 - 1, ry0 + bh - 1), outline=(212, 160, 23))
            x += cell_w + pad
        y += label_h + cell_h + pad
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    im.save(SHEET)
    print(f"Wrote {SHEET.relative_to(ROOT)}")


def emit_bytes(label: str, data: list[int]) -> list[str]:
    return [label, bchunk(data).rstrip(), ""]


def rect_note(data: list[int]) -> str:
    xb, yb, bw, bh = data[:4]
    if yb >= 128:
        yb -= 256
    return f"{bw * 8}x{bh} @ {xb * 8},{yb} ({len(data)}B)"


def main() -> None:
    if not DOC.is_file():
        raise SystemExit(f"missing {DOC}")
    shot_pix = shotgun_canvas()
    cock_pix = cock_canvas()
    pist_pix = pistol_canvas()
    fist_pix = line_png("fist_lefthand_lines.png")
    hand_pix = line_png("fist_righthand_lines.png")
    saw_pix = line_png("chainsaw_lines.png")
    chain_pix = line_png("chaingun_a_lines.png")
    chain2_pix = line_png("chaingun_b_lines.png")
    rkt_pix = line_png("rocketlauncher_lines.png")

    shot_b = pack_clipped(shot_pix, black=True, name="shot")
    cock_b = pack_clipped(cock_pix, black=True, name="cock")
    pist_b = pack_clipped(pist_pix, black=True, name="pist")
    fist_b = pack_clipped(fist_pix, black=True, name="fist")
    hand_b = pack_clipped(hand_pix, black=True, name="hand")
    saw_b = pack_clipped(saw_pix, black=True, name="saw")
    chain_b = pack_clipped(chain_pix, black=True, name="chain")
    chain2_b = pack_clipped(chain2_pix, black=True, name="chain2")
    rkt_b = pack_clipped(rkt_pix, black=True, name="rkt")
    if shot_b[0] != 0 or shot_b[1] != 0 or shot_b[2] != 5 or shot_b[3] != 32:
        raise SystemExit(f"shotgun rect {shot_b[:4]}, expected 40x32 at 0,0")
    if cock_b[0] != 2 or cock_b[1] != 0 or cock_b[2] != 4 or cock_b[3] != 42:
        raise SystemExit(f"cock rect {cock_b[:4]}, expected 32x42 at x=16")
    flashes = [
        (label, pack_clipped(flash_pix(png), x_origin=ox, y_origin=dy, name=label))
        for label, png, ox, dy in FLASHES
    ]

    # Frame order: fist, hand, shot, cock, chain, chain B, rocket, pist, saw.
    # wpn_fr_base is per weapon id. Chain B is base+1. Cock is the shotgun's +1.
    parts = [
        "; Generated by tools/genweapons.py from assets/weapons — do not edit",
        "; One rect: x_byte, y, width, height, then width*height row-major bytes.",
        "; X is a multiple of 8 hires (phase 0). Bodies are inverted (ink %00, clear %11).",
        "; Flashes are ink %11 / clear %00. Phase 1 ORs line colour; phase 2 writes %10.",
        "",
        "; Frame pointers: fist, hand, shot, cock, chain, chain B, rocket, pist, saw.",
        "wpn_fr_lo",
        "\t!byte <spr_fist_b, <spr_hand_b, <spr_shot_b, <spr_shot_cock_b, <spr_chain_b, <spr_chain2_b, <spr_rkt_b, <spr_pist_b, <spr_saw_b",
        "wpn_fr_hi",
        "\t!byte >spr_fist_b, >spr_hand_b, >spr_shot_b, >spr_shot_cock_b, >spr_chain_b, >spr_chain2_b, >spr_rkt_b, >spr_pist_b, >spr_saw_b",
        "wpn_fr_base",
        "\t!byte 0, 2, 4, 6, 7, 8",
        "wpn_fl4_lo",
        "\t!byte <spr_muzzle_b, <spr_muzzle_b, <spr_muzzle_b, <spr_muzzle_b, <spr_muzzle_b, <spr_muzzle_b",
        "wpn_fl4_hi",
        "\t!byte >spr_muzzle_b, >spr_muzzle_b, >spr_muzzle_b, >spr_muzzle_b, >spr_muzzle_b, >spr_muzzle_b",
        "",
    ]
    parts += emit_bytes("spr_fist_b", fist_b)
    parts += emit_bytes("spr_hand_b", hand_b)
    parts += emit_bytes("spr_shot_b", shot_b)
    parts += emit_bytes("spr_shot_cock_b", cock_b)
    parts += emit_bytes("spr_chain_b", chain_b)
    parts += emit_bytes("spr_chain2_b", chain2_b)
    parts += emit_bytes("spr_rkt_b", rkt_b)
    parts += emit_bytes("spr_pist_b", pist_b)
    parts += emit_bytes("spr_saw_b", saw_b)
    for label, data in flashes:
        parts += emit_bytes(label, data)

    OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}")
    print(f"  fist {rect_note(fist_b)}  hand {rect_note(hand_b)}  saw {rect_note(saw_b)}")
    print(f"  chain {rect_note(chain_b)}  chain2 {rect_note(chain2_b)}  rkt {rect_note(rkt_b)}")
    print(f"  shot {rect_note(shot_b)}  cock {rect_note(cock_b)}  pist {rect_note(pist_b)}")
    for label, data in flashes:
        print(f"  {label}: {rect_note(data)}")

    write_sheet(
        [
            [
                ("fist", fist_pix, fist_b),
                ("hand", hand_pix, hand_b),
                ("saw", saw_pix, saw_b),
                ("chain", chain_pix, chain_b),
                ("chain2", chain2_pix, chain2_b),
            ],
            [
                ("rocket", rkt_pix, rkt_b),
                ("shot2", shot_pix, shot_b),
                ("cock", cock_pix, cock_b),
                ("pist", pist_pix, pist_b),
            ],
        ]
    )


if __name__ == "__main__":
    main()
