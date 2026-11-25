; Main menu (port of src/menu.asm run_menu / menu_select / menu_esc / draw_menu / show_text_screen).
; Logo (128x64, tools/gbc_genmenu.py) on tile rows 0-7, options below on a black screen, skull cursor as OAM,
; menu music (gbc/music.asm) for as long as the menu runs. The A8 tree without Quit and Mouse:
;   main: New game, Options, Controls, Read this!, Credits
;   New game -> episode (E1 -> skill, E2 / E3 -> the order pages) -> skill (starts on Hurt me plenty)
;   Options: Volume 0..15 (left / right, wraps as A8 vol_fx_inc / dec)
; Pad: up / down move (wrap), A / Start select, B back (A8 Esc). Text pages: any button turns the page.
; After E1M8 (wGameDone) the ending pages come first, as A8 run_menu does with game_complete.
;
; MenuRunB is entered from gbc/main.asm with the LCD off and interrupts off; it returns the same way with the
; skill in wDifficulty. While it runs: VBlank + timer interrupts (input sampling), no STAT interrupt, BG tiles at
; $8000. VRAM: bank 0 logo tiles 0.., font 128..223 as colour 1 (yellow); bank 1 font 128..223 as colour 2
; (white, the selected row) and the skull OBJ tiles 0..47. Every text tile uses BG palette 7.

INCLUDE "hw.inc"

IF !DEF(TEST_EXIT) && !DEF(LIVETEST)

DEF MENU_LCDC   EQU LCDCF_ON | LCDCF_BGON | LCDCF_BG8000 | LCDCF_OBJON | LCDCF_OBJ16
DEF ATTR_TEXT   EQU 7                ; palette 7, VRAM bank 0
DEF ATTR_HILITE EQU 7 | 8            ; palette 7, VRAM bank 1 (white copy of the font)
DEF BLANK       EQU 128              ; font tile for ' ': colour 0 = black
DEF SKULL_BLINK EQU 24               ; VBlanks per skull frame (A8: 20 VBIs at 50 Hz, SquareDoom CURSOR_TICK_MAX)
DEF SKULL_SPR   EQU 12               ; 2 layers x 3 columns x 2 rows of 8x16
DEF OAM_BASE    EQU $FE00
DEF PAD_ANY     EQU JOY_A | JOY_B | JOY_SELECT | JOY_START

; next_menu codes (A8 NM_*); 0..3 = a menu id
DEF NM_BACK     EQU $F0
DEF NM_START    EQU $F1
DEF NM_ORDER    EQU $F2
DEF NM_CTRL     EQU $F3
DEF NM_HELP     EQU $F4
DEF NM_CREDITS  EQU $F5

SECTION "menuvars", WRAMX, BANK[1]
wMenuId:      ds 1
wMenuItem:    ds 1
wMenuPrev:    ds 1
wMenuSize:    ds 1
wMenuTextCol: ds 1
wMenuSkullX:  ds 1                   ; OAM x of the skull's left edge
wMenuRow0:    ds 1                   ; tile row of item 0
wMenuLens:    ds 8                   ; label length per item (attribute rows)
wMenuStackD:  ds 1
wMenuStkM:    ds 4
wMenuStkI:    ds 4
wMenuPadPrev: ds 1
wMenuPressed: ds 1
wMenuFrame:   ds 1                   ; skull frame 0 closed / 1 eyes
wMenuTick:    ds 1
wMenuSkullOn: ds 1
wMenuSelDirty: ds 1                  ; selection moved: rewrite two attribute rows at the next VBlank
wMenuVolDirty: ds 1                  ; volume changed: rewrite its digits at the next VBlank
wMenuPage:    ds 1
wMenuPages:   ds 1
wMenuText:    ds 2                   ; page table of the text being shown

SECTION "menu", ROMX

; HL = \1 + A. Clobbers A.
MACRO ADDA
    add LOW(\1)
    ld l, a
    adc HIGH(\1)
    sub l
    ld h, a
ENDM

MenuRunB::
    xor a
    ld [wApOk], a                   ; VBlankISR's WpnTick stays out of OAM
    ldh [hCard], a
    ldh [rSCX], a
    ldh [rSCY], a
    ld [wMenuId], a
    ld [wMenuItem], a
    ld [wMenuStackD], a
    ld [wMenuFrame], a
    ld [wMenuTick], a
    ld [wMenuSelDirty], a
    ld [wMenuVolDirty], a
    inc a
    ld [wMenuSkullOn], a
    call MenuVideoInit
    xor a                           ; input sampling as in Start (TimerISR -> wPadLive)
    ld [wPadLive], a
    ld a, 256 - INPUT_DIV
    ldh [rTMA], a
    ldh [rTIMA], a
    ld a, %100
    ldh [rTAC], a
    xor a
    ldh [rIF], a
    ld a, IEF_VBLANK | IEF_TIMER
    ldh [rIE], a
    ei
    call MusStart
    ld a, [wGameDone]
    and a
    jr z, .menu
    xor a
    ld [wGameDone], a
    ld hl, TextEnding               ; A8 run_menu: show_ending_pages before the menu
    call MenuPages
.menu:
    call MenuDraw
.loop:
    call MenuFrame
    ld a, [wMenuPressed]
    and a
    jr z, .loop
    bit 2, a                        ; JOY_UP
    call nz, MenuUp
    ld a, [wMenuPressed]
    bit 3, a                        ; JOY_DOWN
    call nz, MenuDown
    ld a, [wMenuId]
    cp MENU_VOL_MENU
    call z, MenuVolInput
    ld a, [wMenuPressed]
    and JOY_B
    call nz, MenuEsc
    ld a, [wMenuPressed]
    and JOY_A | JOY_START
    jr z, .loop
    call MenuSelect
    jr nc, .loop
    ; skill chosen: music off, screen off, OAM clear, no stale presses for the game
    call MusStop
    call MenuLcdOff
    call MenuOamClear
    xor a
    ld [wPadLatch], a
    di
    ret

; ---- per frame ---------------------------------------------------------------------------------------------

; VBlank: skull OAM, pending selection / volume tiles; then music, skull blink, pad edges.
MenuFrame:
    call WaitVBlank
    call MenuSkullOam
    ld a, [wMenuSelDirty]
    and a
    call nz, MenuSelAttr
    ld a, [wMenuVolDirty]
    and a
    call nz, MenuVolDigits
    call MusTick
    ld hl, wMenuTick
    inc [hl]
    ld a, [hl]
    cp SKULL_BLINK
    jr c, .pad
    ld [hl], 0
    ld hl, wMenuFrame
    ld a, [hl]
    xor 1
    ld [hl], a
.pad:
    ld a, [wPadLive]
    ld b, a
    ld a, [wMenuPadPrev]
    cpl
    and b
    ld [wMenuPressed], a
    ld a, b
    ld [wMenuPadPrev], a
    ret

; 12 OAM entries: layer (OBJ palette 0 / 1, VRAM bank 1), row, column; hidden while wMenuSkullOn = 0.
MenuSkullOam:
    ld hl, OAM_BASE
    ld a, [wMenuSkullOn]
    and a
    jr nz, .on
    ld b, SKULL_SPR
.hide:
    ld [hl+], a
    inc l
    inc l
    inc l
    dec b
    jr nz, .hide
    ret
.on:
    ld a, [wMenuItem]               ; y = (row0 + 2 item) * 8 - 6, OAM + 16
    add a
    ld b, a
    ld a, [wMenuRow0]
    add b
    add a
    add a
    add a
    add 16 - 6
    ld d, a
    ld a, [wMenuSkullX]
    ld e, a
    ld a, [wMenuFrame]
    add a
    add a
    add a
    ld b, a
    add a
    add b                           ; frame * 24 = first tile of the frame
    ld c, a
    ld b, 0                         ; layer
.layer:
    push de
    ld a, 2
.row:
    push af
    push de
    ld a, 3
.col:
    push af
    ld a, d
    ld [hl+], a
    ld a, e
    ld [hl+], a
    add 8
    ld e, a
    ld a, c
    ld [hl+], a
    add 2
    ld c, a
    ld a, b
    or 8                            ; OBJ palette = layer, tiles in VRAM bank 1
    ld [hl+], a
    pop af
    dec a
    jr nz, .col
    pop de
    ld a, d
    add 16
    ld d, a
    pop af
    dec a
    jr nz, .row
    pop de
    inc b
    ld a, b
    cp 2
    jr nz, .layer
    ret

MenuOamClear:
    ld hl, OAM_BASE
    ld b, 160
    xor a
.c:
    ld [hl+], a
    dec b
    jr nz, .c
    ret

; ---- input -------------------------------------------------------------------------------------------------

MenuUp:
    ld a, [wMenuItem]
    ld [wMenuPrev], a
    and a
    jr nz, .dec
    ld a, [wMenuSize]
.dec:
    dec a
    jr MenuSetItem

MenuDown:
    ld a, [wMenuItem]
    ld [wMenuPrev], a
    inc a
    ld hl, wMenuSize
    cp [hl]
    jr c, MenuSetItem
    xor a
MenuSetItem:
    ld [wMenuItem], a
    ld a, 1
    ld [wMenuSelDirty], a
    ret

; A8 menu_vol_input: left / right on the volume row, 0..15 wrapping.
MenuVolInput:
    ld a, [wMenuItem]
    cp MENU_VOL_ITEM
    ret nz
    ld a, [wMenuPressed]
    ld b, a
    ld a, [wEffectsVol]
    bit 0, b                        ; JOY_RIGHT
    jr z, .l
    inc a
.l:
    bit 1, b                        ; JOY_LEFT
    jr z, .st
    dec a
.st:
    and $0F
    ld [wEffectsVol], a
    ld a, 1
    ld [wMenuVolDirty], a
    ret

; A8 menu_esc: pop the menu stack.
MenuEsc:
    ld a, [wMenuStackD]
    and a
    ret z
    dec a
    ld [wMenuStackD], a
    ld c, a
    ld b, 0
    ld hl, wMenuStkM
    add hl, bc
    ld a, [hl]
    ld [wMenuId], a
    ld hl, wMenuStkI
    add hl, bc
    ld a, [hl]
    ld [wMenuItem], a
    jp MenuDraw

; A8 menu_select. Carry set = start the game (skill in wDifficulty).
MenuSelect:
    ld a, [wMenuId]
    add a
    add a
    add a
    ld b, a
    ld a, [wMenuItem]
    add b
    ADDA MenuNext
    ld a, [hl]
    cp NM_BACK
    jr nz, .nb
    call MenuEsc
    and a
    ret
.nb:
    cp NM_START
    jr nz, .ns
    ld a, [wMenuItem]
    ld [wDifficulty], a
    scf
    ret
.ns:
    cp NM_ORDER
    ld hl, TextOrder
    jr z, .pages
    cp NM_CTRL
    ld hl, TextControls
    jr z, .pages
    cp NM_HELP
    ld hl, TextReadthis
    jr z, .pages
    cp NM_CREDITS
    ld hl, TextCredits
    jr z, .pages
    ld hl, wMenuId                  ; a menu id
    cp [hl]
    ret z                           ; same menu (the volume row): nothing (carry clear: z => nc here)
    ld c, a
    ld a, [wMenuStackD]             ; push
    ld e, a
    ld d, 0
    inc a
    ld [wMenuStackD], a
    ld hl, wMenuStkM
    add hl, de
    ld a, [wMenuId]
    ld [hl], a
    ld hl, wMenuStkI
    add hl, de
    ld a, [wMenuItem]
    ld [hl], a
    ld a, c
    ld [wMenuId], a
    cp 2                            ; skill: cursor starts on Hurt me plenty
    ld a, 0
    jr nz, .it
    inc a
.it:
    ld [wMenuItem], a
    call MenuDraw
    and a
    ret
.pages:
    call MenuPages
    call MenuDraw
    and a
    ret

; menu id * 8 + item (A8 next_menu without Quit / Mouse / Jukebox)
MenuNext:
    db 1, 3, NM_CTRL, NM_HELP, NM_CREDITS, 0, 0, 0
    db 2, NM_ORDER, NM_ORDER, 0, 0, 0, 0, 0
    db NM_START, NM_START, NM_START, 0, 0, 0, 0, 0
    db 3, 0, 0, 0, 0, 0, 0, 0
ASSERT MENU_COUNT == 4

; ---- drawing -----------------------------------------------------------------------------------------------

MenuLcdOff:
    ldh a, [rLCDC]
    and LCDCF_ON
    ret z                           ; already off (LY would never reach VBlank)
.w:
    ldh a, [rLY]
    cp 144
    jr c, .w
    ldh a, [rLCDC]
    and $FF - LCDCF_ON
    ldh [rLCDC], a
    ret

MenuLcdOn:
    ld a, MENU_LCDC
    ldh [rLCDC], a
    ret

; Rows 8..17 to blank tiles / text attributes (LCD off).
MenuClearLower:
    ld hl, $9800 + MENU_ROW0 * 32
    ld bc, 10 * 32
.t:
    ld a, BLANK
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .t
    ld a, 1
    ldh [rVBK], a
    ld hl, $9800 + MENU_ROW0 * 32
    ld bc, 10 * 32
.a:
    ld a, ATTR_TEXT
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .a
    xor a
    ldh [rVBK], a
    ret

; HL = source (len, tiles...), DE = map address, A = attribute. Writes the tiles (bank 0) and the attribute
; (bank 1); returns HL past the string, B = length. LCD off or VBlank.
MenuPut:
    ld c, a
    ld a, [hl+]
    ld b, a
    and a
    ret z
    push de
    push bc
.t:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .t
    pop bc
    pop de
    ld a, 1
    ldh [rVBK], a
    push bc
.a:
    ld a, c
    ld [de], a
    inc de
    dec b
    jr nz, .a
    pop bc
    xor a
    ldh [rVBK], a
    ret

; DE = row * 32 + col for row A, column [wMenuTextCol] (BG map address).
MenuRowAddr:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, [wMenuTextCol]
    add l
    ld e, a
    ld a, h
    adc HIGH($9800)
    ld d, a
    ret

; A8 draw_menu: blank, title, items, skull, unblank.
MenuDraw:
    call MenuLcdOff
    call MenuClearLower
    ld a, [wMenuId]
    add a
    ADDA MenuDefs
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]
    ld [wMenuSize], a
    ld a, [hl+]
    ld [wMenuTextCol], a
    ld a, [hl+]
    ld [wMenuSkullX], a
    ld a, [hl+]
    ld [wMenuRow0], a
    ld a, [hl+]                     ; title row (0 = none)
    and a
    jr z, .items
    push hl                         ; title: row, col, len, tiles
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld d, h
    ld e, l
    pop hl
    ld a, [hl+]
    add e
    ld e, a
    ld a, d
    adc HIGH($9800)
    ld d, a
    ld a, ATTR_TEXT
    call MenuPut
.items:
    ld c, 0
.item:
    ld b, [hl]                      ; label length, kept for the attribute rows
    push hl
    ld a, c
    ADDA wMenuLens
    ld [hl], b
    ld a, c
    add a
    ld b, a
    ld a, [wMenuRow0]
    add b
    call MenuRowAddr
    pop hl
    ld a, [wMenuItem]
    cp c
    ld a, ATTR_TEXT
    jr nz, .put
    ld a, ATTR_HILITE
.put:
    push bc
    call MenuPut
    pop bc
    inc c
    ld a, [wMenuSize]
    cp c
    jr nz, .item
    ld a, [wMenuId]
    cp MENU_VOL_MENU
    call z, MenuVolDigits
    xor a
    ld [wMenuSelDirty], a
    ld [wMenuVolDirty], a
    ld a, [wPadLive]                ; no press carried over the redraw
    ld [wMenuPadPrev], a
    ld a, 1
    ld [wMenuSkullOn], a
    call MenuSkullOam
    jp MenuLcdOn

; Selection moved: attribute rows of the old and the new item (VBlank).
MenuSelAttr:
    xor a
    ld [wMenuSelDirty], a
    ld a, [wMenuPrev]
    ld c, ATTR_TEXT
    call .row
    ld a, [wMenuItem]
    ld c, ATTR_HILITE
.row:
    push bc
    ld b, a
    ADDA wMenuLens
    ld a, [hl]
    push af
    ld a, b
    add a
    ld b, a
    ld a, [wMenuRow0]
    add b
    call MenuRowAddr
    pop af
    pop bc
    and a
    ret z
    ld b, a
    ld a, 1
    ldh [rVBK], a
    ld h, d
    ld l, e
    ld a, c
.a:
    ld [hl+], a
    dec b
    jr nz, .a
    xor a
    ldh [rVBK], a
    ret

; Volume row digits (A8 write_vol2: ' ' or '1', then the units). VBlank or LCD off.
MenuVolDigits:
    xor a
    ld [wMenuVolDirty], a
    ld a, [wMenuRow0]               ; MENU_VOL_ITEM = 0
    call MenuRowAddr
    ld a, e
    add MENU_VOL_DIGITS
    ld l, a
    ld a, d
    adc 0
    ld h, a
    ld a, [wEffectsVol]
    cp 10
    jr c, .one
    sub 10
    ld b, a
    ld a, '1' + 96
    ld [hl+], a
    ld a, b
    jr .units
.one:
    ld b, a
    ld a, BLANK
    ld [hl+], a
    ld a, b
.units:
    add '0' + 96
    ld [hl], a
    ret

; HL = text (db npages; dw page...). Each page: blank lower rows, its lines, skull hidden; any button turns it,
; B leaves the rest (A8 show_text_screen loop). Leaves the skull hidden; MenuDraw shows it again.
MenuPages:
    ld a, [hl+]
    ld [wMenuPages], a
    ld a, l
    ld [wMenuText], a
    ld a, h
    ld [wMenuText + 1], a
    xor a
    ld [wMenuPage], a
    ld [wMenuSkullOn], a
.page:
    call MenuLcdOff
    call MenuSkullOam
    call MenuClearLower
    ld a, [wMenuPage]
    add a
    ld c, a
    ld b, 0
    ld a, [wMenuText]
    ld l, a
    ld a, [wMenuText + 1]
    ld h, a
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, [hl+]                     ; lines
    ld c, a
.line:
    ld a, [hl+]                     ; map offset
    ld e, a
    ld a, [hl+]
    add HIGH($9800)
    ld d, a
    push bc
    ld a, ATTR_TEXT
    call MenuPut
    pop bc
    dec c
    jr nz, .line
    call MenuLcdOn
    ld a, [wPadLive]
    ld [wMenuPadPrev], a
.wait:
    call MenuFrame
    ld a, [wMenuPressed]
    and PAD_ANY
    jr z, .wait
    and JOY_B                       ; B: leave the remaining pages
    ret nz
    ld hl, wMenuPage
    inc [hl]
    ld a, [wMenuPages]
    cp [hl]
    jr nz, .page
    ret

; ---- video setup (LCD off) ---------------------------------------------------------------------------------

MenuVideoInit:
    ld a, 1
    ldh [rVBK], a
    call ClearVRAMBank
    xor a
    ldh [rVBK], a
    call ClearVRAMBank
    ld hl, MenuLogoTiles            ; bank 0: logo
    ld de, VRAM_TILES
    ld bc, MenuLogoTilesEnd - MenuLogoTiles
    call MenuCopy
    ld hl, MenuFont                 ; bank 0: font as colour 1
    ld de, VRAM_TILES + MENU_FONT_TILE0 * 16
    call MenuFontPlane0
    ld a, 1
    ldh [rVBK], a
    ld hl, MenuSkullTiles           ; bank 1: skull
    ld de, VRAM_TILES
    ld bc, MenuSkullTilesEnd - MenuSkullTiles
    call MenuCopy
    ld hl, MenuFont                 ; bank 1: font as colour 2
    ld de, VRAM_TILES + MENU_FONT_TILE0 * 16
    call MenuFontPlane1
    ld hl, $9800                    ; bank 1 map: text attribute everywhere
    ld bc, $0400
.attr:
    ld a, ATTR_TEXT
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .attr
    ld hl, MenuLogoAttr             ; logo palettes
    call MenuLogoBlock
    xor a
    ldh [rVBK], a
    ld hl, $9800                    ; bank 0 map: blank everywhere
    ld bc, $0400
.map:
    ld a, BLANK
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .map
    ld hl, MenuLogoMap
    call MenuLogoBlock
    ld a, $80                       ; BG palettes 0..7
    ldh [rBCPS], a
    ld hl, MenuBgPal
    ld b, 64
.bp:
    ld a, [hl+]
    ldh [rBCPD], a
    dec b
    jr nz, .bp
    ld a, $80                       ; OBJ palettes 0..1 (skull layers)
    ldh [rOCPS], a
    ld hl, MenuObjPal
    ld b, 16
.op:
    ld a, [hl+]
    ldh [rOCPD], a
    dec b
    jr nz, .op
    jp MenuOamClear

; HL = 16x8 bytes -> map rows 0..7, columns MENU_LOGO_COL.. (current VRAM bank).
MenuLogoBlock:
    ld de, $9800 + MENU_LOGO_COL
    ld c, MENU_LOGO_ROWS
.r:
    ld b, MENU_LOGO_W
.x:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .x
    ld a, e
    add 32 - MENU_LOGO_W
    ld e, a
    ld a, d
    adc 0
    ld d, a
    dec c
    jr nz, .r
    ret

MenuCopy:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, MenuCopy
    ret

; HL = 1bpp rows, DE = tiles; 96 glyphs. Plane 0 = glyph (colour 1) / plane 1 = glyph (colour 2).
MenuFontPlane0:
    ld bc, 96 * 8
.r:
    ld a, [hl+]
    ld [de], a
    inc de
    xor a
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .r
    ret

MenuFontPlane1:
    ld bc, 96 * 8
.r:
    xor a
    ld [de], a
    inc de
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .r
    ret

INCLUDE "menu_gfx.inc"

ENDC
