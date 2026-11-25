import {
  FONT_COUNT,
  FONT_FIRST,
  FONT_H,
  FONT_W,
  fontCharLabel,
  fontFlipH,
  fontFlipV,
  fontFromImageData,
  fontGetPixel,
  fontGlyphStats,
  fontHex2,
  fontInvert,
  fontLayoutText,
  fontRowsEqual,
  fontSetPixel,
  fontShift,
  fontToImageData,
} from "./fontModel.js";

const FONT_INK = "#e8e4d8";
const FONT_BG = "#0a0a0c";
const FONT_GRID = "rgba(255, 255, 255, 0.09)";
const FONT_CELL_PX = 32;
const FONT_SLOT_COUNT = 4;
const FONT_DRAG_THRESHOLD = 4;
const FONT_SAMPLE = "DoomA8: the quick brown fox\njumps over the lazy dog 0123456789 !?";

function fontEl(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

/**
 * Font tab: overview of 96 glyphs (left), four 8x8 workspace grids (center), live text preview.
 * Glyph data lives in doc.font; this view reads it through opts.getFont() and never caches it.
 * opts: left, panel (DOM roots), getFont, beginUndo, endUndo, markDirty,
 *       onChange (inspector needs a rebuild), onUiChange (slots/active changed), onStatus.
 */
export class FontView {
  constructor(opts) {
    this.opts = opts;
    this.enabled = false;
    this.slots = new Array(FONT_SLOT_COUNT).fill(null);
    this.active = 0;
    this.clip = null;
    this.stroke = null;
    this.drag = null;
    this.proportional = true;
    this.sample = FONT_SAMPLE;
    this.cells = [];
    this.slotEls = [];
    this.#buildOverview(opts.left);
    this.#buildPanel(opts.panel);
  }

  // ---- state ----

  getState() {
    return { slots: this.slots.slice(), active: this.active };
  }

  setState(s) {
    const slots = new Array(FONT_SLOT_COUNT).fill(null);
    if (Array.isArray(s?.slots)) {
      for (let i = 0; i < FONT_SLOT_COUNT; i++) {
        const c = s.slots[i];
        if (Number.isInteger(c) && c >= FONT_FIRST && c < FONT_FIRST + FONT_COUNT) slots[i] = c;
      }
    }
    this.slots = slots;
    const a = Number(s?.active) | 0;
    this.active = a >= 0 && a < FONT_SLOT_COUNT ? a : 0;
  }

  activeCode() {
    return this.slots[this.active];
  }

  hasClip() {
    return !!this.clip;
  }

  #font() {
    return this.opts.getFont();
  }

  #rowsFor(code) {
    return this.#font()[code - FONT_FIRST];
  }

  // ---- DOM ----

  #buildOverview(root) {
    root.textContent = "";
    root.append(fontEl("h2", "", "Font"));
    const grid = fontEl("div", "font-overview");
    for (let i = 0; i < FONT_COUNT; i++) {
      const code = FONT_FIRST + i;
      const btn = fontEl("button", "font-cell");
      btn.type = "button";
      btn.dataset.code = String(code);
      btn.title = `${code} · 0x${fontHex2(code)}`;
      const cv = document.createElement("canvas");
      cv.width = FONT_W;
      cv.height = FONT_H;
      btn.append(cv, fontEl("span", "font-cell-label", fontCharLabel(code)));
      grid.append(btn);
      this.cells.push({ btn, cv });
    }
    grid.addEventListener("pointerdown", (e) => this.#onCellDown(e));
    grid.addEventListener("pointermove", (e) => this.#onCellMove(e));
    grid.addEventListener("pointerup", (e) => this.#onCellUp(e, true));
    grid.addEventListener("pointercancel", (e) => this.#onCellUp(e, false));
    grid.addEventListener("contextmenu", (e) => e.preventDefault());
    root.append(grid);
    root.append(fontEl("p", "muted font-left-hint", "Drag a glyph onto a grid · click to load into the active grid"));
  }

  #buildPanel(root) {
    root.textContent = "";
    const slots = fontEl("div", "font-slots");
    for (let i = 0; i < FONT_SLOT_COUNT; i++) {
      const el = fontEl("div", "font-slot");
      const head = fontEl("div", "font-slot-head");
      const title = fontEl("span", "font-slot-title");
      const close = fontEl("button", "font-slot-x", "×");
      close.type = "button";
      close.title = "Close this grid";
      close.addEventListener("click", () => this.#closeSlot(i));
      head.append(title, close);
      const cv = document.createElement("canvas");
      cv.className = "font-grid";
      cv.width = FONT_W * FONT_CELL_PX;
      cv.height = FONT_H * FONT_CELL_PX;
      const hex = fontEl("div", "font-slot-hex muted");
      el.append(head, cv, hex);
      el.addEventListener("pointerdown", () => this.#setActive(i), true);
      cv.addEventListener("pointerdown", (e) => this.#onGridDown(e, i));
      cv.addEventListener("pointermove", (e) => this.#onGridMove(e));
      cv.addEventListener("pointerup", (e) => this.#endStroke(e));
      cv.addEventListener("pointercancel", (e) => this.#endStroke(e));
      cv.addEventListener("lostpointercapture", (e) => this.#endStroke(e));
      cv.addEventListener("contextmenu", (e) => e.preventDefault());
      cv.addEventListener("mousedown", (e) => {
        if (e.button === 1) e.preventDefault();
      });
      cv.addEventListener("auxclick", (e) => {
        if (e.button === 1) e.preventDefault();
      });
      slots.append(el);
      this.slotEls.push({ el, title, cv, hex });
    }
    root.append(slots);

    const prev = fontEl("div", "font-preview");
    const bar = fontEl("div", "font-preview-bar");
    const input = document.createElement("textarea");
    input.className = "font-preview-input";
    input.value = this.sample;
    input.rows = 3;
    input.maxLength = 600;
    input.spellcheck = false;
    input.placeholder = "Preview text (Enter = new line)";
    input.addEventListener("input", () => {
      this.sample = input.value;
      this.#drawPreview();
    });
    const prop = fontEl("button", "toggle active", "Proportional");
    prop.type = "button";
    prop.title = "Menu text: glyphs trimmed to their ink width (src/menu.asm). Off = fixed 8px.";
    prop.addEventListener("click", () => {
      this.proportional = !this.proportional;
      prop.classList.toggle("active", this.proportional);
      this.#drawPreview();
    });
    bar.append(input, prop);
    // No scrolling: the large copy picks the biggest integer scale (<= 4) that fits the panel.
    const wrap = fontEl("div", "font-preview-wrap");
    this.previewA = document.createElement("canvas");
    this.previewB = document.createElement("canvas");
    this.previewA.className = this.previewB.className = "font-preview-canvas";
    this.previewCap = fontEl("div", "font-preview-cap muted");
    wrap.append(this.previewA, this.previewCap, this.previewB);
    prev.append(bar, wrap);
    root.append(prev);
    this.previewInput = input;
    this.previewWrap = wrap;
    this.previewWidth = 0;
    new ResizeObserver(() => {
      const w = wrap.clientWidth;
      if (w === this.previewWidth) return;
      this.previewWidth = w;
      this.#drawPreview();
    }).observe(wrap);
  }

  // ---- drawing ----

  refresh() {
    if (!this.enabled) return;
    for (let i = 0; i < FONT_COUNT; i++) this.#drawCell(FONT_FIRST + i);
    for (let i = 0; i < FONT_SLOT_COUNT; i++) this.#drawSlot(i);
    this.#drawPreview();
  }

  #drawGlyphEverywhere(code) {
    this.#drawCell(code);
    for (let i = 0; i < FONT_SLOT_COUNT; i++) if (this.slots[i] === code) this.#drawSlot(i);
    this.#drawPreview();
  }

  #drawCell(code) {
    const { btn, cv } = this.cells[code - FONT_FIRST];
    const rows = this.#rowsFor(code);
    const ctx = cv.getContext("2d");
    ctx.fillStyle = FONT_BG;
    ctx.fillRect(0, 0, FONT_W, FONT_H);
    ctx.fillStyle = FONT_INK;
    for (let y = 0; y < FONT_H; y++) {
      for (let x = 0; x < FONT_W; x++) if (fontGetPixel(rows, x, y)) ctx.fillRect(x, y, 1, 1);
    }
    const inSlot = this.slots.includes(code);
    btn.classList.toggle("in-slot", inSlot);
    btn.classList.toggle("active", this.slots[this.active] === code);
    btn.classList.toggle("empty", rows.every((r) => r === 0));
  }

  #drawSlot(i) {
    const { el, title, cv, hex } = this.slotEls[i];
    const code = this.slots[i];
    el.classList.toggle("active", i === this.active);
    el.classList.toggle("empty", code == null);
    const ctx = cv.getContext("2d");
    const S = FONT_W * FONT_CELL_PX;
    ctx.fillStyle = FONT_BG;
    ctx.fillRect(0, 0, S, S);
    if (code == null) {
      title.textContent = `Grid ${i + 1}`;
      hex.textContent = "";
      this.#drawGridLines(ctx, S);
      ctx.fillStyle = "#8b91a0";
      ctx.font = "22px Segoe UI, sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText("drop a glyph here", S / 2, S / 2);
      return;
    }
    const rows = this.#rowsFor(code);
    ctx.fillStyle = FONT_INK;
    for (let y = 0; y < FONT_H; y++) {
      for (let x = 0; x < FONT_W; x++) {
        if (fontGetPixel(rows, x, y)) {
          ctx.fillRect(x * FONT_CELL_PX + 1, y * FONT_CELL_PX + 1, FONT_CELL_PX - 1, FONT_CELL_PX - 1);
        }
      }
    }
    this.#drawGridLines(ctx, S);
    title.textContent = `${fontCharLabel(code)}  ${code} · 0x${fontHex2(code)}`;
    hex.textContent = rows.map(fontHex2).join(" ");
  }

  #drawGridLines(ctx, S) {
    ctx.strokeStyle = FONT_GRID;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let i = 0; i <= FONT_W; i++) {
      const p = i * FONT_CELL_PX + 0.5;
      ctx.moveTo(p, 0);
      ctx.lineTo(p, S);
      ctx.moveTo(0, p);
      ctx.lineTo(S, p);
    }
    ctx.stroke();
  }

  #drawPreview() {
    if (!this.enabled) return;
    const font = this.#font();
    const lays = this.sample.split("\n").map((l) => fontLayoutText(font, l, this.proportional));
    const w = Math.max(1, ...lays.map((l) => l.width));
    const h = lays.length * FONT_H;
    const avail = this.previewWrap.clientWidth || w;
    const fit = Math.max(1, Math.min(4, Math.floor(avail / w)));
    this.previewCap.textContent = `${w}x${h} px · actual size above${fit > 1 ? `, ${fit}x below` : ""}`;
    this.previewB.hidden = fit === 1;
    for (const [cv, scale] of [
      [this.previewA, 1],
      [this.previewB, fit],
    ]) {
      cv.width = w;
      cv.height = h;
      cv.style.width = `${w * scale}px`;
      cv.style.aspectRatio = `${w} / ${h}`;
      const ctx = cv.getContext("2d");
      ctx.fillStyle = FONT_BG;
      ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = FONT_INK;
      lays.forEach((lay, li) => {
        const y0 = li * FONT_H;
        for (const c of lay.cells) {
          const rows = font[c.code - FONT_FIRST];
          for (let y = 0; y < FONT_H; y++) {
            for (let x = 0; x < FONT_W; x++) {
              const px = c.x + x - c.shift;
              if (px >= 0 && fontGetPixel(rows, x, y)) ctx.fillRect(px, y0 + y, 1, 1);
            }
          }
        }
      });
    }
  }

  // ---- slots ----

  #setActive(i) {
    if (this.active === i) return;
    this.active = i;
    this.opts.onUiChange?.();
    this.refresh();
    this.opts.onChange?.();
  }

  #closeSlot(i) {
    if (this.slots[i] == null) return;
    this.slots[i] = null;
    this.opts.onUiChange?.();
    this.refresh();
    this.opts.onChange?.();
  }

  loadSlot(i, code) {
    this.slots[i] = code;
    this.active = i;
    this.opts.onUiChange?.();
    this.refresh();
    this.opts.onChange?.();
  }

  // ---- overview drag ----

  #onCellDown(e) {
    if (!this.enabled || e.button !== 0) return;
    const btn = e.target.closest?.(".font-cell");
    if (!btn) return;
    e.preventDefault();
    this.drag = {
      code: Number(btn.dataset.code),
      pid: e.pointerId,
      sx: e.clientX,
      sy: e.clientY,
      moved: false,
      ghost: null,
      hover: -1,
    };
    btn.setPointerCapture(e.pointerId);
  }

  #slotAt(x, y) {
    for (let i = 0; i < FONT_SLOT_COUNT; i++) {
      const r = this.slotEls[i].el.getBoundingClientRect();
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return i;
    }
    return -1;
  }

  #onCellMove(e) {
    const d = this.drag;
    if (!d || e.pointerId !== d.pid) return;
    if (!d.moved) {
      if (Math.hypot(e.clientX - d.sx, e.clientY - d.sy) < FONT_DRAG_THRESHOLD) return;
      d.moved = true;
      const ghost = fontEl("div", "font-drag-ghost");
      const cv = document.createElement("canvas");
      cv.width = FONT_W;
      cv.height = FONT_H;
      const ctx = cv.getContext("2d");
      ctx.fillStyle = FONT_BG;
      ctx.fillRect(0, 0, FONT_W, FONT_H);
      ctx.fillStyle = FONT_INK;
      const rows = this.#rowsFor(d.code);
      for (let y = 0; y < FONT_H; y++) {
        for (let x = 0; x < FONT_W; x++) if (fontGetPixel(rows, x, y)) ctx.fillRect(x, y, 1, 1);
      }
      ghost.append(cv);
      document.body.append(ghost);
      d.ghost = ghost;
      document.body.classList.add("font-dragging");
    }
    d.ghost.style.transform = `translate(${e.clientX + 10}px, ${e.clientY + 10}px)`;
    const hover = this.#slotAt(e.clientX, e.clientY);
    if (hover !== d.hover) {
      d.hover = hover;
      this.slotEls.forEach((s, i) => s.el.classList.toggle("drop", i === hover));
    }
  }

  #onCellUp(e, commit) {
    const d = this.drag;
    if (!d || e.pointerId !== d.pid) return;
    this.drag = null;
    d.ghost?.remove();
    document.body.classList.remove("font-dragging");
    this.slotEls.forEach((s) => s.el.classList.remove("drop"));
    if (!commit) return;
    if (d.moved) {
      if (d.hover >= 0) this.loadSlot(d.hover, d.code);
      return;
    }
    const existing = this.slots.indexOf(d.code);
    if (existing >= 0) this.#setActive(existing);
    else this.loadSlot(this.active, d.code);
  }

  // ---- painting ----

  #cellAt(canvas, e) {
    const r = canvas.getBoundingClientRect();
    return {
      x: Math.floor(((e.clientX - r.left) / r.width) * FONT_W),
      y: Math.floor(((e.clientY - r.top) / r.height) * FONT_H),
    };
  }

  #onGridDown(e, slot) {
    if (!this.enabled) return;
    if (e.button === 1) e.preventDefault();
    if (e.button !== 0 && e.button !== 2) return;
    const code = this.slots[slot];
    if (code == null) return;
    e.preventDefault();
    const c = this.#cellAt(e.currentTarget, e);
    this.stroke = {
      slot,
      code,
      on: e.button === 0,
      last: c,
      pid: e.pointerId,
      began: false,
    };
    e.currentTarget.setPointerCapture(e.pointerId);
    this.#paintCell(c.x, c.y);
  }

  #onGridMove(e) {
    const s = this.stroke;
    if (!s || e.pointerId !== s.pid) return;
    const c = this.#cellAt(this.slotEls[s.slot].cv, e);
    if (c.x === s.last.x && c.y === s.last.y) return;
    // Bresenham so fast drags leave no gaps.
    let x0 = s.last.x;
    let y0 = s.last.y;
    const dx = Math.abs(c.x - x0);
    const dy = -Math.abs(c.y - y0);
    const sx = x0 < c.x ? 1 : -1;
    const sy = y0 < c.y ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.#paintCell(x0, y0);
      if (x0 === c.x && y0 === c.y) break;
      const e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y0 += sy;
      }
    }
    s.last = c;
  }

  #paintCell(x, y) {
    const s = this.stroke;
    if (!s || x < 0 || y < 0 || x >= FONT_W || y >= FONT_H) return;
    const rows = this.#rowsFor(s.code);
    if (fontGetPixel(rows, x, y) === s.on) return;
    if (!s.began) {
      s.began = true;
      this.opts.beginUndo();
    }
    fontSetPixel(rows, x, y, s.on);
    this.#drawGlyphEverywhere(s.code);
  }

  #endStroke(e) {
    const s = this.stroke;
    if (!s || (e && e.pointerId !== s.pid)) return;
    this.stroke = null;
    if (!s.began) return;
    this.opts.endUndo();
    this.opts.markDirty();
    this.opts.onChange?.();
  }

  // ---- glyph operations (inspector buttons, shortcuts) ----

  #editActive(fn) {
    const code = this.activeCode();
    if (code == null) return false;
    const font = this.#font();
    const idx = code - FONT_FIRST;
    const next = fn(font[idx].slice());
    if (fontRowsEqual(next, font[idx])) return false;
    this.opts.beginUndo();
    font[idx] = next;
    this.opts.endUndo();
    this.opts.markDirty();
    this.#drawGlyphEverywhere(code);
    this.opts.onChange?.();
    return true;
  }

  shiftActive(dx, dy) {
    return this.#editActive((r) => fontShift(r, dx, dy));
  }
  flipHActive() {
    return this.#editActive(fontFlipH);
  }
  flipVActive() {
    return this.#editActive(fontFlipV);
  }
  invertActive() {
    return this.#editActive(fontInvert);
  }
  clearActive() {
    return this.#editActive(() => new Array(FONT_H).fill(0));
  }

  copyActive() {
    const code = this.activeCode();
    if (code == null) return false;
    this.clip = this.#rowsFor(code).slice();
    this.opts.onStatus?.(`Copied ${fontCharLabel(code)}`);
    this.opts.onChange?.();
    return true;
  }

  pasteActive() {
    if (!this.clip) return false;
    const clip = this.clip.slice();
    return this.#editActive(() => clip);
  }

  /** Returns true when the key was a font shortcut. Caller skips text inputs. */
  handleKey(e) {
    if (e.altKey) return false;
    const mod = e.ctrlKey || e.metaKey;
    const k = e.key.toLowerCase();
    if (mod) {
      if (e.shiftKey) return false;
      if (k === "c") return this.copyActive() || true;
      if (k === "v") return this.pasteActive() || true;
      return false;
    }
    if (k >= "1" && k <= String(FONT_SLOT_COUNT)) {
      this.#setActive(Number(k) - 1);
      return true;
    }
    switch (k) {
      case "arrowleft":
        return this.shiftActive(-1, 0) || true;
      case "arrowright":
        return this.shiftActive(1, 0) || true;
      case "arrowup":
        return this.shiftActive(0, -1) || true;
      case "arrowdown":
        return this.shiftActive(0, 1) || true;
      case "h":
        return this.flipHActive() || true;
      case "v":
        return this.flipVActive() || true;
      case "i":
        return this.invertActive() || true;
      case "delete":
      case "backspace":
        return this.clearActive() || true;
      default:
        return false;
    }
  }

  // ---- PNG sheet import / export ----

  async importSheet(file, invert) {
    let bmp;
    try {
      bmp = await createImageBitmap(file, { colorSpaceConversion: "none" });
    } catch {
      this.opts.onStatus?.("Could not read that image", true);
      return;
    }
    const cv = document.createElement("canvas");
    cv.width = bmp.width;
    cv.height = bmp.height;
    const ctx = cv.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(bmp, 0, 0);
    bmp.close?.();
    const res = fontFromImageData(ctx.getImageData(0, 0, cv.width, cv.height), { invert });
    if (res.error) {
      this.opts.onStatus?.(res.error, true);
      return;
    }
    const font = this.#font();
    const changed = res.glyphs.filter((g) => !fontRowsEqual(g.rows, font[g.index]));
    if (!changed.length) {
      this.opts.onStatus?.(`Imported ${res.glyphs.length} glyphs: no changes`);
      return;
    }
    this.opts.beginUndo();
    for (const g of changed) font[g.index] = g.rows.slice();
    this.opts.endUndo();
    this.opts.markDirty();
    this.refresh();
    this.opts.onChange?.();
    const nonEmpty = res.glyphs.filter((g) => !fontGlyphStats(g.rows).empty).length;
    const extra = res.ignored ? `, ${res.ignored} cells past glyph 96 ignored` : "";
    this.opts.onStatus?.(
      `Imported ${res.glyphs.length} glyphs (${nonEmpty} non-empty, ${changed.length} changed)${extra}`,
    );
  }

  exportSheet() {
    const img = fontToImageData(this.#font());
    const cv = document.createElement("canvas");
    cv.width = img.width;
    cv.height = img.height;
    cv.getContext("2d").putImageData(new ImageData(img.data, img.width, img.height), 0, 0);
    cv.toBlob((blob) => {
      if (!blob) {
        this.opts.onStatus?.("PNG export failed", true);
        return;
      }
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "font.png";
      document.body.append(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      this.opts.onStatus?.("Exported font.png (64x96)");
    }, "image/png");
  }
}
