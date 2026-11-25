// Game Boy Color weapon timing (period, recoil / pump / punch pose tables). Pure data, no DOM.
// Stored in editor/doom64.json ("gbWeapons"); tools/gbc_genwpntab.py writes gbc/build/wpntable.asm from it.
// Times are VBlanks (1 / 59.73 s). The preview mirrors gbc/wpn.asm WpnPose / WpnVBlank.

export const GBW_VBLANK_HZ = 59.7275;
export const GBW_FLASH_TICKS = 7; // gbc/wpn.asm FLASH_TICKS
export const GBW_FLASH_DY = 15; // flash sits this far above the body (gbc/wpn.asm)
export const GBW_VIEW_W = 128;
export const GBW_VIEW_H = 112;
export const GBW_MAX_STEPS = 8;

/**
 * Catalogue in GBC weapon id order (WPN_FIST .. WPN_SAW).
 * tabled: has a pose table (steps + overhang); the anim length is the last step's "until".
 * Others (chaingun, chainsaw) only take period + anim length; their frame logic stays in the code.
 * idle / alt: sprite ids in gbSprites. flash: sprite ids alternated per shot (none for melee).
 */
export const GBW_DEFS = [
  { id: "fist", name: "Fist", tabled: true, idle: "fist_righthand_lines", alt: "fist_lefthand_lines", flash: [], altName: "punch" },
  { id: "shotgun", name: "Shotgun", tabled: true, idle: "shotgun_lines", alt: "shotgun_cock_lines", flash: ["muzzle_flash", "muzzle_flash_b"], altName: "pump" },
  { id: "chaingun", name: "Chaingun", tabled: false, idle: "chaingun_a_lines", alt: "chaingun_b_lines", flash: ["muzzle_flash", "muzzle_flash_b"], altName: "B" },
  { id: "rocket", name: "Rocket launcher", tabled: true, idle: "rocketlauncher_lines", alt: "rocketlauncher_lines", flash: ["muzzle_flash", "muzzle_flash_b"], altName: "alt" },
  { id: "pistol", name: "Pistol", tabled: true, idle: "pistol_lines", alt: "pistol_lines", flash: ["muzzle_flash", "muzzle_flash_b"], altName: "alt" },
  { id: "chainsaw", name: "Chainsaw", tabled: false, idle: "chainsaw_lines", alt: "chainsaw_lines", flash: [], altName: "alt" },
];

/** Defaults = the values in gbc/wpn.asm before the table moved into the editor. */
const DEFAULTS = {
  fist: { period: 48, anim: 22, overhang: 0, steps: [{ until: 22, dy: 0, frame: "alt" }] },
  shotgun: {
    period: 36,
    anim: 34,
    overhang: 10,
    steps: [
      { until: 3, dy: -10, frame: "idle" },
      { until: 9, dy: 14, frame: "idle" },
      { until: 15, dy: 6, frame: "idle" },
      { until: 19, dy: 0, frame: "idle" },
      { until: 21, dy: 0, frame: "alt" },
      { until: 24, dy: 5, frame: "alt" },
      { until: 34, dy: 0, frame: "alt" },
    ],
  },
  chaingun: { period: 6, anim: 6, overhang: 0, steps: [] },
  rocket: {
    period: 60,
    anim: 60,
    overhang: 0,
    steps: [
      { until: 50, dy: 24, frame: "idle" },
      { until: 55, dy: 16, frame: "idle" },
      { until: 60, dy: 8, frame: "idle" },
    ],
  },
  pistol: {
    period: 36,
    anim: 28,
    overhang: 6,
    steps: [
      { until: 18, dy: -4, frame: "idle" },
      { until: 28, dy: -6, frame: "idle" },
    ],
  },
  chainsaw: { period: 6, anim: 6, overhang: 0, steps: [] },
};

export function gbwDef(id) {
  return GBW_DEFS.find((d) => d.id === id) || null;
}

function clampInt(v, min, max, fallback) {
  const n = Math.round(Number(v));
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

/** Default steps are written as (until, dy, frame); the document stores per-step durations. */
function durations(steps) {
  let prev = 0;
  return steps.map((s) => {
    const out = { duration: s.until - prev, dy: s.dy, frame: s.frame };
    prev = s.until;
    return out;
  });
}

export function gbwDefault(def) {
  const d = DEFAULTS[def.id];
  return { id: def.id, period: d.period, anim: d.anim, overhang: d.overhang, steps: durations(d.steps) };
}

/** Always returns every weapon, in catalogue order. Step order is kept as given (gbwIssues flags it). */
export function normalizeGbWeapons(raw) {
  const list = Array.isArray(raw) ? raw : [];
  return GBW_DEFS.map((def) => {
    const base = gbwDefault(def);
    const r = list.find((w) => w && w.id === def.id);
    if (!r) return base;
    // Older files stored "until" (end time); turn it into a duration.
    let prevUntil = 0;
    const steps = Array.isArray(r.steps)
      ? r.steps.slice(0, GBW_MAX_STEPS).map((s) => {
          let dur = s?.duration;
          if (dur == null && s?.until != null) dur = Number(s.until) - prevUntil;
          const step = {
            duration: clampInt(dur, 1, 255, 1),
            dy: clampInt(s?.dy, -128, 127, 0),
            frame: s?.frame === "alt" ? "alt" : "idle",
          };
          prevUntil += step.duration;
          return step;
        })
      : base.steps;
    return {
      id: def.id,
      period: clampInt(r.period, 1, 255, base.period),
      anim: clampInt(r.anim, 0, 255, base.anim),
      overhang: clampInt(r.overhang, 0, 64, base.overhang),
      steps,
    };
  });
}

/** End time of each step (VBlanks since the shot): what the GBC table stores as "until". */
export function gbwUntils(w) {
  let t = 0;
  return w.steps.map((s) => (t += s.duration));
}

/** Anim length in VBlanks: the sum of the step durations for table weapons, the stored value otherwise. */
export function gbwAnimLen(def, w) {
  if (!def.tabled) return w.anim;
  return w.steps.reduce((a, s) => a + s.duration, 0);
}

/** Problems that would stop gbc_genwpntab.py (or make the table meaningless). */
export function gbwIssues(def, w) {
  const out = [];
  if (!def.tabled) return out;
  const total = gbwAnimLen(def, w);
  if (total > 255) out.push(`total ${total} VBlanks: the table can hold at most 255`);
  return out;
}

/** Pose e VBlanks after a shot (e < 0: idle). Mirrors WpnPose: {alt, dy}; dy is the offset from the rest position. */
export function gbwPose(def, w, e) {
  if (def.tabled && e >= 0) {
    let end = 0;
    for (const st of w.steps) {
      end += st.duration;
      if (e < end) return st.frame === "alt" ? { alt: true, dy: st.dy } : { alt: false, dy: st.dy + w.overhang };
    }
  }
  return { alt: false, dy: def.tabled ? w.overhang : 0 };
}

export function gbwMs(vblanks) {
  return (vblanks * 1000) / GBW_VBLANK_HZ;
}
