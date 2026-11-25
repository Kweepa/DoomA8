#!/usr/bin/env python3
"""Menu music for the GBC port: the A8 menu tune (tools/genpokey.py front end) re-targeted to the GB APU.

Same SID emulation, voice model, pitch grid, (AD, SR) instrument table, LZ packing and player envelope as the A8
(tools/genpokey.py, src/a8music.asm); only the channel mapping and the column values change:
  SID voice 1 -> CH3 (the 32-sample square wave of gbc/sound.asm; it reaches 32 Hz, the A8 gives voice 1 the
  16-bit POKEY pair), voice 2 -> CH1 pulse, voice 3 -> CH2 pulse (50 % duty). Pulses below 64 Hz go up octaves.
  A voice in noise class plays on CH4 (NR43 by nearest LFSR clock to the SID noise rate, 15-bit); its tone
  channel is silent meanwhile.
Columns (one tick = mask byte + changed columns):
    0 lo CH1  1 lo CH2  2 lo CH3   (period low byte; NR43 when the voice is noise)
    3 hi CH1 | hi CH2 << 4         4 hi CH3
    5 E CH1   6 E CH2   7 E CH3    (retrig<<7 | gate<<6 | class<<4 | inst, class 0 tone, 2 noise, 3 silent)
Blob: ninst, (AD, SR) * ninst, LZ tokens (genpokey format). The ring is 4 KB.

Writes <outdir>/music.inc. Skipped when it is newer than the tune and both generator scripts.
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import genpokey as gp  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
GB_VBL_HZ = 4194304.0 / 70224.0          # 59.73 (double speed keeps the frame rate)
ORDER = (2, 0, 1)                         # SID voice 1, 2, 3 -> column channel (0 CH1, 1 CH2, 2 CH3)
GB_PULSE_VOL = 12                         # as tools/gbc_gensound.py / gbc/sound.asm SND_VOL_PULSE
BUDGET = 12000

SPF_GB = tuple(min(65535, int(round(256.0 * gp.PAL_PHI2 / GB_VBL_HZ / p))) for p in gp.RATE_PERIOD)


def die(msg):
    raise SystemExit("gbc_genmusic: " + msg)


def period(hz, ch):
    """GB 11-bit register value; CH3 runs a 32-sample wave (half the pulse clock)."""
    clk = 65536.0 if ch == 2 else 131072.0
    hz = max(hz, 1.0)
    while clk / hz > 2048:
        hz *= 2.0
    return max(0, min(2047, int(round(2048 - clk / hz))))


def nr43(hz):
    rate = max(hz * 16.0, 1.0)            # SID noise LFSR clock (genpokey noise_div)
    best = None
    for sh in range(14):
        for r in range(8):
            f = 262144.0 / ((r or 0.5) * (1 << sh))
            err = abs(f - rate) / rate
            if best is None or err < best[0]:
                best = (err, sh, r)
    return (best[1] << 4) | best[2]


def build_columns(frames, insts):
    cols = []
    st = [0, 0, 0]                        # per GB channel: period / NR43
    for row in frames:
        e = [0, 0, 0]
        for vi, (wc, hz, lvl, gate, rt, ad, sr) in enumerate(row):
            ch = ORDER[vi]
            cls = 3
            if wc and wc != "noise" and hz < gp.MIN_TONE_HZ:
                wc = None
            if wc:
                audible = lvl >= gp.AUDIBLE_LEVEL or rt
                if wc == "noise":
                    cls = 2
                    if audible:
                        st[ch] = nr43(hz)
                else:
                    cls = 0
                    if audible:
                        st[ch] = period(gp.quant_pitch(hz), ch)
            e[ch] = (rt << 7) | (gate << 6) | (cls << 4) | insts[(ad, sr)]
        cols.append((st[0] & 255, st[1] & 255, st[2] & 255,
                     (st[0] >> 8) | ((st[1] >> 8) << 4), st[2] >> 8, e[0], e[1], e[2]))
    return cols


def sparse_encode(cols, full_first=False):
    base = [0] * 8
    out = bytearray()
    for n, f in enumerate(cols):
        m = 0
        vals = bytearray()
        for i in range(8):
            v = f[i]
            chg = ((v & 0x7F) != base[i] or (v & 0x80)) if i >= 5 else v != base[i]
            if chg or (full_first and n == 0):
                m |= 1 << i
                vals.append(v)
            base[i] = (v & 0x7F) if i >= 5 else v
        out.append(m)
        out += vals
    return bytes(out)


def decode_ticks(blob, ninst):
    """Columns per tick, as the player sees them (intro, loop, loop)."""
    it = gp.lz_decode(blob[1 + 2 * ninst:])
    col = [0] * 8
    ticks = []
    for m in it:
        if isinstance(m, tuple):
            continue
        for i in range(8):
            if m >> i & 1:
                v = next(it)
                col[i] = v & 0x7F if i >= 5 else v
        ticks.append(tuple(col))
    return ticks


def main():
    outdir = Path(sys.argv[1])
    out = outdir / "music.inc"
    srcs = [gp.TUNE, Path(gp.__file__), Path(__file__)]
    if out.exists() and all(out.stat().st_mtime >= s.stat().st_mtime for s in srcs):
        print("gbc_genmusic: music.inc up to date")
        return
    tick_hz, init_writes, ticks, loop_start, loop_len = gp.emulate(gp.TUNE)
    ni, nl = loop_start + 1, loop_len
    total = ni + 3 * nl
    frames = gp.render_voices(tick_hz, init_writes, ticks, total, [k / tick_hz for k in range(total)])
    intro, body = frames[:ni], frames[ni + nl:ni + 2 * nl]
    insts = {}
    for row in intro + body:
        for r in row:
            insts.setdefault((r[5], r[6]), len(insts))
    if len(insts) > 16:
        die("%d envelope pairs (max 16)" % len(insts))
    cols = build_columns(intro + body, insts)
    noise2 = sum(1 for c in cols if sum(1 for e in c[5:] if (e >> 4) & 3 == 2) > 1)
    s_intro = sparse_encode(cols[:ni])
    s_loop = sparse_encode(cols[ni:], full_first=True)
    hdr = bytes((len(insts),)) + b"".join(bytes(k) for k in insts)
    blob = hdr + gp.pack_stream(s_intro, s_loop, gp.RING_BYTES - 1)
    got = decode_ticks(blob, len(insts))
    want = [tuple(c[:5]) + tuple(x & 0x7F for x in c[5:]) for c in cols] + \
           [tuple(c[:5]) + tuple(x & 0x7F for x in c[5:]) for c in cols[ni:]]
    if got != want:
        die("LZ round trip mismatch")
    if len(blob) > BUDGET:
        die("packed %d > budget %d" % (len(blob), BUDGET))
    rate = min(65535, int(round(tick_hz / GB_VBL_HZ * 65536.0)))
    print("gbc_genmusic: %s %.2f Hz, intro %d loop %d ticks, %d envelope pairs, %d ticks with 2+ noise voices, "
          "%d stream bytes -> %d packed" % (gp.TUNE.name, tick_hz, ni, nl, len(insts), noise2,
                                            len(s_intro) + len(s_loop), len(blob)))
    vol = [max(1, round(v * GB_PULSE_VOL / 15)) if v else 0 for v in range(16)]
    o = ["; Generated by tools/gbc_genmusic.py from %s - do not edit." % gp.TUNE.name,
         "DEF MUS_RATE EQU $%04X   ; ticks per VBlank, 0.16" % rate,
         "MusSpf:   ; envelope steps per VBlank, 8.8, by SID rate",
         "    dw " + ",".join("$%04X" % v for v in SPF_GB),
         "MusVolTab:   ; 0..15 -> GB pulse / noise volume (12 / 15, as the effects)",
         "    db " + ",".join("$%02X" % v for v in vol),
         "MusInst:   ; (AD, SR) per instrument",
         "    db " + ",".join("$%02X" % b for b in blob[1:1 + 2 * len(insts)]),
         "MusTokens:"]
    toks = blob[1 + 2 * len(insts):]
    for i in range(0, len(toks), 16):
        o.append("    db " + ",".join("$%02X" % b for b in toks[i:i + 16]))
    o.append("MusTokensEnd:")
    outdir.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(o) + "\n", encoding="ascii", newline="\n")
    print("gbc_genmusic: wrote %s" % out)


if __name__ == "__main__":
    main()
