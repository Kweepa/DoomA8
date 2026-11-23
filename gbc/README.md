# Doom GBC (port of the A8 build)

Build: `build-gbc.bat` -> `gbc\build\doomgbc.gbc`. Run: `run-gbc.bat` (BGB). A8 build untouched.
CGB-only MBC5+RAM+battery, RGBDS 1.0.4.

## Controls
- D-pad: up/down move, left/right turn. B + left/right: strafe.
- A: fire. Select: cycle weapon.
- Start: debug cheat (all keys, weapons, ammo, full HP).

## What's in
- Wireframe room renderer (128x112 viewport, WRAM framebuffer, double-buffered VRAM, HDMA).
- All 8 levels cooked from the editor data; room-hull collision, floor/slope/fall, doors (passage only, no animation), key bits.
- Static objects, pickups/props and the four enemy types drawn as wireframe meshes (poses by AI state).
- Player weapons as OAM sprites (fist, shotgun, chaingun, rocket launcher, pistol, chainsaw) with flash tiles.
- Pickups (health, armor, ammo, weapons, keys, backpack, soulsphere), hitscan combat, armor soak, player death -> level reload. HUD numbers.
- Enemy AI (`ai.asm`, ROM bank 31; rules follow src/enemy.asm and ai_*.asm):
  - Idle enemies wake when the player is within 32 cells and in their facing half-plane (or adjacent), or on any shot.
    They stand and turn for 0.5 s (alert), then chase.
  - Chase walks one cell per 300 ms in one of 8 octants toward the player (never straight back, side step 1 time in 4,
    possessed and imps back off inside 8 cells); picks again on a block.
  - Possessed: hitscan within 28 cells with line of sight, hit when rnd&31 > min(dist,28), 6-15 damage, ~0.8 s cycle.
    Pinky: bite within 3 cells, 3-24. Imp / baron: claw within 3 cells, otherwise one fireball at a time
    (more likely the farther away), 10 + rnd(16) / 30 + rnd(16), quarter cell per VBlank, cleared by walls.
  - Game time runs on real VBlanks (dt clamp 12), not a fixed 4.
- Switches are drawn as the A8 up-pointing triangle on their face.

## Test ROMs (all spec-based, headless BGB; Python spec in tools/gbc_*.py)
| mode | runner | last result |
|---|---|---|
| `test` / `live` | `gbc_check.py [--live]` | PASS |
| `pose` | `gbc_posetest.py` | 160/0 |
| `map` | `gbc_maptest.py` (runs 2 slices, `GBC_MSLICE`) | 342 scene + 342 FindRoom / 0 |
| `move` | `gbc_movetest.py` | 182/0 |
| `world` | `gbc_worldtest.py` (`GBC_WSLICE=a:b`, <=120 per ROM; 922 total) | 922/0 |
| `ent` | `gbc_enttest.py` | 101/0 |
| `comb` / `pick` | `gbc_combunit.py` / `gbc_pickunit.py` | 0 mismatches |
| `smoke` | `gbc_smoke.py [name]` | 13 scenarios pass (pickups, shooting, attack/chase per enemy type, unseen enemy stays idle, death; attack_pinky_e1m2 skips: none there) |

ROM0 (16 KB) is nearly full in the test builds, which is why the map/world tests are sliced.

## Known gaps
- Performance: ~8.5 fps in the E1M1 spawn room. DrawEntity ~29k M-cycles/entity and the serialized HBlank DMA dominate.
  Ideas: axis-aligned statics through the room column path, far-LOD weak perspective for items/enemies,
  overlap game update with DMA, back-face edge culling.
- Not implemented: rocket projectiles/explosions, enemy muzzle flash, infighting, elevators/switches/triggers, door animation and key prompts,
  HUD labels/key icons, sound/music, menu, SRAM save, enemy line of sight.
- Enemy facing (yaw = -heading) and weapon sprite scale are not checked visually in-game.
- Enemy scale: pose data is in stick units (editor `LAYOUT_ENEMY_SCALE` = 1/4), so enemies use shift 4 / radius 3.
