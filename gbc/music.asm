; Menu music (port of src/a8music.asm). Plays the stream tools/gbc_genmusic.py writes into music.inc: the A8
; menu tune (same SID emulation, pitch grid, envelopes and LZ packing as tools/genpokey.py), columns re-targeted
; to the GB APU: CH1 / CH2 pulse (50 %), CH3 the 32-sample square of gbc/sound.asm, CH4 for whichever voice is
; in noise class.
;
; Stream: LZ tokens into a 4 KB ring (WRAMX bank 3), mask + changed columns per SID tick. A 16-bit phase
; accumulator steps the stream at the tune's 50.12 Hz from the 59.73 Hz menu frame; each channel runs the A8
; per-frame envelope from its (AD, SR) pair; volume = level >> 4, scaled by wEffectsVol as the A8 scales it.
; GB volume: pulses / noise NRx2 (gbvol 12 / 15 as the effects) with a retrigger when it changes or a note
; starts; CH3 NR32 (4 levels). Interrupts are held off while bank 3 is mapped (the ISRs touch bank 1).
;
; Called once per menu frame through the ROM0 stubs MusStart / MusTick / MusStop (gbc/main.asm).

INCLUDE "hw.inc"

IF !DEF(TEST_EXIT) && !DEF(LIVETEST)

DEF rNR11 EQU $FF11
DEF rNR12 EQU $FF12
DEF rNR13 EQU $FF13
DEF rNR14 EQU $FF14
DEF rNR21 EQU $FF16
DEF rNR22 EQU $FF17
DEF rNR23 EQU $FF18
DEF rNR24 EQU $FF19
DEF rNR30 EQU $FF1A
DEF rNR32 EQU $FF1C
DEF rNR33 EQU $FF1D
DEF rNR34 EQU $FF1E
DEF rNR42 EQU $FF21
DEF rNR43 EQU $FF22
DEF rNR44 EQU $FF23

DEF MUS_RING_BANK EQU 3

SECTION "musring", WRAMX[$D000], BANK[3]
wMusRing:    ds 4096

SECTION "musvars", WRAMX, BANK[1]
wMusCol:     ds 8                   ; lo CH1, lo CH2, lo CH3, hi CH1 | hi CH2 << 4, hi CH3, E CH1, E CH2, E CH3
wMusPh:      ds 3                   ; 0 attack, 1 decay / sustain, 2 release
wMusLvl:     ds 3                   ; envelope 0..255
wMusFrac:    ds 3                   ; step fraction
wMusTrig:    ds 3                   ; a note started this frame (gate rising edge)
wMusOut:     ds 3                   ; last NRx2 / NR32 written (0 = off)
wMusNz:      ds 1                   ; last NR42 written (0 = off)
DEF MUS_CLEAR EQU 24                ; wMusCol .. wMusNz
wMusV:       ds 3                   ; volume 0..15 this frame
wMusEn:      ds 1
wMusAc:      ds 2                   ; tick phase accumulator
wMusMask:    ds 1
wMusFlags:   ds 1
wMusMlen:    ds 1
wMusRd:      ds 2                   ; ring read pointer (lo, hi)
wMusWr:      ds 2                   ; ring write pointer
wMusFetch:   ds 2                   ; packed stream pointer
wMusLoop:    ds 2                   ; stream position after LOOPMARK
wMusB1:      ds 1
wMusAd:      ds 1
wMusSr:      ds 1
wMusTgt:     ds 1
wMusStep:    ds 2                   ; steps per frame, 8.8 (lo, hi)
wMusTmp:     ds 1

SECTION "music", ROMX

INCLUDE "music.inc"


; HL = \1 + C (C = channel or column). Clobbers A.
MACRO MIDX
    ld hl, \1
    ld a, l
    add c
    ld l, a
    adc h
    sub l
    ld h, a
ENDM

; APU on (SndInit: both sides, square wave, effect state cleared), every channel silent, stream at its start.
MusStartB::
    call SndInit
    call MusSilence
    ld hl, wMusCol
    ld b, MUS_CLEAR
    xor a
.clr:
    ld [hl+], a
    dec b
    jr nz, .clr
    ld a, 2
    ld [wMusPh], a
    ld [wMusPh + 1], a
    ld [wMusPh + 2], a
    ld a, LOW(MusTokens)
    ld [wMusFetch], a
    ld a, HIGH(MusTokens)
    ld [wMusFetch + 1], a
    call MusReset
    xor a
    ld [wMusAc], a
    ld a, $80                       ; half a frame of slack either way (A8)
    ld [wMusAc + 1], a
    ld a, 1
    ld [wMusEn], a
    ret

MusStopB::
    xor a
    ld [wMusEn], a
MusSilence:
    xor a
    ldh [rNR12], a                  ; volume 0, no envelope: DAC off
    ldh [rNR22], a
    ldh [rNR30], a
    ldh [rNR42], a
    ret

; Ring write position and token state back to a stream (re)start.
MusReset:
    xor a
    ld [wMusFlags], a
    ld [wMusMlen], a
    ld [wMusWr], a
    ld a, HIGH(wMusRing)
    ld [wMusWr + 1], a
    ret

; Once per menu frame (A8 a8_music_tick).
MusTickB::
    ld a, [wMusEn]
    and a
    ret z
    ld hl, wMusAc
    ld a, [hl]
    add LOW(MUS_RATE)
    ld [hl+], a
    ld a, [hl]
    adc HIGH(MUS_RATE)
    ld [hl], a
    call c, MusStep
    ld c, 0
.env:
    call MusEnv
    inc c
    ld a, c
    cp 3
    jr nz, .env
    jp MusOut

; One stream tick: mask + changed columns (A8 mus_tick).
MusStep:
    call MusNext
    ld [wMusMask], a
    ld c, 0
.col:
    ld hl, wMusMask
    srl [hl]
    jr nc, .skip
    call MusNext
    ld b, a
    MIDX wMusCol
    ld a, c
    cp 5
    jr nc, .ev
    ld [hl], b
    jr .skip
.ev:
    ld a, b
    and $7F
    ld [hl], a
    bit 7, b
    jr nz, .att
    bit 6, b
    jr nz, .skip                    ; gate held, no retrigger
    MIDX wMusPh - 5
    ld [hl], 2                      ; gate off: release
    jr .skip
.att:
    MIDX wMusPh - 5
    ld [hl], 0
    MIDX wMusTrig - 5
    ld [hl], 1
.skip:
    inc c
    ld a, c
    cp 8
    jr nz, .col
    ret

; C = channel. One frame of the envelope (A8 mus_env), volume 0..15 into wMusV. Keeps C.
MusEnv:
    MIDX wMusCol + 5
    ld a, [hl]
    and $0F
    add a
    ld e, a
    ld d, 0
    ld hl, MusInst
    add hl, de
    ld a, [hl+]
    ld [wMusAd], a
    ld a, [hl]
    ld [wMusSr], a
    MIDX wMusPh
    ld a, [hl]
    and a
    jr z, .atk
    dec a
    jr z, .dec
    xor a                           ; release to 0
    ld [wMusTgt], a
    ld a, [wMusSr]
    and $0F
    call MusDown
    jr .out
.dec:
    ld a, [wMusSr]                  ; sustain = (sr >> 4) * 17
    and $F0
    ld b, a
    swap a
    or b
    ld [wMusTgt], a
    ld a, [wMusAd]
    and $0F
    call MusDown
    jr .out
.atk:
    ld a, [wMusAd]
    swap a
    and $0F
    call MusSpfGet
    call MusAcc
    ld b, a
    MIDX wMusLvl
    ld a, [hl]
    add b
    jr c, .top
    ld [hl], a
    cp 255
    jr nz, .out
.top:
    ld [hl], 255
    MIDX wMusPh
    ld [hl], 1
.out:
    MIDX wMusLvl
    ld a, [hl]
    swap a
    and $0F
    ld b, a                         ; level >> 4
    ld a, [wEffectsVol]
    and $0F
    cp $0F
    jr z, .full
    inc a                           ; v * (vol + 1) >> 4 (A8)
    ld e, a
    xor a
    ld d, 4
.ml:
    srl e
    jr nc, .mn
    add b
.mn:
    sla b
    dec d
    jr nz, .ml
    swap a
    and $0F
    ld b, a
.full:
    MIDX wMusV
    ld [hl], b
    ret

; A = rate 0..15, C = channel, wMusTgt = floor. Decay / release step (A8 mus_down).
MusDown:
    ld d, a
    ld a, [wMusTgt]
    ld b, a
    MIDX wMusLvl
    ld a, [hl]
    cp b
    ret z
    ret c
    ld a, d
    call MusSpfGet
    MIDX wMusLvl
    ld a, [hl]
    ld d, 0                         ; exponential segments, as the SID counter
    cp $5E
    jr nc, .sh
    inc d
    cp $37
    jr nc, .sh
    inc d
    cp $1B
    jr nc, .sh
    inc d
    cp $0F
    jr nc, .sh
    inc d
    cp $07
    jr nc, .sh
    inc d
.sh:
    ld a, d
    and a
    jr z, .ns
.sl:
    ld hl, wMusStep + 1
    srl [hl]
    dec hl
    rr [hl]
    dec d
    jr nz, .sl
.ns:
    call MusAcc
    ld b, a
    MIDX wMusLvl
    ld a, [hl]
    sub b
    jr c, .tg
    ld b, a
    ld a, [wMusTgt]
    cp b
    jr nc, .tg                      ; below the floor
    ld a, b
    jr .st
.tg:
    ld a, [wMusTgt]
.st:
    ld [hl], a
    ret

; A = rate 0..15 -> wMusStep = steps per frame (8.8).
MusSpfGet:
    add a
    ld e, a
    ld d, 0
    ld hl, MusSpf
    add hl, de
    ld a, [hl+]
    ld [wMusStep], a
    ld a, [hl]
    ld [wMusStep + 1], a
    ret

; frac[C] += step low; A = whole steps (255 on overflow).
MusAcc:
    MIDX wMusFrac
    ld a, [wMusStep]
    add [hl]
    ld [hl], a
    ld a, [wMusStep + 1]
    adc 0
    ret nc
    ld a, 255
    ret

; ---- output ---------------------------------------------------------------------------------------------------

; C = channel 0..2 -> DE = period (D high bits, E low byte).
MusPeriod:
    MIDX wMusCol
    ld e, [hl]
    ld a, c
    cp 2
    jr z, .c3
    ld a, [wMusCol + 3]
    bit 0, c
    jr z, .lo
    swap a
.lo:
    and $07
    ld d, a
    ret
.c3:
    ld a, [wMusCol + 4]
    ld d, a
    ret

; Tone volume of channel C (0 unless class 0 = tone) -> B = 0..15.
MusToneV:
    MIDX wMusCol + 5
    ld a, [hl]
    and $30
    ld b, 0
    ret nz
    MIDX wMusV
    ld b, [hl]
    ret

MusOut:
    ld c, 0
.pulse:
    call MusToneV
    ld e, b
    ld d, 0
    ld hl, MusVolTab
    add hl, de
    ld a, [hl]
    swap a
    ld [wMusTmp], a                 ; NRx2 wanted (0 = off)
    call MusPeriod
    ld a, c
    and a
    ld hl, rNR11
    jr z, .h1
    ld l, LOW(rNR21)
.h1:
    push hl
    MIDX wMusOut
    ld a, [wMusTmp]
    ld b, a
    and a
    jr nz, .on
    ld a, [hl]                      ; off: DAC off once
    and a
    pop hl
    jr z, .pnext
    MIDX wMusOut
    ld [hl], 0
    ld a, c
    and a
    ld hl, rNR12
    jr z, .z1
    ld l, LOW(rNR22)
.z1:
    xor a
    ld [hl], a
    jr .pnext
.on:
    ld a, [hl]
    cp b
    ld [hl], b
    jr nz, .trig
    MIDX wMusTrig
    ld a, [hl]
    and a
    pop hl
    jr nz, .trig2
    inc hl                          ; same volume: period only
    inc hl
    ld [hl], e
    inc hl
    ld [hl], d
    jr .pnext
.trig:
    pop hl
.trig2:
    ld a, $80                       ; duty 50 %
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld [hl], e
    inc hl
    ld a, d
    or $80
    ld [hl], a
.pnext:
    inc c
    ld a, c
    cp 2
    jr nz, .pulse

    ; CH3: NR32 by volume (0, 25, 50, 100 %)
    call MusToneV
    ld e, b
    ld d, 0
    ld hl, MusWaveVol
    add hl, de
    ld b, [hl]
    call MusPeriod
    ld hl, wMusOut + 2
    ld a, b
    and a
    jr nz, .won
    ld a, [hl]
    and a
    jr z, .noise
    ld [hl], 0
    xor a
    ldh [rNR30], a
    jr .noise
.won:
    ld a, [hl]
    ld [hl], b
    and a
    jr z, .wtrig
    cp b
    jr z, .wsame
    ld a, b
    ldh [rNR32], a
.wsame:
    ld a, [wMusTrig + 2]
    and a
    jr nz, .wtrig
    ld a, e
    ldh [rNR33], a
    ld a, d
    ldh [rNR34], a
    jr .noise
.wtrig:
    ld a, $80
    ldh [rNR30], a
    ld a, b
    ldh [rNR32], a
    ld a, e
    ldh [rNR33], a
    ld a, d
    or $80
    ldh [rNR34], a

.noise:
    ; CH4: the first voice in noise class with a volume
    ld c, 0
.nfind:
    MIDX wMusCol + 5
    ld a, [hl]
    and $30
    cp $20
    jr nz, .nnext
    MIDX wMusV
    ld a, [hl]
    and a
    jr nz, .nfound
.nnext:
    inc c
    ld a, c
    cp 3
    jr nz, .nfind
    ld a, [wMusNz]
    and a
    jr z, .done
    xor a
    ld [wMusNz], a
    ldh [rNR42], a
    jr .done
.nfound:
    ld e, a
    ld d, 0
    ld hl, MusVolTab
    add hl, de
    ld a, [hl]
    swap a
    ld b, a                         ; NR42
    MIDX wMusCol
    ld e, [hl]                      ; NR43
    ld a, [wMusNz]
    cp b
    jr nz, .ntrig
    MIDX wMusTrig
    ld a, [hl]
    and a
    jr nz, .ntrig
    ld a, e
    ldh [rNR43], a
    jr .done
.ntrig:
    ld a, b
    ld [wMusNz], a
    ldh [rNR42], a
    ld a, e
    ldh [rNR43], a
    ld a, $80
    ldh [rNR44], a
.done:
    xor a
    ld [wMusTrig], a
    ld [wMusTrig + 1], a
    ld [wMusTrig + 2], a
    ret

MusWaveVol:                         ; volume 0..15 -> NR32 (off, 25 %, 50 %, 100 %)
    db $00, $60, $60, $60, $40, $40, $40, $40, $20, $20, $20, $20, $20, $20, $20, $20

; ---- stream ---------------------------------------------------------------------------------------------------

; Next decoded stream byte in A (A8 mus_next). Keeps BC.
MusNext:
    push bc
.again:
    ld a, [wMusMlen]
    and a
    jr z, .tok
    dec a
    ld [wMusMlen], a
    ld hl, wMusRd                   ; copy from the ring
    ld e, [hl]
    inc hl
    ld d, [hl]
    di
    ld a, MUS_RING_BANK
    ldh [rSVBK], a
    ld a, [de]
    ld c, a
    ld a, 1
    ldh [rSVBK], a
    ei
    inc de
    ld a, d
    and $0F
    or HIGH(wMusRing)
    ld [hl-], a
    ld [hl], e
    ld a, c
    jr .put
.tok:
    ld hl, wMusFlags
    srl [hl]
    jr nz, .bit
    call MusFetch                   ; flag byte, sentinel in bit 7
    scf
    rra
    ld [wMusFlags], a
.bit:
    jr nc, .match
    call MusFetch                   ; literal
    jr .put
.match:
    call MusFetch
    ld c, a                         ; distance low
    call MusFetch
    ld [wMusB1], a
    and $0F
    jr z, .ctl
    cp 15
    jr z, .long
    add 2
    jr .len
.long:
    call MusFetch
    add 17
.len:
    ld [wMusMlen], a
    ld a, [wMusB1]                  ; read pointer = write pointer - distance
    swap a
    and $0F
    ld b, a
    ld hl, wMusWr
    ld a, [hl+]
    sub c
    ld [wMusRd], a
    ld a, [hl]
    sbc b
    and $0F
    or HIGH(wMusRing)
    ld [wMusRd + 1], a
    jr .again
.ctl:
    ld a, c
    and a
    jr nz, .end
    ld a, [wMusFetch]               ; LOOPMARK: the body starts here
    ld [wMusLoop], a
    ld a, [wMusFetch + 1]
    ld [wMusLoop + 1], a
    call MusReset
    jp .again
.end:
    ld a, [wMusLoop]                ; END: back to the body
    ld [wMusFetch], a
    ld a, [wMusLoop + 1]
    ld [wMusFetch + 1], a
    call MusReset
    jp .again
.put:
    ld c, a                         ; A -> ring at the write pointer
    ld hl, wMusWr
    ld e, [hl]
    inc hl
    ld d, [hl]
    di
    ld a, MUS_RING_BANK
    ldh [rSVBK], a
    ld a, c
    ld [de], a
    ld a, 1
    ldh [rSVBK], a
    ei
    inc de
    ld a, d
    and $0F
    or HIGH(wMusRing)
    ld [hl-], a
    ld [hl], e
    ld a, c
    pop bc
    ret

; Next packed byte in A. Clobbers HL.
MusFetch:
    ld hl, wMusFetch
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]
    push af
    ld a, l
    ld [wMusFetch], a
    ld a, h
    ld [wMusFetch + 1], a
    pop af
    ret

ENDC
