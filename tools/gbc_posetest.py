#!/usr/bin/env python3
"""Run the GBC pose-test ROM headless in BGB; compare per-pose framebuffer
checksums with the Python spec (tools/gbc_room.py) and report render timing.

Needs build-gbc.bat pose first.
"""
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_room as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TICK_MCYCLES = 64
FRAME_MCYCLES_DS = 35112
MCYCLE_US = 1e6 / 2097152.0


def s16(v):
    return v - 65536 if v >= 32768 else v


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_pose.gbc")
    state = os.path.join(ROOT, "gbc", "build", "pose.sna")
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    addr = None
    for line in open(os.path.splitext(rom)[0] + ".sym"):
        if line.strip().endswith(" MainLoop"):
            addr = line.split()[0].split(":")[1]
    if os.path.exists(state):
        os.remove(state)
    subprocess.run([bgb, "-hf", "-nobatt", "-rom", rom, "-br", addr,
                    "-stateonexit", state], timeout=10)
    data = open(state, "rb").read()
    i = data.find(b"POSE")
    if i < 0:
        sys.exit("POSE block not found in state")
    poses = gr.poses()
    n = len(poses)
    (ticks,) = struct.unpack("<H", data[i + 4:i + 6])
    words = struct.unpack("<%dH" % n, data[i + 6:i + 6 + 2 * n])
    bad = []
    for k, (x, z, yaw) in enumerate(poses):
        exp = gr.fletcher(gr.fb_bytes(gr.render(x, z, yaw)))
        if words[k] != exp:
            bad.append((k, (x, z, yaw), words[k], exp))
    print("poses: %d, checksum mismatches: %d" % (n, len(bad)))
    for k, p, got, exp in bad[:12]:
        print("  pose %d cam=(%d,%d) yaw=%d got %04X expected %04X" % (k, p[0], p[1], p[2], got, exp))
    # Timing: n renders, no clear.
    mc = ticks * TICK_MCYCLES
    per = mc / n
    print("render: %d poses in %d M-cycles = %.0f M-cycles/render (%.2f ms; %.1f%% of a 60 Hz frame)"
          % (n, mc, per, per * MCYCLE_US / 1000, 100 * per / FRAME_MCYCLES_DS))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
