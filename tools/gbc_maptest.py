#!/usr/bin/env python3
"""Run the GBC map-test ROM headless in BGB: every room of every level, rendered from the
room centre at two yaws, compared (Fletcher of the framebuffer) with the Python spec.

Needs build-gbc.bat map first.
"""
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_genmap as gmap  # noqa: E402
import gbc_room as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_map.gbc")
    state = os.path.join(ROOT, "gbc", "build", "map.sna")
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    addr = None
    for line in open(os.path.splitext(rom)[0] + ".sym"):
        if line.strip().endswith(" MainLoop"):
            addr = line.split()[0].split(":")[1]
    if os.path.exists(state):
        os.remove(state)
    subprocess.run([bgb, "-hf", "-nobatt", "-rom", rom, "-br", addr, "-stateonexit", state], timeout=120)
    data = open(state, "rb").read()
    i = data.find(b"POSE")
    if i < 0:
        sys.exit("POSE block not found in state")
    tests = gmap.map_tests()
    n = len(tests)
    words = struct.unpack("<%dH" % n, data[i + 6:i + 6 + 2 * n])

    # Rebuild the meshes in the same order as the cooker.
    meshes = {}
    li = 0
    for key in gmap.gm.LEVEL_NAMES:
        lv = gmap.gm.load_level(key)
        objs = lv.get("objects") or []
        if not any(o.get("kind") == "spawn" for o in objs):
            continue
        meshes[li] = [gmap.room_mesh(r) for r in objs if r.get("kind") == "room"]
        li += 1
    # FindRoom results sit 1041 bytes after the POSE magic (wPoseOut 1024 + wCamSave 8 + wTestCnt 2 + wTestRoom 1 + ...).
    finds = list(data[i + 4 + 2 + 1024 + 8 + 2 + 1:i + 4 + 2 + 1024 + 8 + 2 + 1 + n])
    payloads = {}
    offsets = {}
    fields = gmap.parse_bind_table()
    li = 0
    for key in gmap.gm.LEVEL_NAMES:
        lv = gmap.gm.load_level(key)
        if not any(o.get("kind") == "spawn" for o in (lv.get("objects") or [])):
            continue
        p = gmap.gm.cook_one(lv, key)
        _, offs, _ = gmap.field_offsets(p, fields)
        payloads[li] = p
        offsets[li] = {f: o for (f, o, _) in offs}
        li += 1
    find_bad = []
    for k, (lv_, rm, cx, cz, cy, yaw) in enumerate(tests):
        p, o = payloads[lv_], offsets[lv_]
        exp = 0xFF
        for r in range(p[0]):
            ok = True
            for pos, siz, val in (("room_x", "room_sx", cx >> 8), ("room_z", "room_sz", cz >> 8), ("room_y", "room_sy", cy >> 8)):
                if ((val - p[o[pos] + r]) & 255) >= p[o[siz] + r]:
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
        gr.set_scene(*meshes[lv_][rm])
        exp = gr.fletcher(gr.fb_bytes(gr.render(cx, cz, yaw, cy)))
        if words[k] != exp:
            bad.append((k, lv_, rm, yaw, words[k], exp))
    print("map tests: %d (levels %d), mismatches: %d" % (n, li, len(bad)))
    for b in bad[:15]:
        print("  #%d level %d room %d yaw %d got %04X expected %04X" % b)
    sys.exit(1 if (bad or find_bad) else 0)


if __name__ == "__main__":
    main()
