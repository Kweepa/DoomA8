#!/usr/bin/env python3
"""Incremental DoomA8 build.

A step runs when an output is missing, an input is missing, or the newest
input is strictly newer than the oldest output. ``build-a8.bat`` is a thin
wrapper around this.

Two products are rewritten by a later step (map PRGs, and ``game.prg`` from
the label assemble). Those steps compare against a private output so a later
rewrite does not make the earlier step look stale forever.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
TOOLS = ROOT / "tools"
ENEMIES = ROOT / "enemies"
MAPS = ROOT / "maps"
STAMPS = ROOT / "build" / "stamps"

DOS = ["poss", "baron", "pinky", "imp"]
DISK_MAPS = [f"e1m{i}" for i in range(1, 8)]

SOURCE_RE = re.compile(
    r'(?m)^[ \t]*!(?:source|src|binary|bin)\s+"([^"]+)"'
)
CREDITS_DATE = re.compile(
    r"\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}"
)
MONTHS = (
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
)

# Rewritten after the AI label assemble. Leaving them in that step's inputs
# would rebuild the label pass on every run.
AI_LABEL_DROP = {
    (SRC / "level_prefix.asm").resolve(),
    (SRC / "enemy_sizes.asm").resolve(),
}


class Step:
    def __init__(
        self,
        name: str,
        inputs,
        outputs,
        run,
        *,
        anchor=None,
        also_stale=None,
    ):
        self.name = name
        self.inputs = inputs
        self.outputs = outputs
        self.run = run
        self.anchor = anchor
        self.also_stale = also_stale


def uniq(paths) -> list[Path]:
    out: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        out.append(resolved)
    return out


def asm_inputs(root: Path) -> list[Path]:
    """Root listing plus every transitive !source / !bin."""
    root = root.resolve()
    seen: set[Path] = set()
    ordered: list[Path] = []
    stack = [root]
    while stack:
        path = stack.pop()
        if path in seen:
            continue
        seen.add(path)
        ordered.append(path)
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for raw in SOURCE_RE.findall(text):
            stack.append((path.parent / raw).resolve())
    return ordered


def mtime_ns(path: Path) -> int:
    return path.stat().st_mtime_ns


def needs_build(step: Step) -> bool:
    if step.also_stale and step.also_stale():
        return True
    inputs = uniq(step.inputs())
    outputs = uniq(step.outputs())
    if any(not path.exists() for path in inputs):
        return True
    if any(not path.is_file() for path in outputs):
        return True
    newest = max(mtime_ns(path) for path in inputs)
    anchor = step.anchor() if step.anchor else None
    targets = [anchor.resolve()] if anchor is not None else outputs
    if any(not path.is_file() for path in targets):
        return True
    oldest = min(mtime_ns(path) for path in targets)
    return newest > oldest


def touch(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(path.read_bytes() if path.is_file() else b"")


def py(*args: str) -> None:
    subprocess.run([sys.executable, *args], cwd=ROOT, check=True)


def tool(script: str, *args: str) -> None:
    py(str(TOOLS / script), *args)


def find_acme() -> str:
    env = os.environ.get("ACME", "")
    if env and Path(env).is_file():
        return env
    found = shutil.which("acme")
    if found:
        return found
    raise SystemExit("ACME not found. Set ACME in setup-env.bat")


def acme(exe: str, args: list[str], moves: list[str] | None = None) -> None:
    subprocess.run([exe, *args], cwd=SRC, check=True)
    for name in moves or []:
        src = SRC / name
        if not src.is_file():
            raise SystemExit(f"missing {src}")
        dest = ROOT / name
        if dest.exists():
            dest.unlink()
        shutil.move(src, dest)


def run_checkaibanks() -> None:
    tool("checkaibanks.py")
    touch(STAMPS / "checkaibanks")


def run_mkreloc() -> None:
    tool("mkreloc.py", "--labels", "game.lbl")
    touch(STAMPS / "mkreloc")


def run_game_reloc(exe: str) -> None:
    acme(
        exe,
        ["-v3", "--vicelabels", str(ROOT / "game.lbl"), "doom64.asm"],
        ["game.prg"],
    )
    # This pass rewrites game.prg after mkreloc has already read it. The batch
    # file does not run mkreloc again on that binary, so the stamp stays fresh.
    touch(STAMPS / "mkreloc")


def run_ai_labels(exe: str) -> None:
    """Assemble GAME for labels only. ACME also writes src/game.prg; put that
    file back so the later GAME assemble is judged on its own output."""
    prg = SRC / "game.prg"
    saved = prg.read_bytes() if prg.is_file() else None
    stamp = prg.stat().st_mtime_ns if saved is not None else None
    try:
        acme(exe, ["-v3", "--vicelabels", str(ROOT / "game-ai.lbl"), "doom64.asm"])
    except Exception:
        (ROOT / "game-ai.lbl").unlink(missing_ok=True)
        raise
    finally:
        if saved is None:
            prg.unlink(missing_ok=True)
        else:
            prg.write_bytes(saved)
            os.utime(prg, ns=(stamp, stamp))


def credits_date_stale() -> bool:
    path = ROOT / "credits.txt"
    if not path.is_file():
        return True
    match = CREDITS_DATE.search(path.read_text(encoding="utf-8"))
    if match is None:
        return True
    today = date.today()
    stamp = f"{today.day} {MONTHS[today.month - 1]} {today.year}"
    return match.group(0) != stamp


def enemy_json() -> list[Path]:
    folder = ROOT / "editor" / "enemies"
    return [folder, *(folder / f"{dos}.json" for dos in DOS)]


def map_json() -> list[Path]:
    folder = ROOT / "editor" / "maps"
    return [folder, *(folder / f"e1m{i}.json" for i in range(1, 9))]


def weapon_pngs() -> list[Path]:
    folder = ROOT / "assets" / "weapons"
    if not folder.is_dir():
        return [folder]
    pics = [
        path
        for path in folder.iterdir()
        if path.is_file()
        and path.suffix.lower() == ".png"
        and path.name.lower() != "sheet.png"
    ]
    return [folder, *pics]


def ref_audio() -> list[Path]:
    return [ROOT / "ref" / "DOOM.WAD"]


def doom_sources(*, labels: bool) -> list[Path]:
    paths = asm_inputs(SRC / "doom64.asm")
    if not labels:
        return paths
    return [path for path in paths if path not in AI_LABEL_DROP]


def ai_sources(name: str) -> list[Path]:
    return asm_inputs(SRC / name)


def map_prgs() -> list[Path]:
    return [MAPS / f"{name}.prg" for name in DISK_MAPS]


def enemy_prgs() -> list[Path]:
    return [ENEMIES / f"{dos}.prg" for dos in DOS]


def steps(exe: str) -> list[Step]:
    doc = ROOT / "editor" / "doom64.json"
    return [
        Step(
            "gen_smc_tags",
            lambda: [TOOLS / "gen_smc_tags.py"],
            lambda: [SRC / "smc_tags.asm"],
            lambda: tool("gen_smc_tags.py"),
        ),
        Step(
            "gentables",
            lambda: [TOOLS / "gentables.py"],
            lambda: [SRC / "tables.asm", SRC / "sqtab.asm"],
            lambda: tool("gentables.py"),
        ),
        Step(
            "genscreens",
            lambda: [TOOLS / "genscreens.py"],
            lambda: [SRC / "screens.asm"],
            lambda: tool("genscreens.py"),
        ),
        Step(
            "genlinebodies",
            lambda: [TOOLS / "genlinebodies.py"],
            lambda: [SRC / "_a8line_bodies.asm"],
            lambda: tool("genlinebodies.py"),
        ),
        Step(
            "genrotate",
            lambda: [TOOLS / "genrotate.py"],
            lambda: [SRC / "_rotate_body.asm"],
            lambda: tool("genrotate.py"),
        ),
        Step(
            "genuifont",
            lambda: [
                TOOLS / "genuifont.py",
                ROOT / "ui" / "doomfont.png",
                ROOT / "ui" / "powerups.png",
            ],
            lambda: [SRC / "uifont_data.asm", SRC / "uifont.asm"],
            lambda: tool("genuifont.py"),
        ),
        Step(
            "genenemymuzzle",
            lambda: [
                TOOLS / "genenemymuzzle.py",
                TOOLS / "sprmask.py",
                *(ROOT / "assets" / "enemies" / f"enemy_muzzle_{i}.png" for i in range(3)),
            ],
            lambda: [SRC / "enemy_muzzle.asm"],
            lambda: tool("genenemymuzzle.py"),
        ),
        Step(
            "gensplat",
            lambda: [
                TOOLS / "gensplat.py",
                TOOLS / "sprmask.py",
                *(ROOT / "assets" / "weapons" / f"splat_{i}.png" for i in range(3)),
            ],
            lambda: [SRC / "splat_spr.asm"],
            lambda: tool("gensplat.py"),
        ),
        Step(
            "gensounds",
            lambda: [
                TOOLS / "gensounds.py",
                TOOLS / "pcsrc.py",
                *ref_audio(),
            ],
            lambda: [
                SRC / "pcsounds.asm",
                ENEMIES / "sound_ids.json",
            ],
            lambda: tool("gensounds.py"),
        ),
        Step(
            "genenemies",
            lambda: [
                TOOLS / "genenemies.py",
                TOOLS / "doommdl.py",
                doc,
                *enemy_json(),
                ENEMIES / "sound_ids.json",
            ],
            # Pose PRGs and enemy_sizes.asm are rewritten by genaibanks.
            lambda: [
                SRC / "enemy_data.asm",
                SRC / "enemy_data_blob.asm",
                *(ENEMIES / f"{dos}.pose" for dos in DOS),
                *(ENEMIES / f"{dos}.skel" for dos in DOS),
            ],
            lambda: tool("genenemies.py"),
        ),
        Step(
            "genmap",
            lambda: [TOOLS / "genmap.py", TOOLS / "roomgeom.py", *map_json()],
            # Map PRGs are rewritten by mkreloc. Counts/sizes are not.
            lambda: [SRC / "map_counts.asm", SRC / "map_sizes.asm", *map_prgs()],
            lambda: tool("genmap.py"),
        ),
        Step(
            "genitems",
            lambda: [TOOLS / "genitems.py", doc],
            lambda: [SRC / "item_mesh.asm"],
            lambda: tool("genitems.py"),
        ),
        Step(
            "genweapons",
            lambda: [
                TOOLS / "genweapons.py",
                TOOLS / "sprmask.py",
                doc,
                *weapon_pngs(),
            ],
            lambda: [SRC / "weapon_spr.asm"],
            lambda: tool("genweapons.py"),
        ),
        Step(
            "gen_menu_text",
            lambda: [
                TOOLS / "gen_menu_text.py",
                ROOT / "credits.txt",
                ROOT / "control.txt",
                ROOT / "order.txt",
                ROOT / "readthis.txt",
                ROOT / "ending.txt",
            ],
            lambda: [SRC / "menu_text.asm"],
            lambda: tool("gen_menu_text.py"),
            also_stale=credits_date_stale,
        ),
        Step(
            "gen_menu_title",
            lambda: [TOOLS / "gen_menu_title.py", ROOT / "ui" / "m_doom_c64.png"],
            lambda: [SRC / "menu_title.asm"],
            lambda: tool("gen_menu_title.py"),
        ),
        Step(
            "gen_menu_cursor",
            lambda: [
                TOOLS / "gen_menu_cursor_sprites.py",
                ROOT / "ui" / "m_skull_c64.png",
                ROOT / "ui" / "m_skull2_c64.png",
            ],
            lambda: [SRC / "menu_cursor_spr.asm"],
            lambda: tool("gen_menu_cursor_sprites.py"),
        ),
        Step(
            "gen_a8_cursor",
            lambda: [TOOLS / "gen_a8_cursor.py", SRC / "menu_cursor_spr.asm"],
            lambda: [SRC / "a8_cursor_tab.asm"],
            lambda: tool("gen_a8_cursor.py"),
        ),
        Step(
            "genpokey",
            lambda: [TOOLS / "genpokey.py", ROOT / "ref" / "At_Dooms_Gate_E1M1.sid"],
            lambda: [ROOT / "music" / "at_dooms_gate.asm"],
            lambda: tool("genpokey.py"),
        ),
        Step(
            "acme enemy_data_blob.asm",
            lambda: asm_inputs(SRC / "enemy_data_blob.asm"),
            lambda: [ROOT / "enemydata.prg"],
            lambda: acme(exe, ["enemy_data_blob.asm"], ["enemydata.prg"]),
        ),
        Step(
            "acme tables.asm",
            lambda: asm_inputs(SRC / "tables.asm"),
            lambda: [ROOT / "tab.prg"],
            lambda: acme(exe, ["tables.asm"], ["tab.prg"]),
        ),
        Step(
            "acme sqtab.asm",
            lambda: asm_inputs(SRC / "sqtab.asm"),
            lambda: [ROOT / "sqt.prg"],
            lambda: acme(exe, ["sqtab.asm"], ["sqt.prg"]),
        ),
        Step(
            "acme uifont.asm",
            lambda: asm_inputs(SRC / "uifont.asm"),
            lambda: [ROOT / "fnt.prg"],
            lambda: acme(exe, ["uifont.asm"], ["fnt.prg"]),
        ),
        Step(
            "acme overlay.asm",
            lambda: asm_inputs(SRC / "overlay.asm"),
            lambda: [SRC / "overlay.bin", ROOT / "overlay.lbl"],
            lambda: acme(exe, ["--vicelabels", str(ROOT / "overlay.lbl"), "overlay.asm"]),
        ),
        Step(
            "acme doom64.asm ai",
            lambda: doom_sources(labels=True),
            lambda: [ROOT / "game-ai.lbl"],
            lambda: run_ai_labels(exe),
        ),
        Step(
            "genaisymbols",
            lambda: [TOOLS / "genaisymbols.py", TOOLS / "mkreloc.py", ROOT / "game-ai.lbl"],
            lambda: [SRC / "ai_game_syms.asm"],
            lambda: tool("genaisymbols.py", "--labels", "game-ai.lbl"),
        ),
        *[
            Step(
                f"acme {asm}",
                lambda asm=asm: ai_sources(asm),
                lambda stem=stem: [ENEMIES / f"{stem}.bin", ENEMIES / f"{stem}.lbl"],
                lambda asm=asm, stem=stem: acme(
                    exe,
                    ["--vicelabels", str(ENEMIES / f"{stem}.lbl"), asm],
                ),
            )
            for asm, stem in (
                ("ai_poss.asm", "ai_poss"),
                ("ai_pinky.asm", "ai_pinky"),
                ("ai_baron.asm", "ai_baron"),
                ("ai_imp.asm", "ai_imp"),
                ("skel_draw.asm", "skel_draw"),
            )
        ],
        Step(
            "genaimeta",
            lambda: [
                TOOLS / "genaimeta.py",
                TOOLS / "mkreloc.py",
                SRC / "mem.asm",
                *(ENEMIES / f"ai_{dos}.bin" for dos in DOS),
                *(ENEMIES / f"ai_{dos}.lbl" for dos in DOS),
                ENEMIES / "skel_draw.bin",
                ENEMIES / "skel_draw.lbl",
            ],
            lambda: [
                *(ENEMIES / f"ai_{dos}.rel" for dos in DOS),
                ENEMIES / "skel_draw.rel",
            ],
            lambda: tool("genaimeta.py"),
        ),
        Step(
            "genaibanks",
            lambda: [
                TOOLS / "genaibanks.py",
                *(ENEMIES / f"{dos}.pose" for dos in DOS),
                *(ENEMIES / f"{dos}.skel" for dos in DOS),
                *(ENEMIES / f"ai_{dos}.bin" for dos in DOS),
                *(ENEMIES / f"ai_{dos}.rel" for dos in DOS),
                ENEMIES / "skel_draw.bin",
                ENEMIES / "skel_draw.rel",
            ],
            lambda: [*enemy_prgs(), SRC / "enemy_sizes.asm"],
            lambda: tool("genaibanks.py"),
        ),
        Step(
            "checkaibanks",
            lambda: [
                TOOLS / "checkaibanks.py",
                TOOLS / "genaibanks.py",
                TOOLS / "genaimeta.py",
                TOOLS / "mkreloc.py",
                SRC / "mem.asm",
                *enemy_prgs(),
                *(ENEMIES / f"ai_{dos}.lbl" for dos in DOS),
            ],
            lambda: [STAMPS / "checkaibanks"],
            run_checkaibanks,
        ),
        Step(
            "acme doom64.asm",
            lambda: doom_sources(labels=False),
            lambda: [ROOT / "game.prg", ROOT / "game.lbl"],
            lambda: acme(
                exe,
                ["-v3", "--vicelabels", str(ROOT / "game.lbl"), "doom64.asm"],
                ["game.prg"],
            ),
        ),
        Step(
            "acme a8boot.asm",
            lambda: asm_inputs(SRC / "a8boot.asm"),
            lambda: [SRC / "a8boot.bin", SRC / "a8boot.lbl"],
            lambda: acme(exe, ["--vicelabels", str(SRC / "a8boot.lbl"), "a8boot.asm"]),
        ),
        Step(
            "mkreloc",
            lambda: [
                TOOLS / "mkreloc.py",
                SRC / "mem.asm",
                SRC / "overlay.bin",
                ROOT / "overlay.lbl",
                ROOT / "game.prg",
                ROOT / "game.lbl",
                *map_prgs(),
            ],
            # level_prefix.asm is not the freshness anchor: mkreloc leaves it
            # untouched when the constants match, and the map PRGs are inputs
            # as well as outputs. The stamp records that this input set was built.
            lambda: [SRC / "level_prefix.asm", *map_prgs(), STAMPS / "mkreloc"],
            run_mkreloc,
            anchor=lambda: STAMPS / "mkreloc",
        ),
        Step(
            "acme doom64.asm reloc",
            lambda: doom_sources(labels=False),
            lambda: [ROOT / "game.prg", ROOT / "game.lbl"],
            lambda: run_game_reloc(exe),
        ),
        Step(
            "acme menu.asm",
            lambda: asm_inputs(SRC / "menu.asm"),
            lambda: [ROOT / "menu.prg", ROOT / "menu.lbl"],
            lambda: acme(
                exe,
                ["-v3", "--vicelabels", str(ROOT / "menu.lbl"), "menu.asm"],
                ["menu.prg"],
            ),
        ),
        Step(
            "genqsyms",
            lambda: [TOOLS / "genqsyms.py", TOOLS / "mkreloc.py", ROOT / "game.lbl"],
            lambda: [SRC / "qsyms.asm"],
            lambda: tool("genqsyms.py", "--labels", "game.lbl"),
        ),
        Step(
            "acme a8qsave.asm",
            lambda: asm_inputs(SRC / "a8qsave.asm"),
            lambda: [ROOT / "qsave.prg", ROOT / "qsave.lbl"],
            lambda: acme(
                exe,
                ["-v3", "--vicelabels", str(ROOT / "qsave.lbl"), "a8qsave.asm"],
                ["qsave.prg"],
            ),
        ),
        Step(
            "mkatr",
            lambda: [
                TOOLS / "mkatr.py",
                SRC / "mem.asm",
                SRC / "a8boot.bin",
                SRC / "a8boot.lbl",
                ROOT / "enemydata.prg",
                ROOT / "game.prg",
                ROOT / "sqt.prg",
                ROOT / "fnt.prg",
                ROOT / "tab.prg",
                ROOT / "menu.prg",
                ROOT / "qsave.prg",
                *map_prgs(),
                *enemy_prgs(),
            ],
            lambda: [ROOT / "dooma8.atr"],
            lambda: tool("mkatr.py"),
        ),
        Step(
            "buildreport",
            lambda: [
                TOOLS / "buildreport.py",
                TOOLS / "checkheap.py",
                TOOLS / "memoryreport.py",
                TOOLS / "mkatr.py",
                TOOLS / "genaibanks.py",
                TOOLS / "mkreloc.py",
                ROOT / "dooma8.atr",
                ROOT / "game.lbl",
                *enemy_prgs(),
            ],
            lambda: [ROOT / "build-report.json"],
            lambda: tool("buildreport.py"),
        ),
    ]


def fail(name: str) -> None:
    print(f"FAILED: {name}", flush=True)
    subprocess.run(
        [sys.executable, str(TOOLS / "buildreport.py"), "--failed", name],
        cwd=ROOT,
    )
    raise SystemExit(1)


def execute(step: Step, force: bool) -> None:
    if not force and not needs_build(step):
        print(f"skip {step.name}", flush=True)
        return
    print(f"build {step.name}", flush=True)
    try:
        step.run()
    except subprocess.CalledProcessError:
        fail(step.name)
    except SystemExit as exc:
        if exc.code not in (0, None):
            fail(step.name)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description="Incremental DoomA8 build")
    parser.add_argument("--all", action="store_true", help="rebuild every step")
    args = parser.parse_args()

    try:
        import PIL  # noqa: F401
    except ImportError:
        print("Pillow missing. Run: python -m pip install pillow")
        fail("pillow")

    try:
        exe = find_acme()
    except SystemExit as exc:
        if exc.code not in (0, None):
            print(exc)
            fail("acme")
        raise

    for step in steps(exe):
        execute(step, args.all)

    atr = ROOT / "dooma8.atr"
    if not atr.is_file():
        print("dooma8.atr missing after build")
        raise SystemExit(1)
    print(f"Built {atr.name}  {atr.stat().st_size} bytes")


if __name__ == "__main__":
    main()
