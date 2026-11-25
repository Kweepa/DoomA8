#!/usr/bin/env python3
"""One-off: seed editor/font.json from ui/doomfont.png (needs Pillow).

After this, editor/font.json is the source of truth (tools/genuifont.py reads it).
Output format matches editor/js/fontModel.js fontToJson, so the editor's first save
does not rewrite the file.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PNG = ROOT / "ui" / "doomfont.png"
OUT = ROOT / "editor" / "font.json"

COLS = 8
ROWS = 12
CELL = 8
ASCII_BASE = 32


def glyph_rows(im: Image.Image, col: int, row: int) -> list[int]:
    out = []
    for y in range(CELL):
        b = 0
        for x in range(CELL):
            if im.getpixel((col * CELL + x, row * CELL + y)) > 128:
                b |= 0x80 >> x
        out.append(b)
    return out


def main() -> None:
    im = Image.open(PNG).convert("L")
    w, h = im.size
    if w != COLS * CELL or h != ROWS * CELL:
        raise SystemExit(f"{PNG} is {w}x{h}, expected {COLS * CELL}x{ROWS * CELL}")

    lines = []
    for i in range(COLS * ROWS):
        code = ASCII_BASE + i
        rows = glyph_rows(im, i % COLS, i // COLS)
        ch = "DEL" if code == 127 else chr(code)
        hexes = ", ".join(f'"{r:02X}"' for r in rows)
        lines.append(f'    {{ "code": {code}, "char": {json.dumps(ch)}, "rows": [{hexes}] }}')

    text = (
        '{\n  "version": 1,\n  "firstChar": 32,\n  "glyphs": [\n'
        + ",\n".join(lines)
        + "\n  ]\n}\n"
    )
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
