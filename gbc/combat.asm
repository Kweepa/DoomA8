; Gameplay: HUD, pickups, player shots, enemy AI, damage, death.
; Positions are integer cells (cam x/z high bytes) plus 8-bit fractions.

INCLUDE "hw.inc"
INCLUDE "map_fields.inc"
INCLUDE "wpn_ids.inc"

INCLUDE "en.inc"

DEF TH_HEALTH_SM EQU 0
DEF TH_HEALTH_LG EQU 1
DEF TH_ARMOR_G   EQU 2
DEF TH_ARMOR_B   EQU 3
DEF TH_BULLETS   EQU 4
DEF TH_SHELLS    EQU 5
DEF TH_ROCKETS   EQU 6
DEF TH_SHOTGUN   EQU 7
DEF TH_CHAINGUN  EQU 8
DEF TH_CHAINSAW  EQU 9
DEF TH_RLAUNCHER EQU 10
DEF TH_BACKPACK  EQU 11
DEF TH_KEY_RED   EQU 12
DEF TH_KEY_YEL   EQU 13
DEF TH_KEY_BLUE  EQU 14
DEF TH_SOUL      EQU 15
DEF TH_NTYPES    EQU 19

SECTION "combat", ROM0

; ---- helpers -----------------------------------------------------------------------------

; 8-bit Galois LFSR (taps $B8). A = next value; hRnd must never be 0.
Rnd::
    ldh a, [hRnd]
    srl a
    jr nc, .nx
    xor $B8
.nx:
    ldh [hRnd], a
    ret

; A = byte -> wDec: hundreds, tens, ones as tile ids (FONT_TILE0 + digit).
DecimalA::
    ld b, 0
.h:
    cp 100
    jr c, .hd
    sub 100
    inc b
    jr .h
.hd:
    ld c, a
    ld a, b
    add FONT_TILE0
    ld [wDec], a
    ld b, 0
    ld a, c
.t:
    cp 10
    jr c, .td
    sub 10
    inc b
    jr .t
.td:
    ld c, a
    ld a, b
    add FONT_TILE0
    ld [wDec + 1], a
    ld a, c
    add FONT_TILE0
    ld [wDec + 2], a
    ret

; Fill wHud (12 tiles: HP, armor on row 15, ammo, kills on row 16) from the player state.
HudUpdate::
    ld a, [wHP]
    call DecimalA
    ld hl, wHud
    call .put3
    ld a, [wArmor]
    call DecimalA
    ld hl, wHud + 3
    call .put3
    ; ammo of the current weapon
    ld a, [wWpnCur]
    ld e, a
    ld d, 0
    ld hl, HudAmmoSel
    add hl, de
    ld a, [hl]
    ld e, a
    ld d, 0
    ld hl, wAmmoNone
    add hl, de
    ld a, [hl]
    call DecimalA
    ld hl, wHud + 6
    call .put3
    ld a, [wKills]
    call DecimalA
    ld hl, wHud + 9
    call .put3
    ; frame time in ms (VBlank = 16.74 ms: 16.75 * n), 255 max
    ld a, [wRawDt]
    cp 16
    jr c, .msOk
    ld a, 255
    jr .msHave
.msOk:
    ld b, a
    swap a
    add b
    ld c, a                         ; 17 * n
    ld a, b
    srl a
    srl a
    ld b, a
    ld a, c
    sub b                           ; - n / 4
.msHave:
    call DecimalA
    ld hl, wHud + 12
.put3:
    ld a, [wDec]
    ld [hl+], a
    ld a, [wDec + 1]
    ld [hl+], a
    ld a, [wDec + 2]
    ld [hl], a
    ret

; Offsets from wAmmoNone: none -> 0 (the zero byte), bullets, shells, rockets.
HudAmmoSel:
    db 0, 2, 1, 3, 1, 0              ; fist, shotgun(shells), chaingun, rocket, pistol, saw

; ---- pickups -----------------------------------------------------------------------------

; Walk-over pickups in the current room: |dx| <= 1, |dz| <= 1 cells and |feet - y| <= 2.
PickupScan::
    ld a, [wObjBank]
    ld [rROMB0], a
    ld a, [wRoom]
    add a
    ld c, a
    ld b, 0
    ld a, [wObjTab]
    ld l, a
    ld a, [wObjTab + 1]
    ld h, a
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]                     ; n_static
    ld c, a
    ld b, 0
    and a
    jr z, .noStatics
    push hl
    ld h, 0
    ld l, c
    ld d, h
    ld e, l                         ; DE = n
    add hl, hl
    add hl, de                      ; 3n
    ld b, h
    ld c, l
    ld h, d
    ld l, e
    add hl, hl
    add hl, hl
    add hl, hl                      ; 8n
    add hl, bc                      ; 11n: a static entry is 11 bytes
    ld b, h
    ld c, l
    pop hl
    add hl, bc
.noStatics:
    ld a, [hl+]                     ; n_things
    and a
    ret z
    ld [wPkN], a
    xor a
    ld [wPkI], a
.loop:
    ld a, [hl+]
    ld [wPkIdx], a
    ld a, [hl+]
    ld [wPkType], a
    ld a, [hl+]
    ld b, a                         ; x
    ld a, [hl+]
    ld c, a                         ; y
    ld a, [hl+]
    ld d, a                         ; z
    inc hl
    push hl
    ld a, [wPkType]
    cp TH_NTYPES - 2
    jr nc, .next                    ; props (light post, barrel) are not pickups
    ld a, [wPkIdx]
    ld e, a
    push de
    ld d, 0
    ld hl, wThTaken
    add hl, de
    ld a, [hl]
    pop de
    and a
    jr nz, .next
    ld a, [wCamX + 1]
    sub b
    jr nc, .dxp
    cpl
    inc a
.dxp:
    cp 2
    jr nc, .next
    ld a, [wCamZ + 1]
    sub d
    jr nc, .dzp
    cpl
    inc a
.dzp:
    cp 2
    jr nc, .next
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    sub c
    jr nc, .dyp
    cpl
    inc a
.dyp:
    cp 3
    jr nc, .next
    ld a, [wPkIdx]
    ld e, a
    ld d, 0
    ld hl, wThTaken
    add hl, de
    ld [hl], 1
    ld a, [wPkType]
    call ApplyPickup
.next:
    pop hl
    ld a, [wPkI]
    inc a
    ld [wPkI], a
    ld b, a
    ld a, [wPkN]
    cp b
    jr nz, .loop
    ret

; Add A to the byte at HL, capped at B.
AddCap:
    add [hl]
    jr c, .cap
    cp b
    jr c, .ok
.cap:
    ld a, b
.ok:
    ld [hl], a
    ret

; A = thing type. Applies the pickup.
ApplyPickup::
    ld e, a
    ld d, 0
    ld hl, .jump
    add hl, de
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    jp hl
.jump:
    dw .hsm, .hlg, .arg, .arb, .bul, .shl, .rkt, .sg, .cg, .saw, .rl, .bp, .kred, .kyel, .kblue, .soul, .none
.hsm:
    ld a, 10
    ld b, 100
    ld hl, wHP
    jp AddCap
.hlg:
    ld a, 25
    ld b, 100
    ld hl, wHP
    jp AddCap
.arg:
    ld a, 100
    ld b, 100
    ld hl, wArmor
    jp AddCap
.arb:
    ld a, 200
    ld b, 200
    ld hl, wArmor
    jp AddCap
.bul:
    ld a, 10
    ld b, 200
    ld hl, wAmmoBul
    jp AddCap
.shl:
    ld a, 4
    ld b, 50
    ld hl, wAmmoShl
    jp AddCap
.rkt:
    ld a, 5
    ld b, 50
    ld hl, wAmmoRkt
    jp AddCap
.sg:
    ld a, [wHaveWpn]
    or 1 << 1
    ld [wHaveWpn], a
    ld a, 8
    ld b, 50
    ld hl, wAmmoShl
    jp AddCap
.cg:
    ld a, [wHaveWpn]
    or 1 << 2
    ld [wHaveWpn], a
    ld a, 20
    ld b, 200
    ld hl, wAmmoBul
    jp AddCap
.saw:
    ld a, [wHaveWpn]
    or 1 << 5
    ld [wHaveWpn], a
    ret
.rl:
    ld a, [wHaveWpn]
    or 1 << 3
    ld [wHaveWpn], a
    ld a, 2
    ld b, 50
    ld hl, wAmmoRkt
    jp AddCap
.bp:
    ld a, 10
    ld b, 200
    ld hl, wAmmoBul
    call AddCap
    ld a, 4
    ld b, 50
    ld hl, wAmmoShl
    call AddCap
    ld a, 1
    ld b, 50
    ld hl, wAmmoRkt
    jp AddCap
.kred:
    ld a, [wHaveKeys]
    or 4
    ld [wHaveKeys], a
    ret
.kyel:
    ld a, [wHaveKeys]
    or 1
    ld [wHaveKeys], a
    ret
.kblue:
    ld a, [wHaveKeys]
    or 2
    ld [wHaveKeys], a
    ret
.soul:
    ld a, 100
    ld b, 200
    ld hl, wHP
    jp AddCap
.none:
    ret

; ---- HUD ---------------------------------------------------------------------------------

; Call in VBlank: HP / armor on map row 15, ammo / kills on row 16 (3 digit tiles each).
HudBlit::
    ld hl, VRAM_MAP0 + 32 * 15 + 2
    ld de, wHud
    call .three
    ld hl, VRAM_MAP0 + 32 * 15 + 7
    call .three
    ld hl, VRAM_MAP0 + 32 * 16 + 2
    call .three
    ld hl, VRAM_MAP0 + 32 * 16 + 7
    call .three
    ld hl, VRAM_MAP0 + 32 * 15 + 12   ; frame time, ms
.three:
    ld a, [de]
    inc de
    ld [hl+], a
    ld a, [de]
    inc de
    ld [hl+], a
    ld a, [de]
    inc de
    ld [hl], a
    ret

; ---- enemy geometry helpers --------------------------------------------------------------

; Enemy wObjI position -> wEx / wExL / wEz / wEzL.
LoadEnPos::
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnX
    add hl, de
    ld a, [hl]
    ld [wEx], a
    ld hl, wEnXL
    add hl, de
    ld a, [hl]
    ld [wExL], a
    ld hl, wEnZ
    add hl, de
    ld a, [hl]
    ld [wEz], a
    ld hl, wEnZL
    add hl, de
    ld a, [hl]
    ld [wEzL], a
    ret

StoreEnPos::
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnX
    add hl, de
    ld a, [wEx]
    ld [hl], a
    ld hl, wEnXL
    add hl, de
    ld a, [wExL]
    ld [hl], a
    ld hl, wEnZ
    add hl, de
    ld a, [wEz]
    ld [hl], a
    ld hl, wEnZL
    add hl, de
    ld a, [wEzL]
    ld [hl], a
    ret

; wDx / wDz = player - enemy (8.8, signed).
DeltaToPlayer::
    ld a, [wCamX]
    ld hl, wExL
    sub [hl]
    ld [wDx], a
    ld a, [wCamX + 1]
    ld hl, wEx
    sbc [hl]
    ld [wDx + 1], a
    ld a, [wCamZ]
    ld hl, wEzL
    sub [hl]
    ld [wDz], a
    ld a, [wCamZ + 1]
    ld hl, wEz
    sbc [hl]
    ld [wDz + 1], a
    ret

; wDx / wDz = enemy - player (8.8, signed), for shot tests.
DeltaFromPlayer:
    ld a, [wExL]
    ld hl, wCamX
    sub [hl]
    ld [wDx], a
    ld a, [wEx]
    ld hl, wCamX + 1
    sbc [hl]
    ld [wDx + 1], a
    ld a, [wEzL]
    ld hl, wCamZ
    sub [hl]
    ld [wDz], a
    ld a, [wEz]
    ld hl, wCamZ + 1
    sbc [hl]
    ld [wDz + 1], a
    ret

; BC = |wDx|, DE = |wDz|.
AbsPair::
    ld a, [wDx]
    ld c, a
    ld a, [wDx + 1]
    ld b, a
    bit 7, b
    jr z, .xp
    xor a
    sub c
    ld c, a
    ld a, 0
    sbc b
    ld b, a
.xp:
    ld a, [wDz]
    ld e, a
    ld a, [wDz + 1]
    ld d, a
    bit 7, d
    jr z, .zp
    xor a
    sub e
    ld e, a
    ld a, 0
    sbc d
    ld d, a
.zp:
    ret

; DE = max(|dx|, |dz|) + min / 2.
ApproxDist::
    call AbsPair
    ld a, b
    cp d
    jr c, .swap
    jr nz, .ok
    ld a, c
    cp e
    jr nc, .ok
.swap:
    push bc
    push de
    pop bc
    pop de
.ok:
    srl b
    rr c
    ld a, e
    add c
    ld e, a
    ld a, d
    adc b
    ld d, a
    ret

; A = heading (0 = +z, 64 = +x) of (wDx, wDz); spec: tools/gbc_game.angle_to.
AngleTo::
    call AbsPair
    ld a, b
    or c
    or d
    or e
    jr nz, .nz
    xor a
    ret
.nz:
.sh:
    ld a, b
    or d
    jr z, .shd
    srl b
    rr c
    srl d
    rr e
    jr .sh
.shd:                               ; C = ax, E = az (8-bit)
    xor a
    ld [wAngSw], a
    ld a, c
    cp e
    jr c, .le
    jr z, .le
    ld a, 1
    ld [wAngSw], a
    ld a, e                         ; numerator az, divisor ax
    ld b, c
    jr .div
.le:
    ld a, c                         ; numerator ax, divisor az
    ld b, e
.div:
    ld e, a
    srl a
    srl a
    ld d, a                         ; n >> 2
    ld a, e
    and 3
    rrca
    rrca                            ; (n & 3) << 6
    ld e, a
    ld c, b                         ; divisor
    ld b, 0
    call Div24x8                    ; DE = (n << 6) / divisor
    ld hl, AtanTab
    ld d, 0
    add hl, de
    ld a, [hl]
    ld c, a
    ld a, [wAngSw]
    and a
    ld a, c
    jr z, .noInv
    ld a, 64
    sub c
.noInv:
    ld c, a                         ; angle within the quadrant
    ld a, [wDz + 1]
    bit 7, a
    jr nz, .zneg
    ld a, [wDx + 1]
    bit 7, a
    ld a, c
    ret z
    xor a
    sub c
    ret
.zneg:
    ld a, [wDx + 1]
    bit 7, a
    jr nz, .both
    ld a, 128
    sub c
    ret
.both:
    ld a, 128
    add c
    ret

; ---- damage ------------------------------------------------------------------------------

; A = damage. Armor soaks a third of it (tools/gbc_game.player_damage).
PlayerDamage::
    ld c, a
    ld a, [wArmor]
    and a
    jr z, .hp
    ld b, 0
    ld a, c
.d3:
    cp 3
    jr c, .d3d
    sub 3
    inc b
    jr .d3
.d3d:
    ld a, [wArmor]
    cp b
    jr nc, .soak
    ld b, a
.soak:
    sub b
    ld [wArmor], a
    ld a, c
    sub b
    ld c, a
.hp:
    ld a, [wHP]
    cp c
    jr c, .dead
    jr z, .dead
    sub c
    ld [wHP], a
    ret
.dead:
    xor a
    ld [wHP], a
    ret

; Enemy wObjI takes A damage: death, or a pain flinch by chance; idle enemies wake.
DamageEnemy:
    ld [wDmg], a
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_DYING
    ret nc
    ld hl, wEnHp
    add hl, de
    ld a, [wDmg]
    ld b, a
    ld a, [hl]
    cp b
    jr c, .kill
    jr z, .kill
    sub b
    ld [hl], a
    ; still alive: wake / pain
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    and a
    jr nz, .pain
    ld [hl], EN_CHASE
    ld hl, wEnTimer
    add hl, de
    ld [hl], 0
.pain:
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    swap a
    ld c, a
    ld b, 0
    ld hl, EnemyParams + 7
    add hl, bc
    ld a, [hl]
    ld b, a
    call Rnd
    cp b
    ret nc
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnState
    add hl, de
    ld [hl], EN_PAIN
    ld hl, wEnTimer
    add hl, de
    ld [hl], 0
    ld hl, wEnFrame
    add hl, de
    ld [hl], 0
    ret
.kill:
    xor a
    ld [hl], a
    ld hl, wEnState
    add hl, de
    ld [hl], EN_DYING
    ld hl, wEnTimer
    add hl, de
    ld [hl], 0
    ld a, [wKills]
    inc a
    ld [wKills], a
    ret

; ---- player shots ------------------------------------------------------------------------

; Consumes wFireEvent: a ray along the view direction hits the nearest live enemy in the room
; within weapon range and hitbox width. Rockets also splash enemies near the target.
PlayerShot::
    ld a, [wFireEvent]
    and a
    ret z
    xor a
    ld [wFireEvent], a
    ld a, [wEnN]
    and a
    ret z
    ; weapon shot params
    ld a, [wWpnCur]
    add a
    add a
    ld e, a
    ld d, 0
    ld hl, WeaponShot
    add hl, de
    ld a, [hl+]
    ld [wShRange], a
    ld a, [hl+]
    ld [wShMin], a
    ld a, [hl+]
    ld [wShMask], a
    ld a, [hl]
    ld [wShSplash], a
    ; view direction (forward = sin, cos of yaw)
    ld a, [wYaw]
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wSin], a
    ld a, [wYaw]
    add 64
    ld l, a
    ld a, [hl]
    ld [wCos], a
    ld a, $FF
    ld [wBestI], a
    ld a, $FF
    ld [wBestF], a
    ld a, $7F
    ld [wBestF + 1], a
    xor a
    ld [wObjI], a
.loop:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnRoom
    add hl, de
    ld a, [wRoom]
    cp [hl]
    jp nz, .next
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_DYING
    jp nc, .next
    call LoadEnPos
    call DeltaFromPlayer
    ; f = dx*sin + dz*cos ; l = dx*cos - dz*sin
    ld a, [wDx]
    ld e, a
    ld a, [wDx + 1]
    ld d, a
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, e
    ld [wTa], a
    ld a, d
    ld [wTa + 1], a
    ld a, [wDz]
    ld e, a
    ld a, [wDz + 1]
    ld d, a
    ld a, [wCos]
    ld c, a
    call SMul16
    ld a, [wTa]
    add e
    ld [wTa], a
    ld a, [wTa + 1]
    adc d
    ld [wTa + 1], a                 ; forward distance (8.8)
    ld a, [wDx]
    ld e, a
    ld a, [wDx + 1]
    ld d, a
    ld a, [wCos]
    ld c, a
    call SMul16
    ld a, e
    ld [wTb], a
    ld a, d
    ld [wTb + 1], a
    ld a, [wDz]
    ld e, a
    ld a, [wDz + 1]
    ld d, a
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, [wTb]
    sub e
    ld [wTb], a
    ld a, [wTb + 1]
    sbc d
    ld [wTb + 1], a                 ; lateral offset (8.8)
    ld a, [wTa + 1]
    bit 7, a
    jp nz, .next                    ; behind
    ld b, a
    ld a, [wTa]
    or b
    jp z, .next
    ld a, [wShRange]
    cp b
    jp c, .next                     ; farther than range
    ; |lateral| < hitbox width = (wid / 2) units
    ld a, [wTb]
    ld c, a
    ld a, [wTb + 1]
    ld b, a
    bit 7, b
    jr z, .lp
    xor a
    sub c
    ld c, a
    ld a, 0
    sbc b
    ld b, a
.lp:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    swap a
    ld e, a
    ld d, 0
    ld hl, EnemyParams + 8
    add hl, de
    ld a, [hl]                      ; wid
    srl a
    ld d, a                         ; width high byte (units)
    ld a, [hl]
    and 1
    rrca
    ld e, a                         ; width low byte (0 or 128)
    ld a, c
    sub e
    ld a, b
    sbc d
    jp nc, .next                    ; |lateral| >= width
    ; nearest so far?
    ld a, [wTa]
    ld c, a
    ld a, [wTa + 1]
    ld b, a
    ld a, [wBestF + 1]
    cp b
    jr c, .next
    jr nz, .better
    ld a, [wBestF]
    cp c
    jr c, .next
    jr z, .next
.better:
    ld a, c
    ld [wBestF], a
    ld a, b
    ld [wBestF + 1], a
    ld a, [wObjI]
    ld [wBestI], a
.next:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    ld b, a
    ld a, [wEnN]
    cp b
    jp nz, .loop
    ; wake every idle enemy in the room (gunfire)
    xor a
    ld [wObjI], a
.wake:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnRoom
    add hl, de
    ld a, [wRoom]
    cp [hl]
    jr nz, .wnext
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    and a
    jr nz, .wnext
    ld [hl], EN_ALERT
.wnext:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    ld b, a
    ld a, [wEnN]
    cp b
    jr nz, .wake
    ld a, [wBestI]
    cp $FF
    ret z
    ld [wObjI], a
    call Rnd
    ld hl, wShMask
    and [hl]
    ld hl, wShMin
    add [hl]
    ld [wShDmg], a
    ld a, [wBestI]
    ld [wObjI], a
    ld a, [wShDmg]
    call DamageEnemy
    ld a, [wShSplash]
    and a
    ret z
    ; splash: other live enemies within the radius of the target take half
    ld a, [wBestI]
    ld [wTgtI], a
    ld [wObjI], a
    call LoadEnPos
    ld a, [wEx]
    ld [wTgtX], a
    ld a, [wEz]
    ld [wTgtZ], a
    xor a
    ld [wObjI], a
.splash:
    ld a, [wObjI]
    ld b, a
    ld a, [wTgtI]
    cp b
    jr z, .snext
    ld e, b
    ld d, 0
    ld hl, wEnRoom
    add hl, de
    ld a, [wRoom]
    cp [hl]
    jr nz, .snext
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_DYING
    jr nc, .snext
    ld hl, wEnX
    add hl, de
    ld a, [wTgtX]
    sub [hl]
    jr nc, .sx
    cpl
    inc a
.sx:
    ld b, a
    ld a, [wShSplash]
    cp b
    jr c, .snext
    ld hl, wEnZ
    add hl, de
    ld a, [wTgtZ]
    sub [hl]
    jr nc, .sz
    cpl
    inc a
.sz:
    ld b, a
    ld a, [wShSplash]
    cp b
    jr c, .snext
    ld a, [wShDmg]
    srl a
    call DamageEnemy
.snext:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    ld b, a
    ld a, [wEnN]
    cp b
    jr nz, .splash
    ret

; ---- per-frame combat update ---------------------------------------------------------------

; Player shots, enemy AI, player death (the world reloads after a short freeze).
CombatUpdate::
    call Rnd
    call PlayerShot
    ld a, BANK(AiTick)
    ld [rROMB0], a
    call AiTick
    ld a, [wHP]
    and a
    ret nz
    ; dead: count the freeze, then reload the level
    ld a, [wMoveDt]
    ld b, a
    ld a, [wDeadTimer]
    add b
    ld [wDeadTimer], a
    cp 90
    ret c
    xor a
    ld [wDeadTimer], a
    ld [wHaveKeys], a
    ld a, [wLevel]
    call LoadLevel
    jp WpnInit
