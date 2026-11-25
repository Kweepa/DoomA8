// 96-glyph 8x8 UI font (ASCII 32..127). Pure data, no DOM.
// A glyph is 8 row bytes, MSB = leftmost pixel (same as tools/genuifont.py).

export const FONT_FIRST = 32;
export const FONT_COUNT = 96;
export const FONT_W = 8;
export const FONT_H = 8;
/** Overview / PNG sheet columns. */
export const FONT_COLS = 8;
/** Keep in sync with src/menu.asm SPACE_W / FONT_GAP. */
export const FONT_SPACE_W = 4;
export const FONT_GAP = 1;
export const FONT_FILE_VERSION = 1;

export function fontBlank() {
  return Array.from({ length: FONT_COUNT }, () => new Array(FONT_H).fill(0));
}

export function normalizeFont(raw) {
  const out = fontBlank();
  if (!Array.isArray(raw)) return out;
  for (let i = 0; i < FONT_COUNT; i++) {
    const g = raw[i];
    if (!Array.isArray(g)) continue;
    for (let y = 0; y < FONT_H; y++) out[i][y] = (Number(g[y]) | 0) & 0xff;
  }
  return out;
}

export function fontCharLabel(code) {
  if (code === 32) return "SP";
  if (code === 127) return "DEL";
  return String.fromCharCode(code);
}

export function fontHex2(n) {
  return (n & 0xff).toString(16).toUpperCase().padStart(2, "0");
}

export function fontGetPixel(rows, x, y) {
  return (rows[y] & (0x80 >> x)) !== 0;
}

/** Mutates rows. Returns true when the pixel changed. */
export function fontSetPixel(rows, x, y, on) {
  const bit = 0x80 >> x;
  const was = (rows[y] & bit) !== 0;
  if (was === on) return false;
  rows[y] = on ? rows[y] | bit : rows[y] & ~bit & 0xff;
  return true;
}

export function fontRowsEqual(a, b) {
  for (let y = 0; y < FONT_H; y++) if (a[y] !== b[y]) return false;
  return true;
}

function popcount8(n) {
  let c = 0;
  for (let x = n & 0xff; x; x &= x - 1) c++;
  return c;
}

/** lead/width match src/menu.asm font_scan: all-zero glyph = lead 0, width 0 (space). */
export function fontGlyphStats(rows) {
  let occ = 0;
  let pixels = 0;
  for (let y = 0; y < FONT_H; y++) {
    occ |= rows[y];
    pixels += popcount8(rows[y]);
  }
  if (!occ) return { pixels: 0, lead: 0, width: 0, empty: true };
  let first = 0;
  while (!(occ & (0x80 >> first))) first++;
  let last = 7;
  while (!(occ & (0x80 >> last))) last--;
  return { pixels, lead: first, width: last - first + 1, empty: false };
}

export function fontStats(font) {
  let nonEmpty = 0;
  let pixels = 0;
  let widest = 0;
  let touchLeft = 0;
  let touchRight = 0;
  for (const rows of font) {
    const s = fontGlyphStats(rows);
    if (s.empty) continue;
    nonEmpty++;
    pixels += s.pixels;
    if (s.width > widest) widest = s.width;
    if (s.lead === 0) touchLeft++;
    if (s.lead + s.width === FONT_W) touchRight++;
  }
  return { nonEmpty, pixels, widest, touchLeft, touchRight };
}

// ---- transforms (return new rows) ----

/** dx > 0 right, dy > 0 down. No wrap. */
export function fontShift(rows, dx, dy) {
  const out = new Array(FONT_H).fill(0);
  for (let y = 0; y < FONT_H; y++) {
    const sy = y - dy;
    if (sy < 0 || sy >= FONT_H) continue;
    const r = rows[sy] & 0xff;
    out[y] = dx >= 0 ? (r >> dx) & 0xff : (r << -dx) & 0xff;
  }
  return out;
}

function reverseBits8(n) {
  let r = 0;
  for (let i = 0; i < 8; i++) if (n & (1 << i)) r |= 0x80 >> i;
  return r;
}

export function fontFlipH(rows) {
  return rows.map(reverseBits8);
}

export function fontFlipV(rows) {
  return rows.slice().reverse();
}

export function fontInvert(rows) {
  return rows.map((r) => ~r & 0xff);
}

// ---- JSON file ----

/** One glyph per line so diffs stay readable. */
export function fontToJson(font) {
  const f = normalizeFont(font);
  const lines = f.map((rows, i) => {
    const code = FONT_FIRST + i;
    const ch = code === 127 ? "DEL" : String.fromCharCode(code);
    const hex = rows.map((r) => `"${fontHex2(r)}"`).join(", ");
    return `    { "code": ${code}, "char": ${JSON.stringify(ch)}, "rows": [${hex}] }`;
  });
  return (
    `{\n  "version": ${FONT_FILE_VERSION},\n  "firstChar": ${FONT_FIRST},\n  "glyphs": [\n` +
    `${lines.join(",\n")}\n  ]\n}\n`
  );
}

function parseRowByte(v) {
  if (typeof v === "string") {
    const n = parseInt(v.replace(/^(0x|\$)/i, ""), 16);
    return Number.isFinite(n) ? n & 0xff : 0;
  }
  return (Number(v) | 0) & 0xff;
}

/** Throws on malformed JSON. Entries are placed by `code`, falling back to position. */
export function fontFromJson(text) {
  const data = typeof text === "string" ? JSON.parse(text) : text;
  const out = fontBlank();
  const glyphs = Array.isArray(data?.glyphs) ? data.glyphs : [];
  glyphs.forEach((g, pos) => {
    const code = Number.isFinite(Number(g?.code)) ? Number(g.code) | 0 : FONT_FIRST + pos;
    const idx = code - FONT_FIRST;
    if (idx < 0 || idx >= FONT_COUNT || !Array.isArray(g?.rows)) return;
    for (let y = 0; y < FONT_H; y++) out[idx][y] = parseRowByte(g.rows[y]);
  });
  return out;
}

// ---- PNG sheet ----

/**
 * Slice an RGBA image ({width,height,data}) into 8x8 cells, row-major, first cell = ASCII 32.
 * Ink = luma > 128 (PIL "L" formula, as genuifont.py) and alpha >= 128; `invert` makes
 * opaque dark pixels the ink instead. Returns {error} or {glyphs:[{index,rows}], cols, rows, ignored}.
 */
export function fontFromImageData(img, opts = {}) {
  const { width, height, data } = img;
  if (!(width >= FONT_W) || !(height >= FONT_H) || width % FONT_W || height % FONT_H) {
    return { error: `Sheet is ${width}x${height}; both sides must be multiples of ${FONT_W}` };
  }
  const cols = width / FONT_W;
  const rowsN = height / FONT_H;
  const cells = cols * rowsN;
  const total = Math.min(FONT_COUNT, cells);
  const glyphs = [];
  for (let i = 0; i < total; i++) {
    const cx = (i % cols) * FONT_W;
    const cy = Math.floor(i / cols) * FONT_H;
    const rows = [];
    for (let y = 0; y < FONT_H; y++) {
      let b = 0;
      for (let x = 0; x < FONT_W; x++) {
        const p = ((cy + y) * width + cx + x) * 4;
        if (data[p + 3] < 128) continue;
        const luma = (data[p] * 19595 + data[p + 1] * 38470 + data[p + 2] * 7471 + 0x8000) >> 16;
        const on = opts.invert ? luma <= 128 : luma > 128;
        if (on) b |= 0x80 >> x;
      }
      rows.push(b);
    }
    glyphs.push({ index: i, rows });
  }
  return { glyphs, cols, rows: rowsN, ignored: cells - total };
}

/** RGBA sheet, white on black, 8 cols x 12 rows. */
export function fontToImageData(font) {
  const f = normalizeFont(font);
  const width = FONT_COLS * FONT_W;
  const height = (FONT_COUNT / FONT_COLS) * FONT_H;
  const data = new Uint8ClampedArray(width * height * 4);
  for (let i = 3; i < data.length; i += 4) data[i] = 255;
  f.forEach((rows, i) => {
    const cx = (i % FONT_COLS) * FONT_W;
    const cy = Math.floor(i / FONT_COLS) * FONT_H;
    for (let y = 0; y < FONT_H; y++) {
      for (let x = 0; x < FONT_W; x++) {
        if (!fontGetPixel(rows, x, y)) continue;
        const p = ((cy + y) * width + cx + x) * 4;
        data[p] = data[p + 1] = data[p + 2] = 255;
      }
    }
  });
  return { width, height, data };
}

// ---- text layout (mirrors src/menu.asm) ----

export function fontCodeFor(ch) {
  const c = ch.charCodeAt(0);
  return c >= FONT_FIRST && c < FONT_FIRST + FONT_COUNT ? c : FONT_FIRST;
}

/**
 * Proportional: glyph shifted left by its lead, advance = (width || SPACE_W) + GAP.
 * Mono: unshifted, advance 8. Returns {cells:[{x,code,shift}], width} in pixels; x is the pen
 * position, shift the leftward pixel offset to apply when drawing.
 */
export function fontLayoutText(font, text, proportional) {
  const cells = [];
  let x = 0;
  for (const ch of text) {
    const code = fontCodeFor(ch);
    const rows = font[code - FONT_FIRST];
    if (proportional) {
      const s = fontGlyphStats(rows);
      cells.push({ x, code, shift: s.lead });
      x += (s.width || FONT_SPACE_W) + FONT_GAP;
    } else {
      cells.push({ x, code, shift: 0 });
      x += FONT_W;
    }
  }
  return { cells, width: x };
}
