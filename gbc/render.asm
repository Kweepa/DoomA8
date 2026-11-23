; Room renderer: rotate, project, near clip, screen clip, draw.
; Spec: tools/gbc_room.py (bit-exact). Scene data: scene.inc.

INCLUDE "hw.inc"

; dst = a - b (16-bit, WRAM addresses)
MACRO SUB16M
    ld a, [\2]
    ld hl, \3
    sub [hl]
    ld [\1], a
    ld a, [\2 + 1]
    inc hl
    sbc [hl]
    ld [\1 + 1], a
ENDM

; dst = a + b (16-bit, WRAM addresses)
MACRO ADD16M
    ld a, [\2]
    ld hl, \3
    add [hl]
    ld [\1], a
    ld a, [\2 + 1]
    inc hl
    adc [hl]
    ld [\1 + 1], a
ENDM

; Unique-coordinate rotation loop.
; \1 = count label, \2 = values label, \3 = cam var, \4 = dest offset (cos), \5 = dest offset (sin)
MACRO ROT_UNIQUES
    xor a
    ld [wI], a
.u\@:
    ld a, [wI]
    ld c, a
    ld b, 0
    ld hl, \2
    add hl, bc
    ld a, [hl]
    ld d, a
    ld e, 0                         ; u * 256
    ld a, [\3]
    ld c, a
    ld a, [\3 + 1]
    ld b, a
    ld a, e
    sub c
    ld e, a
    ld a, d
    sbc b
    ld d, a                         ; d = u*256 - cam
    push de
    ld a, [wCos]
    ld c, a
    call SMul16
    ld a, [wI]
    add a
    add \4
    ld l, a
    ld h, HIGH(wUniq)
    ld [hl], e
    inc l
    ld [hl], d
    pop de
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, [wI]
    add a
    add \5
    ld l, a
    ld h, HIGH(wUniq)
    ld [hl], e
    inc l
    ld [hl], d
    ld a, [wI]
    inc a
    ld [wI], a
    ld hl, \1
    cp [hl]
    jr nz, .u\@
ENDM

SECTION "render", ROM0

; Camera: wCamX, wCamY, wCamZ (8.8), wYaw. Draws into the framebuffer.
RenderScene::
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

    ROT_UNIQUES wSceneNUX, wSceneUX, wCamX, 0, 16
    ROT_UNIQUES wSceneNUZ, wSceneUZ, wCamZ, 32, 48

    ; ---- columns -------------------------------------------------------
    xor a
    ld [wI], a
.col:
    ld a, [wI]
    add a
    ld c, a
    ld b, 0
    ld hl, wSceneCols
    add hl, bc
    ld a, [hl+]
    ld [wXid], a
    ld a, [hl]
    ld [wZid], a
    ; X' = UXC[xid] - UZS[zid]
    ld a, [wXid]
    add a
    ld l, a
    ld h, HIGH(wUniq)
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a
    ld a, [wZid]
    add a
    add 48
    ld l, a
    ld h, HIGH(wUniq)
    ld a, [hl+]
    ld c, a
    ld a, [hl]
    ld b, a
    ld a, e
    sub c
    ld e, a
    ld a, d
    sbc b
    ld d, a
    ld a, [wI]
    add a
    ld l, a
    ld h, HIGH(wCols)               ; CX @ 0
    ld [hl], e
    inc l
    ld [hl], d
    ; Z' = UXS[xid] + UZC[zid]
    ld a, [wXid]
    add a
    add 16
    ld l, a
    ld h, HIGH(wUniq)
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a
    ld a, [wZid]
    add a
    add 32
    ld l, a
    ld h, HIGH(wUniq)
    ld a, [hl+]
    ld c, a
    ld a, [hl]
    ld b, a
    ld a, e
    add c
    ld e, a
    ld a, d
    adc b
    ld d, a
    ld a, [wI]
    add a
    add 32
    ld l, a
    ld h, HIGH(wCols)               ; CZ @ 32
    ld [hl], e
    inc l
    ld [hl], d
    ; front: Z' >= 256  <=>  1 <= hi <= 127
    ld a, d
    dec a
    cp 127
    jr nc, .rear
    ld a, [wI]
    add 144
    ld l, a
    ld h, HIGH(wCols)               ; CF @ 144
    ld [hl], 1
    call SetRecip                   ; DE = Z'
    ld a, [wI]
    add a
    add 96
    ld l, a
    ld h, HIGH(wCols)               ; CR @ 96
    ldh a, [hR]
    ld [hl+], a
    ldh a, [hR + 1]
    ld [hl], a
    ld a, [wI]
    add 128
    ld l, a
    ld h, HIGH(wCols)               ; CS @ 128
    ldh a, [hS]
    ld [hl], a
    ld a, [wI]
    add a
    ld l, a
    ld h, HIGH(wCols)
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a                         ; DE = X'
    call ProjectMul
    ld hl, 64
    add hl, de                      ; sx = 64 + px
    ld a, [wI]
    add a
    add 64
    ld e, a
    ld d, HIGH(wCols)               ; CSX @ 64
    ld a, l
    ld [de], a
    inc e
    ld a, h
    ld [de], a
    jr .colNext
.rear:
    ld a, [wI]
    add 144
    ld l, a
    ld h, HIGH(wCols)
    ld [hl], 0
.colNext:
    ld a, [wI]
    inc a
    ld [wI], a
    ld hl, wSceneNC
    cp [hl]
    jp nz, .col

    ; ---- vertices ------------------------------------------------------
    xor a
    ld [wI], a
.vert:
    ld a, [wI]
    add a
    ld c, a
    ld b, 0
    ld hl, wSceneVerts
    add hl, bc
    ld a, [hl+]
    ld [wXid], a                    ; column
    ld a, [hl]
    ld d, a                         ; y (world)
    ld e, 0
    ld a, [wCamY]
    ld c, a
    ld a, [wCamY + 1]
    ld b, a
    ld a, e
    sub c
    ld e, a
    ld a, d
    sbc b
    ld d, a                         ; Y' = y*256 - camY
    ld a, [wI]
    add a
    add 32
    ld l, a
    ld h, HIGH(wVerts)              ; VY @ 32
    ld [hl], e
    inc l
    ld [hl], d
    ; VX[v] = CX[col]
    ld a, [wXid]
    add a
    ld l, a
    ld h, HIGH(wCols)
    ld a, [hl+]
    ld c, a
    ld a, [hl]
    ld b, a
    ld a, [wI]
    add a
    ld l, a
    ld h, HIGH(wVerts)              ; VX @ 0
    ld [hl], c
    inc l
    ld [hl], b
    ; VZ[v] = CZ[col]
    ld a, [wXid]
    add a
    add 32
    ld l, a
    ld h, HIGH(wCols)
    ld a, [hl+]
    ld c, a
    ld a, [hl]
    ld b, a
    ld a, [wI]
    add a
    add 64
    ld l, a
    ld h, HIGH(wVerts)              ; VZ @ 64
    ld [hl], c
    inc l
    ld [hl], b
    ; VF[v] = CF[col]
    ld a, [wXid]
    add 144
    ld l, a
    ld h, HIGH(wCols)
    ld a, [hl]
    ld c, a
    ld a, [wI]
    add 160
    ld l, a
    ld h, HIGH(wVerts)              ; VF @ 160
    ld [hl], c
    ld a, c
    and a
    jr z, .vertNext
    ; front: hR/hS from the column, py = project(Y'), sy = 56 - py, sx = CSX
    ld a, [wXid]
    add a
    add 96
    ld l, a
    ld h, HIGH(wCols)
    ld a, [hl+]
    ldh [hR], a
    ld a, [hl]
    ldh [hR + 1], a
    ld a, [wXid]
    add 128
    ld l, a
    ld h, HIGH(wCols)
    ld a, [hl]
    ldh [hS], a
    ld a, [wI]
    add a
    add 32
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a                         ; Y'
    call ProjectMul
    ld hl, 56
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a                         ; sy = 56 - py
    ld a, [wI]
    add a
    add 128
    ld e, a
    ld d, HIGH(wVerts)              ; VSY @ 128
    ld a, l
    ld [de], a
    inc e
    ld a, h
    ld [de], a
    ld a, [wXid]
    add a
    add 64
    ld l, a
    ld h, HIGH(wCols)
    ld a, [hl+]
    ld c, a
    ld a, [hl]
    ld b, a                         ; CSX
    ld a, [wI]
    add a
    add 96
    ld l, a
    ld h, HIGH(wVerts)              ; VSX @ 96
    ld [hl], c
    inc l
    ld [hl], b
.vertNext:
    ld a, [wI]
    inc a
    ld [wI], a
    ld hl, wSceneNV
    cp [hl]
    jp nz, .vert

    ld a, [wSceneNE]
    ld [wEdgeN], a
    ld a, LOW(wSceneEdges)
    ld [wEdgePtr], a
    ld a, HIGH(wSceneEdges)
    ld [wEdgePtr + 1], a
    ; fall through

; Near-clip, screen-clip and plot every edge of wScene (NE / Edges) using the vertex arrays
; (wVerts: VX VY VZ VSX VSY VF) already filled by RenderScene or DrawEntity.
DrawEdges::
    xor a
    ld [wI], a
.edge:
    ld a, [wI]
    add a
    ld c, a
    ld b, 0
    ld a, [wEdgePtr]
    ld l, a
    ld a, [wEdgePtr + 1]
    ld h, a
    add hl, bc
    ld a, [hl+]
    ld [wVa], a
    ld a, [hl]
    ld [wVb], a
    ld a, [wVa]
    add 160
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl]
    ld [wFa], a
    ld a, [wVb]
    add 160
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl]
    ld [wFb], a
    ld b, a
    ld a, [wFa]
    or b
    jr z, .edgeNext                 ; both behind
    ld a, [wVa]
    ld [wMe], a
    ld a, [wVb]
    ld [wOth], a
    ld hl, wPts
    call PointFor
    ld a, [wVb]
    ld [wMe], a
    ld a, [wVa]
    ld [wOth], a
    ld hl, wPts + 4
    call PointFor
    call ClipDraw
.edgeNext:
    ld a, [wI]
    inc a
    ld [wI], a
    ld hl, wEdgeN
    cp [hl]
    jp nz, .edge
    ret

; wMe = vertex, wOth = the other end, HL = dest (x, y 16-bit).
; Front vertex: its projected screen point. Behind: clipped to z = 256.
PointFor:
    ld a, h
    ld [wDst + 1], a
    ld a, l
    ld [wDst], a
    ld a, [wMe]
    add 160
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl]
    and a
    jr z, NearClipPt
    ; front: copy VSX, VSY
    ld a, [wMe]
    add a
    add 96
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl+]
    ld c, a
    ld a, [hl]
    ld b, a                         ; VSX
    ld a, [wMe]
    add a
    add 128
    ld l, a
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a                         ; VSY
    ld a, [wDst]
    ld l, a
    ld a, [wDst + 1]
    ld h, a
    ld a, c
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld [hl], d
    ret

; DE = 16-bit field of a vertex. A = index, C = field offset.
GetV:
    add a
    add c
    ld l, a
    ld h, HIGH(wVerts)
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld d, a
    ret

NearClipPt:
    ; n = 256 - VZ[me]
    ld a, [wMe]
    ld c, 64
    call GetV                       ; DE = VZ[me]
    ld a, 0
    sub e
    ld [wTa], a
    ld a, 1
    sbc d
    ld [wTa + 1], a
    ; d = VZ[oth] - VZ[me]
    ld a, [wOth]
    ld c, 64
    call GetV                       ; DE = VZ[oth]
    ld a, [wMe]
    ld c, 64
    call GetV2                      ; HL = VZ[me]; DE kept
    ld a, e
    sub l
    ld [wTb], a
    ld a, d
    sbc h
    ld [wTb + 1], a
    ; X = VX[me] + Lerp(VX[oth] - VX[me], n, d)
    ld a, [wOth]
    ld c, 0
    call GetV
    ld a, [wMe]
    ld c, 0
    call GetV2
    ld a, e
    sub l
    ld e, a
    ld a, d
    sbc h
    ld d, a                         ; DE = dX
    call LerpTemps                  ; DE = r
    ld a, [wMe]
    ld c, 0
    call GetV2                      ; HL = VX[me]
    add hl, de
    ld a, l
    ld [wTx], a
    ld a, h
    ld [wTx + 1], a
    ; Y
    ld a, [wOth]
    ld c, 32
    call GetV
    ld a, [wMe]
    ld c, 32
    call GetV2
    ld a, e
    sub l
    ld e, a
    ld a, d
    sbc h
    ld d, a
    call LerpTemps
    ld a, [wMe]
    ld c, 32
    call GetV2
    add hl, de
    ld a, l
    ld [wTy], a
    ld a, h
    ld [wTy + 1], a
    ; sx = 64 + (X * 40 >> 7)
    ld a, [wTx]
    ld e, a
    ld a, [wTx + 1]
    ld d, a
    ld c, FOCAL_HALF
    call SMul16
    ld hl, 64
    add hl, de
    ld a, [wDst]
    ld e, a
    ld a, [wDst + 1]
    ld d, a
    ld a, l
    ld [de], a
    inc de
    ld a, h
    ld [de], a
    inc de
    push de
    ; sy = 56 - (Y * 40 >> 7)
    ld a, [wTy]
    ld e, a
    ld a, [wTy + 1]
    ld d, a
    ld c, FOCAL_HALF
    call SMul16
    ld hl, 56
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a
    pop de
    ld a, l
    ld [de], a
    inc de
    ld a, h
    ld [de], a
    ret

; HL = 16-bit field of a vertex (DE preserved). A = index, C = field offset.
GetV2:
    add a
    add c
    ld l, a
    push de
    ld h, HIGH(wVerts)
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    ld h, a
    ld l, e
    pop de
    ret

; DE = Y, wTa = n, wTb = d  ->  DE = Lerp16(Y, n, d)
LerpTemps:
    ld a, [wTa]
    ld c, a
    ld a, [wTa + 1]
    ld b, a
    ld a, [wTb]
    ld l, a
    ld a, [wTb + 1]
    ld h, a
    jp Lerp16

; ---- screen clip ---------------------------------------------------------

; HL -> x (16-bit), y (16-bit). A = outcode: 1 left, 2 right, 4 top, 8 bottom.
Outcode:
    ld b, 0
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    bit 7, a
    jr z, .xnn
    ld b, 1
    jr .xdone
.xnn:
    and a
    jr nz, .xright
    ld a, e
    cp 128
    jr c, .xdone
.xright:
    ld b, 2
.xdone:
    ld a, [hl+]
    ld e, a
    ld a, [hl]
    bit 7, a
    jr z, .ynn
    ld a, b
    or 4
    ld b, a
    jr .ydone
.ynn:
    and a
    jr nz, .ybot
    ld a, e
    cp 112
    jr c, .ydone
.ybot:
    ld a, b
    or 8
    ld b, a
.ydone:
    ld a, b
    ret

SwapPts:
    ld hl, wPts
    ld de, wPts + 4
    ld b, 4
.l:
    ld a, [de]
    ld c, [hl]
    ld [hl+], a
    ld a, c
    ld [de], a
    inc de
    dec b
    jr nz, .l
    ret

; Clip P (wPts+0) against x = DE: new y by lerp.
ClipAxisX:
    ld a, e
    ld [wBnd], a
    ld a, d
    ld [wBnd + 1], a
    SUB16M wTa, wBnd, wPts + 0
    SUB16M wTb, wPts + 4, wPts + 0
    SUB16M wTc, wPts + 6, wPts + 2
    ld a, [wTc]
    ld e, a
    ld a, [wTc + 1]
    ld d, a
    call LerpTemps
    ld a, e
    ld [wTc], a
    ld a, d
    ld [wTc + 1], a
    ADD16M wPts + 2, wPts + 2, wTc
    ld a, [wBnd]
    ld [wPts + 0], a
    ld a, [wBnd + 1]
    ld [wPts + 1], a
    ret

; Clip P against y = DE: new x by lerp.
ClipAxisY:
    ld a, e
    ld [wBnd], a
    ld a, d
    ld [wBnd + 1], a
    SUB16M wTa, wBnd, wPts + 2
    SUB16M wTb, wPts + 6, wPts + 2
    SUB16M wTc, wPts + 4, wPts + 0
    ld a, [wTc]
    ld e, a
    ld a, [wTc + 1]
    ld d, a
    call LerpTemps
    ld a, e
    ld [wTc], a
    ld a, d
    ld [wTc + 1], a
    ADD16M wPts + 0, wPts + 0, wTc
    ld a, [wBnd]
    ld [wPts + 2], a
    ld a, [wBnd + 1]
    ld [wPts + 3], a
    ret

; wPts = x0 y0 x1 y1 (16-bit). 16-bit Cohen-Sutherland, then DrawLine.
ClipDraw:
    ld a, 8
    ld [wGuard], a
.iter:
    ld hl, wPts
    call Outcode
    ld [wOc0], a
    ld hl, wPts + 4
    call Outcode
    ld [wOc1], a
    ld b, a
    ld a, [wOc0]
    ld c, a
    or b
    jr z, .draw
    ld a, c
    and b
    ret nz
    ld a, c
    and a
    jr nz, .pOut
    call SwapPts
    ld a, [wOc1]
    ld c, a
.pOut:
    bit 0, c
    jr nz, .left
    bit 1, c
    jr nz, .right
    bit 2, c
    jr nz, .top
    ld de, 111
    call ClipAxisY
    jr .next
.left:
    ld de, 0
    call ClipAxisX
    jr .next
.right:
    ld de, 127
    call ClipAxisX
    jr .next
.top:
    ld de, 0
    call ClipAxisY
.next:
    ld a, [wGuard]
    dec a
    ld [wGuard], a
    jr nz, .iter
    ret
.draw:
    ld a, [wPts + 0]
    ld b, a
    ld a, [wPts + 2]
    ld c, a
    ld a, [wPts + 4]
    ld d, a
    ld a, [wPts + 6]
    ld e, a
    jp DrawLine
