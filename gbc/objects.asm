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
    ld a, 128
    ld [wEntOX], a
    ld [wEntOZ], a
    xor a
    ld [wEntOY], a
    ld a, b
    ld [wEntOX + 1], a
    ld a, c
    ld [wEntOY + 1], a
    ld a, d
    ld [wEntOZ + 1], a
    ld a, [wSpin]
    add a
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
    cp EN_DEAD
    jp z, .nextE
    cp EN_ALERT
    jr nz, .stOk
    xor a                           ; alert is drawn as idle
.stOk:
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
    ld hl, wEnYaw
    add hl, de
    ld a, [hl]
    ld [wEntYaw], a
    ld hl, wEnTimer
    add hl, de
    ld a, [hl]
    ld [wTmpFrame], a               ; state timer
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    ld c, a
    ld b, 0
    ld hl, EnemyTab
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [wTmpKind]
    add a
    add 8                           ; clip table offset: 8 + 2 * state
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hl+]
    ld [wTmpAux], a                 ; clip start
    ld a, [hl]
    ld b, a                         ; clip length
    ld a, [wTmpKind]
    and a
    jr nz, .notIdle
    ld a, [wSpin]                   ; idle: ambient loop on the global counter
    jr .haveTimer
.notIdle:
    cp EN_CHASE
    ld a, [wTmpFrame]
    jr nz, .haveTimer
    ld a, [wObjI]                   ; walk cycle: global counter, phase offset per enemy
    ld c, a                         ; (B holds the clip length)
    add a
    add a
    add c
    ld c, a
    ld a, [wSpin]
    add c
.haveTimer:
    srl a
    srl a
    ld d, a                         ; timer / 4
    ld a, [wTmpKind]
    cp EN_CHASE + 1
    ld a, d
    jr nc, .clamp                   ; attack / pain / dying: hold the last frame
.mod:                               ; idle / chase: loop
    cp b
    jr c, .modDone
    sub b
    jr .mod
.clamp:
    cp b
    jr c, .modDone
    ld a, b
    dec a
.modDone:
    ld d, a
    ld a, [wTmpAux]
    add d                           ; frame
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
.nextE:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    ld b, a
    ld a, [wEnN]
    cp b
    jp nz, .enemy
    jp DrawProjectiles

; Fireballs of this room (wPr* arrays, gbc/ai.asm): the shared item mesh, spinning.
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
    ld hl, wPrRoom
    add hl, de
    ld a, [wRoom]
    cp [hl]
    jr nz, .np
    ld hl, wPrXL
    add hl, de
    ld a, [hl]
    ld [wEntOX], a
    ld hl, wPrX
    add hl, de
    ld a, [hl]
    ld [wEntOX + 1], a
    ld hl, wPrZL
    add hl, de
    ld a, [hl]
    ld [wEntOZ], a
    ld hl, wPrZ
    add hl, de
    ld a, [hl]
    ld [wEntOZ + 1], a
    ld hl, wPrY
    add hl, de
    ld a, [hl]
    ld [wEntOY + 1], a
    xor a
    ld [wEntOY], a
    ld a, [wSpin]
    add a
    add a
    ld [wEntYaw], a
    ld a, [EntBank]
    ld [rROMB0], a
    ld hl, ItemTab + 2 * ITEM_FIREBALL
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    call EntSetMesh
    call DrawEntity
.np:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    cp PR_N
    jr nz, .p
    ret

; Enemy arrays from the payload (en_*). Positions are integer cells (drawn at the cell centre).
LoadEnemies::
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
    swap a
    add a                           ; rot * 32
    ld hl, wEnYaw
    call .put
    xor a
    ld hl, wEnState
    call .put
    ld hl, wEnFrame
    call .put
    ld hl, wEnTimer
    call .put
    ld hl, wEnCool
    call .put
    ld a, 128
    ld hl, wEnXL
    call .put
    ld a, 128
    ld hl, wEnZL
    call .put
    ld a, $FF
    ld hl, wEnDir
    call .put
    xor a
    ld hl, wEnStep
    call .put
    xor a                           ; .put clobbers A
    ld hl, wEnAtk
    call .put
    xor a
    ld hl, wPrOn                    ; no fireballs in flight
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
    ld a, [EntBank]
    ld [rROMB0], a
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnType
    add hl, de
    ld a, [hl]
    add a
    ld c, a
    ld b, 0
    ld hl, EnemyTab
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, 5
    add hl, de
    ld a, [hl]                      ; hp from the entity record
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
