#!/usr/bin/env python3
"""GBC intermission data (Doom wi_stuff.c single-player screens): map, splat / arrow sprites, per-level stats.

Writes <outdir>/inter_gfx.inc and <outdir>/inter_preview.png.
  Map: ui/intermission/WIMAP0_160.png (160x128 = 20x16 tiles) on screen rows 2-17 (rows 0-1 hold the caption).
    Quantised to the 8 BG palettes (k-means over tiles as in gbc_genmenu.build_logo); palettes 6 / 7 keep
    black + white / red in colours 0 / 1 for the caption text and have 2 free colours for the map. Tiles deduplicated: bank 0 ids 0..255,
    the overflow in bank 1 ids 0.. (map attribute bit 3 selects the bank).
  Font: the HUD glyphs (editor/font.json), 2bpp colour 1, bank 1 ids 128..223 (tile = ASCII + 96, ASCII 32 = blank).
  Sprites (8x16 OBJ, bank 1 ids 224..): splat 16x16 (2 sprites), the two arrows 8x8 (padded), "you are here" 24x16
    (3 sprites). OBJ palettes 0 splat, 1 arrow, 2 text (3 colours + transparent each).
  Nodes: Doom lnodes[0] (E1M1..E1M8) scaled from 320x200 to the 160x128 map (x 0.5, y 0.64, +16 for the caption rows),
    patch offsets from the lumps (WISPLAT 28x22 at 15,11; WIURH0 60x15 at -2,15 = text right of the node;
    WIURH1 62,15 = text left). Doom picks WIURH0 unless it runs off the right edge, else WIURH1.
  LevelStats: per level kills total, items total (pickups, type < TH_LIGHTPOST), par seconds (Doom E1 pars).
"""
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import genmap as gm  # noqa: E402
import gbc_genmap as gmap  # noqa: E402
import gbc_genmenu as gmenu  # noqa: E402
import gbc_hudfont  # noqa: E402
import gbc_world as gw  # noqa: E402

ROOT = os.path.dirname(HERE)
UI = os.path.join(ROOT, "ui", "intermission")

MAP_W, MAP_H = 160, 128
MAP_ROW0 = 2
NPAL_MAP = 8                             # palettes 6 / 7 double as the text palettes (colours 0 / 1 fixed)
RED555 = (28, 2, 2)                      # caption red
WHITE555 = (31, 31, 31)
RESTARTS = 24
FONT_ID0 = 128                           # bank 1 font tile of ASCII 32
OBJ_ID0 = 224                            # bank 1 first OBJ tile

# Doom wi_stuff.c lnodes[0] (episode 1), E1M1..E1M8 (the ninth is the secret level)
NODES = [(185, 164), (148, 143), (69, 122), (209, 102), (116, 89), (166, 55), (71, 56), (135, 29)]
# Doom g_game.c pars[1][1..8], seconds. Editor data replaces this later.
PARS = [30, 75, 120, 90, 165, 180, 180, 30]
SX, SY = 0.5, 0.64                       # 320x200 -> 160x128
SPLAT_OFF = (15, 11)                     # lump offsets, 28x22 patch
URH_OFF = [(-2, 15), (62, 15)]           # WIURH0 / WIURH1, 60x15 patch
ARROW_W, TEXT_W = 8, 24
TH_LIGHTPOST_DEFAULT = 17
NBLD_MAX = 20                            # building overlay sprites (OAM: 4 arrow / text + 14 splats + these <= 40)
BLD_ERR = 3.0                            # a pixel is a candidate when the map's colour is this far (Lab dE) off
BLD_GAIN = 0.5                           # ... and the sprite colour is at least this much closer
BLD_WIN_W, BLD_WIN_H = 24, 16            # window per node: 3 sprites of 8x16
BLD_WEIGHT = 1.0                         # map tiles around the nodes weigh this much in the BG palette fit
OBJ_PAL_BLD0 = 3                         # OBJ palettes 3..7


def die(msg):
    raise SystemExit("gbc_genintermission: " + msg)


def hexl(vals):
    return ",".join("$%02X" % v for v in vals)


def cluster_palettes(unit_lab, unit_cnt, npal, fixed, seed, ncol=4):
    """Assign units (each: Lab colours + pixel counts) to npal palettes of ncol colours; palette p starts with the
    colours fixed[p]. k-means over units, colours per palette by weighted k-means, several restarts, lowest error
    kept. Returns (palettes of RGB555 tuples, assignment per unit, total squared Lab error)."""
    cands555, cands_lab = gmenu.all555_lab()
    n = len(unit_lab)
    fixed_lab = [gmenu.lab(np.array([gmenu.from555(c) for c in f], dtype=np.float64)) if f else np.zeros((0, 3))
                 for f in fixed]

    def err(t, pl):
        d = np.min(np.sum((unit_lab[t][:, None] - pl[None]) ** 2, axis=2), axis=1)
        return float((d * unit_cnt[t]).sum())

    best = None
    for rs in range(RESTARTS):
        rng = np.random.default_rng(seed + rs)
        means = np.array([(tl * c[:, None]).sum(0) / c.sum() for tl, c in zip(unit_lab, unit_cnt)])
        seeds = means[rng.choice(n, min(npal, n), replace=n < npal)]
        assign = np.argmin(np.sum((means[:, None] - seeds[None]) ** 2, axis=2), axis=1)
        prev = None
        for _ in range(12):
            pals = []
            for p in range(npal):
                mem = [t for t in range(n) if assign[t] == p]
                if mem:
                    pl = np.concatenate([unit_lab[t] for t in mem])
                    w = np.concatenate([unit_cnt[t] for t in mem]).astype(np.float64)
                else:
                    pl, w = np.zeros((0, 3)), np.zeros(0)
                idx = gmenu.fit_colours(pl, w, fixed_lab[p], ncol - len(fixed[p]), rng, cands_lab)
                cols = list(fixed[p]) + ([tuple(int(v) for v in cands555[i]) for i in idx] if len(idx) else [])
                while len(cols) < ncol:
                    cols.append((0, 0, 0))
                pals.append(cols)
            pal_lab = [gmenu.lab(np.array([gmenu.from555(c) for c in cols], dtype=np.float64)) for cols in pals]
            errs = np.array([[err(t, pal_lab[p]) for p in range(npal)] for t in range(n)])
            assign = np.argmin(errs, axis=1)
            total = float(errs[np.arange(n), assign].sum())
            if prev is not None and total >= prev - 1e-6:
                break
            prev = total
        if best is None or total < best[0]:
            best = (total, [list(p) for p in pals], assign.copy())
    return best[1], best[2], best[0]


# ---- map -------------------------------------------------------------------------------------------------------

def build_map():
    im = Image.open(os.path.join(UI, "WIMAP0_160.png")).convert("RGB")
    if im.size != (MAP_W, MAP_H):
        die("WIMAP0_160.png is %dx%d, want %dx%d" % (im.size[0], im.size[1], MAP_W, MAP_H))
    img = np.array([[gmenu.to555(im.getpixel((x, y))) for x in range(MAP_W)] for y in range(MAP_H)], dtype=np.int64)
    cands555, cands_lab = gmenu.all555_lab()
    key = lambda c: (c[0] << 10) | (c[1] << 5) | c[2]   # noqa: E731
    tw, th = MAP_W // 8, MAP_H // 8
    tiles = []
    for ty in range(th):
        for tx in range(tw):
            blk = img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8].reshape(-1, 3)
            u, cnt = np.unique(blk, axis=0, return_counts=True)
            tiles.append((u, cnt))
    tile_lab = [gmenu.lab(np.array([gmenu.from555(tuple(c)) for c in u], dtype=np.float64)) for u, _ in tiles]
    fixed = [[]] * 6 + [[(0, 0, 0), WHITE555], [(0, 0, 0), RED555]]
    # tiles that hold a building (around the nodes) count BLD_WEIGHT times: the palettes go to the greys / greens /
    # oranges first and the terrain makes do with what is left
    wt = np.ones(tw * th)
    for (nx, ny) in NODES:
        cx, cy = nx * SX, ny * SY
        for ty in range(th):
            for tx in range(tw):
                if abs(tx * 8 + 4 - cx) <= BLD_WIN_W // 2 + 4 and abs(ty * 8 + 4 - cy) <= BLD_WIN_H // 2 + 4:
                    wt[ty * tw + tx] = BLD_WEIGHT
    pals, assign, total = cluster_palettes(tile_lab, [t[1] * wt[i] for i, t in enumerate(tiles)], NPAL_MAP, fixed,
                                           seed=4321)
    pal_lab = [gmenu.lab(np.array([gmenu.from555(c) for c in cols], dtype=np.float64)) for cols in pals]
    idx_img = np.zeros((MAP_H, MAP_W), dtype=np.int64)
    for ty in range(th):
        for tx in range(tw):
            t = ty * tw + tx
            blk = img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8].reshape(-1, 3)
            bl = gmenu.lab(np.array([gmenu.from555(tuple(c)) for c in blk], dtype=np.float64))
            idx_img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8] = np.argmin(
                np.sum((bl[:, None] - pal_lab[assign[t]][None]) ** 2, axis=2), axis=1).reshape(8, 8)
    ncol = len({key(c) for p in pals for c in p})
    print("gbc_genintermission: map %d colours" % ncol)
    return pals, assign, idx_img, img


# ---- sprites ---------------------------------------------------------------------------------------------------

def load_rgba(name, size):
    im = Image.open(os.path.join(UI, name)).convert("RGBA")
    if im.size != size:
        die("%s is %dx%d, want %dx%d" % (name, im.size[0], im.size[1], size[0], size[1]))
    return im


def quantise_obj(images, ncol=3):
    """Shared palette (ncol colours) for the opaque pixels of all images -> list of 555 colours."""
    pix = {}
    for im in images:
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                p = im.getpixel((x, y))
                if p[3] >= 128:
                    c = gmenu.to555(p[:3])
                    pix[c] = pix.get(c, 0) + 1
    cols = list(pix)
    if len(cols) <= ncol:
        return cols + [(0, 0, 0)] * (ncol - len(cols))
    cands555, cands_lab = gmenu.all555_lab()
    pl = gmenu.lab(np.array([gmenu.from555(c) for c in cols], dtype=np.float64))
    w = np.array([pix[c] for c in cols], dtype=np.float64)
    best = None
    for rs in range(RESTARTS):
        rng = np.random.default_rng(99 + rs)
        idx = gmenu.fit_colours(pl, w, np.zeros((0, 3)), ncol, rng, cands_lab)
        pal = [tuple(int(v) for v in cands555[i]) for i in idx]
        pal_lab = gmenu.lab(np.array([gmenu.from555(c) for c in pal], dtype=np.float64))
        err = float((np.min(np.sum((pl[:, None] - pal_lab[None]) ** 2, axis=2), axis=1) * w).sum())
        if best is None or err < best[0]:
            best = (err, pal)
    return best[1]


def obj_index(im, pal):
    """Per pixel 0 (transparent) / 1..3."""
    pal_lab = gmenu.lab(np.array([gmenu.from555(c) for c in pal], dtype=np.float64))
    out = np.zeros((im.size[1], im.size[0]), dtype=np.int64)
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            p = im.getpixel((x, y))
            if p[3] >= 128:
                lb = gmenu.lab(np.array([gmenu.from555(gmenu.to555(p[:3]))], dtype=np.float64))
                out[y, x] = 1 + int(np.argmin(np.sum((pal_lab - lb) ** 2, axis=1)))
    return out


def sprite_tiles(idx, x0, h=16):
    """8x16 OBJ sprite (two tiles, top then bottom) cut from idx at column x0; missing rows are transparent."""
    out = []
    for half in range(2):
        rows = []
        for r in range(8):
            y = half * 8 + r
            rows.append([int(idx[y, x0 + c]) if y < idx.shape[0] and x0 + c < idx.shape[1] else 0 for c in range(8)])
        out.append(gmenu.tile_bytes(rows))
    return out


# ---- building overlay ------------------------------------------------------------------------------------------

def build_buildings(orig555, qimg555, nodes_map):
    """Sprites over the buildings, found from the node (splat) positions: per node a 24x16 window (3 sprites of 8x16,
    the vertical offset with the most quantisation error), then the NBLD_MAX sprites with the most error. A sprite
    pixel is opaque only where its (3 colour, 5 shared palettes) colour beats the BG tile's colour.
    Returns [(map x, map y, [16 rows of 8 values 0..3], palette index 0..4)], the 5 palettes, per-pixel error."""
    h, w = orig555.shape[:2]
    lo = gmenu.lab(np.array([[gmenu.from555(tuple(c)) for c in row] for row in orig555], dtype=np.float64))
    lq = gmenu.lab(np.array([[gmenu.from555(tuple(c)) for c in row] for row in qimg555], dtype=np.float64))
    err = np.linalg.norm(lo - lq, axis=2)
    cand = []                                      # (score, x, y)
    for (cx, cy) in nodes_map:
        best = None
        for dy in range(-12, -3):
            y0 = min(max(int(round(cy)) + dy, 0), h - BLD_WIN_H)
            x0 = min(max(int(round(cx)) - BLD_WIN_W // 2, 0), w - BLD_WIN_W)
            sc = float(np.where(err[y0:y0 + BLD_WIN_H, x0:x0 + BLD_WIN_W] > BLD_ERR,
                                err[y0:y0 + BLD_WIN_H, x0:x0 + BLD_WIN_W], 0).sum())
            if best is None or sc > best[0]:
                best = (sc, x0, y0)
        _, x0, y0 = best
        for k in range(BLD_WIN_W // 8):
            xs = x0 + 8 * k
            m = err[y0:y0 + 16, xs:xs + 8]
            cand.append((float(np.where(m > BLD_ERR, m, 0).sum()), xs, y0))
    chosen = sorted(sorted(cand, reverse=True)[:NBLD_MAX], key=lambda c: (c[2], c[1]))
    chosen = [c for c in chosen if c[0] > 0]
    units, cnts = [], []
    for (_, xs, y0) in chosen:
        px = {}
        for y in range(y0, y0 + 16):
            for x in range(xs, xs + 8):
                if err[y, x] > BLD_ERR:
                    c = tuple(int(v) for v in orig555[y, x])
                    px[c] = px.get(c, 0) + 1
        cols = list(px)
        units.append(gmenu.lab(np.array([gmenu.from555(c) for c in cols], dtype=np.float64)))
        cnts.append(np.array([px[c] for c in cols], dtype=np.float64))
    pals, assign, _ = cluster_palettes(units, cnts, 5, [[]] * 5, seed=777, ncol=3)
    pal_lab = [gmenu.lab(np.array([gmenu.from555(c) for c in cols], dtype=np.float64)) for cols in pals]
    out = []
    for n, (_, xs, y0) in enumerate(chosen):
        rows = []
        pl = pal_lab[assign[n]]
        for y in range(y0, y0 + 16):
            row = []
            for x in range(xs, xs + 8):
                v = 0
                if err[y, x] > BLD_ERR:
                    d = np.linalg.norm(pl - lo[y, x], axis=1)
                    if d.min() + BLD_GAIN < err[y, x]:
                        v = 1 + int(np.argmin(d))
                row.append(v)
            rows.append(row)
        if any(any(r) for r in rows):
            out.append((xs, y0, rows, int(assign[n])))
    print("gbc_genintermission: %d building sprites (of %d candidates), mean error in the windows %.2f dE" % (
        len(out), len(cand), float(np.mean([err[y0:y0 + 16, xs:xs + 8].mean() for (xs, y0, _, _) in out]))))
    return out, pals


# ---- level stats -----------------------------------------------------------------------------------------------

def th_lightpost(outdir):
    try:
        t = open(os.path.join(outdir, "a8const.inc")).read()
        return int(re.search(r"DEF TH_LIGHTPOST EQU (\d+)", t).group(1))
    except (OSError, AttributeError):
        return TH_LIGHTPOST_DEFAULT


def level_stats(outdir):
    lp = th_lightpost(outdir)
    out = []
    for key in gm.LEVEL_NAMES:
        lv = gm.load_level(key)
        if not any(o.get("kind") == "spawn" for o in (lv.get("objects") or [])):
            continue
        payload = gm.cook_one(lv, key)
        L = gw.Level(payload)
        kills = payload[7]
        items = sum(1 for t in range(payload[9]) if L.f("th_type", t) < lp)
        out.append((min(kills, 255), min(items, 255)))
    return out


# ---- main ------------------------------------------------------------------------------------------------------

def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    glyphs = gbc_hudfont.load_glyphs()
    pals, assign, idx_img, orig555 = build_map()
    tw, th = MAP_W // 8, MAP_H // 8

    # ---- map tiles: dedup, bank 0 ids 0..255, overflow bank 1 ids 0..
    uniq, tdata, tmap = {}, [], []
    for ty in range(th):
        for tx in range(tw):
            b = tuple(gmenu.tile_bytes(idx_img[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8].tolist()))
            if b not in uniq:
                uniq[b] = len(tdata)
                tdata.append(b)
            tmap.append(uniq[b])
    n0 = min(len(tdata), 256)
    spill = tdata[256:]
    if len(spill) > FONT_ID0:
        die("map needs %d tiles (max %d)" % (len(tdata), 256 + FONT_ID0))
    mapid = [t if t < 256 else t - 256 for t in tmap]
    mapattr = [int(assign[i]) | (8 if tmap[i] >= 256 else 0) for i in range(tw * th)]

    # ---- sprites
    splat = load_rgba("WISPLAT_160.png", (16, 16))
    urh = [load_rgba("WIURH0_160.png", (8, 8)), load_rgba("WIURH1_160.png", (8, 8))]
    urht = load_rgba("WIURHT_160.png", (24, 16))
    pal_splat = quantise_obj([splat])
    pal_arrow = quantise_obj(urh)
    pal_text = quantise_obj([urht])
    i_splat = obj_index(splat, pal_splat)
    i_arrow = [obj_index(a, pal_arrow) for a in urh]
    i_text = obj_index(urht, pal_text)
    otiles = []                                  # ids OBJ_ID0 ..
    otiles += sprite_tiles(i_splat, 0) + sprite_tiles(i_splat, 8)           # 224..227
    otiles += sprite_tiles(i_arrow[0], 0) + sprite_tiles(i_arrow[1], 0)     # 228..231
    for c in range(3):
        otiles += sprite_tiles(i_text, c * 8)                               # 232..237
    T_SPLAT, T_ARROW0, T_ARROW1, T_TEXT = OBJ_ID0, OBJ_ID0 + 4, OBJ_ID0 + 6, OBJ_ID0 + 8

    # ---- palettes
    bgpals = pals                                        # 6 / 7 carry the text colours in 0 / 1

    # ---- building overlay sprites (bank 1 tile ids after the map's overflow, OBJ palettes 3..7)
    qimg = np.array([[pals[assign[(y // 8) * tw + x // 8]][idx_img[y, x]]
                      for x in range(MAP_W)] for y in range(MAP_H)], dtype=np.int64)
    blds, bld_pals = build_buildings(orig555, qimg, [(nx * SX, ny * SY) for (nx, ny) in NODES])
    bld_id0 = (len(spill) + 1) & ~1
    if bld_id0 + 2 * len(blds) > FONT_ID0:
        die("building sprites need tiles up to %d (font at %d)" % (bld_id0 + 2 * len(blds), FONT_ID0))
    bld_tiles = []
    for (xs, y0, rows, pi) in blds:
        for half in range(2):
            bld_tiles.append(gmenu.tile_bytes(rows[half * 8:half * 8 + 8]))

    # ---- nodes -> sprite placement (OAM coordinates: x + 8, y + 16)
    nodes = []
    for (nx, ny) in NODES:
        cx, cy = nx * SX, ny * SY + MAP_ROW0 * 8
        splat_xy = (int(round(cx - 8)), int(round(cy - 8)))
        # Doom WI_drawOnLnode: the patch sits at (x - leftoffset, y - topoffset); WIURH0 (text right of the arrow)
        # unless that runs off the right edge, then WIURH1 (text left).
        ay = int(round(cy)) - 8                      # arrow's bottom edge on the node, as the 15 px patch's
        left0 = int(round((nx - URH_OFF[0][0]) * SX))
        if left0 + ARROW_W + TEXT_W < 160:
            side = 0
            ax = left0
            tx_ = ax + ARROW_W
        else:
            side = 1
            ax = int(round((nx - URH_OFF[1][0]) * SX)) + TEXT_W
            tx_ = ax - TEXT_W
        ty_ = ay - 2                                 # 11 text rows centred on the 8 px arrow
        nodes.append((splat_xy, side, (ax, ay), (tx_, ty_)))

    stats = level_stats(outdir)
    if len(stats) != len(NODES):
        die("%d levels with a spawn, %d nodes" % (len(stats), len(NODES)))

    # ---- preview: map with every splat, arrow + text at node 3
    prev = Image.new("RGB", (160, 144))
    for y in range(MAP_H):
        for x in range(MAP_W):
            prev.putpixel((x, y + MAP_ROW0 * 8), gmenu.from555(pals[assign[(y // 8) * tw + x // 8]][idx_img[y, x]]))

    def blit(idx, pal, x0, y0, px=None):
        for y in range(idx.shape[0]):
            for x in range(idx.shape[1]):
                if idx[y, x] and 0 <= x0 + x < 160 and 0 <= y0 + y < 144:
                    prev.putpixel((x0 + x, y0 + y), gmenu.from555(pal[idx[y, x] - 1]))

    for (sxy, _s, _a, _t) in nodes[:7]:
        blit(i_splat, pal_splat, sxy[0], sxy[1])
    _sxy, side, (ax, ay), (tx_, ty_) = nodes[3]
    blit(i_arrow[side], pal_arrow, ax, ay)
    blit(i_text, pal_text, tx_, ty_)
    for (xs, y0, rows, pi) in blds:
        blit(np.array(rows), bld_pals[pi], xs, y0 + MAP_ROW0 * 8)
    prev.resize((480, 432), Image.NEAREST).save(os.path.join(outdir, "inter_preview.png"))

    # ---- sprites per scanline, worst case over the screens (finished level 0..6: its splats + the next arrow / text)
    worst = 0
    for last in range(len(NODES) - 1):
        spr = [(sxy[1] + 16 + 16 * 0, 16) for (sxy, *_r) in nodes[:last + 1] for _h in (0, 1)]
        spr += [(nodes[last + 1][2][1] + 16, 16)] + [(nodes[last + 1][3][1] + 16, 16)] * 3
        spr += [(y0 + MAP_ROW0 * 8 + 16, 16) for (_x, y0, _r, _p) in blds]
        for line in range(16, 160):
            worst = max(worst, sum(1 for (y, h) in spr if y <= line < y + h))
    print("gbc_genintermission: at most %d sprites on a scanline (hardware draws 10), %d OAM entries" % (
        worst, 4 + 2 * (len(NODES) - 1) + len(blds)))
    if worst > 10:
        print("gbc_genintermission: WARNING: more than 10 sprites on a line, the lowest priority ones drop out")

    # ---- output
    o = ["; Generated by tools/gbc_genintermission.py - do not edit.",
         "DEF INTER_FONT_ID0 EQU %d" % FONT_ID0,
         "DEF INTER_OBJ_ID0 EQU %d" % OBJ_ID0,
         "DEF INTER_N_BANK0 EQU %d" % n0,
         "DEF INTER_N_SPILL EQU %d" % len(spill),
         "DEF INTER_N_OBJ EQU %d" % len(otiles),
         "DEF INTER_NLEVELS EQU %d" % len(NODES),
         "DEF INTER_NBLD EQU %d" % len(blds),
         "DEF INTER_BLD_ID0 EQU %d" % bld_id0,
         "DEF INTER_N_BLDT EQU %d" % len(bld_tiles),
         "DEF INTER_MAP_ROW0 EQU %d" % MAP_ROW0,
         "DEF INTER_T_ARROW0 EQU %d" % T_ARROW0,
         "DEF INTER_T_ARROW1 EQU %d" % T_ARROW1,
         "DEF INTER_T_TEXT EQU %d" % T_TEXT,
         "DEF INTER_T_SPLAT EQU %d" % T_SPLAT,
         "", "InterTiles0:"]
    for b in tdata[:256]:
        o.append("    db " + hexl(b))
    o.append("InterTiles1:")
    for b in spill:
        o.append("    db " + hexl(b))
    o.append("InterObjTiles:")
    for b in otiles:
        o.append("    db " + hexl(b))
    o.append("InterFont:   ; 2bpp, colour 1, ASCII 32..127")
    for code in range(32, 128):
        rows = glyphs.get(code, [0] * 8)
        o.append("    db " + hexl([v for r in rows for v in (r, 0)]))
    o.append("InterMapId:")
    for r in range(th):
        o.append("    db " + hexl(mapid[r * tw:(r + 1) * tw]))
    o.append("InterMapAttr:")
    for r in range(th):
        o.append("    db " + hexl(mapattr[r * tw:(r + 1) * tw]))
    o.append("InterBgPal:")
    for p in bgpals:
        o.append("    dw " + ",".join("$%04X" % gmenu.bgr555(c) for c in p))
    o.append("InterObjPal:")
    for p in [pal_splat, pal_arrow, pal_text] + list(bld_pals) + [[(0, 0, 0)] * 3] * (5 - len(bld_pals)):
        o.append("    dw $0000," + ",".join("$%04X" % gmenu.bgr555(c) for c in p))
    o.append("InterBldTiles:")
    for b in bld_tiles:
        o.append("    db " + hexl(b))
    o.append("; building overlay OAM entries: y, x, tile, attribute (OBJ palette 3.., bank 1)")
    o.append("InterBld:")
    for n, (xs, y0, rows, pi) in enumerate(blds):
        o.append("    db %d,%d,%d,%d" % (y0 + MAP_ROW0 * 8 + 16, xs + 8, bld_id0 + 2 * n, (OBJ_PAL_BLD0 + pi) | 8))
    o.append("; per level: splat y, x (OAM), arrow tile, arrow y, x, text y, x")
    o.append("InterNodes:")
    for (sxy, side, (ax, ay), (tx_, ty_)) in nodes:
        o.append("    db %d,%d, %d, %d,%d, %d,%d" % (sxy[1] + 16, sxy[0] + 8, T_ARROW0 if side == 0 else T_ARROW1,
                                                      ay + 16, ax + 8, ty_ + 16, tx_ + 8))
    o.append("; per level: kills total, items total, par seconds")
    o.append("InterStats:")
    for i, (k, it) in enumerate(stats):
        o.append("    db %d,%d,%d" % (k, it, PARS[i]))
    open(os.path.join(outdir, "inter_gfx.inc"), "w", newline="\n").write("\n".join(o) + "\n")
    print("gbc_genintermission: %d+%d map tiles, %d OBJ tiles; kills/items %s" % (
        n0, len(spill), len(otiles), ",".join("%d/%d" % s for s in stats)))


if __name__ == "__main__":
    main()
