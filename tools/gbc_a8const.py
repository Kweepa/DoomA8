#!/usr/bin/env python3
"""A8 constants and per-type enemy metadata for the GBC build, taken from the A8 sources.

Writes <outdir>/a8const.inc:
  DEF <name> EQU <value>   for the A8 constants the GBC port uses (src/mem.asm, src/map_counts.asm)
  DEF EM_* EQU <offset>    field offsets inside one enemy meta row
Writes <outdir>/a8enmeta.inc: MACRO EN_META_ROWS <prefix> -> <prefix>Ptr (dw per enemy type) and one row
per type:
        the 34-byte A8 meta row (tools/genenemies.py build_meta_row, the same bytes the A8 .pose
        files carry) followed by the A8 hp byte (enemy_hp_byte).

Nothing here is typed by hand: if a value changes on the A8 side, the GBC build follows.
"""
import copy
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)

SOURCES = ["src/loader.asm", "src/item_mesh.asm", "src/mem.asm", "src/map_counts.asm", "src/build_flags.asm", "src/a8irq.asm", "src/world.asm"]

# A8 names the GBC code uses (same name, same value).
WANT = [
    "ANIM_MS", "ENEMY_DETECT", "ENEMY_STEP_JIT", "DOOM_STEP_MS", "DOOM_ATK_MS", "GRUNT_ATK_MS",
    "IMP_ATK_MS", "DEMON_MELEE_R", "GRUNT_BACKOFF", "ENEMY_CULL_H", "SHOT_MID_H",
    "EN_IDLE", "EN_ALERT", "EN_APPROACH", "EN_ATTACK", "EN_PAIN", "EN_DYING", "EN_DEAD", "EN_GONE",
    "ENT_POSS", "ENT_BARON", "ENT_PINKY", "ENT_IMP", "DOOR_HIDDEN",
    "PLAYER_H", "FALL_LEDGE", "STEP_UP",
    "AI_AP_MOVE", "AI_AP_STAND", "AI_AP_NEXT",
    "TH_LIGHTPOST", "TH_BARREL",
    "HURT_FLASH_MS", "STATUS_MS", "HUD_PF2_STAT", "HUD_PF1_STAT", "HUD_PF1_MSG", "COL_HURT_A8", "COL_SUIT_A8",
    "HUD_CH_BULLET", "HUD_CH_SHELL", "HUD_CH_ROCKET", "HUD_CH_KEY_RED", "HUD_CH_KEY_YEL", "HUD_CH_KEY_BLU",
    "HAVE_YELLOW", "HAVE_BLUE", "HAVE_RED",
    "RKT_MAX", "RKT_F_FIREBALL", "RKT_F_BARON", "RKT_TICK_MS", "RKT_LIFE_MS", "RKT_HIT_R", "RKT_R",
    "RKT_WRIST_L", "RKT_WRIST_R", "EMUZ_OX", "EMUZ_OY", "EMUZ_MS", "EMUZ_Z0", "EMUZ_Z1",
    # player (src/mem.asm, world.asm gb_*)
    "AMMO_SHELLS_START", "AMMO_BULLETS_START", "PLAYER_HP_START", "PLAYER_HP_MAX", "PLAYER_ARMOUR_START",
    "FALL_SAFE", "FALL_DAMAGE", "POWERUP_MS", "PICKUP_HOLD_MS", "TH_FOOT_SX", "TH_GRAB_R", "PL_DEATH_WAIT_MS",
    "HAVE_SHOT", "HAVE_CHAIN", "HAVE_ROCKET", "HAVE_PIST", "HAVE_SAW", "HAVE_START",
    "PISTOL_HIT_X", "CHAIN_HIT_X", "PISTOL_DMG_MAX", "SHOT_PELLETS", "SHOT_SPREAD_MASK", "SHOT_SPREAD_HALF",
    "SHOT_DMG_ROLL", "SHOT_DMG_BASE", "SHOT_Z_MAX", "PUNCH_HIT_R",
    "RKT_F_PEND", "RKT_OWN_PL", "RKT_OWN_EN", "RKT_SPEED_PL", "RKT_SPEED", "RKT_DMG_BASE", "RKT_RAD",
    "BARREL_CHAIN_MS", "EXPLODE_MS", "SPLAT_MS", "COL_SPLAT_HIT", "COL_SPLAT_MISS", "FLASH_YEL_MS", "FLASH_RED_MS", "FX_N", "FX_START_MS", "FX_VEL_SPEED", "TH_FOOT_SY", "ITEM_BIAS",
    "SW_USE_RANGE", "TRIG_MSG", "TRIG_END", "TRIG_HURT", "TRIG_SPAWN", "TRIG_ELEV", "TRIG_SUMMON", "TRIG_UNLOCK",
    "TRIG_UNHIDE", "TRIG_HURT_SM", "TRIG_PURPOSE_MASK", "TRIG_GATED_MASK", "SW_DEST_DOOR", "SW_DEST_ELEV",
    "SW_DEST_TRIG", "SW_DEST_END", "FACE_PZ", "FACE_MZ", "FACE_PX", "FACE_MX", "HURT_MS", "DOOR_UNHIDE_MS",
    "UNHIDE_MAX", "ELEV_STEP_MS", "ELEV_FLAG_SLOW", "HURT_SM_HP", "HURT_LG_HP", "DOOR_KEY_REMOTE", "MAP_NLEVELS",
    "GB_ADD", "GB_GUN", "GB_ARM", "GB_PU", "GB_KEY", "GB_PACK", "TH_NTYPES", "TH_RADSUIT", "TH_ARMOR_B",
]
# A8 values the GBC already defines elsewhere (hw.inc): checked, not emitted.
CHECK = {"EYE_HEIGHT": 3}

DEF_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;]+)")


def read_defs():
    defs = {}
    for rel in SOURCES:
        for line in open(os.path.join(ROOT, rel), encoding="utf-8"):
            m = DEF_RE.match(line.strip())
            if m:
                defs.setdefault(m.group(1), m.group(2).strip())
    return defs


def evaluate(name, defs, seen=()):
    if isinstance(name, str) and name.lstrip("-").isdigit():
        return int(name)
    if name not in defs:
        raise SystemExit("gbc_a8const: %s not defined in %s" % (name, ", ".join(SOURCES)))
    if name in seen:
        raise SystemExit("gbc_a8const: %s is recursive" % name)
    expr = defs[name]
    expr = re.sub(r"\$([0-9A-Fa-f]+)", lambda m: str(int(m.group(1), 16)), expr)
    expr = re.sub(r"%([01]+)", lambda m: str(int(m.group(1), 2)), expr)

    def sub(m):
        tok = m.group(0)
        return str(evaluate(tok, defs, seen + (name,)))
    expr = re.sub(r"[A-Za-z_][A-Za-z0-9_]*", sub, expr)
    return int(eval(expr, {"__builtins__": {}}))


# Offsets inside the 34-byte meta row (genenemies.build_meta_row / loader.asm copy_meta_row).
ROW = [("STAND_S", 0), ("STAND_L", 1), ("ALERT_S", 2), ("ALERT_L", 3), ("RUN_S", 4), ("RUN_L", 5),
       ("WALK_S", 6), ("WALK_L", 7), ("ATK_S", 8), ("ATK_L", 9),
       ("PAIN_N", 10), ("PAIN_S", 11), ("PAIN_L", 15), ("DEATH_N", 19), ("DEATH_S", 20), ("DEATH_L", 24),
       ("RANGE", 28), ("PAIN_CHANCE", 29), ("FIRE_FRAME", 30), ("CLASS", 31), ("NFRAMES", 32),
       ("BLOCK_R", 33), ("HP", 34)]


def pick_tables(defs):
    """{label: [19 values]} for src/world.asm gb_mode / gb_add / gb_max / gb_dbl / gb_bits / gb_wpn."""
    src = open(os.path.join(ROOT, "src", "world.asm"), encoding="utf-8").read().split(chr(10))
    out = {}
    for lab in ("gb_mode", "gb_add", "gb_max", "gb_dbl", "gb_bits", "gb_wpn"):
        i = next(k for k, l in enumerate(src) if l.strip() == lab)
        vals = []
        k = i + 1
        while k < len(src) and src[k].strip().startswith("!byte"):
            for tok in src[k].split("!byte", 1)[1].split(";")[0].split(","):
                vals.append(evaluate(tok.strip(), defs))
            k += 1
        if len(vals) != 19:
            raise SystemExit("gbc_a8const: %s has %d entries, expected 19" % (lab, len(vals)))
        out[lab] = vals
    return out


def enemy_rows():
    import genenemies as g
    doc = g.load_doc()
    by_name = {e["name"]: e for e in doc["enemies"]}
    rows = []
    for name in g.TYPES:
        e = copy.deepcopy(by_name[name])
        g.apply_export_clips(e)
        nframes = len(e["frames"])
        row = bytes(g.build_meta_row(name, e, nframes, nframes))
        rows.append((name, row + bytes([g.enemy_hp_byte(e, name)])))
    return rows


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    defs = read_defs()
    out = ["; Generated by tools/gbc_a8const.py from the A8 sources - do not edit.",
           "IF !DEF(A8CONST_INC)", "DEF A8CONST_INC EQU 1"]
    for name in WANT:
        out.append("DEF %s EQU %d" % (name, evaluate(name, defs)))
    for name, want in CHECK.items():
        got = evaluate(name, defs)
        if got != want:
            raise SystemExit("gbc_a8const: A8 %s = %d but the GBC build assumes %d" % (name, got, want))
    for pre, name in (("A8_WPN_FIST", "WPN_FIST"), ("A8_WPN_SHOT", "WPN_SHOT"), ("A8_WPN_CHAIN", "WPN_CHAIN"),
                      ("A8_WPN_ROCKET", "WPN_ROCKET"), ("A8_WPN_PIST", "WPN_PIST"), ("A8_WPN_SAW", "WPN_SAW"),
                      ("A8_START_HP", "PLAYER_HP_START"), ("A8_START_ARMOUR", "PLAYER_ARMOUR_START"),
                      ("A8_START_BUL", "AMMO_BULLETS_START"), ("A8_START_SHL", "AMMO_SHELLS_START")):
        out.append("DEF %s EQU %d" % (pre, evaluate(name, defs)))   # prefixed: wpn.asm has its own WPN_* names
    for k, off in ROW:
        out.append("DEF EM_%s EQU %d" % (k, off))
    out.append("DEF EM_SIZE EQU %d" % (ROW[-1][1] + 1))
    out.append("ENDC")
    open(os.path.join(outdir, "a8const.inc"), "w", newline="\n").write("\n".join(out) + "\n")

    # A8 pickup tables (src/world.asm gb_*), one byte per TH_* type: a8pick.inc
    pk = ["; Generated by tools/gbc_a8const.py from src/world.asm gb_* - do not edit.",
          "; One byte per TH_* type 0..18 (props 17 / 18 are not pickups)."]
    tabs = pick_tables(defs)
    for lab, name in (("gb_mode", "GbMode"), ("gb_add", "GbAdd"), ("gb_max", "GbMax"), ("gb_dbl", "GbDbl"),
                      ("gb_bits", "GbBits"), ("gb_wpn", "GbWpn")):
        pk.append("%s::" % name)
        pk.append("    db " + ", ".join(str(v & 255) for v in tabs[lab]))
    open(os.path.join(outdir, "a8pick.inc"), "w", newline=chr(10)).write(chr(10).join(pk) + chr(10))

    rows = enemy_rows()
    import gbc_genent
    # Two copies of the same rows: one in the AI bank (gbc/ai.asm, EnemiesBlockPlayer), one in the
    # entity bank next to the enemy meshes (drawing, LoadEnemies). ROM0 has no room for them.
    m = ["; Generated by tools/gbc_a8const.py from the A8 enemy data - do not edit.",
         "; EN_META_ROWS <prefix>: <prefix>Ptr (dw per enemy type) and one EM_SIZE row per type.",
         "DEF ENT_BANK EQU %d" % gbc_genent.ENT_BANK,
         "MACRO EN_META_ROWS",
         "\\1Ptr:: dw " + ", ".join("\\1_%d" % i for i in range(len(rows)))]
    for i, (name, row) in enumerate(rows):
        m.append("\\1_%d:   ; %s" % (i, name))
        m.append("    db " + ", ".join(str(b) for b in row))
    m.append("ENDM")
    open(os.path.join(outdir, "a8enmeta.inc"), "w", newline="\n").write("\n".join(m) + "\n")
    print("a8 constants: %d names, %d enemy meta rows" % (len(WANT), len(rows)))


if __name__ == "__main__":
    main()
