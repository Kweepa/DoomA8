; Benchmarks for the phase 1 spike (build with -D BENCH=1 via build-gbc.bat bench).
; Results land in wBenchOut as 16-bit LE words after the "BNCH" magic;
; tools/gbc_bench.py reads them out of a BGB state file.
;
; Timer: TAC = clock / 256 (64 M-cycles per tick); hOver counts TIMA overflows.

INCLUDE "hw.inc"

SECTION "bench", ROM0

TimerStart:
    xor a
    ldh [rTAC], a
    ldh [hOver], a
    ldh [rTIMA], a
    ldh [rTMA], a
    ldh a, [rIF]
    and %11111011
    ldh [rIF], a
    ld a, %00000111
    ldh [rTAC], a
    ret

; BC = ticks since TimerStart (hOver:TIMA, consistent read).
TimerRead:
.retry:
    ldh a, [hOver]
    ld b, a
    ldh a, [rTIMA]
    ld c, a
    ldh a, [hOver]
    cp b
    jr nz, .retry
    ret

WaitVBlank:
    xor a
    ldh [hVBlank], a
.w:
    halt
    nop
    ldh a, [hVBlank]
    and a
    jr z, .w
    ret

; BC -> [hl], [hl+1]; hl += 2
StoreBC:
    ld a, c
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ret

RunBench::
    ld hl, wBenchMagic
    ld a, 'B'
    ld [hl+], a
    ld a, 'N'
    ld [hl+], a
    ld a, 'C'
    ld [hl+], a
    ld a, 'H'
    ld [hl+], a
    ld a, IEF_VBLANK | IEF_TIMER
    ldh [rIE], a
    ld hl, wBenchOut

    ; 0: ticks per video frame
    call WaitVBlank
    call TimerStart
    call WaitVBlank
    call TimerRead
    call StoreBC

    ; 1: 10 x test set (74 lines, 4022 px)
    call TimerStart
    ld a, 10
    ldh [hLoop], a
.lines:
    push hl
    call DrawTestSet
    pop hl
    ldh a, [hLoop]
    dec a
    ldh [hLoop], a
    jr nz, .lines
    call TimerRead
    call StoreBC

    ; 2: 50 x ClearFB
    call TimerStart
    ld a, 50
    ldh [hLoop], a
.clears:
    push hl
    call ClearFB
    ei
    pop hl
    ldh a, [hLoop]
    dec a
    ldh [hLoop], a
    jr nz, .clears
    call TimerRead
    call StoreBC

    ; 3: 50 x general DMA of the whole 4 KB (LCD on; timing only)
    call TimerStart
    ld a, 50
    ldh [hLoop], a
.gdma:
    push hl
    call CopyFBToVRAM
    pop hl
    ldh a, [hLoop]
    dec a
    ldh [hLoop], a
    jr nz, .gdma
    call TimerRead
    call StoreBC

    ; 4,5: CPU spin baseline: iterations and ticks over two TIMA overflows.
    ; Loop is inc de / ldh / cp / jr = 10 M-cycles per iteration.
    call TimerStart
    ld de, 0
.spinA:
    inc de
    ldh a, [hOver]
    cp 2
    jr c, .spinA
    push de
    call TimerRead
    pop de
    ld a, e
    ld [hl+], a
    ld a, d
    ld [hl+], a
    call StoreBC

    ; 6,7: two HBlank DMA transfers (2 KB each) while the CPU spins.
    call TimerStart
    ld de, 0
    ld a, FB_HI
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES)
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, $80 | 127
    ldh [rHDMA5], a
.spinB1:
    inc de
    ldh a, [rHDMA5]
    bit 7, a
    jr z, .spinB1
    ld a, FB_HI + $08
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES) + $08
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, $80 | 127
    ldh [rHDMA5], a
.spinB2:
    inc de
    ldh a, [rHDMA5]
    bit 7, a
    jr z, .spinB2
    push de
    call TimerRead
    pop de
    ld a, e
    ld [hl+], a
    ld a, d
    ld [hl+], a
    call StoreBC
    ret
