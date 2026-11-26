# Doom on the Atari 8-bit / Game Boy Color

A line-drawn *Doom* demake for various 8-bit machines: portal rooms, stick-figure enemies, sprite weapons.

## Display

The 3D view is a bitmap window alongside a text HUD. On the Atari XE, the world is still projected at 192×128 and rendered at 96x128; it's double buffered by updating display lists. On the Game Boy Color, the screen is 128x112, double buffered. Lines are unrolled Bresenham bodies.

## World

The map is **rooms as axis-aligned hulls**, not a global mesh. Floor plans can be a box or a tetromino (**T / L / S**, including a proper S dogleg) a squared-off **C**, a three-row **Stair**, or a **Pit** (sunken area inside the floor plan). Collision is 8-bit tests against the room’s collider boxes. Closed doors are blocking planes; open doors are walk-throughs that switch the active room. Red, yellow, and blue keycards unlock matching doors. Only the current room is drawn — doorways do not punch a view into the next one.

Ramps use the AABB for **rise/run** (`height = slope_y + (local * sy) / run` in 8.8) so the eye rides the slope. Elevators, switches, and crates share the same box tests. Step off a ledge and you fall; a hard landing costs health.

Walk-over **things** grant ammo, weapons, health, armour, keys, a soulsphere, and the radsuit. Message, hurt, and elevator **triggers** are undrawn AABBs; a switch can arm a trigger that would otherwise stay inert. End-of-level advances `e1mN` or returns to the menu endings.

Off-screen **items** (AABB meshes) and **enemies** skip rotate/project/draw. Horizontal and vertical tests use a fat 45° cone (`|axis| ≤ z` plus a size pad) so the miss is drawing something a bit off-screen, not dropping something that is still in view. The active room’s bounding lines are not frustum-culled.

There’s an editor for maps (Unity-style orbit in the viewport), item meshes, fonts, sprites, and enemy animations.

## Entities

Enemies are **Possessed, Imp, Pinky, and Baron**. Poses live in local space as signed offsets from the creature base. Animations are rotoscoped from Doom sprites onto custom skeletons. A few KB of poses and a skeleton line layout per type.

They run a room-scoped state machine (idle / patrol / alert / approach / attack / pain / death). Imp and Baron throw fireballs. Pinky closes to melee. A room holds at most two types.

Yaw is rolled(!) into the world rotation to avoid a double rotate. Perspective and rotation use 8-bit **log / antilog LUTs** (`alog(log|x| + log|cos θ|)`).

**Fist** is two sprites (left fist, right hand). **Chainsaw** is one vibrating sprite. **Shotgun** is a hitscan with range falloff, blood on a hit and a wall splat on a miss. **Chaingun** is a faster centered hitscan that uses the pistol muzzle and swaps two body frames. **Rocket launcher** throws a straight rocket that explodes on impact, with splash damage. The blast is a half-dome of charset pixels: six unique directions, the other three quadrants filled with 90° Y rotates.

The player weapon is stamped into the bitmap (body, muzzle, enemy muzzle, impact splat). Bob and recoil move that stamp.

SFX are PC-speaker envelopes on separate sound channels (player / enemy / world).

## Build (Atari XE)

6502 (ACME) plus Python table generators. Copy `setup-env.example.bat` to `setup-env.bat` and point `ACME` at your install. Python 3 needs Pillow (`python -m pip install pillow`). The generators pack the UI font, muzzle, splat, and weapon PNGs. The editor does not use Pillow.

```bat
build-a8.bat       :: generate listings, assemble PRGs, write dooma8.atr
make.bat           :: build-a8.bat, then boot dooma8.atr in Altirra
run-game.bat       :: boot dooma8.atr in Altirra
run-editor.bat     :: local map / skeleton / item editor
```

Controls: joystick to move and fire. Button 2 strafes. Enable an ST mouse in Options to turn and shoot.

## Build (Game Boy Color)

Z80-family assembly (RGBDS) plus Python table generators, CGB-only, MBC5 with battery RAM for saves. Set `RGBDS` (folder with `rgbasm`, `rgblink`, `rgbfix`) and `GBEMU` (BGB) in `setup-env.bat`; both default to `C:\dev\tools\...`. Python 3 needs Pillow, as above. The generators pack the A8 constants, HUD and menu fonts, line bodies, rooms, map, enemies, items, weapons, sound, music, and the menu and intermission screens into `gbc\build`.

```bat
build-gbc.bat      :: generate tables, assemble, link, write doomgbc.gbc
run-gbc.bat        :: boot doomgbc.gbc in BGB
run-editor.bat     :: same local editor (maps, skeletons, items, par times)
```

`build-gbc.bat <variant>` (`test`, `bench`, `live`, `map`, `move`, `world`, `ent`, `smoke`, `pick`, `comb`, `los`, `inter`, `pose`) builds a test ROM into `gbc\build` for the checkers in `tools\gbc_*.py`. `GBC_DEFS=-D DEBUG=1` adds the Start-button cheat. `GBC_DEFS=-D FRAME_MS=1` shows the frame-time readout on the HUD (off by default). From a cmd prompt: `set GBC_DEFS=-D FRAME_MS=1`, `build-gbc.bat`, then `set GBC_DEFS=` so it doesn't stay set for later builds. See `gbc\README.md` for the full notes.

Controls: D-pad to move and turn. B + left/right strafes. A fires, Select cycles weapons. Menu: A / Start select, B goes back.
