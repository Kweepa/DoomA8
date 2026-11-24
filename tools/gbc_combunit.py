#!/usr/bin/env python3
"""AngleTo and PlayerDamage on the GBC vs tools/gbc_game.py. Needs build-gbc.bat comb first."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_game as gg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def s16(v):
    return v - 65536 if v >= 32768 else v


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_comb.gbc")
    state = os.path.join(ROOT, "gbc", "build", "comb.sna")
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
    ang, dmg = gg.comb_unit_cases()
    base = i + 4 + 2
    bad = []
    for k, (dx, dz) in enumerate(ang):
        exp = gg.angle_to(dx, dz)
        got = data[base + k]
        if got != exp:
            bad.append(("angle", k, (dx, dz), got, exp))
    off = base + len(ang)
    for k, (hp, ar, d, kind) in enumerate(dmg):
        exp = gg.player_damage(hp, ar, d, kind)
        got = (data[off + 3 * k], data[off + 3 * k + 1], data[off + 3 * k + 2])
        if got != exp:
            bad.append(("damage", k, (hp, ar, d, kind), got, exp))
    print("angle cases %d, damage cases %d, mismatches %d" % (len(ang), len(dmg), len(bad)))
    for b in bad[:10]:
        print("  ", b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
