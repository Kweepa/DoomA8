import {
  KINDS,
  PALETTE_ORDER,
  KIND_ICON,
  ENEMY_TYPES,
  enemyTypesByHp,
  enemiesByHp,
  JOINT_NAMES,
  SKEL_MAX_VERTS,
  SKEL_MAX_LINES,
  cycleEnemyRot,
  clampEnemyRot,
  cycleSlopeOrient,
  SLOPE_FLAG_BOTTOM,
  SLOPE_FLAG_TOP,
  clampObject,
  clampTriggerText,
  clampName,
  clampTag,
  elevHeightsAuto,
  clampElevHeights,
  elevStopBottoms,
  clampTriggerPurpose,
  TRIGGER_PURPOSES,
  TRIGGER_PURPOSE_LABELS,
  clampVertFor,
  vertLimitFor,
  VERT_MIN,
  VERT_MAX,
  ROOM_BG_DEFAULT,
  a8Hex,
  MAX_TRIGGER_TEXT,
  MAX_NAME_LEN,
  MAX_TAG_LEN,
  PICKUP_TYPES,
  PICKUP_ICON,
  ALL_MESH_KEYS,
  ITEM_MESH_KEYS,
  DOOR_MESH_KEYS,
  DOOR_TYPES,
  DOOR_LOCKS,
  DOOR_LOCK_LABELS,
  DOOR_SCALES,
  DOOR_SCALE_LABELS,
  clampPickupType,
  clampDoorLock,
  clampDoorType,
  clampDoorScale,
  isDoorMeshKey,
  ITEM_MAX_UNIQUE,
  ITEM_TABLE_MAX,
  itemMeshStats,
  itemGlobalBudgets,
  createObject,
  createDefaultDocument,
  localFocusRoom,
  normalizeDocument,
  uid,
  LEVEL_NAMES,
  activeMap,
  mapStats,
  formatMapStats,
  formatMapLoadTitle,
  mapKindStatRows,
  packedPoseBytes,
  ENEMY_POSE_MAX,
  ROOM_MAX,
  ROOM_MAX_TYPES,
  ENEMY_MAX,
  canAddEnemyType,
  clipForFrame,
  dummyFrameFor,
  enemyPreviewFrame,
  findEnemyTemplate,
  isFigureObject,
  enableSpawn,
  ensureSpawnExclusive,
  objectLabel,
  objectTree,
  layoutSearchTerms,
  objectMatchesLayoutSearch,
  mapMatchesLayoutSearch,
  roomUnderObject,
  roomById,
  roomsOf,
  WORLD_MIN,
  WORLD_MAX,
  assignDoorRooms,
  tryConnectDoor,
  doorDoublyConnected,
  snapDoorBetweenRooms,
  snapDoorToFace,
  snapSwitchToFace,
  snapSwitchToRoom,
  usesLinkTag,
  doorUsesTag,
  triggerUsesTag,
  emptyMdlRig,
  DEFAULT_MDL_SCALE,
  clampMdlScale,
  clampEnemyHp,
  clampEnemyPainChance,
  clampWeaponVert,
  JOINT_NAMES,
  WEAPON_VERT,
  WEAPON_KEYS,
  WEAPON_LABELS,
  clampWeaponScale,
  DEFAULT_WEAPON_SCALE,
  ROOM_SHAPES,
  applyRoomShape,
  rotateRoom,
  rotateRoomY,
  rotateRoomsBlockY,
  roomFloorY,
  clampRoomShape,
  parseEditorState,
  gameDocument,
  withClipSound,
  clipIsAttackRole,
  attackFrameOrDefault,
  ENEMY_CUE_LABELS,
  ENEMY_ATTACK_CUES,
  enemyFileRecords,
  mapFileRecords,
  enemyHasSprites,
  DOOM_SPRITE_PREFIX,
  SPRITE_MAX_VERTS,
  SPRITE_MAX_LINES,
} from "./model.js";
import { lookVectors, projectLine } from "./math3d.js";
import {
  DEFAULT_DOC_PATH,
  docFileName,
  getStoredProjectDir,
  hasDocFileHandle,
  loadProjectDoc,
  saveDocJSON,
  loadEditorSettings,
  saveEditorSettings,
  tryRestoreProjectDoc,
  allowStoredProjectDir,
  pickProjectDirectory,
  pickSharewareDirectory,
  tryRestoreSharewareDir,
  getStoredSharewareHandle,
  sharewareFolderName,
  loadSharewarePakBuffers,
  readEnemyFiles,
  writeEnemyFiles,
  readMapFiles,
  writeMapFiles,
  readProjectBytes,
  ensureWeaponsPngDirectory,
  writePngFile,
} from "./io.js";
import { showBuildView } from "./buildView.js";
import { parsePakBuffers } from "./pak.js";
import { loadDoomSprites, spriteHit, spriteLetters } from "./doompic.js";
import { StickOrtho } from "./stickOrtho.js";
import {
  loadEnemyMdls,
  loadWeaponMdls,
  mdlEditorVerts,
  averageJointPositions,
  filterMdlClips,
  buildStickFramesFromMdl,
  resolveWeaponFrames,
  rasterWeaponFrame,
  WEAPON_MDL_PATHS,
  WEAPON_SPRITE_W,
  WEAPON_SPRITE_H,
} from "./mdl.js";
import { LayoutView } from "./layoutView.js";
import { OverheadView } from "./overheadView.js";
import { PreviewView } from "./previewView.js";
import { AnimView } from "./animView.js";
import { WeaponView } from "./weaponView.js";
import { ItemView } from "./itemView.js";

const statusEl = document.getElementById("status");
const titleEl = document.querySelector(".toolbar h1");
const btnUndo = document.getElementById("btn-undo");
const btnRedo = document.getElementById("btn-redo");
const UNDO_LIMIT = 40;
const AUTOSAVE_MS = 8000;
const MDL_RIG_BACKUP_KEY = "doom64-mdl-rigs";
/** Match Doom monster default: one MDL frame per 0.1s think. */
const ANIM_PLAY_MS = 100;

let doc = createDefaultDocument();
let editorMode = "layout";
let localDraw = false;
let neighbourDraw = false;
let roomsOnlyDraw = false;
let selectedIds = [];
let pendingPlace = null;
let enemyIndex = 0;
let frameIndex = 0;
let selectedVerts = [];
let selectedLines = [];
let pendingBind = null;
let dirty = false;
let saving = false;
let autosaveTimer = null;
let editorSaveRaf = 0;
let editorSettingsReady = false;
let applyingEditor = false;
let undoStack = [];
let redoStack = [];
let undoGesture = false;
let animPlaying = false;
let animPlayTimer = null;
let animLoop = false;
let sharewareModels = {};
let sharewareMissing = [];
let sharewareWeapons = {};
let sharewareWeaponMissing = [];
let overlayOn = true;
let refSpriteOn = true;
let stickWireOn = true;
let drawingOrtho = false;
let doomSprites = null;
let spriteSelClip = null;
let framePoseClip = null;
let bindJoint = -1;
let clipIndex = 0;
let frameLocal = 0;
let mdlScale = DEFAULT_MDL_SCALE;
let weaponKey = "shot2";
let weaponFrame = 0;
let itemMeshKey = "backpack";
/** Collapsed room ids in the Objects tree. */
const collapsedRooms = new Set();
/** Maps-panel search. Session only; does not dirty the document. */
let layoutSearch = "";
/** Last room used for placement / parenting. */
let lastRoomId = null;

const layoutView = new LayoutView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getDoc: () => doc,
  getSelectedIds: () => selectedIds,
  getLocalMode: () => localDraw && editorMode === "layout",
  getNeighbourMode: () => neighbourDraw,
  getRoomsOnlyMode: () => roomsOnlyDraw,
  getFocusRoom: () => localFocusRoom(doc, selectedIds, lastRoomId),
  onSelectIds: (ids, additive) => {
    const added = [];
    if (additive) {
      for (const id of ids) {
        if (!selectedIds.includes(id)) {
          selectedIds.push(id);
          added.push(id);
        }
      }
    } else {
      selectedIds = [...ids];
      added.push(...ids);
    }
    rememberSelectedRoom();
    const linked = connectUnlinkedDoors(added);
    if (linked) markDirty();
    else markUi();
    refreshPanels();
  },
  onToggleSelect: (id) => {
    const i = selectedIds.indexOf(id);
    const added = [];
    if (i >= 0) selectedIds.splice(i, 1);
    else {
      selectedIds.push(id);
      added.push(id);
    }
    rememberSelectedRoom();
    const linked = connectUnlinkedDoors(added);
    if (linked) markDirty();
    else markUi();
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  onViewChanged: () => {
    markUi();
  },
  onStatus: setStatus,
  beginUndo,
  endUndo,
  getLayoutSearch: () => layoutSearch,
  onTick: () => previewView.draw(),
});

document.getElementById("layout-search")?.addEventListener("input", (e) => {
  layoutSearch = e.target.value;
  renderLevelList();
  renderObjectList();
  if (editorMode === "layout") layoutView.draw();
});

const overheadView = new OverheadView(document.getElementById("overhead-canvas"), {
  getDoc: () => doc,
  getCamera: () => layoutView.camera,
  getSelectedId: () => (selectedIds.length ? selectedIds[selectedIds.length - 1] : null),
  getSelectedIds: () => selectedIds,
  getLocalMode: () => localDraw,
  getNeighbourMode: () => neighbourDraw,
  getRoomsOnlyMode: () => roomsOnlyDraw,
  getFocusRoom: () => localFocusRoom(doc, selectedIds, lastRoomId),
});

function selectedSpawn() {
  const objs = activeMap(doc).objects;
  for (let i = selectedIds.length - 1; i >= 0; i--) {
    const obj = objs.find((o) => o.id === selectedIds[i]);
    if (obj?.kind === "spawn") return obj;
  }
  return null;
}

function previewSpawn() {
  const selected = selectedSpawn();
  if (selected) return selected;
  const room = localFocusRoom(doc, selectedIds, lastRoomId);
  if (!room) return null;
  const spawns = activeMap(doc).objects.filter((o) => o.kind === "spawn" && o.roomId === room.id);
  if (!spawns.length) return null;
  return spawns.find((s) => s.enabled) || spawns[0];
}

function previewRoom() {
  const spawn = selectedSpawn();
  if (spawn) return roomById(doc, spawn.roomId) || localFocusRoom(doc, selectedIds, lastRoomId);
  return localFocusRoom(doc, selectedIds, lastRoomId);
}

const previewView = new PreviewView(document.getElementById("preview-canvas"), {
  getDoc: () => doc,
  getRoom: () => previewRoom(),
  getSpawn: () => previewSpawn(),
  getEditSpawn: () => selectedSpawn(),
  getRoomsOnlyMode: () => roomsOnlyDraw,
  pistolImg: document.getElementById("preview-pistol-png"),
  onRotate: (yaw) => {
    const spawn = selectedSpawn();
    if (!spawn) return;
    spawn.rot = clampEnemyRot(Math.round(yaw / (Math.PI / 4)));
    markDirty();
  },
  onMove: (x, z) => {
    const spawn = selectedSpawn();
    if (!spawn) return;
    spawn.x = Math.max(WORLD_MIN, Math.min(WORLD_MAX, Math.round(x - 1)));
    spawn.z = Math.max(WORLD_MIN, Math.min(WORLD_MAX, Math.round(z - 1)));
    markDirty();
  },
  onEditStart: beginUndo,
  onEditEnd: () => {
    endUndo();
    refreshAll();
  },
  onChange: () => {
    layoutView.draw();
    overheadView.draw();
    renderInspector();
  },
});

const animView = new AnimView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getEnemy: () => doc.enemies[enemyIndex],
  getFrame: () => {
    const e = doc.enemies[enemyIndex];
    const stick = stickClipFor(e, activeTimelineClip());
    if (stick) {
      const fi = (stick.start | 0) + frameLocal;
      if (e.frames?.[fi]) return fi;
    }
    if (e?.customSkeleton || !e?.clips?.length) return 0;
    return frameIndex;
  },
  getLocalFrame: () => {
    const clip = activeTimelineClip();
    if (!clip) return null;
    return Math.max(0, Math.min(frameLocal, (clip.len | 0) - 1));
  },
  getClipName: () => activeTimelineClip()?.name ?? null,
  hasStickFrame: () => {
    const e = doc.enemies[enemyIndex];
    if (stickClipFor(e, activeTimelineClip())) return true;
    return !!e?.customSkeleton && Array.isArray(e.frames?.[0]);
  },
  getSelectedVerts: () => selectedVerts,
  getSelectedLines: () => selectedLines,
  onSelectVert: (i, additive) => {
    if (i < 0) selectedVerts = [];
    else if (additive) {
      if (!selectedVerts.includes(i)) selectedVerts.push(i);
    } else selectedVerts = [i];
    selectedLines = [];
    markUi();
    refreshPanels();
  },
  onSelectVerts: (indices, additive) => {
    if (additive) {
      for (const i of indices) {
        if (!selectedVerts.includes(i)) selectedVerts.push(i);
      }
    } else selectedVerts = [...indices];
    selectedLines = [];
    markUi();
    refreshPanels();
  },
  onSelectLine: (i, additive) => {
    if (i < 0) selectedLines = [];
    else if (additive) {
      if (!selectedLines.includes(i)) selectedLines.push(i);
    } else selectedLines = [i];
    selectedVerts = [];
    markUi();
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  onViewChanged: () => {
    markUi();
  },
  onZoomSync: () => syncStickScale(),
  onDrawn: () => {
    if (drawingOrtho) return;
    syncStickScale();
    stickLeft?.draw();
    stickFront?.draw();
  },
  onStageResize: () => {
    stickLeft?.resize();
    stickFront?.resize();
  },
  beginUndo,
  endUndo,
  getMeshOverlay: () => {
    if (!overlayOn) return null;
    const e = doc.enemies[enemyIndex];
    if (!e || enemyHasSprites(e)) return null;
    const mdl = sharewareModels[e.name];
    if (!mdl) return null;
    const timeline = getTimeline(e);
    const clip = timeline[clipIndex] || timeline[0];
    if (!clip) return null;
    const local = Math.max(0, Math.min(frameLocal, clip.len - 1));
    const frameName = clip.frameNames?.[local] || `${clip.name}${local}`;
    const mdlFi = clip.mdlFrames[local]?.index ?? 0;
    const verts = mdlEditorVerts(mdl, mdlFi, mdlScale);
    const rig = e.mdlRig || emptyMdlRig();
    return {
      verts,
      edges: mdl.edges,
      binding: pendingBind != null || bindJoint >= 0,
      bindJoint: pendingBind != null ? -1 : bindJoint,
      meshSel: pendingBind != null ? pendingBind : rig.jointVerts[bindJoint] || [],
      jointVerts: rig.jointVerts,
      ghost: averageJointPositions(verts, rig.jointVerts),
      lines: e.lines,
      frameName,
    };
  },
  onSelectMeshVert: (i, additive) => {
    if (pendingBind) stageMeshBind([i], additive);
    else assignMeshVerts([i], additive);
  },
  onSelectMeshVerts: (indices, additive) => {
    if (pendingBind) stageMeshBind(indices, additive);
    else assignMeshVerts(indices, additive);
  },
});

function orthoSprite(rot) {
  const e = activeEnemy();
  if (!enemyHasSprites(e)) return null;
  const prefix = DOOM_SPRITE_PREFIX[e.name];
  const clip = clipForFrame(e.clips, frameIndex);
  const letter = clip?.sprites?.[frameIndex - clip.start];
  if (!prefix || !letter) return null;
  const hit = spriteHit(doomSprites, prefix, letter, rot);
  if (!hit) return null;
  // Side lumps are the left-side photo. Doom stores that view as the mirror.
  if (rot === 7) return { ...hit, flip: !hit.flip };
  return hit;
}

function refreshFromOrtho() {
  drawingOrtho = true;
  animView.draw();
  drawingOrtho = false;
  stickLeft.draw();
  stickFront.draw();
}

function syncVertXyz() {
  const row = document.querySelector("#right-editors .vert-xyz");
  if (!row) return;
  const e = activeEnemy();
  if (!e || selectedVerts.length !== 1) return;
  const v = e.frames[frameIndex]?.[selectedVerts[0]];
  if (!v) return;
  for (const axis of ["x", "y", "z"]) {
    const inp = row.querySelector(`input[data-axis="${axis}"]`);
    if (!inp || document.activeElement === inp) continue;
    const next = String(v[axis]);
    if (inp.value !== next) inp.value = next;
  }
}

/** Ortho pixels-per-unit matches the perspective view at the XZ origin. */
function syncStickScale() {
  const px = animView.pixelsAtOrigin();
  if (!(px > 0)) return;
  stickLeft?.setScale(px);
  stickFront?.setScale(px);
}

function makeStickOrtho(id, horiz, rot) {
  return new StickOrtho(document.getElementById(id), {
    horiz,
    getEnemy: () => activeEnemy(),
    getFrame: () => frameIndex,
    getSelected: () => selectedVerts,
    onSelect: (next) => {
      selectedVerts = next;
      selectedLines = [];
      markUi();
      refreshPanels();
    },
    beginUndo,
    endUndo,
    onPose: () => {
      markDirty();
      refreshFromOrtho();
      syncVertXyz();
    },
    onZoom: (factor) => animView.zoomBy(factor),
    getGroundPan: () => animView.groundPanY,
    setGroundPan: (y) => {
      animView.groundPanY = y;
      animView.draw();
    },
    showWire: () => stickWireOn,
    getSprite: () => (refSpriteOn ? orthoSprite(rot) : null),
    spriteScale: () => 0.35,
    vertLimit: () => vertLimitFor(activeEnemy()),
    clampVert: (n) => clampVertFor(activeEnemy())(n),
  });
}

const stickLeft = makeStickOrtho("stick-left-canvas", "z", 7);
const stickFront = makeStickOrtho("stick-front-canvas", "x", 1);

const weaponView = new WeaponView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  previewCanvas: document.getElementById("weapon-preview-canvas"),
  getMdl: () => sharewareWeapons[weaponKey] || null,
  getScale: () => doc.weapons.scale,
  getPan: () => {
    const item = doc.weapons.items[weaponKey];
    return item?.pan || { x: 0, y: 0 };
  },
  getPreviewFrame: () => weaponFrame,
  getOnionFrames: () => selectedWeaponFrames(),
  setScale: (v) => {
    doc.weapons.scale = clampWeaponScale(v);
    syncWeaponScaleInputs();
  },
  setPan: (x, y) => {
    const item = ensureWeaponItem(weaponKey);
    item.pan = { x, y };
  },
  beginUndo,
  endUndo,
  onChange: () => {
    markDirty();
  },
  onPanEnd: () => {
    refreshWeaponClipStatus();
  },
});

const itemView = new ItemView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getMesh: () => {
    if (!doc.items) doc.items = {};
    if (!doc.items[itemMeshKey]) doc.items[itemMeshKey] = { verts: [], lines: [] };
    return doc.items[itemMeshKey];
  },
  beginUndo,
  endUndo,
  onChange: () => {
    markDirty();
    renderInspector();
  },
  onSelect: () => renderInspector(),
  onStatus: (msg, isError) => setStatus(msg, isError),
  onViewChanged: () => markUi(),
});

function setStatus(msg, isError = false) {
  statusEl.textContent = msg || "";
  statusEl.classList.toggle("error", isError);
}

function updateDirtyIndicator() {
  const star = dirty ? "*" : "";
  if (titleEl) titleEl.textContent = `DoomA8${star}`;
  document.title = dirty ? "DoomA8 *" : "DoomA8 Editor";
}

function markDirty() {
  if (!dirty) {
    dirty = true;
    updateDirtyIndicator();
  }
  scheduleAutosave();
}

function markClean() {
  dirty = false;
  updateDirtyIndicator();
  clearAutosaveTimer();
}

function mdlRigBackupRaw() {
  try {
    const raw = JSON.parse(localStorage.getItem(MDL_RIG_BACKUP_KEY) || "null");
    return raw && typeof raw === "object" ? raw : null;
  } catch {
    return null;
  }
}

function persistMdlRigBackup() {
  const out = { ...(mdlRigBackupRaw() || {}) };
  for (const e of doc.enemies || []) {
    const jv = e.mdlRig?.jointVerts;
    if (!Array.isArray(jv) || !jv.some((list) => list.length)) {
      delete out[e.name];
      continue;
    }
    out[e.name] = jv.map((list) => [...list]);
  }
  try {
    if (!Object.keys(out).length) localStorage.removeItem(MDL_RIG_BACKUP_KEY);
    else localStorage.setItem(MDL_RIG_BACKUP_KEY, JSON.stringify(out));
  } catch {
    /* private mode / quota */
  }
}

/** Fill empty in-memory rigs from localStorage (survives refresh without doc reload). */
function restoreMdlRigBackup() {
  const raw = mdlRigBackupRaw();
  if (!raw) return false;
  let changed = false;
  for (const e of doc.enemies || []) {
    const jv = e.mdlRig?.jointVerts;
    if (Array.isArray(jv) && jv.some((list) => list.length)) continue;
    const saved = raw[e.name];
    if (!Array.isArray(saved)) continue;
    e.mdlRig = normalizeMdlRig({ jointVerts: saved }, saved.length);
    changed = true;
  }
  return changed;
}

function clearAutosaveTimer() {
  if (autosaveTimer) {
    clearTimeout(autosaveTimer);
    autosaveTimer = null;
  }
}

function isEditingField(el = document.activeElement) {
  return (
    el instanceof HTMLInputElement ||
    el instanceof HTMLTextAreaElement ||
    el instanceof HTMLSelectElement ||
    !!el?.isContentEditable
  );
}

function scheduleAutosave() {
  clearAutosaveTimer();
  if (!dirty || isEditingField()) return;
  autosaveTimer = setTimeout(() => {
    autosaveTimer = null;
    void runAutosave();
  }, AUTOSAVE_MS);
}

async function runAutosave() {
  if (!dirty || saving || !hasDocFileHandle()) return;
  if (isEditingField()) {
    scheduleAutosave();
    return;
  }
  await saveNow("Autosaved");
}

document.addEventListener("focusin", (e) => {
  if (isEditingField(e.target)) clearAutosaveTimer();
});
document.addEventListener("focusout", () => {
  requestAnimationFrame(() => {
    if (dirty && !isEditingField()) scheduleAutosave();
  });
});

function markUi() {
  if (applyingEditor || !editorSettingsReady) return;
  schedulePersistEditor();
}

/** Per-map layout cameras (E1M1 …). */
let layoutCamerasByLevel = {};

function snapshotLayoutCamera() {
  const cam = layoutView.camera;
  return {
    x: cam.x,
    y: cam.y,
    z: cam.z,
    yaw: cam.yaw,
    pitch: cam.pitch,
    speed: cam.speed,
  };
}

function applyLayoutCamera(cam) {
  const c = layoutView.camera;
  c.x = cam.x;
  c.y = cam.y;
  c.z = cam.z;
  c.yaw = cam.yaw;
  c.pitch = cam.pitch;
  c.speed = cam.speed;
}

function defaultLayoutCamera() {
  return parseEditorState(null).layoutCamera;
}

function mergeLayoutCamerasFromEditor(ed) {
  layoutCamerasByLevel = { ...(ed.layoutCameras || {}) };
  const level =
    ed.activeLevel && LEVEL_NAMES.includes(ed.activeLevel) ? ed.activeLevel : doc.activeLevel;
  if (ed.layoutCamera && !layoutCamerasByLevel[level]) {
    layoutCamerasByLevel[level] = { ...ed.layoutCamera };
  }
}

function restoreLayoutCameraForLevel(level) {
  applyLayoutCamera(layoutCamerasByLevel[level] || defaultLayoutCamera());
}

function collectEditorState() {
  layoutCamerasByLevel[doc.activeLevel] = snapshotLayoutCamera();
  const cam = layoutCamerasByLevel[doc.activeLevel];
  const orb = animView.orbit;
  const iorb = itemView.orbit;
  const enemy = doc.enemies[enemyIndex];
  return parseEditorState({
    mode: editorMode,
    localDraw,
    neighbourDraw,
    roomsOnlyDraw,
    selectedIds: [...selectedIds],
    enemy: enemy?.name || "Possessed",
    frameIndex,
    clipIndex,
    frameLocal,
    selectedVerts: [...selectedVerts],
    layoutCamera: { ...cam },
    layoutCameras: { ...layoutCamerasByLevel },
    animOrbit: { yaw: orb.yaw, pitch: orb.pitch, dist: orb.dist },
    mdlScale,
    weapon: weaponKey,
    weaponFrame,
    overlayOn,
    orthoMode: overheadView.mode,
    collapsedRooms: [...collapsedRooms],
    activeLevel: doc.activeLevel,
    item: itemMeshKey,
    itemOrbit: {
      yaw: iorb.yaw,
      pitch: iorb.pitch,
      dist: iorb.dist,
      target: { x: iorb.target.x, y: iorb.target.y, z: iorb.target.z },
    },
  });
}

function persistEditorSettings() {
  if (!editorSettingsReady) return;
  if (editorSaveRaf) {
    cancelAnimationFrame(editorSaveRaf);
    editorSaveRaf = 0;
  }
  saveEditorSettings(docFileName(), collectEditorState());
}

function schedulePersistEditor() {
  if (!editorSettingsReady || applyingEditor) return;
  if (editorSaveRaf) return;
  editorSaveRaf = requestAnimationFrame(() => {
    editorSaveRaf = 0;
    persistEditorSettings();
  });
}

function applyEditorState(ed) {
  ed = parseEditorState(ed);
  applyingEditor = true;
  try {
    mergeLayoutCamerasFromEditor(ed);
    if (ed.activeLevel && LEVEL_NAMES.includes(ed.activeLevel)) doc.activeLevel = ed.activeLevel;
    restoreLayoutCameraForLevel(doc.activeLevel);
    const orb = animView.orbit;
    orb.yaw = ed.animOrbit.yaw;
    orb.pitch = ed.animOrbit.pitch;
    orb.dist = ed.animOrbit.dist;
    syncStickScale();
    const ei = doc.enemies.findIndex((e) => e.name === ed.enemy);
    enemyIndex = ei >= 0 ? ei : 0;
    frameIndex = ed.frameIndex;
    clampFrameIndex(activeEnemy());
    syncClipFromFrameIndex(activeEnemy());
    const have = new Set(activeMap(doc).objects.map((o) => o.id));
    selectedIds = ed.selectedIds.filter((id) => have.has(id));
    rememberSelectedRoom();
    selectedVerts = [...ed.selectedVerts];
    setMdlScale(ed.mdlScale);
    weaponKey = WEAPON_KEYS.includes(ed.weapon) ? ed.weapon : "shot2";
    weaponFrame = Math.max(0, ed.weaponFrame | 0);
    setOverlayOn(ed.overlayOn);
    setOrthoMode(ed.orthoMode);
    collapsedRooms.clear();
    for (const id of ed.collapsedRooms) collapsedRooms.add(id);
    itemMeshKey = ALL_MESH_KEYS.includes(ed.item) ? ed.item : "backpack";
    const iorb = itemView.orbit;
    iorb.yaw = ed.itemOrbit.yaw;
    iorb.pitch = ed.itemOrbit.pitch;
    iorb.dist = ed.itemOrbit.dist;
    iorb.target.x = ed.itemOrbit.target.x;
    iorb.target.y = ed.itemOrbit.target.y;
    iorb.target.z = ed.itemOrbit.target.z;
    setNeighbourDraw(ed.neighbourDraw, false);
    setRoomsOnlyDraw(ed.roomsOnlyDraw, false);
    setDrawMode(ed.localDraw);
    setMode(ed.mode);
  } finally {
    applyingEditor = false;
  }
}

async function saveNow(okMsg = "Saved") {
  if (saving) return;
  if (!hasDocFileHandle()) {
    showFileAccessGate(await getStoredProjectDir());
    setStatus("Open the DoomA8 folder to save editor/doom64.json", true);
    return;
  }
  saving = true;
  try {
    persistEditorSettings();
    const payload = gameDocument(doc);
    const how = await saveDocJSON(payload);
    if (!how) {
      setStatus("Save cancelled", true);
      return;
    }
    await writeEnemyFiles(enemyFileRecords(doc));
    await writeMapFiles(mapFileRecords(doc));
    markClean();
    persistMdlRigBackup();
    setStatus(`${okMsg} ${docFileName()}`);
  } catch (err) {
    setStatus(String(err.message || err), true);
    scheduleAutosave();
  } finally {
    saving = false;
  }
}

function snapshot() {
  return JSON.stringify({
    version: doc.version,
    activeLevel: doc.activeLevel,
    maps: doc.maps,
    enemies: doc.enemies,
    weapons: doc.weapons,
    items: doc.items,
  });
}

function beginUndo() {
  if (undoGesture) return;
  undoStack.push(snapshot());
  if (undoStack.length > UNDO_LIMIT) undoStack.shift();
  redoStack.length = 0;
  undoGesture = true;
  updateUndoButtons();
}

function endUndo() {
  undoGesture = false;
}

function pushUndo() {
  beginUndo();
  endUndo();
}

function restore(json) {
  doc = normalizeDocument(JSON.parse(json));
  deriveAllEnemyFrames();
  const have = new Set(activeMap(doc).objects.map((o) => o.id));
  selectedIds = selectedIds.filter((id) => have.has(id));
  selectedVerts = selectedVerts.filter((i) => i >= 0 && i < stickCount(activeEnemy()));
  selectedLines = selectedLines.filter((i) => i >= 0 && i < (activeEnemy()?.lines.length || 0));
  if (enemyIndex >= doc.enemies.length) enemyIndex = 0;
  clampFrameIndex(activeEnemy());
  syncClipFromFrameIndex(activeEnemy());
  clampWeaponPreviewFrame();
  markDirty();
  buildPalette();
  refreshAll();
}

function clearUndoHistory() {
  undoStack.length = 0;
  redoStack.length = 0;
  undoGesture = false;
  updateUndoButtons();
}

function undo() {
  if (!undoStack.length) return;
  endUndo();
  redoStack.push(snapshot());
  restore(undoStack.pop());
  updateUndoButtons();
}

function redo() {
  if (!redoStack.length) return;
  undoStack.push(snapshot());
  restore(redoStack.pop());
  updateUndoButtons();
}

function updateUndoButtons() {
  btnUndo.disabled = undoStack.length === 0;
  btnRedo.disabled = redoStack.length === 0;
}

function activeEnemy() {
  return doc.enemies[enemyIndex];
}

function stickClipFor(e, clip) {
  if (!clip || !e?.clips?.length || !e.frames?.length) return null;
  const stick = e.clips.find((c) => c.name === clip.name);
  if (!stick) return null;
  const start = stick.start | 0;
  const len = stick.len | 0;
  if (start < 0 || len < 1 || start + len > e.frames.length) return null;
  if (!e.frames[start]?.length) return null;
  return stick;
}

function attackCueLabel(cue) {
  return ENEMY_CUE_LABELS[cue];
}

function renderClipSoundFields(root, e, clip) {
  const stick = stickClipFor(e, clip);
  if (!stick) return;
  const sel = document.createElement("select");
  const none = document.createElement("option");
  none.value = "";
  none.textContent = "(none)";
  sel.appendChild(none);
  for (const cue of ENEMY_ATTACK_CUES) {
    const o = document.createElement("option");
    o.value = cue;
    o.textContent = attackCueLabel(cue);
    sel.appendChild(o);
  }
  sel.value = ENEMY_ATTACK_CUES.includes(stick.sound) ? stick.sound : "";
  sel.addEventListener("change", () => {
    pushUndo();
    const next = withClipSound({ name: stick.name, start: stick.start, len: stick.len }, {
      sound: sel.value,
      soundFrame: stick.soundFrame,
    });
    stick.sound = next.sound;
    stick.soundFrame = next.soundFrame;
    if (!next.sound) {
      delete stick.sound;
      delete stick.soundFrame;
    }
    markDirty();
    refreshAll();
  });
  root.appendChild(field("Attack cue", sel));
  const fr = document.createElement("input");
  fr.type = "number";
  fr.min = "0";
  fr.max = String(Math.max(0, stick.len - 1));
  fr.step = "1";
  fr.value = String(stick.sound ? stick.soundFrame | 0 : 0);
  fr.disabled = !stick.sound;
  fr.addEventListener("change", () => {
    if (!stick.sound) return;
    pushUndo();
    const next = withClipSound(stick, { sound: stick.sound, soundFrame: fr.value });
    stick.soundFrame = next.soundFrame;
    fr.value = String(stick.soundFrame);
    markDirty();
    refreshAll();
  });
  root.appendChild(field("Sound frame", fr));
  if (!clipIsAttackRole(e.name, stick.name)) return;
  const atk = document.createElement("input");
  atk.type = "number";
  atk.min = "0";
  atk.max = String(Math.max(0, stick.len - 1));
  atk.step = "1";
  atk.value = String(attackFrameOrDefault(stick.attackFrame, stick.len));
  atk.addEventListener("change", () => {
    pushUndo();
    const next = attackFrameOrDefault(atk.value, stick.len);
    stick.attackFrame = next;
    atk.value = String(next);
    markDirty();
    refreshAll();
  });
  root.appendChild(field("Attack frame", atk));
}

function clipIsExported(e, name) {
  if (!Array.isArray(e?.exportClips)) return true;
  return e.exportClips.includes(name);
}

function setClipExported(e, name, on) {
  const all = (e.clips || []).map((c) => c.name);
  const have = new Set(Array.isArray(e.exportClips) ? e.exportClips : all);
  if (on) have.add(name);
  else have.delete(name);
  e.exportClips = all.filter((n) => have.has(n));
}

function exportClipNames(e, mdl) {
  const mdlNames = new Set((mdl?.clips || []).map((c) => c.name));
  if (Array.isArray(e?.exportClips)) {
    return e.exportClips.filter((n) => !mdlNames.size || mdlNames.has(n));
  }
  if (e?.clips?.length) {
    return e.clips.map((c) => c.name).filter((n) => !mdlNames.size || mdlNames.has(n));
  }
  return filterMdlClips(mdl?.clips).map((c) => c.name);
}

function formatPackedPoseMem(packed) {
  const { bytes, nLogical, nStored } = packed;
  const size =
    bytes >= 1024
      ? `${bytes / 1024 < 10 ? (bytes / 1024).toFixed(1) : Math.round(bytes / 1024)} KB`
      : `${bytes} bytes`;
  const over =
    bytes > ENEMY_POSE_MAX ? ` OVER ${bytes - ENEMY_POSE_MAX}` : "";
  return `≈ ${size} in-game (${nStored} stored / ${nLogical} logical)${over}`;
}

function getTimeline(e) {
  if (enemyHasSprites(e) && e?.clips?.length) {
    return e.clips.map((c) => ({
      name: c.name,
      len: c.len,
      start: c.start,
      frameNames: [],
      mdlFrames: [],
      hasStick: true,
      sprites: c.sprites,
    }));
  }
  const mdl = sharewareModels[e?.name];
  if (mdl?.clips?.length) {
    const byName = new Map((e.clips || []).map((c) => [c.name, c]));
    return mdl.clips.map((c) => {
      const stick = byName.get(c.name);
      return {
        name: c.name,
        len: c.frames.length,
        start: stick ? stick.start : 0,
        frameNames: c.frames.map((fr) => fr.name),
        mdlFrames: c.frames,
        hasStick: !!stick,
      };
    });
  }
  if (e?.clips?.length) {
    return e.clips.map((c) => ({
      name: c.name,
      len: c.len,
      start: c.start,
      frameNames: [],
      mdlFrames: [],
      hasStick: true,
    }));
  }
  return [];
}

function clampFrameIndex(e) {
  if (!e?.frames?.length) {
    frameIndex = 0;
    return;
  }
  if (e.clips?.length) {
    frameIndex = Math.max(0, Math.min(frameIndex, e.frames.length - 1));
  }
}

function syncClipFromFrameIndex(e) {
  const timeline = getTimeline(e);
  if (!timeline.length) {
    clipIndex = 0;
    frameLocal = 0;
    return;
  }
  const mdl = sharewareModels[e?.name];
  if (e?.clips?.length) {
    const stick = clipForFrame(e.clips, frameIndex);
    if (stick) {
      const idx = timeline.findIndex((c) => c.name === stick.name);
      if (idx >= 0) {
        clipIndex = idx;
        frameLocal = frameIndex - stick.start;
        return;
      }
      if (!mdl) {
        clipIndex = Math.max(0, e.clips.indexOf(stick));
        frameLocal = frameIndex - stick.start;
        return;
      }
    }
  }
  if (clipIndex >= timeline.length) clipIndex = 0;
  const clip = timeline[clipIndex];
  frameLocal = Math.max(0, Math.min(frameLocal, clip.len - 1));
}

function frameLabel(e, fi) {
  if (!e?.clips?.length) return "rest";
  const clip = clipForFrame(e.clips, fi);
  if (!clip) return `frame ${fi}`;
  return `${clip.name} ${fi - clip.start}`;
}

function activeTimelineClip() {
  const timeline = getTimeline(activeEnemy());
  if (!timeline.length) return null;
  if (clipIndex >= timeline.length) clipIndex = 0;
  return timeline[clipIndex];
}

function setMode(mode) {
  if (mode === "sounds") mode = "layout";
  editorMode = mode;
  document.getElementById("btn-mode-layout").classList.toggle("active", mode === "layout");
  document.getElementById("btn-mode-anim").classList.toggle("active", mode === "anim");
  document.getElementById("btn-mode-weapons").classList.toggle("active", mode === "weapons");
  document.getElementById("btn-mode-items")?.classList.toggle("active", mode === "items");
  document.getElementById("btn-mode-build")?.classList.toggle("active", mode === "build");
  document.querySelector(".layout")?.classList.toggle("layout-build", mode === "build");
  const leftAside = document.querySelector(".left");
  if (leftAside) leftAside.hidden = mode === "build";
  const rightAside = document.querySelector(".right");
  if (rightAside) rightAside.hidden = mode === "build";
  const buildPanel = document.getElementById("build-panel");
  if (buildPanel) buildPanel.hidden = mode !== "build";
  const centerHeading = document.querySelector(".center-heading");
  if (centerHeading) centerHeading.hidden = mode === "build";
  const mapStage = document.getElementById("map-stage");
  if (mapStage) mapStage.hidden = mode === "build";
  const stick = mode === "anim";
  mapStage?.classList.toggle("stick-stage", stick);
  for (const id of ["stick-left", "stick-front"]) {
    const el = document.getElementById(id);
    if (el) el.hidden = !stick;
  }
  stickLeft.enabled = stick;
  stickFront.enabled = stick;
  const hintEl = document.getElementById("hint");
  if (hintEl) hintEl.hidden = mode === "build";
  document.getElementById("layout-left").hidden = mode !== "layout";
  document.querySelector(".left")?.classList.toggle("left-map", mode === "layout");
  document.getElementById("anim-left").hidden = mode !== "anim";
  document.getElementById("weapons-left").hidden = mode !== "weapons";
  const itemsLeft = document.getElementById("items-left");
  if (itemsLeft) itemsLeft.hidden = mode !== "items";
  document.getElementById("draw-mode-group").classList.toggle("inactive", mode !== "layout");
  for (const id of ["btn-draw-all", "btn-draw-local", "btn-draw-neighbours", "btn-draw-rooms-only"]) {
    const btn = document.getElementById(id);
    if (btn) btn.disabled = mode !== "layout";
  }
  document.getElementById("overhead-panel").hidden = mode !== "layout";
  document.getElementById("preview-panel").hidden = mode !== "layout";
  document.getElementById("weapon-preview-panel").hidden = mode !== "weapons";
  if (mode !== "layout") clearPaletteDrag();
  updateCenterChrome();
  document.getElementById("hint").textContent =
    mode === "layout"
      ? "Drag palette to place · LMB box/click-select · Shift add · WASD/wheel fly · Q/E up · RMB look · Alt+LMB / Alt+MMB orbit · MMB pan · Alt+RMB zoom · F focus · G drop · Ctrl+D dup · gizmo moves selection · Del"
      : mode === "weapons"
        ? "LMB drag pans · wheel scale"
        : mode === "items"
          ? "LMB box-select verts · click vert/line to select · Shift add · gizmo moves · V add vert · L add line · Ctrl+C/V copy/paste · Del · F focus · MMB pan · Alt+LMB / RMB orbit · Alt+RMB zoom"
          : mode === "build"
              ? "Open the repo once · Reload after a build"
              : animHintText();
  layoutView.enabled = mode === "layout";
  animView.enabled = mode === "anim";
  weaponView.enabled = mode === "weapons";
  itemView.enabled = mode === "items";
  if (mode === "layout") layoutView.resize();
  else if (mode === "anim") {
    requestAnimationFrame(() => {
      animView.resize();
      stickLeft.resize();
      stickFront.resize();
    });
  } else if (mode === "weapons") weaponView.resize();
  else if (mode === "items") itemView.resize();
  if (mode === "build") showBuildView();
  if (mode !== "anim") stopAnimPlay();
  refreshAll();
  markUi();
}

function setOrthoMode(mode) {
  overheadView.setMode(mode);
  document.getElementById("btn-ortho-top").classList.toggle("active", mode === "top");
  document.getElementById("btn-ortho-left").classList.toggle("active", mode === "left");
  document.getElementById("btn-ortho-forward").classList.toggle("active", mode === "forward");
  const hint = document.getElementById("ortho-hint");
  if (hint) hint.textContent = overheadView.hint();
  markUi();
}

function syncDrawButtons() {
  document.getElementById("btn-draw-all").classList.toggle("active", !localDraw);
  document.getElementById("btn-draw-local").classList.toggle("active", localDraw);
  document.getElementById("btn-draw-neighbours")?.classList.toggle("active", neighbourDraw);
  document.getElementById("btn-draw-rooms-only")?.classList.toggle("active", roomsOnlyDraw);
}

function drawModeStatus() {
  let msg;
  if (!localDraw) msg = "All rooms";
  else if (!localFocusRoom(doc, selectedIds, lastRoomId)) msg = "Local: no room selected";
  else msg = neighbourDraw ? "Local + neighbours" : "Local draw";
  if (roomsOnlyDraw) msg += " (rooms only)";
  return msg;
}

function setDrawMode(local) {
  localDraw = local;
  syncDrawButtons();
  const msg = drawModeStatus();
  setStatus(msg, local && msg.startsWith("Local: no"));
  refreshAll();
  markUi();
}

function setNeighbourDraw(on, redraw = true) {
  neighbourDraw = !!on;
  syncDrawButtons();
  if (redraw) {
    const msg = drawModeStatus();
    if (localDraw) setStatus(msg, msg.startsWith("Local: no"));
    refreshAll();
    markUi();
  }
}

function setRoomsOnlyDraw(on, redraw = true) {
  roomsOnlyDraw = !!on;
  syncDrawButtons();
  if (redraw) {
    const msg = drawModeStatus();
    setStatus(msg, msg.startsWith("Local: no"));
    refreshAll();
    markUi();
  }
}

function canvasClientToScreen(e) {
  const canvas = document.getElementById("view-canvas");
  const rect = canvas.getBoundingClientRect();
  const over =
    e.clientX >= rect.left &&
    e.clientX <= rect.right &&
    e.clientY >= rect.top &&
    e.clientY <= rect.bottom;
  return {
    over,
    mx: ((e.clientX - rect.left) / rect.width) * layoutView.cssW,
    my: ((e.clientY - rect.top) / rect.height) * layoutView.cssH,
  };
}

/** Owner room for palette drop: ray-hit room, miss → selected/last. */
function placeOwner(kind, hitRoom) {
  if (kind === "room") return null;
  return hitRoom || placementRoom();
}

function previewObjectAtScreen(place, mx, my) {
  const kind = place.kind;
  const p = layoutView.placeAtScreen(mx, my, kind);
  const owner = placeOwner(kind, p.room);
  const extra = {};
  if (place.enemy) extra.enemy = place.enemy;
  if (place.pickup) extra.pickup = place.pickup;
  if (owner) extra.roomId = owner.id;
  if (kind === "spawn") {
    extra.enabled = !activeMap(doc).objects.some((o) => o.kind === "spawn");
  }
  const obj = createObject(kind, p.x, p.y, p.z, extra);
  if (kind === "doorway" && p.face) {
    snapDoorToFace(obj, p.face, p.hitY);
  } else if (kind === "switch" && p.face) {
    snapSwitchToFace(obj, p.face, p.hitY);
  } else if (owner && kind !== "room" && p.floorSnap !== false) {
    obj.y = roomFloorY(owner, obj.x + obj.sx / 2, obj.z + obj.sz / 2);
  }
  clampObject(obj);
  return obj;
}

function clearPaletteDrag() {
  document.body.classList.remove("palette-dragging");
  layoutView.clearPlacePreview();
  pendingPlace = null;
  if (editorMode === "layout") layoutView.draw();
}

function updatePaletteDrag(e) {
  if (!pendingPlace || pendingPlace.pointerId !== e.pointerId || editorMode !== "layout") return;
  const { over, mx, my } = canvasClientToScreen(e);
  if (over) layoutView.setPlacePreview(previewObjectAtScreen(pendingPlace, mx, my), true);
  else layoutView.setPlacePreview(null, false);
  layoutView.draw();
}

function buildPalette() {
  const root = document.getElementById("item-palette");
  root.innerHTML = "";
  for (const kind of PALETTE_ORDER) {
    root.appendChild(paletteButton(KINDS[kind].label, KINDS[kind].color, { kind }));
  }
  const thingsSep = document.createElement("div");
  thingsSep.className = "palette-sep";
  thingsSep.textContent = "Things";
  root.appendChild(thingsSep);
  const things = document.createElement("div");
  things.className = "palette-things";
  for (const t of PICKUP_TYPES) {
    things.appendChild(paletteButton(t, KINDS.pickup.color, { kind: "pickup", pickup: t }));
  }
  root.appendChild(things);
  const sep = document.createElement("div");
  sep.className = "palette-sep";
  sep.textContent = "Enemies";
  root.appendChild(sep);
  const enemies = document.createElement("div");
  enemies.className = "palette-enemies";
  for (const t of enemyTypesByHp(doc.enemies)) {
    if (!DOOM_SPRITE_PREFIX[t.name]) continue;
    enemies.appendChild(paletteButton(t.name, KINDS.enemy.color, { kind: "enemy", enemy: t.name }));
  }
  root.appendChild(enemies);
  bindPaletteIconResize(root);
  paintEnemyPaletteIcons();
}

/** Front-3/4 of editor +Z, a little above — rest pose, not the layout walk cycle. */
const ENEMY_ICON_YAW = Math.PI - 0.45;
const ENEMY_ICON_PITCH = -0.3;

let paletteIconRo = null;

function bindPaletteIconResize(root) {
  paletteIconRo?.disconnect();
  paletteIconRo = new ResizeObserver(() => paintEnemyPaletteIcons());
  paletteIconRo.observe(root);
}

function paintEnemyPaletteIcons() {
  for (const canvas of document.querySelectorAll(".palette-enemy-icon")) {
    paintEnemyIcon(canvas, findEnemyTemplate(doc, canvas.dataset.enemy));
  }
}

function paintEnemyIcon(canvas, template) {
  const cssW = canvas.clientWidth >= 8 ? canvas.clientWidth : 96;
  const cssH = canvas.clientHeight >= 8 ? canvas.clientHeight : 36;
  const dpr = window.devicePixelRatio || 1;
  const w = Math.max(1, Math.round(cssW * dpr));
  const h = Math.max(1, Math.round(cssH * dpr));
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, w, h);
  const frame = enemyPreviewFrame(template);
  const lines = template?.lines;
  if (!frame?.length || !lines?.length) return;

  let minX = Infinity;
  let minY = Infinity;
  let minZ = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  let maxZ = -Infinity;
  for (const v of frame) {
    if (v.x < minX) minX = v.x;
    if (v.y < minY) minY = v.y;
    if (v.z < minZ) minZ = v.z;
    if (v.x > maxX) maxX = v.x;
    if (v.y > maxY) maxY = v.y;
    if (v.z > maxZ) maxZ = v.z;
  }
  const cx = (minX + maxX) / 2;
  const cy = (minY + maxY) / 2;
  const cz = (minZ + maxZ) / 2;
  const radius = Math.max(1, Math.hypot(maxX - minX, maxY - minY, maxZ - minZ) * 0.5);
  const { forward } = lookVectors(ENEMY_ICON_YAW, ENEMY_ICON_PITCH);
  const dist = radius * 3.2;
  const cam = {
    x: cx - forward.x * dist,
    y: cy - forward.y * dist,
    z: cz - forward.z * dist,
    yaw: ENEMY_ICON_YAW,
    pitch: ENEMY_ICON_PITCH,
  };
  const focal = Math.min(w, h) * 0.9;
  const segs = [];
  for (const [i, j] of lines) {
    const a = frame[i];
    const b = frame[j];
    if (!a || !b) continue;
    const seg = projectLine(a, b, cam, w, h, focal);
    if (seg) segs.push(seg);
  }
  if (!segs.length) return;

  let sx0 = Infinity;
  let sy0 = Infinity;
  let sx1 = -Infinity;
  let sy1 = -Infinity;
  for (const s of segs) {
    sx0 = Math.min(sx0, s.ax, s.bx);
    sy0 = Math.min(sy0, s.ay, s.by);
    sx1 = Math.max(sx1, s.ax, s.bx);
    sy1 = Math.max(sy1, s.ay, s.by);
  }
  const bw = Math.max(1, sx1 - sx0);
  const bh = Math.max(1, sy1 - sy0);
  const pad = Math.max(2 * dpr, Math.round(Math.min(w, h) * 0.08));
  const scale = Math.min((w - pad * 2) / bw, (h - pad * 2) / bh);
  const ox = (w - bw * scale) / 2 - sx0 * scale;
  const oy = (h - bh * scale) / 2 - sy0 * scale;

  ctx.strokeStyle = KINDS.enemy.color;
  ctx.lineWidth = Math.max(1, dpr);
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.beginPath();
  for (const s of segs) {
    ctx.moveTo(s.ax * scale + ox, s.ay * scale + oy);
    ctx.lineTo(s.bx * scale + ox, s.by * scale + oy);
  }
  ctx.stroke();
}

function paletteButton(label, color, payload) {
  const el = document.createElement("button");
  el.type = "button";
  el.className = "palette-item";
  el.style.borderColor = color;
  if (payload.enemy) {
    el.classList.add("palette-enemy");
    const icon = document.createElement("canvas");
    icon.className = "palette-enemy-icon";
    icon.dataset.enemy = payload.enemy;
    icon.setAttribute("aria-hidden", "true");
    const name = document.createElement("span");
    name.className = "palette-enemy-name";
    name.textContent = label;
    el.append(icon, name);
  } else if (payload.pickup) {
    el.classList.add("palette-thing");
    const icon = document.createElement("img");
    icon.className = "palette-thing-icon";
    icon.alt = "";
    icon.draggable = false;
    icon.src = `thingicons/${PICKUP_ICON[payload.pickup]}.png`;
    const name = document.createElement("span");
    name.className = "palette-thing-name";
    name.textContent = label;
    el.append(icon, name);
  } else if (KIND_ICON[payload.kind]) {
    const icon = document.createElement("img");
    icon.className = "palette-thing-icon";
    icon.alt = "";
    icon.draggable = false;
    icon.src = `thingicons/${KIND_ICON[payload.kind]}.png`;
    const name = document.createElement("span");
    name.className = "palette-thing-name";
    name.textContent = label;
    el.append(icon, name);
  } else {
    el.textContent = label;
  }
  el.title = payload.pickup ? label : "Drag onto the map to place";
  el.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    pendingPlace = { ...payload, pointerId: e.pointerId };
    el.setPointerCapture(e.pointerId);
    document.body.classList.add("palette-dragging");
    setStatus(`Drop ${label} on the map…`);
  });
  el.addEventListener("pointermove", (e) => {
    updatePaletteDrag(e);
  });
  el.addEventListener("pointerup", (e) => {
    if (!pendingPlace || pendingPlace.pointerId !== e.pointerId) return;
    finishPaletteDrop(e);
  });
  el.addEventListener("pointercancel", (e) => {
    if (pendingPlace?.pointerId === e.pointerId) clearPaletteDrag();
  });
  return el;
}

function finishPaletteDrop(e) {
  const place = pendingPlace;
  document.body.classList.remove("palette-dragging");
  layoutView.clearPlacePreview();
  pendingPlace = null;
  if (!place || editorMode !== "layout") return;
  const { over, mx, my } = canvasClientToScreen(e);
  if (!over) {
    layoutView.draw();
    setStatus("Place cancelled", true);
    return;
  }
  const kind = place.kind;
  const p = layoutView.placeAtScreen(mx, my, kind);
  const owner = placeOwner(kind, p.room);
  if (kind === "room" && roomsOf(doc).length >= ROOM_MAX) {
    layoutView.draw();
    setStatus(`Max ${ROOM_MAX} rooms`, true);
    return;
  }
  if (kind === "enemy" && activeMap(doc).objects.filter((o) => o.kind === "enemy").length >= ENEMY_MAX) {
    layoutView.draw();
    setStatus(`Max ${ENEMY_MAX} enemies`, true);
    return;
  }
  if (kind === "enemy" && !canAddEnemyType(activeMap(doc), place.enemy, owner?.id)) {
    layoutView.draw();
    setStatus(`Max ${ROOM_MAX_TYPES} enemy types per room`, true);
    return;
  }
  pushUndo();
  const obj = previewObjectAtScreen(place, mx, my);
  activeMap(doc).objects.push(obj);
  if (kind === "doorway") {
    assignDoorRooms(doc, obj, owner, false);
    clampObject(obj);
  }
  if (kind === "room") lastRoomId = obj.id;
  selectedIds = [obj.id];
  rememberSelectedRoom();
  markDirty();
  refreshAll();
  setStatus(place.enemy ? `Placed ${place.enemy}` : `Placed ${KINDS[kind].label}`);
}

function selectedObject() {
  if (selectedIds.length !== 1) return null;
  return activeMap(doc).objects.find((o) => o.id === selectedIds[0]) || null;
}

function selectedLayoutObjects() {
  const map = activeMap(doc);
  return selectedIds.map((id) => map.objects.find((o) => o.id === id)).filter(Boolean);
}

function unanimous(objs, get) {
  if (!objs.length) return undefined;
  const v0 = get(objs[0]);
  for (let i = 1; i < objs.length; i++) {
    if (get(objs[i]) !== v0) return undefined;
  }
  return v0;
}

function rememberSelectedRoom() {
  for (let i = selectedIds.length - 1; i >= 0; i--) {
    const obj = activeMap(doc).objects.find((o) => o.id === selectedIds[i]);
    if (!obj) continue;
    if (obj.kind === "room") {
      lastRoomId = obj.id;
      break;
    }
    if (obj.roomId) {
      lastRoomId = obj.roomId;
      break;
    }
  }
  if (localDraw && !applyingEditor) {
    const msg = drawModeStatus();
    setStatus(msg, msg.startsWith("Local: no"));
  }
}

function placementRoom() {
  const obj = selectedObject();
  if (obj?.kind === "room") return obj;
  if (obj?.roomId) {
    const r = roomById(doc, obj.roomId);
    if (r) return r;
  }
  return roomById(doc, lastRoomId);
}

function deleteSelected() {
  if (editorMode === "layout") {
    if (!selectedIds.length) return;
    pushUndo();
    const drop = new Set(selectedIds);
    for (const o of activeMap(doc).objects) {
      if (o.kind === "room") continue;
      if (o.roomId && drop.has(o.roomId)) o.roomId = null;
      if (o.otherRoomId && drop.has(o.otherRoomId)) o.otherRoomId = null;
    }
    activeMap(doc).objects = activeMap(doc).objects.filter((o) => !drop.has(o.id));
    ensureSpawnExclusive(activeMap(doc).objects);
    selectedIds = [];
    markDirty();
    refreshAll();
    return;
  }
}

function duplicateSelected() {
  if (!selectedIds.length || editorMode !== "layout") return;
  pushUndo();
  const created = [];
  let skipped = 0;
  let skipReason = "";
  for (const id of selectedIds) {
    const obj = activeMap(doc).objects.find((o) => o.id === id);
    if (!obj) continue;
    if (obj.kind === "room" && roomsOf(doc).length >= ROOM_MAX) {
      skipped++;
      skipReason = `Max ${ROOM_MAX} rooms`;
      continue;
    }
    if (obj.kind === "enemy" && activeMap(doc).objects.filter((o) => o.kind === "enemy").length >= ENEMY_MAX) {
      skipped++;
      skipReason = `Max ${ENEMY_MAX} enemies`;
      continue;
    }
    if (obj.kind === "enemy" && !canAddEnemyType(activeMap(doc), obj.enemy, obj.roomId)) {
      skipped++;
      skipReason = `Max ${ROOM_MAX_TYPES} enemy types per room`;
      continue;
    }
    const copy = clampObject({
      ...obj,
      id: uid(),
      x: obj.x + 2,
      z: obj.z + 2,
    });
    if (copy.kind === "spawn") copy.enabled = false;
    activeMap(doc).objects.push(copy);
    created.push(copy.id);
  }
  if (!created.length) {
    endUndo();
    undoStack.pop();
    updateUndoButtons();
    setStatus(skipped ? skipReason : "Nothing to duplicate", true);
    return;
  }
  selectedIds = created;
  markDirty();
  refreshAll();
  setStatus(skipped ? `Duplicated ${created.length} (${skipped} skipped)` : `Duplicated ${created.length}`);
}

function dropSelectedToFloor() {
  if (!selectedIds.length || editorMode !== "layout") return;
  pushUndo();
  let n = 0;
  for (const id of selectedIds) {
    const obj = activeMap(doc).objects.find((o) => o.id === id);
    if (!obj || obj.kind === "room" || obj.kind === "doorway") continue;
    const room = roomUnderObject(doc, obj);
    obj.y = room ? roomFloorY(room, obj.x + obj.sx / 2, obj.z + obj.sz / 2) : 0;
    clampObject(obj);
    n++;
  }
  if (!n) {
    endUndo();
    undoStack.pop();
    updateUndoButtons();
    setStatus("Nothing to drop", true);
    return;
  }
  markDirty();
  refreshAll();
  setStatus(`Dropped ${n} to floor`);
}

function switchLevel(name) {
  if (!LEVEL_NAMES.includes(name) || name === doc.activeLevel) return;
  layoutCamerasByLevel[doc.activeLevel] = snapshotLayoutCamera();
  doc.activeLevel = name;
  restoreLayoutCameraForLevel(name);
  selectedIds = [];
  lastRoomId = null;
  collapsedRooms.clear();
  markUi();
  refreshAll();
  setStatus(name);
}

function updateCenterChrome() {
  const titleEl = document.getElementById("center-title");
  const statsEl = document.getElementById("map-stats");
  if (editorMode === "layout") {
    const map = activeMap(doc);
    titleEl.textContent = map.name
      ? `Map ${doc.activeLevel} — ${map.name}`
      : `Map ${doc.activeLevel}`;
    if (statsEl) {
      const stats = mapStats(doc);
      statsEl.hidden = false;
      statsEl.replaceChildren();
      formatMapStats(stats).forEach((part, i) => {
        if (i) statsEl.append(" · ");
        if (part.over) {
          const span = document.createElement("span");
          span.className = "over";
          span.textContent = part.text;
          statsEl.append(span);
        } else {
          statsEl.append(part.text);
        }
      });
      statsEl.title = formatMapLoadTitle(stats);
      statsEl.classList.toggle("error", !!stats.overBudget);
    }
    return;
  }
  titleEl.textContent =
    editorMode === "weapons"
      ? WEAPON_LABELS[weaponKey] || "Weapons"
      : editorMode === "items"
        ? itemMeshKey
        : editorMode === "build"
          ? "Build"
          : "Enemy";
  if (statsEl) {
    statsEl.hidden = true;
    statsEl.textContent = "";
    statsEl.title = "";
    statsEl.classList.remove("error");
  }
}

function renderLevelList() {
  const root = document.getElementById("level-list");
  if (!root) return;
  root.classList.add("level-list");
  root.innerHTML = "";
  const title = document.createElement("h2");
  title.textContent = "Levels";
  root.appendChild(title);
  const ul = document.createElement("ul");
  const terms = layoutSearchTerms(layoutSearch);
  for (const name of LEVEL_NAMES) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    const map = doc.maps[name];
    const display = clampName(map?.name);
    btn.textContent = name;
    btn.title = display ? `${name} — ${display}` : name;
    if (name === doc.activeLevel) btn.classList.add("active");
    if (mapMatchesLayoutSearch(map, terms)) btn.classList.add("search-hit");
    btn.addEventListener("click", () => switchLevel(name));
    li.appendChild(btn);
    ul.appendChild(li);
  }
  root.appendChild(ul);
}

function selectObjectIds(ids, additive) {
  const added = [];
  if (additive) {
    for (const id of ids) {
      const i = selectedIds.indexOf(id);
      if (i >= 0) selectedIds.splice(i, 1);
      else {
        selectedIds.push(id);
        added.push(id);
      }
    }
  } else {
    selectedIds = [...ids];
    added.push(...ids);
  }
  rememberSelectedRoom();
  connectUnlinkedDoors(added);
  markDirty();
  refreshPanels();
}

function connectUnlinkedDoors(ids) {
  const map = activeMap(doc);
  const doors = [];
  for (const id of ids) {
    const obj = map.objects.find((o) => o.id === id);
    if (obj?.kind === "doorway" && !doorDoublyConnected(doc, obj)) doors.push(obj);
  }
  if (!doors.length) return false;
  pushUndo();
  let n = 0;
  for (const door of doors) {
    if (tryConnectDoor(doc, door)) {
      clampObject(door);
      n++;
    }
  }
  if (!n) {
    undoStack.pop();
    updateUndoButtons();
    if (doors.length === 1) setStatus("Doorway not connected to two rooms", true);
    return false;
  }
  markDirty();
  setStatus(n === 1 ? "Connected doorway" : `Connected ${n} doorways`);
  return true;
}

function makeObjectListButton(obj, terms) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = objectLabel(obj);
  btn.classList.add(obj.kind === "room" ? "tree-label-wrap" : "tree-label-elide");
  if (selectedIds.includes(obj.id)) btn.classList.add("active");
  if (objectMatchesLayoutSearch(obj, terms)) btn.classList.add("search-hit");
  if (obj.kind === "doorway" && !doorDoublyConnected(doc, obj)) {
    btn.classList.add("door-unlinked");
    btn.title = "Not connected to two rooms";
  }
  btn.addEventListener("click", (e) => {
    selectObjectIds([obj.id], e.shiftKey);
  });
  return btn;
}

function renderObjectList() {
  const ul = document.getElementById("object-list");
  ul.innerHTML = "";
  ul.classList.add("object-tree");
  const { nodes, orphans } = objectTree(doc);
  const terms = layoutSearchTerms(layoutSearch);
  const searching = terms.length > 0;

  for (const { room, children } of nodes) {
    const li = document.createElement("li");
    li.className = "tree-room";
    const row = document.createElement("div");
    row.className = "tree-row";
    const twist = document.createElement("button");
    twist.type = "button";
    twist.className = "tree-twist";
    const roomHit = objectMatchesLayoutSearch(room, terms);
    const childHit = children.some((obj) => objectMatchesLayoutSearch(obj, terms));
    const collapsed = !(searching && (roomHit || childHit)) && collapsedRooms.has(room.id);
    twist.textContent = collapsed ? "▸" : "▾";
    twist.title = collapsed ? "Expand" : "Collapse";
    twist.addEventListener("click", (e) => {
      e.stopPropagation();
      if (collapsedRooms.has(room.id)) collapsedRooms.delete(room.id);
      else collapsedRooms.add(room.id);
      markUi();
      renderObjectList();
    });
    const roomBtn = makeObjectListButton(room, terms);
    roomBtn.classList.add("tree-room-btn");
    row.append(twist, roomBtn);
    li.appendChild(row);
    if (!collapsed) {
      const childUl = document.createElement("ul");
      childUl.className = "tree-children";
      if (!children.length) {
        const empty = document.createElement("li");
        empty.className = "tree-empty";
        empty.textContent = "(empty)";
        childUl.appendChild(empty);
      } else {
        for (const obj of children) {
          const cli = document.createElement("li");
          cli.appendChild(makeObjectListButton(obj, terms));
          childUl.appendChild(cli);
        }
      }
      li.appendChild(childUl);
    }
    ul.appendChild(li);
  }

  if (orphans.length) {
    const li = document.createElement("li");
    li.className = "tree-orphans";
    const label = document.createElement("div");
    label.className = "tree-orphan-label";
    label.textContent = "Outside rooms";
    li.appendChild(label);
    const childUl = document.createElement("ul");
    childUl.className = "tree-children";
    for (const obj of orphans) {
      const cli = document.createElement("li");
      cli.appendChild(makeObjectListButton(obj, terms));
      childUl.appendChild(cli);
    }
    li.appendChild(childUl);
    ul.appendChild(li);
  }
}

function renderEnemyList() {
  const ul = document.getElementById("enemy-list");
  ul.innerHTML = "";
  enemiesByHp(doc.enemies).forEach((e) => {
    const i = doc.enemies.indexOf(e);
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = `${e.name}  ${e.hp}`;
    if (i === enemyIndex) btn.className = "active";
    btn.addEventListener("click", () => {
      const prevClip = activeTimelineClip()?.name;
      enemyIndex = i;
      selectedVerts = [];
      selectedLines = [];
      pendingBind = null;
      bindJoint = -1;
      clampFrameIndex(activeEnemy());
      const timeline = getTimeline(activeEnemy());
      if (prevClip) {
        const idx = timeline.findIndex((c) => c.name === prevClip);
        clipIndex = idx >= 0 ? idx : 0;
      } else clipIndex = 0;
      frameLocal = 0;
      applyFrameLocal();
      markUi();
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  });
}

function renderMeshKeyList(ul, keys) {
  if (!ul) return;
  ul.innerHTML = "";
  if (!doc.items) doc.items = {};
  for (const key of keys) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = key;
    if (key === itemMeshKey) btn.className = "active";
    btn.addEventListener("click", () => {
      itemMeshKey = key;
      if (!doc.items[key]) doc.items[key] = { verts: [], lines: [] };
      itemView.clearSelection();
      persistEditorSettings();
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  }
}

function renderItemBudget() {
  const bud = itemGlobalBudgets(doc);
  const fill = (id, n) => {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = `${n} / ${ITEM_TABLE_MAX}`;
    el.classList.toggle("error", n > ITEM_TABLE_MAX - 1);
  };
  fill("bud-item-nv", bud.pickups.nv);
  fill("bud-item-nx", bud.pickups.nx);
  fill("bud-item-nz", bud.pickups.nz);
  fill("bud-item-ne", bud.pickups.ne);
  fill("bud-door-nv", bud.doors.nv);
  fill("bud-door-nx", bud.doors.nx);
  fill("bud-door-nz", bud.doors.nz);
  fill("bud-door-ne", bud.doors.ne);
}

function renderItemList() {
  renderItemBudget();
  renderMeshKeyList(document.getElementById("item-mesh-list"), ITEM_MESH_KEYS);
  renderMeshKeyList(document.getElementById("door-mesh-list"), DOOR_MESH_KEYS);
}

function ensureWeaponItem(key) {
  if (!doc.weapons) doc.weapons = { scale: DEFAULT_WEAPON_SCALE, items: {} };
  if (!doc.weapons.items[key]) {
    doc.weapons.items[key] = { pan: { x: 0, y: 0 }, frames: null };
  }
  return doc.weapons.items[key];
}

function selectedWeaponFrames() {
  const mdl = sharewareWeapons[weaponKey];
  const item = ensureWeaponItem(weaponKey);
  return resolveWeaponFrames(item, mdl, weaponKey);
}

function clampWeaponPreviewFrame() {
  const mdl = sharewareWeapons[weaponKey];
  const selected = selectedWeaponFrames();
  if (mdl?.frames?.length) {
    weaponFrame = Math.max(0, Math.min(weaponFrame, mdl.frames.length - 1));
  }
  if (selected.length && !selected.includes(weaponFrame)) {
    weaponFrame = selected[0];
  }
}

function syncWeaponScaleInputs() {
  const range = document.getElementById("weapon-scale");
  const num = document.getElementById("weapon-scale-num");
  const shown = String(doc.weapons.scale);
  if (range && range.value !== shown) range.value = shown;
  if (num && document.activeElement !== num && num.value !== shown) num.value = shown;
}

function syncSharewareFolderButtons() {
  const folder = sharewareFolderName();
  const label = folder ? "Change folder…" : "Open shareware folder";
  const weaponBtn = document.getElementById("btn-weapon-folder");
  if (weaponBtn) weaponBtn.textContent = label;
  const animBtn = document.getElementById("btn-anim-folder");
  if (animBtn) animBtn.textContent = label;
  const exportBtn = document.getElementById("btn-weapon-export");
  if (exportBtn) exportBtn.disabled = !Object.keys(sharewareWeapons).length;
}

function refreshWeaponClipStatus() {
  if (editorMode !== "weapons") return;
  if (!sharewareWeapons[weaponKey]) return;
  const n = selectedWeaponFrames().length;
  setStatus(`${WEAPON_LABELS[weaponKey]} · ${n} export frame${n === 1 ? "" : "s"}`);
}

function pixelsToPngBlob(pixels) {
  const canvas = document.createElement("canvas");
  canvas.width = WEAPON_SPRITE_W;
  canvas.height = WEAPON_SPRITE_H;
  const ctx = canvas.getContext("2d");
  const img = ctx.createImageData(WEAPON_SPRITE_W, WEAPON_SPRITE_H);
  for (let i = 0; i < pixels.length; i++) {
    const on = pixels[i] ? 1 : 0;
    const o = i * 4;
    img.data[o] = on ? 232 : 0;
    img.data[o + 1] = on ? 228 : 0;
    img.data[o + 2] = on ? 216 : 0;
    img.data[o + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("PNG encode failed"));
    }, "image/png");
  });
}

async function exportWeaponPngs() {
  if (!Object.keys(sharewareWeapons).length) {
    setStatus("Load shareware to export", true);
    return;
  }
  const dir = await ensureWeaponsPngDirectory();
  if (!dir) return;
  let n = 0;
  for (const key of WEAPON_KEYS) {
    const mdl = sharewareWeapons[key];
    if (!mdl) continue;
    const item = ensureWeaponItem(key);
    const frames = resolveWeaponFrames(item, mdl, key);
    const pan = item.pan || { x: 0, y: 0 };
    for (const fi of frames) {
      const { pixels } = rasterWeaponFrame(mdl, fi, doc.weapons.scale, pan);
      const blob = await pixelsToPngBlob(pixels);
      await writePngFile(dir, `${key}_${fi}.png`, blob);
      n++;
    }
  }
  setStatus(`Exported ${n} PNG${n === 1 ? "" : "s"} (copy to *_edit.png to clean)`);
}

function renderWeaponList() {
  const ul = document.getElementById("weapon-list");
  if (!ul) return;
  ul.innerHTML = "";
  for (const key of WEAPON_KEYS) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = WEAPON_LABELS[key];
    if (key === weaponKey) btn.className = "active";
    btn.addEventListener("click", () => {
      weaponKey = key;
      clampWeaponPreviewFrame();
      markUi();
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  }
}

function renderWeaponInspector(root) {
  const h = document.createElement("h2");
  h.textContent = WEAPON_LABELS[weaponKey] || weaponKey;
  root.appendChild(h);

  const mdl = sharewareWeapons[weaponKey];
  const item = ensureWeaponItem(weaponKey);
  const folder = sharewareFolderName();

  const status = document.createElement("p");
  status.className = "muted";
  if (mdl) {
    status.textContent = folder
      ? `${folder} · ${mdl.numVerts} verts · ${mdl.frames.length} frames`
      : `${mdl.numVerts} verts · ${mdl.frames.length} frames`;
  } else if (sharewareWeaponMissing.includes(weaponKey)) {
    const mdlPath = WEAPON_MDL_PATHS[weaponKey];
    status.textContent = folder && mdlPath
      ? `${mdlPath} is not in ${folder}`
      : "View-model not in the opened PAK";
  } else {
    status.textContent = folder
      ? `Opened ${folder}. Open again if models did not load.`
      : "Open a folder that contains pak0.pak or id1/pak0.pak";
  }
  root.appendChild(status);

  root.appendChild(
    vec3Field("Pan XY", [
      {
        value: Math.round(item.pan.x * 100) / 100,
        onChange: (v) => {
          pushUndo();
          item.pan.x = Number.isFinite(v) ? v : 0;
          markDirty();
          refreshAll();
        },
      },
      {
        value: Math.round(item.pan.y * 100) / 100,
        onChange: (v) => {
          pushUndo();
          item.pan.y = Number.isFinite(v) ? v : 0;
          markDirty();
          refreshAll();
        },
      },
    ])
  );

  const fh = document.createElement("h2");
  fh.textContent = "Export frames";
  root.appendChild(fh);
  if (!mdl) {
    const p = document.createElement("p");
    p.className = "muted";
    p.textContent = "Load shareware to pick frames.";
    root.appendChild(p);
    return;
  }

  const selected = new Set(selectedWeaponFrames());
  const ul = document.createElement("ul");
  ul.className = "weapon-frame-list";
  for (const clip of mdl.clips || []) {
    const head = document.createElement("li");
    head.className = "clip-head";
    head.textContent = clip.name;
    ul.appendChild(head);
    for (const fr of clip.frames) {
      const li = document.createElement("li");
      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = selected.has(fr.index);
      chk.addEventListener("change", () => {
        pushUndo();
        const next = new Set(selectedWeaponFrames());
        if (chk.checked) next.add(fr.index);
        else next.delete(fr.index);
        item.frames = [...next].sort((a, b) => a - b);
        clampWeaponPreviewFrame();
        markDirty();
        refreshAll();
      });
      const nameBtn = document.createElement("button");
      nameBtn.type = "button";
      nameBtn.className = "frame-name" + (weaponFrame === fr.index ? " current" : "");
      nameBtn.textContent = fr.name || `frame ${fr.index}`;
      nameBtn.addEventListener("click", () => {
        weaponFrame = fr.index;
        markDirty();
        refreshAll();
      });
      li.append(chk, nameBtn);
      ul.appendChild(li);
    }
  }
  root.appendChild(ul);
}

function field(label, input) {
  const row = document.createElement("label");
  row.className = "field";
  const span = document.createElement("span");
  span.textContent = label;
  row.append(span, input);
  return row;
}

function toggleField(label, active, onToggle) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = label;
  btn.classList.toggle("active", !!active);
  btn.addEventListener("click", () => onToggle(btn));
  return field(label, btn);
}

function rotateRow(onClick) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = "Rotate";
  btn.addEventListener("click", onClick);
  return field("Rotate", btn);
}

function vec3Field(label, specs) {
  const row = document.createElement("label");
  row.className = "field vec3";
  const span = document.createElement("span");
  span.textContent = label;
  const wrap = document.createElement("div");
  wrap.className = "vec3-inputs";
  for (const s of specs) {
    const inp = numInput(s.value, s.onChange, s.min, s.max, s.step);
    if (s.axis) inp.dataset.axis = s.axis;
    wrap.appendChild(inp);
  }
  row.append(span, wrap);
  return row;
}

function numInput(value, onChange, min, max, step) {
  const inp = document.createElement("input");
  inp.type = "number";
  inp.value = String(value);
  if (min != null) inp.min = String(min);
  if (max != null) inp.max = String(max);
  if (step != null) inp.step = String(step);
  inp.addEventListener("change", () => onChange(Number(inp.value)));
  return inp;
}

function textInputMixed(current, { maxLength, placeholder, onChange }) {
  const inp = document.createElement("input");
  inp.type = "text";
  if (maxLength != null) inp.maxLength = maxLength;
  if (current === undefined) {
    inp.value = "";
    inp.placeholder = "Mixed";
  } else {
    inp.value = current;
    if (placeholder) inp.placeholder = placeholder;
  }
  inp.addEventListener("change", () => onChange(inp.value));
  return inp;
}

function textareaMixed(current, { rows, maxLength, placeholder, onChange }) {
  const ta = document.createElement("textarea");
  ta.rows = rows;
  if (maxLength != null) ta.maxLength = maxLength;
  if (current === undefined) {
    ta.value = "";
    ta.placeholder = "Mixed";
  } else {
    ta.value = current;
    if (placeholder) ta.placeholder = placeholder;
  }
  ta.addEventListener("change", () => onChange(ta.value));
  return ta;
}

function numberInputMixed(current, onChange) {
  const inp = document.createElement("input");
  inp.type = "number";
  inp.step = "1";
  if (current === undefined) {
    inp.value = "";
    inp.placeholder = "Mixed";
  } else {
    inp.value = String(current);
  }
  inp.addEventListener("change", () => onChange(inp.value | 0));
  return inp;
}

function selectMixed(current, items, onChange) {
  const sel = document.createElement("select");
  if (current === undefined) {
    const mixed = document.createElement("option");
    mixed.value = "__mixed";
    mixed.textContent = "Mixed";
    mixed.selected = true;
    sel.appendChild(mixed);
  }
  for (const it of items) {
    const opt = document.createElement("option");
    opt.value = it.value;
    opt.textContent = it.text;
    if (current !== undefined && String(current) === String(it.value)) opt.selected = true;
    sel.appendChild(opt);
  }
  sel.addEventListener("change", () => {
    if (sel.value === "__mixed") return;
    onChange(sel.value);
  });
  return sel;
}

function layoutInspectorTitle(objs) {
  const kind = objs[0].kind;
  let label;
  if (kind === "enemy") {
    const name = unanimous(objs, (o) => o.enemy || "Enemy");
    label = name === undefined ? "Enemy" : name;
  } else {
    label = KINDS[kind].label;
  }
  return objs.length > 1 ? `${label} (${objs.length})` : label;
}

function roomItems() {
  return [
    { value: "", text: "(none)" },
    ...roomsOf(doc).map((r) => ({ value: r.id, text: r.name || "Room" })),
  ];
}

function a8ByteText(byte) {
  return "$" + byte.toString(16).padStart(2, "0");
}

function roomPaletteEditor(objs, apply) {
  const wrap = document.createElement("div");
  wrap.className = "field color-field room-palette";
  const span = document.createElement("span");
  const cur = unanimous(objs, (o) => o.a8Bg ?? ROOM_BG_DEFAULT);
  span.textContent = cur === undefined ? "Background" : `Background ${a8ByteText(cur)}`;

  const hues = document.createElement("div");
  hues.className = "hue-digits";
  for (let hue = 0; hue < 16; hue++) {
    const digit = document.createElement("span");
    digit.textContent = hue.toString(16).toUpperCase();
    hues.appendChild(digit);
  }

  const row = document.createElement("div");
  row.className = "color-swatches";
  for (const lum of [0x08, 0x06, 0x04]) {
    for (let hue = 0; hue < 16; hue++) {
      const byte = (hue << 4) | lum;
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "swatch" + (byte === cur ? " selected" : "");
      btn.title = a8ByteText(byte);
      btn.style.background = a8Hex(byte);
      btn.addEventListener("click", () => apply((obj) => (obj.a8Bg = byte)));
      row.appendChild(btn);
    }
  }
  wrap.append(span, hues, row);
  return wrap;
}

function appendMixedKindStub(root, objs) {
  const p = document.createElement("p");
  p.className = "muted";
  p.textContent = `${objs.length} selected`;
  root.appendChild(p);
  const selectedRooms = objs.filter((o) => o.kind === "room");
  if (selectedRooms.length < 2) return;
  const row = document.createElement("div");
  row.className = "btn-row";
  const rotY = document.createElement("button");
  rotY.type = "button";
  rotY.textContent = "Rotate Y";
  rotY.addEventListener("click", () => {
    pushUndo();
    rotateRoomsBlockY(
      doc,
      selectedRooms.map((r) => r.id),
      1
    );
    markDirty();
    refreshAll();
  });
  row.append(rotY);
  root.appendChild(row);
}

function renderLayoutObjectFields(root, objs) {
  const kind = objs[0].kind;
  const apply = (fn) => {
    pushUndo();
    for (const obj of objs) {
      fn(obj);
      clampObject(obj);
    }
    markDirty();
    refreshAll();
  };

  if (kind === "room") {
    const nameCur = unanimous(objs, (o) => o.name || "");
    root.appendChild(
      field(
        "Name",
        textInputMixed(nameCur, {
          maxLength: MAX_NAME_LEN,
          placeholder: "Display name",
          onChange: (v) => apply((obj) => (obj.name = clampName(v))),
        })
      )
    );
    root.appendChild(roomPaletteEditor(objs, apply));

    const shapeRow = document.createElement("div");
    shapeRow.className = "btn-row shape-picker";
    const curShape = unanimous(objs, (o) => clampRoomShape(o.shape));
    for (const s of ROOM_SHAPES) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = s === "box" ? "Box" : s;
      btn.classList.toggle("active", curShape === s);
      btn.addEventListener("click", () => {
        if (curShape === s) return;
        apply((obj) => {
          if (clampRoomShape(obj.shape) === s) return;
          applyRoomShape(obj, s);
        });
      });
      shapeRow.append(btn);
    }
    root.appendChild(field("Shape", shapeRow));

    const allNonBox = objs.every((o) => clampRoomShape(o.shape) !== "box");
    const rotAxes = allNonBox ? ["x", "y", "z"] : ["y"];
    const rotRow = document.createElement("div");
    rotRow.className = "btn-row rot-axes";
    for (const axis of rotAxes) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = axis.toUpperCase();
      btn.addEventListener("click", () => {
        if (axis === "y" && objs.length >= 2) {
          pushUndo();
          rotateRoomsBlockY(
            doc,
            objs.map((o) => o.id),
            1
          );
          markDirty();
          refreshAll();
          return;
        }
        apply((obj) => {
          if (axis === "y") rotateRoomY(doc, obj, 1);
          else rotateRoom(obj, axis, 1);
        });
      });
      rotRow.append(btn);
    }
    root.appendChild(field("Rotate", rotRow));
  }

  if (kind === "spawn") {
    const allOn = objs.every((o) => !!o.enabled);
    root.appendChild(
      toggleField("Enabled", allOn, () => {
        pushUndo();
        enableSpawn(activeMap(doc).objects, objs[0].id);
        markDirty();
        refreshAll();
      })
    );
  }

  if (isFigureObject(objs[0])) {
    root.appendChild(rotateRow(() => apply((obj) => (obj.rot = cycleEnemyRot(obj.rot ?? 0)))));
  }

  if (kind === "trigger") {
    const purpose = unanimous(objs, (o) => clampTriggerPurpose(o.purpose));
    root.appendChild(
      field(
        "Purpose",
        selectMixed(
          purpose,
          TRIGGER_PURPOSES.map((p) => ({ value: p, text: TRIGGER_PURPOSE_LABELS[p] })),
          (v) => apply((obj) => (obj.purpose = v))
        )
      )
    );
    if (purpose === "message") {
      const textCur = unanimous(objs, (o) => o.text || "");
      const row = field(
        "Text",
        textareaMixed(textCur, {
          rows: 3,
          maxLength: MAX_TRIGGER_TEXT,
          placeholder: "Shown while inside",
          onChange: (v) => apply((obj) => (obj.text = clampTriggerText(v))),
        })
      );
      row.classList.add("block");
      root.appendChild(row);
    }
    if (purpose !== undefined && triggerUsesTag(purpose)) {
      const tagCur = unanimous(objs, (o) => o.tag || "");
      root.appendChild(
        field(
          "Tag",
          textInputMixed(tagCur, {
            maxLength: MAX_TAG_LEN,
            placeholder: "destination tag",
            onChange: (v) => apply((obj) => (obj.tag = clampTag(v))),
          })
        )
      );
    }
    const enableCur = unanimous(objs, (o) => o.enableTag || "");
    root.appendChild(
      field(
        "Armed by",
        textInputMixed(enableCur, {
          maxLength: MAX_TAG_LEN,
          placeholder: "switch tag (optional)",
          onChange: (v) => apply((obj) => (obj.enableTag = clampTag(v))),
        })
      )
    );
  }

  if (usesLinkTag(kind)) {
    const tagCur = unanimous(objs, (o) => o.tag || "");
    root.appendChild(
      field(
        "Tag",
        textInputMixed(tagCur, {
          maxLength: MAX_TAG_LEN,
          placeholder:
            kind === "elevator"
              ? "elevator link"
              : kind === "switch"
                ? "elevator, door, or trigger"
                : "destination tag",
          onChange: (v) => apply((obj) => (obj.tag = clampTag(v))),
        })
      )
    );
  }

  if (kind === "switch") {
    const allOn = objs.every((o) => !!o.shootable);
    root.appendChild(
      toggleField("Shootable", allOn, () => apply((obj) => (obj.shootable = !allOn)))
    );
  }

  if (kind === "elevator") {
    const allAuto = objs.every((o) => elevHeightsAuto(o));
    root.appendChild(
      toggleField("Auto heights", allAuto, () =>
        apply((obj) => {
          obj.elevAuto = !allAuto;
          if (!obj.elevAuto) {
            const room = roomById(doc, obj.roomId);
            const floorY = room ? room.y | 0 : 0;
            const stops = elevStopBottoms(doc, { ...obj, elevAuto: true });
            obj.elevLow = stops.dest - floorY;
            obj.elevHigh = stops.home - floorY;
            clampElevHeights(obj);
          }
        })
      )
    );
    const auto = unanimous(objs, (o) => elevHeightsAuto(o));
    if (auto === false) {
      for (const obj of objs) clampElevHeights(obj);
      const lowCur = unanimous(objs, (o) => o.elevLow | 0);
      const highCur = unanimous(objs, (o) => o.elevHigh | 0);
      root.appendChild(
        field(
          "Low (vs room)",
          numberInputMixed(lowCur, (n) =>
            apply((obj) => {
              obj.elevLow = n;
              clampElevHeights(obj);
            })
          )
        )
      );
      root.appendChild(
        field(
          "High (vs room)",
          numberInputMixed(highCur, (n) =>
            apply((obj) => {
              obj.elevHigh = n;
              clampElevHeights(obj);
            })
          )
        )
      );
    }
  }

  if (kind === "pickup") {
    const cur = unanimous(objs, (o) => clampPickupType(o.pickup));
    root.appendChild(
      field(
        "Contains",
        selectMixed(
          cur,
          PICKUP_TYPES.map((t) => ({ value: t, text: t })),
          (v) => apply((obj) => (obj.pickup = v))
        )
      )
    );
  }

  if (kind === "platform") {
    const allOn = objs.every((o) => o.collide !== false);
    root.appendChild(
      toggleField("Collide", allOn, () => apply((obj) => (obj.collide = !allOn)))
    );
  }

  if (kind !== "room") {
    const roomCur = unanimous(objs, (o) => o.roomId || "");
    root.appendChild(
      field(
        "Room",
        selectMixed(roomCur, roomItems(), (v) =>
          apply((obj) => {
            obj.roomId = v || null;
            if (obj.kind === "doorway") assignDoorRooms(doc, obj, roomById(doc, obj.roomId));
            if (obj.kind === "switch") snapSwitchToRoom(obj, roomById(doc, obj.roomId));
          })
        )
      )
    );
  }

  if (kind === "doorway") {
    const otherCur = unanimous(objs, (o) => o.otherRoomId || "");
    root.appendChild(
      field(
        "Other room",
        selectMixed(otherCur, roomItems(), (v) =>
          apply((obj) => {
            obj.otherRoomId = v || null;
            snapDoorBetweenRooms(obj, roomById(doc, obj.roomId), roomById(doc, obj.otherRoomId));
          })
        )
      )
    );
    const lockCur = unanimous(objs, (o) => clampDoorLock(o.lockKey));
    root.appendChild(
      field(
        "Lock",
        selectMixed(
          lockCur,
          DOOR_LOCKS.map((t) => ({ value: t, text: DOOR_LOCK_LABELS[t] })),
          (v) => apply((obj) => (obj.lockKey = v))
        )
      )
    );
    if (lockCur !== undefined && doorUsesTag(lockCur)) {
      const tagCur = unanimous(objs, (o) => o.tag || "");
      root.appendChild(
        field(
          "Tag",
          textInputMixed(tagCur, {
            maxLength: MAX_TAG_LEN,
            placeholder: "destination tag",
            onChange: (v) => apply((obj) => (obj.tag = clampTag(v))),
          })
        )
      );
    }
    const typeCur = unanimous(objs, (o) => clampDoorType(o.doorType));
    root.appendChild(
      field(
        "Type",
        selectMixed(
          typeCur,
          DOOR_TYPES.map((t) => ({ value: t, text: t })),
          (v) => apply((obj) => (obj.doorType = v))
        )
      )
    );
    const allHidden = objs.every((o) => !!o.hidden);
    root.appendChild(
      toggleField("Hidden", allHidden, () =>
        apply((obj) => {
          if (allHidden) delete obj.hidden;
          else obj.hidden = true;
        })
      )
    );
    const scaleCur = unanimous(objs, (o) => clampDoorScale(o.doorScale));
    root.appendChild(
      field(
        "Scale",
        selectMixed(
          scaleCur,
          DOOR_SCALES.map((t) => ({ value: String(t), text: DOOR_SCALE_LABELS[t] })),
          (v) =>
            apply((obj) => {
              const floorY = obj.y | 0;
              obj.doorScale = clampDoorScale(v);
              assignDoorRooms(doc, obj, roomById(doc, obj.roomId));
              obj.y = floorY;
            })
        )
      )
    );
  }

  const sizeP = document.createElement("p");
  sizeP.className = "muted";
  const sizeStr = unanimous(objs, (o) => `${o.sx}×${o.sy}×${o.sz}`);
  if (sizeStr === undefined) {
    sizeP.textContent = "Size mixed";
  } else {
    sizeP.textContent = KINDS[kind].fixed ? `Fixed size ${sizeStr}` : `Size ${sizeStr}`;
  }
  root.appendChild(sizeP);

  if (kind === "crate") {
    const allEdges = objs.every((o) => !!o.allEdges);
    root.appendChild(
      toggleField("All edges", allEdges, () =>
        apply((obj) => {
          if (allEdges) delete obj.allEdges;
          else obj.allEdges = true;
        })
      )
    );
  }

  if (kind === "slope") {
    root.appendChild(rotateRow(() => apply((obj) => cycleSlopeOrient(obj))));
    const allBottom = objs.every((o) => !!((o.flags | 0) & SLOPE_FLAG_BOTTOM));
    const allTop = objs.every((o) => !!((o.flags | 0) & SLOPE_FLAG_TOP));
    root.appendChild(
      toggleField("Bottom", allBottom, () =>
        apply((obj) => {
          if (allBottom) obj.flags = (obj.flags | 0) & ~SLOPE_FLAG_BOTTOM;
          else obj.flags = (obj.flags | 0) | SLOPE_FLAG_BOTTOM;
        })
      )
    );
    root.appendChild(
      toggleField("Top", allTop, () =>
        apply((obj) => {
          if (allTop) obj.flags = (obj.flags | 0) & ~SLOPE_FLAG_TOP;
          else obj.flags = (obj.flags | 0) | SLOPE_FLAG_TOP;
        })
      )
    );
  }
}

function renderInspector() {
  const root = document.getElementById("right-editors");
  root.innerHTML = "";
  if (editorMode === "items") {
    const h = document.createElement("h2");
    h.textContent = "Item";
    root.appendChild(h);
    if (!doc.items) doc.items = {};
    if (!doc.items[itemMeshKey]) doc.items[itemMeshKey] = { verts: [], lines: [] };
    const stats = itemMeshStats(doc.items[itemMeshKey]);
    const p = document.createElement("p");
    p.className = stats.over ? "error" : "muted";
    p.textContent = `${stats.nv} verts · ${stats.ne} lines · unique X ${stats.nx}/${ITEM_MAX_UNIQUE} · unique Z ${stats.nz}/${ITEM_MAX_UNIQUE} · ~${stats.bytes} B`;
    root.appendChild(p);
    if (itemMeshKey !== "backpack" && !doc.items[itemMeshKey].verts.length) {
      const f = document.createElement("p");
      f.className = "muted";
      f.textContent = isDoorMeshKey(itemMeshKey)
        ? "Empty — falls back to Tech."
        : "Empty — falls back to backpack.";
      root.appendChild(f);
    }
    const sel = itemView.selection();
    const row = document.createElement("div");
    row.className = "btn-row";
    const addV = document.createElement("button");
    addV.type = "button";
    addV.textContent = "Add Vert";
    addV.title = "V";
    addV.addEventListener("click", () => itemView.addVertAtOrigin());
    const addL = document.createElement("button");
    addL.type = "button";
    addL.textContent = "Add Line";
    addL.title = "L";
    addL.disabled = sel.verts.length !== 2;
    addL.addEventListener("click", () => itemView.addLineFromSelection());
    const copy = document.createElement("button");
    copy.type = "button";
    copy.textContent = "Copy";
    copy.title = "Ctrl+C — verts plus connected edges";
    copy.disabled = !sel.verts.length && !sel.lines.length;
    copy.addEventListener("click", () => itemView.copySelection());
    const paste = document.createElement("button");
    paste.type = "button";
    paste.textContent = "Paste";
    paste.title = "Ctrl+V — skipped if it would exceed counts";
    paste.disabled = !itemView.hasClipboard();
    paste.addEventListener("click", () => itemView.pasteSelection());
    const del = document.createElement("button");
    del.type = "button";
    del.className = "danger";
    del.textContent = "Delete";
    del.disabled = !sel.verts.length && !sel.lines.length;
    del.addEventListener("click", () => itemView.deleteSelection());
    row.append(addV, addL, copy, paste, del);
    root.appendChild(row);
    const hint = document.createElement("p");
    hint.className = "muted";
    hint.textContent = "Grid −4…4 · origin at 0,0,0 · Add Vert places at origin.";
    root.appendChild(hint);
    return;
  }
  if (editorMode === "weapons") {
    renderWeaponInspector(root);
    return;
  }
  if (editorMode === "layout") {
    const objs = selectedLayoutObjects();
    const h = document.createElement("h2");
    const kind = objs.length ? unanimous(objs, (o) => o.kind) : undefined;
    if (objs.length > 1 && kind === undefined) {
      h.textContent = "Inspector";
      root.appendChild(h);
      appendMixedKindStub(root, objs);
      return;
    }
    if (!objs.length) {
      h.textContent = "Inspector";
      root.appendChild(h);
      const map = activeMap(doc);
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = `Map ${doc.activeLevel}. Select an object or drag one from the palette.`;
      root.appendChild(p);
      const nameInp = document.createElement("input");
      nameInp.type = "text";
      nameInp.maxLength = MAX_NAME_LEN;
      nameInp.value = map.name || "";
      nameInp.placeholder = "Display name";
      nameInp.addEventListener("change", () => {
        pushUndo();
        map.name = clampName(nameInp.value);
        markDirty();
        refreshAll();
      });
      root.appendChild(field("Name", nameInp));
      for (const row of mapKindStatRows(mapStats(doc))) {
        const line = document.createElement("div");
        line.className = "field level-stat";
        const label = document.createElement("span");
        label.textContent = row.label;
        const val = document.createElement("span");
        val.textContent = String(row.n);
        line.append(label, val);
        root.appendChild(line);
      }
      return;
    }
    h.textContent = layoutInspectorTitle(objs);
    root.appendChild(h);
    renderLayoutObjectFields(root, objs);
    return;
  }

  const e = activeEnemy();
  const h = document.createElement("h2");
  h.textContent = e.name;
  root.appendChild(h);

  const hpInp = document.createElement("input");
  hpInp.type = "number";
  hpInp.min = "1";
  hpInp.max = "255";
  hpInp.step = "1";
  hpInp.value = String(clampEnemyHp(e.hp, e.name));
  hpInp.title = "Hit points loaded for this type";
  hpInp.addEventListener("change", () => {
    pushUndo();
    e.hp = clampEnemyHp(hpInp.value, e.name);
    hpInp.value = String(e.hp);
    markDirty();
    buildPalette();
    refreshAll();
  });
  const painInp = document.createElement("input");
  painInp.type = "number";
  painInp.min = "0";
  painInp.max = "255";
  painInp.step = "1";
  painInp.value = String(clampEnemyPainChance(e.painChance, e.name));
  painInp.title = "Flinch when the roll is below this";
  painInp.addEventListener("change", () => {
    pushUndo();
    e.painChance = clampEnemyPainChance(painInp.value, e.name);
    painInp.value = String(e.painChance);
    markDirty();
    refreshAll();
  });
  const statRow = document.createElement("div");
  statRow.className = "field-pair";
  statRow.append(field("Hit points", hpInp), field("Pain chance", painInp));
  root.appendChild(statRow);

  const timeline = getTimeline(e);
  const spriteEnemy = enemyHasSprites(e);
  const hasStick = !!stickClipFor(e, activeTimelineClip());
  if (timeline.length) {
    if (clipIndex >= timeline.length) clipIndex = 0;
    const clip = activeTimelineClip() || timeline[0];
    frameLocal = Math.max(0, Math.min(frameLocal, clip.len - 1));
  }

  const listLbl = document.createElement("h2");
  listLbl.textContent = "CLIPS";
  root.appendChild(listLbl);
  if (timeline.length) {
    const ul = document.createElement("ul");
    ul.className = "export-clip-list";
    timeline.forEach((c, i) => {
      const li = document.createElement("li");
      const box = document.createElement("input");
      box.type = "checkbox";
      box.checked = clipIsExported(e, c.name);
      box.title = "Export this clip";
      box.addEventListener("change", () => {
        pushUndo();
        setClipExported(e, c.name, box.checked);
        markDirty();
        refreshAll();
      });
      const nameBtn = document.createElement("button");
      nameBtn.type = "button";
      nameBtn.className = "frame-name" + (i === clipIndex ? " current" : "");
      nameBtn.textContent = c.name;
      nameBtn.addEventListener("click", () => {
        clipIndex = i;
        frameLocal = 0;
        applyFrameLocal();
        markUi();
        refreshAll();
      });
      const len = document.createElement("span");
      len.className = "export-clip-len";
      len.textContent = String(c.len);
      li.append(box, nameBtn, len);
      ul.appendChild(li);
    });
    root.appendChild(ul);
  }
  const packed = packedPoseBytes(e);
  const mem = document.createElement("p");
  mem.className = "muted anim-mem";
  mem.classList.toggle("error", packed.bytes > ENEMY_POSE_MAX);
  mem.title = "Packed pose PRG: 2 + logical map + stored gx/gy/gz. Clip tables are in GAME.";
  mem.textContent = formatPackedPoseMem(packed);
  root.appendChild(mem);

  if (timeline.length) {
    const clip = activeTimelineClip() || timeline[0];

    const transport = document.createElement("div");
    transport.className = "anim-transport";
    const slider = document.createElement("input");
    slider.id = "anim-frame-slider";
    slider.type = "range";
    slider.min = "0";
    slider.max = String(Math.max(0, clip.len - 1));
    slider.value = String(frameLocal);
    slider.addEventListener("input", () => {
      frameLocal = Number(slider.value) | 0;
      applyFrameLocal();
      markUi();
      syncPlayUi();
    });
    transport.appendChild(slider);

    const playRow = document.createElement("div");
    playRow.className = "btn-row anim-transport-btns";
    const playBtn = document.createElement("button");
    playBtn.id = "btn-anim-play";
    playBtn.type = "button";
    playBtn.textContent = animPlaying ? "Pause" : "Play";
    if (animPlaying) playBtn.className = "active";
    playBtn.addEventListener("click", toggleAnimPlay);
    const loopBtn = document.createElement("button");
    loopBtn.id = "btn-anim-loop";
    loopBtn.type = "button";
    loopBtn.textContent = "Loop";
    if (animLoop) loopBtn.className = "active";
    loopBtn.addEventListener("click", () => {
      animLoop = !animLoop;
      updateLoopButton();
    });
    const frameNum = document.createElement("span");
    frameNum.id = "anim-frame-num";
    frameNum.className = "anim-frame-num";
    frameNum.textContent = String(frameLocal);
    playRow.append(playBtn, loopBtn, frameNum);
    if (spriteEnemy) {
      const spriteSel = document.createElement("select");
      spriteSel.title = "Backing sprite";
      const choices = spriteChoices(e);
      const current = frameSpriteLetter(e) || choices[0] || "A";
      if (!choices.includes(current)) choices.unshift(current);
      for (const letter of choices) {
        const opt = document.createElement("option");
        opt.value = letter;
        opt.textContent = letter;
        if (letter === current) opt.selected = true;
        spriteSel.appendChild(opt);
      }
      spriteSel.addEventListener("change", () => setFrameSprite(e, spriteSel.value));
      playRow.append(spriteSel);
    }
    transport.appendChild(playRow);
    if (spriteEnemy) {
      const editRow = document.createElement("div");
      editRow.className = "btn-row anim-transport-btns";
      const addBtn = document.createElement("button");
      addBtn.type = "button";
      addBtn.textContent = "Add";
      addBtn.addEventListener("click", () => addSpriteFrame(e));
      const remBtn = document.createElement("button");
      remBtn.type = "button";
      remBtn.textContent = "Remove";
      remBtn.addEventListener("click", () => removeSpriteFrame(e));
      const copyBtn = document.createElement("button");
      copyBtn.type = "button";
      copyBtn.textContent = "Copy";
      copyBtn.addEventListener("click", () => copyFramePose(e));
      const pasteBtn = document.createElement("button");
      pasteBtn.type = "button";
      pasteBtn.textContent = "Paste";
      pasteBtn.addEventListener("click", () => pasteFramePose(e));
      const avgBtn = document.createElement("button");
      avgBtn.type = "button";
      avgBtn.textContent = "Average";
      avgBtn.title = "Write the midpoint of the frames on either side into this frame";
      avgBtn.addEventListener("click", () => averageNeighborFrames(e));
      editRow.append(addBtn, remBtn, copyBtn, pasteBtn, avgBtn);
      transport.appendChild(editRow);
    }
    root.appendChild(transport);
    renderClipSoundFields(root, e, clip);
  }

  const counts = document.createElement("p");
  counts.className = "muted";
  const clip = activeTimelineClip() || (e.clips?.length ? clipForFrame(e.clips, frameIndex) : null);
  const stick = stickClipFor(e, clip);
  const stickFrame = stick ? stick.start + frameLocal : 0;
  const height = frameHeight(e.frames[stickFrame] || e.frames[0]);
  const nvShow = stickCount(e);
  const weapon = clampWeaponVert(e.weaponVert ?? WEAPON_VERT, nvShow);
  counts.textContent = `${nvShow} verts · ${e.lines.length} lines · height ${height} · weapon ${weapon}`;
  root.appendChild(counts);

  if (hasStick && selectedVerts.length === 1) {
    const vi = selectedVerts[0];
    const v = e.frames[stickFrame][vi];
    const clamp = clampVertFor(e);
    const fine = enemyHasSprites(e);
    const lim = fine ? VERT_MAX / 4 : vertLimitFor(e);
    const lo = fine ? VERT_MIN / 4 : e.customSkeleton ? -lim : -lim - 1;
    const setC = (k, val) => {
      pushUndo();
      v[k] = clamp(val);
      markDirty();
      refreshAll();
    };
    const name = !e.customSkeleton && JOINT_NAMES[vi] ? ` ${JOINT_NAMES[vi]}` : "";
    const xyz = vec3Field(`Vertex ${vi}${name}`, [
      { axis: "x", value: v.x, onChange: (n) => setC("x", n), min: lo, max: lim, step: enemyHasSprites(e) ? 0.25 : undefined },
      { axis: "y", value: v.y, onChange: (n) => setC("y", n), min: lo, max: lim, step: enemyHasSprites(e) ? 0.25 : undefined },
      { axis: "z", value: v.z, onChange: (n) => setC("z", n), min: lo, max: lim, step: enemyHasSprites(e) ? 0.25 : undefined },
    ]);
    xyz.classList.add("vert-xyz");
    root.appendChild(xyz);
    const wbtn = document.createElement("button");
    wbtn.type = "button";
    wbtn.textContent = "Weapon tip";
    wbtn.title = "Muzzle sprite tracks this vertex";
    wbtn.classList.toggle("active", weapon === vi);
    wbtn.addEventListener("click", () => {
      if ((e.weaponVert | 0) === vi) return;
      pushUndo();
      e.weaponVert = vi;
      markDirty();
      refreshAll();
    });
    root.appendChild(wbtn);
  }

  if (!enemyHasSprites(e)) renderDoomSource(root, e);
}

function poseVertCount(e) {
  let n = 0;
  const frames = e?.frames;
  if (!Array.isArray(frames)) return 0;
  for (const fr of frames) {
    if (Array.isArray(fr) && fr.length > n) n = fr.length;
  }
  return n;
}

function spriteChoices(e) {
  const prefix = DOOM_SPRITE_PREFIX[e?.name];
  const fromWad = spriteLetters(doomSprites, prefix);
  if (fromWad.length) return fromWad;
  const set = [];
  for (const c of e?.clips || []) {
    for (const s of c.sprites || []) if (!set.includes(s)) set.push(s);
  }
  set.sort();
  return set.length ? set : ["A"];
}

function frameSpriteLetter(e) {
  const clip = clipForFrame(e?.clips, frameIndex);
  if (!clip?.sprites) return null;
  return clip.sprites[frameIndex - clip.start] || null;
}

function currentSpriteClip(e) {
  const clip = clipForFrame(e?.clips, frameIndex);
  if (!clip?.sprites) return null;
  return { clip, local: frameIndex - clip.start };
}

function addSpriteFrame(e) {
  const hit = currentSpriteClip(e);
  if (!hit || !e.frames?.[frameIndex]) return;
  pushUndo();
  const pose = e.frames[frameIndex].map((v) => ({ x: v.x, y: v.y, z: v.z }));
  const letter = hit.clip.sprites[hit.local] || "A";
  e.frames.splice(frameIndex + 1, 0, pose);
  hit.clip.sprites.splice(hit.local + 1, 0, letter);
  hit.clip.len = (hit.clip.len | 0) + 1;
  for (const c of e.clips) if ((c.start | 0) > (hit.clip.start | 0)) c.start = (c.start | 0) + 1;
  frameLocal = hit.local + 1;
  applyFrameLocal();
  markDirty();
  refreshAll();
}

function removeSpriteFrame(e) {
  const hit = currentSpriteClip(e);
  if (!hit || (hit.clip.len | 0) <= 1) return;
  pushUndo();
  e.frames.splice(frameIndex, 1);
  hit.clip.sprites.splice(hit.local, 1);
  hit.clip.len = (hit.clip.len | 0) - 1;
  for (const c of e.clips) if ((c.start | 0) > (hit.clip.start | 0)) c.start = (c.start | 0) - 1;
  if (frameLocal >= hit.clip.len) frameLocal = hit.clip.len - 1;
  applyFrameLocal();
  markDirty();
  refreshAll();
}

function copyFramePose(e) {
  const fr = e?.frames?.[frameIndex];
  if (!fr) return;
  framePoseClip = fr.map((v) => ({ x: v.x, y: v.y, z: v.z }));
  setStatus(`Copied frame ${frameLocal}`);
}

function pasteFramePose(e) {
  const fr = e?.frames?.[frameIndex];
  if (!fr || !framePoseClip) {
    setStatus("Nothing to paste", true);
    return;
  }
  pushUndo();
  const n = Math.min(fr.length, framePoseClip.length);
  for (let i = 0; i < n; i++) {
    fr[i].x = framePoseClip[i].x;
    fr[i].y = framePoseClip[i].y;
    fr[i].z = framePoseClip[i].z;
  }
  markDirty();
  refreshAll();
}

function setFrameSprite(e, letter) {
  const hit = currentSpriteClip(e);
  if (!hit) return;
  pushUndo();
  hit.clip.sprites[hit.local] = String(letter || "A").slice(0, 1);
  markDirty();
  refreshAll();
}

function averageNeighborFrames(e) {
  const hit = currentSpriteClip(e);
  const len = hit?.clip.len | 0;
  if (!hit || len < 1) return;
  const start = hit.clip.start | 0;
  const prev = e.frames[start + ((hit.local - 1 + len) % len)];
  const next = e.frames[start + ((hit.local + 1) % len)];
  const cur = e.frames[frameIndex];
  if (!prev || !next || !cur) return;
  pushUndo();
  const n = Math.min(cur.length, prev.length, next.length);
  for (let i = 0; i < n; i++) {
    const clamp = clampVertFor(e);
    cur[i].x = clamp((prev[i].x + next[i].x) / 2);
    cur[i].y = clamp((prev[i].y + next[i].y) / 2);
    cur[i].z = clamp((prev[i].z + next[i].z) / 2);
  }
  markDirty();
  refreshAll();
}

function padSpriteJoints(e) {
  if (!e.mdlRig) e.mdlRig = { jointVerts: [] };
  if (!Array.isArray(e.mdlRig.jointVerts)) e.mdlRig.jointVerts = [];
  const nv = e.frames[0]?.length || 0;
  while (e.mdlRig.jointVerts.length < nv) e.mdlRig.jointVerts.push([]);
  e.verts = nv;
}

function addSpriteVert(e) {
  const nv = stickCount(e);
  if (nv >= SPRITE_MAX_VERTS) {
    setStatus(`Vertex cap (${SPRITE_MAX_VERTS})`, true);
    return;
  }
  pushUndo();
  for (const fr of e.frames) fr.push({ x: 0, y: 0, z: 0 });
  padSpriteJoints(e);
  selectedVerts = [nv];
  selectedLines = [];
  markDirty();
  refreshAll();
}

function copySpriteSelection() {
  const e = activeEnemy();
  const nv = stickCount(e);
  const idxs = selectedVerts.filter((i) => i >= 0 && i < nv);
  if (!idxs.length) {
    setStatus("Nothing selected", true);
    return;
  }
  const map = new Map(idxs.map((i, n) => [i, n]));
  const fr = e.frames[frameIndex];
  const verts = idxs.map((i) => ({ x: fr[i].x, y: fr[i].y, z: fr[i].z }));
  const lines = [];
  for (const [a, b] of e.lines) {
    if (map.has(a) && map.has(b)) lines.push([map.get(a), map.get(b)]);
  }
  spriteSelClip = { verts, lines };
  setStatus(`Copied ${verts.length} vert${verts.length === 1 ? "" : "s"}`);
}

function pasteSpriteSelection() {
  const e = activeEnemy();
  if (!spriteSelClip?.verts.length) {
    setStatus("Nothing to paste", true);
    return;
  }
  const nv = stickCount(e);
  if (nv + spriteSelClip.verts.length > SPRITE_MAX_VERTS) {
    setStatus(`Vertex cap (${SPRITE_MAX_VERTS})`, true);
    return;
  }
  if (e.lines.length + spriteSelClip.lines.length > SPRITE_MAX_LINES) {
    setStatus(`Line cap (${SPRITE_MAX_LINES})`, true);
    return;
  }
  pushUndo();
  for (const fr of e.frames) {
    for (const v of spriteSelClip.verts) fr.push({ x: v.x + 2, y: v.y, z: v.z });
  }
  for (const [a, b] of spriteSelClip.lines) e.lines.push([nv + a, nv + b]);
  padSpriteJoints(e);
  selectedVerts = spriteSelClip.verts.map((_, i) => nv + i);
  selectedLines = [];
  markDirty();
  refreshAll();
}

function stickCount(e) {
  if (enemyHasSprites(e)) return poseVertCount(e) || (e?.verts | 0);
  if (!e?.customSkeleton) return 13;
  const joints = e.mdlRig?.jointVerts;
  if (Array.isArray(joints)) return joints.length;
  return poseVertCount(e);
}

function jointLabel(e, i) {
  if (e?.customSkeleton) return String(i);
  return JOINT_NAMES[i] || String(i);
}

function cloneGraph(e) {
  return {
    verts: stickCount(e),
    lines: e.lines.map((p) => [p[0], p[1]]),
    frames: JSON.parse(JSON.stringify(e.frames)),
    mdlRig: JSON.parse(JSON.stringify(e.mdlRig)),
    clips: JSON.parse(JSON.stringify(e.clips || [])),
    exportClips: e.exportClips ? [...e.exportClips] : undefined,
  };
}

function applyGraph(e, g) {
  e.verts = g.verts;
  e.lines = g.lines.map((p) => [p[0], p[1]]);
  e.frames = JSON.parse(JSON.stringify(g.frames));
  e.mdlRig = JSON.parse(JSON.stringify(g.mdlRig));
  if (g.clips) e.clips = JSON.parse(JSON.stringify(g.clips));
  if (g.exportClips) e.exportClips = [...g.exportClips];
}

function setCustomSkeleton(e, on) {
  if (!!e.customSkeleton === !!on) return;
  pushUndo();
  bindJoint = -1;
  pendingBind = null;
  selectedVerts = [];
  selectedLines = [];
  if (on) {
    e.stockGraph = cloneGraph(e);
    if (e.customGraph) applyGraph(e, e.customGraph);
    else {
      e.verts = 0;
      e.lines = [];
      e.frames = [[]];
      e.mdlRig = { jointVerts: [] };
    }
    e.customSkeleton = true;
    e.customGraph = null;
  } else {
    e.customGraph = cloneGraph(e);
    if (e.stockGraph) applyGraph(e, e.stockGraph);
    e.customSkeleton = false;
    e.stockGraph = null;
  }
  markDirty();
  retargetMdlFrames();
  updateAnimHint();
}

function animHintText() {
  const e = activeEnemy();
  if (enemyHasSprites(e)) {
    const wire = stickWireOn ? "Space hide wireframe" : "Space show wireframe";
    return `Left/front drag the on-screen axes · ${wire} · perspective orbits · V add vert · L add line · Del delete · Ctrl+C/V selection · Add/Remove frames · [ ] frames`;
  }
  if (e?.customSkeleton && pendingBind) {
    return "Box-select mesh verts · Shift add · V done · Esc cancels · F focus · RMB orbit";
  }
  if (bindJoint >= 0) {
    return `Box-select mesh verts for ${jointLabel(e, bindJoint)} · Shift add · Esc stops bind · F focus · RMB orbit`;
  }
  if (e?.customSkeleton) {
    return "LMB select verts or a line · Shift add · V bind · L add line · M merge · Del delete · [ ] frames · F focus · MMB pan · Alt+LMB / RMB orbit · Alt+RMB zoom";
  }
  return "LMB box-select verts · click-drag unselected on camera plane · gizmo moves selection · X/Y/Z nudge · [ ] frames · F focus · MMB pan · Alt+LMB / RMB orbit · Alt+RMB zoom";
}

function updateAnimHint() {
  if (editorMode !== "anim") return;
  const hint = document.getElementById("hint");
  if (!hint) return;
  hint.textContent = animHintText();
}

function stageMeshBind(indices, additive) {
  if (!pendingBind) return;
  const mdl = activeMdl();
  const max = mdl ? mdl.numVerts : Infinity;
  const set = new Set(additive ? pendingBind : []);
  for (const i of indices) {
    const n = i | 0;
    if (n >= 0 && n < max) set.add(n);
  }
  pendingBind = [...set].sort((a, b) => a - b);
  animView.draw();
  refreshPanels();
}

function averageMeshBind(e, indices) {
  const mdl = sharewareModels[e.name];
  if (!mdl || !indices.length) return { x: 0, y: 0, z: 0 };
  const timeline = getTimeline(e);
  const clip = timeline[clipIndex] || timeline[0];
  let mdlFi = 0;
  if (clip) {
    const local = Math.max(0, Math.min(frameLocal, (clip.len | 0) - 1));
    mdlFi = clip.mdlFrames?.[local]?.index ?? 0;
  }
  const avg = averageJointPositions(mdlEditorVerts(mdl, mdlFi, DEFAULT_MDL_SCALE), [indices])[0];
  if (!avg) return { x: 0, y: 0, z: 0 };
  const clamp = clampVertFor(e);
  return {
    x: clamp(Math.round(avg.x)),
    y: clamp(Math.round(avg.y)),
    z: clamp(Math.round(avg.z)),
  };
}

function commitCustomVert(e) {
  const picked = pendingBind ? [...pendingBind] : [];
  pendingBind = null;
  if (!picked.length) {
    updateAnimHint();
    refreshPanels();
    animView.draw();
    return;
  }
  ensureEnemyRig(e);
  const nv = stickCount(e);
  if (nv >= SKEL_MAX_VERTS) {
    setStatus(`Vertex cap (${SKEL_MAX_VERTS})`, true);
    updateAnimHint();
    refreshPanels();
    animView.draw();
    return;
  }
  pushUndo();
  const pos = averageMeshBind(e, picked);
  for (const fr of e.frames) fr.push({ ...pos });
  e.mdlRig.jointVerts.push(picked);
  e.verts = nv + 1;
  selectedVerts = [nv];
  selectedLines = [];
  updateAnimHint();
  markDirty();
  persistMdlRigBackup();
  retargetMdlFrames({ status: true });
  refreshPanels();
  animView.draw();
}

function toggleCustomBind(e) {
  if (pendingBind) {
    commitCustomVert(e);
    return;
  }
  pendingBind = [];
  bindJoint = -1;
  selectedVerts = [];
  selectedLines = [];
  setOverlayOn(true);
  updateAnimHint();
  refreshPanels();
  animView.draw();
}

function addCustomLine(e) {
  if (selectedVerts.length !== 2) {
    setStatus("Select two vertices", true);
    return;
  }
  const cap = enemyHasSprites(e) ? SPRITE_MAX_LINES : SKEL_MAX_LINES;
  if (e.lines.length >= cap) {
    setStatus(`Line cap (${cap})`, true);
    return;
  }
  let a = selectedVerts[0] | 0;
  let b = selectedVerts[1] | 0;
  if (a === b) return;
  if (a > b) {
    const t = a;
    a = b;
    b = t;
  }
  if (e.lines.some(([x, y]) => x === a && y === b)) {
    setStatus("Line already exists", true);
    return;
  }
  pushUndo();
  e.lines.push([a, b]);
  markDirty();
  refreshPanels();
  animView.draw();
}

function mergeCustomVerts(e) {
  if (selectedVerts.length !== 2) {
    setStatus("Select two vertices", true);
    return;
  }
  ensureEnemyRig(e);
  const keep = selectedVerts[0] | 0;
  const drop = selectedVerts[1] | 0;
  const nv = stickCount(e);
  if (keep === drop || keep < 0 || drop < 0 || keep >= nv || drop >= nv) return;
  pushUndo();
  const joints = e.mdlRig.jointVerts;
  joints[keep] = [...new Set([...(joints[keep] || []), ...(joints[drop] || [])])].sort((a, b) => a - b);
  const surv = keep > drop ? keep - 1 : keep;
  const remap = (i) => (i === drop ? surv : i > drop ? i - 1 : i);
  for (const fr of e.frames) fr.splice(drop, 1);
  joints.splice(drop, 1);
  const seen = new Set();
  const lines = [];
  for (const [a, b] of e.lines) {
    let x = remap(a);
    let y = remap(b);
    if (x === y) continue;
    if (x > y) {
      const t = x;
      x = y;
      y = t;
    }
    const key = x + "," + y;
    if (seen.has(key)) continue;
    seen.add(key);
    lines.push([x, y]);
  }
  e.lines = lines;
  e.verts = nv - 1;
  e.weaponVert = remap(e.weaponVert ?? WEAPON_VERT);
  if (bindJoint === drop) bindJoint = surv;
  else if (bindJoint > drop) bindJoint--;
  selectedVerts = [surv];
  selectedLines = [];
  markDirty();
  persistMdlRigBackup();
  retargetMdlFrames({ status: true });
  refreshPanels();
  animView.draw();
}

function deleteCustomVerts(e) {
  ensureEnemyRig(e);
  const nv = stickCount(e);
  const drop = new Set(selectedVerts.filter((i) => i >= 0 && i < nv));
  if (!drop.size) return;
  pushUndo();
  const map = [];
  let n = 0;
  for (let i = 0; i < nv; i++) map[i] = drop.has(i) ? -1 : n++;
  for (const fr of e.frames) {
    const next = fr.filter((_, i) => !drop.has(i));
    fr.length = 0;
    fr.push(...next);
  }
  e.mdlRig.jointVerts = e.mdlRig.jointVerts.filter((_, i) => !drop.has(i));
  e.lines = e.lines
    .map(([a, b]) => [map[a], map[b]])
    .filter(([a, b]) => a >= 0 && b >= 0 && a !== b)
    .map(([a, b]) => (a < b ? [a, b] : [b, a]));
  e.verts = n;
  const mappedWeapon = map[e.weaponVert ?? WEAPON_VERT];
  e.weaponVert = mappedWeapon == null || mappedWeapon < 0 ? 0 : mappedWeapon;
  if (bindJoint >= 0) bindJoint = map[bindJoint] ?? -1;
  selectedVerts = [];
  selectedLines = [];
  markDirty();
  persistMdlRigBackup();
  retargetMdlFrames({ status: true });
  refreshPanels();
  animView.draw();
}

function deleteCustomSelection(e) {
  const lines = [...selectedLines].filter((i) => i >= 0 && i < e.lines.length).sort((a, b) => b - a);
  if (lines.length) {
    pushUndo();
    for (const i of lines) e.lines.splice(i, 1);
    selectedLines = [];
    markDirty();
    refreshPanels();
    animView.draw();
    return;
  }
  deleteCustomVerts(e);
}

function ensureEnemyRig(e) {
  if (e?.customSkeleton) {
    if (!e.mdlRig || !Array.isArray(e.mdlRig.jointVerts)) {
      e.mdlRig = { jointVerts: [] };
    }
    const joints = e.mdlRig.jointVerts;
    let donor = null;
    if (Array.isArray(e.frames)) {
      for (const fr of e.frames) {
        if (Array.isArray(fr) && (!donor || fr.length > donor.length)) donor = fr;
      }
      for (const fr of e.frames) {
        if (!Array.isArray(fr)) continue;
        while (fr.length < joints.length) {
          const src = donor && donor.length > fr.length ? donor[fr.length] : null;
          fr.push(src ? { x: src.x, y: src.y, z: src.z } : { x: 0, y: 0, z: 0 });
        }
      }
    }
    e.verts = joints.length;
    return e.mdlRig;
  }
  const n = stickCount(e);
  if (!e.mdlRig || !Array.isArray(e.mdlRig.jointVerts)) {
    e.mdlRig = { jointVerts: Array.from({ length: n }, () => []) };
    return e.mdlRig;
  }
  const joints = e.mdlRig.jointVerts;
  if (joints.length === n) return e.mdlRig;
  e.mdlRig = emptyMdlRig();
  return e.mdlRig;
}

function activeMdl() {
  return sharewareModels[activeEnemy()?.name] || null;
}

function assignMeshVerts(indices, additive) {
  if (bindJoint < 0) return;
  const e = activeEnemy();
  if (!e) return;
  const rig = ensureEnemyRig(e);
  const mdl = activeMdl();
  const max = mdl ? mdl.numVerts : Infinity;
  pushUndo();
  const set = new Set(additive ? rig.jointVerts[bindJoint] : []);
  for (const i of indices) {
    const n = i | 0;
    if (n >= 0 && n < max) set.add(n);
  }
  rig.jointVerts[bindJoint] = [...set].sort((a, b) => a - b);
  markDirty();
  persistMdlRigBackup();
  retargetMdlFrames({ status: true });
  refreshPanels();
  animView.draw();
}

async function loadSharewareFromHandle(handle) {
  try {
    const buffers = await loadSharewarePakBuffers(handle);
    if (!buffers.length) {
      sharewareModels = {};
      sharewareMissing = ENEMY_TYPES.map((t) => t.name);
      sharewareWeapons = {};
      sharewareWeaponMissing = [...WEAPON_KEYS];
      setStatus("No pak0.pak / pak1.pak in that folder", true);
      refreshPanels();
      return;
    }
    const lumps = parsePakBuffers(buffers);
    const { models, missing } = loadEnemyMdls(lumps);
    sharewareModels = models;
    sharewareMissing = missing;
    const weapons = loadWeaponMdls(lumps);
    sharewareWeapons = weapons.models;
    sharewareWeaponMissing = weapons.missing;
    clampWeaponPreviewFrame();
    const n = Object.keys(models).length;
    const wn = Object.keys(sharewareWeapons).length;
    const miss = missing.length ? ` · missing ${missing.join(", ")}` : "";
    const wmiss = weapons.missing.length ? ` · weapons missing ${weapons.missing.join(", ")}` : "";
    setStatus(
      `Loaded ${n} enemy / ${wn} weapon model${wn === 1 ? "" : "s"} from ${sharewareFolderName()}${miss}${wmiss}`
    );
  } catch (err) {
    sharewareModels = {};
    sharewareMissing = ENEMY_TYPES.map((t) => t.name);
    sharewareWeapons = {};
    sharewareWeaponMissing = [...WEAPON_KEYS];
    setStatus(String(err.message || err), true);
  }
  if (restoreMdlRigBackup()) markDirty();
  deriveAllEnemyFrames();
  refreshPanels();
  if (editorMode === "anim") {
    animView.draw();
    refreshPanels();
  }
  if (editorMode === "weapons") weaponView.draw();
}

function adoptDoomSprites(buf) {
  if (!buf) return false;
  doomSprites = loadDoomSprites(buf);
  if (editorMode === "anim") {
    stickLeft.draw();
    stickFront.draw();
  }
  return true;
}

async function loadProjectSprites() {
  try {
    const buf = await readProjectBytes("ref/DOOM.WAD");
    if (buf) adoptDoomSprites(buf);
  } catch (err) {
    console.warn(err);
  }
}

async function openSharewareFolder() {
  let handle;
  try {
    handle = await pickSharewareDirectory();
  } catch (err) {
    setStatus(String(err.message || err), true);
    return;
  }
  if (!handle) {
    setStatus("Open cancelled", true);
    return;
  }
  try {
    await loadSharewareFromHandle(handle);
    await loadProjectSprites();
  } catch (err) {
    setStatus(String(err.message || err), true);
  }
}

function rigBindingComplete(rig) {
  return rig.jointVerts.every((list) => list.length > 0);
}

/** Fill in-memory stick poses from the binding. Does not touch the saved document. */
function deriveEnemyFrames(e) {
  if (!e || enemyHasSprites(e)) return false;
  const mdl = sharewareModels[e.name];
  if (!mdl) return false;
  const rig = ensureEnemyRig(e);
  if (!rigBindingComplete(rig)) return false;
  const names = exportClipNames(e, mdl);
  if (!names.length) return false;
  const rest = e.frames?.[0] || dummyFrameFor(e.name);
  const { frames, clips } = buildStickFramesFromMdl(
    mdl,
    rig,
    DEFAULT_MDL_SCALE,
    rest,
    clampVertFor(e),
    names
  );
  if (!frames.length) return false;
  const prevByName = new Map((e.clips || []).map((c) => [c.name, c]));
  e.frames = frames;
  e.clips = clips.map((c) => withClipSound(c, prevByName.get(c.name)));
  e.exportClips = clips.map((c) => c.name);
  return true;
}

function deriveAllEnemyFrames() {
  const active = activeEnemy();
  const keepName = active ? activeTimelineClip()?.name : null;
  const keepLocal = frameLocal;
  for (const e of doc.enemies || []) deriveEnemyFrames(e);
  paintEnemyPaletteIcons();
  if (!active || !keepName) return;
  const timeline = getTimeline(active);
  const idx = timeline.findIndex((c) => c.name === keepName);
  clipIndex = idx >= 0 ? idx : 0;
  const clip = timeline[clipIndex];
  frameLocal = clip ? Math.max(0, Math.min(keepLocal, (clip.len | 0) - 1)) : 0;
  applyFrameLocal();
}

/** Retarget checked MDL clips onto stick frames when all joints are bound. */
function retargetMdlFrames(options = {}) {
  const { status = false, dirty = true } = options;
  const e = activeEnemy();
  const keepName = e ? activeTimelineClip()?.name : null;
  if (!deriveEnemyFrames(e)) return false;
  frameLocal = 0;
  if (keepName) {
    const timeline = getTimeline(e);
    const idx = timeline.findIndex((c) => c.name === keepName);
    clipIndex = idx >= 0 ? idx : 0;
  } else {
    clipIndex = 0;
  }
  applyFrameLocal();
  if (dirty) markDirty();
  if (status) setStatus(`Retargeted ${e.frames.length} frames`);
  paintEnemyPaletteIcons();
  return true;
}

function renderDoomSource(root, e) {
  const wrap = document.createElement("section");
  wrap.className = "doom-source";
  const h = document.createElement("h2");
  h.textContent = "Doom source";
  wrap.appendChild(h);

  const status = document.createElement("p");
  status.className = "muted";
  const mdl = sharewareModels[e.name];
  const folder = sharewareFolderName();
  const names = mdl ? exportClipNames(e, mdl) : [];
  const selCount = names.length;
  const totalClips = mdl?.clips?.length || 0;
  const selFrames = names.reduce((n, name) => {
    const c = mdl?.clips?.find((cl) => cl.name === name);
    return n + (c?.frames.length || 0);
  }, 0);
  if (mdl) {
    status.textContent = folder
      ? `${folder} · ${mdl.numVerts} mesh verts · ${selCount}/${totalClips} clips · ${selFrames} frames`
      : `${mdl.numVerts} mesh verts · ${selCount}/${totalClips} clips · ${selFrames} frames`;
  } else if (sharewareMissing.includes(e.name)) {
    status.textContent = folder
      ? `${e.name} is not in ${folder}`
      : `${e.name} model not in the opened PAK`;
  } else {
    status.textContent = folder
      ? `Opened ${folder}. Open again if models did not load.`
      : "Open a folder that contains pak0.pak or id1/pak0.pak";
  }
  wrap.appendChild(status);

  const rig = ensureEnemyRig(e);
  const custom = !!e.customSkeleton;
  const count = stickCount(e);

  if (custom) {
    const row = document.createElement("div");
    row.className = "btn-row";
    const bindBtn = document.createElement("button");
    bindBtn.type = "button";
    bindBtn.textContent = pendingBind ? "Done" : "Bind";
    bindBtn.title = "V";
    if (pendingBind) bindBtn.className = "active";
    bindBtn.addEventListener("click", () => toggleCustomBind(e));
    row.append(bindBtn);
    wrap.appendChild(row);
  } else {
  const jointList = document.createElement("ul");
  jointList.className = "joint-list";
  for (let i = 0; i < count; i++) {
    const name = jointLabel(e, i);
    const li = document.createElement("li");
    li.className = "joint-row" + (bindJoint === i ? " active" : "");
    const label = document.createElement("span");
    label.className = "joint-name";
    const n = rig.jointVerts[i]?.length || 0;
    label.classList.toggle("unbound", !n);
    label.textContent = n ? `${name} · ${n}` : name;
    const bindBtn = document.createElement("button");
    bindBtn.type = "button";
    bindBtn.textContent = bindJoint === i ? "Done" : "Bind";
    if (bindJoint === i) bindBtn.className = "active";
    bindBtn.addEventListener("click", () => {
      bindJoint = bindJoint === i ? -1 : i;
      if (bindJoint >= 0) setOverlayOn(true);
      updateAnimHint();
      refreshPanels();
      animView.draw();
    });
    li.append(label, bindBtn);
    jointList.appendChild(li);
  }
  wrap.appendChild(jointList);
  }
  root.appendChild(wrap);
}

function frameHeight(verts) {
  let maxY = -Infinity;
  for (const v of verts) {
    if (v.y > maxY) maxY = v.y;
  }
  return Number.isFinite(maxY) ? maxY : 0;
}

function applyFrameLocal() {
  const e = activeEnemy();
  const stick = stickClipFor(e, activeTimelineClip());
  if (stick) frameIndex = stick.start + frameLocal;
}

function advanceFrame(d) {
  const timeline = getTimeline(activeEnemy());
  if (!timeline.length) return false;
  const clip = timeline[clipIndex] || timeline[0];
  const len = Math.max(1, clip.len);
  frameLocal = (frameLocal + d + len) % len;
  applyFrameLocal();
  return true;
}

function syncPlayUi() {
  const slider = document.getElementById("anim-frame-slider");
  if (slider) slider.value = String(frameLocal);
  const num = document.getElementById("anim-frame-num");
  if (num) num.textContent = String(frameLocal);
  if (editorMode === "anim") animView.draw();
}

function stepFrame(d) {
  if (!advanceFrame(d)) return;
  markUi();
  refreshAll();
}

function stepWeaponFrame(d) {
  const frames = selectedWeaponFrames();
  if (!frames.length) return;
  let i = frames.indexOf(weaponFrame);
  if (i < 0) i = 0;
  weaponFrame = frames[(i + d + frames.length) % frames.length];
  markUi();
  refreshAll();
}

function stopAnimPlay() {
  animPlaying = false;
  if (animPlayTimer) {
    clearInterval(animPlayTimer);
    animPlayTimer = null;
  }
}

function updateLoopButton() {
  const loopBtn = document.getElementById("btn-anim-loop");
  if (!loopBtn) return;
  loopBtn.classList.toggle("active", animLoop);
}

function updatePlayButton() {
  const playBtn = document.getElementById("btn-anim-play");
  if (!playBtn) return;
  playBtn.textContent = animPlaying ? "Pause" : "Play";
  playBtn.classList.toggle("active", animPlaying);
}

function toggleAnimPlay() {
  if (animPlaying) {
    stopAnimPlay();
    updatePlayButton();
    setStatus("Paused");
    return;
  }
  const clip = activeTimelineClip();
  if (!clip) {
    setStatus("No clip to play", true);
    return;
  }
  frameLocal = 0;
  applyFrameLocal();
  syncPlayUi();
  animPlaying = true;
  animPlayTimer = setInterval(tickAnimPlay, ANIM_PLAY_MS);
  updatePlayButton();
  setStatus(`Playing ${clip.name}`);
}

function tickAnimPlay() {
  if (editorMode !== "anim") {
    stopAnimPlay();
    updatePlayButton();
    return;
  }
  const clip = activeTimelineClip();
  if (!clip) {
    stopAnimPlay();
    updatePlayButton();
    return;
  }
  if (frameLocal >= clip.len - 1) {
    if (!animLoop) {
      stopAnimPlay();
      updatePlayButton();
      setStatus("Paused");
      return;
    }
    frameLocal = 0;
  } else {
    frameLocal++;
  }
  applyFrameLocal();
  syncPlayUi();
}

function setOverlayOn(on) {
  overlayOn = !!on;
  if (editorMode === "anim") animView.draw();
  markUi();
}

function setRefSpriteOn(on) {
  refSpriteOn = !!on;
  document.getElementById("btn-mdl-overlay")?.classList.toggle("active", refSpriteOn);
  if (editorMode === "anim") {
    stickLeft.draw();
    stickFront.draw();
  }
  markUi();
}

function setMdlScale(value) {
  mdlScale = clampMdlScale(value);
  const range = document.getElementById("mdl-scale");
  const numInp = document.getElementById("mdl-scale-num");
  const shown = String(mdlScale);
  if (range && range.value !== shown) range.value = shown;
  if (numInp && numInp.value !== shown) numInp.value = shown;
  if (editorMode === "anim") animView.draw();
  markUi();
}

function nudgeVert(axis, delta) {
  const e = activeEnemy();
  if (!e.clips?.length) {
    setStatus("Bind all joints to retarget from MDL first", true);
    return;
  }
  const idxs = selectedVerts.length ? selectedVerts : [];
  if (!idxs.length) {
    setStatus("Select a vertex first", true);
    return;
  }
  pushUndo();
  for (const i of idxs) {
    const v = e.frames[frameIndex][i];
    v[axis] = clampVertFor(e)(v[axis] + delta);
  }
  markDirty();
  refreshAll();
}

function refreshPanels() {
  renderLevelList();
  renderObjectList();
  renderEnemyList();
  renderWeaponList();
  renderItemList();
  renderInspector();
  syncWeaponScaleInputs();
  syncSharewareFolderButtons();
  if (editorMode !== "build") overheadView.draw();
  if (editorMode === "layout") previewView.draw();
  if (editorMode === "layout") layoutView.draw();
  if (editorMode === "anim") animView.draw();
  if (editorMode === "weapons") weaponView.draw();
  if (editorMode === "items") itemView.draw();
}

function refreshAll() {
  updateCenterChrome();
  refreshPanels();
  if (editorMode === "layout") layoutView.draw();
  else if (editorMode === "weapons") weaponView.draw();
  else if (editorMode === "items") itemView.draw();
  else if (editorMode !== "build") animView.draw();
}

document.getElementById("btn-mode-layout").addEventListener("click", () => {
  setMode("layout");
});
document.getElementById("btn-mode-anim").addEventListener("click", () => {
  setMode("anim");
});
document.getElementById("btn-mode-weapons").addEventListener("click", () => {
  setMode("weapons");
});
document.getElementById("btn-mode-items")?.addEventListener("click", () => {
  setMode("items");
});
document.getElementById("btn-mode-build")?.addEventListener("click", () => {
  setMode("build");
});
document.getElementById("btn-mdl-overlay").addEventListener("click", () => {
  setRefSpriteOn(!refSpriteOn);
});
document.getElementById("weapon-scale").addEventListener("input", (e) => {
  doc.weapons.scale = clampWeaponScale(e.target.value);
  syncWeaponScaleInputs();
  if (editorMode === "weapons") weaponView.draw();
});
document.getElementById("weapon-scale").addEventListener("change", (e) => {
  pushUndo();
  doc.weapons.scale = clampWeaponScale(e.target.value);
  syncWeaponScaleInputs();
  markDirty();
  refreshAll();
});
document.getElementById("weapon-scale-num").addEventListener("change", (e) => {
  pushUndo();
  doc.weapons.scale = clampWeaponScale(e.target.value);
  syncWeaponScaleInputs();
  markDirty();
  refreshAll();
});
document.getElementById("btn-weapon-folder")?.addEventListener("click", () => void openSharewareFolder());
document.getElementById("btn-anim-folder")?.addEventListener("click", () => void openSharewareFolder());
document.getElementById("btn-weapon-export")?.addEventListener("click", () => {
  exportWeaponPngs().catch((err) => setStatus(String(err.message || err), true));
});
document.getElementById("btn-draw-all").addEventListener("click", () => {
  setDrawMode(false);
});
document.getElementById("btn-draw-local").addEventListener("click", () => {
  setDrawMode(true);
});
document.getElementById("btn-draw-neighbours")?.addEventListener("click", () => {
  setNeighbourDraw(!neighbourDraw);
});
document.getElementById("btn-draw-rooms-only")?.addEventListener("click", () => {
  setRoomsOnlyDraw(!roomsOnlyDraw);
});
document.getElementById("btn-ortho-top").addEventListener("click", () => setOrthoMode("top"));
document.getElementById("btn-ortho-left").addEventListener("click", () => setOrthoMode("left"));
document.getElementById("btn-ortho-forward").addEventListener("click", () => setOrthoMode("forward"));
document.getElementById("btn-undo").addEventListener("click", undo);
document.getElementById("btn-redo").addEventListener("click", redo);
document.getElementById("btn-save").addEventListener("click", async () => {
  await saveNow("Saved");
});

window.addEventListener("pagehide", () => persistEditorSettings());
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") persistEditorSettings();
});

async function applyLoadedDoc(loaded) {
  const side = await readEnemyFiles();
  if (side?.length) loaded = { ...loaded, enemies: side };
  const sideMaps = await readMapFiles();
  if (sideMaps) loaded = { ...loaded, maps: { ...(loaded.maps || {}), ...sideMaps } };
  doc = normalizeDocument(loaded);
  deriveAllEnemyFrames();
  persistMdlRigBackup();
  const stored = loadEditorSettings(docFileName());
  applyEditorState(stored || loaded.editor || doc.editor);
  if (doc.editor) delete doc.editor;
  editorSettingsReady = true;
  persistEditorSettings();
  clearUndoHistory();
  markClean();
  await loadProjectSprites();
  buildPalette();
  refreshAll();
  setStatus(`Loaded ${docFileName()}`);
}

function showFileAccessGate(storedDir) {
  if (document.querySelector(".file-gate")) return;
  const overlay = document.createElement("div");
  overlay.className = "file-gate";
  overlay.innerHTML = `
    <div class="file-gate-card" role="dialog" aria-modal="true" aria-labelledby="file-gate-title">
      <h2 id="file-gate-title">Open DoomA8 folder</h2>
      <p class="muted">
        ${
          storedDir
            ? `Browser needs permission to read and write <strong>${storedDir.name}</strong>. The map file is editor/${DEFAULT_DOC_PATH}.`
            : `Choose the DoomA8 folder (the one that contains <strong>build-a8.bat</strong>). The map file is editor/${DEFAULT_DOC_PATH}.`
        }
      </p>
      <div class="btn-row">
        <button type="button" class="file-gate-primary" id="file-gate-ok">
          ${storedDir ? `Allow ${storedDir.name}` : "Open DoomA8 folder…"}
        </button>
      </div>
    </div>
  `;
  document.body.appendChild(overlay);
  const ok = overlay.querySelector("#file-gate-ok");
  ok.focus();

  const finish = async (loader) => {
    ok.disabled = true;
    try {
      const loaded = await loader();
      if (!loaded) {
        ok.disabled = false;
        setStatus("Open cancelled", true);
        return;
      }
      overlay.remove();
      await applyLoadedDoc(loaded);
      await restoreSharewareQuietly();
    } catch (err) {
      ok.disabled = false;
      setStatus(String(err.message || err), true);
    }
  };

  ok.addEventListener("click", () => {
    void finish(async () => {
      if (!storedDir) return pickProjectDirectory();
      try {
        return await allowStoredProjectDir(storedDir);
      } catch (err) {
        if (err?.name === "AbortError") return null;
        const msg = String(err?.message || err);
        const wrongFolder = msg.includes("build-a8.bat") || msg.includes("editor/doom64.json");
        if (!wrongFolder) throw err;
        const picked = await pickProjectDirectory();
        if (picked) return picked;
        throw err;
      }
    });
  });
}

document.getElementById("btn-load").addEventListener("click", async () => {
  try {
    const loaded = await loadProjectDoc();
    if (loaded) {
      await applyLoadedDoc(loaded);
      return;
    }
    showFileAccessGate(await getStoredProjectDir());
  } catch (err) {
    setStatus(String(err.message || err), true);
  }
});

window.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
    e.preventDefault();
    void saveNow("Saved");
    return;
  }
  if (e.target.matches("input, select, textarea")) return;
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
    e.preventDefault();
    if (e.shiftKey) redo();
    else undo();
    return;
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "y") {
    e.preventDefault();
    redo();
    return;
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "d" && editorMode === "layout") {
    e.preventDefault();
    duplicateSelected();
    return;
  }
  if (editorMode === "items" && (e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "c") {
    e.preventDefault();
    itemView.copySelection();
    return;
  }
  if (editorMode === "items" && (e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "v") {
    e.preventDefault();
    itemView.pasteSelection();
    return;
  }
  if (editorMode === "anim" && enemyHasSprites(activeEnemy()) && (e.ctrlKey || e.metaKey)) {
    const k = e.key.toLowerCase();
    if (k === "c") {
      e.preventDefault();
      copySpriteSelection();
      return;
    }
    if (k === "v") {
      e.preventDefault();
      pasteSpriteSelection();
      return;
    }
  }
  if (e.key === "Delete" || e.key === "Backspace") {
    if (editorMode === "layout") {
      e.preventDefault();
      deleteSelected();
    }
    if (editorMode === "items") {
      e.preventDefault();
      itemView.deleteSelection();
      return;
    }
    if (editorMode === "anim" && activeEnemy()?.customSkeleton && !pendingBind) {
      e.preventDefault();
      deleteCustomSelection(activeEnemy());
      return;
    }
  }
  if (editorMode === "items" && !e.ctrlKey && !e.metaKey && !e.altKey) {
    const k = e.key.toLowerCase();
    if (k === "v") {
      e.preventDefault();
      itemView.addVertAtOrigin();
      return;
    }
    if (k === "l") {
      e.preventDefault();
      itemView.addLineFromSelection();
      return;
    }
  }
  if (e.key.toLowerCase() === "g" && editorMode === "layout" && !e.ctrlKey && !e.metaKey && !e.altKey) {
    if (selectedIds.length) {
      e.preventDefault();
      dropSelectedToFloor();
      return;
    }
  }
  if (e.key.toLowerCase() === "f" && !e.ctrlKey && !e.metaKey && !e.altKey) {
    if (editorMode === "layout") {
      if (selectedIds.length) {
        e.preventDefault();
        if (layoutView.focusSelection()) setStatus("Focused selection");
      }
      return;
    }
    if (editorMode === "anim") {
      e.preventDefault();
      animView.focusObject();
      setStatus("Focused object");
      return;
    }
    if (editorMode === "items") {
      e.preventDefault();
      itemView.focusObject();
      setStatus("Focused object");
      return;
    }
  }
  if (e.key.toLowerCase() === "r" && editorMode === "layout") {
    const objs = selectedLayoutObjects();
    const kind = objs.length ? unanimous(objs, (o) => o.kind) : undefined;
    if (kind && isFigureObject(objs[0])) {
      e.preventDefault();
      pushUndo();
      for (const obj of objs) {
        obj.rot = cycleEnemyRot(obj.rot ?? 0);
        clampObject(obj);
      }
      markDirty();
      refreshAll();
    }
    if (kind === "slope") {
      e.preventDefault();
      pushUndo();
      for (const obj of objs) {
        cycleSlopeOrient(obj);
        clampObject(obj);
      }
      markDirty();
      refreshAll();
    }
  }
  if (editorMode === "anim") {
    if (e.code === "Space" && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault();
      if (!e.repeat) {
        stickWireOn = !stickWireOn;
        stickLeft.draw();
        stickFront.draw();
        updateAnimHint();
      }
      return;
    }
    if (e.key === "Escape") {
      if (pendingBind || bindJoint >= 0) {
        e.preventDefault();
        pendingBind = null;
        bindJoint = -1;
        updateAnimHint();
        refreshPanels();
        animView.draw();
        return;
      }
    }
    if (!e.ctrlKey && !e.metaKey && !e.altKey && e.key.toLowerCase() === "v") {
      const en = activeEnemy();
      if (enemyHasSprites(en)) {
        e.preventDefault();
        addSpriteVert(en);
        return;
      }
      if (en?.customSkeleton) {
        e.preventDefault();
        toggleCustomBind(en);
        return;
      }
    }
    if (!e.ctrlKey && !e.metaKey && !e.altKey && e.key.toLowerCase() === "l") {
      const en = activeEnemy();
      if (en?.customSkeleton && !pendingBind) {
        e.preventDefault();
        addCustomLine(en);
        return;
      }
    }
    if (!e.ctrlKey && !e.metaKey && !e.altKey && e.key.toLowerCase() === "m") {
      const en = activeEnemy();
      if (en?.customSkeleton && !pendingBind) {
        e.preventDefault();
        mergeCustomVerts(en);
        return;
      }
    }
    if (e.key === "[" || e.key === "," || e.key === "ArrowLeft") {
      e.preventDefault();
      stepFrame(-1);
      return;
    }
    if (e.key === "]" || e.key === "." || e.key === "ArrowRight") {
      e.preventDefault();
      stepFrame(1);
      return;
    }
    const k = e.key.toLowerCase();
    if (k === "x" || k === "y" || k === "z") {
      e.preventDefault();
      nudgeVert(k, e.shiftKey ? -1 : 1);
      return;
    }
  }
  if (editorMode === "weapons") {
    if (e.key === "[" || e.key === "," || e.key === "ArrowLeft") {
      e.preventDefault();
      stepWeaponFrame(-1);
      return;
    }
    if (e.key === "]" || e.key === "." || e.key === "ArrowRight") {
      e.preventDefault();
      stepWeaponFrame(1);
      return;
    }
  }
});

buildPalette();
setMode("layout");
updateUndoButtons();

async function restoreSharewareQuietly() {
  try {
    const dir = await tryRestoreSharewareDir();
    if (dir) {
      await loadSharewareFromHandle(dir);
      return;
    }
    const stored = await getStoredSharewareHandle();
    if (stored && !Object.keys(sharewareModels).length) {
      const name = sharewareFolderName();
      setStatus(
        name
          ? `${name} saved — click Change folder… to reload MDL data`
          : "Click Open shareware folder to load MDL data"
      );
    }
  } catch {
    /* folder optional */
  }
}

async function boot() {
  updateDirtyIndicator();
  refreshAll();
  try {
    const loaded = await tryRestoreProjectDoc();
    if (loaded) {
      await applyLoadedDoc(loaded);
      await restoreSharewareQuietly();
      return;
    }
    const stored = await getStoredProjectDir();
    if (restoreMdlRigBackup()) {
      markDirty();
      refreshAll();
    }
    showFileAccessGate(stored);
    setStatus(
      stored
        ? "Click Allow to open the DoomA8 folder"
        : "Open the DoomA8 folder to edit the project map",
      false
    );
    await restoreSharewareQuietly();
  } catch (err) {
    setStatus(String(err.message || err), true);
  }
}

void boot();

setInterval(() => {
  if (editorMode === "layout") overheadView.draw();
}, 80);
