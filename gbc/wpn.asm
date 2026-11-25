; Player weapons: inventory, firing state machine, view-model sprites (8x16 OAM).
;
; Body frames upload to VRAM bank 1 tile ids 224.. (OAM tiles 224, 226, ...), flash frames to
; bank 0 ids 242.. when the frame changes (GDMA from the weapon ROM bank). Placement lists are
; cached in WRAM so OAM writes need no ROM access. All of WpnVBlank runs in VBlank.

INCLUDE "hw.inc"
INCLUDE "wpn_ids.inc"
INCLUDE "a8const.inc"
INCLUDE "wpntable.asm"                  ; WPN_PERIOD_* / WPN_ANIM_*, WpnPoseTab, Pose* (tools/gbc_genwpntab.py)

DEF WPN_FIST    EQU 0
DEF WPN_SHOT    EQU 1
DEF WPN_CHAIN   EQU 2
DEF WPN_ROCKET  EQU 3
DEF WPN_PISTOL  EQU 4
DEF WPN_SAW     EQU 5
ASSERT WPN_FIST == A8_WPN_FIST && WPN_SHOT == A8_WPN_SHOT && WPN_CHAIN == A8_WPN_CHAIN
ASSERT WPN_ROCKET == A8_WPN_ROCKET && WPN_PISTOL == A8_WPN_PIST && WPN_SAW == A8_WPN_SAW
DEF NUM_WPN     EQU 6

DEF AMMO_NONE   EQU 0
DEF AMMO_BULLET EQU 1
DEF AMMO_SHELL  EQU 2
DEF AMMO_ROCKET EQU 3

DEF OAM_BASE      EQU $FE00
DEF BODY_TILE0    EQU 224
DEF FLASH_TILE0   EQU 242
DEF FLASH_TICKS   EQU 7
DEF VIEW_X0       EQU 16                ; screen x of the viewport's left edge
DEF VIEW_H        EQU 112
DEF FLASH_PARK    EQU 100               ; added to a parked flash entry's y (flash y is ~80..130)

; Per weapon (8 bytes): idle frame, alt frame, flash 0, flash 1 ($FF none), period, anim length,
; ammo type, cost. Period and anim length (VBlanks) come from the editor's Weapons tab through
; wpntable.asm (A8: fist 800 / punch 360 ms, shotgun 600, chaingun 100, rocket 1000, pistol 600, saw 100).
SECTION "wpndef", ROM0
WpnDef:
    db WF_FIST_HAND,  WF_FIST_PUNCH, $FF,         $FF,         WPN_PERIOD_FIST,   WPN_ANIM_FIST,   AMMO_NONE,   0
    db WF_SHOT,       WF_SHOT_COCK,  WF_MUZZLE,   WF_MUZZLE_B, WPN_PERIOD_SHOT,   WPN_ANIM_SHOT,   AMMO_SHELL,  1
    db WF_CHAIN_A,    WF_CHAIN_B,    WF_MUZZLE,   WF_MUZZLE_B, WPN_PERIOD_CHAIN,  WPN_ANIM_CHAIN,  AMMO_BULLET, 1
    db WF_ROCKET,     WF_ROCKET,     WF_MUZZLE,   WF_MUZZLE_B, WPN_PERIOD_ROCKET, WPN_ANIM_ROCKET, AMMO_ROCKET, 1
    db WF_PISTOL,     WF_PISTOL,     WF_MUZZLE,   WF_MUZZLE_B, WPN_PERIOD_PISTOL, WPN_ANIM_PISTOL, AMMO_BULLET, 1
    db WF_SAW,        WF_SAW,        $FF,         $FF,         WPN_PERIOD_SAW,    WPN_ANIM_SAW,    AMMO_NONE,   0

; Pose tables (WpnPoseTab, generated into wpntable.asm from the Weapons tab): per weapon `db overhang`,
; then steps `db until, dy, frame`, then `db 0`. A step applies while the VBlanks since the shot are < until
; (ascending); past the last one, or idle, the pose is the idle frame at dy 0. dy in pixels, down positive.
;   frame 0 (idle): dy + overhang + walk bob (the recoil kicks)
;   frame 1 (alt):  the weapon's alt frame (shotgun pump, fist punch), dy absolute (no overhang or bob)
; The anim length (WpnDef) is the last "until". Chaingun and chainsaw have no table (WpnPose).

SECTION "wpn", ROM0

; HL = &WpnDef[A].
WpnDefPtr:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, WpnDef
    add hl, de
    ret

WpnInit::
    ld a, (1 << WPN_FIST) | (1 << WPN_PISTOL)
    ld [wHaveWpn], a
    ld a, WPN_PISTOL
    ld [wWpnCur], a
    ld a, A8_START_BUL
    ld [wAmmoBul], a
    ld a, A8_START_SHL
    ld [wAmmoShl], a
    xor a
    ld [wAmmoRkt], a
    ld [wHavePack], a               ; A8 reset_loadout: no backpack, green armour, no powerup
    ld [wArmorKind], a
    ld [wPuKind], a
    ld [wPuMs], a
    ld [wPuMs + 1], a
    ld [wPickupMs], a
    ld [wPickupMs + 1], a
    ld [wDeadMs], a
    ld [wDeadMs + 1], a
    ld [wAmmoNone], a
    ld [wKills], a
    ld [wWpnTimer], a
    ld [wWpnAnim], a
    ld [wFlashTimer], a
    ld [wFlashSel], a
    ld [wWpnSelPrev], a
    ld [wBobPhase], a
    ld [wWpnDy], a
    ld [wSawFlip], a
    ld [wFireEvent], a
    ld [wOamUsed], a
    ld [wApOk], a
    ld [wInPose], a
    ld [wVbSince], a
    ld [wApB], a
    ld [wApBodyN], a
    ld [wApFlashN], a
    ld [wApHid], a
    ld a, $FF
    ld [wLoadedBody], a
    ld [wLoadedFlash], a
    ld [wBodyFrame], a
    ld [wFlashFrame], a
    ld a, A8_START_HP
    ld [wHP], a
    ld a, A8_START_ARMOUR
    ld [wArmor], a
    ; OBJ palettes: 0 = ink (white), 1 = flash (yellow)
    ld a, $80
    ldh [rOCPS], a
    ld hl, ObjPalettes
    ld b, 16
.pal:
    ld a, [hl+]
    ldh [rOCPD], a
    dec b
    jr nz, .pal
    ret

ObjPalettes:
    dw $0000, $7FFF, $5ADF, $001F    ; pal 0: -, white, light, red
    dw $0000, $03FF, $02BF, $001F    ; pal 1: -, yellow, orange, red

; ---- game-frame update (wMoveDt = VBlanks since the last frame) ---------------------------

WpnUpdate::
    ld a, [wHP]
    and a
    ret z                           ; dead: frozen
IF DEF(DEBUG)
    ldh a, [hJoy]
    and JOY_START
    jr z, .noCheat
    ld a, $3F                       ; debug cheat (DEBUG builds): all weapons, full ammo
    ld [wHaveWpn], a
    ld a, 99
    ld [wAmmoBul], a
    ld [wAmmoShl], a
    ld [wAmmoRkt], a
    ld a, 100
    ld [wHP], a
.noCheat:
ENDC
    ldh a, [hJoy]
    and JOY_SELECT
    ld b, a
    ld a, [wWpnSelPrev]
    ld c, a
    ld a, b
    ld [wWpnSelPrev], a
    and a
    jr z, .noSwitch
    ld a, c
    and a
    jr nz, .noSwitch                ; held, not a new press
    ld a, [wWpnCur]
    ld b, NUM_WPN
.next:
    ld e, a
    ld d, 0
    ld hl, WpnCycle
    add hl, de
    ld a, [hl]                      ; next weapon in the cycle
    ld c, a
    ld e, a
    ld hl, WpnBits
    add hl, de
    ld a, [wHaveWpn]
    and [hl]
    ld a, c
    jr nz, .picked
    dec b
    jr nz, .next
    jr .noSwitch
.picked:
    ld [wWpnCur], a
    xor a
    ld [wWpnTimer], a
    ld [wWpnAnim], a
    ld [wFlashTimer], a
.noSwitch:
    ; timers
    ld a, [wMoveDt]
    ld b, a
    ld a, [wWpnTimer]
    sub b
    jr nc, .t1
    xor a
.t1:
    ld [wWpnTimer], a
    ld a, [wWpnAnim]
    sub b
    jr nc, .t2
    xor a
.t2:
    ld [wWpnAnim], a
    ld a, [wFlashTimer]
    sub b
    jr nc, .t3
    xor a
.t3:
    ld [wFlashTimer], a
    ; fire?
    ldh a, [hJoy]
    and JOY_A
    jr z, .noFire
    ld a, [wWpnTimer]
    and a
    jr nz, .noFire
    ld a, [wWpnCur]
    call WpnDefPtr
    ld de, 6
    add hl, de
    ld a, [hl+]                     ; ammo type
    ld b, [hl]                      ; cost
    and a
    jr z, .fire                     ; no ammo needed
    cp AMMO_SHELL
    ld hl, wAmmoBul
    jr c, .gotAmmo
    ld hl, wAmmoShl
    jr z, .gotAmmo
    ld hl, wAmmoRkt
.gotAmmo:
    ld a, [hl]
    cp b
    jr c, .noFire                   ; not enough
    sub b
    ld [hl], a
.fire:
    ld a, [wWpnCur]
    call WpnDefPtr
    ld de, 4
    add hl, de
    ld a, [hl+]
    ld [wWpnTimer], a
    ld a, [hl]
    ld [wWpnAnim], a
    ld [wWpnAnimLen], a
    ld a, 1
    ld [wFireEvent], a
    ld a, [wWpnCur]                 ; A8 fire_shot: guns (not fist / chainsaw) wake the room
    cp WPN_FIST
    jr z, .noWake
    cp WPN_SAW
    jr z, .noWake
    ld a, 1
    ld [wGunshotWake], a
.noWake:
    ld a, [wFlashSel]
    xor 1
    ld [wFlashSel], a
    ld a, FLASH_TICKS
    ld [wFlashTimer], a
.noFire:
    ; walk bob (A8: phase += dt / 4 ms, 512 ms per dip): only at rest, moving and on the ground
    ld a, [wWpnAnim]
    and a
    jr nz, .noBob
    ldh a, [hJoy]
    and JOY_UP | JOY_DOWN
    jr z, .noBob
    ld a, [wFalling]
    and a
    jr nz, .noBob
    ld a, [wMoveDt]
    add a
    add a
    ld b, a
    ld a, [wBobPhase]
    add b
    and $7F
    ld [wBobPhase], a
    jr .bobDone
.noBob:
    xor a
    ld [wBobPhase], a
.bobDone:
    ld a, 1
    ld [wInPose], a
    xor a
    ld [wVbSince], a
    call WpnPose
    xor a
    ld [wInPose], a
    ret

; Body frame, vertical offset and flash frame for the weapon's state "wVbSince VBlanks after" the last game
; frame's timers (wWpnAnim / wFlashTimer already hold the time left at the frame's dt). Called from
; WpnUpdate (wVbSince = 0) and from the VBlank interrupt via WpnTick.
WpnPose:
    ld a, [wWpnCur]
    call WpnDefPtr
    ld a, [hl+]
    ld c, a                         ; idle frame
    ld b, [hl]                      ; alt frame
    ld a, [wWpnAnim]
    call WpnVbSub
    and a
    jr nz, .animating
    ld a, $FF
    jr .haveE
.animating:
    ld d, a
    ld a, [wWpnAnimLen]
    sub d
.haveE:
    ld e, a                         ; E = VBlanks since the shot ($FF: none)
    ld a, [wBobPhase]
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    add 8
    srl a
    srl a
    srl a
    srl a
    srl a
    ld d, a                         ; D = bob, 0..4 (down only)
    ld a, [wWpnCur]
    cp WPN_SAW
    jp z, .wSaw
    cp WPN_CHAIN
    jp z, .wChain
    ; table driven: fist, shotgun, rocket, pistol
    push de
    ld a, [wWpnCur]
    ld e, a
    ld d, 0
    ld hl, WpnPoseTab
    add hl, de
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; HL = pose table
    pop de
    ld a, [hl+]
    push af                         ; overhang
.look:
    ld a, [hl+]                     ; until
    and a
    jr z, .rest
    cp e
    jr c, .skip                     ; until < elapsed
    jr z, .skip
    ld a, [hl+]                     ; dy
    ld l, [hl]                      ; frame kind
    jr .got
.skip:
    inc hl
    inc hl
    jr .look
.rest:
    xor a
    ld l, a
.got:
    ld h, a                         ; H = dy, L = frame kind (0 idle, 1 alt)
    pop af
    ld e, a                         ; E = overhang
    ld a, l
    and a
    jr nz, .poseAlt
    ld a, c
    ld [wBodyFrame], a
    ld a, h
    add e
    add d
    ld [wWpnDy], a
    jp .bodyDone
.poseAlt:
    ld a, b
    ld [wBodyFrame], a
    ld a, h
    ld [wWpnDy], a
    jp .bodyDone
.wChain:
    ld a, [wVbSince]
    and a
    jr z, .chainPick
    ld a, d                         ; VBlank tick: keep the frame picked when the shot fired (A / B per shot)
    ld [wWpnDy], a
    jr .bodyDone
.chainPick:
    ld a, e
    cp $FF
    ld a, c
    jr z, .chainSet
    ld a, [wFlashSel]               ; frames alternate per shot
    and a
    ld a, c
    jr z, .chainSet
    ld a, b
.chainSet:
    ld [wBodyFrame], a
    ld a, d
    ld [wWpnDy], a
    jr .bodyDone
.wSaw:                              ; shake: drops 2 on alternate frames, slower when idle
    ld a, c
    ld [wBodyFrame], a
    ld a, [wSawFlip]
    inc a
    ld [wSawFlip], a
    ld b, a
    ldh a, [hJoy]
    and JOY_A
    ld a, b
    jr nz, .sawFire
    srl a                           ; idle: every other pair of frames
.sawFire:
    and 1
    add a
    add d
    ld [wWpnDy], a
.bodyDone:
    ; flash frame
    ld a, [wFlashTimer]
    call WpnVbSub
    and a
    jr z, .noFlash
    ld a, [wWpnCur]
    call WpnDefPtr
    ld de, 2
    add hl, de
    ld a, [hl+]
    ld c, a
    ld b, [hl]
    ld a, [wFlashSel]
    and a
    ld a, c
    jr z, .setFlash
    ld a, b
    cp $FF
    jr nz, .setFlash
    ld a, c
.setFlash:
    ld [wFlashFrame], a
    ret
.noFlash:
    ld a, $FF
    ld [wFlashFrame], a
    ret
; A = max(0, A - wVbSince). Clobbers D, E.
WpnVbSub:
    ld d, a
    ld a, [wVbSince]
    ld e, a
    ld a, d
    sub e
    ret nc
    xor a
    ret

WpnBits:
    db 1, 2, 4, 8, 16, 32
; SELECT cycle: fist, chainsaw, pistol, shotgun, minigun, rocket launcher (indexed by weapon id).
WpnCycle:
    db WPN_SAW, WPN_CHAIN, WPN_ROCKET, WPN_FIST, WPN_SHOT, WPN_PISTOL

; ---- VBlank: tile upload + OAM -----------------------------------------------------------

; A = frame id, C = 0 body / 1 flash. Uploads the frame's tiles and remembers where its placement list is.
WpnUpload:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld de, WpnFrameTab
    add hl, de
    ld a, [WpnBank]
    ld [rROMB0], a
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a                         ; DE = tiles (16-byte aligned)
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; HL = placement header: ncells, w, h
    ld a, [hl+]
    ld b, a                         ; ncells
    inc hl                          ; w (art is centred; x is baked into the placements)
    ld a, [hl+]                     ; h
    ld [wWpnH], a
    ld a, c
    and a
    jr nz, .cacheFlash
    ld a, b
    ld [wBodyN], a
    ld a, [wWpnH]
    ld [wBodyH], a
    ld a, l
    ld [wBodyPtr], a
    ld a, h
    ld [wBodyPtr + 1], a
    jr .doDma
.cacheFlash:
    ld a, b
    ld [wFlashN], a
    ld a, l
    ld [wFlashPtr], a
    ld a, h
    ld [wFlashPtr + 1], a
.doDma:
    ld a, b
    and a
    ret z
    ld a, d
    ldh [rHDMA1], a
    ld a, e
    ldh [rHDMA2], a
    ld a, c
    and a
    jr nz, .flashDst
    ld a, 1
    ldh [rVBK], a
    ld a, HIGH($8000 + BODY_TILE0 * 16)
    ldh [rHDMA3], a
    ld a, LOW($8000 + BODY_TILE0 * 16)
    ldh [rHDMA4], a
    jr .go
.flashDst:
    xor a
    ldh [rVBK], a
    ld a, HIGH($8000 + FLASH_TILE0 * 16)
    ldh [rHDMA3], a
    ld a, LOW($8000 + FLASH_TILE0 * 16)
    ldh [rHDMA4], a
.go:
    ld a, b
    add a
    dec a                           ; blocks - 1 (2 blocks per cell)
    ldh [rHDMA5], a
    xor a
    ldh [rVBK], a
    ret

; A = flash frame to keep loaded: the running one, else the weapon's first flash frame ($FF: none), so
; the tiles and OAM entries exist when a shot's flash is switched on in between frame flips.
WpnFlashWant:
    ld a, [wFlashFrame]
    cp $FF
    ret nz
    ld a, [wWpnCur]
    call WpnDefPtr
    inc hl
    inc hl
    ld a, [hl]
    ret

; Call right after the frame flip, in VBlank. This is on the VBlank budget (double speed leaves ~2300
; machine cycles for ShowBank + this + HudBlit): OAM writes are dropped once the LCD leaves VBlank, so the
; placement loops read ready-made (dy, x, tile) triples straight from the weapon ROM bank.
; The weapon art lives in ROM bank WpnBank, so this maps it. The main loop reaches here straight after
; DrawWorldObjects, which leaves the entity bank mapped, and the code after it (HUD message, pickups,
; combat) reads banked data on that assumption: put the entity bank back, or a frame swap leaves the
; weapon bank mapped and corrupts whatever reads next.
WpnVBlank::
    call WpnVBlankBody
    ld a, [EntBank]
    ld [rROMB0], a
    ret

WpnVBlankBody:
    xor a
    ld [wApOk], a
    ld a, [wBodyFrame]
    cp $FF
    ret z
    ld b, a
    ld a, [wLoadedBody]
    cp b
    jr z, .bodyOk
    ld a, b
    ld [wLoadedBody], a
    ld c, 0
    call WpnUpload
.bodyOk:
    call WpnFlashWant
    ld [wFlashWant], a
    cp $FF
    jr z, .flashOk
    ld b, a
    ld a, [wLoadedFlash]
    cp b
    jr z, .flashOk
    ld a, b
    ld [wLoadedFlash], a
    ld c, 1
    call WpnUpload
.flashOk:
    ld a, [WpnBank]
    ld [rROMB0], a
    ; B = OAM y of the body's top: VIEW_H - h + dy (overhang, bob, recoil; the STAT interrupt clips
    ; everything below the viewport) + 16
    ld a, [wBodyH]
    ld b, a
    ld a, VIEW_H + 16
    sub b
    ld hl, wWpnDy
    add [hl]
    ld b, a
    ld [wApB], a
    xor a
    ld [wApFlashN], a
    ld [wApHid], a
    ld hl, OAM_BASE
    ld a, [wBodyN]
    ld c, a
    ld [wApBodyN], a
    ld [wUsedNow], a
    and a
    jr z, .noBody
    ld a, [wBodyPtr]
    ld e, a
    ld a, [wBodyPtr + 1]
    ld d, a
.bodyLoop:
    ld a, [de]
    inc de
    add b
    ld [hl+], a                     ; Y
    ld a, [de]
    inc de
    ld [hl+], a                     ; X
    ld a, [de]
    inc de
    ld [hl+], a                     ; tile
    ld a, $08                       ; VRAM bank 1, palette 0
    ld [hl+], a
    dec c
    jr nz, .bodyLoop
.noBody:
    ld a, [wFlashWant]
    cp $FF
    jr z, .noFlash
    ld a, [wFlashN]
    and a
    jr z, .noFlash
    ld [wApFlashN], a
    ld c, a
    ld a, [wUsedNow]
    add c
    ld [wUsedNow], a
    ld a, [wWpnCur]                 ; A8 FLASH_DY_GUN 20 above the body, here 15 (flash lowered 5 px); chainsaw flash on it
    cp WPN_SAW
    ld a, 15
    jr nz, .fdy
    xor a
.fdy:
    cpl
    inc a                           ; -fdy
    add b
    ld b, a
    ld a, [wFlashFrame]             ; no flash running: the entries sit parked until WpnTick shows them
    cp $FF
    jr nz, .shown
    ld a, 1
    ld [wApHid], a
    ld a, b
    add FLASH_PARK
    ld b, a
.shown:
    ld a, [wFlashPtr]
    ld e, a
    ld a, [wFlashPtr + 1]
    ld d, a
.flashLoop:
    ld a, [de]
    inc de
    add b
    ld [hl+], a
    ld a, [de]
    inc de
    ld [hl+], a
    ld a, [de]
    inc de
    ld [hl+], a
    ld a, $01                       ; bank 0, palette 1
    ld [hl+], a
    dec c
    jr nz, .flashLoop
.noFlash:
    ld a, 1
    ld [wApOk], a
    ; hide entries that were used last time but not now
    ld a, [wOamUsed]
    ld b, a
    ld a, [wUsedNow]
    ld c, a
    ld [wOamUsed], a
    ld a, b
    sub c
    ret z
    ret c
    ld b, a
.hide:
    xor a
    ld [hl+], a
    inc hl
    inc hl
    inc hl
    dec b
    jr nz, .hide
    ret

; ---- VBlank interrupt: weapon motion at VBlank rate -------------------------------------------
; The game frame is several VBlanks long, so the recoil steps (16 / 35 / 35 ms) and the muzzle flash (7
; VBlanks) would be sampled once per frame and mostly skipped. VBlankISR calls this on every VBlank
; except the one the main loop is waiting on (WpnVBlank does the full job there): it re-evaluates the pose
; for "now" and patches only the OAM y of the entries WpnVBlank wrote (body shifted by the base change,
; flash entries shifted with it and parked off screen once the flash time is up). Tiles and frame swaps
; (pump, punch, chaingun A/B) still change at the next frame flip. Chainsaw shake stays per game frame.
WpnTick::
    ld a, [wApOk]
    and a
    ret z
    ld a, [wInPose]
    and a
    ret nz
    ld a, [wHP]
    and a
    ret z
    ld a, [wWpnCur]
    cp WPN_SAW
    ret z
    ldh a, [hFrame]
    ld b, a
    ldh a, [hLastFrame]
    ld c, a
    ld a, b
    sub c
    ld [wVbSince], a
    call WpnPose
    ; body: shift by the change of the base y (only while the loaded frame is the one in OAM)
    ld a, [wBodyFrame]
    ld b, a
    ld a, [wLoadedBody]
    cp b
    jr nz, .vis
    ld a, [wBodyH]
    ld b, a
    ld a, VIEW_H + 16
    sub b
    ld hl, wWpnDy
    add [hl]
    ld b, a                         ; new base
    ld a, [wApB]
    ld c, a
    ld a, b
    sub c
    jr z, .vis
    ld d, a                         ; delta
    ld a, b
    ld [wApB], a
    ld a, [wApBodyN]
    ld c, a
    ld a, [wApFlashN]
    add c
    jr z, .vis
    ld c, a
    ld hl, OAM_BASE
.shift:
    ld a, [hl]
    add d
    ld [hl+], a
    inc hl
    inc hl
    inc hl
    dec c
    jr nz, .shift
.vis:
    ld a, [wApFlashN]
    and a
    ret z
    ld c, a
    ld a, [wApHid]
    ld b, a                         ; 1: parked now
    ld a, [wFlashFrame]
    cp $FF
    ld a, 0
    jr nz, .want                    ; flash on: want parked = 0
    inc a                           ; flash off: want parked = 1
.want:
    cp b
    ret z
    ld [wApHid], a
    and a
    ld d, FLASH_PARK
    jr nz, .park
    ld d, -FLASH_PARK
.park:
    ld a, [wApBodyN]
    add a
    add a
    ld l, a
    ld h, HIGH(OAM_BASE)
.parkLoop:
    ld a, [hl]
    add d
    ld [hl+], a
    inc hl
    inc hl
    inc hl
    dec c
    jr nz, .parkLoop
    ret
