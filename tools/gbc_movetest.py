#!/usr/bin/env python3
"""Script the pad through the GBC ApplyMove in headless BGB and compare camera x/z/yaw after
every step with tools/gbc_room.apply_move. Needs build-gbc.bat move first."""
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_room as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_move.gbc")
    state = os.path.join(ROOT, "gbc", "build", "move.sna")
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
    if i < 0:
        sys.exit("POSE block not found in state")
    script = gr.move_script()
    st = gr.MOVE_START
    bad = []
    base = i + 4 + 2
    for k, (joy, dt) in enumerate(script):
        st = gr.apply_move(st, joy, dt)
        got = struct.unpack("<HHB", data[base + 5 * k:base + 5 * k + 5])
        if got != st[:3]:
            bad.append((k, joy, dt, got, st))
    # input sampling cases (posetest.asm InputCases): [(pad, ticks)] -> 6 holds + hJoy
    cases = [[(0x04, 10), (0x05, 5)], [(0x2A, 7)], [(0x03, 3)], [(0x04, 60)],
             [(0x10, 1), (0x00, 2)], [(0xC8, 4), (0x00, 4)], [(0x04, 2)]]
    ibad = 0
    ibase = base + 5 * len(script)
    for n, segs in enumerate(cases):
        acc = [0] * 6
        latch = 0
        for pad, ticks in segs:
            for _ in range(ticks):
                latch |= pad & 0xD0
                for slot, bit in ((0, 2), (1, 3)):
                    acc[slot] = min(255, acc[slot] + (pad >> bit & 1))
                o = 4 if pad & 0x20 else 2
                acc[o] = min(255, acc[o] + (pad & 1))
                acc[o + 1] = min(255, acc[o + 1] + (pad >> 1 & 1))
        want = [min(48, a) for a in acc] + [segs[-1][0] | latch]
        got = list(data[ibase + 7 * n:ibase + 7 * n + 7])
        if got != want:
            ibad += 1
            print("  input case %d got %s expected %s" % (n, got, want))
    print("input cases: %d, mismatches: %d" % (len(cases), ibad))
    print("move steps: %d, mismatches: %d, final cam (%.2f, %.2f) yaw %d" %
          (len(script), len(bad), st[0] / 256, st[1] / 256, st[2]))
    for b in bad[:10]:
        print("  step %d joy %02X dt %d got %s expected %s" % b)
    sys.exit(1 if bad or ibad else 0)


if __name__ == "__main__":
    main()
