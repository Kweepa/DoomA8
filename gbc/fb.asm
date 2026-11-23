; Framebuffer helpers (WRAM $C000, 16 columns x 224 B = 3584 B, column-major tiles).

INCLUDE "hw.inc"

SECTION "fb", ROM0

; Zero the framebuffer with the stack trick. Interrupts are left disabled.
ClearFB::
    di
    ld [hSavedSP], sp
    ld sp, FB + FB_SIZE
    ld de, 0
    ld b, FB_SIZE / 16              ; 224 iterations x 16 B
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

; A = destination VRAM bank. The framebuffer is one contiguous run of 224 tiles:
; 128 blocks to $8000 then 96 blocks to $8800. General DMA: LCD off / VBlank only.
CopyFBGeneral::
    ldh [rVBK], a
    ld a, HIGH(FB)
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES)
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, 127                       ; 128 blocks
    ldh [rHDMA5], a
    ld a, HIGH(FB) + 8
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES) + 8
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, VIEW_TILES - 128 - 1      ; 96 blocks
    ldh [rHDMA5], a
    xor a
    ldh [rVBK], a
    ret

; Same as CopyFBGeneral but HBlank DMA (16 B per HBlank), LCD on. The CPU spins
; until each run has landed. A = destination VRAM bank.
CopyFBHBlank::
    ldh [rVBK], a
    ld a, HIGH(FB)
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES)
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, $80 | 127
    ldh [rHDMA5], a
.wait1:
    ldh a, [rHDMA5]
    bit 7, a
    jr z, .wait1
    ld a, HIGH(FB) + 8
    ldh [rHDMA1], a
    xor a
    ldh [rHDMA2], a
    ld a, HIGH(VRAM_TILES) + 8
    ldh [rHDMA3], a
    xor a
    ldh [rHDMA4], a
    ld a, $80 | (VIEW_TILES - 128 - 1)
    ldh [rHDMA5], a
.wait2:
    ldh a, [rHDMA5]
    bit 7, a
    jr z, .wait2
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

; Blank tile (BLANK_TILE) and hex digit tiles (FONT_TILE0 + d), bank 0. LCD off.
InstallFont::
    ld hl, FontTiles
    ld de, VRAM_TILES + BLANK_TILE * 16
    ld bc, FontTilesEnd - FontTiles
.copy:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .copy
    ret

; BG map: viewport cell (x, y) = tile x*14 + y; everything else blank.
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
    ld a, 0                         ; running tile id
.col:
    push hl
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
    ld b, a                         ; keep the id across the compare
    ld a, c
    cp VIEW_COLS
    ld a, b
    jr nz, .col
    ret
