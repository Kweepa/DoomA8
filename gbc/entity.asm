; Entity meshes: rotated local meshes (items, enemies, doors, world objects).
; Spec: tools/gbc_entity.py (bit-exact). The caller maps the ROM bank holding the mesh.
;
; Inputs (WRAM): wEntOX/OZ/OY (8.8 world origin), wEntYaw (object yaw), wEntVP (vertex array,
; signed bytes x,y,z), wEntEP (edge array), wEntNV, wEntNE, wEntShift (S: units of 2^-S),
; wEntRadius (world units, view cull). Uses the render pages and DrawEdges of render.asm.

INCLUDE "hw.inc"

MACRO NEG_DE
    xor a
    sub e
    ld e, a
    ld a, 0
    sbc d
    ld d, a
ENDM

SECTION "entity", ROM0

; A = signed byte l, C = signed byte t -> DE = sign * ((|l| * |t|) >> hSh). hSh = S - 1.
SMulSh8:
    ld b, a
    xor c
    ldh [hSign], a
    ld a, b
    bit 7, a
    jr z, .lp
    cpl
    inc a
.lp:
    ld b, a
    bit 7, c
    jr z, .tp
    xor a
    sub c
    ld c, a
.tp:
    ld a, c
    call Mul8u                      ; HL = |t| * |l|
    ldh a, [hSh]
    and a
    jr z, .ns
    ld b, a
.sh:
    srl h
    rr l
    dec b
    jr nz, .sh
.ns:
    ld d, h
    ld e, l
    ldh a, [hSign]
    bit 7, a
    ret z
    NEG_DE
    ret

; Draw one entity instance. Clobbers everything.
DrawEntity::
    ld a, [wEntShift]
    dec a
    ldh [hSh], a                    ; product shift S - 1
    ; camera sin / cos
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
    ; dx = ox - camX, dz = oz - camZ (8.8)
    ld a, [wEntOX]
    ld b, a
    ld a, [wCamX]
    ld c, a
    ld a, b
    sub c
    ld e, a
    ld a, [wEntOX + 1]
    ld b, a
    ld a, [wCamX + 1]
    ld c, a
    ld a, b
    sbc c
    ld d, a
    ld [wEntAX + 1], a
    ld a, e
    ld [wEntAX], a                  ; dx
    ld a, [wEntOZ]
    ld b, a
    ld a, [wCamZ]
    ld c, a
    ld a, b
    sub c
    ld e, a
    ld a, [wEntOZ + 1]
    ld b, a
    ld a, [wCamZ + 1]
    ld c, a
    ld a, b
    sbc c
    ld d, a
    ld a, e
    ld [wEntAZ], a
    ld a, d
    ld [wEntAZ + 1], a              ; dz
    ; X0 = dx*cs - dz*sn
    ld a, [wEntAX]
    ld e, a
    ld a, [wEntAX + 1]
    ld d, a
    ld a, [wCos]
    ld c, a
    call SMul16
    ld a, e
    ld [wEntX0], a
    ld a, d
    ld [wEntX0 + 1], a
    ld a, [wEntAZ]
    ld e, a
    ld a, [wEntAZ + 1]
    ld d, a
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, [wEntX0]
    sub e
    ld [wEntX0], a
    ld a, [wEntX0 + 1]
    sbc d
    ld [wEntX0 + 1], a
    ; Z0 = dx*sn + dz*cs
    ld a, [wEntAX]
    ld e, a
    ld a, [wEntAX + 1]
    ld d, a
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, e
    ld [wEntZ0], a
    ld a, d
    ld [wEntZ0 + 1], a
    ld a, [wEntAZ]
    ld e, a
    ld a, [wEntAZ + 1]
    ld d, a
    ld a, [wCos]
    ld c, a
    call SMul16
    ld a, [wEntZ0]
    add e
    ld [wEntZ0], a
    ld a, [wEntZ0 + 1]
    adc d
    ld [wEntZ0 + 1], a
    ; Y0 = oy - camY
    ld a, [wEntOY]
    ld b, a
    ld a, [wCamY]
    ld c, a
    ld a, b
    sub c
    ld [wEntY0], a
    ld a, [wEntOY + 1]
    ld b, a
    ld a, [wCamY + 1]
    ld c, a
    ld a, b
    sbc c
    ld [wEntY0 + 1], a

    ; cull: zt = Z0 + radius*256; behind (zt < 256) or |X0| > zt -> skip
    ld a, [wEntZ0 + 1]
    ld b, a
    ld a, [wEntRadius]
    add b
    ld d, a                         ; zt high
    ld a, [wEntZ0]
    ld e, a                         ; zt low
    bit 7, d
    ret nz                          ; negative
    ld a, d
    and a
    ret z                           ; zt < 256
    ld a, [wEntX0]
    ld c, a
    ld a, [wEntX0 + 1]
    ld b, a
    bit 7, b
    jr z, .xpos
    xor a
    sub c
    ld c, a
    ld a, 0
    sbc b
    ld b, a
.xpos:
    ld a, e
    sub c
    ld a, d
    sbc b
    ret c                           ; zt < |X0|

    ; object-yaw rotation: psi = camYaw + objYaw
    ld a, [wYaw]
    ld b, a
    ld a, [wEntYaw]
    add b
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wEntSin], a
    ld a, l
    add 64
    ld l, a
    ld a, [hl]
    ld [wEntCos], a
    ; edges are read straight from the mesh (ROM, bank mapped by the caller)
    ld a, [wEntNE]
    ld [wEdgeN], a
    ld a, [wEntEP]
    ld [wEdgePtr], a
    ld a, [wEntEP + 1]
    ld [wEdgePtr + 1], a
    xor a
    ld [wEntI], a
    ld a, [wEntVP]
    ld [wEntCur], a
    ld a, [wEntVP + 1]
    ld [wEntCur + 1], a
.vert:
    ld a, [wEntCur]
    ld l, a
    ld a, [wEntCur + 1]
    ld h, a
    ld a, [hl+]
    ld [wEntLX], a
    ld a, [hl+]
    ld [wEntLY], a
    ld a, [hl+]
    ld [wEntLZ], a
    ld a, l
    ld [wEntCur], a
    ld a, h
    ld [wEntCur + 1], a
    ; X = X0 + lx*cs2 - lz*sn2
    ld a, [wEntLX]
    ld c, a
    ld a, [wEntCos]
    ld b, a
    ld a, c
    ld c, b
    call SMulSh8
    ld a, [wEntX0]
    add e
    ld [wEntX], a
    ld a, [wEntX0 + 1]
    adc d
    ld [wEntX + 1], a
    ld a, [wEntLZ]
    ld b, a
    ld a, [wEntSin]
    ld c, a
    ld a, b
    call SMulSh8
    ld a, [wEntX]
    sub e
    ld [wEntX], a
    ld a, [wEntX + 1]
    sbc d
    ld [wEntX + 1], a
    ; Z = Z0 + lx*sn2 + lz*cs2
    ld a, [wEntSin]
    ld c, a
    ld a, [wEntLX]
    call SMulSh8
    ld a, [wEntZ0]
    add e
    ld [wEntZ], a
    ld a, [wEntZ0 + 1]
    adc d
    ld [wEntZ + 1], a
    ld a, [wEntCos]
    ld c, a
    ld a, [wEntLZ]
    call SMulSh8
    ld a, [wEntZ]
    add e
    ld [wEntZ], a
    ld a, [wEntZ + 1]
    adc d
    ld [wEntZ + 1], a
    ; Y = Y0 + (ly << (8 - S))
    ld a, [wEntLY]
    ld l, a
    ld h, 0
    bit 7, a
    jr z, .ypos
    ld h, $FF
.ypos:
    ld a, [wEntShift]
    ld b, a
    ld a, 8
    sub b
    jr z, .yadd
    ld b, a
.ysh:
    add hl, hl
    dec b
    jr nz, .ysh
.yadd:
    ld a, [wEntY0]
    add l
    ld [wEntY], a
    ld a, [wEntY0 + 1]
    adc h
    ld [wEntY + 1], a
    ; store VX / VY / VZ
    ld a, [wEntI]
    add a
    ld e, a
    ld d, HIGH(wVerts)              ; VX @ 0
    ld a, [wEntX]
    ld [de], a
    inc e
    ld a, [wEntX + 1]
    ld [de], a
    ld a, e
    add 31                          ; VY @ 32: (2i+1) + 31 = 2i + 32
    ld e, a
    ld a, [wEntY]
    ld [de], a
    inc e
    ld a, [wEntY + 1]
    ld [de], a
    ld a, e
    add 31                          ; VZ @ 64
    ld e, a
    ld a, [wEntZ]
    ld [de], a
    inc e
    ld a, [wEntZ + 1]
    ld [de], a
    ; front?  Z >= 256  <=>  1 <= hi <= 127
    ld a, [wEntZ + 1]
    dec a
    cp 127
    jr nc, .rear
    ld a, [wEntI]
    add 160
    ld e, a
    ld a, 1
    ld [de], a                      ; VF
    ld a, [wEntZ]
    ld e, a
    ld a, [wEntZ + 1]
    ld d, a
    call SetRecip
    ld a, [wEntX]
    ld e, a
    ld a, [wEntX + 1]
    ld d, a
    call ProjectMul
    ld hl, 64
    add hl, de                      ; sx
    ld a, [wEntI]
    add a
    add 96
    ld e, a
    ld d, HIGH(wVerts)              ; VSX @ 96
    ld a, l
    ld [de], a
    inc e
    ld a, h
    ld [de], a
    ld a, [wEntY]
    ld e, a
    ld a, [wEntY + 1]
    ld d, a
    call ProjectMul
    ld hl, 56
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a                         ; sy = 56 - py
    ld a, [wEntI]
    add a
    add 128
    ld e, a
    ld d, HIGH(wVerts)              ; VSY @ 128
    ld a, l
    ld [de], a
    inc e
    ld a, h
    ld [de], a
    jr .next
.rear:
    ld a, [wEntI]
    add 160
    ld e, a
    ld d, HIGH(wVerts)
    xor a
    ld [de], a
.next:
    ld a, [wEntI]
    inc a
    ld [wEntI], a
    ld b, a
    ld a, [wEntNV]
    cp b
    jp nz, .vert
    jp DrawEdges

; HL = src, DE = dst, B = byte count (0..255). Clobbers A, B.
EntCopy:
    ld a, b
    and a
    ret z
.l:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .l
    ret
