; Fixed-point math for the renderer. Spec: tools/gbc_room.py (bit-exact).
; Tables (SinTab, RecipTab, SqLo, SqHi) come from room_tables.inc, page aligned.

INCLUDE "hw.inc"

; DE = -DE
MACRO NEG_DE
    xor a
    sub e
    ld e, a
    ld a, 0
    sbc d
    ld d, a
ENDM

SECTION "math", ROM0

; A * B (unsigned) -> HL, via sq[a+b] - sq[|a-b|]. B preserved. Clobbers A, C, D, E.
Mul8u::
    ld c, a
    add b
    ld l, a
    ld a, HIGH(SqLo)
    adc 0
    ld h, a
    ld e, [hl]
    inc h
    inc h
    ld d, [hl]                      ; DE = sq[a+b]
    ld a, c
    sub b
    jr nc, .pos
    cpl
    inc a
.pos:
    ld l, a
    ld h, HIGH(SqLo)
    ld a, e
    sub [hl]
    ld e, a
    inc h
    inc h
    ld a, d
    sbc [hl]
    ld h, a
    ld l, e
    ret

; DE (s16) * C (s8) >> 7, sign-magnitude truncation -> DE. Clobbers all but nothing saved.
SMul16::
    ld a, d
    xor c
    ldh [hSign], a
    bit 7, c
    jr z, .mpos
    xor a
    sub c
    ld c, a
.mpos:
    ld b, c
    bit 7, d
    jr z, .dpos
    NEG_DE
.dpos:
    push de
    ld a, e
    call Mul8u                      ; HL = lo * |m|
    ld a, l
    ldh [hT0], a
    ld a, h
    ldh [hT1], a
    pop de
    ld a, d
    call Mul8u                      ; HL = hi * |m|
    ldh a, [hT1]
    add l
    ld e, a
    ld a, h
    adc 0
    ld d, a                         ; DE = t2:t1
    ldh a, [hT0]
    add a                           ; carry = t0 bit 7
    ld a, e
    adc a
    ld e, a
    ld a, d
    adc a
    ld d, a                         ; DE = (t2:t1:t0) >> 7
    ldh a, [hSign]
    bit 7, a
    ret z
    NEG_DE
    ret

; DE = Z (>= 256). hS = shift s (zn = Z >> s in 128..255), hR = RecipTab[zn - 128].
SetRecip::
    ld c, 0
.l:
    ld a, d
    and a
    jr z, .done
    srl d
    rr e
    inc c
    jr .l
.done:
    ld a, c
    ldh [hS], a
    ld a, e
    add a
    ld l, a
    ld h, HIGH(RecipTab)
    ld a, [hl+]
    ldh [hR], a
    ld a, [hl]
    ldh [hR + 1], a
    ret

; DE (s16) -> DE = sign * ((|DE| * hR) >> (15 + hS)), hS >= 1.
ProjectMul::
    ld a, d
    ldh [hSign], a
    bit 7, d
    jr z, .pos
    NEG_DE
.pos:
    push de
    ldh a, [hR]
    ld b, a
    ld a, e
    call Mul8u                      ; E * Rlo
    ld a, h
    ldh [hT0], a                    ; a_hi
    ldh a, [hR + 1]
    ld b, a
    pop de
    push de
    ld a, e
    call Mul8u                      ; E * Rhi
    ldh a, [hT0]
    add l
    ldh [hT1], a
    ld a, h
    adc 0
    ldh [hT2], a                    ; S = a_hi + b
    ldh a, [hR]
    ld b, a
    pop de
    push de
    ld a, d
    call Mul8u                      ; D * Rlo
    ldh a, [hT1]
    add l
    ldh [hT1], a
    ldh a, [hT2]
    adc h
    ldh [hT2], a                    ; S2 = S + c
    ld a, 0
    adc 0
    ldh [hT3], a                    ; carry out of S2
    ldh a, [hR + 1]
    ld b, a
    pop de
    ld a, d
    call Mul8u                      ; D * Rhi
    ldh a, [hT2]
    add l
    ld e, a
    ldh a, [hT3]
    adc h
    ld d, a                         ; U = (|v| * R) >> 16
    ldh a, [hS]
    dec a
    jr z, .noshift
    ld c, a
.sh:
    srl d
    rr e
    dec c
    jr nz, .sh
.noshift:
    ldh a, [hSign]
    bit 7, a
    ret z
    NEG_DE
    ret

; DE = Y (s16), BC = n (s16), HL = d (s16), |n| <= |d|.
; DE = Y * n / d, n and d shrunk until |d| <= 255 first. Clobbers all.
Lerp16::
    ld a, d
    xor b
    xor h
    ldh [hSign], a
    bit 7, d
    jr z, .ypos
    NEG_DE
.ypos:
    bit 7, b
    jr z, .npos
    xor a
    sub c
    ld c, a
    ld a, 0
    sbc b
    ld b, a
.npos:
    bit 7, h
    jr z, .dpos
    xor a
    sub l
    ld l, a
    ld a, 0
    sbc h
    ld h, a
.dpos:
.shr:
    ld a, h
    and a
    jr z, .shrunk
    srl h
    rr l
    srl b
    rr c
    jr .shr
.shrunk:
    ld a, l
    and a
    jr z, .zero
    ldh [hT3], a                    ; ad
    ld b, c                         ; B = an
    push de
    ld a, e
    call Mul8u
    ld a, l
    ldh [hT0], a
    ld a, h
    ldh [hT1], a
    pop de
    ld a, d
    call Mul8u
    ldh a, [hT1]
    add l
    ldh [hT1], a
    ld a, h
    adc 0
    ldh [hT2], a                    ; N = |Y| * an = t2:t1:t0
    ldh a, [hT0]
    ld e, a
    ldh a, [hT1]
    ld d, a
    ldh a, [hT2]
    ld b, a                         ; running remainder
    ldh a, [hT3]
    ld c, a
    ld h, 16
.div:
    sla e
    rl d
    rl b
    jr c, .sub
    ld a, b
    cp c
    jr c, .nosub
.sub:
    ld a, b
    sub c
    ld b, a
    inc e
.nosub:
    dec h
    jr nz, .div
    ldh a, [hSign]
    bit 7, a
    ret z
    NEG_DE
    ret
.zero:
    ld de, 0
    ret

; B:D:E = 24-bit numerator (B high), C = divisor, quotient must fit 16 bits (B < C).
; DE = floor(N / C). Clobbers A, B, H.
Div24x8::
    ld h, 16
.div:
    sla e
    rl d
    rl b
    jr c, .sub
    ld a, b
    cp c
    jr c, .nosub
.sub:
    ld a, b
    sub c
    ld b, a
    inc e
.nosub:
    dec h
    jr nz, .div
    ret
