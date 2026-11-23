#!/usr/bin/env python3
"""Run the GBC bench ROM headless in BGB and print timings.

Needs build-gbc.bat bench first. Reads the BNCH result block out of a BGB state file.
"""
import os
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TICK_MCYCLES = 64               # TAC = clock/256
FRAME_MCYCLES_DS = 35112        # 70224 dots, double speed M-cycles (2.097 MHz)
MCYCLE_US = 1e6 / 2097152.0


def main():
    rom = os.path.join(ROOT, "gbc", "build", "doomgbc_bench.gbc")
    state = os.path.join(ROOT, "gbc", "build", "bench.sna")
    bgb = os.environ.get("GBEMU", r"C:\dev\tools\bgb\bgb64.exe")
    addr = None
    for line in open(os.path.splitext(rom)[0] + ".sym"):
        if line.strip().endswith(" MainLoop"):
            addr = line.split()[0].split(":")[1]
    if os.path.exists(state):
        os.remove(state)
    subprocess.run([bgb, "-hf", "-nobatt", "-rom", rom, "-br", addr,
                    "-stateonexit", state], timeout=120)
    data = open(state, "rb").read()
    i = data.find(b"BNCH")
    if i < 0:
        sys.exit("BNCH block not found in state")
    w = struct.unpack("<8H", data[i + 4:i + 20])
    frame, b1, b2, b3, a_de, a_ticks, b_de, b_ticks = w
    print("raw words:", w)
    print("ticks/frame measured: %d  (expect %d if tick = 64 M-cycles, double speed)"
          % (frame, FRAME_MCYCLES_DS // TICK_MCYCLES))

    def mc(ticks):
        return ticks * TICK_MCYCLES

    px = 4022 * 10
    print("lines : %d px in %d M-cycles = %.1f M-cycles/px, %.0f px/frame at full budget"
          % (px, mc(b1), mc(b1) / px, FRAME_MCYCLES_DS / (mc(b1) / px)))
    print("        74-line set = %.0f M-cycles (%.2f ms)"
          % (mc(b1) / 10, mc(b1) / 10 * MCYCLE_US / 1000))
    print("clear : %.0f M-cycles per 4 KB (%.2f ms, %.1f%% of a frame)"
          % (mc(b2) / 50, mc(b2) / 50 * MCYCLE_US / 1000, 100 * mc(b2) / 50 / FRAME_MCYCLES_DS))
    print("gdma  : %.0f M-cycles per 4 KB (%.2f ms, %.1f%% of a frame)"
          % (mc(b3) / 50, mc(b3) / 50 * MCYCLE_US / 1000, 100 * mc(b3) / 50 / FRAME_MCYCLES_DS))
    base_rate = a_de * 10 / mc(a_ticks)           # spin M-cycles per elapsed M-cycle
    dma_rate = b_de * 10 / mc(b_ticks)
    print("hdma  : 4 KB in HBlank mode took %d M-cycles (%.2f frames); CPU spin "
          "availability %.0f%% vs %.0f%% baseline"
          % (mc(b_ticks), mc(b_ticks) / FRAME_MCYCLES_DS, 100 * dma_rate, 100 * base_rate))


if __name__ == "__main__":
    main()
