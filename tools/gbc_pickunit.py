#!/usr/bin/env python3
"""Pickup rules on the GBC vs tools/gbc_game.py. Needs build-gbc.bat pick first."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_game as gg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_pick.gbc")
    state = os.path.join(ROOT, "gbc", "build", "pick.sna")
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
    seq = gg.pickup_unit_sequence()
    P = gg.PlayerState()
    bad = []
    base = i + 4 + 2
    for k, t in enumerate(seq):
        used = gg.apply_pickup(P, t)
        got = tuple(data[base + 11 * k:base + 11 * k + 11])
        want = P.tup() + (1 if used else 0,)
        if got != want:
            bad.append((k, t, got, want))
    print("pickup steps: %d, mismatches: %d, final %s" % (len(seq), len(bad), P.tup()))
    for b in bad[:8]:
        print("  step %d type %d got %s expected %s" % b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
