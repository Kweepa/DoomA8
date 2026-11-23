; da8m GBC port - phase 1 spike.
; CGB-only header, MBC5, double speed, 128x112 viewport (16x14 column-major
; tiles) drawn from a WRAM framebuffer. Static line test for now.
;
; Build with -D TEST_EXIT=1 for the headless test ROM (stops on `ld b,b`).

INCLUDE "hw.inc"

SECTION "vblank_vec", ROM0[$0040]
    jp VBlankISR

SECTION "timer_vec", ROM0[$0050]
    jp TimerISR

SECTION "entry", ROM0[$0100]
    nop
    jp Start

SECTION "header", ROM0[$0104]
    ds $0150 - $0104, 0             ; rgbfix writes logo, title, checksums

SECTION "code", ROM0

Start:
    di
    ld sp, $E000                    ; top of WRAMX bank 1

.waitVBlank:
    ldh a, [rLY]
    cp 144
    jr c, .waitVBlank
    xor a
    ldh [rLCDC], a                  ; LCD off (only legal in VBlank)

    ; Double speed. IE/IF clear and joypad lines deselected, then STOP.
    xor a
    ldh [rIF], a
    ldh [rIE], a
    ld a, $30
    ldh [rP1], a
    ld a, 1
    ldh [rKEY1], a
    stop

    ; Hex font -> VRAM bank 1 tiles $8000.
    ld a, 1
    ldh [rVBK], a
    ld hl, FontTiles
    ld de, VRAM_TILES
    ld bc, FontTilesEnd - FontTiles
.copyFont:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .copyFont

    ; Attribute map: clear, then bank 1 for the four debug-readout cells.
    ld hl, VRAM_MAP0
    ld bc, $0400
.clearAttr:
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .clearAttr
    ld a, $08
    ld [VRAM_MAP0 + 32 * 15 + 2], a
    ld [VRAM_MAP0 + 32 * 15 + 3], a
    ld [VRAM_MAP0 + 32 * 16 + 2], a
    ld [VRAM_MAP0 + 32 * 16 + 3], a
    xor a
    ldh [rVBK], a

    call InitViewMap

    ; BG palette 0: dark brown, light, red, white (BGR555).
    ld a, $80                       ; index 0, auto-increment
    ldh [rBCPS], a
    ld hl, BgPalette0
    ld b, 8
.pal:
    ld a, [hl+]
    ldh [rBCPD], a
    dec b
    jr nz, .pal

    xor a
    ldh [rSCX], a
    ldh [rSCY], a
    ldh [hFrame], a
    ldh [hVBlank], a

    ldh a, [rKEY1]
    and $80
    ldh [hSpeed], a

    ; Test scene.
    call ClearFB
    call DrawTestSet
    call CopyFBToVRAM

    ld a, IEF_VBLANK
    ldh [rIE], a
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_BG8000
    ldh [rLCDC], a
    ei

IF DEF(BENCH)
    call RunBench
ENDC

IF DEF(TEST_EXIT)
    ; Let a couple of frames reach the screen before MainLoop, where
    ; tools/gbc_check.py sets a breakpoint (headless BGB exits on it).
    ld b, 3
.testWait:
    halt
    nop
    dec b
    jr nz, .testWait
ENDC

MainLoop:
.wait:
    halt
    nop
    ldh a, [hVBlank]
    and a
    jr z, .wait
    xor a
    ldh [hVBlank], a

    ld hl, VRAM_MAP0 + 32 * 15 + 2
    ldh a, [hFrame]
    call PutHex
    ld hl, VRAM_MAP0 + 32 * 16 + 2
    ldh a, [hSpeed]
    call PutHex
    jr MainLoop

; Draw every line in TestLines. Clobbers all.
DrawTestSet::
    ld hl, TestLines
.next:
    ld a, [hl+]
    cp $FF
    ret z
    ld b, a
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld d, a
    ld a, [hl+]
    ld e, a
    push hl
    call DrawLine
    pop hl
    jr .next

; a = value, hl = dest. Writes two font tiles (digit + 1, bank 1).
PutHex:
    ld b, a
    swap a
    and $0F
    inc a
    ld [hl+], a
    ld a, b
    and $0F
    inc a
    ld [hl], a
    ret

TimerISR:
    push af
    ldh a, [hOver]
    inc a
    ldh [hOver], a
    pop af
    reti

VBlankISR:
    push af
    ld a, 1
    ldh [hVBlank], a
    ldh a, [hFrame]
    inc a
    ldh [hFrame], a
    pop af
    reti

BgPalette0:
    dw %0000110001100100            ; 0: dark brown
    dw %0101101101011100            ; 1: light
    dw %0000100001011000            ; 2: red
    dw %0111111111111111            ; 3: white

INCLUDE "font.inc"
INCLUDE "test_lines.inc"
