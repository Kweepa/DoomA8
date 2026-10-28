const HANDLE_DB = "doom64-editor";
const HANDLE_STORE = "handles";
const SHAREWARE_KEY = "shareware";
const WEAPONS_PNG_KEY = "weapons-png";
const REPO_KEY = "repo";
// Project root. The old "doc" file handle is left unread so a Doom64 path cannot be restored.
const PROJECT_KEY = "dooma8-project";
const PROJECT_DOC_REL = "editor/doom64.json";

export const DEFAULT_DOC_PATH = "doom64.json";

/** @type {FileSystemFileHandle | null} */
let docFileHandle = null;
/** @type {FileSystemDirectoryHandle | null} */
let projectDirHandle = null;
/** @type {FileSystemDirectoryHandle | null} */
let sharewareDirHandle = null;
/** @type {FileSystemDirectoryHandle | null} */
let weaponsPngDirHandle = null;
/** @type {FileSystemDirectoryHandle | null} */
let repoDirHandle = null;

export function docFileName() {
  return docFileHandle?.name || DEFAULT_DOC_PATH;
}

export function hasDocFileHandle() {
  return !!docFileHandle;
}

const EDITOR_SETTINGS_KEY = "doom64-editor-settings";

function isFlatEditorState(obj) {
  return !!obj && typeof obj === "object" && (obj.layoutCamera || obj.mode || obj.animOrbit);
}

export function loadEditorSettings(fileName) {
  try {
    const raw = localStorage.getItem(EDITOR_SETTINGS_KEY);
    if (!raw) return null;
    const all = JSON.parse(raw);
    if (!all || typeof all !== "object") return null;
    if (isFlatEditorState(all)) return all;
    const name = fileName || DEFAULT_DOC_PATH;
    return all[name] || null;
  } catch {
    return null;
  }
}

export function saveEditorSettings(fileName, state) {
  try {
    const name = fileName || DEFAULT_DOC_PATH;
    let all = {};
    try {
      all = JSON.parse(localStorage.getItem(EDITOR_SETTINGS_KEY) || "{}") || {};
    } catch {
      all = {};
    }
    if (isFlatEditorState(all)) all = { [name]: all };
    all[name] = state;
    localStorage.setItem(EDITOR_SETTINGS_KEY, JSON.stringify(all));
  } catch {
    /* private mode / quota */
  }
}

function openHandleDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(HANDLE_DB, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(HANDLE_STORE)) {
        db.createObjectStore(HANDLE_STORE);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function queryPermission(handle, mode = "readwrite") {
  if (!handle?.queryPermission) return "granted";
  return handle.queryPermission({ mode });
}

async function ensurePermission(handle, mode = "readwrite") {
  if (!handle?.queryPermission || !handle?.requestPermission) return true;
  const opts = { mode };
  if ((await handle.queryPermission(opts)) === "granted") return true;
  return (await handle.requestPermission(opts)) === "granted";
}

function withoutEditor(doc) {
  if (!doc || typeof doc !== "object") return doc;
  const { editor: _editor, ...rest } = doc;
  return rest;
}

async function writeDocToHandle(handle, doc) {
  const text = JSON.stringify(withoutEditor(doc), null, 2);
  const writable = await handle.createWritable();
  await writable.write(text);
  await writable.close();
}

async function readDocFromHandle(handle) {
  const file = await handle.getFile();
  return JSON.parse(await file.text());
}

async function projectDocFile(dir) {
  const marker = await getFileInDir(dir, "build-a8.bat");
  if (!marker) {
    throw new Error("That folder is not the DoomA8 project (no build-a8.bat).");
  }
  const file = await getFileInDir(dir, PROJECT_DOC_REL);
  if (!file) {
    throw new Error(`${PROJECT_DOC_REL} is missing from that folder.`);
  }
  return file;
}

async function bindProjectDir(dir) {
  const file = await projectDocFile(dir);
  projectDirHandle = dir;
  docFileHandle = file;
  await storeHandle(PROJECT_KEY, dir);
  return file;
}

async function writeProjectDoc(doc) {
  if (!docFileHandle || !projectDirHandle) return null;
  if (!(await ensurePermission(projectDirHandle, "readwrite"))) {
    throw new Error("No write permission for the DoomA8 folder");
  }
  await writeDocToHandle(docFileHandle, doc);
  return "file";
}

const ENEMY_FILE_DOS = ["poss", "baron", "pinky", "imp"];

async function enemyDir(create) {
  if (!projectDirHandle) return null;
  const editor = await projectDirHandle.getDirectoryHandle("editor");
  return editor.getDirectoryHandle("enemies", create ? { create: true } : undefined);
}

/** Per-enemy records. Null when editor/enemies is not there yet. */
export async function readEnemyFiles() {
  let dir;
  try {
    dir = await enemyDir(false);
  } catch {
    return null;
  }
  if (!dir) return null;
  const out = [];
  for (const dos of ENEMY_FILE_DOS) {
    try {
      const fh = await dir.getFileHandle(`${dos}.json`);
      const text = await (await fh.getFile()).text();
      out.push(JSON.parse(text));
    } catch {
      /* missing file */
    }
  }
  return out.length ? out : null;
}

export async function writeEnemyFiles(records) {
  const dir = await enemyDir(true);
  if (!dir) return;
  const byDos = new Map(records.map((rec) => [rec.dos, rec.data]));
  for (const dos of ENEMY_FILE_DOS) {
    const data = byDos.get(dos);
    if (!data) continue;
    const fh = await dir.getFileHandle(`${dos}.json`, { create: true });
    const w = await fh.createWritable();
    await w.write(JSON.stringify(data, null, 2));
    await w.close();
  }
}

export async function getStoredProjectDir() {
  return loadStoredHandle(PROJECT_KEY);
}

export async function tryRestoreProjectDoc() {
  const dir = await loadStoredHandle(PROJECT_KEY);
  if (!dir) return null;
  if ((await queryPermission(dir, "readwrite")) !== "granted") return null;
  try {
    const file = await bindProjectDir(dir);
    return readDocFromHandle(file);
  } catch {
    projectDirHandle = null;
    docFileHandle = null;
    return null;
  }
}

export async function allowStoredProjectDir(dir) {
  if (!dir) return null;
  if (!(await ensurePermission(dir, "readwrite"))) return null;
  const file = await bindProjectDir(dir);
  return readDocFromHandle(file);
}

export async function pickProjectDirectory() {
  if (!window.showDirectoryPicker) {
    throw new Error("This browser cannot open a folder (needs Chromium file access)");
  }
  try {
    const opts = { id: "dooma8-project", mode: "readwrite" };
    const startIn = projectDirHandle || (await loadStoredHandle(PROJECT_KEY));
    if (startIn) opts.startIn = startIn;
    const handle = await window.showDirectoryPicker(opts);
    const file = await bindProjectDir(handle);
    return readDocFromHandle(file);
  } catch (e) {
    if (e.name === "AbortError") return null;
    throw e;
  }
}

/** Re-read editor/doom64.json. Null when the DoomA8 folder is not granted yet. */
export async function loadProjectDoc() {
  if (!projectDirHandle) return tryRestoreProjectDoc();
  if (!(await ensurePermission(projectDirHandle, "readwrite"))) {
    throw new Error("No write permission for the DoomA8 folder");
  }
  const file = await projectDocFile(projectDirHandle);
  docFileHandle = file;
  return readDocFromHandle(file);
}

export async function autosaveDocJSON(doc) {
  const how = await writeProjectDoc(doc);
  if (!how) {
    throw new Error("Open the DoomA8 folder once so autosave can write editor/doom64.json");
  }
  return how;
}

export async function saveDocJSON(doc) {
  return writeProjectDoc(doc);
}

export function sharewareFolderName() {
  return sharewareDirHandle?.name || "";
}

export function hasSharewareDirHandle() {
  return !!sharewareDirHandle;
}

async function storeHandle(key, handle) {
  if (!window.indexedDB || !handle) return;
  const db = await openHandleDb();
  await new Promise((resolve, reject) => {
    const tx = db.transaction(HANDLE_STORE, "readwrite");
    tx.objectStore(HANDLE_STORE).put(handle, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

async function loadStoredHandle(key) {
  if (!window.indexedDB) return null;
  try {
    const db = await openHandleDb();
    const handle = await new Promise((resolve, reject) => {
      const tx = db.transaction(HANDLE_STORE, "readonly");
      const req = tx.objectStore(HANDLE_STORE).get(key);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
    db.close();
    return handle || null;
  } catch {
    return null;
  }
}

async function storeSharewareHandle(handle) {
  sharewareDirHandle = handle;
  await storeHandle(SHAREWARE_KEY, handle);
}

export async function getStoredSharewareHandle() {
  return loadStoredHandle(SHAREWARE_KEY);
}

export async function tryRestoreSharewareDir() {
  const handle = await loadStoredHandle(SHAREWARE_KEY);
  if (!handle) return null;
  const state = await queryPermission(handle, "read");
  if (state !== "granted") return null;
  sharewareDirHandle = handle;
  return handle;
}

export async function allowStoredSharewareDir(handle) {
  if (!handle) return null;
  if (!(await ensurePermission(handle, "read"))) return null;
  await storeSharewareHandle(handle);
  return handle;
}

export function repoFolderName() {
  return repoDirHandle?.name || "";
}

export async function tryRestoreRepoDir() {
  const handle = await loadStoredHandle(REPO_KEY);
  if (!handle) return null;
  const state = await queryPermission(handle, "read");
  if (state !== "granted") return null;
  repoDirHandle = handle;
  return handle;
}

export async function pickRepoDirectory() {
  if (!window.showDirectoryPicker) {
    throw new Error("This browser cannot open a folder (needs Chromium file access)");
  }
  try {
    const opts = { id: "doom64-repo", mode: "read" };
    const startIn = repoDirHandle || (await loadStoredHandle(REPO_KEY));
    if (startIn) opts.startIn = startIn;
    const handle = await window.showDirectoryPicker(opts);
    repoDirHandle = handle;
    await storeHandle(REPO_KEY, handle);
    return handle;
  } catch (e) {
    if (e.name === "AbortError") return null;
    throw e;
  }
}

/** Text of a file in the repo root, or null if it is not there. */
/** Bytes of a file under the open DoomA8 folder, or null. */
export async function readProjectBytes(relPath) {
  if (!projectDirHandle) return null;
  const fh = await getFileInDir(projectDirHandle, relPath);
  if (!fh) return null;
  return (await fh.getFile()).arrayBuffer();
}

export async function readRepoFile(dirHandle, name) {
  if (!(await ensurePermission(dirHandle, "read"))) {
    throw new Error("No read permission for the repo folder");
  }
  const fh = await getFileInDir(dirHandle, name);
  if (!fh) return null;
  return (await fh.getFile()).text();
}

export async function pickSharewareDirectory() {
  if (!window.showDirectoryPicker) {
    throw new Error("This browser cannot open a folder (needs Chromium file access)");
  }
  try {
    const handle = await window.showDirectoryPicker({
      id: "doom-shareware",
      mode: "read",
    });
    await storeSharewareHandle(handle);
    return handle;
  } catch (e) {
    if (e.name === "AbortError") return null;
    throw e;
  }
}

async function getFileInDir(dir, relPath) {
  const parts = relPath.split("/");
  let cur = dir;
  for (let i = 0; i < parts.length - 1; i++) {
    try {
      cur = await cur.getDirectoryHandle(parts[i]);
    } catch {
      return null;
    }
  }
  try {
    return await cur.getFileHandle(parts[parts.length - 1]);
  } catch {
    return null;
  }
}

/** Load pak0 then pak1 from the folder or an id1/ child. */
export async function loadSharewarePakBuffers(dirHandle) {
  const buffers = [];
  const seen = new Set();
  const candidates = ["pak0.pak", "id1/pak0.pak", "pak1.pak", "id1/pak1.pak"];
  for (const rel of candidates) {
    const fh = await getFileInDir(dirHandle, rel);
    if (!fh) continue;
    const file = await fh.getFile();
    const key = `${file.name}:${file.size}:${file.lastModified}`;
    if (seen.has(key)) continue;
    seen.add(key);
    buffers.push(await file.arrayBuffer());
  }
  return buffers;
}

export async function ensureWeaponsPngDirectory() {
  if (weaponsPngDirHandle && (await ensurePermission(weaponsPngDirHandle, "readwrite"))) {
    return weaponsPngDirHandle;
  }
  const stored = await loadStoredHandle(WEAPONS_PNG_KEY);
  if (stored && (await ensurePermission(stored, "readwrite"))) {
    weaponsPngDirHandle = stored;
    return stored;
  }
  return pickWeaponsPngDirectory();
}

export async function pickWeaponsPngDirectory() {
  if (!window.showDirectoryPicker) {
    throw new Error("This browser cannot open a folder (needs Chromium file access)");
  }
  try {
    const opts = { id: "doom-assets-weapons", mode: "readwrite" };
    const startIn = weaponsPngDirHandle || (await loadStoredHandle(WEAPONS_PNG_KEY));
    if (startIn) opts.startIn = startIn;
    const handle = await window.showDirectoryPicker(opts);
    weaponsPngDirHandle = handle;
    await storeHandle(WEAPONS_PNG_KEY, handle);
    return handle;
  } catch (e) {
    if (e.name === "AbortError") return null;
    throw e;
  }
}

export async function writePngFile(dirHandle, filename, blob) {
  const fh = await dirHandle.getFileHandle(filename, { create: true });
  const writable = await fh.createWritable();
  await writable.write(blob);
  await writable.close();
}

export function downloadJSON(doc, filename = DEFAULT_DOC_PATH) {
  const blob = new Blob([JSON.stringify(withoutEditor(doc), null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
