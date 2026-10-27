/** Orthographic stick pane. Front edits X/Y. Left edits Z/Y. */

export const STICK_GROUND_Y = 0.72;

const HIT = 8;

function clampCoord(v, lim) {
  const n = Math.round(v);
  if (n < -lim) return -lim;
  if (n > lim) return lim;
  return n;
}

export class StickOrtho {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.drag = null;
    this.px = 4;
    this.panX = 0;
    this.panY = 0;
    this.enabled = false;
    canvas.addEventListener("pointerdown", (e) => this.#onDown(e));
    canvas.addEventListener("pointermove", (e) => this.#onMove(e));
    canvas.addEventListener("pointerup", (e) => this.#onUp(e));
    canvas.addEventListener("pointerleave", (e) => this.#onUp(e));
    canvas.addEventListener("wheel", (e) => this.#onWheel(e), { passive: false });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());
    canvas.addEventListener("mousedown", (e) => {
      if (e.button === 1) e.preventDefault();
    });
  }

  resize() {
    if (!this.enabled) return;
    const rect = this.canvas.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(32, Math.floor(rect.width));
    const h = Math.max(32, Math.floor(rect.height));
    this.canvas.width = Math.floor(w * dpr);
    this.canvas.height = Math.floor(h * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.cssW = w;
    this.cssH = h;
    this.draw();
  }

  #enemy() {
    return this.opts.getEnemy?.() || null;
  }

  #verts() {
    const e = this.#enemy();
    const fi = this.opts.getFrame?.() ?? 0;
    return e?.frames?.[fi] || null;
  }

  #groundPan() {
    return this.opts.getGroundPan?.() ?? this.panY;
  }

  #origin() {
    return {
      x: this.cssW * 0.5 + this.panX,
      y: this.cssH * STICK_GROUND_Y + this.#groundPan(),
    };
  }

  // Front looks along -Z, so screen-right is -X, matching the perspective camera.
  // Left looks along +X (180° from the old right view), so screen-right is -Z.
  #sign() {
    return -1;
  }

  #toScreen(v) {
    const o = this.#origin();
    const horiz = this.opts.horiz === "z" ? v.z : v.x;
    return { x: o.x + this.#sign() * horiz * this.px, y: o.y - v.y * this.px };
  }

  #eventPos(e) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * this.cssW,
      y: ((e.clientY - rect.top) / rect.height) * this.cssH,
    };
  }

  #hitVert(sx, sy) {
    const verts = this.#verts();
    if (!verts) return -1;
    let best = -1;
    let bestD = HIT * HIT;
    for (let i = 0; i < verts.length; i++) {
      const p = this.#toScreen(verts[i]);
      const d = (p.x - sx) ** 2 + (p.y - sy) ** 2;
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  #onDown(e) {
    if (!this.enabled) return;
    const p = this.#eventPos(e);
    if (e.button === 1 || e.button === 2) {
      this.drag = { kind: "pan", x: p.x, y: p.y, panX: this.panX, panY: this.#groundPan() };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0) return;
    const hit = this.#hitVert(p.x, p.y);
    if (hit < 0) return;
    const selected = this.opts.getSelected?.() || [];
    const next = e.shiftKey
      ? selected.includes(hit)
        ? selected.filter((i) => i !== hit)
        : [...selected, hit]
      : selected.includes(hit)
        ? selected
        : [hit];
    this.opts.onSelect?.(next);
    const verts = this.#verts();
    this.drag = {
      kind: "vert",
      x: p.x,
      y: p.y,
      indices: next.slice(),
      start: next.map((i) => ({ ...verts[i] })),
      undo: false,
    };
    this.canvas.setPointerCapture(e.pointerId);
  }

  #onMove(e) {
    if (!this.drag) return;
    const p = this.#eventPos(e);
    if (this.drag.kind === "pan") {
      this.panX = this.drag.panX + (p.x - this.drag.x);
      const panY = this.drag.panY + (p.y - this.drag.y);
      if (this.opts.setGroundPan) this.opts.setGroundPan(panY);
      else this.panY = panY;
      this.draw();
      return;
    }
    if (!this.drag.undo) {
      this.opts.beginUndo?.();
      this.drag.undo = true;
    }
    const verts = this.#verts();
    const lim = this.opts.vertLimit?.() ?? 127;
    const quant = this.opts.clampVert;
    const du = (p.x - this.drag.x) / this.px;
    const dy = (this.drag.y - p.y) / this.px;
    const horiz = this.opts.horiz === "z" ? "z" : "x";
    const sign = this.#sign();
    this.drag.indices.forEach((i, n) => {
      const src = this.drag.start[n];
      if (!src || !verts[i]) return;
      const x = src[horiz] + sign * du;
      const y = src.y + dy;
      verts[i][horiz] = quant ? quant(x) : clampCoord(x, lim);
      verts[i].y = quant ? quant(y) : clampCoord(y, lim);
    });
    this.draw();
    this.opts.onPose?.();
  }

  #onUp(e) {
    if (!this.drag) return;
    if (this.drag.undo) this.opts.endUndo?.();
    this.drag = null;
    if (this.canvas.hasPointerCapture?.(e.pointerId)) this.canvas.releasePointerCapture(e.pointerId);
    this.opts.onPose?.();
  }

  setScale(px) {
    this.px = Math.max(0.05, Math.min(800, px));
  }

  #onWheel(e) {
    if (!this.enabled) return;
    e.preventDefault();
    this.opts.onZoom?.(e.deltaY > 0 ? 1.1 : 1 / 1.1);
  }

  draw() {
    if (!this.enabled) return;
    const ctx = this.ctx;
    const w = this.cssW;
    const h = this.cssH;
    if (!w || !h) return;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, w, h);
    const e = this.#enemy();
    const verts = this.#verts();
    const o = this.#origin();
    const sprite = this.opts.getSprite?.();
    const scale = this.opts.spriteScale?.() ?? 1;
    if (sprite?.canvas) {
      const k = scale * this.px;
      const dw = sprite.canvas.width * k;
      const dh = sprite.canvas.height * k;
      const left = sprite.flip ? sprite.canvas.width - sprite.left : sprite.left;
      const dx = o.x - left * k;
      const dy = o.y - sprite.top * k;
      ctx.save();
      ctx.globalAlpha = 0.85;
      if (sprite.flip) {
        ctx.translate(dx + dw, dy);
        ctx.scale(-1, 1);
        ctx.drawImage(sprite.canvas, 0, 0, dw, dh);
      } else {
        ctx.drawImage(sprite.canvas, dx, dy, dw, dh);
      }
      ctx.restore();
    }
    if (!verts) return;
    const selected = new Set(this.opts.getSelected?.() || []);
    ctx.lineWidth = 1.5;
    for (const [a, b] of e.lines || []) {
      const pa = verts[a];
      const pb = verts[b];
      if (!pa || !pb) continue;
      const sa = this.#toScreen(pa);
      const sb = this.#toScreen(pb);
      ctx.strokeStyle = "#9ab";
      ctx.beginPath();
      ctx.moveTo(sa.x, sa.y);
      ctx.lineTo(sb.x, sb.y);
      ctx.stroke();
    }
    for (let i = 0; i < verts.length; i++) {
      const p = this.#toScreen(verts[i]);
      ctx.fillStyle = selected.has(i) ? "#fc6" : "#eee";
      ctx.beginPath();
      ctx.arc(p.x, p.y, selected.has(i) ? 4.5 : 3, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}
