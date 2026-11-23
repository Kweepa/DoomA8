; Joypad.

INCLUDE "hw.inc"

SECTION "input", ROM0

; hJoy: bit0 right 1 left 2 up 3 down 4 A 5 B 6 select 7 start (active high).
ReadJoy::
IF DEF(SMOKEDRAW)
    ld a, [wScriptJoy]              ; scripted input
    ldh [hJoy], a
    ret
ENDC
    ld a, $20                       ; select d-pad
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    ld b, a
    ld a, $10                       ; select buttons
    ldh [rP1], a
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    ldh a, [rP1]
    cpl
    and $0F
    swap a
    or b
    ldh [hJoy], a
    ld a, $30
    ldh [rP1], a
    ret
