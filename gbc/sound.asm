; Sound effects (port of src/playsound.asm). The A8 plays the Doom PC-speaker envelopes on three
; channels: player (ch 0), enemy (ch 1), world (ch 2). Same here, one effect per channel, a higher or
; equal priority preempts, one envelope byte per tick (every frame from the LY 111 STAT interrupt, ~60 Hz; the A8 steps once per
; mid-split raster). The data are the A8's PC-speaker bytes (tools/gbc_gensound.py -> sound.inc);
; the byte is a PC timer divisor, so the pitch is 1193181 / (byte * 60) Hz. Voices: ch 0 -> CH1 pulse,
; ch 1 -> CH2 pulse, ch 2 -> CH3 (32-sample square wave). Every tick is a pure tone at full volume
; (A8 effects_vol $0F); a 0 byte is a gap.
;
; PlaySound is callable from any code (it only stages a request); SndTick runs from StatISR. State is
; in HRAM, so the tick never depends on the WRAM bank.

INCLUDE "hw.inc"
INCLUDE "a8const.inc"

DEF rNR30 EQU $FF1A
DEF rNR50 EQU $FF24
DEF rNR51 EQU $FF25
DEF rNR52 EQU $FF26
DEF rWAVE EQU $FF30
DEF rNR42 EQU $FF21
DEF rNR43 EQU $FF22
DEF rNR44 EQU $FF23

DEF SND_VOL_PULSE EQU $C0           ; NR12 / NR22: initial volume 12, no envelope
DEF SND_VOL_WAVE  EQU $20           ; NR32: 100 %

SECTION "sndhram", HRAM
hSndReq::  ds 3                      ; staged id + 1 per channel (0 none)
hSndRP::   ds 3                      ; priority of the staged one
hSndPri::  ds 3                      ; priority of the running effect (0 idle)
hSndN::    ds 3                      ; ticks in the running effect (0 idle)
hSndIdx::  ds 3                      ; next tick
hSndPL::   ds 3                      ; tick data pointer
hSndPH::   ds 3
hSndOn::   ds 3                      ; 1: channel triggered and audible
hSndTick:: ds 1                      ; tick count (A8 vbi_count): the noise gates
hSawBite:: ds 1                      ; A8 saw_bite: the last chainsaw swing hit (gbc/ai.asm MeleeShot)
hSawRng::  ds 1                      ; A8 saw_rng
hElevMov:: ds 1                      ; a car is moving (gbc/level.asm ElevTick; A8 elev_noise_n)
hNzVol::   ds 1                      ; CH4 running volume (0 off)

SECTION "sound", ROM0

INCLUDE "sndids.inc"
INCLUDE "sound.inc"

IF DEF(TEST_EXIT)
; Test builds keep ROM0 for the code under test: no sound data or driver, the calls do nothing.
SndInit::
SndStopEnemy::
PlaySound::
SndTick::
    ret
ELSE

; HL = &(array + C)
MACRO CHP
    ld hl, \1
    ld a, l
    add c
    ld l, a
ENDM

; Power the APU, route every channel to both sides, load the square wave, clear the state.
SndInit::
    ld a, $80
    ldh [rNR52], a
    ld a, $77
    ldh [rNR50], a
    ld a, $FF
    ldh [rNR51], a
    xor a
    ldh [rNR30], a                   ; DAC off while the wave RAM is written
    ld hl, rWAVE
    ld a, $FF
    ld b, 8
.hi:
    ld [hl+], a
    dec b
    jr nz, .hi
    xor a
    ld b, 8
.lo:
    ld [hl+], a
    dec b
    jr nz, .lo
    ld hl, hSndReq
    ld b, 29
.clr:
    ld [hl+], a
    dec b
    jr nz, .clr
    ret

; Level loads: stop the enemy channel only (A8 stop_streamed_sfx); the world and player effects play on.
SndStopEnemy::
    ld c, 1
    call SndChOff
    ld hl, hSndReq + 1
    xor a
    ld [hl], a                       ; req
    ld hl, hSndPri + 1
    ld [hl], a
    ld hl, hSndN + 1
    ld [hl], a
    ldh [hElevMov], a                ; (the level's cars are gone)
    ret

; C = channel: DAC / volume off, not audible.
SndChOff:
    ld hl, SndDacReg
    ld b, 0
    add hl, bc
    ld a, [hl]
    ld l, a
    ld h, $FF
    xor a
    ld [hl], a
    CHP hSndOn
    xor a
    ld [hl], a
    ret

SndDacReg: db $12, $17, $1A          ; NR12 / NR22 / NR30: zero = DAC off
SndBase:   db $11, $16, $1B          ; NR11 / NR21 / NR31; +1 volume, +2 period low, +3 period high

; A = id -> HL = effect block (N, voice, priority, ticks...).
SndHdr:
    ld l, a
    ld h, 0
    add hl, hl
    ld de, SndTable
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ret

; A = SND_* id. Stages it on the effect's channel unless a higher priority one is already staged.
PlaySound::
    push bc
    push de
    push hl
    ld b, a
    call SndHdr
    inc hl
    ld a, [hl+]
    ld c, a                          ; channel
    ld d, [hl]                       ; priority
    CHP hSndReq
    ld a, [hl]
    and a
    jr z, .set
    push hl
    CHP hSndRP
    ld a, [hl]
    pop hl
    cp d
    jr c, .set
    jr z, .set
    jr .out                          ; the staged one outranks this
.set:
    CHP hSndRP
    ld [hl], d
    CHP hSndReq
    ld a, b
    inc a
    ld [hl], a
.out:
    pop hl
    pop de
    pop bc
    ret

; StatISR: commit staged effects, then one tick per running channel. Clobbers everything.
SndTick::
    ld c, 0
.ch:
    CHP hSndReq
    ld a, [hl]
    and a
    jr z, .step
    ld [hl], 0
    dec a
    call SndHdr
    ld a, [hl+]                      ; N
    ld b, a
    inc hl
    ld a, [hl+]                      ; priority
    ld d, a
    push hl
    CHP hSndPri
    ld a, [hl]
    cp d
    jr nc, .keep                     ; (running outranks: skip; equal preempts below)
.start:
    ld [hl], d
    CHP hSndN
    ld [hl], b
    CHP hSndIdx
    ld [hl], 0
    pop de                           ; tick data
    CHP hSndPL
    ld [hl], e
    CHP hSndPH
    ld [hl], d
    jr .step
.keep:
    jr nz, .drop                     ; running priority > new
    jr .start
.drop:
    pop de
.step:
    CHP hSndN
    ld a, [hl]
    and a
    jp z, .next
    ld b, a
    CHP hSndIdx
    ld a, [hl]
    cp b
    jp nc, .stop
    inc [hl]
    ld d, a
    CHP hSndPL
    ld a, [hl]
    add d
    ld e, a
    CHP hSndPH
    ld a, [hl]
    adc 0
    ld d, a
    ld a, [de]                       ; PC-speaker byte
    and a
    jr z, .gap
    ; period = byte * 105 / 16 (= 131072 / pulse Hz), 1161 at most
    ld e, a
    ld d, 0
    ld h, d
    ld l, e
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                       ; 16 b
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a                          ; 15 b
    ld d, h
    ld e, l
    add hl, hl
    add hl, hl
    add hl, hl                       ; 120 b
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a                          ; 105 b
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ld a, c
    cp 2
    jr nz, .period
    srl h                            ; CH3 plays a 32-sample wave: half the pulse period
    rr l
.period:
    xor a
    sub l
    ld e, a
    ld a, 8
    sbc h
    ld d, a                          ; register value = 2048 - period
    ld b, 0
    ld hl, SndBase
    add hl, bc
    ld a, [hl]
    ld l, a
    ld h, $FF                        ; HL = NRx1
    push hl
    CHP hSndOn
    ld a, [hl]
    ld b, a
    ld [hl], 1
    pop hl
    ld a, b
    and a
    jr nz, .tone
    ld a, c                          ; first tone: DAC / volume on, trigger with the period
    cp 2
    jr nz, .pulse
    ld a, $80
    ldh [rNR30], a
    inc hl
    ld [hl], SND_VOL_WAVE
    jr .trig
.pulse:
    ld a, $80
    ld [hl+], a                      ; duty 50 %
    ld [hl], SND_VOL_PULSE
.trig:
    inc hl
    ld [hl], e
    inc hl
    ld a, d
    or $80
    ld [hl], a
    jp .next
.tone:
    inc hl
    inc hl
    ld [hl], e
    inc hl
    ld [hl], d
    jp .next
.gap:
    push bc
    call SndChOff
    pop bc
    jp .next
.stop:
    push bc
    call SndChOff
    pop bc
    CHP hSndN
    ld [hl], 0
    CHP hSndPri
    ld [hl], 0
.next:
    inc c
    ld a, c
    cp 3
    jp nz, .ch
    jp SndNoise

; CH4 noise filler, once per tick after the channels (A8 a8_noise / a8_saw). Chainsaw out: A held = the
; bite (a hit, pitch re-rolled from the saw LFSR every tick, full volume) or the fire rattle (every other
; tick, vol >> 2); not held = the idle rattle (two on, two off, vol >> 3). Otherwise the elevator rumble
; while a car moves and no world effect is playing. The A8 pitches are POKEY AUDF; NR43 / volumes are
; derived in tools/gbc_gensound.py.
SndNoise:
    ldh a, [hSndTick]
    ld b, a                          ; the tick count before this one (A8: vbi_count - 1)
    inc a
    ldh [hSndTick], a
    ld a, [wWpnCur]
    cp A8_WPN_SAW
    jr nz, .elev
    ld a, [wPadLive]
    and JOY_A
    jr z, .idle
    ldh a, [hSawBite]
    and a
    jr nz, .bite
    ld a, b
    and 1
    jr z, .off
    ld b, NZ_V_FIRE
    ld c, NZ_FIRE
    jr .on
.idle:
    ld a, b
    and 2
    jr z, .off
    ld b, NZ_V_IDLE
    ld c, NZ_IDLE
    jr .on
.bite:
    ldh a, [hSawRng]
    and a
    jr nz, .rng
    ld a, $7B
.rng:
    add a
    jr nc, .tap
    xor NZ_RNG_TAP
.tap:
    ldh [hSawRng], a
    and NZ_BITE_MASK
    ld e, a
    ld d, 0
    ld hl, SndBiteTab
    add hl, de
    ld c, [hl]
    ld b, NZ_V_BITE
    jr .on
.elev:
    ldh a, [hElevMov]
    and a
    jr z, .off
    ldh a, [hSndN + 2]
    and a
    jr nz, .off                      ; a world effect owns the world voice
    ld b, NZ_V_ELEV
    ld c, NZ_ELEV
.on:
    ldh a, [hNzVol]
    cp b
    ld a, c
    ldh [rNR43], a
    ret z                            ; running at this volume: only the pitch moved
    ld a, b
    ldh [hNzVol], a
    swap a
    ldh [rNR42], a
    ld a, $80
    ldh [rNR44], a
    ret
.off:
    ldh a, [hNzVol]
    and a
    ret z
    xor a
    ldh [hNzVol], a
    ldh [rNR42], a
    ret
ENDC
