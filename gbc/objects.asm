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
    cp 2
    jp z, .elev
    cp 1
    jp z, .door
    cp 3
    jp z, .crate
    cp 4
    jp z, .switch
    cp 5
    jp nz, .drawS
    ld a, [wTmpAux]                 ; platform: a small non-solid one is not drawn from below
    ld c, a
    ld a, F_PLAT_SOLID
    call MapGet
    and a
    jp nz, .drawS
    ld a, F_PLAT_SX
    call MapGet
    cp 5
    jp nc, .drawS
    ld a, F_PLAT_SZ
    call MapGet
    cp 5
    jp nc, .drawS
    ld a, F_PLAT_Y
    call MapGet
    ld b, a
    ld a, [wCamY + 1]
    cp b
    jp c, .nextS                    ; eye below the plane
    jp .drawS
.door:
    ld a, [wTmpAux]
    ld c, a
    ld a, F_DOOR_TYPE
    call MapGet
    bit 7, a
    jp nz, .nextS                   ; hidden door
    ld a, F_DOOR_X                  ; the type mesh sits on the outward face: only seen from its air side
    call LoadBox6
    ld a, F_DOOR_FACE
    call MapGet
    call FaceFront
    jp nc, .nextS
    jp .drawS
.switch:                            ; the face id points at the wall: seen from the other side
    ld a, [wTmpAux]
    ld c, a
    ld a, F_SW_X
    call LoadBox6
    ld a, F_SW_FACE
    call MapGet
    call FaceFront
    jp c, .nextS
    jp .drawS
.crate:                             ; A8 draw_box: edges of faces the eye can see, all 12 with crate_flags
    ld a, [wTmpAux]
    ld c, a
    ld a, F_CRATE_FLAGS
    call MapGet
    and a
    jp nz, .drawS
    ld a, F_CRATE_X
    call LoadBox6
    call CrateFaceBits
    ld [wTmpFrame], a               ; face bits
    jp .drawS
.elev:                              ; A8: the top plate at elev_y + sy
    ld a, [wTmpAux]
    ld c, a
    ld a, F_ELEV_SY
    call MapGet
    ld e, c
    ld d, 0
    ld hl, wElevY
    add hl, de
    add [hl]
    ld [wEntOY + 1], a
    xor a
    ld [wEntOY], a
.drawS:
    ld a, [wTmpMesh]
    ld l, a
    ld a, [wTmpMesh + 1]
    ld h, a
    call EntSetMesh
    ld a, [wTmpKind]
    cp 3
    jp nz, .draw
    ld a, [wTmpAux]
    ld c, a
    ld a, F_CRATE_FLAGS
    call MapGet
    and a
    jp nz, .draw
    call CullCrateEdges             ; wTmpFrame = face bits
    jp z, .nextS                    ; no visible edge
.draw:
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
    jp z, DrawCrack
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
    call DrawCrack
    call DrawProjectiles
    ld a, [EntBank]
    ld [rROMB0], a
    call DrawExplosion
    call DrawSplat
    jp DrawMuzzle

; A8 draw_crack: the bump mark, the Crack door mesh at x1 on the stored face point, current room
; only, from the outward side of its face (the plane is the stored coordinate; PZ / PX need cam >= it,
; MZ / MX cam <= it).
DrawCrack:
    ld a, [wCrackMs]
    ld b, a
    ld a, [wCrackMs + 1]
    or b
    ret z
    ld a, [wCrackRoom]
    ld b, a
    ld a, [wRoom]
    cp b
    ret nz
    ld a, [wCrackFace]
    srl a
    xor 1                           ; face axis: 0 X, 1 Z
    ld e, a
    ld d, 0
    ld hl, wCrackX
    add hl, de
    ld b, [hl]                      ; plane
    ld hl, wCamX + 1
    ld a, e
    and a
    jr z, .cam
    ld hl, wCamZ + 1
.cam:
    ld c, [hl]                      ; eye
    ld a, [wCrackFace]
    rra
    jr c, .minus
    ld a, c
    cp b                            ; PZ / PX: hidden when eye < plane
    ret c
    jr .vis
.minus:
    ld a, b
    cp c                            ; MZ / MX: hidden when plane < eye
    ret c
.vis:
    ld a, [wCrackXL]
    ld [wEntOX], a
    ld a, [wCrackX]
    ld [wEntOX + 1], a
    ld a, [wCrackXL + 1]
    ld [wEntOZ], a
    ld a, [wCrackX + 1]
    ld [wEntOZ + 1], a
    xor a
    ld [wEntOY], a
    ld a, [wCrackY]
    ld [wEntOY + 1], a
    ld a, [wCrackFace]
    and 3
    ld e, a
    ld d, 0
    ld hl, CrackYaw
    add hl, de
    ld a, [hl]
    ld [wEntYaw], a
    ld a, [EntBank]
    ld [rROMB0], a
    ld hl, ItemTab + 2 * ITEM_CRACK
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    call EntSetMesh
    jp DrawEntity

CrackYaw:                           ; door_face_rot: local +Z points out of the face (PZ, MZ, PX, MX)
    db 0, 128, 192, 64

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

; A = first of six map fields (x, y, z, sx, sy, sz), C = index -> wBoxX .. wBoxSZ. Keeps C.
LoadBox6::
    ld hl, wBoxX
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

; A = face (FACE_*), wBoxX / Z / SX / SZ -> carry = the eye is on the outward side of its plane
; (A8 check_face_front).
FaceFront:
    cp FACE_PX
    jr nc, .x
    cp FACE_MZ
    jr z, .mz
    ld a, [wBoxZ]                   ; PZ: cam_z >= z + sz
    ld b, a
    ld a, [wBoxSZ]
    add b
    ld b, a
    ld a, [wCamZ + 1]
    cp b
    ccf
    ret
.mz:
    ld a, [wCamZ + 1]               ; MZ: cam_z <= z
    ld b, a
    ld a, [wBoxZ]
    cp b
    ccf
    ret
.x:
    cp FACE_MX
    jr z, .mx
    ld a, [wBoxX]                   ; PX: cam_x >= x + sx
    ld b, a
    ld a, [wBoxSX]
    add b
    ld b, a
    ld a, [wCamX + 1]
    cp b
    ccf
    ret
.mx:
    ld a, [wCamX + 1]               ; MX: cam_x <= x
    ld b, a
    ld a, [wBoxX]
    cp b
    ccf
    ret

; wBox* = the crate -> A = visible face bits (A8 cull_axis: -face when cam < min, +face when
; cam - min >= size; bit 0 -X, 1 +X, 2 -Y, 3 +Y, 4 -Z, 5 +Z).
CrateFaceBits:
    ld d, 0
    ld a, [wCamX + 1]
    ld hl, wBoxX
    ld e, 1
    call .axis
    ld a, [wCamY + 1]
    ld hl, wBoxY
    ld e, 4
    call .axis
    ld a, [wCamZ + 1]
    ld hl, wBoxZ
    ld e, $10
    call .axis
    ld a, d
    ret
.axis:                              ; A = cam, [HL] = min, [HL + 3] = size, E = -face bit
    ld b, a
    ld a, [hl]
    ld c, a
    ld a, b
    cp c
    jr nc, .ge
    ld a, d
    or e
    ld d, a
    ret
.ge:
    sub c
    inc hl
    inc hl
    inc hl
    cp [hl]
    ret c                           ; cam - min < size: inside
    ld a, e
    add a
    or d
    ld d, a
    ret

; Keeps the edges of the mesh just set (wEntEP / wEntNE) that touch a visible face (wTmpFrame) in
; wCullEdges. A8 box_edge_faces order. Z = no edge left.
CullCrateEdges:
    ld a, [wEntEP]
    ld l, a
    ld a, [wEntEP + 1]
    ld h, a
    ld de, wCullEdges
    ld bc, 0                        ; B = edge index, C = kept
.l:
    ld a, b
    push hl
    ld hl, CrateEdgeFaces
    push de
    ld e, a
    ld d, 0
    add hl, de
    pop de
    ld a, [hl]
    pop hl
    ld e, a
    ld a, [wTmpFrame]
    and e
    ld e, a                         ; keep?
    ld a, [hl+]
    ld [wCullTmp], a
    ld a, [hl+]
    ld [wCullTmp + 1], a
    ld a, e
    and a
    jr z, .skip
    push hl
    ld hl, wCullEdges
    ld a, c
    add a
    ld e, a
    ld d, 0
    add hl, de
    ld a, [wCullTmp]
    ld [hl+], a
    ld a, [wCullTmp + 1]
    ld [hl], a
    pop hl
    inc c
.skip:
    inc b
    ld a, b
    cp 12
    jr nz, .l
    ld a, LOW(wCullEdges)
    ld [wEntEP], a
    ld a, HIGH(wCullEdges)
    ld [wEntEP + 1], a
    ld a, c
    ld [wEntNE], a
    and a
    ret

CrateEdgeFaces:
    db $14, $06, $24, $05, $18, $0A, $28, $09, $11, $12, $22, $21

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
    ld [wSplatMs], a                ; no splat
    ld [wLnMode], a                 ; line tests: first-hit mode
    ld [wSplatFresh], a
    ld [wSgAbs], a
    ld [wFxMs], a                   ; A8 init_things / init_rockets: no explosion, no barrel chain
    ld [wFxMs + 1], a
    ld [wBarrelCh], a
    ld [wBarrelCh + 1], a
    push af
    ld a, BANK(ElevInitB)           ; every elevator at its start height, idle
    ld [rROMB0], a
    call ElevInitB
    ld a, [EntBank]                 ; (LoadEnemies reads the entity bank next)
    ld [rROMB0], a
    pop af
    ld [wTrigInside], a             ; A8 level start: no trigger occupied, no unhide timers
    ld [wKeyUseWas], a
    ld [wCrackMs], a                ; A8 level start: no bump mark
    ld [wCrackMs + 1], a
    ld [wCrackFlags], a
    ld [wTrigHurtMs], a
    ld [wTrigHurtMs + 1], a
    ld [wUhHide], a
    ld [wNextLevelReq], a
    ld hl, wUhTag
    ld b, 12
.clrUh:
    ld [hl+], a
    dec b
    jr nz, .clrUh
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
    ld a, [wEmuzCol]
    ld [wStampCol], a
    ld a, [wEmuzY]
    ld [wStampY], a
    ld a, 1                         ; red
    ld [wStampPlane], a
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
    ; fall through

; BC = 24x21 image (3 bytes per row), wStampCol (byte column), wStampY, wStampPlane (0 ink, 1 red): OR it into
; the framebuffer.
StampImage:
    xor a
.colk:
    ld [wEmuzK], a
    push bc
    ld a, [wStampCol]               ; HL = FB + plane + (col + k) * FB_STRIDE + y * 2
    ld e, a
    ld a, [wEmuzK]
    add e
    ld e, a
    ld d, 0
    ld a, [wStampPlane]
    ld hl, FB
    add l
    ld l, a
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
    ld a, [wStampY]
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

; A8 splat_track + stamp_splat: the hit point is re-projected for this frame's camera, the splat image
; (3 distance LODs) stamped at it plus the jitter, byte-snapped, red for a hit, ink for a wall spark.
DrawSplat:
    ld a, [wSplatMs]
    and a
    ret z
    ld hl, wFxOrg                   ; FxView reads wFxOrg: borrow it
    ld b, 6
.sv:
    ld a, [hl+]
    push af
    dec b
    jr nz, .sv
    ld hl, wFxOrg
    ld de, wSplatOrg
    ld b, 6
.cp:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .cp
    call FxView                     ; HL = X, DE = Y, wFxA = Z
    ld a, l
    ld [wShF], a
    ld a, h
    ld [wShF + 1], a
    ld a, e
    ld [wShL], a
    ld a, d
    ld [wShL + 1], a
    ld hl, wFxOrg + 5               ; give wFxOrg back
    ld b, 6
.rs:
    pop af
    ld [hl-], a
    dec b
    jr nz, .rs
    ld a, [wFxA + 1]
    dec a
    cp 127
    ret nc                          ; behind / on the camera
    ld a, [wFxA]
    ld e, a
    ld a, [wFxA + 1]
    ld d, a
    call SetRecip
    ld a, [wShF]
    ld e, a
    ld a, [wShF + 1]
    ld d, a
    call ProjectMul
    ld hl, 64
    add hl, de
    ld a, [wSplatJx]                ; + jitter (signed)
    ld e, a
    add a
    sbc a
    ld d, a
    add hl, de
    bit 7, h
    ret nz
    ld a, h
    and a
    ret nz
    ld a, l
    cp 128
    ret nc
    ld [wTa], a                     ; tip sx
    ld a, [wShL]
    ld e, a
    ld a, [wShL + 1]
    ld d, a
    call ProjectMul
    ld hl, 56
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a
    ld a, [wSplatJy]
    ld e, a
    add a
    sbc a
    ld d, a
    add hl, de
    bit 7, h
    ret nz
    ld a, h
    and a
    ret nz
    ld a, l
    cp VIEW_ROWS * 8
    ret nc
    ld [wTb], a                     ; tip sy
    ; box anchor (A8 stamp_anchor): byte column nearest (sx - EMUZ_OX), clamped; row sy - EMUZ_OY clamped
    ld a, [wTa]
    sub EMUZ_OX - 4
    jr nc, .cx
    xor a
.cx:
    srl a
    srl a
    srl a
    cp VIEW_COLS - 3
    jr c, .cok
    ld a, VIEW_COLS - 3
.cok:
    ld [wStampCol], a
    ld a, [wTb]
    sub EMUZ_OY
    jr nc, .cy
    xor a
.cy:
    cp VIEW_ROWS * 8 - 21
    jr c, .yok
    ld a, VIEW_ROWS * 8 - 21
.yok:
    ld [wStampY], a
    ld a, [wSplatCol]
    cp COL_SPLAT_HIT
    ld a, 0
    jr nz, .pl
    inc a
.pl:
    ld [wStampPlane], a
    ld a, [wFxA + 1]                ; LOD by depth (EMUZ_Z0 / EMUZ_Z1)
    ld b, 0
    cp EMUZ_Z0
    jr c, .lod
    inc b
    cp EMUZ_Z1
    jr c, .lod
    inc b
.lod:
    ld a, b
    add a
    ld e, a
    ld d, 0
    ld hl, SplatPtr
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld b, h
    ld c, l
IF DEF(SMOKE)
    ld hl, wSplatDrawn
    inc [hl]
ENDC
    jp StampImage

; ---- explosion particles (A8 fx.asm start_explosion / draw_explosion) --------------------------------
; FX_N red pixels (the A8 plots ink; Steve wants red) fly out of the blast origin for the explosion's time: pixel = projected origin + the
; projected offset (velocity * t8, t8 = elapsed >> 4), at the origin's depth. The velocities are picked at
; the first draw after the explosion starts, from a random direction on a quarter sphere, flattened by
; how close and how far above the eye the blast is. Entity bank mapped.

; A, B signed -> A = sign * ((|A| * |B|) >> 7)  (A8 smul7).
Smul7E:
    ld c, a
    xor b
    ld d, a                          ; sign in bit 7
    ld a, c
    bit 7, a
    jr z, .a
    cpl
    inc a
.a:
    ld c, a
    ld a, b
    bit 7, a
    jr z, .b
    cpl
    inc a
.b:
    ld b, a
    ld a, c
    push de
    call Mul8u
    pop de
    sla l
    ld a, h
    rla
    bit 7, d
    ret z
    cpl
    inc a
    ret

; Origin -> view space. wFxA = view depth Z (8.8), wFxZ.. returns: HL = X (8.8), DE = Y (8.8), wFxA = Z.
FxView:
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
    ld a, [wCamX]                    ; dx = org - cam (8.8)
    ld b, a
    ld a, [wFxOrg]
    sub b
    ld [wDx], a
    ld a, [wCamX + 1]
    ld b, a
    ld a, [wFxOrg + 1]
    sbc b
    ld [wDx + 1], a
    ld a, [wCamZ]
    ld b, a
    ld a, [wFxOrg + 4]
    sub b
    ld [wDz], a
    ld a, [wCamZ + 1]
    ld b, a
    ld a, [wFxOrg + 5]
    sbc b
    ld [wDz + 1], a
    ld a, [wDx]                      ; Z = dx * sin + dz * cos
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
    ld [wFxA], a
    ld a, [wTa + 1]
    adc d
    ld [wFxA + 1], a
    ld a, [wDx]                      ; X = dx * cos - dz * sin
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
    ld l, a
    ld a, [wTb + 1]
    sbc d
    ld h, a                          ; HL = X
    ld a, [wCamY]                    ; Y = org_y - cam_y
    ld b, a
    ld a, [wFxOrg + 2]
    sub b
    ld e, a
    ld a, [wCamY + 1]
    ld b, a
    ld a, [wFxOrg + 3]
    sbc b
    ld d, a                          ; DE = Y
    ret

; A8 start_explosion: pick wFxVx / wFxVy. Scratch: wShF e1x, wShL counter / sin(theta), wScanAim cos(theta),
; wScanLim sin(phi) / cos(phi), wTb e0x / e1xh.
FxPick:
    call FxView
    ld a, d                          ; CAM_YH: below the eye adds |y| / 2 to the flattening
    ld e, 0
    bit 7, a
    jr z, .ypos
    cpl
    inc a
    srl a
    ld e, a
.ypos:
    ld a, [wFxA + 1]                 ; CAM_ZH: the nearer the blast, the flatter
    bit 7, a
    jr nz, .bias
    cp 32
    jr c, .z
    ld a, 32
.z:
    ld b, a
    ld a, 32
    sub b
    add e
    ld e, a
.bias:
    ld a, e
    cp 65
    jr c, .e1
    ld a, 64
.e1:
    ld [wShF], a                     ; e1x
    xor a
    ld [wShL], a
.p:
    call Rnd
    and $3F                          ; polar angle 0 .. 63
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wShL + 1], a                 ; sin(theta)
    ld a, l
    add 64
    ld l, a
    ld a, [hl]
    ld [wScanAim], a                 ; cos(theta)
    call Rnd
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wScanLim], a                 ; sin(phi)
    ld a, l
    add 64
    ld l, a
    ld a, [hl]
    ld [wScanLim + 1], a             ; cos(phi)
    ld a, [wScanLim + 1]
    ld b, a
    ld a, [wShL + 1]
    call Smul7E
    ld [wTb], a                      ; e0x = sin(theta) * cos(phi)
    ld a, [wScanLim]
    ld b, a
    ld a, [wShL + 1]
    call Smul7E                      ; e0z = sin(theta) * sin(phi)
    bit 7, a
    jr z, .za
    cpl
    inc a
.za:
    ld b, a                          ; |e0z|
    ld a, [wScanAim]
    ld [wTb + 1], a                  ; e1xh = cos(theta)
    ld a, [wShF]
    and a
    jr z, .nob
    ld c, a
    ld a, b
    ld b, c
    call Smul7E                      ; rot2 = |e0z| * e1x
    ld b, a
    ld a, [wTb + 1]
    sub b
    ld [wTb + 1], a                  ; e1xh -= rot2
.nob:
    ld a, [wTb]
    ld b, FX_VEL_SPEED
    call Smul7E
    ld [wTa], a                      ; vx
    ld a, [wTb + 1]
    ld b, FX_VEL_SPEED
    call Smul7E
    ld [wTa + 1], a                  ; vy
    ld a, [wShL]
    ld e, a
    ld d, 0
    ld hl, wFxVx
    add hl, de
    ld a, [wTa]
    ld [hl], a
    ld hl, wFxVy
    add hl, de
    ld a, [wTa + 1]
    ld [hl], a
    ld hl, wShL
    inc [hl]
    ld a, [hl]
    cp FX_N
    jp nz, .p
    ret

; A = signed velocity -> DE = signed (v * t8), t8 in wScanCnt.
VelT8:
    ld b, a
    bit 7, a
    jr z, .p
    cpl
    inc a
.p:
    ld c, a
    ld a, [wScanCnt]
    ld d, b                          ; keep the sign byte
    ld b, a
    ld a, c
    push de
    call Mul8u                       ; HL = |v| * t8
    pop de
    ld a, d
    ld d, h
    ld e, l
    bit 7, a
    ret z
    xor a
    sub e
    ld e, a
    ld a, 0
    sbc d
    ld d, a
    ret

; A8 draw_explosion.
DrawExplosion:
    ld a, [wFxMs]
    ld b, a
    ld a, [wFxMs + 1]
    or b
    ret z
    ld a, [wFxNew]
    and a
    jr z, .have
    xor a
    ld [wFxNew], a
    call FxPick
.have:
    call FxView                      ; HL = X, DE = Y, wFxA = Z (8.8)
    ld a, l
    ld [wShF], a
    ld a, h
    ld [wShF + 1], a
    ld a, e
    ld [wShL], a
    ld a, d
    ld [wShL + 1], a
    ld a, [wFxA + 1]
    dec a
    cp 127
    ret nc                           ; not in front by a cell
    ld a, [wFxA]
    ld e, a
    ld a, [wFxA + 1]
    ld d, a
    call SetRecip
    ld a, [wShF]
    ld e, a
    ld a, [wShF + 1]
    ld d, a
    call ProjectMul
    ld hl, 64
    add hl, de
    ld a, l
    ld [wTa], a
    ld a, h
    ld [wTa + 1], a                  ; root x
    ld a, [wShL]
    ld e, a
    ld a, [wShL + 1]
    ld d, a
    call ProjectMul
    ld hl, 56
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a
    ld a, l
    ld [wTb], a
    ld a, h
    ld [wTb + 1], a                  ; root y
    ld a, [wFxMs]                    ; t8 = (EXPLODE_MS - time left) >> 4
    ld c, a
    ld a, [wFxMs + 1]
    ld b, a
    ld a, LOW(EXPLODE_MS)
    sub c
    ld l, a
    ld a, HIGH(EXPLODE_MS)
    sbc b
    ld h, a
    REPT 4
    srl h
    rr l
    ENDR
    ld a, l
    ld [wScanCnt], a
    xor a
    ld [wScanBest], a                ; particle index
.dp:
    ld a, [wScanBest]
    ld e, a
    ld d, 0
    ld hl, wFxVx
    add hl, de
    ld a, [hl]
    call VelT8
    call ProjectMul
    ld a, [wTa]
    add e
    ld l, a
    ld a, [wTa + 1]
    adc d
    ld h, a
    bit 7, h
    jr nz, .next
    ld a, h
    and a
    jr nz, .next
    ld a, l
    cp 128
    jr nc, .next
    ld [wScanLim], a                 ; x
    ld a, [wScanBest]
    ld e, a
    ld d, 0
    ld hl, wFxVy
    add hl, de
    ld a, [hl]
    call VelT8
    call ProjectMul
    ld a, [wTb]
    sub e
    ld l, a
    ld a, [wTb + 1]
    sbc d
    ld h, a
    bit 7, h
    jr nz, .next
    ld a, h
    and a
    jr nz, .next
    ld a, l
    cp VIEW_ROWS * 8
    jr nc, .next
    ld c, a
    ld a, [wScanLim]
    ld b, a
IF DEF(SMOKE)
    ld hl, wFxPlots
    inc [hl]
ENDC
    call PlotInk
.next:
    ld hl, wScanBest
    inc [hl]
    ld a, [hl]
    cp FX_N
    jr nz, .dp
    ret

; B = x, C = y (inside the viewport): one red pixel (bitplane 1, colour 2 = A8_RED) in the framebuffer.
PlotInk:
    ld a, b
    srl a
    srl a
    srl a
    add a
    add LOW(ColBase)
    ld l, a
    ld h, HIGH(ColBase)
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, c
    add a
    add l
    ld l, a
    jr nc, .c
    inc h
.c:
    inc l                           ; the row's second byte: bitplane 1 (rows are even-aligned)
    ld a, b
    and 7
    ld e, a
    ld a, $80
    inc e
.s:
    dec e
    jr z, .d
    srl a
    jr .s
.d:
    or [hl]
    ld [hl], a
    ret
