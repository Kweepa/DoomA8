; Gameplay: HUD, pickups, player shots, enemy AI, damage, death.
; Positions are integer cells (cam x/z high bytes) plus 8-bit fractions.

INCLUDE "hw.inc"
INCLUDE "sndids.inc"
INCLUDE "map_fields.inc"
INCLUDE "wpn_ids.inc"

INCLUDE "en.inc"

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

; ---- HUD (gbc/hud.asm, ROMX) -------------------------------------------------------------
; The banked routines map their bank; callers re-map what they were reading. The level bank is
; restored after the message calls (they run inside movement / pickup code).

HudInit::
    ld a, BANK(HudInitB)
    ld [rROMB0], a
    jp HudInitB

HudUpdate::
    ld a, BANK(HudUpdateB)
    ld [rROMB0], a
    jp HudUpdateB

; A = TH_* type: "+<name>" on the message row.
HudGot::
    push af
    ld a, BANK(HudGotB)
    ld [rROMB0], a
    pop af
    call HudGotB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ret

; A = door key: "Need a <key> keycard" / "Opened elsewhere".
HudKeyReq::
    push af
    ld a, BANK(HudKeyReqB)
    ld [rROMB0], a
    pop af
    call HudKeyReqB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ret

; ---- pickups -----------------------------------------------------------------------------

; A8 try_thing_pickup: walk-over things of the current room. After a grab nothing is taken for
; PICKUP_HOLD_MS, and the scan ends at the first item used up. Reach: Chebyshev <= TH_GRAB_R from the
; player's cell to the TH_FOOT_SX square at the thing (A8 near_box_xz), and the player's feet-to-head
; span overlapping [y, y + TH_FOOT_SX) (player_overlaps_y). Refused items (at the cap, already owned)
; stay on the floor.
PickupScan::
    ld a, [wHP]
    and a
    ret z                           ; dead: frozen
    ld a, [wPickupMs]
    ld b, a
    ld a, [wPickupMs + 1]
    or b
    jr z, .go
    ld a, [wDtMs]
    ld b, a
    ld a, [wPickupMs]
    sub b
    ld [wPickupMs], a
    ld a, [wPickupMs + 1]
    sbc 0
    ld [wPickupMs + 1], a
    ret nc                          ; still > 0 (or exactly 0: the next frame is free)
    xor a
    ld [wPickupMs], a
    ld [wPickupMs + 1], a
.go:
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
    ld [wPkX], a
    ld a, [hl+]
    ld [wPkY], a
    ld a, [hl+]
    ld [wPkZ], a
    inc hl
    push hl
    ld a, [wPkType]
    cp TH_LIGHTPOST
    jr nc, .next                    ; props (lightpost, barrel) are not pickups
    ld a, [wPkIdx]
    ld e, a
    ld d, 0
    ld hl, wThTaken
    add hl, de
    ld a, [hl]
    and a
    jr nz, .next
    ld a, [wCamX + 1]
    ld b, a
    ld a, [wPkX]
    ld c, a
    call NearAxis
    cp TH_GRAB_R + 1
    jr nc, .next
    ld a, [wCamZ + 1]
    ld b, a
    ld a, [wPkZ]
    ld c, a
    call NearAxis
    cp TH_GRAB_R + 1
    jr nc, .next
    ld a, [wPkY]
    ld [wBoxY], a
    ld a, TH_FOOT_SX
    ld [wBoxSY], a
    call PlayerOverlapsY
    jr nc, .next
    ld a, [wPkType]
    call ApplyPickup
    jr nc, .next                    ; refused: stays on the floor
    ld a, [wPkIdx]
    ld e, a
    ld d, 0
    ld hl, wThTaken
    add hl, de
    ld [hl], 1
    ld a, LOW(PICKUP_HOLD_MS)
    ld [wPickupMs], a
    ld a, HIGH(PICKUP_HOLD_MS)
    ld [wPickupMs + 1], a
    pop hl
    ld a, [wPkType]                 ; A8 pickup_sound: ammo WPNUP, the rest ITEMUP
    cp SND_PICK_N
    jr nc, .noSnd
    ld e, a
    ld d, 0
    ld hl, SndPick
    add hl, de
    ld a, [hl]
    call PlaySound
.noSnd:
    ld a, [wPkType]                 ; A8 hud_got
    jp HudGot                       ; one grab per hold: the scan ends
.next:
    pop hl
    ld a, [wPkI]
    inc a
    ld [wPkI], a
    ld b, a
    ld a, [wPkN]
    cp b
    jp nz, .loop
    ret

; A8 near_box_xz axis: B = player cell, C = box start (size TH_FOOT_SX) -> A = distance to the box
; (0 inside; beyond the far end it is measured from start + size).
NearAxis:
    ld a, b
    cp c
    jr c, .lo
    ld a, c
    add TH_FOOT_SX
    ld d, a
    ld a, b
    cp d
    jr nc, .hi
    xor a
    ret
.lo:
    ld a, c
    sub b
    ret
.hi:
    ld a, b
    sub d
    ret

; A = thing type -> carry = used up. Banked: gbc/player.asm; the object bank is mapped again for the
; scan loop.
ApplyPickup::
    push af
    ld a, BANK(ApplyPickupB)
    ld [rROMB0], a
    pop af
    call ApplyPickupB
    push af
    ld a, [wObjBank]
    ld [rROMB0], a
    pop af
    ret

; ---- HUD ---------------------------------------------------------------------------------

; VBlank: the four HUD shadow rows (14-17, all 20 columns) into the map, then the staged palettes.
HudBlit::
    xor a
    ldh [rVBK], a
    ld hl, wHudRows
    ld de, VRAM_MAP0 + 32 * 14
    ld c, 4
.row:
    ld b, 20
.col:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .col
    ld a, e
    add 32 - 20
    ld e, a
    jr nc, .nc
    inc d
.nc:
    dec c
    jr nz, .row
    ld a, [wPalDirty]
    and a
    ret z
    xor a
    ld [wPalDirty], a
    ld a, $80                       ; BG palette 0, auto-increment
    ldh [rBCPS], a
    ld hl, wPalStage
    ld b, 32
.pal:
    ld a, [hl+]
    ldh [rBCPD], a
    dec b
    jr nz, .pal
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
DeltaFromPlayer::
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

; A8 take_damage (no god mode): A = damage, scaled by the skill first (wDifficulty 0: / 2, at least 1;
; 2: x 3/2, at most 255). Armour saves 5/16 (green: /4 + /16)
; or 1/2 (blue) of the hit; if armour then wraps past 200 it is used up. HP floors at 0 (the death
; wait is CombatUpdate). Starts the HURT_FLASH_MS red border (gbc/hud.asm PaletteUpdate).
PlayerDamage::
    ld c, a
    ld a, [wHP]
    and a
    ret z                           ; already dead
    ld a, [wDifficulty]
    dec a
    jr z, .skill
    ld b, c
    srl b                           ; dmg / 2
    inc a
    jr nz, .uv
    ld c, b                         ; too young to die
    inc b
    dec b
    jr nz, .skill
    inc c                           ; at least 1
    jr .skill
.uv:
    ld a, c                         ; ultra-violence
    add b
    jr nc, .cap
    ld a, 255
.cap:
    ld c, a
.skill:
    ld a, [wArmor]
    and a
    jr z, .hp
    ld a, [wArmorKind]
    and a
    jr nz, .blue
    ld a, c
    srl a
    srl a                           ; dmg / 4
    ld b, a
    ld a, c
    swap a
    and $0F                         ; dmg / 16
    add b
    jr .saved
.blue:
    ld a, c
    srl a                           ; dmg / 2
.saved:
    and a
    jr z, .hp                       ; tiny hit: nothing absorbed
    ld b, a
    ld a, c
    sub b
    ld c, a
    ld a, [wArmor]
    sub b
    ld [wArmor], a
    cp 201
    jr c, .hp                       ; (A8: > 200 means it underflowed)
    xor a
    ld [wArmor], a
    ld [wArmorKind], a
.hp:
    ld a, LOW(HURT_FLASH_MS)
    ld [wHurtMs], a
    ld a, HIGH(HURT_FLASH_MS)
    ld [wHurtMs + 1], a
    ld a, [wHP]
    sub c
    jr nc, .st
    xor a
.st:
    ld [wHP], a
    ld a, SND_PLPAIN                ; A8 take_damage: hurt grunt, or the death cry at 0 hp
    jr nz, .snd
    ld a, SND_PLDETH
.snd:
    jp PlaySound

; Enemy wObjI takes A damage: the A8 damage_enemy port (gbc/ai.asm AiDamageEnemy, bank 11).
DamageEnemy:
    push af
    ld a, BANK(AiDamageEnemy)
    ld [rROMB0], a
    pop af
    jp AiDamageEnemy

; ---- level mechanics (gbc/level.asm) ----------------------------------------------------------

; Once per game frame after the player has moved: switch bumps, triggers, unhide timers. A level
; change asked for by the banked code (end trigger / switch) is done here: keys are per level, the
; loadout stays (A8 next_level); after the last level the episode starts over.
; try_proximity + elevator motion, between the move and UpdateFloor (A8 frame order).
ElevPre::
    ld a, BANK(ElevPreB)
    ld [rROMB0], a
    call ElevPreB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ret

LevelUpdate::
    ld a, [wHP]
    and a
    ret z                           ; dead: frozen
    ld a, BANK(LevelUpdateB)
    ld [rROMB0], a
    call LevelUpdateB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ld a, [wNextLevelReq]
    and a
    ret z
    xor a
    ld [wNextLevelReq], a
    ld [wHaveKeys], a
    ld a, [wLevel]
    inc a
    cp MAP_NLEVELS
    jr c, .go
IF !DEF(TEST_EXIT) && !DEF(LIVETEST)
    ld a, 1                         ; episode done: the menu, ending pages first (A8 episode_done)
    ld [wGameDone], a
    jp Restart
ELSE
    xor a
ENDC
.go:
    call LoadLevel
    jp EnterCard

; ---- "entering" card (A8 loader.asm enter_card) -----------------------------------------------

DEF ENTER_HOLD_FRAMES EQU 118            ; ENTER_HOLD_MS (2000) / 17 ms per VBlank
DEF CARD_ROW          EQU 6              ; viewport tile row of "entering"; the map name is the next row

; After the first load and after a level change (not after death): the viewport is black, the weapon
; sprites are off (hCard), "entering" and the map name (payload header + 23, NUL-terminated) are
; centred as font tiles drawn into the framebuffer (hud.asm HudCardTextB), held ENTER_HOLD_FRAMES
; VBlanks. Input counters and the frame clock restart afterwards.
EnterCard::
    ld a, 1
    ldh [hCard], a
    ld hl, wHudRows                 ; HUD rows blank during the card
    ld b, 4 * 20
    xor a
.clr:
    ld [hl+], a
    dec b
    jr nz, .clr
    call ClearFBLive
    ld hl, wMsgTmp
    ld de, .entering
.en:
    ld a, [de]
    inc de
    ld [hl+], a
    and a
    jr nz, .en
    ld c, CARD_ROW
    call CardText
    ld c, 0                         ; map name -> wMsgTmp (max 16 columns)
.nm:
    ld hl, wMap + 23
    ld b, 0
    add hl, bc
    ld a, 2
    ldh [rSVBK], a
    ld d, [hl]
    ld a, 1
    ldh [rSVBK], a
    ld hl, wMsgTmp
    add hl, bc
    ld [hl], d
    ld a, d
    and a
    jr z, .nmDone
    inc c
    ld a, c
    cp 16
    jr c, .nm
    ld hl, wMsgTmp + 16
    ld [hl], 0
.nmDone:
    ld c, CARD_ROW + 1
    call CardText
    ld a, BANK(HudCardPalB)
    ld [rROMB0], a
    call HudCardPalB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ldh a, [hShow]                  ; text frame into the hidden bank, then flip
    xor 1
    call CopyFBHBlank
    call WaitVBlank
    ldh a, [hShow]
    xor 1
    ldh [hShow], a
    call ShowBank
    call HudBlit                    ; black / white palette 0
    ld b, ENTER_HOLD_FRAMES
.hold:
    call WaitVBlank
    dec b
    jr nz, .hold
    ld hl, wHudRows
    ld b, 4 * 20
    xor a
.clr2:
    ld [hl+], a
    dec b
    jr nz, .clr2
    ld [wStatusMs], a
    ld [wStatusMs + 1], a
    ld [wFireEvent], a
    ld a, $FE                       ; room palette is rebuilt by HudUpdate (paper back from black)
    ld [wPalRoom], a
    call HudUpdate
    ld a, [wLevelBank]
    ld [rROMB0], a
    call WaitVBlank
    call HudBlit
    di                              ; no input or time carried over from the hold
    xor a
    ld [wPadLatch], a
    ld [wAccF], a
    ld [wAccB], a
    ld [wAccTR], a
    ld [wAccTL], a
    ld [wAccSR], a
    ld [wAccSL], a
    ldh a, [hFrame]
    ldh [hLastFrame], a
    ei
    xor a
    ldh [hCard], a
    ret
.entering:
    db "entering", 0

; C = tile row, text in wMsgTmp.
CardText:
    ld a, BANK(HudCardTextB)
    ld [rROMB0], a
    call HudCardTextB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ret

; ---- player shots ----------------------------------------------------------------------

; Consumes wFireEvent: the shot code is in bank 11 (gbc/ai.asm PlayerShotB, next to line of sight and
; AiDamageEnemy).
PlayerShot::
    ld a, [wFireEvent]
    and a
    ret z
    xor a
    ld [wFireEvent], a
    ld a, BANK(PlayerShotB)
    ld [rROMB0], a
    call PlayerShotB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ret

; ---- per-frame combat update ---------------------------------------------------------------

; Player shots, enemy AI, player death (the world reloads after a short freeze).
CombatUpdate::
    ld a, [wHP]
    and a
    jr z, .dead
    call Rnd
    call PlayerShot
    ld a, BANK(AiTick)
    ld [rROMB0], a
    jp AiTick
.dead:                              ; A8 death_restart: the game is frozen; scream + PL_DEATH_WAIT_MS
    ld a, [wDtMs]
    ld b, a
    ld a, [wDeadMs]
    add b
    ld [wDeadMs], a
    ld a, [wDeadMs + 1]
    adc 0
    ld [wDeadMs + 1], a
    cp HIGH(PL_DEATH_WAIT_MS)
    ret c
    jr nz, .go
    ld a, [wDeadMs]
    cp LOW(PL_DEATH_WAIT_MS)
    ret c
.go:
    xor a
    ld [wHaveKeys], a
    ld a, [wLevel]
    call LoadLevel
    jp WpnInit                      ; reset_loadout (also clears wDeadMs)
