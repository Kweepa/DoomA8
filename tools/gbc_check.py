#!/usr/bin/env python3
"""Run a GBC test ROM headless in BGB and compare the screen to the reference.

  gbc_check.py          static line pattern (build-gbc.bat test), break at MainLoop
  gbc_check.py --live   spinning-room demo, 3 frames (build-gbc.bat live), break at LiveStop;
                        checks the double-buffered, HBlank-DMA'd frame against the spec render

BGB path from env GBEMU (default C:\\dev\\tools\\bgb\\bgb64.exe).
"""
import os
import subprocess
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_genlines as gl  # noqa: E402
import gbc_room as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW_X0 = 16          # map column 2 * 8

LIVE_CAM = (22 * 256 + 77, 20 * 256 + 5)
LIVE_FRAMES = 6
LIVE_YAW_STEP = 2


def main():
    live = "--live" in sys.argv
    name = "doomgbc_live" if live else "doomgbc_test"
    label = "LiveStop" if live else "MainLoop"
    rom = os.path.join(ROOT, "gbc", "build", name + ".gbc")
    shot = os.path.join(ROOT, "gbc", "build", name + "_screen.bmp")
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    if os.path.exists(shot):
        os.remove(shot)
    # Headless BGB exits when it would break to the debugger.
    addr = None
    for line in open(os.path.splitext(rom)[0] + ".sym"):
        if line.strip().endswith(" " + label):
            addr = line.split()[0].split(":")[1]
    if addr is None:
        sys.exit(label + " not found in sym file")
    state = os.path.join(ROOT, "gbc", "build", name + ".sna")
    args = [bgb, "-hf", "-nobatt", "-rom", rom, "-br", addr, "-screenonexit", shot]
    if live:
        args += ["-stateonexit", state]
    subprocess.run(args, timeout=10)
    if live:
        d = open(state, "rb").read()
        i = d.find(b"LIVE")
        if i >= 0:
            fr = list(d[i + 6:i + 6 + LIVE_FRAMES])      # skip wPoseTicks
            diffs = [(b - a) & 255 for a, b in zip(fr, fr[1:])]
            print("VBlanks per demo iteration:", diffs,
                  "-> ~%.1f fps" % (59.7275 / (sum(diffs) / len(diffs))))
    img = Image.open(shot).convert("RGB")
    print("screenshot", img.size)
    # Viewport paper (room colour, palette 0) and border colour (palette 1) differ: the paper is the
    # most common viewport colour, the border is the top-left pixel.
    from collections import Counter
    bg = Counter(img.getpixel((VIEW_X0 + x, y)) for y in range(gl.VIEW_H) for x in range(gl.VIEW_W)).most_common(1)[0][0]
    border = img.getpixel((0, 0))
    if live:
        # E1M1 spawn room: room mesh + objects + things + enemies, camera at the spawn point.
        import gbc_scene as gsc
        sd = gsc.SceneData("E1M1")
        payload = sd.L.p
        sx, sy, sz, rot, sroom = payload[17], payload[18], payload[19], payload[20], payload[21]
        yaw = (rot * 32) & 255
        spin = 0
        ens = sd.enemy_list()
        d = open(state, "rb").read()
        i = d.find(b"LIVE")
        if i >= 0:
            spin = d[i + 6 + 8]                      # wItemSpin high byte at LiveStop (wPoseOut[8])
            frames = d[i + 6 + 16:i + 6 + 40]        # wEnFrame at LiveStop (wPoseOut[16..39])
            for k, e in enumerate(ens):
                e["frame"] = frames[k]
        expect = gsc.scene_pixels(sd, sroom, (sx + 1) * 256, (sz + 1) * 256, (sy + 3) * 256, yaw, spin, enemies=ens)
        print("live: E1M1 spawn room %d, cam (%d,%d,%d) yaw %d spin %d" % (sroom, sx + 1, sy + 3, sz + 1, yaw, spin))
    else:
        expect = gl.reference_frame()
    got = set()
    weapon_got = set()
    for y in range(gl.VIEW_H):
        for x in range(gl.VIEW_W):
            c = img.getpixel((VIEW_X0 + x, y))
            if c != bg:
                if live and min(c) >= 248:           # OBJ palette 0 ink (white): the weapon sprite
                    weapon_got.add((x, y))
                else:
                    got.add((x, y))
    if live:
        import gbc_genwpn as gw
        name = "PISTOL"                             # WpnInit selects the pistol; no input in the test
        bits = gw.scale(gw.load_ink("pistol_lines.png"))
        h, w = len(bits), len(bits[0])
        ox, oy = (128 - w) // 2, 112 - h + 6      # pistol rests 6 rows past the bottom (OVERHANG_PISTOL); STAT clips at 112
        weapon_exp = {(ox + x, oy + y) for y in range(h) for x in range(w) if bits[y][x]}
        weapon_exp = {(x, y) for (x, y) in weapon_exp if 0 <= x < 128 and 0 <= y < 112}
        wmiss, wextra = sorted(weapon_exp - weapon_got), sorted(weapon_got - weapon_exp)
        print("weapon sprite: expected %d px, drawn %d, missing %d, extra %d" %
              (len(weapon_exp), len(weapon_got), len(wmiss), len(wextra)))
        # the sprite covers room lines under it
        expect = expect - weapon_exp
        if wmiss or wextra:
            print("  weapon missing e.g.", wmiss[:8], "extra e.g.", wextra[:8])
            wfail = True
        else:
            wfail = False
    missing = sorted(expect - got)
    extra = sorted(got - expect)
    print("expected %d px, drawn %d px, missing %d, extra %d" %
          (len(expect), len(got), len(missing), len(extra)))
    if missing:
        print("missing e.g.", missing[:10])
    if extra:
        print("extra e.g.", extra[:10])
    # Border columns must be untouched background.
    stray = [(x, y) for y in range(gl.VIEW_H) for x in list(range(0, VIEW_X0)) +
             list(range(VIEW_X0 + gl.VIEW_W, 160)) if img.getpixel((x, y)) != border]
    print("stray border px:", len(stray))
    ok = not missing and not extra and not stray and not (live and wfail)
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
