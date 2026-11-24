#!/usr/bin/env python3
"""Run the GBC entity-test ROM headless in BGB and compare per-case framebuffer checksums with
the Python spec (tools/gbc_entity.py). Needs build-gbc.bat ent first."""
import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gbc_entity as ge  # noqa: E402
import gbc_genent as gen  # noqa: E402
import gbc_room as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_ent.gbc")
    state = os.path.join(ROOT, "gbc", "build", "ent.sna")
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
    cases = gen.enttests()
    n = len(cases)
    words = struct.unpack("<%dH" % n, data[i + 6:i + 6 + 2 * n])
    bad = []
    for k, c in enumerate(cases):
        verts, edges, shift, radius = gen.mesh_of(*c[:3])
        px = ge.entity_pixels(c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], verts, edges, shift, radius)
        exp = gr.fletcher(gr.fb_bytes(px))
        if words[k] != exp:
            bad.append((k, c[:3], words[k], exp))
    print("entity cases: %d, mismatches: %d" % (n, len(bad)))
    for b in bad[:12]:
        print("  case %d kind/idx/frame %s got %04X expected %04X" % b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
