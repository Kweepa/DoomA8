import {
  GBW_DEFS,
  GBW_FLASH_DY,
  GBW_FLASH_TICKS,
  GBW_MAX_STEPS,
  GBW_VBLANK_HZ,
  GBW_VIEW_H,
  GBW_VIEW_W,
  gbwAnimLen,
  gbwDef,
  gbwIssues,
  gbwMs,
  gbwPose,
  gbwUntils,
} from "./gbWeaponModel.js";

const SCALE = 3;
const TL_W = 720;
const TL_H = 170;
const COL_INK = "#ffffff";
const COL_FLASH = "#ffd23c";
const COL_BG = "#0b0d14";
const COL_VIEW = "#07162e";
const SPEEDS = [1, 0.5, 0.25, 0.125];

function wEl(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

/**
 * Weapons tab: weapon list (left); period, anim, overhang and the pose-step table (centre top); a
 * firing preview with a dy-over-time timeline (centre bottom). Data lives in doc.gbWeapons
 * (opts.getWeapons()); the preview draws the sprite art from doc.gbSprites (opts.getSprites()).
 * opts: left, panel (DOM roots), getWeapons, getSprites, beginUndo, endUndo, markDirty, onChange, onStatus.
 */
export class GbWeaponView {
  constructor(opts) {
    this.opts = opts;
    this._en = false;
    this.selId = GBW_DEFS[0].id;
    this.t = -1; // VBlanks since the last shot (float); < 0 = idle
    this.shots = 0; // shot counter: parity picks flash A / B and the chaingun frame
    this.playing = false;
    this.loop = true;
    this.speed = 1;
    this.raf = 0;
    this.last = 0;
    this.sprCache = new Map();
    this.listBtns = new Map();
    this.#buildList(opts.left);
    this.#buildPanel(opts.panel);
  }

  getState() {
    return { sel: this.selId };
  }

  setState(s) {
    this.selId = gbwDef(s?.sel) ? s.sel : GBW_DEFS[0].id;
  }

  selected() {
    return this.opts.getWeapons().find((w) => w.id === this.selId) || null;
  }

  // ---- DOM ----

  #buildList(root) {
    root.textContent = "";
    root.append(wEl("h2", "", "Weapons"));
    const wrap = wEl("div", "spr-list");
    for (const def of GBW_DEFS) {
      const btn = wEl("button", "spr-item gbw-item");
      btn.type = "button";
      const label = wEl("span", "spr-item-label", def.name);
      const info = wEl("span", "spr-item-dim muted");
      btn.append(wEl("span"), label, info);
      btn.addEventListener("click", () => this.select(def.id));
      wrap.append(btn);
      this.listBtns.set(def.id, { btn, info });
    }
    root.append(wrap);
    root.append(
      wEl(
        "p",
        "muted spr-left-hint",
        "Times are VBlanks (1 = 16.7 ms). Saved in doom64.json; the GBC build writes gbc/build/wpntable.asm from it.",
      ),
    );
  }

  #buildPanel(root) {
    root.textContent = "";
    this.title = wEl("div", "spr-title");
    this.form = wEl("div", "gbw-form");
    this.preview = wEl("div", "gbw-preview");
    root.append(this.title, this.form, this.preview);

    const controls = wEl("div", "gbw-controls");
    this.btnFire = this.#button("Fire", "Shoot once from rest (Space)", () => this.fire());
    this.btnLoop = this.#button("Hold fire", "Re-fire every period, like holding the button", () => {
      this.loop = !this.loop;
      this.btnLoop.classList.toggle("active", this.loop);
    });
    this.btnLoop.classList.toggle("active", this.loop);
    this.speedSel = document.createElement("select");
    for (const s of SPEEDS) {
      const o = document.createElement("option");
      o.value = String(s);
      o.textContent = s === 1 ? "real time" : `${s}x speed`;
      this.speedSel.append(o);
    }
    this.speedSel.addEventListener("change", () => {
      this.speed = Number(this.speedSel.value);
      this.speedSel.blur();
    });
    this.scrub = document.createElement("input");
    this.scrub.type = "range";
    this.scrub.min = "-1";
    this.scrub.max = "100";
    this.scrub.step = "1";
    this.scrub.className = "gbw-scrub";
    this.scrub.addEventListener("input", () => {
      this.playing = false;
      this.t = Number(this.scrub.value);
      this.#draw();
    });
    this.scrub.addEventListener("change", () => this.scrub.blur());
    this.readout = wEl("span", "muted gbw-readout");
    controls.append(this.btnFire, this.btnLoop, this.speedSel, this.scrub, this.readout);

    const stage = wEl("div", "gbw-stage");
    this.view = document.createElement("canvas");
    this.view.width = GBW_VIEW_W * SCALE;
    this.view.height = GBW_VIEW_H * SCALE;
    this.view.className = "gbw-view";
    this.tl = document.createElement("canvas");
    this.tl.width = TL_W;
    this.tl.height = TL_H;
    this.tl.className = "gbw-timeline";
    this.tl.addEventListener("pointerdown", (e) => this.#tlScrub(e));
    this.tl.addEventListener("pointermove", (e) => {
      if (e.buttons & 1) this.#tlScrub(e);
    });
    stage.append(this.view, this.tl);
    this.preview.append(controls, stage);
  }

  #button(label, title, onClick, cls = "") {
    const b = wEl("button", cls, label);
    b.type = "button";
    b.title = title;
    b.addEventListener("click", onClick);
    return b;
  }

  // ---- state ----

  select(id) {
    if (!gbwDef(id)) return;
    this.selId = id;
    this.t = -1;
    this.playing = false;
    this.shots = 0;
    this.refresh();
    this.opts.onChange?.();
  }

  refresh() {
    this.sprCache.clear();
    const def = gbwDef(this.selId);
    const w = this.selected();
    if (!def || !w) return;
    for (const d of GBW_DEFS) {
      const ww = this.opts.getWeapons().find((x) => x.id === d.id);
      const rec = this.listBtns.get(d.id);
      rec.btn.classList.toggle("active", d.id === this.selId);
      rec.info.textContent = ww ? `${ww.period}` : "";
      rec.btn.title = ww ? `period ${ww.period} VBlanks (${gbwMs(ww.period).toFixed(0)} ms)` : "";
    }
    this.title.textContent = `Weapon — ${def.name}`;
    this.#buildForm(def, w);
    const span = Math.max(w.period, gbwAnimLen(def, w), GBW_FLASH_TICKS) + 4;
    this.scrub.max = String(span);
    this.#draw();
  }

  /** Edit gesture: one undo step per committed change. */
  #edit(fn) {
    this.opts.beginUndo();
    fn();
    this.opts.endUndo();
    this.opts.markDirty();
    this.refresh();
    this.opts.onChange?.();
  }

  #number(label, value, min, max, title, onCommit) {
    const row = wEl("label", "gbw-field");
    row.title = title || "";
    const name = wEl("span", "gbw-field-name", label);
    const input = document.createElement("input");
    input.type = "number";
    input.min = String(min);
    input.max = String(max);
    input.step = "1";
    input.value = String(value);
    input.addEventListener("change", () => {
      const v = Math.max(min, Math.min(max, Math.round(Number(input.value))));
      if (!Number.isFinite(v)) {
        input.value = String(value);
        return;
      }
      if (v !== value) onCommit(v);
      else input.value = String(value);
    });
    row.append(name, input);
    return { row, input };
  }

  #buildForm(def, w) {
    const f = this.form;
    f.textContent = "";
    const top = wEl("div", "gbw-row");
    const per = this.#number("Period", w.period, 1, 255, "VBlanks between shots while the button is held", (v) =>
      this.#edit(() => (w.period = v)),
    );
    per.row.append(wEl("span", "muted gbw-ms", `${gbwMs(w.period).toFixed(0)} ms`));
    top.append(per.row);
    if (def.tabled) {
      const ov = this.#number(
        "Overhang",
        w.overhang,
        0,
        64,
        "Art rows that hang below the viewport at rest; added to every non-pump step so the kicks still meet the art",
        (v) => this.#edit(() => (w.overhang = v)),
      );
      top.append(ov.row);
      const len = gbwAnimLen(def, w);
      top.append(wEl("span", "muted gbw-ms", `anim ${len} VBlanks (${gbwMs(len).toFixed(0)} ms) = sum of the durations`));
    } else {
      const an = this.#number("Anim", w.anim, 0, 255, "VBlanks the shot animation runs (chaingun: frame A / B per shot)", (v) =>
        this.#edit(() => (w.anim = v)),
      );
      an.row.append(wEl("span", "muted gbw-ms", `${gbwMs(w.anim).toFixed(0)} ms`));
      top.append(an.row);
      top.append(wEl("span", "muted gbw-ms", "frames / shake are in gbc/wpn.asm; no pose table"));
    }
    f.append(top);
    if (!def.tabled) return;

    const issues = gbwIssues(def, w);
    const table = wEl("table", "gbw-steps");
    const head = wEl("tr");
    for (const h of ["#", "duration (VBlanks)", "dy (px)", "frame", ""]) head.append(wEl("th", "", h));
    table.append(head);
    const ends = gbwUntils(w);
    w.steps.forEach((st, i) => {
      const tr = wEl("tr");
      const from = i ? ends[i - 1] : 0;
      tr.append(wEl("td", "muted", `${i + 1}`));
      const mk = (val, min, max, key) => {
        const td = wEl("td");
        const input = document.createElement("input");
        input.type = "number";
        input.min = String(min);
        input.max = String(max);
        input.step = "1";
        input.value = String(val);
        input.addEventListener("change", () => {
          const v = Math.max(min, Math.min(max, Math.round(Number(input.value))));
          if (!Number.isFinite(v) || v === val) {
            input.value = String(val);
            return;
          }
          this.#edit(() => (st[key] = v));
        });
        td.append(input);
        return td;
      };
      const durTd = mk(st.duration, 1, 255, "duration");
      durTd.append(wEl("span", "muted gbw-ms", ` ${from}–${ends[i]} · ${gbwMs(st.duration).toFixed(0)} ms`));
      tr.append(durTd, mk(st.dy, -128, 127, "dy"));
      const sel = document.createElement("select");
      for (const [v, label] of [
        ["idle", "idle (dy + overhang)"],
        ["alt", `${def.altName} (dy absolute)`],
      ]) {
        const o = document.createElement("option");
        o.value = v;
        o.textContent = label;
        sel.append(o);
      }
      sel.value = st.frame;
      sel.addEventListener("change", () => {
        const v = sel.value;
        sel.blur();
        this.#edit(() => (st.frame = v));
      });
      const ftd = wEl("td");
      ftd.append(sel);
      tr.append(ftd);
      const del = this.#button("✕", "Delete step", () => this.#edit(() => w.steps.splice(i, 1)), "danger");
      const dtd = wEl("td");
      dtd.append(del);
      tr.append(dtd);
      table.append(tr);
    });
    f.append(table);
    const row = wEl("div", "btn-row");
    const add = this.#button("Add step", "Append a step after the last one", () =>
      this.#edit(() => {
        const last = w.steps[w.steps.length - 1];
        w.steps.push({ duration: 4, dy: last ? last.dy : 0, frame: last ? last.frame : "idle" });
      }),
    );
    add.disabled = w.steps.length >= GBW_MAX_STEPS;
    row.append(add);
    f.append(row);
    f.append(
      wEl(
        "p",
        "muted gbw-note",
        "Steps run one after another from the shot, each for its duration. After the last step the weapon is back at rest.",
      ),
    );
    if (issues.length) f.append(wEl("p", "error", issues.join(" · ")));
  }

  // ---- preview ----

  fire() {
    this.shots++;
    this.t = 0;
    this.playing = true;
    this.last = 0;
    this.#loop();
  }

  #loop() {
    if (this.raf) return;
    const step = (now) => {
      this.raf = 0;
      if (!this.enabled || !this.playing) return;
      const w = this.selected();
      if (w) {
        if (this.last) this.t += ((now - this.last) / 1000) * GBW_VBLANK_HZ * this.speed;
        this.last = now;
        if (this.loop && this.t >= w.period) {
          this.t -= w.period;
          this.shots++;
        } else if (!this.loop) {
          const def = gbwDef(this.selId);
          const end = Math.max(w.period, gbwAnimLen(def, w), GBW_FLASH_TICKS) + 2;
          if (this.t >= end) {
            this.t = -1;
            this.playing = false;
          }
        }
        this.#draw();
      }
      this.raf = requestAnimationFrame(step);
    };
    this.raf = requestAnimationFrame(step);
  }

  #tlScrub(e) {
    const rect = this.tl.getBoundingClientRect();
    const w = this.selected();
    const def = gbwDef(this.selId);
    if (!w || !def) return;
    const span = Math.max(w.period, gbwAnimLen(def, w), GBW_FLASH_TICKS) + 4;
    const x = ((e.clientX - rect.left) / rect.width) * TL_W;
    this.playing = false;
    this.t = Math.max(0, Math.min(span, Math.floor(((x - 36) / (TL_W - 44)) * span)));
    if (this.shots === 0) this.shots = 1;
    this.#draw();
  }

  /** {canvas, w, h} for a sprite id in `color`; h is the height without trailing blank rows. */
  #sprite(id, color) {
    const key = `${id}|${color}`;
    const hit = this.sprCache.get(key);
    if (hit) return hit;
    const sp = this.opts.getSprites()?.find((s) => s.id === id);
    if (!sp) return null;
    let h = 1;
    for (let y = 0; y < sp.h; y++) if (sp.rows[y].includes("#")) h = y + 1;
    const cv = document.createElement("canvas");
    cv.width = sp.w;
    cv.height = sp.h;
    const c = cv.getContext("2d");
    c.fillStyle = color;
    for (let y = 0; y < sp.h; y++) for (let x = 0; x < sp.w; x++) if (sp.rows[y][x] === "#") c.fillRect(x, y, 1, 1);
    const rec = { canvas: cv, w: sp.w, h, fullH: sp.h };
    this.sprCache.set(key, rec);
    return rec;
  }

  #draw() {
    const def = gbwDef(this.selId);
    const w = this.selected();
    if (!def || !w) return;
    const e = this.t < 0 ? -1 : Math.floor(this.t);
    this.scrub.value = String(Math.max(-1, e));
    const pose = gbwPose(def, w, e);
    const sel = this.shots & 1; // WpnUpdate toggles wFlashSel per shot: the first shot uses flash B
    const dueMs = e < 0 ? "rest" : `${e} VBlanks · ${gbwMs(e).toFixed(0)} ms`;
    const flashOn = e >= 0 && e < GBW_FLASH_TICKS && def.flash.length > 0;
    this.readout.textContent = `${dueMs}${flashOn ? " · flash" : ""}${e >= 0 && e < gbwAnimLen(def, w) ? " · anim" : ""}`;

    // ---- viewport
    const c = this.view.getContext("2d");
    c.imageSmoothingEnabled = false;
    c.fillStyle = COL_VIEW;
    c.fillRect(0, 0, this.view.width, this.view.height);
    let bodyId = def.idle;
    if (pose.alt) bodyId = def.alt;
    else if (def.id === "chaingun" && e >= 0 && e < w.anim && sel) bodyId = def.alt;
    const body = this.#sprite(bodyId, COL_INK);
    c.save();
    c.beginPath();
    c.rect(0, 0, this.view.width, this.view.height);
    c.clip();
    if (body) {
      const bx = (GBW_VIEW_W - body.w) >> 1;
      const by = GBW_VIEW_H - body.h + pose.dy;
      c.drawImage(body.canvas, 0, 0, body.w, body.h, bx * SCALE, by * SCALE, body.w * SCALE, body.h * SCALE);
      if (flashOn) {
        const fl = this.#sprite(def.flash[sel] ?? def.flash[0], COL_FLASH);
        if (fl) {
          const fx = (GBW_VIEW_W - fl.w) >> 1;
          const fy = by - GBW_FLASH_DY;
          c.drawImage(fl.canvas, fx * SCALE, fy * SCALE, fl.w * SCALE, fl.fullH * SCALE);
        }
      }
    }
    c.restore();
    c.strokeStyle = "rgba(255,255,255,0.18)";
    c.strokeRect(0.5, 0.5, this.view.width - 1, this.view.height - 1);

    this.#drawTimeline(def, w, e, pose);
  }

  #drawTimeline(def, w, e) {
    const c = this.tl.getContext("2d");
    const anim = gbwAnimLen(def, w);
    const span = Math.max(w.period, anim, GBW_FLASH_TICKS) + 4;
    const left = 36;
    const right = TL_W - 8;
    const top = 14;
    const bottom = TL_H - 34;
    c.fillStyle = COL_BG;
    c.fillRect(0, 0, TL_W, TL_H);
    // per-VBlank pose values
    const rows = [];
    for (let i = 0; i < span; i++) rows.push(gbwPose(def, w, i));
    const dys = rows.map((r) => r.dy);
    let lo = Math.min(0, ...dys);
    let hi = Math.max(0, ...dys);
    if (hi === lo) hi = lo + 1;
    const X = (v) => left + ((right - left) * v) / span;
    const Y = (v) => bottom - ((bottom - top) * (v - lo)) / (hi - lo);
    c.font = "11px Segoe UI, sans-serif";
    // grid + labels
    c.strokeStyle = "rgba(255,255,255,0.08)";
    c.fillStyle = "rgba(255,255,255,0.55)";
    c.textAlign = "right";
    for (const v of new Set([lo, 0, hi])) {
      c.beginPath();
      c.moveTo(left, Y(v));
      c.lineTo(right, Y(v));
      c.stroke();
      c.fillText(String(v), left - 4, Y(v) + 4);
    }
    c.textAlign = "center";
    const tick = span > 70 ? 10 : 5;
    for (let v = 0; v <= span; v += tick) {
      c.fillText(String(v), X(v), TL_H - 20);
      c.strokeStyle = "rgba(255,255,255,0.06)";
      c.beginPath();
      c.moveTo(X(v), top);
      c.lineTo(X(v), bottom);
      c.stroke();
    }
    c.textAlign = "left";
    c.fillText("VBlanks since the shot", left, TL_H - 6);
    // alt-frame shading, flash bar
    c.fillStyle = "rgba(80,160,255,0.16)";
    rows.forEach((r, i) => {
      if (r.alt || (def.id === "chaingun" && i < w.anim)) c.fillRect(X(i), top, X(i + 1) - X(i), bottom - top);
    });
    if (def.flash.length) {
      c.fillStyle = COL_FLASH;
      c.fillRect(X(0), bottom + 4, X(GBW_FLASH_TICKS) - X(0), 5);
      c.fillStyle = "rgba(255,210,60,0.8)";
      c.fillText("flash", X(GBW_FLASH_TICKS) + 4, bottom + 10);
    }
    // dy curve (a step per VBlank)
    c.strokeStyle = "#7fd6ff";
    c.lineWidth = 2;
    c.beginPath();
    rows.forEach((r, i) => {
      c.lineTo(X(i), Y(r.dy));
      c.lineTo(X(i + 1), Y(r.dy));
    });
    c.stroke();
    c.lineWidth = 1;
    // anim end + period
    const mark = (v, color, label) => {
      c.strokeStyle = color;
      c.setLineDash([4, 3]);
      c.beginPath();
      c.moveTo(X(v), top - 4);
      c.lineTo(X(v), bottom);
      c.stroke();
      c.setLineDash([]);
      c.fillStyle = color;
      c.textAlign = "center";
      c.fillText(label, X(v), top - 4);
    };
    if (anim) mark(anim, "#9bd17a", `anim ${anim}`);
    mark(w.period, "#ff9a6a", `period ${w.period}`);
    // cursor
    if (e >= 0) {
      const cx = X(Math.min(span, this.t));
      c.strokeStyle = "#fff";
      c.beginPath();
      c.moveTo(cx, top);
      c.lineTo(cx, bottom);
      c.stroke();
    }
    c.textAlign = "left";
  }

  handleKey(e) {
    if (e.key === " " && !e.ctrlKey && !e.metaKey) {
      this.fire();
      return true;
    }
    return false;
  }

  get enabled() {
    return this._en;
  }

  set enabled(on) {
    this._en = on;
    if (!on) {
      this.playing = false;
      if (this.raf) cancelAnimationFrame(this.raf);
      this.raf = 0;
    }
  }
}
