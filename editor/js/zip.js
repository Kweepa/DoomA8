/** PK3 / zip reader. Method 0 stored, method 8 deflate-raw. */

async function inflateRaw(bytes) {
  if (typeof DecompressionStream !== "function") {
    throw new Error("This browser cannot inflate a pk3");
  }
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return await new Response(stream).arrayBuffer();
}

/** Lowercase path → ArrayBuffer. Directory entries are skipped. */
export async function unzipPk3(buffer) {
  const view = new DataView(buffer);
  let eocd = -1;
  const min = Math.max(0, buffer.byteLength - 22 - 65535);
  for (let i = buffer.byteLength - 22; i >= min; i--) {
    if (view.getUint32(i, true) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("Not a zip");
  const count = view.getUint16(eocd + 10, true);
  let cd = view.getUint32(eocd + 16, true);
  const files = new Map();
  for (let n = 0; n < count; n++) {
    if (cd + 46 > buffer.byteLength || view.getUint32(cd, true) !== 0x02014b50) break;
    const method = view.getUint16(cd + 10, true);
    const compSize = view.getUint32(cd + 20, true);
    const nameLen = view.getUint16(cd + 28, true);
    const extraLen = view.getUint16(cd + 30, true);
    const commentLen = view.getUint16(cd + 32, true);
    const localOff = view.getUint32(cd + 42, true);
    let name = "";
    for (let i = 0; i < nameLen; i++) name += String.fromCharCode(view.getUint8(cd + 46 + i));
    name = name.replace(/\\/g, "/");
    if (!name.endsWith("/")) {
      const localName = view.getUint16(localOff + 26, true);
      const localExtra = view.getUint16(localOff + 28, true);
      const dataOff = localOff + 30 + localName + localExtra;
      const comp = buffer.slice(dataOff, dataOff + compSize);
      let raw = comp;
      if (method === 8) raw = await inflateRaw(comp);
      else if (method !== 0) throw new Error(`zip method ${method}`);
      files.set(name.toLowerCase(), raw);
    }
    cd += 46 + nameLen + extraLen + commentLen;
  }
  return files;
}
