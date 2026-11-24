; da8m GBC port - phase 1 spike.
; CGB-only header, MBC5, double speed, 128x112 viewport (16x14 column-major
; tiles) drawn from a WRAM framebuffer into VRAM bank 0/1 (double buffered by
; flipping the tile-attribute bank bit).
;
; Build modes (build-gbc.bat): default = spinning room demo; `test` = static
; line pattern; `bench`; `pose`; `live` (demo that stops after 3 frames).

INCLUDE "hw.inc"

SECTION "vblank_vec", ROM0[$0040]
    jp VBlankISR

SECTION "stat_vec", ROM0[$0048]
    jp StatISR

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
    ld sp, STACK_TOP                ; WRAM0 $CF00-$CFFF

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

    ; VRAM: clear both banks, hex font, map.
    ld a, 1
    ldh [rVBK], a
    call ClearVRAMBank
    xor a
    ldh [rVBK], a
    call ClearVRAMBank
    call InstallFont
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
    ldh [hShow], a

    ldh a, [rKEY1]
    and $80
    ldh [hSpeed], a

    ; Level 0 (E1M1): map into WRAM bank 2, spawn camera, spawn room mesh.
    xor a
    ld [wPoseI], a
    ldh [hLastFrame], a
    ld [wHaveKeys], a
    call LoadLevel
    call WpnInit
    ld a, $A5
    ldh [hRnd], a

    ; Static test scene into bank 0 (shown until the demo loop replaces it).
    call ClearFB
    call DrawTestSet
    xor a
    call CopyFBGeneral

    ld a, 111
    ldh [rLYC], a
    ld a, $40                       ; STAT interrupt on LY = LYC
    ldh [rSTAT], a
    ld a, IEF_VBLANK | IEF_STAT
    ldh [rIE], a
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_BG8000 | LCDCF_OBJON | LCDCF_OBJ16
    ldh [rLCDC], a
    ei

IF DEF(BENCH)
    call RunBench
ENDC

IF DEF(POSETEST)
    call RunPoseTest
ENDC

IF DEF(MAPTEST)
    call RunMapTest
ENDC

IF DEF(MOVETEST)
    call RunMoveTest
ENDC

IF DEF(WORLDTEST)
    call RunWorldTest
ENDC

IF DEF(ENTTEST)
    call RunEntTest
ENDC

IF DEF(SMOKE)
    call RunSmoke
ENDC

IF DEF(PICKUNIT)
    call RunPickUnit
ENDC

IF DEF(COMBUNIT)
    call RunCombUnit
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
IF DEF(TEST_EXIT)
    ; Test builds stop here; park instead of running the demo.
.park:
    halt
    nop
    jr .park
ENDC

; ---- demo: spinning room, double buffered ---------------------------------
Demo:
    call ClearFB
    ei
    call RenderScene
IF !DEF(NOOBJ)
    call DrawWorldObjects
ENDC
    ldh a, [hShow]
    xor 1
    call CopyFBHBlank               ; into the hidden bank
    call WaitVBlank
    ldh a, [hShow]
    xor 1
    ldh [hShow], a
    call ShowBank                   ; flip
    call WpnVBlank
    call HudBlit
IF DEF(LIVETEST)
    ; Record the VBlank counter per iteration under a "LIVE" magic.
    ld hl, wPoseMagic
    ld a, 'L'
    ld [hl+], a
    ld a, 'I'
    ld [hl+], a
    ld a, 'V'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    ld a, [wPoseI]
    ld c, a
    ld b, 0
    ld hl, wPoseOut
    add hl, bc
    ldh a, [hFrame]
    ld [hl], a
    ld a, c
    inc a
    ld [wPoseI], a
    cp 6
    jr nz, .noStop
    ld a, [wSpin]
    ld [wPoseOut + 8], a
    call WaitVBlank
    call WaitVBlank
    jp LiveStop
.noStop:
ENDC
    call UpdateMove
    call WpnUpdate
    call PickupScan
    call CombatUpdate
    call HudUpdate
    jr Demo

IF DEF(LIVETEST)
LiveStop::                           ; headless test breakpoint (tools/gbc_check.py --live)
    nop
    jr LiveStop
ENDC

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

; a = value, hl = dest. Writes two hex-digit tiles (digit d = tile FONT_TILE0 + d).
PutHex:
    ld b, a
    swap a
    and $0F
    add FONT_TILE0
    ld [hl+], a
    ld a, b
    and $0F
    add FONT_TILE0
    ld [hl], a
    ret

TimerISR:
    push af
    ldh a, [hOver]
    inc a
    ldh [hOver], a
    pop af
    reti

; LY = 111 (LYC): at the end of that line switch sprites off, so the weapon is clipped at the
; viewport bottom like the A8 build (rows >= 128 are never drawn). VBlankISR switches them back on.
StatISR:
    push af
.hblank:
    ldh a, [rSTAT]
    and 3
    jr nz, .hblank
    ldh a, [rLCDC]
    and $FF - LCDCF_OBJON
    ldh [rLCDC], a
    pop af
    reti

VBlankISR:
    push af
    ldh a, [rLCDC]
    or LCDCF_OBJON
    ldh [rLCDC], a
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
