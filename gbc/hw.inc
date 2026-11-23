; Game Boy Color hardware registers used by the port.

DEF rP1     EQU $FF00
DEF rDIV    EQU $FF04
DEF rTIMA   EQU $FF05
DEF rTMA    EQU $FF06
DEF rTAC    EQU $FF07
DEF rIF     EQU $FF0F
DEF rLCDC   EQU $FF40
DEF rSTAT   EQU $FF41
DEF rSCY    EQU $FF42
DEF rSCX    EQU $FF43
DEF rLY     EQU $FF44
DEF rBGP    EQU $FF47
DEF rKEY1   EQU $FF4D
DEF rVBK    EQU $FF4F
DEF rHDMA1  EQU $FF51
DEF rHDMA2  EQU $FF52
DEF rHDMA3  EQU $FF53
DEF rHDMA4  EQU $FF54
DEF rHDMA5  EQU $FF55
DEF rSVBK   EQU $FF70             ; WRAM bank (1-7) at $D000-$DFFF
DEF rBCPS   EQU $FF68
DEF rBCPD   EQU $FF69
DEF rOCPS   EQU $FF6A
DEF rOCPD   EQU $FF6B
DEF rIE     EQU $FFFF

DEF LCDCF_ON      EQU %10000000
DEF LCDCF_BGON    EQU %00000001
DEF LCDCF_BG8000  EQU %00010000   ; BG/window tile data at $8000
DEF LCDCF_OBJON   EQU %00000010
DEF LCDCF_OBJ16   EQU %00000100   ; 8x16 sprites

DEF IEF_VBLANK    EQU %00000001
DEF IEF_TIMER     EQU %00000100

; MBC5
DEF rROMB0  EQU $2000             ; ROM bank low 8 bits
DEF rROMB1  EQU $3000             ; ROM bank bit 8

DEF VRAM_TILES  EQU $8000
DEF VRAM_MAP0   EQU $9800

; Viewport: 16 x 14 tiles = 128 x 112 px, column-major tiles. Column tx is 224 bytes
; at FB + tx*224; pixel (x,y) is at column(x>>3) + y*2 (plane 0), bit 7-(x&7).
; Tile id = tx*14 + ty, so the whole buffer is one contiguous DMA run of 224 blocks.
DEF VIEW_COLS   EQU 16
DEF VIEW_ROWS   EQU 14
DEF VIEW_MAPX   EQU 2             ; BG map column of the viewport's left edge
DEF FB          EQU $C000
DEF FB_HI       EQU $C0
DEF FB_STRIDE   EQU 224           ; bytes per column
DEF FB_SIZE     EQU FB_STRIDE * VIEW_COLS   ; 3584
DEF VIEW_TILES  EQU VIEW_COLS * VIEW_ROWS   ; 224
DEF BLANK_TILE  EQU VIEW_TILES    ; tile 224 = blank, 225.. = hex digits 0-F
DEF FONT_TILE0  EQU VIEW_TILES + 1
DEF STACK_TOP   EQU $D000         ; stack lives in WRAM0 $CF00-$CFFF (outside the WRAMX window)
DEF EYE_HEIGHT   EQU 3            ; eye above the feet, world units
DEF FOCAL_HALF  EQU 40            ; FOCAL (80) / 2, for SMul16's >> 7

; Joypad byte (hJoy): active high.
DEF JOY_RIGHT   EQU %00000001
DEF JOY_LEFT    EQU %00000010
DEF JOY_UP      EQU %00000100
DEF JOY_DOWN    EQU %00001000
DEF JOY_A       EQU %00010000
DEF JOY_B       EQU %00100000
DEF JOY_SELECT  EQU %01000000
DEF JOY_START   EQU %10000000
