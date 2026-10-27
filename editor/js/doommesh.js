/** MD2/MD3 monsters → the same clip/frame/tri shape as parseMdl.
 *  Frames are Quake-space floats (X forward, Y left, Z up) on frame.xyz.
 *  Clip indices match tools/doommdl.py DOOM_CLIPS. */

const IMPORT_SCALE = 0.75;
const MAX_OVERLAY_TRIS = 600;

const DOOM_PARTS = {
  Possessed: [
    "models/monsters/soldiers/doom_body.md2",
    "models/monsters/soldiers/head_fodder.md2",
    "models/monsters/soldiers/weapon_rifle.md2",
  ],
  Imp: ["models/monsters/doomimp/imp.md2", "models/monsters/doomimp/imp-hand.md2"],
  Pinky: ["models/monsters/demon/pinky.md3"],
  Baron: [
    "models/monsters/baronofhell/bruiser_body.md2",
    "models/monsters/baronofhell/bruiser_head.md2",
  ],
};

const DOOM_CLIPS = {
  Possessed: [
    ["stand", [[0, 0, 0]]],
    ["walk", [[0, 0, 0], [2, 2, 2], [4, 4, 4], [6, 6, 6]]],
    ["pain", [[54, 22, 0], [55, 22, 0], [56, 22, 0]]],
    ["missile", [[8, 8, 8], [9, 9, 9], [10, 10, 10]]],
    ["death", [[57, 26, 0], [58, 26, 0], [60, 28, 0], [62, 30, 0], [64, 32, 0]]],
  ],
  Imp: [
    ["stand", [[1, 1]]],
    ["walk", [[1, 1], [3, 3], [5, 5], [7, 7]]],
    ["pain", [[23, 23]]],
    ["melee", [[10, 10], [13, 13]]],
    ["missile", [[10, 10], [12, 12]]],
    ["death", [[23, 23]]],
  ],
  Pinky: [
    ["stand", [[0]]],
    ["walk", [[0], [4], [8], [12]]],
    ["pain", [[24]]],
    ["melee", [[20], [22]]],
    ["death", [[28], [35], [36], [37], [40], [41], [42], [46]]],
  ],
  Baron: [
    ["stand", [[2, 2]]],
    ["walk", [[2, 2], [4, 4], [6, 6], [8, 8]]],
    ["pain", [[18, 18]]],
    ["melee", [[13, 13], [14, 14]]],
    ["missile", [[13, 13], [14, 14]]],
    ["death", [[18, 18]]],
  ],
};

function quake(x, y, z) {
  const s = IMPORT_SCALE;
  return [y * s, -x * s, z * s];
}

function strideTris(tris) {
  const n = tris.length;
  if (n <= MAX_OVERLAY_TRIS) return tris;
  const step = Math.ceil(n / MAX_OVERLAY_TRIS);
  const out = [];
  for (let i = 0; i < n; i += step) out.push(tris[i]);
  return out;
}

function uniqueEdges(tris) {
  const seen = new Set();
  const edges = [];
  const add = (a, b) => {
    if (a === b) return;
    const lo = a < b ? a : b;
    const hi = a < b ? b : a;
    const key = lo + ":" + hi;
    if (seen.has(key)) return;
    seen.add(key);
    edges.push([lo, hi]);
  };
  for (const t of tris) {
    add(t[0], t[1]);
    add(t[1], t[2]);
    add(t[2], t[0]);
  }
  return edges;
}

function parseMd2(buffer) {
  const view = new DataView(buffer);
  if (view.getUint32(0, true) !== 0x32504449) throw new Error("Not an IDP2 MD2");
  const version = view.getInt32(4, true);
  const fsize = view.getInt32(16, true);
  const nverts = view.getInt32(24, true);
  const ntris = view.getInt32(32, true);
  const nframes = view.getInt32(40, true);
  const ofsTris = view.getInt32(52, true);
  const ofsFrames = view.getInt32(56, true);
  if (version !== 8 || nverts <= 0 || nframes <= 0) throw new Error("MD2 header invalid");
  const tris = [];
  for (let i = 0; i < ntris; i++) {
    const o = ofsTris + i * 12;
    tris.push([view.getUint16(o, true), view.getUint16(o + 2, true), view.getUint16(o + 4, true)]);
  }
  const frames = [];
  const bytes = new Uint8Array(buffer);
  for (let fi = 0; fi < nframes; fi++) {
    const base = ofsFrames + fi * fsize;
    const sx = view.getFloat32(base, true);
    const sy = view.getFloat32(base + 4, true);
    const sz = view.getFloat32(base + 8, true);
    const tx = view.getFloat32(base + 12, true);
    const ty = view.getFloat32(base + 16, true);
    const tz = view.getFloat32(base + 20, true);
    const xyz = new Float32Array(nverts * 3);
    let vo = base + 40;
    for (let i = 0; i < nverts; i++) {
      const q = quake(bytes[vo] * sx + tx, bytes[vo + 1] * sy + ty, bytes[vo + 2] * sz + tz);
      xyz[i * 3] = q[0];
      xyz[i * 3 + 1] = q[1];
      xyz[i * 3 + 2] = q[2];
      vo += 4;
    }
    frames.push(xyz);
  }
  return { numVerts: nverts, frames, tris };
}

function parseMd3(buffer) {
  const view = new DataView(buffer);
  if (view.getUint32(0, true) !== 0x33504449) throw new Error("Not an IDP3 MD3");
  const nframes = view.getInt32(76, true);
  const ofsSurf = view.getInt32(100, true);
  const nfr = view.getInt32(ofsSurf + 72, true);
  const nverts = view.getInt32(ofsSurf + 80, true);
  const ntris = view.getInt32(ofsSurf + 84, true);
  const ofsTri = view.getInt32(ofsSurf + 88, true);
  const ofsXyz = view.getInt32(ofsSurf + 100, true);
  if (nfr !== nframes || nverts <= 0 || nframes <= 0) throw new Error("MD3 surface invalid");
  const tris = [];
  for (let i = 0; i < ntris; i++) {
    const o = ofsSurf + ofsTri + i * 12;
    tris.push([view.getUint32(o, true), view.getUint32(o + 4, true), view.getUint32(o + 8, true)]);
  }
  const frames = [];
  for (let fi = 0; fi < nframes; fi++) {
    const xyz = new Float32Array(nverts * 3);
    let vo = ofsSurf + ofsXyz + fi * nverts * 8;
    for (let i = 0; i < nverts; i++) {
      const q = quake(view.getInt16(vo, true) / 64, view.getInt16(vo + 2, true) / 64, view.getInt16(vo + 4, true) / 64);
      xyz[i * 3] = q[0];
      xyz[i * 3 + 1] = q[1];
      xyz[i * 3 + 2] = q[2];
      vo += 8;
    }
    frames.push(xyz);
  }
  return { numVerts: nverts, frames, tris };
}

function loadPart(files, rel) {
  const buf = files.get(rel);
  if (!buf) throw new Error(`missing ${rel}`);
  return rel.endsWith(".md3") ? parseMd3(buf) : parseMd2(buf);
}

export function loadDoomEnemy(name, files) {
  const rels = DOOM_PARTS[name];
  const parts = rels.map((rel) => loadPart(files, rel));
  const spec = DOOM_CLIPS[name];
  const frames = [];
  const clips = [];
  let start = 0;
  const bases = [];
  let acc = 0;
  for (const part of parts) {
    bases.push(acc);
    acc += part.numVerts;
  }
  const tris = [];
  parts.forEach((part, pi) => {
    const base = bases[pi];
    for (const tri of part.tris) tris.push([tri[0] + base, tri[1] + base, tri[2] + base]);
  });
  for (const [clipName, samples] of spec) {
    const clipFrames = [];
    for (const sample of samples) {
      const xyz = new Float32Array(acc * 3);
      let dst = 0;
      for (let pi = 0; pi < parts.length; pi++) {
        const src = parts[pi].frames[sample[pi]];
        if (!src) throw new Error(`${name} ${clipName}: frame ${sample[pi]}`);
        xyz.set(src, dst);
        dst += src.length;
      }
      const index = frames.length;
      frames.push({ name: `${clipName}${clipFrames.length}`, xyz });
      clipFrames.push({ name: frames[index].name, index });
    }
    clips.push({ name: clipName, frames: clipFrames, start, len: clipFrames.length });
    start += clipFrames.length;
  }
  const kept = strideTris(tris);
  return {
    numVerts: acc,
    scale: [1, 1, 1],
    origin: [0, 0, 0],
    floatFrames: true,
    frames,
    clips,
    tris: kept,
    edges: uniqueEdges(kept),
    weaponBase: name === "Possessed" ? bases[bases.length - 1] : 0,
  };
}

export function loadDoomEnemies(files) {
  const models = {};
  const missing = [];
  for (const name of Object.keys(DOOM_PARTS)) {
    try {
      models[name] = loadDoomEnemy(name, files);
    } catch (err) {
      missing.push(name);
      console.warn(`Failed to parse ${name}:`, err);
    }
  }
  return { models, missing };
}
