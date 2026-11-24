; Joypad. The timer interrupt (TimerISR in main.asm) is the only code that touches P1: every tick it
; stores the pad and adds a tick to each held direction, so movement and turning integrate the time a
; button was down during the frame (as the A8 build does with its 50 Hz IRQ), not a per-frame sample.

INCLUDE "hw.inc"

DEF MAX_HOLD EQU 48                 ; ticks per frame, = the 12 VBlank dt clamp

SECTION "input", ROM0

MACRO SynHold                       ; \1 = hJoy bit in C, B = ticks, HL = dest (advances)
    xor a
    bit \1, c
    jr z, .z\@
    ld a, b
.z\@:
    ld [hl+], a
ENDM

; hJoy: bit0 right 1 left 2 up 3 down 4 A 5 B 6 select 7 start (active high).
; Called once per game frame after wMoveDt is set: hJoy = pad now plus buttons tapped since the last
; frame, and the hold counters move to wHold* (clamped) and restart.
ReadJoy::
IF DEF(SMOKEDRAW)
    ld a, [wScriptJoy]              ; scripted input
    ldh [hJoy], a
    jr HoldsFromJoy
ENDC
    di
    ld a, [wPadLive]
    ld b, a
    ld a, [wPadLatch]
    or b
    ldh [hJoy], a
    xor a
    ld [wPadLatch], a
    ld hl, wAccF
    ld de, wHoldF
    ld c, 6
.cp:
    ld a, [hl]
    cp MAX_HOLD + 1
    jr c, .ok
    ld a, MAX_HOLD
.ok:
    ld [de], a
    inc de
    xor a
    ld [hl+], a
    dec c
    jr nz, .cp
    ei
    ret

; Test / scripted input: hJoy held for the whole of wMoveDt VBlanks (4 ticks each).
HoldsFromJoy::
    ld a, [wMoveDt]
    add a
    add a
    ld b, a
    ldh a, [hJoy]
    ld c, a
    ld hl, wHoldF
    SynHold 2
    SynHold 3
    bit 5, c
    jr nz, .strafe
    SynHold 0
    SynHold 1
    xor a
    ld [hl+], a
    ld [hl], a
    ret
.strafe:
    xor a
    ld [hl+], a
    ld [hl+], a
    SynHold 0
    SynHold 1
    ret
