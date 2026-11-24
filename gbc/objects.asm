; World object drawing: per-room static meshes (crates, platforms, slopes, switches, elevators,
; doors), pickups/props (shared item meshes, spinning) and enemies (animated frames).
; Static lists live in the level's object bank, item/enemy meshes in the entity bank.
; Spec: tools/gbc_entity.py + tools/gbc_genobj.py (see gbc_check.py --live).

INCLUDE "hw.inc"
INCLUDE "map_fields.inc"

INCLUDE "en.inc"

SECTION "objects", ROM0

; HL = mesh header (nv, ne, shift, radius, verts, edges) in the mapped bank -> wEnt* mesh vars.
EntSetMesh::
    ld a, [hl+]
    ld [wEntNV], a
    ld c, a
    ld a, [hl+]
    ld [wEntNE], a
    ld a, [hl+]
    ld [wEntShift], a
    ld a, [hl+]
    ld [wEntRadius], a
    ld a, l
    ld [wEntVP], a
    ld a, h
    ld [wEntVP + 1], a
    ld a, c
    add a
    add c
    ld c, a
    ld b, 0
    add hl, bc
    ld a, l
    ld [wEntEP], a
    ld a, h
    ld [wEntEP + 1], a
    ret

; C = enemy type, A = frame index (entity bank mapped) -> wEnt* mesh vars.
EntSetEnemyMesh::
    ld [wTmpFrame], a
    ld b, 0
    ld hl, EnemyTab
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; HL = enemy record
    ld a, [hl+]
    ld [wEntNV], a
    ld a, [hl+]
    ld [wEntNE], a
    ld a, [hl+]
    ld [wEntShift], a
    ld a, [hl+]
    ld [wEntRadius], a
    ld bc, 4 + 10                   ; nframes, hp, block_r, weapon_vert + clip table
    add hl, bc
    ld a, l
    ld [wEntEP], a
    ld a, h
    ld [wEntEP + 1], a
    ld a, [wEntNE]
    add a
    ld c, a
    ld b, 0
    add hl, bc                      ; frame 0
    ld a, [wEntNV]
    ld c, a
    add a
    add c
    ld c, a                         ; bytes per frame
    ld b, 0
    ld a, [wTmpFrame]
.frame:
    and a
    jr z, .done
    add hl, bc
    dec a
    jr .frame
.done:
    ld a, l
    ld [wEntVP], a
    ld a, h
    ld [wEntVP + 1], a
    ret

; Draw everything in the current room: statics, things, enemies.
DrawWorldObjects::
    ; ---- statics ----
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
    ld a, [hl+]
    ld [wObjN], a
    ld a, l
    ld [wObjPtr], a
    ld a, h
    ld [wObjPtr + 1], a
    xor a
    ld [wObjI], a
.static:
    ld a, [wObjI]
    ld b, a
    ld a, [wObjN]
    cp b
    jp z, .things
    ld a, [wObjPtr]
    ld l, a
    ld a, [wObjPtr + 1]
    ld h, a
    ld a, [hl+]
    ld [wTmpMesh], a
    ld a, [hl+]
    ld [wTmpMesh + 1], a
    ld a, [hl+]
    ld [wEntOX], a
    ld a, [hl+]
    ld [wEntOX + 1], a
    ld a, [hl+]
    ld [wEntOY], a
    ld a, [hl+]
    ld [wEntOY + 1], a
    ld a, [hl+]
    ld [wEntOZ], a
    ld a, [hl+]
    ld [wEntOZ + 1], a
    ld a, [hl+]
    ld [wEntYaw], a
    ld a, [hl+]
    ld [wTmpKind], a
    ld a, [hl+]
    ld [wTmpAux], a
    ld a, l
    ld [wObjPtr], a
    ld a, h
    ld [wObjPtr + 1], a
    ld a, [wTmpKind]
    cp 1
    jr nz, .drawS
    ld a, [wTmpAux]
    ld c, a
    ld a, F_DOOR_TYPE
    call MapGet
    bit 7, a
    jr nz, .nextS                   ; hidden door
.drawS:
    ld a, [wTmpMesh]
    ld l, a
    ld a, [wTmpMesh + 1]
    ld h, a
    call EntSetMesh
    call DrawEntity
.nextS:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    jp .static

    ; ---- things ----
.things:
    ld a, [wObjPtr]
    ld l, a
    ld a, [wObjPtr + 1]
    ld h, a
    ld a, [hl+]
    ld [wObjN], a
    ld a, l
    ld [wObjPtr], a
    ld a, h
    ld [wObjPtr + 1], a
    xor a
    ld [wObjI], a
.thing:
    ld a, [wObjI]
    ld b, a
    ld a, [wObjN]
    cp b
    jp z, .enemies
    ld a, [wObjPtr]
    ld l, a
    ld a, [wObjPtr + 1]
    ld h, a
    ld a, [hl+]
    ld [wTmpAux], a                 ; thing index
    ld a, [hl+]
    ld [wTmpKind], a                ; type
    ld a, [hl+]
    ld b, a                         ; x
    ld a, [hl+]
    ld c, a                         ; y
    ld a, [hl+]
    ld d, a                         ; z
    inc hl
    ld a, l
    ld [wObjPtr], a
    ld a, h
    ld [wObjPtr + 1], a
    ld a, [wTmpAux]
    ld e, a
    push de
    ld d, 0
    ld hl, wThTaken
    add hl, de
    ld a, [hl]
    pop de
    and a
    jr nz, .nextT
    ; A8 xform_item_spin: world centre = box + ITEM_BIAS (1) on X and Z.
    xor a
    ld [wEntOX], a
    ld [wEntOZ], a
    ld [wEntOY], a
    ld a, b
    inc a
    ld [wEntOX + 1], a
    ld a, c
    ld [wEntOY + 1], a
    ld a, d
    inc a
    ld [wEntOZ + 1], a
    ; A8 fill_item_verts: props (lightpost, barrel) stay put; pickups spin on item_spin.
    ld a, [wTmpKind]
    cp TH_LIGHTPOST
    jr z, .still
    cp TH_BARREL
    jr z, .still
    ld a, [wItemSpin + 1]
    jr .yaw
.still:
    xor a
.yaw:
    ld [wEntYaw], a
    ld a, [EntBank]
    ld [rROMB0], a
    ld a, [wTmpKind]
    ld c, a
    ld b, 0
    ld hl, ItemTab
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    call EntSetMesh
    call DrawEntity
    ld a, [wObjBank]
    ld [rROMB0], a
.nextT:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    jp .thing

    ; ---- enemies ----
.enemies:
    ld a, [EntBank]
    ld [rROMB0], a
    ld a, [wEnN]
    and a
    ret z
    xor a
    ld [wObjI], a
.enemy:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnRoom
    add hl, de
    ld a, [wRoom]
    cp [hl]
    jp nz, .nextE
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_GONE
    jp z, .nextE                    ; tagged, not spawned yet
    ld [wTmpKind], a                ; state
    ld hl, wEnX
    add hl, de
    ld a, [hl]
    ld [wEntOX + 1], a
    ld hl, wEnXL
    add hl, de
    ld a, [hl]
    ld [wEntOX], a
    ld hl, wEnY
    add hl, de
    ld a, [hl]
    ld [wEntOY + 1], a
    ld hl, wEnZ
    add hl, de
    ld a, [hl]
    ld [wEntOZ + 1], a
    ld hl, wEnZL
    add hl, de
    ld a, [hl]
    ld [wEntOZ], a
    xor a
    ld [wEntOY], a
    ld hl, wEnRot                   ; A8 draws bones with R(yaw - en_rot)
    add hl, de
    xor a
    sub [hl]
    ld [wEntYaw], a
    ; A8 enemy_logical_frame: clip start for the state (+ the pain / death variant) + en_frame
    ld hl, wEnPainI
    add hl, de
    ld b, [hl]
    ld hl, wEnFrame
    add hl, de
    ld c, [hl]
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    add a
    ld e, a
    ld d, 0
    ld hl, EnMetaEPtr
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; HL = meta row
    ld a, [wTmpKind]
    ld e, EM_DEATH_S
    cp EN_DYING
    jr z, .var
    cp EN_DEAD
    jr z, .var
    ld e, EM_PAIN_S
    cp EN_PAIN
    jr z, .var
    ld e, EM_ATK_S
    cp EN_ATTACK
    jr z, .clip
    ld e, EM_ALERT_S
    cp EN_ALERT
    jr z, .clip
    ld e, EM_RUN_S
    cp EN_APPROACH
    jr z, .clip
    ld e, EM_STAND_S
    jr .clip
.var:
    ld a, e
    add b
    ld e, a
.clip:
    ld d, 0
    add hl, de
    ld a, [hl]
    add c                           ; logical frame
    push af
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    ld c, a
    pop af
    call EntSetEnemyMesh            ; C = type, A = frame
    call DrawEntity
    call MuzzleCheck
.nextE:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    ld b, a
    ld a, [wEnN]
    cp b
    jp nz, .enemy
    call DrawProjectiles
    ld a, [EntBank]
    ld [rROMB0], a
    jp DrawMuzzle

; A8 draw_rockets / rkt_draw_one: every fireball in flight as a screen triangle of half-extent
; RKT_R (0.375 units) at its depth, in red. The triangle is the fireball item mesh turned to face the
; camera (yaw = -camera yaw), so the entity projection and clipping draw it; hPlane = 1 puts its
; lines in bitplane 1 (colour 2 = A8 red $46).
DrawProjectiles:
    xor a
    ld [wObjI], a
.p:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wPrOn
    add hl, de
    ld a, [hl]
    and a
    jr z, .np
    ld hl, wPrXL
    add hl, de
    ld a, [hl]
    ld [wEntOX], a
    ld hl, wPrX
    add hl, de
    ld a, [hl]
    ld [wEntOX + 1], a
    ld hl, wPrYL
    add hl, de
    ld a, [hl]
    ld [wEntOY], a
    ld hl, wPrY
    add hl, de
    ld a, [hl]
    ld [wEntOY + 1], a
    ld hl, wPrZL
    add hl, de
    ld a, [hl]
    ld [wEntOZ], a
    ld hl, wPrZ
    add hl, de
    ld a, [hl]
    ld [wEntOZ + 1], a
    ld a, [wYaw]
    cpl
    inc a
    ld [wEntYaw], a
    ld a, [EntBank]
    ld [rROMB0], a
    ld hl, ItemTab + 2 * ITEM_FIREBALL
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    call EntSetMesh
    ld a, 1
    ldh [hPlane], a
    call DrawEntity
    xor a
    ldh [hPlane], a
.np:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    cp RKT_MAX
    jr nz, .p
    ret

; C = enemy type, A = pose frame, B = vertex -> D = lx, B = ly, E = lz (signed pose bytes).
; Called from bank 31 (gbc/ai.asm EnVertWorld): maps the entity bank, then the AI bank back.
EnVertLocal::
    push bc
    push af
    ld a, [EntBank]
    ld [rROMB0], a
    pop af
    call EntSetEnemyMesh
    pop bc
    ld a, [wEntVP]
    ld l, a
    ld a, [wEntVP + 1]
    ld h, a
    ld a, b
    add a
    add b
    ld e, a
    ld d, 0
    add hl, de
    ld d, [hl]
    inc hl
    ld b, [hl]
    inc hl
    ld e, [hl]
    ld a, BANK(AiTick)
    ld [rROMB0], a
    ret

; A8 init_enemies: enemy arrays from the payload (en_*). Positions are whole cells, drawn at the
; cell origin as on the A8 (wEnXL / wEnZL = 0). en_dir = map rot (editor octant, 0 = +z),
; en_rot = rot * 32, hp from the A8 table, idle; tagged enemies stay EN_GONE until a spawn trigger.
LoadEnemies::
    ld a, [EntBank]                 ; hp from EnMetaE (entity bank)
    ld [rROMB0], a
    xor a
    ld [wAnimAcc], a                ; A8 loader.asm: anim_acc = 0
    ld [wAnimAcc + 1], a
    ld [wDoomAnimPh], a
    ld [wGunshotWake], a
    ld [wFxMs], a                   ; A8 init_things / init_rockets: no explosion, no barrel chain
    ld [wFxMs + 1], a
    ld [wBarrelCh], a
    ld [wBarrelCh + 1], a
    ld hl, wBarrelPend
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld hl, wPrOn                    ; no fireballs in flight
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
    ld a, [wMapHdr + H_NENEMIES]
    ld [wEnN], a
    and a
    ret z
    xor a
    ld [wObjI], a
.l:
    ld a, [wObjI]
    ld c, a
    ld a, F_EN_X
    call MapGet
    ld hl, wEnX
    call .put
    ld a, F_EN_Y
    call MapGet
    ld hl, wEnY
    call .put
    ld a, F_EN_Z
    call MapGet
    ld hl, wEnZ
    call .put
    ld a, F_EN_TYPE
    call MapGet
    ld hl, wEnType
    call .put
    ld a, F_EN_ROOM
    call MapGet
    ld hl, wEnRoom
    call .put
    ld a, F_EN_ROT
    call MapGet
    and 7
    ld hl, wEnDir
    call .put
    ld a, F_EN_ROT
    call MapGet
    swap a
    add a                           ; en_rot = rot * 32
    ld hl, wEnRot
    call .put
    ld a, F_EN_TAG
    call MapGet
    and a
    ld a, EN_IDLE
    jr z, .st
    ld a, EN_GONE
.st:
    ld hl, wEnState
    call .put
    xor a
    ld hl, wEnFrame
    call .put
    xor a
    ld hl, wEnTimer
    call .put
    xor a
    ld hl, wEnTimerH
    call .put
    xor a
    ld hl, wEnStep
    call .put
    xor a
    ld hl, wEnStepH
    call .put
    xor a
    ld hl, wEnPainI
    call .put
    xor a
    ld hl, wEnXL
    call .put
    xor a
    ld hl, wEnZL
    call .put
    xor a
    ld hl, wEnAtk
    call .put
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    add a
    ld e, a
    ld hl, EnMetaEPtr
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, EM_HP
    add hl, de
    ld a, [hl]                      ; A8 enemy_hp_init
    ld hl, wEnHp
    call .put
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    ld b, a
    ld a, [wEnN]
    cp b
    jp nz, .l
    ret
; A = value, HL = array base, wObjI = index
.put:
    ld e, a
    ld a, [wObjI]
    add l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    ld [hl], e
    ret

; A8 per-type enemy tables (tools/gbc_a8const.py), next to the enemy meshes in the entity bank.
INCLUDE "a8enmeta.inc"
SECTION "ent_meta", ROMX, BANK[ENT_BANK]
EN_META_ROWS EnMetaE

; The muzzle code runs only while the entity bank is mapped (enemy and fireball drawing).
; A8 try_enemy_muzzle / enemy_muzzle_want, after the enemy wObjI is drawn (its projected vertices in
; wVerts): a possessed shooting, or an imp / baron throwing, on its fire frame starts the muzzle at
; the projected weapon vertex for EMUZ_MS. LOD by the vertex depth (EMUZ_Z0 / EMUZ_Z1). The anchor
; (tip - EMUZ_OX / OY) snaps to the nearest byte column and the 24x21 box stays in the viewport
; (A8 stamp_anchor).
MuzzleCheck:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_ATTACK
    ret nz
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    ld c, a
    cp ENT_PINKY
    ret z                           ; bite: no muzzle
    cp ENT_POSS
    jr z, .ff
    ld hl, wEnAtk
    add hl, de
    ld a, [hl]
    and a
    ret z                           ; claw: no muzzle
.ff:
    push de
    ld a, c
    add a
    ld e, a
    ld d, 0
    ld hl, EnMetaEPtr
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, EM_FIRE_FRAME
    add hl, de
    ld b, [hl]
    pop de
    bit 7, b
    ret nz
    ld hl, wEnFrame
    add hl, de
    ld a, [hl]
    cp b
    ret nz                          ; not on the fire frame
    ld b, 0
    ld hl, EnemyTab
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, 7
    add hl, de
    ld c, [hl]                      ; weapon vertex (ents.inc record byte 7)
    ld a, c
    add 160
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl]
    and a
    ret z                           ; behind the camera
    ld a, c
    add a
    add 65
    ld l, a
    ld a, [hl]                      ; depth, whole units
    ld b, 0
    cp EMUZ_Z0
    jr c, .lod
    inc b
    cp EMUZ_Z1
    jr c, .lod
    inc b
.lod:
    ld a, b
    ld [wEmuzLod], a
    ld a, c
    add a
    add 96
    ld l, a
    ld a, [hl+]
    ld e, a
    ld d, [hl]                      ; DE = tip sx
    ld hl, 4 - EMUZ_OX
    add hl, de
    sra h
    rr l
    sra h
    rr l
    sra h
    rr l                            ; nearest byte column of the uncropped left
    bit 7, h
    ld a, 0
    jr nz, .col
    ld a, h
    and a
    ld a, VIEW_COLS - 3
    jr nz, .col
    ld a, l
    cp VIEW_COLS - 3
    jr c, .col
    ld a, VIEW_COLS - 3
.col:
    ld [wEmuzCol], a
    ld a, c
    add a
    add 128
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl+]
    ld e, a
    ld d, [hl]                      ; DE = tip sy
    ld hl, -EMUZ_OY
    add hl, de
    bit 7, h
    ld a, 0
    jr nz, .row
    ld a, h
    and a
    ld a, VIEW_ROWS * 8 - 21
    jr nz, .row
    ld a, l
    cp VIEW_ROWS * 8 - 21
    jr c, .row
    ld a, VIEW_ROWS * 8 - 21
.row:
    ld [wEmuzY], a
    ld a, EMUZ_MS
    ld [wEmuzMs], a
IF DEF(SMOKE)
    ld hl, wEmuzSeen                ; smoke test: muzzle starts
    inc [hl]
ENDC
    ret

; A8 stamp_emuz: while the muzzle timer runs, OR its 24x21 LOD image into bitplane 1 (red) at the
; anchored byte column / row.
DrawMuzzle:
    ld a, [wEmuzMs]
    and a
    ret z
    ld a, [wEmuzLod]
    add a
    ld e, a
    ld d, 0
    ld hl, EmuzPtr
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld b, h
    ld c, l                         ; BC = image rows (3 bytes each)
    xor a
.colk:
    ld [wEmuzK], a
    push bc
    ld a, [wEmuzCol]                ; HL = FB + (col + k) * FB_STRIDE + y * 2 + 1
    ld e, a
    ld a, [wEmuzK]
    add e
    ld e, a
    ld d, 0
    ld hl, FB + 1
    ld a, e
    and a
    jr z, .y
.mul:
    push de
    ld de, FB_STRIDE
    add hl, de
    pop de
    dec e
    jr nz, .mul
.y:
    ld a, [wEmuzY]
    add a
    ld e, a
    ld d, 0
    add hl, de
    ld a, [wEmuzK]
    add c
    ld c, a
    ld a, b
    adc 0
    ld b, a                         ; BC = this column's byte of row 0
    ld d, 21
.rows:
    ld a, [bc]
    or [hl]
    ld [hl+], a
    inc hl
    inc bc
    inc bc
    inc bc
    dec d
    jr nz, .rows
    pop bc
    ld a, [wEmuzK]
    inc a
    cp 3
    jr nz, .colk
    ret

