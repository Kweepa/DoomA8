#!/usr/bin/env python3
"""Enemy line of sight on the GBC (gbc/ai.asm LineSolidsBlocked) vs a Python port of the A8 segment
code (src/util.asm line_solids_blocked, line_hit_box, .slope_one).

  gbc_losunit.py        generate the cases, build `losunit`, run it headless, compare

Cases: in every room of every level, random segments inside the room box plus segments through the
middle of each solid (cutouts, crates, solid platforms, elevators, slopes), as an enemy at mid-body
looking at the player's eye would make them. One result byte per case (1 = blocked).

lerpdv here is exact (floor, magnitude capped at 127) like the GBC routine; the A8 uses a log table.
"""
import os
import random
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gbc_genmap as gmap  # noqa: E402
import gbc_world as gw  # noqa: E402

ROOT = os.path.dirname(HERE)
MAX_CASES = 1000                     # one result byte each in wPoseOut (1024)


def s8(v):
    v &= 255
    return v - 256 if v >= 128 else v


def lerpdv(a, b, c):
    a, b, c = s8(a), s8(b), s8(c)
    if a == 0 or b == 0 or c == 0:
        return 0
    q = min((abs(a) * abs(b)) // abs(c), 127)
    return (-q) & 255 if (a < 0) ^ (b < 0) ^ (c < 0) else q


def face_mul7(t, d):
    d = s8(d)
    m = ((abs(d) * t + 64) >> 7) & 255
    return (-m) & 255 if d < 0 else m


class Seg:
    def __init__(self, a, b):
        self.a, self.b = list(a), list(b)
        self.box = [0] * 6
        self.m = [0] * 3

    def box_max(self):
        self.m = [(self.box[i] + self.box[i + 3]) & 255 for i in range(3)]

    def overlap(self):
        for i in range(3):
            lo, hi = sorted((self.a[i], self.b[i]))
            if hi < self.box[i] or lo >= self.m[i]:
                return False
        return True

    def outcode(self, p):
        oc = 0
        for i in range(3):
            if p[i] < self.box[i]:
                oc |= 1 << (2 * i)
            if p[i] >= self.m[i]:
                oc |= 2 << (2 * i)
        return oc

    def t_plane(self, f, plane):
        e = self.a[f]
        d = (self.b[f] - e) & 255
        if d == 0:
            return None
        return lerpdv((plane - e) & 255, 127, d)

    def face_hit(self, f, t):
        for c in range(3):
            if c == f:
                continue
            e = self.a[c]
            v = (face_mul7(t, (self.b[c] - e) & 255) + e) & 255
            if v < self.box[c] or v >= self.m[c]:
                return False
        return True

    def hit_box(self):
        self.box_max()
        if not self.overlap():
            return False
        oc0, oc1 = self.outcode(self.a), self.outcode(self.b)
        if oc0 & oc1:
            return False
        best = 255
        for bit in (1, 2, 4, 8, 16, 32):
            if not (oc0 ^ oc1) & bit:
                continue
            axis = 0 if bit < 4 else (1 if bit < 16 else 2)
            plane = self.m[axis] if bit & 0x2A else self.box[axis]
            t = self.t_plane(axis, plane)
            if t is None or t == 0 or t & 0x80 or t >= best:
                continue
            if self.face_hit(axis, t):
                best = t
        return best != 255

    def pt_at(self, t, c):
        e = self.a[c]
        return (lerpdv((self.b[c] - e) & 255, t, 127) + e) & 255

    def clamp(self, v, c):
        if v < self.box[c]:
            return self.box[c]
        if v >= self.m[c]:
            return self.m[c] - 1 if self.m[c] else 0
        return v

    def xz_clip(self):
        self.t0, self.t1 = 0, 127
        self.box_max()
        for c in (0, 2):
            e = self.a[c]
            d = (self.b[c] - e) & 255
            if d == 0:
                if not (self.box[c] <= e < self.m[c]):
                    return False
                continue
            t = lerpdv((self.box[c] - e) & 255, 127, d)
            (self._lower if d & 0x80 else self._raise)(t)
            t = lerpdv((self.m[c] - e) & 255, 127, d)
            (self._raise if d & 0x80 else self._lower)(t)
            if not self.t0 <= self.t1:
                return False
        return True

    def _raise(self, t):
        if not t & 0x80 and t >= self.t0:
            self.t0 = t

    def _lower(self, t):
        if t & 0x80:
            self.t0, self.t1 = 1, 0
        elif t < self.t1:
            self.t1 = t


def slope_one(L, room, X, sg):
    if L.f("slope_sx", X) == 0:
        return False
    sg.box = [L.f("slope_x", X), 0, L.f("slope_z", X), L.f("slope_sx", X), 0, L.f("slope_sz", X)]
    if not sg.xz_clip():
        return False

    def h_at(t):
        px = sg.clamp(sg.pt_at(t, 0), 0)
        pz = sg.clamp(sg.pt_at(t, 2), 2)
        P = gw.Player(L, room, px << 8, pz << 8, 0, 0, 0)
        return gw.slope_height(P, X, 0)[0]
    h0, h1 = h_at(sg.t0), h_at(sg.t1)
    rel0 = (sg.pt_at(sg.t0, 1) - h0) & 255
    rel1 = (sg.pt_at(sg.t1, 1) - h1) & 255
    if rel0 == 0:
        s = 0
    elif rel1 == 0:
        s = 127
    else:
        if not (rel0 ^ rel1) & 0x80:
            return False
        s = lerpdv(rel0, 127, (rel0 - rel1) & 255)
        if s == 0 or s & 0x80:
            return False
    t = (lerpdv((sg.t1 - sg.t0) & 255, s, 127) + sg.t0) & 255
    return t != 0 and not t & 0x80


def solids(L, room):
    """Boxes in line_solids_blocked order (slopes separately), as the GBC reads them."""
    out = []
    for k in range(2):
        i = room * 2 + k
        if L.f("rb_sx", i):
            out.append([L.f(n, i) for n in ("rb_x", "rb_y", "rb_z", "rb_sx", "rb_sy", "rb_sz")])
    for c in range(L.ncrates):
        if L.f("crate_room", c) == room and L.f("crate_sx", c):
            out.append([L.f(n, c) for n in ("crate_x", "crate_y", "crate_z", "crate_sx", "crate_sy", "crate_sz")])
    lo, hi = gw.slice_of(L, "room_plat_o", room)
    for p in range(lo, hi):
        if L.f("plat_solid", p):
            out.append([L.f("plat_x", p), L.f("plat_y", p), L.f("plat_z", p), L.f("plat_sx", p), 0, L.f("plat_sz", p)])
    for e in range(L.p[6]):
        if L.f("elev_room", e) == room:
            out.append([L.f(n, e) for n in ("elev_x", "elev_y0", "elev_z", "elev_sx", "elev_sy", "elev_sz")])
    return out


def blocked(L, room, a, b):
    sg = Seg(a, b)
    for box in solids(L, room):
        sg.box = list(box)
        if sg.hit_box():
            return True
    lo, hi = gw.slice_of(L, "room_slope_o", room)
    for X in range(lo, hi):
        if slope_one(L, room, X, sg):
            return True
    sg.box = [L.f(n, room) for n in ("room_x", "room_y", "room_z", "room_sx", "room_sy", "room_sz")]
    return sg.hit_box()


def levels():
    out = []
    for key in gmap.gm.LEVEL_NAMES:
        lv = gmap.gm.load_level(key)
        if any(o.get("kind") == "spawn" for o in (lv.get("objects") or [])):
            out.append(gw.Level(gmap.gm.cook_one(lv, key)))
    return out


def cases():
    rnd = random.Random(1234)
    out = []
    for li, L in enumerate(levels()):
        for room in range(L.nrooms):
            rx, ry, rz = L.f("room_x", room), L.f("room_y", room), L.f("room_z", room)
            sx, sy, sz = L.f("room_sx", room), L.f("room_sy", room), L.f("room_sz", room)

            def pick():
                return [rx + rnd.randrange(max(sx, 1)), ry + rnd.randrange(max(sy, 1)), rz + rnd.randrange(max(sz, 1))]
            segs = [(pick(), pick()) for _ in range(2)]
            lo, hi = gw.slice_of(L, "room_slope_o", room)
            targets = solids(L, room) + [[L.f(n, X) for n in ("slope_x", "slope_y", "slope_z", "slope_sx", "slope_sy", "slope_sz")]
                                          for X in range(lo, hi)]
            for box in targets:
                mid = [(box[i] + box[i + 3] // 2) & 255 for i in range(3)]
                a = pick()
                b = [(2 * mid[i] - a[i]) & 255 for i in range(3)]          # through the middle
                b = [min(max(b[0], rx), rx + sx - 1), min(max(b[1], ry), ry + sy - 1), min(max(b[2], rz), rz + sz - 1)]
                segs.append((a, b))
            for a, b in segs:
                out.append((li, room, a, b))
    if len(out) > MAX_CASES:
        rnd.shuffle(out)
        out = sorted(out[:MAX_CASES], key=lambda c: (c[0], c[1]))
    return out


def write_inc(cs):
    lines = ["; Generated by tools/gbc_losunit.py - do not edit.",
             "DEF NumLosCases EQU %d" % len(cs), "EXPORT NumLosCases",
             'SECTION "loscases", ROMX', "LosCases::"]
    for (li, room, a, b) in cs:
        lines.append("    db %d, %d, %s" % (li, room, ", ".join(str(v & 255) for v in a + b)))
    open(os.path.join(ROOT, "gbc", "build", "losunit.inc"), "w", newline="\n").write("\n".join(lines) + "\n")


def main():
    cs = cases()
    write_inc(cs)
    subprocess.run(["cmd", "/c", os.path.join(ROOT, "build-gbc.bat"), "los"], check=True, stdout=subprocess.DEVNULL)
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_los.gbc")
    state = os.path.join(ROOT, "gbc", "build", "los.sna")
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    addr = None
    for line in open(os.path.splitext(rom)[0] + ".sym"):
        if line.strip().endswith(" MainLoop"):
            addr = line.split()[0].split(":")[1]
    if os.path.exists(state):
        os.remove(state)
    subprocess.run([bgb, "-hf", "-nobatt", "-rom", rom, "-br", addr, "-stateonexit", state], timeout=10)
    data = open(state, "rb").read()
    i = data.find(b"POSE")
    base = i + 4 + 2
    Ls = levels()
    bad = []
    nblk = 0
    for k, (li, room, a, b) in enumerate(cs):
        exp = 1 if blocked(Ls[li], room, a, b) else 0
        nblk += exp
        got = data[base + k]
        if got != exp:
            bad.append((k, li, room, a, b, got, exp))
    print("los cases: %d (%d blocked), mismatches: %d" % (len(cs), nblk, len(bad)))
    for x in bad[:10]:
        print("  #%d level %d room %d %s -> %s got %d expected %d" % x)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
