#!/usr/bin/env python3
"""Run the GBC world-test ROM headless in BGB: a scripted walk in every room of every level
(collision, floor following, slopes, gravity, ledge unstick) compared with tools/gbc_world.py.

Needs build-gbc.bat world first. Usage: gbc_worldtest.py [--show N]  (show spec trace of test N)
"""
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_genmap as gmap  # noqa: E402
import gbc_world as gw  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_world.gbc")
    state = os.path.join(ROOT, "gbc", "build", "world.sna")
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    addr = None
    for line in open(os.path.splitext(rom)[0] + ".sym"):
        if line.strip().endswith(" MainLoop"):
            addr = line.split()[0].split(":")[1]
    if os.path.exists(state):
        os.remove(state)
    subprocess.run([bgb, "-hf", "-nobatt", "-rom", rom, "-br", addr, "-stateonexit", state], timeout=300)
    data = open(state, "rb").read()
    i = data.find(b"POSE")
    if i < 0:
        sys.exit("POSE block not found in state")
    a, b = gw.wslice()
    tests = gw.world_tests()[a:b]
    script = gw.walk_script()
    steps = os.environ.get("GBC_STEPS")
    if steps:
        script = script[:int(steps)]
    levels = {}
    li = 0
    for key in gmap.gm.LEVEL_NAMES:
        lv = gmap.gm.load_level(key)
        if not any(o.get("kind") == "spawn" for o in (lv.get("objects") or [])):
            continue
        levels[li] = gw.Level(gmap.gm.cook_one(lv, key))
        li += 1
    base = i + 4 + 2
    bad = []
    for k, t in enumerate(tests):
        (chk, camx, _, _), P = gw.run_test(levels[t[0]], t, script)
        got = struct.unpack("<HH", data[base + 4 * k:base + 4 * k + 4])
        if got != (chk, camx):
            bad.append((k, t[0], t[1], got, (chk, camx)))
    print("world tests: %d, mismatches: %d" % (len(tests), len(bad)))
    if os.environ.get("GBC_WORLDTIME"):
        (ticks,) = struct.unpack("<H", data[i + 4:i + 6])
        steps_total = len(tests) * len(script)
        per = ticks * 64 / steps_total
        print("timing: %d steps in %d M-cycles = %.0f M-cycles/step including ~300 of test overhead "
              "(%.1f%% of a 60 Hz frame)" % (steps_total, ticks * 64, per, 100 * per / 35112))
    dbg = i + 4 + 2 + 1024 + 8 + 2 + 1 + 400
    for k in range(min(4, len(tests))):
        _, P = gw.run_test(levels[tests[k][0]], tests[k], script)
        got = struct.unpack("<HHHBBBBBB", data[dbg + 12 * k:dbg + 12 * k + 12])
        print("  test %d asm  x=%04X z=%04X y=%04X floor=%d/%d flags=%d yaw=%d vel=%02X%02X" % ((k,) + got))
        print("         spec x=%04X z=%04X y=%04X floor=%d/%d flags=%d yaw=%d vel=%04X" %
              (P.cam_x, P.cam_z, P.cam_y, P.floor_y, P.floor_yl, P.falling | (P.floor_slope << 1), P.yaw, P.fall_vel))
    for b in bad[:12]:
        print("  #%d level %d room %d got (%04X,%04X) expected (%04X,%04X)" %
              (b[0], b[1], b[2], b[3][0], b[3][1], b[4][0], b[4][1]))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
