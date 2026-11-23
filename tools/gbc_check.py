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
    subprocess.run(args, timeout=60)
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
    bg = img.getpixel((0, 0))
    if live:
        yaw = LIVE_YAW_STEP * (LIVE_FRAMES - 1)
        expect = gr.render(LIVE_CAM[0], LIVE_CAM[1], yaw)
        print("live: expecting yaw %d" % yaw)
    else:
        expect = gl.reference_frame()
    got = set()
    for y in range(gl.VIEW_H):
        for x in range(gl.VIEW_W):
            if img.getpixel((VIEW_X0 + x, y)) != bg:
                got.add((x, y))
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
             list(range(VIEW_X0 + gl.VIEW_W, 160)) if img.getpixel((x, y)) != bg]
    print("stray border px:", len(stray))
    ok = not missing and not extra and not stray
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
