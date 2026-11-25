#!/usr/bin/env python3
"""Intermission screenshots: builds the INTERTEST ROM per scene and runs it headless in BGB (as gbc_check.py).

  gbc_intercheck.py            scenes: stats mid-count, stats final, map, entering (blink on), the game 30 frames after
Writes gbc/build/inter_<scene>.png (3x). The test ROM fakes an exit from the third level (7 kills, 12 items, 95 s) and
presses A by itself at frame 200 / 250 of each screen; GBC_DEFS selects the screen (INTER_SCR) and frame (INTER_BRK)
whose breakpoint label ImDbgBreak the screenshot is taken at.
"""
import os
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES = [("stats_mid", 1, 120), ("stats_final", 1, 230), ("map", 2, 100), ("entering", 3, 100), ("game", 0, 0)]


def main():
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_inter.gbc")
    for name, scr, brk in SCENES:
        label = " ImDbgGame" if name == "game" else " ImDbgBreak"
        env = dict(os.environ, GBC_DEFS="-D INTER_SCR=%d -D INTER_BRK=%d" % (scr, brk))
        r = subprocess.run(["cmd", "/c", os.path.join(ROOT, "build-gbc.bat"), "inter"], cwd=ROOT, env=env, capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout + r.stderr)
        addr = bank = None
        for line in open(os.path.splitext(rom)[0] + ".sym"):
            if line.strip().endswith(label):
                bank, addr = line.split()[0].split(":")
        shot = os.path.join(ROOT, "gbc", "build", "inter_%s.bmp" % name)
        if os.path.exists(shot):
            os.remove(shot)
        subprocess.run([bgb, "-hf", "-nobatt", "-rom", rom, "-br", "%s:%s" % (bank, addr), "-screenonexit", shot],
                       timeout=30)
        im = Image.open(shot).convert("RGB")
        im.resize((im.size[0] * 3, im.size[1] * 3), Image.NEAREST).save(shot.replace(".bmp", ".png"))
        print(name, im.size)


if __name__ == "__main__":
    main()
