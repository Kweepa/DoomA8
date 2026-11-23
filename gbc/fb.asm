; Framebuffer helpers (WRAM $C000, 16 columns x 256 B).

INCLUDE "hw.inc"

SECTION "fb", ROM0

; Zero the framebuffer with the stack trick. Interrupts are left disabled.
ClearFB::
    di
    ld [hSavedSP], sp
    ld sp, FB + FB_SIZE
    ld de, 0
    ld b, 0                         ; 256 iterations x 16 B
.loop:
    REPT 8
    push de
    ENDR
    dec b
    jr nz, .loop
    ldh a, [hSavedSP]
    ld l, a
    ldh a, [hSavedSP + 1]
    ld h, a
    ld sp, hl
    ret

; Copy the whole framebuffer to VRAM bank 0 tiles $8000 (general DMA, two
; 2 KB transfers). LCD must be off or in VBlank long enough; the CPU stalls.
CopyFBToVRAM::
    xor a
    ldh [rVBK], a
    ld a, FB_HI
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES)
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, 127                       ; 128 blocks
    ldh [rHDMA5], a
    ld a, FB_HI + $08
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES) + $08
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, 127
    ldh [rHDMA5], a
    ret

; BG map: viewport cell (x, y) = tile x*16 + y; everything else blank.
InitViewMap::
    ld hl, VRAM_MAP0
    ld bc, $0400
    ld d, BLANK_TILE
.fill:
    ld a, d
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .fill
    ld hl, VRAM_MAP0 + VIEW_MAPX
    ld de, 32
    ld c, 0                         ; column
.col:
    push hl
    ld a, c
    swap a                          ; tile id = col * 16
    ld b, VIEW_ROWS
.row:
    ld [hl], a
    inc a
    add hl, de
    dec b
    jr nz, .row
    pop hl
    inc hl
    inc c
    ld a, c
    cp VIEW_COLS
    jr nz, .col
    ret
