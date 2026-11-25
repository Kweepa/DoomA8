# Doom GBC (port of the A8 build)

Build: `build-gbc.bat` -> `gbc\build\doomgbc.gbc`. Run: `run-gbc.bat` (BGB). A8 build untouched.
CGB-only MBC5+RAM+battery, RGBDS 1.0.4.

## Controls
- D-pad: up/down move, left/right turn. B + left/right: strafe.
- A: fire. Select: cycle weapon.
- Start: debug cheat (all keys, weapons, ammo, full HP), only in builds with `GBC_DEFS=-D DEBUG=1` (A8 has none in play).

## What's in
- Wireframe room renderer (128x112 viewport, WRAM framebuffer, double-buffered VRAM, HDMA).
- All 8 levels cooked from the editor data; room-hull collision, floor/slope/fall, doors (passage only, no animation), key bits.
- Static objects, pickups/props and the four enemy types drawn as wireframe meshes (poses by AI state). Pickups sit at
  cell + 1 and spin on the A8 `item_spin` (dt_ms << 4, ~1 rev / 4.1 s); the lightpost and barrel never spin (A8 `fill_item_verts`).
- Player weapons as OAM sprites (fist, shotgun, chaingun, rocket launcher, pistol, chainsaw) with flash tiles.
- Level mechanics (`level.asm`, ROMX; A8 world.asm / door.asm / elevator.asm):
  - Switches: a blocked move into the pad from its air side (`SW_USE_RANGE`, facing, one fire per press) fires it:
    unlock the doors of its tag, arm the triggers waiting on its tag, start the elevator whose index is its tag, or
    end the level. Shootable switches (`SW_SHOOT`) are not ported.
  - Triggers: per-room volumes, enter fires once per visit: unlock / unhide (`DOOR_UNHIDE_MS`, then hidden again) the
    remote doors of a tag, spawn the `EN_GONE` enemies of a tag, hurt (`HURT_LG_HP` / `HURT_SM_HP` per `HURT_MS`
    while inside, none under the radsuit), end of level, elevator (every car of the group; two or more latch the
    gate) and summon. Message triggers are not ported (the map text is not in the GBC payload and every shipped
    message trigger is empty). The map payload is written in place (WRAM bank 2) and reloads with the level.
  - Level change: the keys are cleared and the loadout kept; after E1M8 the episode starts over at E1M1 (there is
    no menu yet). Banked code only sets `wNextLevelReq`; the ROM0 stub `LevelUpdate` calls `LoadLevel`.
  - Elevators: per car current height, target and step timer; one unit per `ELEV_STEP_MS` (x4 for slow cars);
    the player boards the car top (`elev_update_floor`, always snaps while riding), enemies on the top ride, the
    top plate is drawn at the current height, and enemy floor probes / line of sight see the car. Things on a car are
    not carried (the object lists are ROM). The A8 process-slot limit is not modelled.
  - Drawing: crates draw only the edges of faces the eye can see (all 12 with `crate_flags`), doors only from their
    air side, switches only from the other side, small non-solid platforms not from below.
  - Bump crack (A8 `note_bump` / `draw_crack`, `collide.asm` + `objects.asm`): a rejected move into a wall (outside
    every room collider) or a crate arms one `Crack` mesh (x1) on the face for `CRACK_MS`, at the legal pose
    +- `PLAYER_R` (a crate: its face, raised to the crate bottom), drawn from the outward side in that room only. An
    enemy, platform, door or step-up arms none; a live mark or `CRACK_HOLD` skips the probe; a switch fire or door
    transit on the same frame drops it.
  - "entering" card (A8 `enter_card`, `EnterCard` in combat.asm): after the first load and each level change (not
    after death) the viewport is black (palette 0 = black / white), the weapon sprites are off (`hCard`), and
    "entering" / the map name are centred on tile rows 6 / 7 as HUD-font tiles copied into the framebuffer
    (`HudCardTextB`, hud.asm; name max 16 columns) for `ENTER_HOLD_FRAMES` (2000 ms). Input counters and the frame
    clock restart afterwards.
- Player rules are the A8's (`player.asm`, gbc/ai.asm shots; constants and the `gb_*` pickup tables generated from
  src/ by `tools/gbc_a8const.py`):
  - Pickups: a thing at the cap, an owned key / chainsaw, a second backpack, armour that is not better stays on the
    floor; ammo amounts and caps are the A8's (backpack doubles the caps); armour sets the value and class (green
    saves 5/16, blue 1/2); a new gun is selected; one grab per `PICKUP_HOLD_MS`; reach is `near_box_xz` (Chebyshev
    `TH_GRAB_R` from the `TH_FOOT_SX` square) plus the Y overlap; the radsuit starts `POWERUP_MS` (green border).
  - Start loadout 50 bullets / 25 shells, pistol. Falling more than `FALL_SAFE` cells costs `FALL_DAMAGE`. Dead = the
    game freezes for `PL_DEATH_WAIT_MS`, then the starting loadout and a level reload. `take_damage` at skill 1.
  - Guns: pistol / chaingun one bullet, 1..16, nearest body in a +-12 / +-6 px cone; shotgun `SHOT_PELLETS` pellets,
    each a random column +-32 px and the body half-width `block_r`, 2..6 each; range `SHOT_Z_MAX` cells, clear line
    from the eye. Fist / chainsaw: first live enemy within `PUNCH_HIT_R` cells in any direction, 1..16. The A8 tests in
    screen pixels at FOCAL 100; here the same tests are made on the view-space tangent, so the cones are the same
    angle on the GBC viewport.
  - Rockets: player projectile at `RKT_SPEED_PL`, explodes on a wall / solid / enemy / barrel, splash `RKT_RAD` cells
    for 16..47 (enemies only), one explosion at a time (`EXPLODE_MS`, the next rocket waits). Barrels: shot or rocketed
    they are taken at once, splash, and chain to barrels within `RKT_RAD` after `BARREL_CHAIN_MS`.
    Explosion graphic (A8 fx.asm): `FX_N` red pixels (A8 plots ink; red by request) thrown from the blast origin, velocities picked at the first draw
    (random direction on a quarter sphere, flattened by how near and how far above the eye the blast is), each at
    projected origin + projected (velocity * elapsed / 16) for `EXPLODE_MS`; the one-at-a-time gate lasts
    `EXPLODE_MS - FX_START_MS`, as on the A8.
- HUD (`hud.asm`, ROMX; port of A8 hud.asm contents, Doom-style GBC layout): row 14 the message line ("+<item>",
  "Need a <key> keycard", "Opened elsewhere": the A8 texts shortened to 20 columns) for STATUS_MS; rows 15-17 an ammo
  column on the left (bullets, shells, rockets), health and armour on row 16, the frame time ("ms" + ms per game
  frame) under the armour, and a key card column on the right (blue, yellow, red). Three digits with leading zeros,
  no labels, no title / map name.
  Glyphs are the A8 UI charset (editor/font.json (Font tab) via `tools/gbc_hudfont.py`) at $9000, tile id = ASCII - 32; the A8
  icons are `{ | }` (ammo) and `[ \ ]` (red / yellow / blue key); `^` health and `~` armour are GBC glyphs, drawn as
  placeholders (cross, shield) while their cells in the sheet are empty. The LY 111 STAT interrupt switches the HUD
  rows to $8800 tile addressing (and sprites off); VBlank switches back.
- Colour follows the A8 (src/a8irq.asm): BG palette 0 = room paper (`room_bg`), ink (same hue, lum $C), red $46,
  black, rebuilt when the room changes; palette 1 = border, black or COL_HURT_A8 for HURT_FLASH_MS after damage;
  palettes 2 / 3 = HUD stats / message (A8 text mode: hue of HUD_PF2_STAT, lum HUD_PF1_STAT / HUD_PF1_MSG).
  A8 bytes map to BGR555 through the editor's A8_HEX table. Walls, enemies and pickups are all ink, as on the A8;
  red is reserved for blood splats and the fireball triangle (not drawn yet).
- Enemy AI (`ai.asm`, ROM bank 31) is a translation of the A8 code, routine by routine: `enemies_update`,
  `enemy_anim_step`, `eu_idle`, `eu_approach`, `enemy_enter_approach`, `select_dodge_dir`, `enemy_try_step`,
  `damage_enemy` (src/enemy.asm) and the per-type entries of src/ai_poss|pinky|imp|baron.asm. Labels in the
  comments name the A8 source. A8 constants (`ANIM_MS`, `DOOM_STEP_MS`, `EN_*`, ...) and the per-type tables
  (clip starts / lengths, range, pain chance, fire frame, block radius, hp) are generated from the A8 sources by
  `tools/gbc_a8const.py` (no hand-copied numbers). Time is `wDtMs` (A8 `dt_ms`, VBlanks * 17).
  - Animation: one clock, frames advance every other `ANIM_MS` step (200 ms) for all four types; idle and
    approach loop, alert / attack / pain end on the clip length, the dying clip plays every frame (bounce
    included) then holds its last frame as `EN_DEAD`.
  - Wake: `gunshot_wake` (guns only, not fist / chainsaw) or Chebyshev <= `ENEMY_DETECT` and `enemy_facing_ok`
    on the `en_dir` octant (half-plane on an axis, quadrant on a diagonal, always within one cell). Waking goes
    straight to approach. Tagged enemies start as `EN_GONE`.
  - Approach: whole-cell hops every `DOOM_STEP_MS`, direction from `select_dodge_dir`, re-picked only on
    approach entry or a blocked step. Enemies and the player block each other (`enemies_block_player`,
    `player_blocks_enemy`, block radius per type).
  - Facing: `en_rot` is the A8 heading (octant * 32 or the analog angle to the player); meshes are drawn
    with yaw -en_rot, as the A8 draws bones with R(yaw - en_rot).
  - Line of sight: the A8 3D segment test from mid-body (feet + SHOT_MID_H) to the eye against the room's
    cutouts, crates, solid platforms, elevators (at their start height until they move), slopes and the room
    shell (`LineSolidsBlocked`; lerpdv exact instead of the A8 log table). Checked by `gbc_losunit.py`.
  - Fireballs: the A8 rocket slots (RKT_MAX). Spawn at the higher wrist joint of the attack pose, aimed in 3D at
    the eye (A8 .z_aim, ~15.6 cells/s), stepped every RKT_TICK_MS (x, z, y) as a point against the player's
    room colliders, solids, ceiling and floor; 10 / 30 + rnd(16) on a hit; RKT_LIFE_MS; drawn as the A8 red
    screen triangle (half-extent 0.375) in bitplane 1.
  - Muzzle: on the fire frame (possessed, imp / baron throwing) the A8 enemy_muzzle image (3 distance LODs) is
    stamped in red at the projected weapon vertex for EMUZ_MS, byte-snapped and kept inside the viewport.
  - Steps need a floor within STEP_UP of the enemy's feet at the destination (collider floor, crate top, solid
    platform: `FloorBelow` / `EnemyMoveOk`), so enemies stop at ledges as on the A8.
- Input is hold-time based like the A8's 50 Hz IRQ: a timer interrupt (~241 Hz, 4 per VBlank, `TimerISR` in main.asm)
  reads the pad and counts a tick for every direction held; each game frame snapshots the counters (`ReadJoy`) and
  turns / moves by the time held, so taps shorter than a frame and release mid-frame count exactly. Rates are the A8's:
  turn 1 yaw unit per 16 ms (67/256 unit per tick, 8.8 accumulator `wTurnFrac`), move (sin * ms) >> 6 = ~7.75 units/s
  (8.25 8.8-units per tick). A / Select / Start taps are latched until the frame reads them.
- Weapon animation follows the A8 build: shotgun snaps up / kicks down / settles then cocks, rocket snaps down, pistol rises
  4 then 6 for 300 / 160 ms, fist swaps to the punch frame, chaingun alternates frames per shot, chainsaw shakes;
  walk bob is down-only (0..4 px, 512 ms per dip, no side sway); fire periods match (pistol 600 ms, rocket 1000 ms,
  fist 800 ms). Art and offsets are the A8's native size (1:1). A STAT (LY = 111) interrupt switches sprites off
  below the viewport, so recoil can push art past the bottom edge exactly as the A8 bitmap clip does.
- Switches are drawn as the A8 up-pointing triangle on their face.

## Test ROMs (all spec-based, headless BGB; Python spec in tools/gbc_*.py)
Every BGB run takes 0.3-2 s; the scripts give BGB 10 s, so a hung ROM fails fast. Test ROMs that call ClearFB
must `ei` afterwards (it leaves interrupts off), or the TEST_EXIT VBlank wait never returns.

| mode | runner | last result |
|---|---|---|
| `test` / `live` | `gbc_check.py [--live]` | PASS |
| `pose` | `gbc_posetest.py` | 160/0 |
| `map` | `gbc_maptest.py` (runs 2 slices, `GBC_MSLICE`) | 342 scene + 342 FindRoom / 0 |
| `move` | `gbc_movetest.py` (also the 7 hold-sampling cases) | 182/0, 7/0 |
| `world` | `gbc_worldtest.py` (`GBC_WSLICE=a:b`, <=120 per ROM; 922 total; elevator floors modelled) | 922/0 |
| `ent` | `gbc_enttest.py` | 103/0 |
| `comb` / `pick` | `gbc_combunit.py` / `gbc_pickunit.py` | 0 mismatches (A8 `take_damage` incl. armour class; 68 pickup steps incl. caps, backpack, refusals) |
| `los` | `gbc_losunit.py` (builds and runs itself) | 600 segments (276 blocked) / 0 |
| `smoke` | `gbc_smoke.py [name]` | 42 scenarios pass (adds: end / hurt / spawn / unlock triggers, elevator trigger and boarding) |

ROM0 (16 KB) is nearly full in the test builds, which is why the map/world tests are sliced.

## Known gaps
- Performance: ~8.5 fps in the E1M1 spawn room. DrawEntity ~29k M-cycles/entity and the serialized HBlank DMA dominate.
  Ideas: axis-aligned statics through the room column path, far-LOD weak perspective for items/enemies,
  overlap game update with DMA, back-face edge culling.
- Not implemented: blood / wall splats, shootable switches, infighting, door animation and key prompts,
  sound/music, menu, SRAM save, radsuit border tint (COL_SUIT_A8), trigger / cheat messages.
- Enemy scale: pose data is in stick units (editor `LAYOUT_ENEMY_SCALE` = 1/4), so enemies use shift 4 / radius 3.
