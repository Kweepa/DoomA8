; Enemy AI, in ROM bank 11 (called through AiTick from CombatUpdate). The state machine and the
; per-type AI are a translation of the A8 build (src/enemy.asm enemies_update / enemy_anim_step /
; eu_idle / eu_approach / select_dodge_dir / damage_enemy, src/ai_poss|pinky|imp|baron.asm); the
; A8 constants and per-type tables come from tools/gbc_a8const.py. Line of sight is the A8 segment
; test (util.asm line_solids_blocked), fireballs the A8 rocket slots (rocket.asm, ai_imp .throw /
; .z_aim). The enemy step probes (EnemyMoveOk) are GBC collision code with the A8 rules.

INCLUDE "hw.inc"
INCLUDE "sndids.inc"
INCLUDE "map_fields.inc"
INCLUDE "en.inc"
INCLUDE "a8enmeta.inc"


SECTION "ai", ROMX, BANK[11]

; Carry = the enemy (wObjI) may stand at cell (wColX, wColZ): inside its room's colliders and
; not blocked by crates / platforms / locked doors. The collision tests use the player's feet,
; so the eye height is swapped to the enemy's for the call (as the A8 engine does).
EnemyCellOk:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnY
    add hl, de
    ld a, [hl]
; A = floor y of whoever stands there.
CellOkY:
    ld b, a
    ld a, [wCamY + 1]
    ld [wLedgeSaveY], a
    ld a, b
    add EYE_HEIGHT
    ld [wCamY + 1], a
    call InRoomInset
    jr nc, .no
    call SolidAt
    jr c, .no
    ld a, [wLedgeSaveY]
    ld [wCamY + 1], a
    scf
    ret
.no:
    ld a, [wLedgeSaveY]
    ld [wCamY + 1], a
    and a
    ret

; wColX/wColZ, wFbProbe = probe y. Carry = found; wFloorTmp = the highest walkable surface at or
; below the probe: a collider floor (the lowest one; a lid above the probe does not count), a crate
; top or a solid platform (A8 floor_below).
FloorBelow:
    call PeekRcFloor                ; wFound, wFloorTmp = lowest collider y
    jr nc, .surf
    ld a, [wFbProbe]
    ld b, a
    ld a, [wFloorTmp]
    cp b
    jr z, .surf
    jr c, .surf
    xor a
    ld [wFound], a
.surf:
    ld a, [wCrN]
    and a
    jr z, .plats
    ld c, 0
.cl:
    ld b, 0
    ld hl, wCrX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wCrZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wCrSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wCrSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInBoxXZ
    jr nc, .cn
    ld hl, wCrY
    add hl, bc
    ld a, [hl]
    ld hl, wCrSY
    add hl, bc
    add [hl]                        ; crate top
    call .cand
.cn:
    inc c
    ld a, [wCrN]
    cp c
    jr nz, .cl
.plats:
    ld a, [wPlN]
    and a
    jr z, .elevs
    ld c, 0
.pl:
    ld b, 0
    ld hl, wPlX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wPlZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wPlSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wPlSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInBoxXZ
    jr nc, .pn
    ld hl, wPlY
    add hl, bc
    ld a, [hl]
    call .cand
.pn:
    inc c
    ld a, [wPlN]
    cp c
    jr nz, .pl
.elevs:                             ; A8 floor_below: elevator tops of the room
    ld a, [wMapHdr + H_NELEVS]
    and a
    jr z, .done
    ld [wLvN], a
    ld c, 0
.ev:
    push bc
    ld a, F_ELEV_ROOM
    call MapGet
    ld b, a
    ld a, [wRoom]
    cp b
    jr nz, .evn
    pop bc
    push bc
    ld hl, wBoxX
    ld a, F_ELEV_X
    ld b, 6
.evbox:
    push af
    push hl
    push bc
    call MapGet
    pop bc
    pop hl
    ld [hl+], a
    pop af
    inc a
    dec b
    jr nz, .evbox
    pop bc
    push bc
    call PointInFloorXZ
    jr nc, .evn
    pop bc
    push bc
    ld b, 0
    ld hl, wElevY
    add hl, bc
    ld a, [wBoxSY]
    add [hl]
    call .cand
.evn:
    pop bc
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .ev
.done:
    ld a, [wFound]
    rra
    ret
; A = candidate surface y: keep the highest one not above the probe.
.cand:
    ld b, a
    ld a, [wFbProbe]
    cp b
    ret c
    ld a, [wFound]
    and a
    jr z, .take
    ld a, [wFloorTmp]
    cp b
    ret nc
.take:
    ld a, b
    ld [wFloorTmp], a
    ld a, 1
    ld [wFound], a
    ret

; Carry = the enemy wObjI may step to (wColX, wColZ): EnemyCellOk, and the floor there is within
; STEP_UP of its feet (no walking into thin air, as on the A8). wAiFloorY = that floor.
EnemyMoveOk:
    call EnemyCellOk
    ret nc
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnY
    add hl, de
    ld a, [hl]
    ld [wAiOldY], a
    add STEP_UP
    jr nc, .p
    ld a, 255
.p:
    ld [wFbProbe], a
    call FloorBelow
    ret nc
    ld a, [wFloorTmp]
    ld [wAiFloorY], a
    ld b, a
    ld a, [wAiOldY]
    ld c, a
    ld a, b
    sub c
    jr nc, .d
    cpl
    inc a
.d:
    cp STEP_UP + 1
    ret

; Move enemy wObjI toward heading wAng by speed * dt; slide on X then Z.
; ---- small helpers ---------------------------------------------------------------------------

; HL = &array[wObjI] (clobbers A, D, E).
MACRO ENPTR
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, \1
    add hl, de
ENDM

; HL = &array[wAiI] (fireball slot; clobbers A, D, E).
MACRO PRPTR
    ld a, [wAiI]
    ld e, a
    ld d, 0
    ld hl, \1
    add hl, de
ENDM

; wDist = max(|wDx|, |wDz|) (8.8): the Chebyshev distance the A8 AI uses.
CalcDist:
    call AbsPair
    ld a, b
    cp d
    jr c, .de
    jr nz, .bc
    ld a, c
    cp e
    jr c, .de
.bc:
    ld a, c
    ld [wDist], a
    ld a, b
    ld [wDist + 1], a
    ret
.de:
    ld a, e
    ld [wDist], a
    ld a, d
    ld [wDist + 1], a
    ret

; A = new state for wObjI; resets the state timer and the fired flag.
; A8 ai_imp / ai_baron .fireball_live: carry = a fireball is in flight.
FireballAlive:
    ld hl, wPrOn
    ld de, wPrFl
    ld b, RKT_MAX
.l:
    ld a, [hl+]
    and a
    jr z, .n
    ld a, [de]
    and RKT_F_FIREBALL
    jr nz, .yes
.n:
    inc de
    dec b
    jr nz, .l
    and a
    ret
.yes:
    scf
    ret

; ---- A8 rockets / fireballs (src/rocket.asm, src/ai_imp.asm .throw / .z_aim) ----------------

; A8 rkt_alloc: carry = free slot in wAiI.
RktAlloc:
    ld hl, wPrOn
    ld b, 0
.l:
    ld a, [hl+]
    and a
    jr z, .got
    inc b
    ld a, b
    cp RKT_MAX
    jr nz, .l
    and a
    ret
.got:
    ld a, b
    ld [wAiI], a
    scf
    ret

; A = l (signed pose byte), C = t (signed trig) -> DE = sign * (|l| * |t|) >> 3 (8.8; the GBC entity
; transform for enemy poses, shift 4: gbc_entity.mulsh).
MulSh3:
    ld b, a
    xor c
    push af
    ld a, b
    call Abs8
    ld b, a
    ld a, c
    call Abs8
    call Mul8u                      ; HL = |t| * |l|
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    pop af
    bit 7, a
    jr z, .p
    xor a
    sub l
    ld l, a
    ld a, 0
    sbc h
    ld h, a
.p:
    ld d, h
    ld e, l
    ret

; A8 ent_vert_world: B = vertex -> wOrgX / Y / Z = world 8.8 of that bone in enemy wObjI's attack
; pose (en_frame of the attack clip). World offset R(-en_rot), as the meshes are drawn.
EnVertWorld:
    push bc
    ld a, EM_ATK_S
    call EnMetaGet
    ld b, a
    ENPTR wEnFrame
    ld a, [hl]
    add b                           ; logical frame
    push af
    ENPTR wEnType
    ld c, [hl]
    pop af
    pop de
    ld b, d                         ; B = vertex
    call EnVertLocal                ; D = lx, B = ly, E = lz (ROM0; maps this bank back)
    ld a, d
    ld [wLnD], a                    ; lx
    ld a, e
    ld [wLnPx], a                   ; lz
    ld a, b                         ; y = en_y + ly << 4
    ld l, a
    add a
    sbc a
    ld h, a
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    push hl
    ENPTR wEnY
    ld b, [hl]
    pop hl
    ld a, h
    add b
    ld [wOrgY + 1], a
    ld a, l
    ld [wOrgY], a
    ENPTR wEnRot                    ; psi = -en_rot
    xor a
    sub [hl]
    ld [wLnT], a
    ; x = en_x + mulsh(lx, cos) - mulsh(lz, sin)
    call .cos
    ld a, [wLnD]
    call MulSh3
    push de
    call .sin
    ld a, [wLnPx]
    call MulSh3
    pop hl
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a
    push hl
    ENPTR wEnX
    ld b, [hl]
    pop hl
    ld a, l
    ld [wOrgX], a
    ld a, h
    add b
    ld [wOrgX + 1], a
    ; z = en_z + mulsh(lx, sin) + mulsh(lz, cos)
    call .sin
    ld a, [wLnD]
    call MulSh3
    push de
    call .cos
    ld a, [wLnPx]
    call MulSh3
    pop hl
    add hl, de
    push hl
    ENPTR wEnZ
    ld b, [hl]
    pop hl
    ld a, l
    ld [wOrgZ], a
    ld a, h
    add b
    ld [wOrgZ + 1], a
    ret
.cos:
    ld a, [wLnT]
    add 64
    jr .trig
.sin:
    ld a, [wLnT]
.trig:
    ld l, a
    ld h, HIGH(SinTab)
    ld c, [hl]
    ret

; A8 .throw: a fireball from the higher wrist of the attack pose, aimed in 3D at the player.
SpawnFireball:
    call FireballAlive
    ret c
    call RktAlloc
    ret nc
    ld b, RKT_WRIST_L
    call EnVertWorld
    ld a, [wOrgY + 1]
    push af
    ld b, RKT_WRIST_R
    call EnVertWorld
    pop af
    ld b, a
    ld a, [wOrgY + 1]
    cp b
    jr nc, .hand                    ; right wrist at least as high
    ld b, RKT_WRIST_L
    call EnVertWorld
.hand:
    ld hl, wOrgX                    ; A8 rkt_fill_slot
    ld de, wPrXL
    call .put2
    ld de, wPrYL
    call .put2
    ld de, wPrZL
    call .put2
    ENPTR wEnType
    ld a, [hl]
    cp ENT_BARON
    ld b, RKT_F_FIREBALL
    jr nz, .fl
    ld b, RKT_F_FIREBALL | RKT_F_BARON
.fl:
    PRPTR wPrFl
    ld [hl], b
    PRPTR wPrOwn
    ld [hl], RKT_OWN_EN
    PRPTR wPrAcc
    ld [hl], 0
    PRPTR wPrLifeL
    ld [hl], LOW(RKT_LIFE_MS)
    PRPTR wPrLifeH
    ld [hl], HIGH(RKT_LIFE_MS)
    PRPTR wPrOn
    ld [hl], 1
    jp ZAim
; HL = source lo, hi; DE = slot array (lo); the hi array is the next one (+ RKT_MAX). HL += 2.
.put2:
    ld a, [wAiI]
    add e
    ld e, a
    ld a, d
    adc 0
    ld d, a
    ld a, [hl+]
    ld [de], a
    ld a, e
    add RKT_MAX
    ld e, a
    ld a, d
    adc 0
    ld d, a
    ld a, [hl+]
    ld [de], a
    ret
ASSERT wPrX == wPrXL + RKT_MAX && wPrY == wPrYL + RKT_MAX && wPrZ == wPrZL + RKT_MAX

; A8 .z_aim: straight line to the chest (cam_y - 1) at speed 16: per axis v = |d| << 12 / len with
; len = max + 3/8 (sum - max) (all 8-bit, as on the 6502).
ZAim:
    PRPTR wPrX
    ld a, [wCamX + 1]
    sub [hl]
    ld [wZcSg], a
    PRPTR wPrY
    ld a, [wCamY + 1]
    scf
    sbc [hl]                        ; clc / sbc: cam_y - y - 1
    ld [wZcSg + 1], a
    PRPTR wPrZ
    ld a, [wCamZ + 1]
    sub [hl]
    ld [wZcSg + 2], a
    ld a, [wZcSg]
    call Abs8
    ld [wZcAd], a
    ld b, a
    ld a, [wZcSg + 1]
    call Abs8
    ld [wZcAd + 1], a
    ld c, a
    ld a, [wZcSg + 2]
    call Abs8
    ld [wZcAd + 2], a
    ld d, a
    ld a, b                         ; sum (8-bit)
    add c
    add d
    ld e, a
    ld a, b                         ; max
    cp c
    jr nc, .m1
    ld a, c
.m1:
    cp d
    jr nc, .m2
    ld a, d
.m2:
    ld b, a                         ; B = max
    ld a, e
    sub b
    srl a
    srl a
    ld c, a                         ; q = (sum - max) >> 2
    srl a
    add c
    add b                           ; len = max + q + q / 2
    jr nz, .len
    inc a
.len:
    ld [wLnD], a
    ld de, wPrVXL
    ld c, 0
.ax:
    push bc
    push de
    ld b, 0
    ld hl, wZcAd
    add hl, bc
    ld a, [hl]                      ; |d| << 12: B = |d| >> 4, D = (|d| & 15) << 4, E = 0
    ld b, a
    and 15
    swap a
    ld d, a
    ld a, b
    swap a
    and 15
    ld b, a
    ld e, 0
    ld a, [wLnD]
    ld c, a
    call Div24x8                    ; DE = v
    pop hl                          ; HL = this axis' VxL array
    pop bc
    push bc
    push hl
    ld b, 0
    ld hl, wZcSg
    add hl, bc
    bit 7, [hl]
    jr z, .pos
    xor a
    sub e
    ld e, a
    ld a, 0
    sbc d
    ld d, a
.pos:
    pop hl
    push hl
    ld a, [wAiI]
    add l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    ld [hl], e                      ; VxL[slot]
    ld bc, RKT_MAX
    add hl, bc
    ld [hl], d                      ; VxH[slot]
    pop hl
    ld bc, 2 * RKT_MAX              ; next axis: VxL -> VyL -> VzL
    add hl, bc
    ld d, h
    ld e, l
    pop bc
    inc c
    ld a, c
    cp 3
    jr nz, .ax
    ret
ASSERT wPrVXH == wPrVXL + RKT_MAX && wPrVYL == wPrVXL + 2 * RKT_MAX && wPrVYH == wPrVYL + RKT_MAX
ASSERT wPrVZL == wPrVYL + 2 * RKT_MAX && wPrVZH == wPrVZL + RKT_MAX

; A8 update_rockets.
ProjUpdate::
    xor a
    ld [wAiI], a
.l:
    PRPTR wPrOn
    ld a, [hl]
    and a
    call nz, RktTick
    ld hl, wAiI
    inc [hl]
    ld a, [hl]
    cp RKT_MAX
    jr nz, .l
    ret

; A8 rkt_tick: RKT_TICK_MS steps (x, z, y, then the owner's contact test), life. A player rocket that
; would explode while another explosion shows waits (RKT_F_PEND) until it is over.
RktTick:
    PRPTR wPrAcc
    ld a, [wDtMs]
    add [hl]
    ld [wRkAcc], a
    ld a, 0
    adc 0
    ld [wRkAcc + 1], a
.tick:
    ld a, [wRkAcc + 1]
    and a
    jr nz, .step
    ld a, [wRkAcc]
    cp RKT_TICK_MS
    jr c, .tdone
.step:
    ld a, [wRkAcc]
    sub RKT_TICK_MS
    ld [wRkAcc], a
    ld a, [wRkAcc + 1]
    sbc 0
    ld [wRkAcc + 1], a
    call RktMoveX
    call RktDead
    jr c, .tdone
    call RktMoveZ
    call RktDead
    jr c, .tdone
    call RktMoveY
    call RktDead
    jr c, .tdone
    call RktHit
    PRPTR wPrOn
    ld a, [hl]
    and a
    ret z                           ; gone
    call RktDead
    jr c, .tdone                    ; pending
    jr .tick
.tdone:
    ld a, [wRkAcc]
    ld b, a
    PRPTR wPrAcc
    ld [hl], b
    PRPTR wPrOn
    ld a, [hl]
    and a
    ret z
    call RktHit                     ; rkt_contact
    PRPTR wPrOn
    ld a, [hl]
    and a
    ret z
    PRPTR wPrFl
    ld a, [hl]
    and RKT_F_PEND
    jr z, .life
    ld a, [wFxMs]
    ld b, a
    ld a, [wFxMs + 1]
    or b
    jr nz, .life
    jp RktExplode                   ; the explosion in view is over
.life:
    PRPTR wPrLifeL
    ld a, [wDtMs]
    ld b, a
    ld a, [hl]
    sub b
    ld [hl], a
    push af
    PRPTR wPrLifeH
    pop af
    ld a, [hl]
    sbc 0
    ld [hl], a
    ret nc
    jp RktExplode                   ; out of life: a fireball clears, a rocket explodes

; A8 rkt_impact: a wall, floor, ceiling or solid. A fireball clears, a rocket explodes.
RktImpact:
    PRPTR wPrFl
    ld a, [hl]
    and RKT_F_FIREBALL
    jp nz, RktClear
    jp RktExplode

; A8 rkt_contact: the owner's targets.
RktHit:
    PRPTR wPrOwn
    ld a, [hl]
    and a
    jp nz, RktHitPlayer             ; enemy fireball
    ; fall through (player rocket)

; A8 rkt_hit_enemies: a barrel under the rocket goes off with it; a live enemy of the room within
; RKT_HIT_R cells (Chebyshev) in X / Z and RKT_HIT_R .. ENEMY_CULL_H in Y explodes it.
RktHitEnemies:
    call RktTouchBarrel
    PRPTR wPrOn
    ld a, [hl]
    and a
    ret z
    ld a, [wEnN]
    and a
    ret z
    xor a
    ld [wObjI], a
.l:
    ENPTR wEnState
    ld a, [hl]
    cp EN_DYING
    jr nc, .n
    ENPTR wEnRoom
    ld a, [wRoom]
    cp [hl]
    jr nz, .n
    ENPTR wEnX
    ld b, [hl]
    PRPTR wPrX
    ld a, [hl]
    sub b
    call Abs8
    cp RKT_HIT_R + 1
    jr nc, .n
    ENPTR wEnZ
    ld b, [hl]
    PRPTR wPrZ
    ld a, [hl]
    sub b
    call Abs8
    cp RKT_HIT_R + 1
    jr nc, .n
    ENPTR wEnY
    ld b, [hl]                      ; y in [en_y, en_y + ENEMY_CULL_H)
    PRPTR wPrY
    ld a, [hl]
    cp b
    jr c, .n
    ld a, b
    add ENEMY_CULL_H
    ld c, a
    ld a, [hl]
    cp c
    jr nc, .n
    jp RktExplode
.n:
    ld hl, wObjI
    inc [hl]
    ld a, [wEnN]
    cp [hl]
    jp nz, .l
    ret

; A8 rkt_explode: a fireball clears; with an explosion already showing the rocket waits (PEND);
; else the blast is placed at the rocket, splashes, shows for EXPLODE_MS and the rocket is gone.
RktExplode:
    PRPTR wPrFl
    ld a, [hl]
    and RKT_F_FIREBALL
    jp nz, RktClear
    ld a, [wFxMs]
    ld b, a
    ld a, [wFxMs + 1]
    or b
    jr z, .go
    PRPTR wPrFl
    ld a, [hl]
    or RKT_F_PEND
    ld [hl], a
    ret
.go:
    call RktPlace
    call RktSplash
    call StartExplosion
    ld a, SND_RXPLOD                ; A8 gex_go
    call PlaySound
    jp RktClear

; A8 rkt_place: blast origin = the rocket (cells), in the player's room.
RktPlace:
    ld a, [wRoom]
    ld [wBlastRoom], a
    PRPTR wPrX
    ld a, [hl]
    ld [wBlast], a
    PRPTR wPrY
    ld a, [hl]
    ld [wBlast + 1], a
    PRPTR wPrZ
    ld a, [hl]
    ld [wBlast + 2], a
    PRPTR wPrXL
    ld a, [hl]
    ld [wBlastFr], a
    PRPTR wPrYL
    ld a, [hl]
    ld [wBlastFr + 1], a
    PRPTR wPrZL
    ld a, [hl]
    ld [wBlastFr + 2], a
    ret

; A8 start_explosion (the particles are not drawn yet): one explosion at a time for EXPLODE_MS.
StartExplosion:
    ld a, LOW(EXPLODE_MS - FX_START_MS)    ; the countdown starts late: elapsed opens at FX_START_MS
    ld [wFxMs], a
    ld a, HIGH(EXPLODE_MS - FX_START_MS)
    ld [wFxMs + 1], a
    ld a, 1
    ld [wFxNew], a
    ld a, [wBlastFr]                       ; origin 8.8
    ld [wFxOrg], a
    ld a, [wBlast]
    ld [wFxOrg + 1], a
    ld a, [wBlastFr + 1]
    ld [wFxOrg + 2], a
    ld a, [wBlast + 1]
    ld [wFxOrg + 3], a
    ld a, [wBlastFr + 2]
    ld [wFxOrg + 4], a
    ld a, [wBlast + 2]
    ld [wFxOrg + 5], a
    ret

; A8 rkt_cheby: A = max(|blast - target|) over x, y, z; target (B, C, D) = x, y, z.
RktCheb3:
    ld a, [wBlast]
    sub b
    call Abs8
    ld e, a
    ld a, [wBlast + 1]
    sub c
    call Abs8
    cp e
    jr c, .y
    ld e, a
.y:
    ld a, [wBlast + 2]
    sub d
    call Abs8
    cp e
    ret nc
    ld a, e
    ret

; A8 rkt_splash: every live enemy of the blast room within RKT_RAD (3D Chebyshev, feet height) takes
; RKT_DMG_BASE + rnd(32).
RktSplash:
    ld a, [wEnN]
    and a
    ret z
    xor a
    ld [wObjI], a
.l:
    ENPTR wEnState
    ld a, [hl]
    cp EN_DYING
    jr nc, .n
    ENPTR wEnRoom
    ld a, [wBlastRoom]
    cp [hl]
    jr nz, .n
    ENPTR wEnX
    ld b, [hl]
    ENPTR wEnY
    ld c, [hl]
    ENPTR wEnZ
    ld d, [hl]
    call RktCheb3
    cp RKT_RAD
    jr nc, .n
    call Rnd
    and 31
    add RKT_DMG_BASE
    call AiDamageEnemy
.n:
    ld hl, wObjI
    inc [hl]
    ld a, [wEnN]
    cp [hl]
    jr nz, .l
    ret

; Thing wTgt field helpers: C = thing index -> A = field.
ThField:
    jp MapGet

; A8 rkt_touch_barrel: a live barrel of the room within RKT_HIT_R of the rocket (its TH_FOOT_SX square,
; near_box_xz) and in Y: the rocket is consumed with its own splash, then the barrel goes off.
RktTouchBarrel:
    ld a, [wMapHdr + H_NTHINGS]
    and a
    ret z
    ld c, 0
.l:
    push bc
    ld a, F_TH_TYPE
    call MapGet
    cp TH_BARREL
    jp nz, .n
    ld b, 0
    ld hl, wThTaken
    add hl, bc
    ld a, [hl]
    and a
    jp nz, .n
    ld a, F_TH_ROOM
    call MapGet
    ld b, a
    ld a, [wRoom]
    cp b
    jp nz, .n
    ld a, F_TH_X
    call MapGet
    ld b, a
    PRPTR wPrX
    ld a, [hl]
    ld e, a
    call NearBox                    ; |rocket - box| beyond the TH_FOOT_SX square
    cp RKT_HIT_R + 1
    jp nc, .n
    ld a, F_TH_Z
    call MapGet
    ld b, a
    PRPTR wPrZ
    ld a, [hl]
    ld e, a
    call NearBox
    cp RKT_HIT_R + 1
    jp nc, .n
    ld a, F_TH_Y
    call MapGet
    ld b, a
    PRPTR wPrY
    ld a, [hl]
    cp b
    jp c, .n
    ld a, b
    add TH_FOOT_SY
    ld [wTgt + 1], a                 ; (C is the thing index: no spare register)
    PRPTR wPrY
    ld a, [hl]
    ld hl, wTgt + 1
    cp [hl]
    jp nc, .n
    pop bc
    push bc
    call RktPlace
    call RktClear
    call RktSplash
    pop bc
    ld a, c
    jp BarrelExplode
.n:
    pop bc
    inc c
    ld a, [wMapHdr + H_NTHINGS]
    cp c
    jp nz, .l
    ret

; A8 near_box_xz axis: B = box start (size TH_FOOT_SX), E = point -> A = distance.
NearBox:
    ld a, e
    cp b
    jr c, .lo
    ld a, b
    add TH_FOOT_SX
    ld d, a
    ld a, e
    cp d
    jr nc, .hi
    xor a
    ret
.lo:
    ld a, b
    sub e
    ret
.hi:
    ld a, e
    sub d
    ret

; ---- barrels (A8 rocket.asm barrel_*) ---------------------------------------------------------

; A = thing index. Splash now; neighbours within RKT_RAD wait BARREL_CHAIN_MS. A taken barrel only
; drops its pending bit.
BarrelExplode:
    ld c, a
    ld b, 0
    ld hl, wThTaken
    add hl, bc
    ld a, [hl]
    and a
    jr z, .go
    ld a, c
    call BarrelClrBit
    jp BarrelArm
.go:
    ld [hl], 1
    ld a, c
    call BarrelClrBit
    ld a, c
    call BarrelPlace
    call RktSplash
    call BarrelQueue
    call StartExplosion
    ld a, SND_RXPLOD
    call PlaySound
BarrelArm:
    ld a, LOW(BARREL_CHAIN_MS)
    ld [wBarrelCh], a
    ld a, HIGH(BARREL_CHAIN_MS)
    ld [wBarrelCh + 1], a
    ret

; C = thing -> (B, C, D) = centre (th + ITEM_BIAS, +1, + ITEM_BIAS). Keeps nothing but the result.
BarrelPv:
    push bc
    ld a, F_TH_X
    call MapGet
    add ITEM_BIAS
    ld [wTgt], a
    ld a, F_TH_Y
    call MapGet
    inc a
    ld [wTgt + 1], a
    ld a, F_TH_Z
    call MapGet
    add ITEM_BIAS
    ld [wTgt + 2], a
    pop bc
    ld a, [wTgt]
    ld b, a
    ld a, [wTgt + 2]
    ld d, a
    ld a, [wTgt + 1]
    ld c, a
    ret

; A = thing -> blast origin and room.
BarrelPlace:
    ld c, a
    push bc
    ld a, F_TH_ROOM
    call MapGet
    ld [wBlastRoom], a
    pop bc
    call BarrelPv
    ld a, b
    ld [wBlast], a
    ld a, c
    ld [wBlast + 1], a
    ld a, d
    ld [wBlast + 2], a
    xor a
    ld [wBlastFr], a
    ld [wBlastFr + 1], a
    ld [wBlastFr + 2], a
    ret

; A8 barrel_queue: live barrels whose centres are inside RKT_RAD of the blast.
BarrelQueue:
    ld a, [wMapHdr + H_NTHINGS]
    and a
    ret z
    ld c, 0
.l:
    push bc
    ld a, F_TH_TYPE
    call MapGet
    cp TH_BARREL
    jr nz, .n
    ld b, 0
    ld hl, wThTaken
    add hl, bc
    ld a, [hl]
    and a
    jr nz, .n
    ld a, F_TH_ROOM
    call MapGet
    ld b, a
    ld a, [wBlastRoom]
    cp b
    jr nz, .n
    pop bc
    push bc
    call BarrelPv
    call RktCheb3
    cp RKT_RAD
    jr nc, .n
    pop bc
    push bc
    ld a, c
    call BarrelSetBit
.n:
    pop bc
    inc c
    ld a, [wMapHdr + H_NTHINGS]
    cp c
    jr nz, .l
    ret

; A = thing -> HL = &barrel_pend[A >> 3], B = 1 << (A & 7).
BarrelBit:
    ld c, a
    srl a
    srl a
    srl a
    ld e, a
    ld d, 0
    ld hl, wBarrelPend
    add hl, de
    ld a, c
    and 7
    ld b, a
    inc b
    ld a, $80
.s:
    rlca
    dec b
    jr nz, .s
    ld b, a
    ret
BarrelSetBit:
    call BarrelBit
    ld a, [hl]
    or b
    ld [hl], a
    ret
BarrelClrBit:
    call BarrelBit
    ld a, b
    cpl
    and [hl]
    ld [hl], a
    ret

; A8 update_barrel_chain + the explosion timer, once per game frame: when the chain delay runs out the
; lowest pending barrel goes off.
FxTick:
    ld a, [wSplatFresh]
    and a
    jr z, .tickSplat
    xor a                            ; spawned this frame: not yet
    ld [wSplatFresh], a
    jr .fx
.tickSplat:
    ld a, [wSplatMs]                 ; the splat's SPLAT_MS
    and a
    jr z, .fx
    ld b, a
    ld a, [wDtMs]
    ld c, a
    ld a, b
    sub c
    jr nc, .sp
    xor a
.sp:
    ld [wSplatMs], a
.fx:
    ld a, [wFxMs]
    ld b, a
    ld a, [wFxMs + 1]
    or b
    jr z, .chain
    ld a, [wDtMs]
    ld b, a
    ld a, [wFxMs]
    sub b
    ld [wFxMs], a
    ld a, [wFxMs + 1]
    sbc 0
    ld [wFxMs + 1], a
    jr nc, .chain
    xor a
    ld [wFxMs], a
    ld [wFxMs + 1], a
.chain:
    ld a, [wBarrelCh]
    ld b, a
    ld a, [wBarrelCh + 1]
    or b
    ret z
    ld a, [wDtMs]
    ld b, a
    ld a, [wBarrelCh]
    sub b
    ld [wBarrelCh], a
    ld a, [wBarrelCh + 1]
    sbc 0
    ld [wBarrelCh + 1], a
    ret nc
    xor a
    ld [wBarrelCh], a
    ld [wBarrelCh + 1], a
    ld a, [wMapHdr + H_NTHINGS]     ; barrel_pop: the lowest set bit
    and a
    ret z
    ld c, 0
.pop:
    ld a, c
    push bc
    call BarrelBit
    ld a, [hl]
    and b
    pop bc
    jr nz, .got
    inc c
    ld a, [wMapHdr + H_NTHINGS]
    cp c
    jr nz, .pop
    ret
.got:
    ld a, c
    jp BarrelExplode

; Carry = slot wAiI is no longer flying.
RktDead:
    PRPTR wPrOn
    ld a, [hl]
    and a
    jr z, .stop
    PRPTR wPrFl
    ld a, [hl]
    and RKT_F_PEND
    jr nz, .stop
    and a
    ret
.stop:
    scf
    ret

RktClear:
    PRPTR wPrOn
    ld [hl], 0
    ret

; HL = velocity lo array -> DE = v >> 5 (arithmetic; A8 rkt_asr5).
RktVel5:
    ld a, [wAiI]
    add l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    ld e, [hl]
    ld bc, RKT_MAX
    add hl, bc
    ld d, [hl]
    ld b, 5
.s:
    sra d
    rr e
    dec b
    jr nz, .s
    ret

; HL = position lo array, DE = delta -> wRkNew = position + delta (8.8). Keeps HL at the lo slot.
RktAdd:
    ld a, [wAiI]
    add l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    ld a, [hl]
    ld [wRkOld], a
    add e
    ld [wRkNew], a
    push hl
    push af
    ld bc, RKT_MAX
    add hl, bc
    pop af
    ld a, [hl]
    ld [wRkOld + 1], a
    adc d
    ld [wRkNew + 1], a
    pop hl
    ret

; HL = position lo slot -> store wRkNew there (and the hi array).
RktCommit:
    ld a, [wRkNew]
    ld [hl], a
    ld bc, RKT_MAX
    add hl, bc
    ld a, [wRkNew + 1]
    ld [hl], a
    ret

; A8 rkt_move_x / rkt_move_z.
RktMoveX:
    ld hl, wPrVXL
    call RktVel5
    ld hl, wPrXL
    call RktAdd
    push hl
    ld a, [wRkNew + 1]
    ld [wColX], a
    PRPTR wPrZ
    ld a, [hl]
    ld [wColZ], a
    jr RktXzDone
RktMoveZ:
    ld hl, wPrVZL
    call RktVel5
    ld hl, wPrZL
    call RktAdd
    push hl
    PRPTR wPrX
    ld a, [hl]
    ld [wColX], a
    ld a, [wRkNew + 1]
    ld [wColZ], a
RktXzDone:
    call RktPosOk
    pop hl
    jp nc, RktImpact                ; impact
    jr RktCommit

; A8 rkt_pos_ok: carry = (wColX, wColZ) inside one of the room's colliders (points: no inset) and no
; solid at the projectile's height.
RktPosOk:
    ld c, 0
.l:
    ld b, 0
    ld hl, wRcSX
    add hl, bc
    ld a, [hl]
    and a
    jr z, .n
    ld [wBoxSX], a
    ld hl, wRcX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wRcZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wRcSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    push bc
    call PointInBoxXZ
    pop bc
    jr c, RktSolidFree
.n:
    inc c
    ld a, c
    cp 3
    jr nz, .l
    and a
    ret

; A8 rkt_solid_at inverted: carry = no solid at (wColX, wColZ) for a point at the slot's height
; (tested as the player's box with its feet there).
RktSolidFree:
    ld a, [wCamY + 1]
    ld [wLedgeSaveY], a
    PRPTR wPrY
    ld a, [hl]
    add EYE_HEIGHT
    ld [wCamY + 1], a
    call SolidAt
    ld a, [wLedgeSaveY]             ; ld keeps the flags
    ld [wCamY + 1], a
    ccf
    ret

; A8 rkt_move_y: the ceiling of the player's room going up, the floor below going down.
RktMoveY:
    ld hl, wPrVYL
    call RktVel5
    ld hl, wPrYL
    call RktAdd
    push hl
    PRPTR wPrVYH
    bit 7, [hl]
    jr nz, .down
    ld a, [wRoom]
    ld c, a
    ld a, F_ROOM_Y
    call MapGet
    ld b, a
    ld a, F_ROOM_SY
    call MapGet
    add b                           ; ceiling
    ld b, a
    ld a, [wRkNew + 1]
    cp b
    jr nc, .impact                  ; ceiling <= y
    jr .try
.down:
    call RktColXz
    PRPTR wPrY
    ld a, [hl]
    ld [wFbProbe], a
    call FloorBelow
    jr nc, .try
    ld a, [wRkNew + 1]
    ld b, a
    ld a, [wFloorTmp]
    cp b
    jr nc, .impact                  ; floor >= y: landed
.try:                               ; A8 rkt_try_y
    pop hl
    push hl
    call RktCommit
    call RktColXz
    PRPTR wPrY
    call RktSolidFree
    pop hl
    ret c
    ld a, [wRkOld]                  ; restore, then impact
    ld [wRkNew], a
    ld a, [wRkOld + 1]
    ld [wRkNew + 1], a
    call RktCommit
    jp RktImpact
.impact:
    pop hl
    jp RktImpact

RktColXz:
    PRPTR wPrX
    ld a, [hl]
    ld [wColX], a
    PRPTR wPrZ
    ld a, [hl]
    ld [wColZ], a
    ret

; A8 rkt_hit_player / rkt_fireball_hit: Chebyshev < RKT_HIT_R + 1 in XZ, y in [feet, feet + PLAYER_H):
; 10 + rnd(16) (baron 30 + rnd(16)) and the fireball clears.
RktHitPlayer:
    PRPTR wPrX
    ld a, [hl]
    ld hl, wCamX + 1
    sub [hl]
    call Abs8
    cp RKT_HIT_R + 1
    ret nc
    PRPTR wPrZ
    ld a, [hl]
    ld hl, wCamZ + 1
    sub [hl]
    call Abs8
    cp RKT_HIT_R + 1
    ret nc
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld b, a                         ; feet
    PRPTR wPrY
    ld a, [hl]
    cp b
    ret c
    ld c, a
    ld a, b
    add PLAYER_H
    ld b, a
    ld a, c
    cp b
    ret nc
    PRPTR wPrFl
    ld a, [hl]
    and RKT_F_BARON
    ld b, 10
    jr z, .dm
    ld b, 30
.dm:
    call Rnd
    and 15
    add b
    call PlayerDamage
    jp RktClear

; A8 en_dx / en_dz: octant 0 = +z, 2 = +x, 4 = -z, 6 = -x.
DirDX:
    db 0, 1, 1, 1, 0, -1, -1, -1
DirDZ:
    db 1, 1, 0, -1, -1, -1, 0, 1

; ==== A8 enemy state machine (src/enemy.asm, src/ai_poss/pinky/imp/baron.asm) ====================
; Translated routine by routine; each label names its A8 source. wObjI = enemy_idx. Positions are
; whole cells (en_x / en_z) as on the A8; wEnXL / wEnZL stay 0. Time is wDtMs (A8 dt_ms).

; HL = this enemy's meta row (A8 enemy_* tables for its type, tools/gbc_a8const.py). Clobbers A, DE.
EnMetaHL:
    ENPTR wEnType
    ld a, [hl]
    add a
    ld e, a
    ld d, 0
    ld hl, EnMetaPtr
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ret

; A = EM_* offset -> A = meta byte. Clobbers DE, HL.
EnMetaGet:
    push af
    call EnMetaHL
    pop af
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hl]
    ret

; A = EM_PAIN_* / EM_DEATH_* base -> A = that field for this enemy's variant (A8 pain_var_off).
EnMetaVar:
    ld b, a
    ENPTR wEnPainI
    ld a, [hl]
    add b
    jr EnMetaGet

; Carry = en_timer != 0. Clobbers A, DE, HL.
EnTimerNz:
    ENPTR wEnTimer
    ld a, [hl]
    ld de, wEnTimerH - wEnTimer
    add hl, de
    or [hl]
    ret z
    scf
    ret

; A8 en_timer_sub: en_timer -= dt. Carry = still running; NC = elapsed (timer zeroed).
EnTimerSub:
    ENPTR wEnTimer
    ld a, [wDtMs]
    ld b, a
    ld a, [hl]
    sub b
    ld [hl], a
    push af
    ld de, wEnTimerH - wEnTimer
    add hl, de
    pop af
    ld a, [hl]
    sbc 0
    ld [hl], a
    jr c, .done
    scf
    ret
.done:
    xor a
    ld [hl], a
    ld de, wEnTimer - wEnTimerH
    add hl, de
    ld [hl], a
    and a
    ret

; Zero en_timer. Clobbers A, DE, HL.
EnTimerClear:
    ENPTR wEnTimer
    xor a
    ld [hl], a
    ld de, wEnTimerH - wEnTimer
    add hl, de
    ld [hl], a
    ret

; A = new state. Clobbers DE, HL; keeps A.
EnSetStateA:
    push af
    ENPTR wEnState
    pop af
    ld [hl], a
    ret

; A8 enemy_chebyshev: A = max(|en_x - cam_xh|, |en_z - cam_zh|). Clobbers B, DE, HL.
EnCheb:
    ENPTR wEnX
    ld a, [wCamX + 1]
    sub [hl]
    jr nc, .x
    cpl
    inc a
.x:
    ld b, a
    ENPTR wEnZ
    ld a, [wCamZ + 1]
    sub [hl]
    jr nc, .z
    cpl
    inc a
.z:
    cp b
    ret nc
    ld a, b
    ret

; A8 enemy_same_floor: carry = |floor_y - en_y| <= FALL_LEDGE.
EnSameFloor:
    ENPTR wEnY
    ld a, [wFloorY]
    sub [hl]
    jr nc, .p
    cpl
    inc a
.p:
    cp FALL_LEDGE + 1
    ret

; A8 enemy_facing_ok: carry = the player is in the en_dir half-plane (quadrant for a diagonal),
; or within one cell.
EnFacingOk:
    call EnCheb
    cp 2
    jr c, .yes
    ENPTR wEnX
    ld a, [wCamX + 1]
    sub [hl]
    ld b, a                         ; dx toward the player
    ENPTR wEnZ
    ld a, [wCamZ + 1]
    sub [hl]
    ld c, a                         ; dz
    ENPTR wEnDir
    ld a, [hl]
    ld e, a
    ld d, 0
    ld hl, DirDX
    add hl, de
    ld a, [hl]                      ; cs_need_dx
    and a
    jr z, .z
    bit 7, a
    jr nz, .ndx
    bit 7, b                        ; need +: fail on dx < 0
    jr nz, .no
    jr .z
.ndx:
    ld a, b                         ; need -: fail on dx > 0
    and a
    jr z, .z
    bit 7, a
    jr z, .no
.z:
    ld hl, DirDZ
    add hl, de
    ld a, [hl]                      ; cs_need_dz
    and a
    jr z, .yes
    bit 7, a
    jr nz, .ndz
    bit 7, c
    jr nz, .no
    jr .yes
.ndz:
    ld a, c
    and a
    jr z, .yes
    bit 7, a
    jr z, .no
.yes:
    scf
    ret
.no:
    and a
    ret

; A8 enemy_set_geom: A = octant -> en_dir, en_rot = octant * 32.
EnSetGeom:
    ld b, a
    ENPTR wEnDir
    ld [hl], b
    ld a, b
    swap a
    add a
    ld b, a
    ENPTR wEnRot
    ld [hl], b
    ret

; A8 enemy_face_player: en_rot = atan2(cam_xh - en_x, cam_zh - en_z) (en_dir unchanged).
EnFacePlayer:
    ENPTR wEnX
    ld a, [wCamX + 1]
    sub [hl]
    ld [wDx + 1], a
    ENPTR wEnZ
    ld a, [wCamZ + 1]
    sub [hl]
    ld [wDz + 1], a
    xor a
    ld [wDx], a
    ld [wDz], a
    call AngleTo
    ld b, a
    ENPTR wEnRot
    ld [hl], b
    ret

; A8 enemy_shot_clear: carry = clear line from mid-body (feet + SHOT_MID_H) to the eye, tested as a
; 3D segment against the room's solids (src/util.asm line_solids_blocked).
EnShotClear:
    ENPTR wEnX
    ld a, [hl]
    ld [wLnA], a
    ENPTR wEnY
    ld a, [hl]
    add SHOT_MID_H
    ld [wLnA + 1], a
    ENPTR wEnZ
    ld a, [hl]
    ld [wLnA + 2], a
    ld a, [wCamX + 1]
    ld [wLnB], a
    ld a, [wCamY + 1]
    ld [wLnB + 1], a
    ld a, [wCamZ + 1]
    ld [wLnB + 2], a
    call LineSolidsBlocked
    ccf
    ret

; ==== A8 3D segment vs boxes (src/util.asm) =====================================================
; wLnA / wLnB: segment ends (x, y, z), whole cells. wLBox: x, y, z, sx, sy, sz; wLnM: exclusive max.
; t is Q7 (0..127 along A -> B). A8 lerpdv is a log-table a*b/c; this one is exact (floor), so a
; rare t can differ by one unit.

; A = |A| (signed byte). -128 -> 128.
Abs8:
    bit 7, a
    ret z
    cpl
    inc a
    ret

; A8 lerpdv: A * B / C, all signed bytes -> A, magnitude capped at 127; 0 if any is 0.
LerpDv:
    ld d, a
    xor b
    xor c
    ld [wLdSign], a
    ld a, d
    call Abs8
    and a
    jr z, .zero
    ld d, a
    ld a, b
    call Abs8
    and a
    jr z, .zero
    ld b, a
    ld a, c
    call Abs8
    and a
    jr z, .zero
    ld c, a
    ld a, d
    push bc
    call Mul8u                      ; HL = |a| * |b|
    pop bc
    ld b, 0
    ld d, h
    ld e, l
    call Div24x8                    ; DE = HL / |c|
    ld a, d
    and a
    jr nz, .sat
    ld a, e
    cp 128
    jr c, .ok
.sat:
    ld a, 127
.ok:
    ld b, a
    ld a, [wLdSign]
    bit 7, a
    ld a, b
    ret z
    cpl
    inc a
    ret
.zero:
    xor a
    ret

; A8 face_mul7: A = t (0..127), B = signed d -> A = round(d * t / 128).
FaceMul7:
    ld e, b
    push de
    ld c, a
    ld a, b
    call Abs8
    ld b, c
    call Mul8u                      ; HL = |d| * t
    ld de, 64
    add hl, de
    add hl, hl
    ld a, h                         ; (|d| * t + 64) >> 7
    pop de
    bit 7, e
    ret z
    cpl
    inc a
    ret

; A8 line_box_max.
LineBoxMax:
    ld a, [wLBox]
    ld b, a
    ld a, [wLBox + 3]
    add b
    ld [wLnM], a
    ld a, [wLBox + 1]
    ld b, a
    ld a, [wLBox + 4]
    add b
    ld [wLnM + 1], a
    ld a, [wLBox + 2]
    ld b, a
    ld a, [wLBox + 5]
    add b
    ld [wLnM + 2], a
    ret

; A8 line_aabb_overlap: carry = the segment's bounding box meets the box (wLnM set).
LineAabbOverlap:
    ld c, 0
.ax:
    ld b, 0
    ld hl, wLnA
    add hl, bc
    ld d, [hl]
    ld hl, wLnB
    add hl, bc
    ld e, [hl]
    ld a, d
    cp e
    jr c, .ord                      ; a < b: min a, max b
    ld a, d
    ld d, e
    ld e, a
.ord:
    ld hl, wLBox
    add hl, bc
    ld a, e
    cp [hl]
    jr c, .no                       ; max < box min
    ld hl, wLnM
    add hl, bc
    ld a, d
    cp [hl]
    jr nc, .no                      ; min >= box max
    inc c
    ld a, c
    cp 3
    jr nz, .ax
    scf
    ret
.no:
    and a
    ret

; A8 line_outcode: HL = point (x, y, z) -> A = outcode (1 x<min, 2 x>=max, 4 / 8 y, $10 / $20 z).
LineOutcode:
    ld e, 0
    ld c, 0
    ld d, 1
.ax:
    push hl
    ld b, 0
    ld hl, wLBox
    add hl, bc
    ld a, [hl]
    pop hl
    push hl
    ld b, a
    ld a, [hl]
    cp b
    jr nc, .hi
    ld a, e
    or d
    ld e, a
.hi:
    ld b, 0
    ld hl, wLnM
    add hl, bc
    ld a, [hl]
    pop hl
    ld b, a
    ld a, [hl]
    cp b
    jr c, .nx
    sla d
    ld a, e
    or d
    ld e, a
    srl d
.nx:
    inc hl
    sla d
    sla d
    inc c
    ld a, c
    cp 3
    jr nz, .ax
    ld a, e
    ret

; A8 line_t_plane: axis wLnFace, plane wLnPlane -> A = t = (plane - a) * 127 / (b - a);
; NC when the segment is parallel to the plane.
LineTPlane:
    ld a, [wLnFace]
    ld c, a
    ld b, 0
    ld hl, wLnA
    add hl, bc
    ld e, [hl]
    ld hl, wLnB
    add hl, bc
    ld a, [hl]
    sub e
    jr z, .no
    ld c, a
    ld a, [wLnPlane]
    sub e
    ld b, 127
    call LerpDv
    scf
    ret
.no:
    and a
    ret

; A8 line_face_hit: carry = the point at t (wLnT) on the other two axes is inside the box face.
LineFaceHit:
    ld c, 0
.l:
    ld a, [wLnFace]
    cp c
    jr z, .n
    ld b, 0
    ld hl, wLnA
    add hl, bc
    ld e, [hl]
    ld hl, wLnB
    add hl, bc
    ld a, [hl]
    sub e
    push bc
    push de
    ld b, a
    ld a, [wLnT]
    call FaceMul7
    pop de
    pop bc
    add e
    ld d, a
    ld b, 0
    ld hl, wLBox
    add hl, bc
    ld a, d
    cp [hl]
    jr c, .no
    ld hl, wLnM
    add hl, bc
    ld a, d
    cp [hl]
    jr nc, .no
.n:
    inc c
    ld a, c
    cp 3
    jr nz, .l
    scf
    ret
.no:
    and a
    ret

; A8 line_hit_box: carry = the segment enters the box through a face (nearest t in wLnBest).
LineHitBox:
    call LineBoxMax
    call LineAabbOverlap
    ret nc
    ld hl, wLnA
    call LineOutcode
    ld [wLnOc0], a
    ld hl, wLnB
    call LineOutcode
    ld [wLnOc1], a
    ld b, a
    ld a, [wLnOc0]
    and b
    jr nz, .no                      ; same side
    ld a, $FF
    ld [wLnBest], a
    ld a, 1
    ld [wLnBit], a
.faces:
    ld a, [wLnOc0]
    ld b, a
    ld a, [wLnOc1]
    xor b
    ld b, a
    ld a, [wLnBit]
    and b
    call nz, .try
    ld a, [wLnBit]
    add a
    ld [wLnBit], a
    cp $40
    jr nz, .faces
    ld a, [wLnBest]
    cp $FF
    jr z, .no
    scf
    ret
.no:
    and a
    ret
.try:
    ld a, [wLnBit]
    ld c, 0
    cp 4
    jr c, .axis
    inc c
    cp 16
    jr c, .axis
    inc c
.axis:
    ld a, c
    ld [wLnFace], a
    ld b, 0
    ld a, [wLnBit]
    and $2A                         ; +X / +Y / +Z faces: the max plane
    jr z, .min
    ld hl, wLnM
    add hl, bc
    ld a, [hl]
    jr .plane
.min:
    ld hl, wLBox
    add hl, bc
    ld a, [hl]
.plane:
    ld [wLnPlane], a
    call LineTPlane
    ret nc
    and a
    ret z                           ; t = 0
    bit 7, a
    ret nz
    ld b, a
    ld a, [wLnBest]
    cp b
    ret c                           ; not strictly nearer
    ret z
    ld a, b
    ld [wLnT], a
    call LineFaceHit
    ret nc
    ld a, [wLnT]
    ld [wLnBest], a
    ret

; A8 .pt_at: A = t, C = axis -> A = a + d * t / 127. Keeps C.
LinePtAt:
    ld b, a
    push bc
    ld b, 0
    ld hl, wLnA
    add hl, bc
    ld e, [hl]
    ld hl, wLnB
    add hl, bc
    ld a, [hl]
    sub e
    pop bc
    push bc
    push de
    ld c, 127
    call LerpDv                     ; d * t / 127
    pop de
    pop bc
    add e
    ret

; A8 .clamp_ax: A = coord, C = axis (0 / 2) -> clamped into [box, max).
LineClampAx:
    ld d, a
    ld b, 0
    ld hl, wLBox
    add hl, bc
    ld a, d
    cp [hl]
    jr nc, .hi
    ld a, [hl]
    ret
.hi:
    ld hl, wLnM
    add hl, bc
    ld a, d
    cp [hl]
    ret c
    ld a, [hl]
    and a
    ret z
    dec a
    ret

; A8 .xz_clip: clip the segment to the box's XZ rect -> wLnT0 / wLnT1. Carry = it meets the rect.
LineXzClip:
    xor a
    ld [wLnT0], a
    ld a, 127
    ld [wLnT1], a
    call LineBoxMax
    ld c, 0
    call .axis
    ret nc
    ld c, 2
.axis:
    ld b, 0
    ld hl, wLnA
    add hl, bc
    ld e, [hl]
    ld hl, wLnB
    add hl, bc
    ld a, [hl]
    sub e
    jr z, .par
    ld [wLnD], a
    ld hl, wLBox
    add hl, bc
    ld a, [hl]
    call .t
    ld b, a
    ld a, [wLnD]
    bit 7, a
    ld a, b
    jr nz, .loLower
    call .raise
    jr .hi
.loLower:
    call .lower
.hi:
    ld b, 0
    ld hl, wLnM
    add hl, bc
    ld a, [hl]
    call .t
    ld b, a
    ld a, [wLnD]
    bit 7, a
    ld a, b
    jr nz, .hiRaise
    call .lower
    jr .span
.hiRaise:
    call .raise
.span:
    ld a, [wLnT1]
    ld b, a
    ld a, [wLnT0]
    cp b
    jr c, .yes
    jr z, .yes
    and a
    ret
.yes:
    scf
    ret
.par:
    ld a, e
    ld hl, wLBox
    add hl, bc
    cp [hl]
    jr c, .out
    ld hl, wLnM
    add hl, bc
    cp [hl]
    jr nc, .out
    scf
    ret
.out:
    and a
    ret
; A = plane, C = axis -> A = signed t = (plane - a) * 127 / d. Keeps C.
.t:
    push bc
    ld d, a
    ld b, 0
    ld hl, wLnA
    add hl, bc
    ld a, d
    sub [hl]
    ld b, 127
    push af
    ld a, [wLnD]
    ld c, a
    pop af
    call LerpDv
    pop bc
    ret
.raise:
    bit 7, a
    ret nz
    ld b, a
    ld a, [wLnT0]
    ld d, a
    ld a, b
    cp d
    ret c
    ld [wLnT0], a
    ret
.lower:
    bit 7, a
    jr z, .lp
    ld a, 1
    ld [wLnT0], a
    xor a
    ld [wLnT1], a
    ret
.lp:
    ld b, a
    ld a, [wLnT1]
    ld d, a
    ld a, b
    cp d
    ret nc
    ld [wLnT1], a
    ret

; A = t -> A = slope height at the segment point t (A8 slope_height with ylo = 0), slope wLnI.
LineSlopeAt:
    push af
    ld c, 0
    call LinePtAt
    ld c, 0
    call LineClampAx
    ld [wLnPx], a
    pop af
    ld c, 2
    call LinePtAt
    ld c, 2
    call LineClampAx
    ld b, a
    ld a, [wCamX]                   ; GBC SlopeHeight reads the camera: park it on the point
    ld [wLnCam], a
    ld a, [wCamX + 1]
    ld [wLnCam + 1], a
    ld a, [wCamZ]
    ld [wLnCam + 2], a
    ld a, [wCamZ + 1]
    ld [wLnCam + 3], a
    xor a
    ld [wCamX], a
    ld [wCamZ], a
    ld a, [wLnPx]
    ld [wCamX + 1], a
    ld a, b
    ld [wCamZ + 1], a
    ld a, [wLnI]
    ld c, a
    call SlopeHeight
    ld a, [wLnCam]
    ld [wCamX], a
    ld a, [wLnCam + 1]
    ld [wCamX + 1], a
    ld a, [wLnCam + 2]
    ld [wCamZ], a
    ld a, [wLnCam + 3]
    ld [wCamZ + 1], a
    ld a, [wSlYv]
    ret

; A8 .slope_one: slope wLnI of the room cache. Carry = the segment crosses the slope face.
LineSlopeOne:
    ld a, [wLnI]
    ld c, a
    ld b, 0
    ld hl, wSlSX
    add hl, bc
    ld a, [hl]
    and a
    ret z
    ld [wLBox + 3], a
    ld hl, wSlX
    add hl, bc
    ld a, [hl]
    ld [wLBox], a
    ld hl, wSlZ
    add hl, bc
    ld a, [hl]
    ld [wLBox + 2], a
    ld hl, wSlSZ
    add hl, bc
    ld a, [hl]
    ld [wLBox + 5], a
    xor a
    ld [wLBox + 1], a
    ld [wLBox + 4], a
    call LineXzClip
    ret nc
    ld a, [wLnT0]
    call LineSlopeAt
    ld [wLnH0], a
    ld a, [wLnT1]
    call LineSlopeAt
    ld [wLnH1], a
    ld a, [wLnT0]
    ld c, 1
    call LinePtAt
    ld b, a
    ld a, [wLnH0]
    ld c, a
    ld a, b
    sub c
    ld [wLnRel0], a                 ; y0 - h0
    ld a, [wLnT1]
    ld c, 1
    call LinePtAt
    ld b, a
    ld a, [wLnH1]
    ld c, a
    ld a, b
    sub c
    ld [wLnRel1], a                 ; y1 - h1
    ld a, [wLnRel0]
    and a
    jr z, .on0
    ld a, [wLnRel1]
    and a
    jr z, .on1
    ld b, a
    ld a, [wLnRel0]
    xor b
    bit 7, a
    jr z, .no                       ; same side of the face
    ld a, [wLnRel1]
    ld b, a
    ld a, [wLnRel0]
    sub b
    ld c, a
    ld a, [wLnRel0]
    ld b, 127
    call LerpDv                     ; s = rel0 * 127 / (rel0 - rel1)
    and a
    jr z, .no
    bit 7, a
    jr nz, .no
    jr .pick
.on0:
    xor a
    jr .pick
.on1:
    ld a, 127
.pick:
    ld b, a
    ld a, [wLnT0]
    ld d, a
    ld a, [wLnT1]
    sub d
    ld c, 127
    push de
    call LerpDv                     ; (t1 - t0) * s / 127
    pop de
    add d
    and a
    jr z, .no
    bit 7, a
    jr nz, .no
    ld [wLnBest], a                 ; t of the crossing (nearest-hit mode)
    scf
    ret
.no:
    and a
    ret

; LineHitBox / LineSlopeOne with the walk's mode: wLnMode 0 = the first hit ends the walk (carry), 1 = keep the
; nearest t in wLnNear and never stop (carry clear).
LineHitBoxM:
    call LineHitBox
    ret nc
    jr LnNote
LineSlopeM:
    call LineSlopeOne
    ret nc
LnNote:
    ld a, [wLnMode]
    and a
    jr z, .first
    ld a, [wLnBest]
    ld hl, wLnNear
    cp [hl]
    jr nc, .keep
    ld [hl], a
.keep:
    and a
    ret
.first:
    scf
    ret

; wLBox from the map: A = first field (F_RB_X / F_ELEV_X / F_ROOM_X), C = index; fields x, y, z,
; sx, sy, sz follow in order. Keeps C.
LoadBoxMap:
    ld hl, wLBox
    ld b, 6
.l:
    push af
    push hl
    push bc
    call MapGet
    pop bc
    pop hl
    ld [hl+], a
    pop af
    inc a
    dec b
    jr nz, .l
    ret

; Cache arrays -> wLBox: C = index, HL = table of 6 array bases (sy base 0 = flat).
LoadBoxCache:
    ld de, wLBox
    ld b, 6
.l:
    push bc
    ld a, [hl+]
    push hl
    ld h, [hl]
    ld l, a
    or h
    jr z, .zero
    ld b, 0
    add hl, bc
    ld a, [hl]
    jr .put
.zero:
    xor a
.put:
    ld [de], a
    inc de
    pop hl
    inc hl
    pop bc
    dec b
    jr nz, .l
    ret

CrateBoxTab:
    dw wCrX, wCrY, wCrZ, wCrSX, wCrSY, wCrSZ
PlatBoxTab:
    dw wPlX, wPlY, wPlZ, wPlSX, 0, wPlSZ

; A8 line_solids_blocked (first-hit mode) for the player's room: carry = something solid is on the
; segment: room cutouts, crates, solid platforms, elevators, slopes, then the room shell.
LineSolidsBlocked::
    ld a, [wRoom]                   ; cutouts rb[room * 2 + 0 / 1]
    add a
    ld c, a
    call .rb
    ret c
    inc c
    call .rb
    ret c
    ld a, [wCrN]                    ; crates
    and a
    jr z, .plats
    ld c, 0
.cr:
    push bc
    ld hl, CrateBoxTab
    call LoadBoxCache
    pop bc
    ld a, [wLBox + 3]
    and a
    jr z, .crn
    push bc
    call LineHitBoxM
    pop bc
    ret c
.crn:
    inc c
    ld a, [wCrN]
    cp c
    jr nz, .cr
.plats:
    ld a, [wPlN]                    ; solid platforms (the cache holds only solid ones), sy = 0
    and a
    jr z, .elevs
    ld c, 0
.pl:
    push bc
    ld hl, PlatBoxTab
    call LoadBoxCache
    call LineHitBoxM
    pop bc
    ret c
    inc c
    ld a, [wPlN]
    cp c
    jr nz, .pl
.elevs:
    ld a, [wMapHdr + H_NELEVS]      ; elevators of this room at their start height (they do not move yet)
    and a
    jr z, .slopes
    ld c, 0
.ev:
    ld a, F_ELEV_ROOM
    call MapGet
    ld b, a
    ld a, [wRoom]
    cp b
    jr nz, .evn
    ld a, F_ELEV_X
    call LoadBoxMap
    ld b, 0
    ld hl, wElevY                    ; the car's current height
    add hl, bc
    ld a, [hl]
    ld [wLBox + 1], a
    push bc
    call LineHitBoxM
    pop bc
    ret c
.evn:
    inc c
    ld a, [wMapHdr + H_NELEVS]
    cp c
    jr nz, .ev
.slopes:
    ld a, [wSlN]
    and a
    jr z, .shell
    xor a
.sl:
    ld [wLnI], a
    call LineSlopeM
    ret c
    ld a, [wLnI]
    inc a
    ld hl, wSlN
    cp [hl]
    jr nz, .sl
.shell:
    ld a, [wRoom]
    ld c, a
    ld a, F_ROOM_X
    call LoadBoxMap
    jp LineHitBoxM
.rb:
    ld a, F_RB_SX
    call MapGet
    and a
    ret z
    ld a, F_RB_X
    call LoadBoxMap
    push bc
    call LineHitBoxM
    pop bc
    ret
ASSERT F_RB_SX == F_RB_X + 3 && F_ELEV_SZ == F_ELEV_X + 5 && F_ROOM_SZ == F_ROOM_X + 5
ASSERT F_ELEV_Y0 == F_ELEV_X + 1

; ---- movement ------------------------------------------------------------------------------

; A8 body_vs_cam: carry = Chebyshev(cam, (D, E)) < C.
BodyVsCam:
    ld a, [wCamX + 1]
    sub d
    jr nc, .x
    cpl
    inc a
.x:
    cp c
    ret nc
    ld a, [wCamZ + 1]
    sub e
    jr nc, .z
    cpl
    inc a
.z:
    cp c
    ret

; A8 player_blocks_enemy: wColX / wColZ proposed. Carry = ok; NC = newly overlapping the player.
PlayerBlocksEnemy:
    ENPTR wEnState
    ld a, [hl]
    cp EN_DYING
    jr nc, .ok
    ENPTR wEnY
    ld a, [hl]
    ld [wBoxY], a
    ld a, ENEMY_CULL_H
    ld [wBoxSY], a
    call PlayerOverlapsY
    jr nc, .ok
    ld a, EM_BLOCK_R
    call EnMetaGet
    inc a
    ld [wTmpAux], a                 ; set_blk_lim
    ld c, a
    ld a, [wColX]
    ld d, a
    ld a, [wColZ]
    ld e, a
    call BodyVsCam
    jr nc, .ok
    ENPTR wEnX
    ld a, [hl]
    push af
    ENPTR wEnZ
    ld e, [hl]
    pop af
    ld d, a
    ld a, [wTmpAux]
    ld c, a
    call BodyVsCam
    jr c, .ok                       ; already overlapping: allow
    and a
    ret
.ok:
    scf
    ret

; A8 enemy_pos_ok: carry = the enemy may step to wColX / wColZ; wAiFloorY = the floor there.
; (player block, room inset, solids with the enemy's eye, destination floor within STEP_UP)
EnPosOk:
    call PlayerBlocksEnemy
    ret nc
    jp EnemyMoveOk

; A8 enemy_probe_dir: A = octant. Carry = walkable; wAiProbe = octant, wColX / wColZ = the cell.
EnProbeDir:
    ld [wAiProbe], a
    ld e, a
    ld d, 0
    ld hl, DirDX
    add hl, de
    ld b, [hl]
    ld hl, DirDZ
    add hl, de
    ld c, [hl]
    push bc
    ENPTR wEnX
    pop bc
    ld a, [hl]
    add b
    ld [wColX], a
    push bc
    ENPTR wEnZ
    pop bc
    ld a, [hl]
    add c
    ld [wColZ], a
    jp EnPosOk

; A8 enemy_try_step: step one cell along en_dir; repath once when blocked.
; (enemy_clamp_room is not needed: EnPosOk only accepts cells inside the room inset.)
EnTryStep:
    ENPTR wEnDir
    ld a, [hl]
    call EnProbeDir
    jr c, .ok
    call SelectDodgeDir
    ENPTR wEnDir
    ld a, [hl]
    call EnProbeDir
    ret nc
.ok:
    ld a, [wColX]
    ld b, a
    ENPTR wEnX
    ld [hl], b
    ld a, [wColZ]
    ld b, a
    ENPTR wEnZ
    ld [hl], b
    ld a, [wAiFloorY]
    ld b, a
    ENPTR wEnY
    ld [hl], b
    ENPTR wEnDir
    ld a, [hl]
    jp EnSetGeom

; Swap wAiTry[0] <-> [1] and [2] <-> [3] (axis order).
DodgeSwapAxes:
    ld hl, wAiTry
    ld a, [hl+]
    ld b, [hl]
    ld [hl-], a
    ld [hl], b
    ld hl, wAiTry + 2
    ld a, [hl+]
    ld b, [hl]
    ld [hl-], a
    ld [hl], b
    ret

; A8 .sdd_setdiag: wAiTry[4] = diag4[((try0 & 4) >> 1) | (try1 >> 2)].
DodgeSetDiag:
    ld a, [wAiTry]
    and 4
    srl a
    ld b, a
    ld a, [wAiTry + 1]
    srl a
    srl a
    or b
    ld e, a
    ld d, 0
    ld hl, .diag4
    add hl, de
    ld a, [hl]
    ld [wAiTry + 4], a
    ret
.diag4:
    db 1, 3, 7, 5

; A8 select_dodge_dir (Wolf-style): try the diagonal toward the player, then the axes (major
; first, randomly swapped), never straight back unless nothing else works. Grunts (all but the
; baron) inside GRUNT_BACKOFF prefer away.
SelectDodgeDir:
    ENPTR wEnDir
    ld a, [hl]
    add 4
    and 7
    ld [wAiTurn], a                 ; en_opp[en_dir]
    ENPTR wEnX
    ld a, [wCamX + 1]
    sub [hl]
    ld [wDodgeDx], a
    ENPTR wEnZ
    ld a, [wCamZ + 1]
    sub [hl]
    ld [wDodgeDz], a
    ld a, [wDodgeDx]
    and a
    jr z, .wx
    bit 7, a
    jr z, .ex
.wx:
    ld a, 6
    ld [wAiTry], a
    ld a, 2
    ld [wAiTry + 2], a
    jr .y
.ex:
    ld a, 2
    ld [wAiTry], a
    ld a, 6
    ld [wAiTry + 2], a
.y:
    ld a, [wDodgeDz]
    and a
    jr z, .nz
    bit 7, a
    jr z, .sz
.nz:
    xor a
    ld [wAiTry + 3], a
    ld a, 4
    ld [wAiTry + 1], a
    jr .diag
.sz:
    xor a
    ld [wAiTry + 1], a
    ld a, 4
    ld [wAiTry + 3], a
.diag:
    call DodgeSetDiag
    ld a, [wDodgeDx]
    bit 7, a
    jr z, .ax
    cpl
    inc a
.ax:
    ld [wDodgeDx], a
    ld a, [wDodgeDz]
    bit 7, a
    jr z, .az
    cpl
    inc a
.az:
    ld [wDodgeDz], a
    ld b, a
    ld a, [wDodgeDx]
    ld c, a
    ld a, b
    cp c
    jr c, .ord                      ; |dz| < |dx|: X already major
    call DodgeSwapAxes
.ord:
    ENPTR wEnType
    ld a, [hl]
    cp ENT_BARON
    jr z, .zig                      ; the baron closes, never backs off
    call EnCheb
    cp GRUNT_BACKOFF + 1
    jr nc, .zig
    ld hl, wAiTry                   ; prefer away: swap toward <-> away, rebuild the diagonal
    ld a, [hl]
    ld b, a
    ld a, [wAiTry + 2]
    ld [hl], a
    ld a, b
    ld [wAiTry + 2], a
    ld hl, wAiTry + 1
    ld a, [hl]
    ld b, a
    ld a, [wAiTry + 3]
    ld [hl], a
    ld a, b
    ld [wAiTry + 3], a
    call DodgeSetDiag
.zig:
    call Rnd
    bit 7, a
    jr nz, .try
    call DodgeSwapAxes
.try:
    ld a, 4                         ; diagonal first
    ld [wDodgeI], a
.lp:
    ld a, [wDodgeI]
    ld e, a
    ld d, 0
    ld hl, wAiTry
    add hl, de
    ld a, [hl]
    ld b, a
    ld a, [wAiTurn]
    cp b
    jr z, .n
    ld a, b
    call EnProbeDir
    jr nc, .n
    ld a, [wAiProbe]
    jp EnSetGeom
.n:
    ld a, [wDodgeI]
    inc a
    cp 5
    jr nz, .n4
    xor a
.n4:
    ld [wDodgeI], a
    cp 4
    jr nz, .lp
    ld a, [wAiTurn]
    cp $FF
    ret z
    call EnProbeDir
    ret nc
    ld a, [wAiProbe]
    jp EnSetGeom

; ---- state entries -------------------------------------------------------------------------

; A8 enemy_enter_approach: approach with a jittered step phase and run frame; the type sets the
; attack hold and the first direction; a non-zero hold gets 0..255 ms more.
EnEnterApproach:
    ld a, EN_APPROACH
    call EnSetStateA
    ENPTR wEnStepH
    ld [hl], 0
    call Rnd
    and ENEMY_STEP_JIT
    ld b, a
    ENPTR wEnStep
    ld [hl], b
    ld a, EM_RUN_L
    call EnMetaGet
    and a
    jr z, .fr
    ld b, a
    call Rnd
.mod:
    cp b
    jr c, .fr
    sub b
    jr .mod
.fr:
    ld b, a
    ENPTR wEnFrame
    ld [hl], b
    call AiApproachEnter
    call EnTimerNz
    ret nc
    call Rnd
    ld b, a
    ENPTR wEnTimer
    ld a, [hl]
    add b
    ld [hl], a
    ret nc
    ld de, wEnTimerH - wEnTimer
    add hl, de
    inc [hl]
    ret

; A8 enemy_enter_alert: the sight bark, then straight to approach.
EnEnterAlert:
    ld hl, SndSight
    call EnCue
    jr EnEnterApproach

; HL = SndSight / SndWince / SndDeath: play the current enemy's cue (A8 enemy_play_cue).
EnCue:
    push hl
    call EnTypeA
    pop hl
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hl]
    cp SND_NONE
    ret z
    jp PlaySound

; A8 enemy_play_clip_sfx: the attack clip's melee / shoot sound plays when the frame steps onto its
; sound frame (old < frame <= new; wEnSfxOld / wEnNewFrame).
EnAtkSound:
    call EnTypeA
    ld e, a
    ld d, 0
    ld hl, SndAtkFrame
    add hl, de
    ld a, [hl]
    cp SND_NONE
    ret z
    ld b, a
    ld a, [wEnSfxOld]
    cp b
    ret nc
    ld a, [wEnNewFrame]
    cp b
    ret c
    jr EnAtkPlay

; A8 enemy_play_clip_sfx_enter: a sound on frame 0 plays as the attack starts.
EnAtkEnterSound:
    call EnTypeA
    ld e, a
    ld d, 0
    ld hl, SndAtkFrame
    add hl, de
    ld a, [hl]
    and a
    ret nz                          ; (SND_NONE is nonzero too)
EnAtkPlay:
    ld hl, SndAtkId
    add hl, de
    ld a, [hl]
    jp PlaySound
; A8 enemy_enter_attack (possessed): attack clip from frame 0, face the player.
EnEnterAttack:
    ld a, EN_ATTACK
    call EnSetStateA
    ENPTR wEnFrame
    ld [hl], 0
    call EnAtkEnterSound
    jp EnFacePlayer

; A8 enemy_enter_demon_attack: as EnEnterAttack, and the step accumulator restarts.
EnEnterDemonAttack:
    ld a, EN_ATTACK
    call EnSetStateA
    ENPTR wEnFrame
    ld [hl], 0
    ENPTR wEnStep
    ld [hl], 0
    ENPTR wEnStepH
    ld [hl], 0
    call EnAtkEnterSound
    jp EnFacePlayer

; ---- per-type AI (A8 ai_poss / ai_baron / ai_pinky / ai_imp entry points) -----------------

; HL = this enemy's type. A = type.
EnTypeA:
    ENPTR wEnType
    ld a, [hl]
    ret

; AI_CMD_APPROACH_ENTER. Imp: no hold. Others: 0..1023 ms. All: pick a direction.
AiApproachEnter:
    call EnTypeA
    cp ENT_IMP
    jr nz, .hold
    call EnTimerClear
    jp SelectDodgeDir
.hold:
    call Rnd
    ld b, a
    ENPTR wEnTimer
    ld [hl], b
    call Rnd
    and 3
    ld b, a
    ENPTR wEnTimerH
    ld [hl], b
    jp SelectDodgeDir

; AI_CMD_APPROACH_MOVE: one cell per DOOM_STEP_MS (all four types). The imp drops its post-throw
; pause when the player is in claw reach.
AiApproachMove:
    call EnTypeA
    cp ENT_IMP
    jr nz, .mv
    call EnTimerNz
    jr nc, .mv
    ENPTR wEnAtk
    ld a, [hl]
    and a
    jr z, .mv                       ; claw recovery keeps the pause
    call EnShotClear
    jr nc, .mv
    call EnCheb
    cp DEMON_MELEE_R
    jr nc, .mv
    call EnSameFloor
    jr nc, .mv
    call EnTimerClear
.mv:
    ENPTR wEnStep
    ld a, [wDtMs]
    add [hl]
    ld [hl], a
    push af
    ld de, wEnStepH - wEnStep
    add hl, de
    pop af
    ld a, [hl]
    adc 0
    ld [hl], a
.slp:
    ENPTR wEnStepH
    ld a, [hl]
    cp HIGH(DOOM_STEP_MS)
    ret c
    jr nz, .go
    ld de, wEnStep - wEnStepH
    add hl, de
    ld a, [hl]
    cp LOW(DOOM_STEP_MS)
    ret c
.go:
    ENPTR wEnStep
    ld a, [hl]
    sub LOW(DOOM_STEP_MS)
    ld [hl], a
    push af
    ld de, wEnStepH - wEnStep
    add hl, de
    pop af
    ld a, [hl]
    sbc HIGH(DOOM_STEP_MS)
    ld [hl], a
    call EnTryStep
    jr .slp

; A8 .missile_ok: d = min(dist, 12); always at d < 4, else when rnd8 >= d * 16 - 64.
MissileOk:
    call EnCheb
    cp 13
    jr c, .c
    ld a, 12
.c:
    swap a
    sub 64
    jr c, .yes
    ld b, a
    call Rnd
    cp b
    jr c, .no
.yes:
    scf
    ret
.no:
    and a
    ret

; AI_CMD_APPROACH_ATTACK (range and hold already checked).
AiApproachAttack:
    call EnTypeA
    cp ENT_POSS
    jr nz, .notPoss
    call EnShotClear                ; possessed: line of sight, shoot
    ret nc
    jp EnEnterAttack
.notPoss:
    cp ENT_PINKY
    jr nz, .notPinky
    call EnSameFloor                ; pinky: bite on the same floor inside DEMON_MELEE_R
    ret nc
    call EnCheb
    cp DEMON_MELEE_R
    ret nc
    call EnShotClear
    ret nc
    jp EnEnterDemonAttack
.notPinky:
    cp ENT_BARON
    jr nz, .imp
    call FireballAlive              ; baron: nothing while its fireball flies
    ret c
.imp:
    call EnShotClear
    ret nc
    call EnCheb
    cp DEMON_MELEE_R
    jr nc, .miss
    call EnSameFloor
    jr nc, .miss
    xor a                           ; claw
    jr .go
.miss:
    call FireballAlive
    ret c
    call MissileOk
    ret nc
    ld a, 1                         ; fireball
.go:
    ld b, a
    ENPTR wEnAtk
    ld [hl], b
    jp EnEnterDemonAttack

; Claw / bite: same floor, inside DEMON_MELEE_R, clear line: (rnd & 7) + 1, times 3.
MeleeHit:
    call EnSameFloor
    ret nc
    call EnCheb
    cp DEMON_MELEE_R
    ret nc
    call EnShotClear
    ret nc
    call Rnd
    and 7
    inc a
    ld b, a
    add a
    add b
    jp PlayerDamage

; AI_CMD_FIRE, on the attack clip's fire frame.
AiFire:
    call EnTypeA
    cp ENT_POSS
    jr nz, .notPoss
    ; possessed: clear line, then hit when (rnd & 31) > min(dist, 28); 6, 9, 12 or 15.
    ; (the muzzle stamp is started at draw time on the fire frame: objects.asm MuzzleCheck)
    call EnShotClear
    ret nc
    call EnCheb
    cp 29
    jr c, .d
    ld a, 28
.d:
    ld b, a
    call Rnd
    and 31
    cp b
    ret z
    ret c
    call Rnd
    and 3
    add 2
    ld b, a
    add a
    add b
    jp PlayerDamage
.notPoss:
    cp ENT_PINKY
    jr z, MeleeHit
    ENPTR wEnAtk
    ld a, [hl]
    and a
    jr z, MeleeHit
    jp SpawnFireball                ; imp / baron throw (A8 .throw)

; AI_CMD_ATTACK_END: back to approach, then the type's reattack pause.
AiAttackEnd:
    call EnEnterApproach
    call EnTypeA
    cp ENT_IMP
    jr nz, .doom
    call Rnd                        ; IMP_ATK_MS + 0..511
    and 1
    add HIGH(IMP_ATK_MS)
    ld b, a
    ENPTR wEnTimerH
    ld [hl], b
    call Rnd
    add LOW(IMP_ATK_MS)
    ld b, a
    push af
    ENPTR wEnTimer
    ld [hl], b
    pop af
    ret nc
    ld de, wEnTimerH - wEnTimer
    add hl, de
    inc [hl]
    ret
.doom:                              ; DOOM_ATK_MS (GRUNT_ATK_MS for the possessed) + 0..255
    call Rnd
    add LOW(DOOM_ATK_MS)
    ld b, a
    ld a, HIGH(DOOM_ATK_MS)
    adc 0
    ld c, a
    ENPTR wEnTimer
    ld [hl], b
    ld de, wEnTimerH - wEnTimer
    add hl, de
    ld [hl], c
    ret
ASSERT GRUNT_ATK_MS == DOOM_ATK_MS

; AI_CMD_DYING_STEP (baron only, ai_baron.asm .dying): while any baron is still up every door is
; hidden; once all are dying or dead every door shows.
AiDyingStep:
    call EnTypeA
    cp ENT_BARON
    ret nz
    ld a, [wEnN]
    ld b, a
    ld c, 0
.scan:
    ld a, c
    cp b
    jr z, .show
    ld e, c
    ld d, 0
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    cp ENT_BARON
    jr nz, .sn
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_DYING
    jr c, .hide
.sn:
    inc c
    jr .scan
.show:
    ld d, $FF - DOOR_HIDDEN
    ld e, 0
    jr .doors
.hide:
    ld d, $FF
    ld e, DOOR_HIDDEN
.doors:
    ld a, [wMapHdr + H_NDOORS]
    and a
    ret z
    ld b, a
    ld c, 0
.dl:
    push bc
    push de
    ld a, F_DOOR_TYPE
    call MapPtrHL
    ld a, 2
    ldh [rSVBK], a
    pop de
    ld a, [hl]
    and d
    or e
    ld [hl], a
    ld a, 1
    ldh [rSVBK], a
    pop bc
    inc c
    ld a, c
    cp b
    jr nz, .dl
    ret

; A = field id, C = index -> HL = that byte in wMap (WRAM bank 2; caller switches SVBK).
MapPtrHL:
    add a
    ld l, a
    ld h, HIGH(wFieldPtr)
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, c
    add l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    ret

; ---- the per-frame update ------------------------------------------------------------------

AiTick::
    call EnemiesUpdate
    jp ProjUpdate

; A8 enemies_update: tick the anim clock (enemy_anim_step per ANIM_MS), then think for every
; enemy of the player's room (idle: wake; approach: step and attack). gunshot_wake is cleared.
EnemiesUpdate::
    call FxTick                     ; explosion and barrel chain timers
    ld a, [wDtMs]                   ; the enemy muzzle's world-sprite timer
    ld b, a
    ld a, [wEmuzMs]
    sub b
    jr nc, .emuz
    xor a
.emuz:
    ld [wEmuzMs], a
    ld a, [wDtMs]
    ld b, a
    ld a, [wAnimAcc]
    add b
    ld [wAnimAcc], a
    ld a, [wAnimAcc + 1]
    adc 0
    ld [wAnimAcc + 1], a
.anim:
    ld a, [wAnimAcc + 1]
    and a
    jr nz, .astep
    ld a, [wAnimAcc]
    cp ANIM_MS
    jr c, .think
.astep:
    ld a, [wAnimAcc]
    sub ANIM_MS
    ld [wAnimAcc], a
    ld a, [wAnimAcc + 1]
    sbc 0
    ld [wAnimAcc + 1], a
    call EnemyAnimStep
    jr .anim
.think:
    ld a, [wEnN]
    and a
    jr z, .done
    xor a
    ld [wObjI], a
.lp:
    ENPTR wEnState
    ld a, [hl]
    cp EN_GONE
    jr z, .next
    ld b, a
    ENPTR wEnRoom
    ld a, [wRoom]
    cp [hl]
    jr nz, .next
    ld a, b
    cp EN_ALERT
    jr c, .idle                     ; 0 (and reserved 1): idle
    cp EN_APPROACH
    jr nz, .next                    ; alert / attack / pain / dying / dead: nothing per think
    call EuApproach
    jr .next
.idle:
    call EuIdle
.next:
    ld hl, wObjI
    inc [hl]
    ld a, [wEnN]
    cp [hl]
    jr nz, .lp
.done:
    xor a
    ld [wGunshotWake], a
    ret

; A8 eu_idle.
EuIdle:
    call EnTimerNz
    jr nc, .sight
    call EnTimerSub
    jr nc, .retry
    ld a, [wGunshotWake]            ; .eu_id_held
    and a
    ret z
.retry:
    call EnTimerClear
    call EnCheb
    cp ENEMY_DETECT + 1
    ret nc
    jp EnEnterApproach
.sight:
    ld a, [wGunshotWake]
    and a
    jr nz, .wake
    call EnCheb
    cp ENEMY_DETECT + 1
    ret nc
    call EnFacingOk
    ret nc
.wake:
    jp EnEnterAlert

; A8 eu_approach: the type steps; in range with the hold over -> the type may attack.
EuApproach:
    call EnTimerNz
    call c, EnTimerSub
    call AiApproachMove             ; all four types answer AI_AP_STAND
    call EnCheb
    ld b, a
    ld a, EM_RANGE
    call EnMetaGet
    cp b
    ret c                           ; dist > range
    call EnTimerNz
    ret c
    jp AiApproachAttack

; A8 enemy_anim_step (every ANIM_MS): all four types are Doom types, so frames advance on every
; other step (200 ms). Loops for idle / approach, one-shot ends for alert / attack / pain, the
; dying clip ends in EN_DEAD on its last frame.
EnemyAnimStep:
    ld a, [wDoomAnimPh]
    xor 1
    ld [wDoomAnimPh], a
    ld a, [wEnN]
    and a
    ret z
    xor a
    ld [wObjI], a
.lp:
    ENPTR wEnState
    ld a, [hl]
    cp EN_GONE
    jr z, .next
    cp EN_DEAD
    jr z, .next
    ENPTR wEnRoom
    ld a, [wRoom]
    cp [hl]
    jr nz, .next
    ld a, [wDoomAnimPh]
    and a
    jr z, .next                     ; Doom types hold this step
    ENPTR wEnFrame
    ld a, [hl]
    ld [wEnSfxOld], a
    ENPTR wEnState
    ld a, [hl]
    cp EN_IDLE
    jr z, .stand
    cp EN_APPROACH
    jr z, .run
    cp EN_ALERT
    jr z, .alert
    cp EN_ATTACK
    jr z, .attack
    cp EN_PAIN
    jr z, .pain
    cp EN_DYING
    call z, .die
.next:
    ld hl, wObjI
    inc [hl]
    ld a, [wEnN]
    cp [hl]
    jr nz, .lp
    ret

.stand:
    ld a, EM_STAND_L
    jr .loop
.run:
    ld a, EM_RUN_L
.loop:
    call EnMetaGet
    ld b, a
    ENPTR wEnFrame
    inc [hl]
    ld a, [hl]
    cp b
    jr c, .next
    ld [hl], 0
    jr .next

; frame++ -> A = new frame.
.inc:
    ENPTR wEnFrame
    inc [hl]
    ld a, [hl]
    ret

.alert:
    call .inc
    ld b, a
    ld a, EM_ALERT_L
    call EnMetaGet
    ld c, a
    ld a, b
    cp c
    jr c, .next
    call EnEnterApproach
    jr .next

.pain:
    call .inc
    push af
    ld a, EM_PAIN_L
    call EnMetaVar
    ld c, a
    pop af
    cp c
    jr c, .next
    call EnEnterApproach
    jr .next

.attack:
    call .inc
    ld [wEnNewFrame], a             ; new frame
    call EnAtkSound
    ld a, EM_FIRE_FRAME
    call EnMetaGet
    bit 7, a
    jr nz, .atkLen                  ; $FF = none
    ld b, a
    ld a, [wEnSfxOld]
    cp b
    jr nc, .atkLen                  ; fire <= old: already on or past it
    ld a, [wEnNewFrame]
    cp b
    jr c, .atkLen                   ; new < fire: not yet
    call AiFire
.atkLen:
    ld a, EM_ATK_L
    call EnMetaGet
    ld b, a
    ld a, [wEnNewFrame]
    cp b
    jp c, .next
    call AiAttackEnd
    jp .next

.die:
    call .inc
    call AiDyingStep
    ld a, EM_DEATH_L
    call EnMetaVar
    ld b, a
    ENPTR wEnFrame
    ld a, [hl]
    cp b
    ret c
    ld a, b                         ; past the end: hold the last frame as EN_DEAD
    dec a
    ld [hl], a
    ld a, EN_DEAD
    jp EnSetStateA

; A8 damage_enemy. wObjI = enemy, A = damage (x 3/2, at most 255, on I'm too young to die). Idle / alert
; enemies wake into approach; survivors flinch on rnd8 < pain_chance; at 0 hp the dying clip starts.
AiDamageEnemy::
    ld b, a
    ld a, [wDifficulty]
    and a
    ld a, b
    jr nz, .dmg
    srl b
    add b
    jr nc, .dmg
    ld a, 255
.dmg:
    ld [wDmg], a
    ENPTR wEnState
    ld a, [hl]
    cp EN_DYING
    ret nc
    ENPTR wEnHp
    ld a, [wDmg]
    ld b, a
    ld a, [hl]
    sub b
    ld [hl], a
    jr z, .kill
    jr c, .kill
    ENPTR wEnState
    ld a, [hl]
    cp EN_APPROACH
    call c, EnEnterApproach         ; wake idle / alert into combat
    call Rnd
    ld b, a
    ld a, EM_PAIN_CHANCE
    call EnMetaGet
    ld c, a
    ld a, b
    cp c
    ret nc
    ld a, EN_PAIN                   ; one pain / death variant exported per type: en_pain_i = 0
    call EnSetStateA
    ENPTR wEnFrame
    ld [hl], 0
    ENPTR wEnPainI
    ld [hl], 0
    ld hl, SndWince
    jp EnCue
.kill:
    ld a, EN_DYING                  ; A8 kill_enemy
    call EnSetStateA
    ENPTR wEnFrame
    ld [hl], 0
    ENPTR wEnPainI
    ld [hl], 0
    call EnTimerClear
    ld a, [wKills]
    inc a
    ld [wKills], a
    ld hl, SndDeath
    jp EnCue

; A8 enemies_block_player: wColX / wColZ proposed. Carry = ok; NC = the player would newly
; overlap a live enemy of this room (Chebyshev < block_r + 1, overlapping in Y). A body the player
; already overlapped at wPreX / wPreZ does not block.
EnemiesBlockPlayer::
    ld a, [wEnN]
    and a
    jr z, .ok
    ld c, 0
.l:
    push bc
    ld e, c
    ld d, 0
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_DYING
    jr nc, .n
    ld hl, wEnRoom
    add hl, de
    ld a, [wRoom]
    cp [hl]
    jr nz, .n
    ld hl, wEnY
    add hl, de
    ld a, [hl]
    ld [wBoxY], a
    ld a, ENEMY_CULL_H
    ld [wBoxSY], a
    push de
    call PlayerOverlapsY
    pop de
    jr nc, .n
    ld hl, wEnType                  ; set_blk_lim: block_r + 1
    add hl, de
    ld a, [hl]
    add a
    ld c, a
    ld b, 0
    ld hl, EnMetaPtr
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld bc, EM_BLOCK_R
    add hl, bc
    ld a, [hl]
    inc a
    ld c, a
    ld hl, wEnX
    add hl, de
    ld b, [hl]
    ld hl, wEnZ
    add hl, de
    ld d, [hl]                      ; B = en_x, D = en_z, C = limit
    ld a, [wColX]
    ld e, a
    call .near
    jr nc, .n
    ld a, [wPreX]
    ld e, a
    ld a, [wPreZ]
    ld h, a
    call .nearH
    jr c, .n                        ; already overlapping: allow
    pop bc
    and a
    ret
.n:
    pop bc
    inc c
    ld a, [wEnN]
    cp c
    jr nz, .l
.ok:
    scf
    ret
; A8 body_vs_en: carry = |B - E| < C and |D - wColZ| < C.
.near:
    ld a, [wColZ]
    ld h, a
; carry = |B - E| < C and |D - H| < C.
.nearH:
    ld a, b
    sub e
    jr nc, .x
    cpl
    inc a
.x:
    cp c
    ret nc
    ld a, d
    sub h
    jr nc, .z
    cpl
    inc a
.z:
    cp c
    ret

; A8 per-type enemy tables (tools/gbc_a8const.py), for this bank.
EN_META_ROWS EnMeta

; ==== Player shots (A8 src/enemy.asm gun_hitscan / shotgun_hitscan / punch_try_kill) ================
; The A8 tests in screen pixels (FOCAL 100, 192 px): |sx - (SCREEN_CX + aim)| <= limit. Here the same
; test is made on the view-space tangent r = lateral / forward (8.8), so the cone is the same angle at
; any viewport: pistol +-PISTOL_HIT_X px = tan 0.125, chaingun +-CHAIN_HIT_X px, each pellet a random
; column -SHOT_SPREAD_HALF .. +SHOT_SPREAD_HALF - 1 and the enemy's body half-width block_r units.
; Not ported yet: barrels, switches, blood / wall splats (the A8 scans those in the same loop).

DEF PISTOL_TAN  EQU (PISTOL_HIT_X * 2 + 1) * 256 / 200     ; half a pixel more, in tan 8.8 (1 px = 2.56)
DEF CHAIN_TAN   EQU (CHAIN_HIT_X * 2 + 1) * 256 / 200

; Shared by the stub in combat.asm: consume wFireEvent for the current weapon.
PlayerShotB::
    ld a, [wWpnCur]
    cp A8_WPN_FIST
    jp z, MeleeShot
    cp A8_WPN_SAW
    jp z, MeleeShot
    cp A8_WPN_ROCKET
    jp z, RocketShot
    cp A8_WPN_SHOT
    jr z, .shotgun
    ld hl, PISTOL_TAN                ; pistol / chaingun: one bullet, nearest body in the centre band
    cp A8_WPN_CHAIN
    jr nz, .flat
    ld hl, CHAIN_TAN
.flat:
    ld a, l
    ld [wScanLim], a
    ld a, h
    ld [wScanLim + 1], a
    xor a
    ld [wScanAim], a
    ld [wScanPel], a
    call GunScan
    ld a, [wScanBest]
    cp $FF
    jp z, SplatMiss                  ; nothing hit: a spark on the wall
    cp $40
    jp nc, ShotBarrel
    ld [wObjI], a
    call SplatHit
    ld a, PISTOL_DMG_MAX
    call RollUpto                    ; 1..16
    jp AiDamageEnemy
.shotgun:
    ld a, SHOT_PELLETS
    ld [wScanCnt], a
    ld a, 1
    ld [wScanPel], a
    ld a, $FF
    ld [wSgHit], a
    xor a
    ld [wSgAbs], a
.pellet:
    call Rnd
    and SHOT_SPREAD_MASK
    sub SHOT_SPREAD_HALF             ; uniform -32 .. +31 px
    ld [wScanAim], a
    call GunScan
    ld a, [wScanBest]
    cp $FF
    jr z, .next
    cp $40
    jr c, .enemy
    ld a, 1
    ld [wSgAbs], a
    ld a, [wScanBest]
    call ShotBarrel                  ; a pellet that reaches a barrel first sets it off
    jr .next
.enemy:
    ld [wSgHit], a
    ld [wObjI], a
    ld a, SHOT_DMG_ROLL
    call RollUpto
    add SHOT_DMG_BASE                ; 2..6 per pellet
    call AiDamageEnemy
.next:
    ld hl, wScanCnt
    dec [hl]
    jr nz, .pellet
    ld a, [wSgHit]                   ; one splat for the volley: blood on the last body hit, else a spark
    cp $FF
    jr z, .nohit
    ld [wObjI], a
    jp SplatHit
.nohit:
    ld a, [wSgAbs]
    and a
    ret nz                           ; a barrel took the shot
    jp SplatMiss

; A = $40 + thing index: the barrel the shot reached explodes (A8 barrel_explode).
ShotBarrel:
    and $3F
    jp BarrelExplode

; A = ceiling (>= 1) -> A uniform in 1..ceiling (A8 roll_upto).
RollUpto:
    cp 2
    ret c
    ld b, a
    call Rnd
.m:
    cp b
    jr c, .d
    sub b
    jr .m
.d:
    inc a
    ret

; A8 punch_try_kill (fist, chainsaw): the first live enemy of the room within PUNCH_HIT_R cells in any
; direction (and overlapping the player in Y) takes 1..16.
MeleeShot:
    xor a
    ldh [hSawBite], a                ; A8 start_saw: a miss clears the bite
    ld a, [wEnN]
    and a
    ret z
    xor a
    ld [wObjI], a
.l:
    ENPTR wEnState
    ld a, [hl]
    cp EN_DYING
    jr nc, .n
    ENPTR wEnRoom
    ld a, [wRoom]
    cp [hl]
    jr nz, .n
    ENPTR wEnX
    ld a, [hl]
    ld hl, wCamX + 1
    sub [hl]
    call Abs8
    cp PUNCH_HIT_R + 1
    jr nc, .n
    ENPTR wEnZ
    ld a, [hl]
    ld hl, wCamZ + 1
    sub [hl]
    call Abs8
    cp PUNCH_HIT_R + 1
    jr nc, .n
    ENPTR wEnY
    ld a, [hl]
    ld [wBoxY], a
    ld a, ENEMY_CULL_H
    ld [wBoxSY], a
    call PlayerOverlapsY
    jr nc, .n
    call Rnd
    swap a
    and $0F
    inc a                            ; (rnd >> 4) + 1
    ld a, 1
    ldh [hSawBite], a
    push af
    ld a, SND_PUNCH                  ; A8 start_punch / start_saw: SOUND_PUNCH on a hit
    call PlaySound
    pop af
    jp AiDamageEnemy
.n:
    ld hl, wObjI
    inc [hl]
    ld a, [wEnN]
    cp [hl]
    jp nz, .l
    ret

; A8 gun_hitscan + scan_shoot_barrels: the nearest target (enemy or barrel; smallest whole-cell depth,
; the first on a tie, enemies before barrels) in the cone, with a clear line from the eye.
; wScanPel 0: |r| <= wScanLim; 1: |r - tan(aim)| <= radius * 256 / forward.
; -> wScanBest = enemy index, $40 + thing index for a barrel, or $FF.
GunScan:
    ld a, $FF
    ld [wScanBest], a
    ld [wScanBestZ], a
    ld a, [wYaw]                     ; view direction (forward = sin, cos of yaw)
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wSin], a
    ld a, [wYaw]
    add 64
    ld l, a
    ld a, [hl]
    ld [wCos], a
    ld a, [wEnN]
    and a
    jr z, .barrels
    xor a
    ld [wObjI], a
.eloop:
    ENPTR wEnState
    ld a, [hl]
    cp EN_DYING
    jr nc, .enext
    ENPTR wEnRoom
    ld a, [wRoom]
    cp [hl]
    jr nz, .enext
    ENPTR wEnX
    ld a, [hl]
    ld [wTgt], a
    ENPTR wEnY
    ld a, [hl]
    add SHOT_MID_H
    ld [wTgt + 1], a
    ENPTR wEnZ
    ld a, [hl]
    ld [wTgt + 2], a
    ld a, EM_BLOCK_R
    call EnMetaGet
    ld [wTgtR], a
    ld a, [wObjI]
    ld [wScanId], a
    call ScanCand
.enext:
    ld hl, wObjI
    inc [hl]
    ld a, [wEnN]
    cp [hl]
    jr nz, .eloop
.barrels:
    ld a, [wMapHdr + H_NTHINGS]
    and a
    ret z
    ld c, 0
.bloop:
    push bc
    ld a, F_TH_TYPE
    call MapGet
    cp TH_BARREL
    jr nz, .bnext
    ld b, 0
    ld hl, wThTaken
    add hl, bc
    ld a, [hl]
    and a
    jr nz, .bnext
    ld a, F_TH_ROOM
    call MapGet
    ld b, a
    ld a, [wRoom]
    cp b
    jr nz, .bnext
    pop bc
    push bc
    call BarrelPv                    ; centre -> wTgt
    ld a, 1                          ; pellets test the barrel's body: a 1-unit radius
    ld [wTgtR], a
    pop bc
    push bc
    ld a, c
    or $40
    ld [wScanId], a
    call ScanCand
.bnext:
    pop bc
    inc c
    ld a, [wMapHdr + H_NTHINGS]
    cp c
    jr nz, .bloop
    ret

; One candidate at wTgt (cell x, y, z) with body radius wTgtR, id wScanId: nearer than the best so far,
; in front within SHOT_Z_MAX cells, a clear line from the eye, inside the cone -> becomes the best.
ScanCand:
    ld a, [wCamX]                    ; dx, dz = target - player (8.8)
    ld b, a
    xor a
    sub b
    ld [wDx], a
    ld a, [wTgt]
    ld b, a
    ld a, [wCamX + 1]
    ld c, a
    ld a, b
    sbc c
    ld [wDx + 1], a
    ld a, [wCamZ]
    ld b, a
    xor a
    sub b
    ld [wDz], a
    ld a, [wTgt + 2]
    ld b, a
    ld a, [wCamZ + 1]
    ld c, a
    ld a, b
    sbc c
    ld [wDz + 1], a
    ; forward f = dx*sin + dz*cos, lateral l = dx*cos - dz*sin
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
    ld [wShF], a
    ld a, [wTa + 1]
    adc d
    ld [wShF + 1], a
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
    ld [wShL], a
    ld a, [wTb + 1]
    sbc d
    ld [wShL + 1], a
    ld a, [wShF + 1]
    bit 7, a
    ret nz                           ; behind
    cp SHOT_Z_MAX
    ret nc                           ; beyond SHOT_Z_MAX cells
    ld b, a
    ld a, [wShF]
    or b
    ret z                            ; exactly at the camera
    ld a, [wScanBestZ]               ; only a strictly nearer whole-cell depth can win
    ld c, a
    ld a, b
    cp c
    ret nc
    ; clear line from the eye to the target
    ld a, [wCamX + 1]
    ld [wLnA], a
    ld a, [wCamY + 1]
    ld [wLnA + 1], a
    ld a, [wCamZ + 1]
    ld [wLnA + 2], a
    ld a, [wTgt]
    ld [wLnB], a
    ld a, [wTgt + 1]
    ld [wLnB + 1], a
    ld a, [wTgt + 2]
    ld [wLnB + 2], a
    call LineSolidsBlocked
    ret c
    ; r = |l| * 256 / f  (tan, 8.8), then the cone test
    ld a, [wShL + 1]
    ld [wShLSign], a
    bit 7, a
    ld a, [wShL]
    ld c, a
    ld a, [wShL + 1]
    ld b, a
    jr z, .ldone
    xor a                            ; BC = -l
    sub c
    ld c, a
    ld a, 0
    sbc b
    ld b, a
.ldone:                              ; BC = |l|
    ld a, b
    ld [wDvN + 2], a
    ld a, c
    ld [wDvN + 1], a
    xor a
    ld [wDvN], a                     ; numerator |l| << 8
    ld a, [wShF]
    ld e, a
    ld a, [wShF + 1]
    ld d, a
    call Div24x16
    call DvClamp                     ; HL = r (0..$7FFF)
    ld a, [wShLSign]
    bit 7, a
    jr z, .rpos
    xor a                            ; r = -r
    sub l
    ld l, a
    ld a, 0
    sbc h
    ld h, a
.rpos:
    ld a, [wScanPel]
    and a
    jr nz, .pellet
    ld a, [wScanLim]                 ; flat: T = lim, centre 0
    ld c, a
    ld a, [wScanLim + 1]
    ld b, a
    jr .cmp
.pellet:
    ; r -= tan(aim) = aim * 2.5625 (aim / 100 in tan 8.8)
    ld a, [wScanAim]
    ld b, a
    sra b
    ld c, b                          ; aim / 2
    ld a, [wScanAim]
    sra a
    sra a
    sra a
    sra a                            ; aim / 16
    add c
    ld c, a
    ld a, [wScanAim]
    add a
    add c                            ; 2 * aim + aim / 2 + aim / 16
    ld c, a
    add a
    sbc a
    ld b, a                          ; sign-extend
    ld a, l
    sub c
    ld l, a
    ld a, h
    sbc b
    ld h, a
    ; T = radius * 256 * 256 / f
    push hl
    ld a, [wTgtR]
    ld [wDvN + 2], a
    xor a
    ld [wDvN + 1], a
    ld [wDvN], a
    ld a, [wShF]
    ld e, a
    ld a, [wShF + 1]
    ld d, a
    call Div24x16
    call DvClampU                    ; HL = T (0..$FFFF)
    ld b, h
    ld c, l
    pop hl
.cmp:
    bit 7, h                         ; |HL| <= BC
    jr z, .abs
    xor a
    sub l
    ld l, a
    ld a, 0
    sbc h
    ld h, a
.abs:
    ld a, b
    cp h
    ret c
    jr nz, .hit
    ld a, c
    cp l
    ret c
.hit:
    ld a, [wShF + 1]
    ld [wScanBestZ], a
    ld a, [wScanId]
    ld [wScanBest], a
    ret

; B:C:D... 24-bit unsigned division. wDvN (3 bytes, lo..hi) / DE (16-bit, non-zero, < $8000) -> the
; quotient in wDvN. Clobbers A, C, HL.
Div24x16:
    ld hl, 0
    ld c, 24
.l:
    ld a, [wDvN]
    add a
    ld [wDvN], a
    ld a, [wDvN + 1]
    rla
    ld [wDvN + 1], a
    ld a, [wDvN + 2]
    rla
    ld [wDvN + 2], a
    rl l
    rl h
    ld a, h
    cp d
    jr c, .no
    jr nz, .sub
    ld a, l
    cp e
    jr c, .no
.sub:
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a
    ld a, [wDvN]
    or 1
    ld [wDvN], a
.no:
    dec c
    jr nz, .l
    ret

; Quotient in wDvN -> HL, saturating at $7FFF (signed use).
DvClamp:
    ld a, [wDvN + 2]
    and a
    jr nz, .sat
    ld a, [wDvN + 1]
    bit 7, a
    jr nz, .sat
    ld h, a
    ld a, [wDvN]
    ld l, a
    ret
.sat:
    ld hl, $7FFF
    ret

; Quotient in wDvN -> HL, saturating at $FFFF.
DvClampU:
    ld a, [wDvN + 2]
    and a
    jr nz, .sat
    ld a, [wDvN + 1]
    ld h, a
    ld a, [wDvN]
    ld l, a
    ret
.sat:
    ld hl, $FFFF
    ret

; A8 spawn_player_rocket: from the camera, feet + 2 high, along the view at RKT_SPEED_PL.
; The velocity is (sin or cos * speed) >> 7 as a sign-magnitude byte, i.e. (|t| >> 1) for 64.
RocketShot:
    call RktAlloc
    ret nc
    PRPTR wPrXL
    ld a, [wCamX]
    ld [hl], a
    PRPTR wPrX
    ld a, [wCamX + 1]
    ld [hl], a
    PRPTR wPrYL
    ld a, [wCamY]
    ld [hl], a
    PRPTR wPrY
    ld a, [wCamY + 1]
    sub EYE_HEIGHT - 2
    ld [hl], a
    PRPTR wPrZL
    ld a, [wCamZ]
    ld [hl], a
    PRPTR wPrZ
    ld a, [wCamZ + 1]
    ld [hl], a
    PRPTR wPrFl
    ld [hl], 0
    PRPTR wPrOwn
    ld [hl], RKT_OWN_PL
    PRPTR wPrAcc
    ld [hl], 0
    PRPTR wPrLifeL
    ld [hl], LOW(RKT_LIFE_MS)
    PRPTR wPrLifeH
    ld [hl], HIGH(RKT_LIFE_MS)
    PRPTR wPrVXL
    ld [hl], 0
    PRPTR wPrVYL
    ld [hl], 0
    PRPTR wPrVYH
    ld [hl], 0
    PRPTR wPrVZL
    ld [hl], 0
    ld a, [wYaw]
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    call SpeedPl
    ld b, a
    PRPTR wPrVXH
    ld [hl], b
    ld a, [wYaw]
    add 64
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    call SpeedPl
    ld b, a
    PRPTR wPrVZH
    ld [hl], b
    PRPTR wPrOn
    ld [hl], 1
    ret

; A = signed trig -> A = sign * ((|A| * RKT_SPEED_PL) >> 7) (A8 smul7, sign-magnitude).
SpeedPl:
    push af
    call Abs8
    ld b, RKT_SPEED_PL
    call Mul8u                       ; HL = |t| * speed
    sla l
    ld a, h
    rla                              ; (HL << 1) >> 8 = HL >> 7
    ld b, a
    pop af
    bit 7, a
    ld a, b
    ret z
    cpl
    inc a
    ret

; ==== Splats (A8 shotgun_hit_splat / shotgun_miss_splat / splat_spawn) ===================================

; wTgt = hit point (cells), A = COL_SPLAT_*: anchor it in the world, jitter it, start the SPLAT_MS timer.
SplatSet:
    ld [wSplatCol], a
    xor a
    ld [wSplatOrg], a
    ld [wSplatOrg + 2], a
    ld [wSplatOrg + 4], a
    ld a, [wTgt]
    ld [wSplatOrg + 1], a
    ld a, [wTgt + 1]
    ld [wSplatOrg + 3], a
    ld a, [wTgt + 2]
    ld [wSplatOrg + 5], a
    call Rnd
    and 7
    sub 4                            ; -4 .. +3 px (A8: +-4 half pixels of a 96 px view)
    ld [wSplatJx], a
    call Rnd
    and 3
    sub 2                            ; -2 .. +1 px
    ld [wSplatJy], a
    ld a, SPLAT_MS
    ld [wSplatMs], a
    ld a, 1
    ld [wSplatFresh], a              ; a frame can outlast SPLAT_MS: draw it at least once
IF DEF(SMOKE)
    ld hl, wSplatSeen
    inc [hl]
ENDC
    ret

; wObjI = enemy: blood at its mid-body.
SplatHit:
    ENPTR wEnX
    ld a, [hl]
    ld [wTgt], a
    ENPTR wEnY
    ld a, [hl]
    add SHOT_MID_H
    ld [wTgt + 1], a
    ENPTR wEnZ
    ld a, [hl]
    ld [wTgt + 2], a
    ld a, COL_SPLAT_HIT
    jr SplatSet

; The view ray hit the nearest solid of the room: a spark there.
SplatMiss:
    call WallHit
    ret nc
    ld a, COL_SPLAT_MISS
    call SplatSet
    ; fall through: WallHit's point is whole cells (eye and hit both floored), which lands it up to ~1.4
    ; cells off the view ray, a constant screen-x offset per angle / distance. Slide it back onto the axis.

; Shift wSplatOrg sideways (along the view's X axis) so its view-space X is 0 (the aim ray: screen centre).
SplatCenter:
    ld a, [wCamX]                    ; dx = org - cam (8.8, org fraction 0)
    ld b, a
    xor a
    sub b
    ld [wDx], a
    ld a, [wCamX + 1]
    ld b, a
    ld a, [wSplatOrg + 1]
    sbc b
    ld [wDx + 1], a
    ld a, [wCamZ]
    ld b, a
    xor a
    sub b
    ld [wDz], a
    ld a, [wCamZ + 1]
    ld b, a
    ld a, [wSplatOrg + 5]
    sbc b
    ld [wDz + 1], a
    ld a, [wDx]                      ; X = dx * cos - dz * sin
    ld e, a
    ld a, [wDx + 1]
    ld d, a
    ld a, [wCos]
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
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, [wTa]
    sub e
    ld [wTa], a
    ld a, [wTa + 1]
    sbc d
    ld [wTa + 1], a                  ; X
    ld a, [wTa]                      ; org.x -= X * cos
    ld e, a
    ld a, [wTa + 1]
    ld d, a
    ld a, [wCos]
    ld c, a
    call SMul16
    ld a, [wSplatOrg]
    sub e
    ld [wSplatOrg], a
    ld a, [wSplatOrg + 1]
    sbc d
    ld [wSplatOrg + 1], a
    ld a, [wTa]                      ; org.z += X * sin
    ld e, a
    ld a, [wTa + 1]
    ld d, a
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, [wSplatOrg + 4]
    add e
    ld [wSplatOrg + 4], a
    ld a, [wSplatOrg + 5]
    adc d
    ld [wSplatOrg + 5], a
    ret

; A8 line_fit_b + line_solids_hit with pitch 0: from the eye along the view to the room boundary, the nearest
; solid (cutout, crate, platform, car, slope, the room shell) -> wTgt (cells). Carry = found.
WallHit:
    ld a, [wCamX + 1]
    ld [wLnA], a
    ld a, [wCamY + 1]
    ld [wLnA + 1], a
    ld [wLnB + 1], a                 ; level
    ld a, [wCamZ + 1]
    ld [wLnA + 2], a
    ld a, [wRoom]
    ld c, a
    ld a, F_ROOM_X
    call LoadBoxMap
    call LineBoxMax
    ld a, [wSin]
    call Abs8
    ld b, a                          ; |sin|
    ld a, [wCos]
    call Abs8
    cp b
    jr nc, .zdom
    ; X dominant: B_x on the room's x boundary, B_z on the ray
    ld a, [wSin]
    bit 7, a
    ld a, [wLBox]
    jr nz, .xmin
    ld a, [wLnM]                     ; exclusive max
    jr .xset
.xmin:
    and a
    jr z, .xset
    dec a
.xset:
    ld [wLnB], a
    ld hl, wLnA
    call .span                       ; E = R = |B_x - A_x| capped at 127
    ld a, [wSin]
    call Abs8
    ld c, a                          ; M
    ld a, [wCos]
    ld b, e
    call LerpDv                      ; cos * R / M
    ld hl, wLnA + 2
    call .addsat
    ld [wLnB + 2], a
    jr .fit
.zdom:
    ld a, [wCos]
    bit 7, a
    ld a, [wLBox + 2]
    jr nz, .zmin
    ld a, [wLnM + 2]
    jr .zset
.zmin:
    and a
    jr z, .zset
    dec a
.zset:
    ld [wLnB + 2], a
    ld hl, wLnA + 2
    call .span
    ld a, [wCos]
    call Abs8
    ld c, a
    ld a, [wSin]
    ld b, e
    call LerpDv
    ld hl, wLnA
    call .addsat
    ld [wLnB], a
.fit:
    ld a, $FF
    ld [wLnNear], a
    ld a, 1
    ld [wLnMode], a
    call LineSolidsBlocked
    xor a
    ld [wLnMode], a
    ld a, [wLnNear]
    cp $FF
    ret z                            ; (carry is clear: cp equal)
    ld c, 0
.pt:
    push bc
    ld a, [wLnNear]
    call LinePtAt                    ; A = t, C = axis -> a + d * t / 127
    pop bc
    ld hl, wTgt
    ld b, 0
    add hl, bc
    ld [hl], a
    inc c
    ld a, c
    cp 3
    jr nz, .pt
    scf
    ret
; HL = &A_axis; the matching B axis is 3 bytes on: E = min(127, |B - A|).
.span:
    ld a, [hl]
    ld de, 3
    add hl, de
    ld b, a
    ld a, [hl]
    sub b
    call Abs8
    cp 128
    jr c, .sp
    ld a, 127
.sp:
    ld e, a
    ret
; A = signed delta, HL = &A_other: A_other + delta, saturating.
.addsat:
    ld b, a
    ld a, [hl]
    bit 7, b
    jr nz, .neg
    add b
    ret nc
    ld a, 255
    ret
.neg:
    add b
    ret c
    xor a
    ret
