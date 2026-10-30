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

AXE_KEY = "axe"
EDIT_RE = re.compile(r"^([a-z0-9]+)_(\d+)_edit\.png$", re.I)

# label, png, viewport-relative hires x (VIC x − 88), dy added to weapon y.
# Same signed offset as wpn_flashdy / place_flash: −FLASH_DY, −FLASH_DY_GUN, FLASH_DY_NAIL.
FLASHES = [
    ("spr_muzzle_b", "muzzle_flash.png", 172 - 88, -20),
    ("spr_spark_b", "axe_flash.png", 172 - 88, -10),
    ("spr_chain_fl_b", "chain_flash_left.png", 160 - 88, -15),
    ("spr_chain_fr_b", "chain_flash_right.png", 184 - 88, -15),
]

# Weapon order in tables: axe, shot, chain, gren, pistol.
# pistol_lines.png and shotgun_lines.png are 2×1 pixels. Even origin,
# so each pair lands on one mode-E pixel. Pistol columns 12–13 and
# shotgun columns 20–21 sit on the muzzle stem (clock 47).
PISTOL_OX = 10
SHOT_OX = 2


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


def pistol_canvas() -> list[list[int]]:
    return line_canvas("pistol_lines.png", PISTOL_OX, 24)


def shotgun_canvas() -> list[list[int]]:
    return line_canvas("shotgun_lines.png", SHOT_OX, 40, 32)


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
    cols = max((len(row) for row in rows), default=1)
    img_w = cols * (W + pad) + pad
    img_h = len(rows) * (H + label_h + pad) + pad
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
            cell_im = Image.new("RGB", (W, H), (10, 10, 12))
            px = cell_im.load()
            for yy in range(H):
                for xx in range(W):
                    if pix[yy][xx]:
                        px[xx, yy] = (232, 228, 216)
            cy = y + label_h
            im.paste(cell_im, (x, cy))
            xb, yb, bw, bh = packed[:4]
            if yb >= 128:
                yb -= 256
            rx0 = x + xb * 8
            ry0 = cy + yb
            draw.rectangle((rx0, ry0, rx0 + bw * 8 - 1, ry0 + bh - 1), outline=(212, 160, 23))
            x += W + pad
        y += label_h + H + pad
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
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    weapons = doc.get("weapons") or {}

    chain_frames = item_frames(weapons, "chain")
    rock_frames = item_frames(weapons, "rock")
    axe_frames = item_frames(weapons, AXE_KEY)

    shot_pix = shotgun_canvas()
    rock_pix = load_pix("rock", rock_frames[0])
    axe_pix = load_pix("axe", axe_frames[0])
    chain_pix = [load_pix("chain", f) for f in chain_frames]
    if len(chain_pix) != 3:
        raise SystemExit(f"chain needs 3 frames, got {len(chain_pix)}")
    pist_pix = pistol_canvas()

    axe_b = pack_clipped(axe_pix, black=True, name="axe")
    shot_b = pack_clipped(shot_pix, black=True, name="shot")
    rock_b = pack_clipped(rock_pix, black=True, name="rock")
    pist_b = pack_clipped(pist_pix, black=True, name="pist")
    chain_b = [pack_clipped(pix, black=True, name=f"chain{i}") for i, pix in enumerate(chain_pix)]
    if shot_b[0] != 0 or shot_b[1] != 0 or shot_b[2] != 5 or shot_b[3] != 32:
        raise SystemExit(f"shotgun rect {shot_b[:4]}, expected 40x32 at 0,0")
    flashes = [
        (label, pack_clipped(flash_pix(png), x_origin=ox, y_origin=dy, name=label))
        for label, png, ox, dy in FLASHES
    ]

    parts = [
        "; Generated by tools/genweapons.py from assets/weapons — do not edit",
        "; One rect: x_byte, y, width, height, then width*height row-major bytes.",
        "; X is a multiple of 8 hires (phase 0). Bodies are inverted (ink %00, clear %11).",
        "; Flashes are ink %11 / clear %00. Phase 1 ORs line colour; phase 2 writes %10.",
        "",
        "; Frame pointers: axe, shot, chain0, chain1, chain2, rock, pist.",
        "wpn_fr_lo",
        "\t!byte <spr_axe_b, <spr_shot_b, <spr_chain_b0, <spr_chain_b1, <spr_chain_b2, <spr_rock_b, <spr_pist_b",
        "wpn_fr_hi",
        "\t!byte >spr_axe_b, >spr_shot_b, >spr_chain_b0, >spr_chain_b1, >spr_chain_b2, >spr_rock_b, >spr_pist_b",
        "wpn_fr_base",
        "\t!byte 0, 1, 2, 5, 6",
        "wpn_fl4_lo",
        "\t!byte <spr_spark_b, <spr_muzzle_b, <spr_chain_fl_b, <spr_muzzle_b, <spr_muzzle_b",
        "wpn_fl4_hi",
        "\t!byte >spr_spark_b, >spr_muzzle_b, >spr_chain_fl_b, >spr_muzzle_b, >spr_muzzle_b",
        "",
    ]
    parts += emit_bytes("spr_axe_b", axe_b)
    parts += emit_bytes("spr_shot_b", shot_b)
    parts += emit_bytes("spr_rock_b", rock_b)
    parts += emit_bytes("spr_pist_b", pist_b)
    for i, data in enumerate(chain_b):
        parts += emit_bytes(f"spr_chain_b{i}", data)
    for label, data in flashes:
        parts += emit_bytes(label, data)

    OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}")
    print(f"  axe {rect_note(axe_b)}  shot {rect_note(shot_b)}")
    print(f"  rock {rect_note(rock_b)}  pist {rect_note(pist_b)}")
    for i, data in enumerate(chain_b):
        print(f"  chain{i} {rect_note(data)}")
    for label, data in flashes:
        print(f"  {label}: {rect_note(data)}")

    write_sheet(
        [
            [
                ("axe", axe_pix, axe_b),
                ("shot2", shot_pix, shot_b),
                ("rock", rock_pix, rock_b),
                ("pist", pist_pix, pist_b),
            ],
            [(f"chain {i}", pix, data) for i, (pix, data) in enumerate(zip(chain_pix, chain_b))],
        ]
    )


if __name__ == "__main__":
    main()
