; Framebuffer helpers (WRAM $C000, 16 columns x 256 B; 224 B of each are pixels).

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

; Whole 4 KB framebuffer -> VRAM bank 0 $8000 in two 2 KB general DMAs (bench only).
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

; A = destination VRAM bank. 16 general DMAs of 14 blocks (the 224 pixel bytes of
; each column); the pad slots in VRAM are left alone. LCD off / VBlank only.
CopyFBGeneral::
    ldh [rVBK], a
    ld c, 0
.col:
    ld a, FB_HI
    add c
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES)
    add c
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, VIEW_ROWS - 1             ; 14 blocks, general purpose
    ldh [rHDMA5], a
    inc c
    ld a, c
    cp VIEW_COLS
    jr nz, .col
    xor a
    ldh [rVBK], a
    ret

; Same as CopyFBGeneral but HBlank DMA (16 B per HBlank), LCD on. The CPU spins
; until each column has landed. A = destination VRAM bank.
CopyFBHBlank::
    ldh [rVBK], a
    ld c, 0
.col:
    ld a, FB_HI
    add c
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES)
    add c
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, $80 | (VIEW_ROWS - 1)
    ldh [rHDMA5], a
.wait:
    ldh a, [rHDMA5]
    bit 7, a
    jr z, .wait
    inc c
    ld a, c
    cp VIEW_COLS
    jr nz, .col
    xor a
    ldh [rVBK], a
    ret

; A = bank (0/1) to display: rewrite the viewport cells' attribute bank bit.
; Call in VBlank (about 530 M-cycles).
ShowBank::
    and 1
    add a
    add a
    add a
    ld c, a
    ld a, 1
    ldh [rVBK], a
    ld a, c
    ld hl, VRAM_MAP0 + VIEW_MAPX
    ld de, 32 - VIEW_COLS
    ld b, VIEW_ROWS
.row:
    REPT VIEW_COLS
    ld [hl+], a
    ENDR
    add hl, de
    dec b
    jr nz, .row
    xor a
    ldh [rVBK], a
    ret

; Fill 8 KB of the current VRAM bank with zero. LCD must be off.
ClearVRAMBank::
    ld hl, VRAM_TILES
    ld bc, $2000
.l:
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .l
    ret

; Hex digit tiles: digit d goes to tile id d*16 + 15 (the free pad slot of
; column d), bank 0. LCD off.
InstallFont::
    ld hl, FontTiles + 16           ; skip the blank tile 0
    ld de, VRAM_TILES + 240
    ld c, 16
.glyph:
    ld b, 16
.byte:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .byte
    push hl
    ld hl, 240
    add hl, de
    ld d, h
    ld e, l
    pop hl
    dec c
    jr nz, .glyph
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
