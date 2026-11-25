// Game Boy Color sprite art (weapons, flashes, splats; blood vs spark is a colour choice in game). Pure data, no DOM.
// One bit per pixel, 1:1 with the GBC screen. rows[y] is a string of "." and "#" (w chars).
// Stored in editor/doom64.json ("gbSprites"); tools/gbc_genwpn.py builds the GBC art from it directly.
// OAM is 8x16: the generator slices every frame into 8-wide x 16-tall cells and skips empty ones,
// so width/height are free (min 8) and the editor draws the 8x16 cell grid.

export const GBS_W_MIN = 8;
export const GBS_W_MAX = 64;
export const GBS_H_MIN = 8;
export const GBS_H_MAX = 48;
export const GBS_CELL_W = 8;
export const GBS_CELL_H = 16;

/**
 * Catalogue. id matches the frame names in tools/gbc_genwpn.py. w/h = default and imported size.
 * cellLimit: gbc_genwpn.py asserts (body frames <= 16 cells, flashes <= 7); null = not wired yet.
 */
export const GBS_DEFS = [
  { id: "pistol_lines", name: "Pistol", group: "Weapon", w: 24, h: 32, cellLimit: 16 },
  { id: "shotgun_lines", name: "Shotgun", group: "Weapon", w: 40, h: 32, cellLimit: 16 },
  { id: "shotgun_cock_lines", name: "Shotgun (cock)", group: "Weapon", w: 24, h: 42, cellLimit: 16 },
  { id: "chaingun_a_lines", name: "Chaingun A", group: "Weapon", w: 48, h: 32, cellLimit: 16 },
  { id: "chaingun_b_lines", name: "Chaingun B", group: "Weapon", w: 48, h: 32, cellLimit: 16 },
  { id: "rocketlauncher_lines", name: "Rocket launcher", group: "Weapon", w: 48, h: 32, cellLimit: 16 },
  { id: "chainsaw_lines", name: "Chainsaw", group: "Weapon", w: 64, h: 40, cellLimit: 16 },
  { id: "fist_righthand_lines", name: "Fist (idle)", group: "Weapon", w: 56, h: 21, cellLimit: 16 },
  { id: "fist_lefthand_lines", name: "Fist (punch)", group: "Weapon", w: 64, h: 32, cellLimit: 16 },
  { id: "muzzle_flash", name: "Muzzle flash", group: "Flash", w: 24, h: 21, cellLimit: 7 },
  { id: "splat_0", name: "Splat 0 (near)", group: "Splat", w: 24, h: 21, cellLimit: null },
  { id: "splat_1", name: "Splat 1", group: "Splat", w: 24, h: 21, cellLimit: null },
  { id: "splat_2", name: "Splat 2 (far)", group: "Splat", w: 24, h: 21, cellLimit: null },
];

export function gbsDef(id) {
  return GBS_DEFS.find((d) => d.id === id) || null;
}

export function gbsBlankRows(w, h) {
  return Array.from({ length: h }, () => ".".repeat(w));
}

export function gbsBlank(def) {
  return { id: def.id, w: def.w, h: def.h, rows: gbsBlankRows(def.w, def.h) };
}

function clampInt(v, min, max, fallback) {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function cleanRows(raw, w, h) {
  const out = gbsBlankRows(w, h);
  if (!Array.isArray(raw)) return out;
  for (let y = 0; y < h; y++) {
    const r = typeof raw[y] === "string" ? raw[y] : "";
    let s = "";
    for (let x = 0; x < w; x++) s += r[x] === "#" ? "#" : ".";
    out[y] = s;
  }
  return out;
}

/** Always returns every catalogue sprite, in catalogue order. */
export function normalizeGbSprites(raw) {
  const list = Array.isArray(raw) ? raw : [];
  return GBS_DEFS.map((def) => {
    const r = list.find((s) => s && s.id === def.id);
    if (!r) return gbsBlank(def);
    const w = clampInt(r.w, GBS_W_MIN, GBS_W_MAX, def.w);
    const h = clampInt(r.h, GBS_H_MIN, GBS_H_MAX, def.h);
    return { id: def.id, w, h, rows: cleanRows(r.rows, w, h) };
  });
}

export function gbsGet(sp, x, y) {
  if (x < 0 || y < 0 || x >= sp.w || y >= sp.h) return false;
  return sp.rows[y][x] === "#";
}

/** Mutates. Returns true when the pixel changed. */
export function gbsSet(sp, x, y, on) {
  if (x < 0 || y < 0 || x >= sp.w || y >= sp.h) return false;
  if (gbsGet(sp, x, y) === on) return false;
  const r = sp.rows[y];
  sp.rows[y] = r.slice(0, x) + (on ? "#" : ".") + r.slice(x + 1);
  return true;
}

export function gbsRowsEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

/** Number of non-empty 8x16 OAM cells, exactly as gbc_genwpn.frame_cells counts them. */
export function gbsCellCount(sp) {
  let n = 0;
  for (let cy = 0; cy < sp.h; cy += GBS_CELL_H) {
    for (let cx = 0; cx < sp.w; cx += GBS_CELL_W) {
      if (gbsCellUsed(sp, cx, cy)) n++;
    }
  }
  return n;
}

export function gbsCellUsed(sp, cx, cy) {
  for (let y = cy; y < Math.min(sp.h, cy + GBS_CELL_H); y++) {
    for (let x = cx; x < Math.min(sp.w, cx + GBS_CELL_W); x++) {
      if (sp.rows[y][x] === "#") return true;
    }
  }
  return false;
}

/** New rows, content moved by (dx, dy); anything pushed off the edge is lost. */
export function gbsShiftRows(sp, dx, dy) {
  const out = gbsBlankRows(sp.w, sp.h);
  for (let y = 0; y < sp.h; y++) {
    const sy = y - dy;
    if (sy < 0 || sy >= sp.h) continue;
    let s = "";
    for (let x = 0; x < sp.w; x++) {
      const sx = x - dx;
      s += sx >= 0 && sx < sp.w ? sp.rows[sy][sx] : ".";
    }
    out[y] = s;
  }
  return out;
}

export function gbsFlipHRows(sp) {
  return sp.rows.map((r) => r.split("").reverse().join(""));
}

export function gbsFlipVRows(sp) {
  return sp.rows.slice().reverse();
}

export function gbsInvertRows(sp) {
  return sp.rows.map((r) => r.replace(/[.#]/g, (c) => (c === "#" ? "." : "#")));
}

/**
 * Resize to (w, h), anchored top-left (the generator and wpn.asm place art from its top-left, so
 * growing or shrinking never moves existing pixels). Returns a new sprite object.
 */
export function gbsResize(sp, w, h) {
  const rows = gbsBlankRows(w, h);
  for (let y = 0; y < Math.min(h, sp.h); y++) {
    let s = "";
    for (let x = 0; x < w; x++) s += x < sp.w ? sp.rows[y][x] : ".";
    rows[y] = s;
  }
  return { id: sp.id, w, h, rows };
}
