#!/usr/bin/env python3
"""Spec of the GBC player collision / floor / fall (port of src/world.asm static geometry).

Covered: room colliders (PLAYER_R inset, shared-face joins), crates, solid platforms, step-up,
slopes, floor following, gravity, ledge_unstick. Not yet: doors, elevators, enemies, damage.
All arithmetic is 8-bit unsigned with the same wrap/carry behaviour as the 6502 source.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gbc_genmap as gmap  # noqa: E402
import gbc_room as gr  # noqa: E402

EYE = 3
PLAYER_H = 4
PLAYER_R = 1
STEP_UP = 2
FALL_LEDGE = 1
FALL_ACCEL = 0x10
FALL_TICK_MS = 32
MS_PER_VBLANK = 17


class Level:
    def __init__(self, payload):
        fields = gmap.parse_bind_table()
        _, offs, _ = gmap.field_offsets(payload, fields)
        self.p = payload
        self.o = {f: o for (f, o, _) in offs}
        self.nrooms, self.ncrates, self.nslopes, self.nplats = payload[0], payload[2], payload[3], payload[4]
        self.spawn = payload[17:23]
        # Enemies as LoadEnemies leaves them (A8 init_enemies): idle at their map cells, tagged = gone.
        import gbc_a8const as ac
        block_r = [row[33] for (_, row) in ac.enemy_rows()]
        self.enemies = [dict(x=self.f("en_x", i), y=self.f("en_y", i), z=self.f("en_z", i),
                             room=self.f("en_room", i), r=block_r[self.f("en_type", i)])
                        for i in range(payload[7]) if not self.f("en_tag", i)]

    def f(self, name, i):
        return self.p[self.o[name] + i]


class Player:
    def __init__(self, lv, room, x16, z16, y16, yaw, floor_y):
        self.lv = lv
        self.room = room
        self.cam_x, self.cam_z, self.cam_y = x16, z16, y16
        self.yaw = yaw
        self.turn_frac = 0
        self.floor_y = floor_y
        self.floor_yl = 0
        self.floor_slope = 0
        self.falling = 0
        self.fall_vel = 0
        self.fall_acc = 0
        self.fall_y0 = 0
        self.keys = 0
        self.door_key = [lv.f("door_key", d) for d in range(lv.p[1])]
        self.door_type = [lv.f("door_type", d) for d in range(lv.p[1])]

    @property
    def xh(self):
        return self.cam_x >> 8

    @property
    def zh(self):
        return self.cam_z >> 8

    @property
    def yh(self):
        return self.cam_y >> 8

    def set_yh(self, v):
        self.cam_y = (self.cam_y & 0xFF) | ((v & 255) << 8)


def feet(P):
    return (P.yh - EYE) & 255


def overlaps_y(P, box_y, box_sy):
    top = (box_y + box_sy) & 255
    ft = feet(P)
    if ft >= top:
        return False
    head = (ft + PLAYER_H) & 255
    return box_y < head


def in_box_xz(col_x, col_z, bx, bz, bsx, bsz, inclusive):
    if col_x < bx:
        return False
    top = (bx + bsx) & 255
    if inclusive:
        if top < col_x:
            return False
    elif top <= col_x:
        return False
    if col_z < bz:
        return False
    top = (bz + bsz) & 255
    if inclusive:
        if top < col_z:
            return False
    elif top <= col_z:
        return False
    return True


def point_in_rc_xz(L, X, col_x, col_z):
    if L.f("rc_sx", X) == 0:
        return False
    return in_box_xz(col_x, col_z, L.f("rc_x", X), L.f("rc_z", X), L.f("rc_sx", X), L.f("rc_sz", X), False)


def rc_overlaps_y(P, X):
    return overlaps_y(P, P.lv.f("rc_y", X), P.lv.f("rc_sy", X))


def _ov(L, a, b, axis_pos, axis_size):
    """.rio_ovx / .rio_ovz: sibling Y and collider X overlap on the other axis (exclusive)."""
    ya = (L.f(axis_pos, a) + L.f(axis_size, a)) & 255
    if ya <= L.f(axis_pos, b):
        return False
    xa = (L.f(axis_pos, b) + L.f(axis_size, b)) & 255
    if xa <= L.f(axis_pos, a):
        return False
    return True


def join(P, X, room3, kind):
    """C=1 => skip the inset on that face (a sibling collider shares it)."""
    L = P.lv
    for k in range(3):
        Y = room3 + k
        if Y == X or L.f("rc_sx", Y) == 0:
            continue
        if kind == "xmin":
            if ((L.f("rc_x", Y) + L.f("rc_sx", Y)) & 255) != L.f("rc_x", X):
                continue
            ok = _ov(L, Y, X, "rc_z", "rc_sz")
        elif kind == "xmax":
            if ((L.f("rc_x", X) + L.f("rc_sx", X)) & 255) != L.f("rc_x", Y):
                continue
            ok = _ov(L, Y, X, "rc_z", "rc_sz")
        elif kind == "zmin":
            if ((L.f("rc_z", Y) + L.f("rc_sz", Y)) & 255) != L.f("rc_z", X):
                continue
            ok = _ov(L, Y, X, "rc_x", "rc_sx")
        else:
            if ((L.f("rc_z", X) + L.f("rc_sz", X)) & 255) != L.f("rc_z", Y):
                continue
            ok = _ov(L, Y, X, "rc_x", "rc_sx")
        if ok and overlaps_y(P, L.f("rc_y", Y), L.f("rc_sy", Y)):
            return True
    return False


def rc_inset_ok(P, X, room3, col_x, col_z):
    L = P.lv
    if L.f("rc_sx", X) == 0:
        return False
    if not rc_overlaps_y(P, X):
        return False
    a = col_x
    if not join(P, X, room3, "xmin"):
        a -= PLAYER_R
        if a < 0:
            return False
    if a < L.f("rc_x", X):
        return False
    a = (L.f("rc_x", X) + L.f("rc_sx", X)) & 255
    if not join(P, X, room3, "xmax"):
        a = (a - PLAYER_R) & 255
    if a <= col_x:
        return False
    a = col_z
    if not join(P, X, room3, "zmin"):
        a -= PLAYER_R
        if a < 0:
            return False
    if a < L.f("rc_z", X):
        return False
    a = (L.f("rc_z", X) + L.f("rc_sz", X)) & 255
    if not join(P, X, room3, "zmax"):
        a = (a - PLAYER_R) & 255
    if a <= col_z:
        return False
    return True


def in_room_inset(P, col_x, col_z, room=None):
    room = P.room if room is None else room
    r3 = room * 3
    return any(rc_inset_ok(P, r3 + k, r3, col_x, col_z) for k in range(3))


def peek_rc_floor(P, room, col_x, col_z):
    """(found, lowest rc_y among colliders containing the cell)."""
    found = False
    best = 0
    for k in range(3):
        X = room * 3 + k
        if point_in_rc_xz(P.lv, X, col_x, col_z):
            y = P.lv.f("rc_y", X)
            if not found:
                best, found = y, True
            elif y < best:
                best = y
    return found, best


def step_up_ok(P, col_x, col_z):
    found, df = peek_rc_floor(P, P.room, col_x, col_z)
    if not found:
        return True
    ft = feet(P)
    if df == ft or df < ft:
        return True
    return (df - ft) < STEP_UP + 1


def crates_block(P, col_x, col_z):
    L = P.lv
    for x in range(L.ncrates):
        if L.f("crate_room", x) != P.room:
            continue
        by, bsy = L.f("crate_y", x), L.f("crate_sy", x)
        if not overlaps_y(P, by, bsy):
            continue
        rise = (((by + bsy) & 255) - feet(P)) & 255
        if rise < STEP_UP + 1:
            continue
        if in_box_xz(col_x, col_z, L.f("crate_x", x), L.f("crate_z", x),
                     L.f("crate_sx", x), L.f("crate_sz", x), False):
            return True
    return False


def slice_of(L, name, room):
    return L.f(name, room), L.f(name, room + 1)


def solid_at(P, col_x, col_z):
    if crates_block(P, col_x, col_z):
        return True
    L = P.lv
    lo, hi = slice_of(L, "room_plat_o", P.room)
    for x in range(lo, hi):
        if L.f("plat_solid", x) == 0:
            continue
        py = L.f("plat_y", x)
        if not overlaps_y(P, py, 0):
            continue
        rise = (py - feet(P)) & 255
        if rise < STEP_UP + 1:
            continue
        if in_box_xz(col_x, col_z, L.f("plat_x", x), L.f("plat_z", x),
                     L.f("plat_sx", x), L.f("plat_sz", x), False):
            return True
    return door_blocks(P, col_x, col_z)


HAVE_YELLOW, HAVE_BLUE, HAVE_RED = 1, 2, 4
DOOR_Y_SLACK = 1
DOOR_AIM = 32
THRU_YAW = [128, 0, 192, 64]          # PZ, MZ, PX, MX
DOOR_HIDDEN = 0x80


def door_unlocked(P, d):
    key = P.door_key[d]
    if key == 0:
        return True
    if key == 3:                      # remote: opened by a switch / trigger only
        return False
    if key == 2:
        return bool(P.keys & HAVE_BLUE)
    if key == 4:
        return bool(P.keys & HAVE_RED)
    return bool(P.keys & HAVE_YELLOW)


def room_doors(P):
    lo = P.lv.f("room_door_o", P.room)
    return range(lo, lo + P.lv.f("room_ndoor", P.room))


def door_blocks(P, col_x, col_z):
    L = P.lv
    for d in room_doors(P):
        if door_unlocked(P, d):
            continue
        if in_box_xz(col_x, col_z, L.f("door_x", d), L.f("door_z", d),
                     L.f("door_sx", d), L.f("door_sz", d), False):
            return True
    return False


def door_y_ok(P, d):
    a = (feet(P) - P.lv.f("door_y", d)) & 255
    return a <= DOOR_Y_SLACK or a >= 256 - DOOR_Y_SLACK


def door_thru(P, d, joy_up, wx, wz):
    """Forward held, yaw within DOOR_AIM of the through-heading, wish pointing through."""
    if not joy_up:
        return False
    face = P.lv.f("door_face", d)
    delta = (P.yaw - THRU_YAW[face & 3]) & 255
    if delta >= 128:
        delta = (256 - delta) & 255
    if delta > DOOR_AIM:
        return False
    minus = face & 1
    zaxis = (face >> 1) == 0
    w = wz if zaxis else wx
    hi = (w >> 8) & 255
    if not minus:
        return hi >= 128                      # negative: toward -axis
    return w != 0 and hi < 128                # positive and non-zero


def door_snap(P, d):
    L = P.lv
    face = L.f("door_face", d)
    minus = face & 1
    if (face >> 1) == 0:
        if not minus:
            a = L.f("door_z", d) - 2
            a = 0 if a < 0 else a
        else:
            a = (L.f("door_z", d) + L.f("door_sz", d)) & 255
            a = (a + 1) & 255
        P.cam_z = a << 8
    else:
        if not minus:
            a = L.f("door_x", d) - 2
            a = 0 if a < 0 else a
        else:
            a = (L.f("door_x", d) + L.f("door_sx", d)) & 255
            a = (a + 1) & 255
        P.cam_x = a << 8


def try_door_wish(P, joy_up, wx, wz, blk):
    """A wall-ward wish that was blocked may pass through an unlocked door. True = transit."""
    if blk == 0 or (wx | wz) == 0:
        return False
    L = P.lv
    save_x, save_z = P.cam_x, P.cam_z
    if blk & 1:
        P.cam_x = (P.cam_x + wx) & 0xFFFF
    if blk & 2:
        P.cam_z = (P.cam_z + wz) & 0xFFFF
    for d in room_doors(P):
        if P.door_type[d] & DOOR_HIDDEN:
            continue
        dx, dz = L.f("door_x", d), L.f("door_z", d)
        bx = 0 if dx == 0 else dx - 1
        bz = 0 if dz == 0 else dz - 1
        bsx = (L.f("door_sx", d) + 2) & 255
        bsz = (L.f("door_sz", d) + 2) & 255
        if not in_box_xz(P.xh, P.zh, bx, bz, bsx, bsz, False):
            continue
        if not door_y_ok(P, d):
            continue
        if not door_thru(P, d, joy_up, wx, wz):
            continue
        if not door_unlocked(P, d):
            break                              # key HUD; restore below
        other = L.f("door_other", d)
        if other == 0xFF:
            continue
        door_snap(P, d)
        P.room = other
        return True
    P.cam_x, P.cam_z = save_x, save_z
    return False


ENEMY_CULL_H = 6


def enemies_block_player(P, col_x, col_z, pre):
    """A8 enemies_block_player: newly overlapping a live enemy of this room (Chebyshev < block_r + 1,
    overlapping in Y) blocks; a body already overlapped at the pre-move cell does not."""
    def near(e, x, z, lim):
        return abs(e["x"] - x) < lim and abs(e["z"] - z) < lim      # unsigned byte difference, as on the 6502
    for e in P.lv.enemies:
        if e["room"] != P.room or not overlaps_y(P, e["y"], ENEMY_CULL_H):
            continue
        lim = e["r"] + 1
        if near(e, col_x, col_z, lim) and not near(e, pre[0], pre[1], lim):
            return True
    return False


def pos_ok(P, col_x, col_z, pre=None):
    if not in_room_inset(P, col_x, col_z):
        return False
    if pre is not None and enemies_block_player(P, col_x, col_z, pre):
        return False
    if solid_at(P, col_x, col_z):
        return False
    return step_up_ok(P, col_x, col_z)


def slope_height(P, X, frac):
    L = P.lv
    axis = L.f("slope_axis", X)
    if axis == 0:
        pos = (((P.xh - L.f("slope_x", X)) & 255) << 8) | frac
        run = L.f("slope_sx", X)
    else:
        pos = (((P.zh - L.f("slope_z", X)) & 255) << 8) | frac
        run = L.f("slope_sz", X)
    if L.f("slope_dir", X) == 0:
        pos = (run * 256 - pos) & 0xFFFF
    if run == 0:
        return L.f("slope_y", X), 0
    q = (L.f("slope_sy", X) * pos) // run
    return (L.f("slope_y", X) + ((q >> 8) & 255)) & 255, q & 255


def update_floor(P):
    L = P.lv
    P.floor_yl = 0
    P.floor_slope = 0
    cx, cz = P.xh, P.zh
    found, y = peek_rc_floor(P, P.room, cx, cz)
    if found:
        P.floor_y = y
    for x in range(L.ncrates):
        if L.f("crate_room", x) != P.room:
            continue
        if not in_box_xz(cx, cz, L.f("crate_x", x), L.f("crate_z", x),
                         L.f("crate_sx", x), L.f("crate_sz", x), True):
            continue
        top = (L.f("crate_y", x) + L.f("crate_sy", x)) & 255
        if top <= P.floor_y:
            continue
        ft = feet(P)
        if ft >= top or ((top - ft) & 255) < STEP_UP + 1:
            P.floor_y = top
    lo, hi = slice_of(L, "room_plat_o", P.room)
    for x in range(lo, hi):
        if L.f("plat_solid", x) == 0:
            continue
        if not in_box_xz(cx, cz, L.f("plat_x", x), L.f("plat_z", x),
                         L.f("plat_sx", x), L.f("plat_sz", x), True):
            continue
        py = L.f("plat_y", x)
        if py <= P.floor_y:
            continue
        ft = feet(P)
        if ft >= py or ((py - ft) & 255) < STEP_UP + 1:
            P.floor_y = py
    lo, hi = slice_of(L, "room_slope_o", P.room)
    for x in range(lo, hi):
        if not in_box_xz(cx, cz, L.f("slope_x", x), L.f("slope_z", x),
                         L.f("slope_sx", x), L.f("slope_sz", x), True):
            continue
        frac = P.cam_x & 255 if L.f("slope_axis", x) == 0 else P.cam_z & 255
        cy, fr = slope_height(P, x, frac)
        if cy < P.floor_y:
            continue
        ft = feet(P)
        if not (cy <= ft or ((cy - ft) & 255) < STEP_UP + 1):
            continue
        P.floor_y = cy
        P.floor_yl = fr
        P.floor_slope = 0
        if ft < cy:
            continue
        gap = ft - cy
        if gap >= FALL_LEDGE + 1:
            continue
        P.floor_slope = 1


def sync_eye(P):
    P.cam_y = (((P.floor_y + EYE) & 255) << 8) | P.floor_yl


DX = [255, 1, 0, 0, 255, 1, 255, 1]
DZ = [0, 0, 255, 1, 255, 255, 1, 1]


def ledge_unstick(P):
    saved = P.yh
    P.set_yh(P.floor_y + EYE)
    cx, cz = P.xh, P.zh
    if not in_room_inset(P, cx, cz):
        for i in range(8):
            nx, nz = cx, cz
            dx = DX[i]
            if dx == 1:
                if cx == 255:
                    continue
                nx = cx + 1
            elif dx == 255:
                if cx == 0:
                    continue
                nx = cx - 1
            dz = DZ[i]
            if dz == 1:
                if cz == 255:
                    continue
                nz = cz + 1
            elif dz == 255:
                if cz == 0:
                    continue
                nz = cz - 1
            if (in_room_inset(P, nx, nz) and step_up_ok(P, nx, nz) and not solid_at(P, nx, nz)):
                if nx != P.xh:
                    P.cam_x = (nx << 8) | (0xFF if nx < P.xh else 0)
                if nz != P.zh:
                    P.cam_z = (nz << 8) | (0xFF if nz < P.zh else 0)
                break
    P.set_yh(saved)


def update_fall(P, dt_ms):
    if not P.falling:
        if P.floor_slope:
            ledge_unstick(P)
            sync_eye(P)
            return
        ft = feet(P)
        if ft == P.floor_y:
            ledge_unstick(P)
            sync_eye(P)
            return
        if ft < P.floor_y:
            if (P.floor_y - ft) < STEP_UP + 1:
                ledge_unstick(P)
                sync_eye(P)
            return
        if (ft - P.floor_y) < FALL_LEDGE + 1:
            ledge_unstick(P)
            sync_eye(P)
            return
        ledge_unstick(P)
        P.falling = 1
        P.fall_vel = 0
        P.fall_acc = 0
        P.fall_y0 = P.yh
    acc = P.fall_acc + dt_ms
    while acc >= FALL_TICK_MS:
        acc -= FALL_TICK_MS
        P.fall_vel = (P.fall_vel + FALL_ACCEL) & 0xFFFF
        P.cam_y = (P.cam_y - P.fall_vel) & 0xFFFF
        if feet(P) <= P.floor_y:
            land(P)
            return
    P.fall_acc = acc & 255
    if feet(P) <= P.floor_y:
        land(P)


def land(P):
    sync_eye(P)
    P.falling = 0
    P.fall_vel = 0
    P.fall_acc = 0


def wish_of(yaw, frac, joy, dt):
    """Turn -> (new_yaw, new_frac, wish_dx, wish_dz) as signed ints (summed SMul16)."""
    dist = gr.hold_dist(4 * dt)
    yaw, frac = gr.turn_step(yaw, frac, joy, dt)
    sn, cs = gr.sin_of(yaw), gr.cos_of(yaw)
    wx = wz = 0

    def along(bm, cm):
        nonlocal wx, wz
        wx += gr.smul16(dist, bm)
        wz += gr.smul16(dist, cm)

    if joy & 4:
        along(sn, cs)
    if joy & 8:
        along(-sn, -cs)
    if joy & 0x20:
        if joy & 1:
            along(cs, -sn)
        if joy & 2:
            along(-cs, sn)
    return yaw, frac, wx & 0xFFFF, wz & 0xFFFF


def apply_wish(P, wx, wz):
    """Returns door_blk: bit0 = X rejected, bit1 = Z rejected."""
    blk = 0
    if P.falling:
        return blk
    pre = [P.xh, P.zh]                  # A8 save_xh / save_zh
    if wx:
        save = P.cam_x
        P.cam_x = (P.cam_x + wx) & 0xFFFF
        if not pos_ok(P, P.xh, P.zh, pre):
            P.cam_x = save
            blk |= 1
    pre[0] = P.xh
    if wz:
        save = P.cam_z
        P.cam_z = (P.cam_z + wz) & 0xFFFF
        if not pos_ok(P, P.xh, P.zh, pre):
            P.cam_z = save
            blk |= 2
    return blk


def step(P, joy, dt):
    P.yaw, P.turn_frac, wx, wz = wish_of(P.yaw, P.turn_frac, joy, dt)
    blk = apply_wish(P, wx, wz)
    try_door_wish(P, bool(joy & 4), wx, wz, blk)
    update_floor(P)
    update_fall(P, dt * MS_PER_VBLANK)


# ---- test scenarios -----------------------------------------------------------------

def walk_script(n=32, seed=12345):
    """Deterministic pad script: 16 steady forward steps (to push into walls / doors), then a
    forward-heavy random mix with turns, strafes and back steps."""
    joys = [0x04, 0x04, 0x04, 0x04, 0x05, 0x06, 0x04, 0x08, 0x25, 0x26, 0x24, 0x04, 0x0C, 0x00]
    s = seed
    out = [(0x04, 3)] * 16
    for _ in range(n):
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        joy = joys[(s >> 8) % len(joys)]
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        dt = 1 + ((s >> 10) % 4)
        out.append((joy, dt))
    return out


def world_tests():
    """[(level_idx, room, camx16, camz16, camy16, yaw, floor_y, keys)].
    Per room: start in collider 0 (centre). Per crate / solid platform / slope of a room: start just
    west of the object facing it, and start above its centre (falls onto it)."""
    out = []
    li = 0
    for key in gmap.gm.LEVEL_NAMES:
        lv = gmap.gm.load_level(key)
        if not any(o.get("kind") == "spawn" for o in (lv.get("objects") or [])):
            continue
        L = Level(gmap.gm.cook_one(lv, key))
        base = []
        extra = []
        for r in range(L.nrooms):
            X = r * 3
            while X < r * 3 + 3 and L.f("rc_sx", X) == 0:
                X += 1
            if X >= r * 3 + 3:
                continue
            fy = L.f("rc_y", X)
            cx = (L.f("rc_x", X) + L.f("rc_sx", X) // 2) * 256 + 77
            cz = (L.f("rc_z", X) + L.f("rc_sz", X) // 2) * 256 + 131
            base.append((li, r, cx, cz, ((fy + EYE) & 255) << 8, (r * 37 + li * 11) & 255, fy, 0))
            objs = []
            for x in range(L.ncrates):
                if L.f("crate_room", x) == r:
                    objs.append((L.f("crate_x", x), L.f("crate_z", x), L.f("crate_sx", x), L.f("crate_sz", x)))
            lo, hi = slice_of(L, "room_plat_o", r)
            for x in range(lo, hi):
                if L.f("plat_solid", x):
                    objs.append((L.f("plat_x", x), L.f("plat_z", x), L.f("plat_sx", x), L.f("plat_sz", x)))
            lo, hi = slice_of(L, "room_slope_o", r)
            for x in range(lo, hi):
                objs.append((L.f("slope_x", x), L.f("slope_z", x), L.f("slope_sx", x), L.f("slope_sz", x)))
            for (ox, oz, osx, osz) in objs:
                zc = (oz + osz // 2) * 256 + 9
                extra.append((li, r, ((ox - 1) & 255) * 256 + 200, zc, ((fy + EYE) & 255) << 8, 64 + (r & 7), fy, 0))
                extra.append((li, r, (ox + osx // 2) * 256 + 13, zc, ((fy + EYE + 10) & 255) << 8, (r * 5) & 255, fy, 0))
            # doors of this room: start inside, a step or two from the slab, aimed through it
            lo = L.f("room_door_o", r)
            for d in range(lo, lo + L.f("room_ndoor", r)):
                dx, dy, dz = L.f("door_x", d), L.f("door_y", d), L.f("door_z", d)
                dsx, dsz, face = L.f("door_sx", d), L.f("door_sz", d), L.f("door_face", d)
                if face == 0:
                    px, pz = dx + dsx // 2, dz + dsz + 1
                elif face == 1:
                    px, pz = dx + dsx // 2, dz - 2
                elif face == 2:
                    px, pz = dx + dsx + 1, dz + dsz // 2
                else:
                    px, pz = dx - 2, dz + dsz // 2
                yaw = (THRU_YAW[face & 3] + (d * 7) % 24 - 12) & 255
                for keys in ((0, 7) if L.f("door_key", d) else (0,)):
                    extra.append((li, r, (px & 255) * 256 + 100, (pz & 255) * 256 + 100,
                                  ((dy + EYE) & 255) << 8, yaw, dy, keys))
        out += base + extra
        li += 1
    return out


def wslice():
    """Optional env GBC_WSLICE=a:b selects a slice of world_tests() (RAM limits one run to ~250)."""
    spec = os.environ.get("GBC_WSLICE", "0:200")
    a, b = spec.split(":")
    return int(a), int(b)


def run_test(L, t, script):
    """Run one scenario; returns the per-test record the ROM stores: (checksum16, camx, camz, camy)."""
    (_, room, cx, cz, cy, yaw, fy, keys) = t
    P = Player(L, room, cx, cz, cy, yaw, fy)
    P.keys = keys
    s1 = s2 = 0
    for (joy, dt) in script:
        step(P, joy, dt)
        for b in (P.cam_x & 255, P.cam_x >> 8, P.cam_z & 255, P.cam_z >> 8, P.cam_y & 255, P.cam_y >> 8,
                  P.floor_y, P.falling | (P.floor_slope << 1), P.yaw, P.room):
            s1 = (s1 + b) & 255
            s2 = (s2 + s1) & 255
    return ((s2 << 8) | s1, P.cam_x, P.cam_z, P.cam_y), P


# ---- per-room collision record (cooker output, copied into the WRAM room cache) -----------------

FACES = ("xmin", "xmax", "zmin", "zmax")


def static_join_mask(L, room, k, face):
    """Bit j set when sibling collider j of the room shares that face of collider k (static part of
    join(); the runtime adds the player-Y overlap test)."""
    X = room * 3 + k
    m = 0
    for j in range(3):
        Y = room * 3 + j
        if Y == X or L.f("rc_sx", Y) == 0:
            continue
        if face == "xmin":
            if ((L.f("rc_x", Y) + L.f("rc_sx", Y)) & 255) != L.f("rc_x", X):
                continue
            ok = _ov(L, Y, X, "rc_z", "rc_sz")
        elif face == "xmax":
            if ((L.f("rc_x", X) + L.f("rc_sx", X)) & 255) != L.f("rc_x", Y):
                continue
            ok = _ov(L, Y, X, "rc_z", "rc_sz")
        elif face == "zmin":
            if ((L.f("rc_z", Y) + L.f("rc_sz", Y)) & 255) != L.f("rc_z", X):
                continue
            ok = _ov(L, Y, X, "rc_x", "rc_sx")
        else:
            if ((L.f("rc_z", X) + L.f("rc_sz", X)) & 255) != L.f("rc_z", Y):
                continue
            ok = _ov(L, Y, X, "rc_x", "rc_sx")
        if ok:
            m |= 1 << j
    return m


def _pad(vals, n):
    return list(vals) + [0] * (n - len(vals))


ROOM_REC_LEN = 36 + 49 + 41 + 33 + 65     # = 224


def room_record(L, room):
    """159-byte record laid out exactly like the WRAM room cache (see gbc/vars.asm wRoomCache)."""
    rec = []
    for name in ("rc_x", "rc_y", "rc_z", "rc_sx", "rc_sy", "rc_sz"):
        rec += _pad([L.f(name, room * 3 + k) for k in range(3)], 4)
    for k in range(3):
        for face in FACES:
            rec.append(static_join_mask(L, room, k, face))
    crates = [x for x in range(L.ncrates) if L.f("crate_room", x) == room]
    assert len(crates) <= 8
    rec.append(len(crates))
    for name in ("crate_x", "crate_y", "crate_z", "crate_sx", "crate_sy", "crate_sz"):
        rec += _pad([L.f(name, x) for x in crates], 8)
    lo, hi = slice_of(L, "room_plat_o", room)
    plats = [x for x in range(lo, hi) if L.f("plat_solid", x) != 0]
    assert len(plats) <= 8
    rec.append(len(plats))
    for name in ("plat_x", "plat_y", "plat_z", "plat_sx", "plat_sz"):
        rec += _pad([L.f(name, x) for x in plats], 8)
    lo, hi = slice_of(L, "room_slope_o", room)
    slopes = list(range(lo, hi))
    assert len(slopes) <= 4
    rec.append(len(slopes))
    for name in ("slope_x", "slope_y", "slope_z", "slope_sx", "slope_sy", "slope_sz", "slope_axis", "slope_dir"):
        rec += _pad([L.f(name, x) for x in slopes], 4)
    lo = L.f("room_door_o", room)
    doors = list(range(lo, lo + L.f("room_ndoor", room)))
    assert len(doors) <= 8
    rec.append(len(doors))
    rec += _pad(doors, 8)
    for name in ("door_x", "door_y", "door_z", "door_sx", "door_sz", "door_face", "door_other"):
        rec += _pad([L.f(name, d) for d in doors], 8)
    assert len(rec) == ROOM_REC_LEN, len(rec)
    return rec
