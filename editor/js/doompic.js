/** DOOM picture and sprite-rotation index. */

const PREFIXES = ["POSS", "TROO", "SARG", "BOSS"];

function u16(b, o) {
  return b[o] | (b[o + 1] << 8);
}
function u32(b, o) {
  return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
}
function i16(b, o) {
  const v = u16(b, o);
  return v & 0x8000 ? v - 0x10000 : v;
}

function lumpName(b, o) {
  let s = "";
  for (let i = 0; i < 8; i++) {
    const c = b[o + i];
    if (!c) break;
    s += String.fromCharCode(c);
  }
  return s.toUpperCase();
}

function decodePatch(blob, pos, size) {
  const width = i16(blob, pos);
  const height = i16(blob, pos + 2);
  const left = i16(blob, pos + 4);
  const top = i16(blob, pos + 6);
  if (width <= 0 || height <= 0 || width > 512 || height > 512) {
    throw new Error("bad doom patch");
  }
  const index = new Uint8Array(width * height);
  index.fill(255);
  for (let x = 0; x < width; x++) {
    let p = pos + u32(blob, pos + 8 + x * 4);
    const end = pos + size;
    while (p < end) {
      const topdelta = blob[p];
      p += 1;
      if (topdelta === 255) break;
      const length = blob[p];
      p += 2;
      for (let i = 0; i < length; i++) {
        const y = topdelta + i;
        if (y >= 0 && y < height && p < end) index[y * width + x] = blob[p];
        p += 1;
      }
      p += 1;
    }
  }
  return { width, height, left, top, index };
}

function install(rot, prefix, frame, rotation, flip, lump) {
  if (rotation === 0) {
    for (let r = 1; r <= 8; r++) {
      const key = prefix + frame + r;
      if (!rot.has(key)) rot.set(key, { lump, flip: false });
    }
    return;
  }
  if (rotation < 1 || rotation > 8) return;
  const key = prefix + frame + rotation;
  if (!rot.has(key)) rot.set(key, { lump, flip });
}

/** Pictures between S_START and S_END, rotations for the four monsters. */
export function loadDoomSprites(buffer) {
  const blob = new Uint8Array(buffer);
  const ident = String.fromCharCode(blob[0], blob[1], blob[2], blob[3]);
  if (ident !== "IWAD" && ident !== "PWAD") throw new Error("DOOM.WAD is not a WAD");
  const numlumps = u32(blob, 4);
  const dirofs = u32(blob, 8);
  const lumps = [];
  for (let i = 0; i < numlumps; i++) {
    const o = dirofs + i * 16;
    lumps.push({
      pos: u32(blob, o),
      size: u32(blob, o + 4),
      name: lumpName(blob, o + 8),
    });
  }
  let palPos = -1;
  let s0 = -1;
  let s1 = lumps.length;
  for (let i = 0; i < lumps.length; i++) {
    const name = lumps[i].name;
    if (name === "PLAYPAL" && palPos < 0) palPos = lumps[i].pos;
    if ((name === "S_START" || name === "SS_START") && s0 < 0) s0 = i;
    if ((name === "S_END" || name === "SS_END") && s0 >= 0 && i > s0) {
      s1 = i;
      break;
    }
  }
  if (palPos < 0) throw new Error("DOOM.WAD has no PLAYPAL");
  const palette = blob.subarray(palPos, palPos + 768);
  const byName = new Map();
  const rot = new Map();
  const letters = new Map();
  for (const prefix of PREFIXES) letters.set(prefix, []);
  if (s0 >= 0) {
    for (let i = s0 + 1; i < s1; i++) {
      const lump = lumps[i];
      const name = lump.name;
      if (name.length < 6) continue;
      byName.set(name, lump);
      const prefix = name.slice(0, 4);
      if (!letters.has(prefix)) continue;
      const frame = name[4];
      const rotation = name.charCodeAt(5) - 48;
      install(rot, prefix, frame, rotation, false, name);
      if (name.length >= 8) {
        const frame2 = name[6];
        const rot2 = name.charCodeAt(7) - 48;
        install(rot, prefix, frame2, rot2, true, name);
      }
      const list = letters.get(prefix);
      if (!list.includes(frame)) list.push(frame);
      if (name.length >= 8 && !list.includes(name[6])) list.push(name[6]);
    }
  }
  for (const list of letters.values()) list.sort();
  const cache = new Map();
  return { blob, palette, byName, rot, letters, cache };
}

export function spriteLetters(pack, prefix) {
  if (!pack) return [];
  return pack.letters.get(prefix) || [];
}

function canvasFor(pack, lumpName) {
  let canvas = pack.cache.get(lumpName);
  if (canvas) return canvas;
  const lump = pack.byName.get(lumpName);
  if (!lump) return null;
  const pic = decodePatch(pack.blob, lump.pos, lump.size);
  canvas = document.createElement("canvas");
  canvas.width = pic.width;
  canvas.height = pic.height;
  const ctx = canvas.getContext("2d");
  const img = ctx.createImageData(pic.width, pic.height);
  const pal = pack.palette;
  for (let i = 0; i < pic.index.length; i++) {
    const c = pic.index[i];
    const o = i * 4;
    if (c === 255) {
      img.data[o + 3] = 0;
      continue;
    }
    img.data[o] = pal[c * 3];
    img.data[o + 1] = pal[c * 3 + 1];
    img.data[o + 2] = pal[c * 3 + 2];
    img.data[o + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  canvas._left = pic.left;
  canvas._top = pic.top;
  pack.cache.set(lumpName, canvas);
  return canvas;
}

/** Rotation 1 is front. Rotation 7 is the left side, or a mirror of 3. */
export function spriteHit(pack, prefix, letter, rot) {
  if (!pack || !prefix || !letter) return null;
  const hit = pack.rot.get(prefix + letter + String(rot));
  if (!hit) return null;
  const canvas = canvasFor(pack, hit.lump);
  if (!canvas) return null;
  return { canvas, flip: hit.flip, left: canvas._left, top: canvas._top };
}
