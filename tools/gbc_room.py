#!/usr/bin/env python3
"""GBC room renderer: bit-exact Python spec + include generator.

Pipeline (all integer, sign-magnitude truncation toward zero):
  trig  : sin/cos 8-bit signed (+-127), yaw 0..255
  rotate: per unique X / Z: d = u*256 - cam (8.8), dc = d*cos>>7, ds = d*sin>>7
          X' = dxc - dzs, Z' = dxs + dzc, Y' = y*256 - cam_y
  near  : Z' < ZCLIP (256) is behind
  project (front): zn = Z' >> s with zn in 128..255; R = RECIP[zn-128] (16 bit);
          p = (|v| * R) >> (15 + s); sx = 64 + p(X'), sy = 56 - p(Y')
  edges : both behind -> skip; one behind -> lerp to z = ZCLIP in view space
          (scaled n/d, see lerp), then project with FOCAL/ZCLIP
  clip  : 16-bit Cohen-Sutherland against 0..127 x 0..111 using lerp
  draw  : Bresenham from gbc_genlines.ref_line

Usage: gbc_room.py <outdir>   writes room_tables.inc, scene.inc, poses.inc
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_genlines as gl  # noqa: E402

FOCAL = 80
CX, CY = 64, 56
ZCLIP = 256
VW, VH = gl.VIEW_W, gl.VIEW_H


def sin_tab():
    t = []
    for i in range(256):
        v = int(round(127.0 * math.sin(i * 2.0 * math.pi / 256.0)))
        t.append(max(-127, min(127, v)))
    return t


SIN = sin_tab()


def sin_of(yaw):
    return SIN[yaw & 255]


def cos_of(yaw):
    return SIN[(yaw + 64) & 255]


RECIP = [int(round(FOCAL * 32768.0 / zn)) for zn in range(128, 256)]


def sgn_mag(v):
    return (-1 if v < 0 else 1), abs(v)


def smul16(d, m):
    """(d * m) >> 7, sign-magnitude, d 16-bit signed, m 8-bit signed."""
    s = (d < 0) != (m < 0)
    mag = (abs(d) * abs(m)) >> 7
    return -mag if s else mag


def norm(z):
    """z >= 256 (16-bit). Returns (s, zn) with zn = z >> s in 128..255."""
    s = 0
    while (z >> s) > 255:
        s += 1
    return s, z >> s


def project(v, R, s):
    sign = v < 0
    mag = (abs(v) * R) >> (15 + s)
    return -mag if sign else mag


def lerp(Y, n, d):
    """Y * n / d with n, d shrunk to d <= 255 first (sign-magnitude)."""
    sign = (Y < 0) ^ (n < 0) ^ (d < 0)
    an, ad = abs(n), abs(d)
    assert an <= ad, "lerp needs |n| <= |d|"
    while ad > 255:
        an >>= 1
        ad >>= 1
    if ad == 0:
        return 0
    q = (abs(Y) * an) // ad
    return -q if sign else q


# ---- scene -----------------------------------------------------------------
UX = [0, 40, 80, 15, 30]
UZ = [0, 40, 80, 15, 30]
COLS = [(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2),      # L-room corners
        (3, 3), (4, 3), (4, 4), (3, 4)]                       # floor quad
HEIGHT = 40
VERTS = [(c, 0) for c in range(6)] + [(c, HEIGHT) for c in range(6)] + \
        [(c, 0) for c in range(6, 10)]
EDGES = [(i, (i + 1) % 6) for i in range(6)] + \
        [(6 + i, 6 + (i + 1) % 6) for i in range(6)] + \
        [(i, i + 6) for i in range(6)] + \
        [(12 + i, 12 + (i + 1) % 4) for i in range(4)]


def set_scene(ux, uz, cols, verts, edges):
    """Replace the scene (renderer mesh format) used by render()/segments()."""
    global UX, UZ, COLS, VERTS, EDGES
    UX, UZ, COLS, VERTS, EDGES = list(ux), list(uz), list(cols), list(verts), list(edges)


# A8 rates: turn 1 yaw unit per 16 ms, move (sin * ms) >> 6 = ~7.75 units/s. One input tick is
# 1/4 VBlank (4.17 ms): 67/256 yaw unit and 8.25 8.8-units per tick (33 per VBlank).
MOVE_SPEED = 33
TURN_TICK = 67


def hold_dist(ticks):
    """HoldDist in world.asm: 8.8 world units for `ticks` input ticks."""
    return ticks * 8 + (ticks >> 2)


def turn_step(yaw, frac, joy, dt):
    """ApplyInput turn: net hold ticks * TURN_TICK into an 8.8 yaw accumulator. -> (yaw, frac)."""
    net = 0
    if not (joy & 0x20):
        net = 4 * dt * ((joy & 1) - (joy >> 1 & 1))
    tot = frac + net * TURN_TICK
    return (yaw + (tot >> 8)) & 255, tot & 255


def apply_move(state, joy, dt):
    """Spec of world.asm ApplyMove. state = (camx, camz, yaw, turn_frac); cam 16-bit 8.8 (wraps)."""
    x, z, yaw, frac = state
    dist = hold_dist(4 * dt)
    yaw, frac = turn_step(yaw, frac, joy, dt)
    sn, cs = sin_of(yaw), cos_of(yaw)

    def along(bm, cm):
        nonlocal x, z
        x = (x + smul16(dist, bm)) & 0xFFFF
        z = (z + smul16(dist, cm)) & 0xFFFF

    if joy & 4:
        along(sn, cs)
    if joy & 8:
        along(-sn, -cs)
    if joy & 0x20:
        if joy & 1:
            along(cs, -sn)
        if joy & 2:
            along(-cs, sn)
    return (x, z, yaw, frac)


def move_script():
    """[(joy, dt)] covering forward/back/turn/strafe at several frame times."""
    out = []
    for dt in (1, 2, 3, 4):
        out += [(0x04, dt)] * 6
    out += [(0x01, 2)] * 20 + [(0x04, 1)] * 8
    out += [(0x02, 3)] * 30 + [(0x04, 2)] * 8
    out += [(0x08, 1)] * 10 + [(0x28 | 0x01, 1)] * 10 + [(0x20 | 0x02, 3)] * 10
    out += [(0x05, 1)] * 10 + [(0x0A, 2)] * 10 + [(0x00, 1)] * 2
    out += [(0x04, 4)] * 40
    return out


MOVE_START = (40 * 256 + 17, 40 * 256 + 90, 200, 0)


def poses():
    """(cam_x, cam_z, yaw) with cam in 8.8; eye height fixed."""
    out = []
    spots = [(22 * 256 + 77, 20 * 256 + 5), (70 * 256 + 200, 22 * 256 + 130),
             (20 * 256 + 17, 60 * 256 + 255), (2 * 256 + 40, 2 * 256 + 9),
             (40 * 256 + 128, 40 * 256 + 128)]
    for (x, z) in spots:
        for yaw in range(0, 256, 8):
            out.append((x, z, yaw))
    return out


CAM_Y = 24 * 256


def outcode(x, y):
    oc = 0
    if x < 0:
        oc |= 1
    elif x > VW - 1:
        oc |= 2
    if y < 0:
        oc |= 4
    elif y > VH - 1:
        oc |= 8
    return oc


def clip_line(x0, y0, x1, y1):
    """16-bit Cohen-Sutherland; returns clipped ints or None."""
    for _ in range(8):
        oc0 = outcode(x0, y0)
        oc1 = outcode(x1, y1)
        if (oc0 | oc1) == 0:
            return x0, y0, x1, y1
        if oc0 & oc1:
            return None
        if oc0:
            oc, px, py, qx, qy = oc0, x0, y0, x1, y1
        else:
            oc, px, py, qx, qy = oc1, x1, y1, x0, y0
        if oc & 1:
            ny = py + lerp(qy - py, 0 - px, qx - px)
            nx = 0
        elif oc & 2:
            ny = py + lerp(qy - py, (VW - 1) - px, qx - px)
            nx = VW - 1
        elif oc & 4:
            nx = px + lerp(qx - px, 0 - py, qy - py)
            ny = 0
        else:
            nx = px + lerp(qx - px, (VH - 1) - py, qy - py)
            ny = VH - 1
        if oc0:
            x0, y0 = nx, ny
        else:
            x1, y1 = nx, ny
    return None


def project_vert(X, Y, Z):
    """(X, Y, Z, front, sx, sy) for a view-space vertex (8.8 units)."""
    if Z >= ZCLIP:
        sh, zn = norm(Z)
        R = RECIP[zn - 128]
        return (X, Y, Z, True, CX + project(X, R, sh), CY - project(Y, R, sh))
    return (X, Y, Z, False, 0, 0)


def segments(cam_x, cam_z, yaw, cam_y=CAM_Y):
    """Clipped integer segments per drawn edge: [(edge_index, x0, y0, x1, y1)]."""
    sn, cs = sin_of(yaw), cos_of(yaw)
    uxc = [smul16(u * 256 - cam_x, cs) for u in UX]
    uxs = [smul16(u * 256 - cam_x, sn) for u in UX]
    uzc = [smul16(u * 256 - cam_z, cs) for u in UZ]
    uzs = [smul16(u * 256 - cam_z, sn) for u in UZ]
    cols = []
    for (xi, zi) in COLS:
        X = uxc[xi] - uzs[zi]
        Z = uxs[xi] + uzc[zi]
        front = Z >= ZCLIP
        if front:
            s, zn = norm(Z)
            R = RECIP[zn - 128]
            sx = CX + project(X, R, s)
        else:
            s = R = sx = 0
        cols.append((X, Z, front, R, s, sx))
    verts = []
    for (c, y) in VERTS:
        X, Z, front, R, s, sx = cols[c]
        Y = y * 256 - cam_y
        sy = CY - project(Y, R, s) if front else 0
        verts.append((X, Y, Z, front, sx, sy))
    return edge_segments(verts, EDGES)


def edge_segments(verts, edges):
    """verts: [(X, Y, Z, front, sx, sy)] view-space. Near clip + screen clip every edge."""
    out = []
    for ei, (a, b) in enumerate(edges):
        va, vb = verts[a], verts[b]
        fa, fb_ = va[3], vb[3]
        if not fa and not fb_:
            continue
        pts = []
        for (me, other) in ((va, vb), (vb, va)):
            if me[3]:
                pts.append((me[4], me[5]))
            else:
                # me behind, other front: clip to z = ZCLIP
                n = ZCLIP - me[2]
                d = other[2] - me[2]
                X = me[0] + lerp(other[0] - me[0], n, d)
                Y = me[1] + lerp(other[1] - me[1], n, d)
                pts.append((CX + smul16(X, FOCAL // 2), CY - smul16(Y, FOCAL // 2)))
        r = clip_line(pts[0][0], pts[0][1], pts[1][0], pts[1][1])
        if r is not None:
            out.append((ei,) + r)
    return out


def render(cam_x, cam_z, yaw, cam_y=CAM_Y):
    fb = set()
    for seg in segments(cam_x, cam_z, yaw, cam_y):
        gl.ref_line(fb, *seg[1:])
    return fb


def fb_bytes(pixels):
    fbb = bytearray(3584)
    for (x, y) in pixels:
        fbb[(x >> 3) * 224 + y * 2] |= 0x80 >> (x & 7)
    return fbb


def fletcher(data):
    s1 = s2 = 0
    for b in data:
        s1 = (s1 + b) & 255
        s2 = (s2 + s1) & 255
    return (s2 << 8) | s1


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "room_tables.inc"), "w", newline="\n") as f:
        f.write("; Generated by tools/gbc_room.py - do not edit.\n")
        f.write('SECTION "tables", ROM0, ALIGN[8]\n')
        f.write("SinTab::\n")
        for i in range(0, 256, 16):
            f.write("    db " + ",".join("%d" % v for v in SIN[i:i + 16]) + "\n")
        f.write("RecipTab::\n")
        for i in range(0, 128, 8):
            f.write("    dw " + ",".join("%d" % v for v in RECIP[i:i + 8]) + "\n")
        sq = [(i * i) // 4 for i in range(512)]
        f.write("SqLo::\n")
        for i in range(0, 512, 16):
            f.write("    db " + ",".join("%d" % (v & 255) for v in sq[i:i + 16]) + "\n")
        f.write("SqHi::\n")
        for i in range(0, 512, 16):
            f.write("    db " + ",".join("%d" % (v >> 8) for v in sq[i:i + 16]) + "\n")
    with open(os.path.join(outdir, "scene.inc"), "w", newline="\n") as f:
        f.write("; Generated by tools/gbc_room.py - do not edit.\n")
        f.write("; Mesh record: nux, nuz, nc, nv, ne, ux[], uz[], cols (xid,zid)[], verts (col,y)[], edges (a,b)[]\n")
        f.write("TestSceneRec::\n")
        f.write("    db %d, %d, %d, %d, %d\n" % (len(UX), len(UZ), len(COLS), len(VERTS), len(EDGES)))
        f.write("    db %s\n" % ",".join(map(str, UX + UZ)))
        f.write("    db %s\n" % ",".join(str(v) for c in COLS for v in c))
        f.write("    db %s\n" % ",".join(str(v) for c in VERTS for v in c))
        f.write("    db %s\n" % ",".join(str(v) for c in EDGES for v in c))
    with open(os.path.join(outdir, "poses.inc"), "w", newline="\n") as f:
        f.write("; Generated by tools/gbc_room.py - do not edit.\n")
        f.write("DEF NumPoses EQU %d\nEXPORT NumPoses\nPoses::\n" % len(poses()))
        for (x, z, yaw) in poses():
            f.write("    dw %d, %d\n    db %d, 0\n" % (x, z, yaw))
        f.write("DEF NumMoveSteps EQU %d\nEXPORT NumMoveSteps\nMoveScript::\n" % len(move_script()))
        for (joy, dt) in move_script():
            f.write("    db %d, %d\n" % (joy, dt))
        f.write("MoveStart::\n    dw %d, %d\n    db %d\n" % MOVE_START[:3])


if __name__ == "__main__":
    main()
