#!/usr/bin/env python3
"""Run the GBC map-test ROM headless in BGB: every room of every level, rendered from the room
centre at two yaws with its objects, pickups and enemies (Fletcher of the framebuffer compared
with tools/gbc_scene.py), plus FindRoom on every camera.

Needs build-gbc.bat map first.
"""
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_genmap as gmap  # noqa: E402
import gbc_room as gr  # noqa: E402
import gbc_scene as gsc  # noqa: E402
import gbc_world as gw  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


SLICE = 180


def main():
    if "GBC_MSLICE" not in os.environ:
        total = len(gmap.map_tests())
        rc = 0
        for a in range(0, total, SLICE):
            env = dict(os.environ, GBC_MSLICE="%d:%d" % (a, a + SLICE))
            subprocess.run(["cmd", "/c", os.path.join(ROOT, "build-gbc.bat"), "map"], check=True, env=env,
                           stdout=subprocess.DEVNULL)
            rc |= subprocess.run([sys.executable, os.path.abspath(__file__)], env=env).returncode
        sys.exit(rc)
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_map.gbc")
    state = os.path.join(ROOT, "gbc", "build", "map.sna")
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
    tests = gmap.map_tests()
    n = len(tests)
    words = struct.unpack("<%dH" % n, data[i + 6:i + 6 + 2 * n])
    # FindRoom results sit after wPoseOut (1024) + wCamSave (8) + wTestCnt (2) + wTestRoom (1).
    fbase = i + 4 + 2 + 1024 + 8 + 2 + 1
    finds = list(data[fbase:fbase + n])

    scenes = {}
    levels = {}
    li = 0
    for key in gmap.gm.LEVEL_NAMES:
        lv = gmap.gm.load_level(key)
        if not any(o.get("kind") == "spawn" for o in (lv.get("objects") or [])):
            continue
        scenes[li] = gsc.SceneData(key)
        levels[li] = scenes[li].L
        li += 1

    find_bad = []
    for k, (lv_, rm, cx, cz, cy, yaw) in enumerate(tests):
        L = levels[lv_]
        exp = 0xFF
        for r in range(L.nrooms):
            ok = True
            for pos, siz, val in (("room_x", "room_sx", cx >> 8), ("room_z", "room_sz", cz >> 8),
                                  ("room_y", "room_sy", cy >> 8)):
                if ((val - L.f(pos, r)) & 255) >= L.f(siz, r):
                    ok = False
                    break
            if ok:
                exp = r
                break
        if finds[k] != exp:
            find_bad.append((k, lv_, rm, finds[k], exp))
    print("FindRoom: %d tests, mismatches: %d" % (n, len(find_bad)))
    for b in find_bad[:10]:
        print("  #%d level %d room %d got %d expected %d" % b)

    bad = []
    for k, (lv_, rm, cx, cz, cy, yaw) in enumerate(tests):
        exp = gr.fletcher(gr.fb_bytes(gsc.scene_pixels(scenes[lv_], rm, cx, cz, cy, yaw, k & 255)))
        if words[k] != exp:
            bad.append((k, lv_, rm, yaw, words[k], exp))
    print("scene tests: %d (levels %d), mismatches: %d" % (n, li, len(bad)))
    for b in bad[:15]:
        print("  #%d level %d room %d yaw %d got %04X expected %04X" % b)
    sys.exit(1 if (bad or find_bad) else 0)


if __name__ == "__main__":
    main()
