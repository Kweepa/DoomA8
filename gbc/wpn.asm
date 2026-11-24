; Player weapons: inventory, firing state machine, view-model sprites (8x16 OAM).
;
; Body frames upload to VRAM bank 1 tile ids 224.. (OAM tiles 224, 226, ...), flash frames to
; bank 0 ids 242.. when the frame changes (GDMA from the weapon ROM bank). Placement lists are
; cached in WRAM so OAM writes need no ROM access. All of WpnVBlank runs in VBlank.

INCLUDE "hw.inc"
INCLUDE "wpn_ids.inc"

DEF WPN_FIST    EQU 0
DEF WPN_SHOT    EQU 1
DEF WPN_CHAIN   EQU 2
DEF WPN_ROCKET  EQU 3
DEF WPN_PISTOL  EQU 4
DEF WPN_SAW     EQU 5
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

; Per weapon (8 bytes): idle frame, alt frame, flash 0, flash 1 ($FF none), period, anim length,
; ammo type, cost. Periods / lengths are in VBlanks (A8: fist 800 / punch 360 ms, shotgun 600,
; chaingun 100, rocket 1000, pistol 600, saw 100).
SECTION "wpndef", ROM0
WpnDef:
    db WF_FIST_HAND,  WF_FIST_PUNCH, $FF,         $FF,         48, 22, AMMO_NONE,   0
    db WF_SHOT,       WF_SHOT_COCK,  WF_MUZZLE,   $FF,         36, 34, AMMO_SHELL,  1
    db WF_CHAIN_A,    WF_CHAIN_B,    WF_CHAIN_FL, WF_CHAIN_FR,  6,  6, AMMO_BULLET, 1
    db WF_ROCKET,     WF_ROCKET,     WF_MUZZLE,   $FF,         60,  5, AMMO_ROCKET, 1
    db WF_PISTOL,     WF_PISTOL,     WF_MUZZLE,   $FF,         36, 28, AMMO_BULLET, 1
    db WF_SAW,        WF_SAW,        WF_AXE_FLASH,$FF,          6,  6, AMMO_NONE,   0

; Recoil: (until elapsed VBlanks, dy) pairs, 0 ends (dy 0 afterwards). dy in pixels, down positive.
; A8 values (art is native size): shotgun snaps up 10, kicks down 14, settles 6 (16/35/35 ms);
; rocket snaps down 24, 16, 8; pistol rises 4 for 300 ms then 6 for 160 ms.
KickShot:
    db 1, -10, 3, 14, 5, 6, 0
KickRocket:
    db 1, 24, 3, 16, 5, 8, 0
KickPistol:
    db 18, -4, 28, -6, 0
; Art rows that hang below the viewport bottom at rest (A8 idle y puts 10 / 6 rows of the
; shotgun / pistol art past the edge, so the upward kicks still meet it).
DEF OVERHANG_SHOT   EQU 10
DEF OVERHANG_PISTOL EQU 6

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

; HL = recoil table, E = elapsed VBlanks -> A = dy. Clobbers HL.
KickLookup:
.l:
    ld a, [hl+]
    and a
    ret z                           ; end: back to rest
    cp e
    jr c, .skip                     ; limit < elapsed
    jr z, .skip
    ld a, [hl]
    ret
.skip:
    inc hl
    jr .l

WpnInit::
    ld a, (1 << WPN_FIST) | (1 << WPN_PISTOL)
    ld [wHaveWpn], a
    ld a, WPN_PISTOL
    ld [wWpnCur], a
    ld a, 50
    ld [wAmmoBul], a
    xor a
    ld [wAmmoShl], a
    ld [wAmmoRkt], a
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
    ld a, $FF
    ld [wLoadedBody], a
    ld [wLoadedFlash], a
    ld [wBodyFrame], a
    ld [wFlashFrame], a
    ld a, 100
    ld [wHP], a
    xor a
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
    ldh a, [hJoy]
    and JOY_START
    jr z, .noCheat
    ld a, $3F                       ; debug cheat: all weapons, full ammo
    ld [wHaveWpn], a
    ld a, 99
    ld [wAmmoBul], a
    ld [wAmmoShl], a
    ld [wAmmoRkt], a
    ld a, 100
    ld [wHP], a
.noCheat:
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
    inc a
    cp NUM_WPN
    jr c, .nw
    xor a
.nw:
    ld c, a
    ld hl, .bits
    ld e, a
    ld d, 0
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
    ; body frame and vertical offset
    ld a, [wWpnCur]
    call WpnDefPtr
    ld a, [hl+]
    ld c, a                         ; idle frame
    ld b, [hl]                      ; alt frame
    ld a, [wWpnAnim]
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
    cp WPN_SHOT
    jr z, .wShot
    cp WPN_ROCKET
    jr z, .wRocket
    cp WPN_PISTOL
    jp z, .wPistol
    cp WPN_SAW
    jp z, .wSaw
    cp WPN_CHAIN
    jp z, .wChain
    ; fist: the punch frame for the animation
    ld a, e
    cp $FF
    ld a, c
    jr z, .fistSet
    ld a, b
.fistSet:
    ld [wBodyFrame], a
    ld a, d
    ld [wWpnDy], a
    jp .bodyDone
.wShot:
    ld a, e
    cp 19
    jr c, .shotRecoil               ; snap up, kick down, settle
    cp 34
    jr nc, .shotRecoil
    ld a, b                         ; cock (A8: after 320 ms): flush at the bottom, dips 4 for a moment
    ld [wBodyFrame], a
    ld a, e
    cp 21
    jr c, .cock0
    cp 24
    jr nc, .cock0
    ld a, 5                         ; A8 cock dip
    jr .cockDy
.cock0:
    xor a
.cockDy:
    ld [wWpnDy], a
    jp .bodyDone
.shotRecoil:
    ld a, c
    ld [wBodyFrame], a
    ld hl, KickShot
    call KickLookup
    add OVERHANG_SHOT
    add d
    ld [wWpnDy], a
    jp .bodyDone
.wRocket:
    ld a, c
    ld [wBodyFrame], a
    ld hl, KickRocket
    call KickLookup
    add d
    ld [wWpnDy], a
    jp .bodyDone
.wPistol:
    ld a, c
    ld [wBodyFrame], a
    ld hl, KickPistol
    call KickLookup
    add OVERHANG_PISTOL
    add d
    ld [wWpnDy], a
    jp .bodyDone
.wChain:
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
.bits:
    db 1, 2, 4, 8, 16, 32

; ---- VBlank: tile upload + OAM -----------------------------------------------------------

; A = frame id, C = 0 body / 1 flash. Uploads the frame's tiles and caches its placements.
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
    ld l, a                         ; HL = placement list
    ld a, [hl+]
    ld b, a                         ; ncells
    ld a, [hl+]
    ld [wWpnW + 0], a
    ld a, [hl+]
    ld [wWpnH + 0], a
    ; cache placements
    ld a, c
    and a
    jr nz, .cacheFlash
    ld a, b
    ld [wBodyN], a
    ld a, [wWpnW]
    ld [wBodyW], a
    ld a, [wWpnH]
    ld [wBodyH], a
    push de
    ld de, wBodyPlace
    jr .copy
.cacheFlash:
    ld a, b
    ld [wFlashN], a
    ld a, [wWpnW]
    ld [wFlashW], a
    ld a, [wWpnH]
    ld [wFlashH], a
    push de
    ld de, wFlashPlace
.copy:
    ld a, b
    add a
    ld b, a
    jr z, .copied
.cl:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .cl
.copied:
    pop de
    ld a, [wBodyN]
    ld b, a
    ld a, c
    and a
    jr z, .doDma
    ld a, [wFlashN]
    ld b, a
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
    ld a, $8E                       ; $8E00 = tile 224
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, [wBodyN]
    jr .go
.flashDst:
    xor a
    ldh [rVBK], a
    ld a, $8F                       ; $8F20 = tile 242
    ldh [rHDMA3], a
    ld a, $20
    ldh [rHDMA4], a
    ld a, [wFlashN]
.go:
    add a
    dec a                           ; blocks - 1 (2 blocks per cell)
    ldh [rHDMA5], a
    xor a
    ldh [rVBK], a
    ret

; Call right after the frame flip, in VBlank.
WpnVBlank::
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
    ld a, [wFlashFrame]
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
    ; body origin: x = VIEW_X0 + (128 - w)/2, y = VIEW_H - h + dy (overhang, bob, recoil; the
    ; STAT interrupt clips everything below the viewport)
    ld a, [wBodyW]
    ld b, a
    ld a, 128
    sub b
    srl a
    add VIEW_X0
    ld [wOx], a
    ld a, [wBodyH]
    ld b, a
    ld a, VIEW_H
    sub b
    ld hl, wWpnDy
    add [hl]
    ld [wOy], a
    ; ---- OAM: body cells, then flash cells ----
    ld hl, OAM_BASE
    ld a, [wBodyN]
    and a
    jr z, .noBody
    ld [wCnt], a
    ld de, wBodyPlace
    ld a, BODY_TILE0
    ld [wTile], a
.bodyLoop:
    ld a, [de]
    inc de
    ld b, a                         ; dx
    ld a, [de]
    inc de
    ld c, a                         ; dy
    ld a, [wOy]
    add c
    add 16
    ld [hl+], a                     ; Y
    ld a, [wOx]
    add b
    add 8
    ld [hl+], a                     ; X
    ld a, [wTile]
    ld [hl+], a
    add 2
    ld [wTile], a
    ld a, $08                       ; VRAM bank 1, palette 0
    ld [hl+], a
    ld a, [wCnt]
    dec a
    ld [wCnt], a
    jr nz, .bodyLoop
.noBody:
    ld a, [wBodyN]
    ld [wUsedNow], a
    ld a, [wFlashFrame]
    cp $FF
    jr z, .noFlash
    ld a, [wFlashN]
    and a
    jr z, .noFlash
    ld [wCnt], a
    ld b, a
    ld a, [wUsedNow]
    add b
    ld [wUsedNow], a
    ld a, [wBodyW]
    ld b, a
    ld a, [wFlashW]
    ld c, a
    ld a, b
    sub c
    sra a
    ld b, a
    ld a, [wOx]
    add b
    ld [wFx], a
    ld a, [wWpnCur]                 ; A8 FLASH_DY_GUN 20 above the body, chainsaw flash on it
    cp WPN_SAW
    ld a, 20
    jr nz, .fdy
    xor a
.fdy:
    ld b, a
    ld a, [wOy]
    sub b
    ld [wFy], a
    ld de, wFlashPlace
    ld a, FLASH_TILE0
    ld [wTile], a
.flashLoop:
    ld a, [de]
    inc de
    ld b, a
    ld a, [de]
    inc de
    ld c, a
    ld a, [wFy]
    add c
    add 16
    ld [hl+], a
    ld a, [wFx]
    add b
    add 8
    ld [hl+], a
    ld a, [wTile]
    ld [hl+], a
    add 2
    ld [wTile], a
    ld a, $01                       ; bank 0, palette 1
    ld [hl+], a
    ld a, [wCnt]
    dec a
    ld [wCnt], a
    jr nz, .flashLoop
.noFlash:
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
