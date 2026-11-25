#!/usr/bin/env python3
"""Extract intermission patches (WIMAP0, WISPLAT, WIURH0, WIURH1) from ref/DOOM.WAD to PNG (+ raw lumps)."""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WAD = ROOT / "ref" / "DOOM.WAD"
OUT = ROOT / "ref" / "wi"
NAMES = ["WIMAP0", "WISPLAT", "WIURH0", "WIURH1"]


def lumps(data: bytes) -> dict[str, bytes]:
	_, n, dofs = struct.unpack_from("<4sII", data, 0)
	d = {}
	for i in range(n):
		fp, sz, nm = struct.unpack_from("<II8s", data, dofs + i * 16)
		d[nm.split(b"\0")[0].decode("ascii").upper()] = data[fp : fp + sz]
	return d


def decode_patch(p: bytes, pal: list[tuple[int, int, int]]) -> Image.Image:
	w, h, _lo, _to = struct.unpack_from("<HHhh", p, 0)
	im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
	px = im.load()
	for x in range(w):
		o = struct.unpack_from("<I", p, 8 + 4 * x)[0]
		while p[o] != 0xFF:
			top, cnt = p[o], p[o + 1]
			for k in range(cnt):
				px[x, top + k] = pal[p[o + 3 + k]] + (255,)
			o += cnt + 4
	return im


def main() -> None:
	L = lumps(WAD.read_bytes())
	pp = L["PLAYPAL"]
	pal = [tuple(pp[i * 3 : i * 3 + 3]) for i in range(256)]
	OUT.mkdir(exist_ok=True)
	for n in NAMES:
		(OUT / f"{n}.lmp").write_bytes(L[n])
		im = decode_patch(L[n], pal)
		im.save(OUT / f"{n}.png")
		print(n, im.size)


if __name__ == "__main__":
	main()
