import {
  aabbCenter,
  clipForFrame,
  clampVertFor,
  enemyHasSprites,
  ANIM_ORBIT_DIST_MIN,
  ANIM_ORBIT_DIST_MAX,
} from "./model.js";
import {
  cornerWorld,
  distPointToSegment2d,
  intersectPlane,
  lookVectors,
  projectLine,
  projectPoint,
  screenRay,
} from "./math3d.js";
import { STICK_GROUND_Y } from "./stickOrtho.js";
import {
  GIZMO_FALLBACK_LEN,
  drawTranslateGizmo,
  gizmoAxisDragDelta,
  hitTranslateGizmo,
} from "./gizmo.js";

const ANIM_BOX_CLICK = 4;
const ANIM_ZOOM_K = 0.008;
function clampAnimDist(d) {
  return Math.max(ANIM_ORBIT_DIST_MIN, Math.min(ANIM_ORBIT_DIST_MAX, d));
}

export class AnimView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.orbit = { yaw: 0.5, pitch: 0.15, dist: 48, target: { x: 0, y: 10, z: 0 } };
    this.groundPanY = 0;
    this.drag = null;
    this.hover = -1;
    this.hoverLine = -1;
    this.hoverGizmo = null;
    this.enabled = false;
    this._ro = new ResizeObserver(() => this.resize());
    this._ro.observe(opts.stage || canvas.parentElement);
    this.resize();

    canvas.addEventListener("pointerdown", (e) => this.#onDown(e));
    canvas.addEventListener("pointermove", (e) => this.#onMove(e));
    canvas.addEventListener("pointerup", (e) => this.#onUp(e));
    canvas.addEventListener("pointerleave", (e) => this.#onUp(e));
    canvas.addEventListener("wheel", (e) => this.#onWheel(e), { passive: false });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());
    canvas.addEventListener("mousedown", (e) => {
      if (e.button === 1) e.preventDefault();
    });
    canvas.addEventListener("auxclick", (e) => {
      if (e.button === 1) e.preventDefault();
    });
  }

  resize() {
    if (!this.enabled) return;
    const stage = this.opts.stage || this.canvas.parentElement;
    const stick = stage?.classList.contains("stick-stage");
    if (stick) {
      this.canvas.style.width = "";
      this.canvas.style.height = "";
    }
    const rect = (stick ? this.canvas : stage).getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(64, Math.floor(rect.width));
    const h = Math.max(64, Math.floor(rect.height));
    this.canvas.width = Math.floor(w * dpr);
    this.canvas.height = Math.floor(h * dpr);
    if (!stick) {
      this.canvas.style.width = `${w}px`;
      this.canvas.style.height = `${h}px`;
    }
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.cssW = w;
    this.cssH = h;
    this.draw();
    this.opts.onStageResize?.();
  }

  #overlay() {
    return this.opts.getMeshOverlay?.() || null;
  }

  #hasStick() {
    return this.opts.hasStickFrame?.() !== false;
  }

  #binding() {
    const overlay = this.#overlay();
    return !!(overlay && (overlay.binding || overlay.bindJoint >= 0));
  }

  #custom() {
    return !!this.opts.getEnemy()?.customSkeleton;
  }

  #cam() {
    const { yaw, pitch, dist, target } = this.orbit;
    const { forward } = lookVectors(yaw, pitch);
    const cam = {
      x: target.x - forward.x * dist,
      y: target.y - forward.y * dist,
      z: target.z - forward.z * dist,
      yaw,
      pitch,
    };
    const w = this.cssW;
    const h = this.cssH;
    if (w && h) {
      const raw = projectPoint({ x: 0, y: 0, z: 0 }, cam, w, h);
      if (raw.ok) cam.sy0 = h * 0.5 + (h * STICK_GROUND_Y + this.groundPanY - raw.sy);
    }
    return cam;
  }

  /** Pixels per world unit on the view plane through the XZ origin. */
  pixelsAtOrigin() {
    const w = this.cssW;
    const h = this.cssH;
    if (!w || !h) return 0;
    const cam = this.#cam();
    const { forward } = lookVectors(cam.yaw, cam.pitch);
    const cz = -cam.x * forward.x - cam.y * forward.y - cam.z * forward.z;
    if (!(cz > 0.5)) return 0;
    return (Math.min(w, h) * 0.9) / cz;
  }

  /** Frame stick/MDL verts; if none, center on origin without changing dist. */
  focusObject() {
    let points = null;
    if (this.#hasStick()) {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      points = enemy?.frames?.[frame] || enemy?.frames?.[0] || null;
    }
    if (!points?.length) {
      const overlay = this.#overlay();
      points = overlay?.verts || null;
    }
    if (!points?.length) {
      this.orbit.target = { x: 0, y: 0, z: 0 };
      this.opts.onViewChanged?.();
      this.draw();
      return true;
    }

    let minx = Infinity;
    let miny = Infinity;
    let minz = Infinity;
    let maxx = -Infinity;
    let maxy = -Infinity;
    let maxz = -Infinity;
    for (const v of points) {
      minx = Math.min(minx, v.x);
      miny = Math.min(miny, v.y);
      minz = Math.min(minz, v.z);
      maxx = Math.max(maxx, v.x);
      maxy = Math.max(maxy, v.y);
      maxz = Math.max(maxz, v.z);
    }
    const box = {
      x: minx,
      y: miny,
      z: minz,
      sx: Math.max(1e-3, maxx - minx),
      sy: Math.max(1e-3, maxy - miny),
      sz: Math.max(1e-3, maxz - minz),
    };
    const center = aabbCenter(box);
    const { yaw, pitch } = this.orbit;
    const { forward, right, up } = lookVectors(yaw, pitch);
    const w = this.cssW;
    const h = this.cssH;
    const focal = Math.min(w, h) * 0.9;
    const pad = 0.82;
    const halfW = Math.max(1, w * 0.5 * pad);
    const halfH = Math.max(1, h * 0.5 * pad);

    let frameDist = 4;
    for (let i = 0; i < 8; i++) {
      const c = cornerWorld(box, i);
      const rx = c.x - center.x;
      const ry = c.y - center.y;
      const rz = c.z - center.z;
      const cx = rx * right.x + ry * right.y + rz * right.z;
      const cy = rx * up.x + ry * up.y + rz * up.z;
      const cz = rx * forward.x + ry * forward.y + rz * forward.z;
      frameDist = Math.max(frameDist, (Math.abs(cx) * focal) / halfW - cz);
      frameDist = Math.max(frameDist, (Math.abs(cy) * focal) / halfH - cz);
      frameDist = Math.max(frameDist, 1 - cz);
    }

    this.orbit.target = { x: center.x, y: center.y, z: center.z };
    this.orbit.dist = clampAnimDist(frameDist);
    this.opts.onZoomSync?.();
    this.opts.onViewChanged?.();
    this.draw();
    return true;
  }

  #eventPos(e) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * this.cssW,
      y: ((e.clientY - rect.top) / rect.height) * this.cssH,
    };
  }

  #selectedIndices() {
    return this.opts.getSelectedVerts?.() || [];
  }

  #selectionAnchor() {
    if (!this.#hasStick()) return null;
    const selected = this.#selectedIndices();
    if (!selected.length) return null;
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const verts = enemy.frames[frame];
    if (selected.length === 1) {
      const i = selected[0];
      return { index: i, v: verts[i], indices: selected };
    }
    let x = 0;
    let y = 0;
    let z = 0;
    for (const i of selected) {
      x += verts[i].x;
      y += verts[i].y;
      z += verts[i].z;
    }
    const n = selected.length;
    return { index: selected[selected.length - 1], v: { x: x / n, y: y / n, z: z / n }, indices: selected };
  }

  #gizmoDragOrigs(prim) {
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const verts = enemy.frames[frame];
    return prim.indices.map((i) => ({
      i,
      x: verts[i].x,
      y: verts[i].y,
      z: verts[i].z,
    }));
  }

  #startGizmoDrag(gizmoHit, prim, p) {
    this.opts.beginUndo?.();
    this.drag = {
      kind: gizmoHit.kind,
      axis: gizmoHit.axis,
      plane: gizmoHit.plane,
      planeN: gizmoHit.planeN,
      grab: gizmoHit.world,
      gizmoAxisLen: gizmoHit.gizmoAxisLen ?? GIZMO_FALLBACK_LEN,
      origs: this.#gizmoDragOrigs(prim),
      orig: { x: prim.v.x, y: prim.v.y, z: prim.v.z },
      start: p,
    };
  }

  #hitAmong(verts, mx, my, radius = 10) {
    const cam = this.#cam();
    let best = -1;
    let bestD = radius;
    verts.forEach((v, i) => {
      const p = projectPoint(v, cam, this.cssW, this.cssH);
      if (!p.ok) return;
      const d = Math.hypot(mx - p.sx, my - p.sy);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    });
    return best;
  }

  #hitVert(mx, my) {
    const overlay = this.#overlay();
    if (this.#binding()) return this.#hitAmong(overlay.verts, mx, my, 8);
    if (!this.#hasStick()) return -1;
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    return this.#hitAmong(enemy.frames[frame], mx, my, 10);
  }

  #hitLine(mx, my) {
    if (!this.#custom() || this.#binding() || !this.#hasStick()) return -1;
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const verts = enemy.frames[frame];
    if (!verts) return -1;
    const cam = this.#cam();
    let best = -1;
    let bestD = 6;
    enemy.lines.forEach(([ia, ib], i) => {
      const a = verts[ia];
      const b = verts[ib];
      if (!a || !b) return;
      const pl = projectLine(a, b, cam, this.cssW, this.cssH);
      if (!pl) return;
      const d = distPointToSegment2d(mx, my, pl.ax, pl.ay, pl.bx, pl.by);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    });
    return best;
  }

  zoomBy(factor) {
    this.orbit.dist = clampAnimDist(this.orbit.dist * factor);
    this.opts.onZoomSync?.();
    this.opts.onViewChanged?.();
    this.draw();
  }

  #onWheel(e) {
    if (!this.enabled) return;
    e.preventDefault();
    this.zoomBy(e.deltaY > 0 ? 1.1 : 1 / 1.1);
  }

  #onDown(e) {
    if (!this.enabled) return;
    this.canvas.focus();
    const p = this.#eventPos(e);
    if (e.button === 2 && e.altKey) {
      this.drag = { kind: "zoom", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button === 1) {
      this.drag = { kind: "pan", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button === 2) {
      this.drag = { kind: "orbit", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0) return;
    if (e.altKey) {
      e.preventDefault();
      this.drag = { kind: "orbit", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    const binding = this.#binding();
    if (!binding) {
      const prim = this.#selectionAnchor();
      if (prim) {
        const gizmoHit = hitTranslateGizmo(prim.v, this.#cam(), this.cssW, this.cssH, p.x, p.y);
        if (gizmoHit) {
          this.#startGizmoDrag(gizmoHit, prim, p);
          this.canvas.setPointerCapture(e.pointerId);
          return;
        }
      }
    }

    const vi = this.#hitVert(p.x, p.y);
    if (vi >= 0) {
      if (binding) {
        this.opts.onSelectMeshVert?.(vi, e.shiftKey);
        this.drag = { kind: "select" };
        this.canvas.setPointerCapture(e.pointerId);
        this.draw();
        return;
      }
      const selected = this.opts.getSelectedVerts?.() || [];
      const wasSelected = selected.includes(vi);
      this.opts.onSelectVert?.(vi, e.shiftKey);
      if (!wasSelected && !e.shiftKey) {
        const enemy = this.opts.getEnemy();
        const frame = this.opts.getFrame();
        const v = enemy.frames[frame][vi];
        this.drag = {
          kind: "slide",
          index: vi,
          lock: this.#lockAxis(),
          orig: { x: v.x, y: v.y, z: v.z },
          undoStarted: false,
        };
      } else {
        this.drag = { kind: "select" };
      }
      this.canvas.setPointerCapture(e.pointerId);
      this.draw();
      return;
    }
    if (!binding && this.#custom()) {
      const li = this.#hitLine(p.x, p.y);
      if (li >= 0) {
        this.opts.onSelectLine?.(li, e.shiftKey);
        this.drag = { kind: "select" };
        this.canvas.setPointerCapture(e.pointerId);
        this.draw();
        return;
      }
    }
    this.drag = { kind: "box", start: p, end: p, additive: e.shiftKey };
    this.canvas.setPointerCapture(e.pointerId);
  }

  #onMove(e) {
    if (!this.enabled) return;
    const p = this.#eventPos(e);
    if (!this.drag) {
      const binding = this.#binding();
      const prim = binding ? null : this.#selectionAnchor();
      this.hover = this.#hitVert(p.x, p.y);
      this.hoverGizmo =
        prim && this.hover < 0
          ? hitTranslateGizmo(prim.v, this.#cam(), this.cssW, this.cssH, p.x, p.y)
          : null;
      this.hoverLine = binding || this.hover >= 0 || this.hoverGizmo ? -1 : this.#hitLine(p.x, p.y);
      this.draw();
      return;
    }
    if (this.drag.kind === "orbit") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      this.orbit.yaw += dx * 0.01;
      this.orbit.pitch = Math.max(-1.2, Math.min(1.2, this.orbit.pitch - dy * 0.01));
      this.draw();
      return;
    }
    if (this.drag.kind === "pan") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      if (dx) {
        const focal = Math.min(this.cssW, this.cssH) * 0.9;
        const scale = this.orbit.dist / focal;
        const { right } = lookVectors(this.orbit.yaw, this.orbit.pitch);
        const t = this.orbit.target;
        t.x += -right.x * dx * scale;
        t.z += -right.z * dx * scale;
      }
      if (dy) this.groundPanY += dy;
      this.draw();
      return;
    }
    if (this.drag.kind === "zoom") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      const delta = dx + dy;
      if (delta) this.zoomBy(Math.exp(-delta * ANIM_ZOOM_K));
      return;
    }
    if (this.drag.kind === "box") {
      this.drag.end = p;
      this.draw();
      return;
    }
    if (this.drag.kind === "axis") {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const verts = enemy.frames[frame];
      const delta = gizmoAxisDragDelta(
        p,
        this.drag.grab,
        this.drag.axis,
        this.drag.start,
        this.drag.gizmoAxisLen ?? GIZMO_FALLBACK_LEN,
        this.#cam(),
        this.cssW,
        this.cssH,
        !enemyHasSprites(enemy)
      );
      if (delta == null) return;
      const clamp = clampVertFor(enemy);
      for (const o of this.drag.origs) {
        const v = verts[o.i];
        v.x = o.x;
        v.y = o.y;
        v.z = o.z;
        v[this.drag.axis] = clamp(o[this.drag.axis] + delta);
      }
      this.opts.onChange?.();
      this.draw();
      return;
    }
    if (this.drag.kind === "plane") {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const verts = enemy.frames[frame];
      const ray = screenRay(p.x, p.y, this.#cam(), this.cssW, this.cssH);
      const hit = intersectPlane(ray.origin, ray.dir, this.drag.grab, this.drag.planeN);
      if (!hit) return;
      const fine = enemyHasSprites(enemy);
      const raw = (n) => (fine ? n : Math.round(n));
      let dx = raw(hit.point.x - this.drag.grab.x);
      let dy = raw(hit.point.y - this.drag.grab.y);
      let dz = raw(hit.point.z - this.drag.grab.z);
      if (this.drag.plane === "xy") dz = 0;
      else if (this.drag.plane === "xz") dy = 0;
      else if (this.drag.plane === "yz") dx = 0;
      const clamp = clampVertFor(enemy);
      for (const o of this.drag.origs) {
        const v = verts[o.i];
        v.x = clamp(o.x + dx);
        v.y = clamp(o.y + dy);
        v.z = clamp(o.z + dz);
      }
      this.opts.onChange?.();
      this.draw();
      return;
    }
    if (this.drag.kind === "slide") {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const v = enemy.frames[frame][this.drag.index];
      const orig = this.drag.orig;
      const cam = this.#cam();
      const ray = screenRay(p.x, p.y, cam, this.cssW, this.cssH);
      const n = { x: 0, y: 0, z: 0 };
      n[this.drag.lock] = 1;
      const hit = intersectPlane(ray.origin, ray.dir, orig, n);
      if (!hit) return;
      const clamp = clampVertFor(enemy);
      const next = {
        x: this.drag.lock === "x" ? orig.x : clamp(hit.point.x),
        y: this.drag.lock === "y" ? orig.y : clamp(hit.point.y),
        z: this.drag.lock === "z" ? orig.z : clamp(hit.point.z),
      };
      if (next.x === v.x && next.y === v.y && next.z === v.z) return;
      if (!this.drag.undoStarted) {
        this.opts.beginUndo?.();
        this.drag.undoStarted = true;
      }
      v.x = next.x;
      v.y = next.y;
      v.z = next.z;
      this.opts.onChange?.();
      this.draw();
    }
  }

  #lockAxis() {
    const { forward } = lookVectors(this.orbit.yaw, this.orbit.pitch);
    const ax = Math.abs(forward.x);
    const ay = Math.abs(forward.y);
    const az = Math.abs(forward.z);
    if (ax >= ay && ax >= az) return "x";
    if (ay >= az) return "y";
    return "z";
  }

  #boxRect() {
    const a = this.drag.start;
    const b = this.drag.end;
    const x0 = Math.min(a.x, b.x);
    const y0 = Math.min(a.y, b.y);
    const x1 = Math.max(a.x, b.x);
    const y1 = Math.max(a.y, b.y);
    return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
  }

  #vertsInBox(rect) {
    const overlay = this.#overlay();
    const verts =
      overlay && (overlay.binding || overlay.bindJoint >= 0)
        ? overlay.verts
        : this.#hasStick()
          ? this.opts.getEnemy().frames[this.opts.getFrame()]
          : [];
    const cam = this.#cam();
    const hits = [];
    verts.forEach((v, i) => {
      const p = projectPoint(v, cam, this.cssW, this.cssH);
      if (!p.ok) return;
      if (p.sx >= rect.x0 && p.sx <= rect.x1 && p.sy >= rect.y0 && p.sy <= rect.y1) hits.push(i);
    });
    return hits;
  }

  #finishBox() {
    const rect = this.#boxRect();
    const additive = this.drag.additive;
    const binding = this.#binding();
    if (rect.w < ANIM_BOX_CLICK && rect.h < ANIM_BOX_CLICK) {
      if (binding) {
        if (!additive) this.opts.onSelectMeshVerts?.([], false);
      } else if (!additive) this.opts.onSelectVerts?.([]);
      return;
    }
    const hits = this.#vertsInBox(rect);
    if (binding) this.opts.onSelectMeshVerts?.(hits, additive);
    else this.opts.onSelectVerts?.(hits, additive);
  }

  #onUp(e) {
    if (!this.enabled) return;
    const orbitEnded =
      this.drag?.kind === "orbit" || this.drag?.kind === "zoom" || this.drag?.kind === "pan";
    if (this.drag?.kind === "box") this.#finishBox();
    if (this.drag?.kind === "axis" || this.drag?.kind === "plane" || this.drag?.undoStarted) {
      this.opts.endUndo?.();
    }
    this.drag = null;
    if (orbitEnded) this.opts.onViewChanged?.();
    try {
      this.canvas.releasePointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    this.draw();
  }

  #strokeSeg(ctx, cam, w, h, p0, p1, col, width = 1) {
    const seg = projectLine(p0, p1, cam, w, h);
    if (!seg) return;
    ctx.strokeStyle = col;
    ctx.lineWidth = width;
    ctx.beginPath();
    ctx.moveTo(seg.ax, seg.ay);
    ctx.lineTo(seg.bx, seg.by);
    ctx.stroke();
  }

  #drawForwardArrow(ctx, cam, w, h) {
    const y = 0.2;
    const tip = { x: 0, y, z: 14 };
    const col = "#d4a017";
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y, z: 0 }, tip, col, 2.5);
    this.#strokeSeg(ctx, cam, w, h, tip, { x: 2.5, y, z: 10 }, col, 2);
    this.#strokeSeg(ctx, cam, w, h, tip, { x: -2.5, y, z: 10 }, col, 2);
    this.#strokeSeg(ctx, cam, w, h, tip, { x: 0, y: 2.5, z: 10 }, col, 2);
    const label = projectPoint({ x: 0, y: 1.5, z: 16 }, cam, w, h);
    if (label.ok) {
      ctx.fillStyle = col;
      ctx.font = "11px Segoe UI, sans-serif";
      ctx.fillText("fwd", label.sx - 10, label.sy);
    }
  }

  #drawGizmo(ctx, cam, w, h, v) {
    drawTranslateGizmo(ctx, v, cam, w, h, { hoverGizmo: this.hoverGizmo, drag: this.drag });
  }

  draw() {
    if (!this.enabled) return;
    const ctx = this.ctx;
    const w = this.cssW;
    const h = this.cssH;
    if (!w || !h) return;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, w, h);

    const cam = this.#cam();
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const selected = this.opts.getSelectedVerts?.() || [];
    const selectedLines = this.opts.getSelectedLines?.() || [];
    const overlay = this.#overlay();
    const binding = overlay && (overlay.binding || overlay.bindJoint >= 0);
    const stickOn = this.#hasStick();
    const verts = stickOn ? enemy.frames[frame] || enemy.frames[0] : null;
    let shown = selected;
    let meshShown = overlay ? [...(overlay.meshSel || [])] : [];
    if (this.drag?.kind === "box") {
      const r = this.#boxRect();
      if (r.w >= ANIM_BOX_CLICK || r.h >= ANIM_BOX_CLICK) {
        const hits = this.#vertsInBox(r);
        if (binding) {
          meshShown = this.drag.additive ? [...new Set([...meshShown, ...hits])] : hits;
        } else {
          shown = this.drag.additive ? [...new Set([...selected, ...hits])] : hits;
        }
      }
    }

    ctx.lineWidth = 1;
    for (let i = -24; i <= 24; i += 8) {
      this.#strokeSeg(ctx, cam, w, h, { x: i, y: 0, z: -24 }, { x: i, y: 0, z: 24 }, "#3d4658");
      this.#strokeSeg(ctx, cam, w, h, { x: -24, y: 0, z: i }, { x: 24, y: 0, z: i }, "#3d4658");
    }
    this.#strokeSeg(ctx, cam, w, h, { x: -20, y: 0, z: 0 }, { x: 20, y: 0, z: 0 }, "#a66");
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y: 0, z: 0 }, { x: 0, y: 24, z: 0 }, "#6a6");
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y: 0, z: -20 }, { x: 0, y: 0, z: 20 }, "#66a");
    this.#drawForwardArrow(ctx, cam, w, h);

    if (overlay) {
      ctx.lineWidth = 1;
      for (const [i, j] of overlay.edges) {
        const a = overlay.verts[i];
        const b = overlay.verts[j];
        if (a && b) this.#strokeSeg(ctx, cam, w, h, a, b, "#3a4458", 1);
      }
      if (overlay.ghost) {
        for (const [i, j] of overlay.lines || enemy.lines) {
          const a = overlay.ghost[i];
          const b = overlay.ghost[j];
          if (a && b) this.#strokeSeg(ctx, cam, w, h, a, b, "#5ec8c8", 1.5);
        }
        overlay.ghost.forEach((v) => {
          if (!v) return;
          const p = projectPoint(v, cam, w, h);
          if (!p.ok) return;
          ctx.fillStyle = "#5ec8c8";
          ctx.beginPath();
          ctx.arc(p.sx, p.sy, 4, 0, Math.PI * 2);
          ctx.fill();
        });
      }
    }

    if (stickOn && verts) {
      ctx.lineWidth = 1.5;
      enemy.lines.forEach(([i, j], li) => {
        const sel = !binding && selectedLines.includes(li);
        const ho = !binding && li === this.hoverLine;
        this.#strokeSeg(ctx, cam, w, h, verts[i], verts[j], sel ? "#f2d36b" : ho ? "#fff" : "#c8ccd4", sel || ho ? 2.5 : 1.5);
      });

      verts.forEach((v, i) => {
        const p = projectPoint(v, cam, w, h);
        if (!p.ok) return;
        const sel = !binding && shown.includes(i);
        const hover = !binding && i === this.hover;
        ctx.fillStyle = sel ? "#d4a017" : hover ? "#fff" : "#8b91a0";
        const r = sel ? 5 : 4;
        ctx.beginPath();
        ctx.arc(p.sx, p.sy, r, 0, Math.PI * 2);
        ctx.fill();
      });
    }

    if (binding) {
      const assignedOther = new Set();
      overlay.jointVerts.forEach((list, ji) => {
        if (overlay.bindJoint >= 0 && ji === overlay.bindJoint) return;
        for (const i of list) assignedOther.add(i);
      });
      overlay.verts.forEach((v, i) => {
        const p = projectPoint(v, cam, w, h);
        if (!p.ok) return;
        const sel = meshShown.includes(i);
        const hover = i === this.hover;
        const other = assignedOther.has(i);
        ctx.fillStyle = sel ? "#d4a017" : hover ? "#fff" : other ? "#5ec8c8" : "#5a6270";
        const r = sel || hover ? 3.5 : 2.5;
        ctx.beginPath();
        ctx.arc(p.sx, p.sy, r, 0, Math.PI * 2);
        ctx.fill();
      });
    }

    const prim = this.#selectionAnchor();
    if (prim && !binding && stickOn) this.#drawGizmo(ctx, cam, w, h, prim.v);

    if (this.drag?.kind === "box") {
      const r = this.#boxRect();
      ctx.fillStyle = "rgba(212, 160, 23, 0.12)";
      ctx.fillRect(r.x0, r.y0, r.w, r.h);
      ctx.strokeStyle = "#d4a017";
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.strokeRect(r.x0 + 0.5, r.y0 + 0.5, r.w, r.h);
      ctx.setLineDash([]);
    }

    ctx.fillStyle = "#8b91a0";
    ctx.font = "11px Segoe UI, sans-serif";
    const clip = clipForFrame(enemy.clips, frame);
    const previewLocal = this.opts.getLocalFrame?.();
    const previewClip = this.opts.getClipName?.();
    let label = "rest";
    if (previewClip && previewLocal != null) {
      label = `${previewClip} ${previewLocal}`;
    } else if (stickOn && enemy.clips?.length && clip) {
      label = `${clip.name} ${frame - clip.start}`;
    }
    const frameTotal = stickOn && enemy.clips?.length ? enemy.frames.length : overlay ? "MDL" : enemy.frames.length;
    const nv = (stickOn ? enemy.frames[frame] || enemy.frames[0] : null)?.length || enemy.verts || 0;
    ctx.fillText(`${enemy.name} · ${label} · ${nv} verts · ${frameTotal} frames`, 8, 16);
    this.opts.onDrawn?.();
  }
}
