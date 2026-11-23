#!/usr/bin/env python3
"""Run the GBC test ROM headless in BGB and compare the screen to the reference.

Usage: gbc_check.py [rom] [--shot out.png]
Needs build-gbc.bat test first. BGB path from env GBEMU (default C:\\dev\\tools\\bgb\\bgb64.exe).
"""
import os
import subprocess
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_genlines as gl  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW_X0 = 16          # map column 2 * 8


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_test.gbc")
    shot = os.path.join(ROOT, "gbc", "build", "test_screen.bmp")
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if args:
        rom = args[0]
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    if os.path.exists(shot):
        os.remove(shot)
    # Headless BGB exits when it would break to the debugger: break at MainLoop.
    sym = os.path.splitext(rom)[0] + ".sym"
    addr = None
    for line in open(sym):
        if line.strip().endswith(" MainLoop"):
            addr = line.split()[0].split(":")[1]
    if addr is None:
        sys.exit("MainLoop not found in " + sym)
    subprocess.run([bgb, "-hf", "-nobatt", "-rom", rom, "-br", addr,
                    "-screenonexit", shot], timeout=20)
    img = Image.open(shot).convert("RGB")
    print("screenshot", img.size)
    bg = img.getpixel((0, 0))
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
