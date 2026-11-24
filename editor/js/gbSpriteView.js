import {
  GBS_CELL_H,
  GBS_CELL_W,
  GBS_DEFS,
  GBS_H_MAX,
  GBS_H_MIN,
  GBS_W_MAX,
  GBS_W_MIN,
  gbsBlankRows,
  gbsCellCount,
  gbsCellUsed,
  gbsDef,
  gbsFlipHRows,
  gbsFlipVRows,
  gbsGet,
  gbsInvertRows,
  gbsResize,
  gbsRowsEqual,
  gbsSet,
  gbsShiftRows,
} from "./gbSpriteModel.js";

const GBS_INK = "#ffffff";
const GBS_BG = "#000000";
const GBS_GRID = "rgba(255, 255, 255, 0.12)";
const GBS_CELL_LINE = "rgba(255, 200, 80, 0.55)";
const GBS_CELL_USED = "rgba(80, 160, 255, 0.14)";
const GBS_MAX_W = 640;
const GBS_MAX_H = 560;

function gbsEl(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

/**
 * Game Boy sprites tab: sprite list (left), 1-bit pixel painter (centre) with width/height sliders,
 * shift, flip/invert, copy/paste and PNG import/export. Data lives in doc.gbSprites via opts.getSprites().
 * opts: left, panel (DOM roots), getSprites, beginUndo, endUndo, markDirty, onChange, onStatus,
 *       onImport, onExport (async PNG round trip with assets/weapons).
 */
export class GbSpriteView {
  constructor(opts) {
    this.opts = opts;
    this.enabled = false;
    this.selId = GBS_DEFS[0].id;
    this.clip = null;
    this.stroke = null;
    this.thumbs = new Map();
    this.#buildList(opts.left);
    this.#buildPanel(opts.panel);
  }

  getState() {
    return { sel: this.selId };
  }

  setState(s) {
    this.selId = gbsDef(s?.sel) ? s.sel : GBS_DEFS[0].id;
  }

  selected() {
    return this.opts.getSprites().find((s) => s.id === this.selId) || null;
  }

  // ---- DOM ----

  #buildList(root) {
    root.textContent = "";
    root.append(gbsEl("h2", "", "GB sprites"));
    const wrap = gbsEl("div", "spr-list");
    let group = null;
    for (const def of GBS_DEFS) {
      if (def.group !== group) {
        group = def.group;
        wrap.append(gbsEl("h3", "spr-group", group));
      }
      const btn = gbsEl("button", "spr-item");
      btn.type = "button";
      const cv = document.createElement("canvas");
      cv.className = "spr-thumb";
      const label = gbsEl("span", "spr-item-label", def.name);
      const dim = gbsEl("span", "spr-item-dim muted");
      btn.append(cv, label, dim);
      btn.addEventListener("click", () => this.select(def.id));
      wrap.append(btn);
      this.thumbs.set(def.id, { btn, cv, dim });
    }
    root.append(wrap);
    const io = gbsEl("div", "btn-row");
    io.append(
      this.#button("Import PNGs", "Read assets/weapons/*.png into every sprite (replaces the tab's data)", () =>
        this.opts.onImport?.(),
      ),
      this.#button("Export PNGs", "Write every sprite to assets/weapons/<id>.png (white on black)", () =>
        this.opts.onExport?.(),
      ),
    );
    root.append(io);
    root.append(gbsEl("p", "muted spr-left-hint", "1 px = 1 GBC pixel. White = ink. Build reads assets/weapons/*.png."));
  }

  #button(label, title, onClick, cls = "") {
    const b = gbsEl("button", cls, label);
    b.type = "button";
    b.title = title;
    b.addEventListener("click", onClick);
    return b;
  }

  #slider(label, min, max, onInput) {
    const row = gbsEl("label", "spr-slider");
    const name = gbsEl("span", "spr-slider-name", label);
    const input = document.createElement("input");
    input.type = "range";
    input.min = String(min);
    input.max = String(max);
    input.step = "1";
    const val = gbsEl("span", "spr-slider-val");
    input.addEventListener("input", () => onInput(Number(input.value), false));
    input.addEventListener("change", () => {
      onInput(Number(input.value), true);
      input.blur(); // a focused range input swallows Ctrl+Z in the window key handler
    });
    row.append(name, input, val);
    return { row, input, val };
  }

  #cross(label, title, fn) {
    const cross = gbsEl("div", "spr-cross");
    cross.append(
      gbsEl("span"),
      this.#button("↑", `${title} up`, (e) => fn(0, -(e.shiftKey ? 8 : 1))),
      gbsEl("span"),
      this.#button("←", `${title} left`, (e) => fn(-(e.shiftKey ? 8 : 1), 0)),
      gbsEl("span", "spr-cross-mid", label),
      this.#button("→", `${title} right`, (e) => fn(e.shiftKey ? 8 : 1, 0)),
      gbsEl("span"),
      this.#button("↓", `${title} down`, (e) => fn(0, e.shiftKey ? 8 : 1)),
      gbsEl("span"),
    );
    return cross;
  }

  #buildPanel(root) {
    root.textContent = "";
    this.title = gbsEl("div", "spr-title");
    root.append(this.title);

    const main = gbsEl("div", "spr-main");
    const cv = document.createElement("canvas");
    cv.className = "spr-grid";
    cv.addEventListener("pointerdown", (e) => this.#onDown(e));
    cv.addEventListener("pointermove", (e) => this.#onMove(e));
    cv.addEventListener("pointerup", (e) => this.#endStroke(e));
    cv.addEventListener("pointercancel", (e) => this.#endStroke(e));
    cv.addEventListener("lostpointercapture", (e) => this.#endStroke(e));
    cv.addEventListener("contextmenu", (e) => e.preventDefault());
    this.grid = cv;

    const side = gbsEl("div", "spr-side");
    this.wSlider = this.#slider("Width", GBS_W_MIN, GBS_W_MAX, (v, done) => this.#resize(v, null, done));
    this.hSlider = this.#slider("Height", GBS_H_MIN, GBS_H_MAX, (v, done) => this.#resize(null, v, done));
    this.sizeNote = gbsEl("p", "muted spr-size-note");

    const ops = gbsEl("div", "btn-row spr-ops");
    ops.append(
      this.#button("Clear", "Del", () => this.clear(), "danger"),
      this.#button("Invert", "I", () => this.invert()),
      this.#button("Flip H", "H", () => this.flipH()),
      this.#button("Flip V", "V", () => this.flipV()),
    );
    const clip = gbsEl("div", "btn-row spr-ops");
    this.pasteBtn = this.#button("Paste", "Ctrl+V", () => this.paste());
    clip.append(this.#button("Copy", "Ctrl+C", () => this.copy()), this.pasteBtn);

    const sliders = gbsEl("div", "spr-sliders");
    sliders.append(this.wSlider.row, this.hSlider.row, this.sizeNote);
    const btns = gbsEl("div", "spr-btns");
    btns.append(ops, clip);
    side.append(sliders, this.#cross("shift", "Shift (arrows, Shift = 8)", (dx, dy) => this.shift(dx, dy)), btns);

    const stage = gbsEl("div", "spr-stage");
    stage.append(cv);
    main.append(stage, side);
    root.append(main);
  }

  // ---- drawing ----

  #cell(sp) {
    const k = Math.max(4, Math.min(24, Math.floor(GBS_MAX_H / sp.h), Math.floor(GBS_MAX_W / sp.w)));
    return k;
  }

  refresh() {
    if (!this.enabled) return;
    const sp = this.selected();
    for (const def of GBS_DEFS) this.#drawThumb(def.id);
    if (!sp) return;
    const def = gbsDef(sp.id);
    this.title.textContent = `${def.name} · ${sp.id}.png · ${sp.w}×${sp.h}`;
    this.wSlider.input.value = String(sp.w);
    this.wSlider.val.textContent = String(sp.w);
    this.hSlider.input.value = String(sp.h);
    this.hSlider.val.textContent = String(sp.h);
    this.sizeNote.textContent = this.#cellNote(sp, def);
    this.sizeNote.classList.toggle("error", this.#overLimit(sp, def));
    this.pasteBtn.disabled = !this.clip;
    this.#drawGrid(sp);
  }

  #overLimit(sp, def) {
    return def.cellLimit != null && gbsCellCount(sp) > def.cellLimit;
  }

  #cellNote(sp, def) {
    const n = gbsCellCount(sp);
    const lim = def.cellLimit == null ? "" : ` / ${def.cellLimit}`;
    return `${n}${lim} OAM cells (8×16, empty cells skipped)`;
  }

  #drawGrid(sp) {
    const k = this.#cell(sp);
    const cv = this.grid;
    cv.width = sp.w * k;
    cv.height = sp.h * k;
    const ctx = cv.getContext("2d");
    ctx.fillStyle = GBS_BG;
    ctx.fillRect(0, 0, cv.width, cv.height);
    ctx.fillStyle = GBS_CELL_USED;
    for (let cy = 0; cy < sp.h; cy += GBS_CELL_H) {
      for (let cx = 0; cx < sp.w; cx += GBS_CELL_W) {
        if (!gbsCellUsed(sp, cx, cy)) continue;
        ctx.fillRect(cx * k, cy * k, Math.min(GBS_CELL_W, sp.w - cx) * k, Math.min(GBS_CELL_H, sp.h - cy) * k);
      }
    }
    ctx.fillStyle = GBS_INK;
    for (let y = 0; y < sp.h; y++) {
      for (let x = 0; x < sp.w; x++) {
        if (gbsGet(sp, x, y)) ctx.fillRect(x * k + 1, y * k + 1, k - 1, k - 1);
      }
    }
    ctx.lineWidth = 1;
    ctx.strokeStyle = GBS_GRID;
    ctx.beginPath();
    for (let x = 0; x <= sp.w; x++) {
      const px = Math.min(x * k + 0.5, cv.width - 0.5);
      ctx.moveTo(px, 0);
      ctx.lineTo(px, cv.height);
    }
    for (let y = 0; y <= sp.h; y++) {
      const py = Math.min(y * k + 0.5, cv.height - 0.5);
      ctx.moveTo(0, py);
      ctx.lineTo(cv.width, py);
    }
    ctx.stroke();
    // OAM cell boundaries: every 8 px across, every 16 px down.
    ctx.strokeStyle = GBS_CELL_LINE;
    ctx.beginPath();
    // The right / bottom edge sits on the canvas border, so pull it half a pixel inside.
    for (let x = 0; x <= sp.w; x += GBS_CELL_W) {
      const px = Math.min(x * k + 0.5, cv.width - 0.5);
      ctx.moveTo(px, 0);
      ctx.lineTo(px, cv.height);
    }
    for (let y = 0; y <= sp.h; y += GBS_CELL_H) {
      const py = Math.min(y * k + 0.5, cv.height - 0.5);
      ctx.moveTo(0, py);
      ctx.lineTo(cv.width, py);
    }
    ctx.stroke();
  }

  #drawThumb(id) {
    const t = this.thumbs.get(id);
    const sp = this.opts.getSprites().find((s) => s.id === id);
    if (!t || !sp) return;
    t.btn.classList.toggle("active", id === this.selId);
    const def = gbsDef(id);
    t.dim.textContent = `${sp.w}×${sp.h}`;
    t.dim.classList.toggle("error", this.#overLimit(sp, def));
    const cv = t.cv;
    cv.width = sp.w;
    cv.height = sp.h;
    const k = Math.max(1, Math.min(Math.floor(56 / sp.w), Math.floor(44 / sp.h)));
    cv.style.width = `${sp.w * k}px`;
    cv.style.height = `${sp.h * k}px`;
    const ctx = cv.getContext("2d");
    ctx.fillStyle = GBS_BG;
    ctx.fillRect(0, 0, sp.w, sp.h);
    ctx.fillStyle = GBS_INK;
    for (let y = 0; y < sp.h; y++) {
      for (let x = 0; x < sp.w; x++) if (gbsGet(sp, x, y)) ctx.fillRect(x, y, 1, 1);
    }
  }

  // ---- selection ----

  select(id) {
    if (!gbsDef(id) || id === this.selId) return;
    this.selId = id;
    this.refresh();
    this.opts.onChange?.();
  }

  // ---- painting ----

  #cellAt(e) {
    const sp = this.selected();
    const r = this.grid.getBoundingClientRect();
    return {
      x: Math.floor(((e.clientX - r.left) / r.width) * sp.w),
      y: Math.floor(((e.clientY - r.top) / r.height) * sp.h),
    };
  }

  #onDown(e) {
    if (!this.enabled || !this.selected()) return;
    if (e.button !== 0 && e.button !== 2) return;
    e.preventDefault();
    if (document.activeElement && document.activeElement !== document.body) document.activeElement.blur();
    const c = this.#cellAt(e);
    this.stroke = { on: e.button === 0, last: c, pid: e.pointerId, began: false };
    this.grid.setPointerCapture(e.pointerId);
    this.#paint(c.x, c.y);
  }

  #onMove(e) {
    const s = this.stroke;
    if (!s || e.pointerId !== s.pid) return;
    const c = this.#cellAt(e);
    if (c.x === s.last.x && c.y === s.last.y) return;
    let x0 = s.last.x;
    let y0 = s.last.y;
    const dx = Math.abs(c.x - x0);
    const dy = -Math.abs(c.y - y0);
    const sx = x0 < c.x ? 1 : -1;
    const sy = y0 < c.y ? 1 : -1;
    let err = dx + dy;
    for (;;) {
      this.#paint(x0, y0);
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

  #paint(x, y) {
    const s = this.stroke;
    const sp = this.selected();
    if (!s || !sp || x < 0 || y < 0 || x >= sp.w || y >= sp.h) return;
    if (gbsGet(sp, x, y) === s.on) return;
    if (!s.began) {
      s.began = true;
      this.opts.beginUndo();
    }
    gbsSet(sp, x, y, s.on);
    this.#drawGrid(sp);
    this.#drawThumb(sp.id);
    this.sizeNote.textContent = this.#cellNote(sp, gbsDef(sp.id));
    this.sizeNote.classList.toggle("error", this.#overLimit(sp, gbsDef(sp.id)));
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

  // ---- edits ----

  #edit(fn) {
    const sp = this.selected();
    if (!sp) return false;
    const next = fn(sp);
    if (!next || gbsRowsEqual(next, sp.rows)) return false;
    this.opts.beginUndo();
    sp.rows = next;
    this.opts.endUndo();
    this.opts.markDirty();
    this.refresh();
    this.opts.onChange?.();
    return true;
  }

  shift(dx, dy) {
    return this.#edit((sp) => gbsShiftRows(sp, dx, dy));
  }
  flipH() {
    return this.#edit(gbsFlipHRows);
  }
  flipV() {
    return this.#edit(gbsFlipVRows);
  }
  invert() {
    return this.#edit(gbsInvertRows);
  }
  clear() {
    return this.#edit((sp) => gbsBlankRows(sp.w, sp.h));
  }

  copy() {
    const sp = this.selected();
    if (!sp) return false;
    this.clip = { w: sp.w, h: sp.h, rows: sp.rows.slice() };
    this.opts.onStatus?.(`Copied ${gbsDef(sp.id).name}`);
    this.refresh();
    return true;
  }

  /** Top-left aligned; anything past the current size is cropped. */
  paste() {
    const clip = this.clip;
    if (!clip) return false;
    return this.#edit((sp) => {
      const rows = gbsBlankRows(sp.w, sp.h);
      for (let y = 0; y < Math.min(sp.h, clip.h); y++) {
        let s = "";
        for (let x = 0; x < sp.w; x++) s += x < clip.w ? clip.rows[y][x] : ".";
        rows[y] = s;
      }
      return rows;
    });
  }

  /** One undo step per slider drag: begins on the first input, ends on change. */
  #resize(w, h, done) {
    const sp = this.selected();
    if (!sp) return;
    const nw = w ?? sp.w;
    const nh = h ?? sp.h;
    if (nw !== sp.w || nh !== sp.h) {
      this.opts.beginUndo();
      Object.assign(sp, gbsResize(sp, nw, nh));
      this.opts.markDirty();
      this.refresh();
    }
    if (done) {
      this.opts.endUndo();
      this.opts.onChange?.();
    }
  }

  /** Returns true when the key was a sprite shortcut. Caller skips text inputs. */
  handleKey(e) {
    if (e.altKey) return false;
    const mod = e.ctrlKey || e.metaKey;
    const k = e.key.toLowerCase();
    if (mod) {
      if (e.shiftKey) return false;
      if (k === "c") return this.copy() || true;
      if (k === "v") return this.paste() || true;
      return false;
    }
    const n = e.shiftKey ? 8 : 1;
    switch (k) {
      case "arrowleft":
        return this.shift(-n, 0) || true;
      case "arrowright":
        return this.shift(n, 0) || true;
      case "arrowup":
        return this.shift(0, -n) || true;
      case "arrowdown":
        return this.shift(0, n) || true;
      case "h":
        return this.flipH() || true;
      case "v":
        return this.flipV() || true;
      case "i":
        return this.invert() || true;
      case "delete":
      case "backspace":
        return this.clear() || true;
      default:
        return false;
    }
  }
}
