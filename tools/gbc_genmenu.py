#!/usr/bin/env python3
"""GBC menu data (port of the A8 menu: src/menu.asm, tools/gen_menu_*.py).

Writes <outdir>/menu_gfx.inc and <outdir>/menu_logo_preview.png:
  Logo: ui/hiresdoomlogo.png point-sampled to 128x64 (pixel centres), cut into 16x8 tiles of 4 colours. The 8 CGB
  BG palettes all keep colour 0 black (the menu background). Palette 7 also holds the text colours (A8 TEXT_COL 7
  yellow, HILITE_COL 1 white, VIC/Pepto) and has one colour left for the logo; palettes 0-6 have three free each.
  Tiles are clustered onto the palettes (k-means over tiles, colours per palette by weighted k-means in Lab, several
  restarts, the lowest error kept). Logo tiles go at VRAM bank 0 tile 0.., deduplicated.
  Font: the HUD glyphs (editor/font.json via gbc_hudfont.load_glyphs), 1bpp, 96 glyphs. The menu copies them to
  bank 0 tiles 128..223 as colour 1 (yellow) and bank 1 tiles 128..223 as colour 2 (white, the selected row).
  Map tile = ASCII + 96; ASCII 32 (tile 128) is the blank / black tile.
  Skull: ui/m_skull_c64.png (closed) / ui/m_skull2_c64.png (eyes), 20x19, as 8x16 OBJ: two layers of 3x2 sprites,
  each layer one OBJ palette (3 colours + transparent). 2 frames x 2 layers x 6 sprites x 2 tiles = 48 tiles at
  VRAM bank 1 tile 0.
  Menus: the A8 menu tree minus Quit / Mouse, labels shortened to fit the skull + 16 columns.
  Pages: gbc/text/{controls,order,readthis,credits,ending}.txt, pages split on lines that are only '^'
  (as tools/gen_menu_text.py). At most 20 columns x 9 lines per page; drawn on rows 9-17, centred.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_hudfont  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "ui", "hiresdoomlogo.png")
SKULL = (os.path.join(ROOT, "ui", "m_skull_c64.png"), os.path.join(ROOT, "ui", "m_skull2_c64.png"))
TEXT_DIR = os.path.join(ROOT, "gbc", "text")
PAGES = ("controls", "order", "readthis", "credits", "ending")

LOGO_W, LOGO_H = 128, 64
LOGO_COL = 2                             # BG map column of the logo's left edge (centred on 20)
SCREEN_COLS = 20
PAGE_ROW0, PAGE_ROWS = 9, 9              # text pages: rows 9-17 (row 8 blank under the logo)
MENU_ROW0 = 8                            # first menu row (title or first item); items every other row
SKULL_COLS = 3                           # 20 px skull + 4 px gap
FONT_TILE0 = 128
TEXT_YELLOW = (0xB8, 0xC7, 0x6F)         # VIC 7 (Pepto), A8 menu TEXT_COL
TEXT_WHITE = (0xFF, 0xFF, 0xFF)          # VIC 1, A8 menu HILITE_COL
RESTARTS = 24

# A8 next_menu / menu_str tables (src/menu.asm) without Quit and Mouse. Shortened labels: the skull needs 3 columns.
MENUS = [
    ("", ["New game", "Options", "Controls", "Read this!", "Credits"]),
    ("Which episode?", ["Knee deep in dead", "Shores of hell", "Inferno", "Back"]),
    ("Choose skill level", ["Too young to die", "Hurt me plenty", "Ultra-violence", "Back"]),
    ("Options", ["Volume 15", "Back"]),
]
VOL_MENU, VOL_ITEM, VOL_DIGITS = 3, 0, 7  # "Volume " is 7 characters; two digits follow


def die(msg):
    raise SystemExit("gbc_genmenu: " + msg)


# ---- colour ---------------------------------------------------------------------------------------------------

def to555(rgb):
    return tuple(int(c) >> 3 for c in rgb)


def from555(c):
    return tuple((v << 3) | (v >> 2) for v in c)


def bgr555(c):
    return c[0] | (c[1] << 5) | (c[2] << 10)


def lab(rgb):
    """rgb: (..., 3) floats 0..255 -> CIE Lab."""
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])], -1)


def all555_lab():
    g = np.arange(32)
    r, gg, b = np.meshgrid(g, g, g, indexing="ij")
    c = np.stack([r, gg, b], -1).reshape(-1, 3)
    full = (c << 3) | (c >> 2)
    return c, lab(full)


# ---- logo -----------------------------------------------------------------------------------------------------

def sample_logo():
    im = Image.open(LOGO).convert("RGB")
    w, h = im.size
    out = np.zeros((LOGO_H, LOGO_W, 3), dtype=np.int64)
    for y in range(LOGO_H):
        sy = min(h - 1, int((y + 0.5) * h / LOGO_H))
        for x in range(LOGO_W):
            sx = min(w - 1, int((x + 0.5) * w / LOGO_W))
            out[y, x] = to555(im.getpixel((sx, sy)))
    return out                            # RGB555 components


def fit_colours(pix_lab, weights, fixed_lab, nfree, rng, cands_lab):
    """Weighted k-means: nfree free centroids plus the fixed ones (never moved). Returns free centroids (Lab)."""
    if nfree == 0 or len(pix_lab) == 0:
        return np.zeros((0, 3))
    # init: farthest point from the fixed colours, weighted
    cent = []
    d = np.min(np.linalg.norm(pix_lab[:, None] - fixed_lab[None], axis=2), axis=1) if len(fixed_lab) else \
        np.full(len(pix_lab), 1e9)
    for _ in range(nfree):
        p = d * d * weights
        if p.sum() <= 0:
            cent.append(pix_lab[rng.integers(len(pix_lab))])
        else:
            cent.append(pix_lab[rng.choice(len(pix_lab), p=p / p.sum())])
        d = np.minimum(d, np.linalg.norm(pix_lab - cent[-1], axis=1))
    cent = np.array(cent)
    for _ in range(12):
        allc = np.concatenate([fixed_lab, cent]) if len(fixed_lab) else cent
        a = np.argmin(np.linalg.norm(pix_lab[:, None] - allc[None], axis=2), axis=1) - len(fixed_lab)
        for k in range(nfree):
            m = a == k
            if m.any():
                cent[k] = (pix_lab[m] * weights[m, None]).sum(0) / weights[m].sum()
    # snap to the nearest RGB555 colour
    return np.array([np.argmin(np.sum((cands_lab - c) ** 2, axis=1)) for c in cent])


def build_logo():
    img = sample_logo()
    cands555, cands_lab = all555_lab()
    key = lambda c: (c[0] << 10) | (c[1] << 5) | c[2]   # noqa: E731
    black = (0, 0, 0)
    yellow, white = to555(TEXT_YELLOW), to555(TEXT_WHITE)
    tiles = []                                         # per tile: unique colours (555) and counts
    for ty in range(LOGO_H // 8):
        for tx in range(LOGO_W // 8):
            blk = img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8].reshape(-1, 3)
            u, cnt = np.unique(blk, axis=0, return_counts=True)
            tiles.append((u, cnt))
    tile_lab = [lab(np.array([from555(tuple(c)) for c in u], dtype=np.float64)) for u, _ in tiles]

    fixed = [[black]] * 7 + [[black, yellow, white]]
    fixed_lab = [lab(np.array([from555(c) for c in f], dtype=np.float64)) for f in fixed]
    nfree = [3] * 7 + [1]

    def tile_err(t, pal_lab):
        d = np.min(np.sum((tile_lab[t][:, None] - pal_lab[None]) ** 2, axis=2), axis=1)
        return float((d * tiles[t][1]).sum())

    best = None
    for rs in range(RESTARTS):
        rng = np.random.default_rng(1234 + rs)
        # init: tiles by mean colour into 8 groups (random seeds)
        means = np.array([(tl * c[:, None]).sum(0) / c.sum() for tl, (_, c) in zip(tile_lab, tiles)])
        seeds = means[rng.choice(len(means), 8, replace=False)]
        assign = np.argmin(np.sum((means[:, None] - seeds[None]) ** 2, axis=2), axis=1)
        pals = None
        prev = None
        for _ in range(10):
            pals = []
            for p in range(8):
                mem = [t for t in range(len(tiles)) if assign[t] == p]
                if mem:
                    pl = np.concatenate([tile_lab[t] for t in mem])
                    w = np.concatenate([tiles[t][1] for t in mem]).astype(np.float64)
                else:
                    pl = np.zeros((0, 3))
                    w = np.zeros(0)
                idx = fit_colours(pl, w, fixed_lab[p], nfree[p], rng, cands_lab)
                free = [tuple(int(v) for v in cands555[i]) for i in idx]
                cols = list(fixed[p]) + free
                while len(cols) < 4:
                    cols.append(black)
                pals.append(cols)
            pal_lab = [lab(np.array([from555(c) for c in cols], dtype=np.float64)) for cols in pals]
            errs = np.array([[tile_err(t, pal_lab[p]) for p in range(8)] for t in range(len(tiles))])
            assign = np.argmin(errs, axis=1)
            total = float(errs[np.arange(len(tiles)), assign].sum())
            if prev is not None and total >= prev - 1e-6:
                break
            prev = total
        if best is None or total < best[0]:
            best = (total, [list(p) for p in pals], assign.copy())
    total, pals, assign = best

    # per pixel nearest colour in the tile's palette
    pal_lab = [lab(np.array([from555(c) for c in cols], dtype=np.float64)) for cols in pals]
    idx_img = np.zeros((LOGO_H, LOGO_W), dtype=np.int64)
    for ty in range(LOGO_H // 8):
        for tx in range(LOGO_W // 8):
            t = ty * (LOGO_W // 8) + tx
            blk = img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8].reshape(-1, 3)
            bl = lab(np.array([from555(tuple(c)) for c in blk], dtype=np.float64))
            idx_img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8] = np.argmin(
                np.sum((bl[:, None] - pal_lab[assign[t]][None]) ** 2, axis=2), axis=1).reshape(8, 8)
    ncol = len({key(c) for p in pals for c in p})
    npx = LOGO_W * LOGO_H
    print("gbc_genmenu: logo %d colours (incl. black), mean dE %.2f per pixel" % (ncol, (total / npx) ** 0.5))
    return img, pals, assign, idx_img


def tile_bytes(ix8):
    out = []
    for row in ix8:
        lo = hi = 0
        for x, v in enumerate(row):
            if v & 1:
                lo |= 0x80 >> x
            if v & 2:
                hi |= 0x80 >> x
        out += [lo, hi]
    return out


# ---- skull ----------------------------------------------------------------------------------------------------

def build_skull():
    frames = []
    colours = []
    for path in SKULL:
        im = Image.open(path).convert("RGBA")
        if im.size != (20, 19):
            die("%s is %dx%d, want 20x19" % (path, im.size[0], im.size[1]))
        px = [[im.getpixel((x, y)) for x in range(20)] for y in range(19)]
        frames.append(px)
        for row in px:
            for p in row:
                if p[3] and p[:3] not in colours:
                    colours.append(p[:3])
    if len(colours) > 6:
        die("skull has %d colours, two OBJ palettes hold 6" % len(colours))
    colours.sort(key=lambda c: sum(c))                 # darks in layer 0, lights in layer 1
    layer_cols = [colours[:3], colours[3:]]
    pals = [[(0, 0, 0)] + lc + [(0, 0, 0)] * (3 - len(lc)) for lc in layer_cols]
    tiles = []                                         # frame, layer, sprite (col, half), 2 tiles
    for px in frames:
        for li, lc in enumerate(layer_cols):
            for half in range(2):
                for col in range(3):
                    for sub in range(2):
                        rows = []
                        for r in range(8):
                            y = half * 16 + sub * 8 + r
                            row = []
                            for c in range(8):
                                x = col * 8 + c
                                v = 0
                                if x < 20 and y < 19 and px[y][x][3] and px[y][x][:3] in lc:
                                    v = lc.index(px[y][x][:3]) + 1
                                row.append(v)
                            rows.append(row)
                        tiles.append(tile_bytes(rows))
    return pals, tiles


# ---- text -----------------------------------------------------------------------------------------------------

def check_chars(s, glyphs, where):
    for ch in s:
        c = ord(ch)
        if ch != " " and not (32 <= c < 128 and any(glyphs.get(c, [0]))):
            die("%s: %r has no glyph in editor/font.json" % (where, ch))


def load_pages(name, glyphs):
    path = os.path.join(TEXT_DIR, name + ".txt")
    if not os.path.exists(path):
        die("missing %s" % path)
    raw = open(path, encoding="utf-8").read().replace("\r", "")
    pages = []
    cur = []
    for line in raw.split("\n"):
        if line.strip() == "^":
            pages.append(cur)
            cur = []
        else:
            cur.append(line.rstrip())
    pages.append(cur)
    out = []
    for n, pg in enumerate(pages):
        while pg and not pg[-1]:
            pg.pop()
        while pg and not pg[0]:
            pg.pop(0)
        if not pg:
            continue
        where = "%s.txt page %d" % (name, n + 1)
        if len(pg) > PAGE_ROWS:
            die("%s has %d lines (max %d)" % (where, len(pg), PAGE_ROWS))
        for ln in pg:
            if len(ln) > SCREEN_COLS:
                die("%s: %r is %d columns (max %d)" % (where, ln, len(ln), SCREEN_COLS))
            check_chars(ln, glyphs, where)
        out.append(pg)
    if not out:
        die("%s.txt has no pages" % name)
    return out


def asm_tiles(s):
    return ",".join("$%02X" % (ord(ch) + 96) for ch in s)


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    glyphs = gbc_hudfont.load_glyphs()
    img, pals, assign, idx_img = build_logo()

    # logo tiles (dedup; an all-colour-0 tile maps to the blank font tile 128)
    uniq = {}
    tdata = []
    tmap = []
    for ty in range(LOGO_H // 8):
        for tx in range(LOGO_W // 8):
            blk = idx_img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8]
            if not blk.any():
                tmap.append(FONT_TILE0)
                continue
            b = tuple(tile_bytes(blk.tolist()))
            if b not in uniq:
                uniq[b] = len(tdata)
                tdata.append(b)
            tmap.append(uniq[b])
    if len(tdata) > FONT_TILE0:
        die("logo needs %d tiles (max %d)" % (len(tdata), FONT_TILE0))

    # preview (2x)
    prev = Image.new("RGB", (LOGO_W, LOGO_H))
    for y in range(LOGO_H):
        for x in range(LOGO_W):
            t = (y // 8) * (LOGO_W // 8) + x // 8
            prev.putpixel((x, y), from555(pals[assign[t]][idx_img[y, x]]))
    prev.resize((LOGO_W * 2, LOGO_H * 2), Image.NEAREST).save(os.path.join(outdir, "menu_logo_preview.png"))

    spals, stiles = build_skull()

    o = ["; Generated by tools/gbc_genmenu.py - do not edit.",
         "DEF MENU_LOGO_COL EQU %d" % LOGO_COL,
         "DEF MENU_LOGO_ROWS EQU %d" % (LOGO_H // 8),
         "DEF MENU_LOGO_W EQU %d" % (LOGO_W // 8),
         "DEF MENU_FONT_TILE0 EQU %d" % FONT_TILE0,
         "DEF MENU_ROW0 EQU %d" % MENU_ROW0,
         "DEF MENU_SKULL_TILES EQU %d" % len(stiles),
         "DEF MENU_VOL_MENU EQU %d" % VOL_MENU,
         "DEF MENU_VOL_ITEM EQU %d" % VOL_ITEM,
         "DEF MENU_VOL_DIGITS EQU %d" % VOL_DIGITS,
         "DEF MENU_COUNT EQU %d" % len(MENUS),
         "",
         "MenuLogoTiles:"]
    for b in tdata:
        o.append("    db " + ",".join("$%02X" % v for v in b))
    o.append("MenuLogoTilesEnd:")
    o.append("MenuLogoMap:")
    for r in range(LOGO_H // 8):
        o.append("    db " + ",".join("$%02X" % v for v in tmap[r * 16:r * 16 + 16]))
    o.append("MenuLogoAttr:")
    for r in range(LOGO_H // 8):
        o.append("    db " + ",".join("$%02X" % int(assign[r * 16 + c]) for c in range(16)))
    o.append("MenuBgPal:")
    for p in pals:
        o.append("    dw " + ",".join("$%04X" % bgr555(c) for c in p))
    o.append("MenuObjPal:")
    for p in spals:
        o.append("    dw " + ",".join("$%04X" % bgr555(to555(c)) for c in p))
    o.append("MenuSkullTiles:")
    for t in stiles:
        o.append("    db " + ",".join("$%02X" % v for v in t))
    o.append("MenuSkullTilesEnd:")
    o.append("MenuFont:   ; 1bpp, ASCII 32..127")
    for code in range(32, 128):
        rows = glyphs.get(code, [0] * 8)
        o.append("    db " + ",".join("$%02X" % r for r in rows))

    # menus: nitems, text column, skull x (OAM, +8), first item row; title (row, col, len, tiles); items (len, tiles)
    o.append("MenuDefs:")
    for m in range(len(MENUS)):
        o.append("    dw MenuDef%d" % m)
    for m, (title, items) in enumerate(MENUS):
        width = max(len(s) for s in items)
        if SKULL_COLS + width > SCREEN_COLS:
            die("menu %d: %d-column label leaves no room for the skull" % (m, width))
        left = (SCREEN_COLS - SKULL_COLS - width) // 2
        first = MENU_ROW0 + (2 if title else 0)
        if first + 2 * (len(items) - 1) > 17:
            die("menu %d does not fit below the logo" % m)
        o.append("MenuDef%d:" % m)
        o.append("    db %d, %d, %d, %d" % (len(items), left + SKULL_COLS, left * 8 + 8, first))
        if title:
            check_chars(title, glyphs, "menu title")
            if len(title) > SCREEN_COLS:
                die("title %r too long" % title)
            o.append("    db %d, %d, %d, %s   ; %s" % (MENU_ROW0, (SCREEN_COLS - len(title)) // 2, len(title),
                                                     asm_tiles(title), title))
        else:
            o.append("    db 0")
        for s in items:
            check_chars(s, glyphs, "menu item")
            o.append("    db %d, %s   ; %s" % (len(s), asm_tiles(s), s))

    # pages: per text: db npages; dw page...; page: db nlines; per line: dw map offset, db len, tiles
    total = 0
    for name in PAGES:
        pages = load_pages(name, glyphs)
        lab_ = "Text" + name.capitalize()
        o.append("%s::" % lab_)
        o.append("    db %d" % len(pages))
        for k in range(len(pages)):
            o.append("    dw %s_%d" % (lab_, k))
        for k, pg in enumerate(pages):
            o.append("%s_%d:" % (lab_, k))
            o.append("    db %d" % len(pg))
            w = max(len(ln) for ln in pg)
            col = (SCREEN_COLS - w) // 2
            row = PAGE_ROW0 + (PAGE_ROWS - len(pg)) // 2
            for i, ln in enumerate(pg):
                off = (row + i) * 32 + col
                if ln:
                    o.append("    dw $%04X\n    db %d, %s" % (off, len(ln), asm_tiles(ln)))
                else:
                    o.append("    dw $%04X\n    db 0" % off)
        total += len(pages)
    open(os.path.join(outdir, "menu_gfx.inc"), "w", newline="\n").write("\n".join(o) + "\n")
    print("gbc_genmenu: %d logo tiles, %d skull tiles, %d text pages" % (len(tdata), len(stiles), total))


if __name__ == "__main__":
    main()
