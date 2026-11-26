; Level intermission (Doom wi_stuff.c single-player screens), shown after E1M1..E1M7 (E1M8 goes to the ending).
;
;   1 stats    : level name (white) / "Finished" (red); Kills, Items, Secret count up one after the other in red
;                (+2 % per tick, pistol sound every 4th tick, barrel sound at the end of each, one second between),
;                then Time and Par (+3 s per tick). A skips to the final numbers, A again goes on.
;   2 map      : the 160x128 Doom map (tools/gbc_genintermission.py) with a splat on every finished level, name
;                (white) / "Finished" (red) above. A goes on.
;   3 entering : the same map, "Entering" (red) / next level name (white) above, the "you are here" arrow and text
;                blinking on the next level (Doom: on while tick & 31 < 20). A starts the level.
; A tick is 2 VBlanks (~30 Hz; Doom runs at 35). Secrets = secret triggers entered / secret triggers in the map (100% when the map has none); the par
; times are Doom's E1 table.
;
; Called from LevelUpdate (combat.asm): ImSnapB before LoadLevel (finished level name and stats), ImRunB after it
; (the next level's name is in wMap). ImRunB takes the whole screen (LCD off, STAT interrupt off, own VRAM) and
; returns with the LCD off, VRAM wiped and the game's view map rebuilt; LevelUpdate then restores the HUD, the weapon
; video state and the interrupts (ImRestore). Banked code can only call ROM0 routines.

INCLUDE "hw.inc"
INCLUDE "sndids.inc"
INCLUDE "map_fields.inc"
INCLUDE "en.inc"

IF !DEF(TEST_EXIT) && !DEF(LIVETEST)

DEF IM_LCDC     EQU LCDCF_ON | LCDCF_BGON | LCDCF_BG8000 | LCDCF_OBJON | LCDCF_OBJ16
DEF ATTR_WHITE  EQU 6 | 8               ; palette 6, VRAM bank 1 (font)
DEF ATTR_RED    EQU 7 | 8               ; palette 7, VRAM bank 1
DEF IM_OAM         EQU $FE00
DEF TICK_VB     EQU 2                   ; VBlanks per intermission tick
DEF PAUSE_TICKS EQU 30                  ; Doom: TICRATE tics between the stats
DEF HIDDEN      EQU $FF                 ; count not started (8-bit); 16-bit: high byte $FF

; Screen layout (tiles)
DEF ROW_K       EQU 5
DEF ROW_I       EQU 7
DEF ROW_S       EQU 9
DEF ROW_T       EQU 13                  ; three blank rows after Secret
DEF ROW_P       EQU 15
DEF COL_LABEL   EQU 3
DEF COL_PCT     EQU 17                  ; '%' column; the digits end one column left
DEF COL_TIMEV   EQU COL_PCT             ; right edge of the time / par values (under the '%')

; sp_state (Doom): odd = pause
DEF ST_PAUSE_K  EQU 1
DEF ST_KILLS    EQU 2
DEF ST_PAUSE_I  EQU 3
DEF ST_ITEMS    EQU 4
DEF ST_PAUSE_S  EQU 5
DEF ST_SECRET   EQU 6
DEF ST_PAUSE_T  EQU 7
DEF ST_TIME     EQU 8
DEF ST_PAUSE_E  EQU 9
DEF ST_WAIT     EQU 10

SECTION "intervars", WRAMX, BANK[1]
wImNameA:     ds 20                     ; finished level's name
wImNameB:     ds 20                     ; next level's name
wImLast:      ds 1                      ; finished level index
wImFoundK:    ds 1
wImFoundI:    ds 1
wImFoundS:    ds 1
wImTotS:      ds 1                      ; secret triggers in the finished level
wImSec:       ds 2                      ; level time, seconds
wImTgtK:      ds 1                      ; final percentages
wImTgtI:      ds 1
wImTgtS:      ds 1
wImTgtT:      ds 2
wImTgtP:      ds 2
wImCntK:      ds 1                      ; shown values (HIDDEN until counting starts)
wImCntI:      ds 1
wImCntS:      ds 1
wImCntT:      ds 2
wImCntP:      ds 2
wImState:     ds 1
wImPause:     ds 1
wImVb:        ds 1                      ; VBlank counter within a tick
wImTick:      ds 1
wImPadPrev:   ds 1
wImArrowOn:   ds 1                      ; entering screen: 1 once the blink runs
wImShown:     ds 1                      ; arrow / text sprites currently visible
wImNode:      ds 2                      ; ROM pointer to the level's node record
wImDirty:     ds 1                      ; stats screen: draw the values at the next VBlank
IF DEF(INTERTEST)
wImDbg::      ds 1
wImDone::     ds 1                      ; set by LevelUpdate after the intermission: frames since
wImScr:       ds 1
ENDC

SECTION "intermission", ROMX, BANK[13]

INCLUDE "inter_gfx.inc"

DEF IM_BLANK    EQU INTER_FONT_ID0      ; font tile of ' ' (colour 0 = black)

; ---- snapshot (before LoadLevel) -----------------------------------------------------------------------------

; A = finished level is wLevel. Copies the map name and the counters.
ImSnapB::
    ld a, [wLevel]
    ld [wImLast], a
    ld hl, wImNameA
    call ImCopyName
    ld a, [wKills]
    ld [wImFoundK], a
    ld a, [wStItems]
    ld [wImFoundI], a
    ld a, [wStSecrets]
    ld [wImFoundS], a
    call ImCountSecrets
    ld [wImTotS], a
    ld a, [wStSec]
    ld [wImSec], a
    ld a, [wStSec + 1]
    ld [wImSec + 1], a
    ret

; -> A = number of secret triggers in the loaded map. The latch ORs $F0 into entered ones, so the low
; nibble is still the purpose. Keeps nothing.
ImCountSecrets:
    ld a, [wMapHdr + H_NTRIGS]
    and a
    ret z
    ld [wLvN], a
    ld b, 0                         ; count
    ld c, 0
.l:
    push bc
    ld a, F_TR_PURPOSE
    call MapGet
    pop bc
    and TRIG_PURPOSE_MASK
    cp TRIG_SECRET
    jr nz, .n
    inc b
.n:
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .l
    ld a, b
    ret

; HL = destination (20 bytes): the level name at wMap + 23 (WRAM bank 2), NUL-terminated, at most 19 characters.
ImCopyName:
    ld de, wMap + 23
    ld b, 19
.l:
    ld a, 2
    ldh [rSVBK], a
    ld a, [de]
    ld c, a
    ld a, 1
    ldh [rSVBK], a
    ld a, c
    ld [hl+], a
    and a
    jr z, .done
    inc de
    dec b
    jr nz, .l
    xor a
    ld [hl], a
.done:
    ret

; ---- entry -------------------------------------------------------------------------------------------------

; LoadLevel(next) has run: wMap holds the next level. Runs the three screens.
ImRunB::
IF DEF(INTERTEST)
    xor a
    ld [wImScr], a
ENDC
    ld hl, wImNameB
    call ImCopyName
    call ImTargets
    call ImVideoInit

    ; ---- 1: stats
    call ImLcdOff
    call ImClearMap
    call ImDrawStatsText
    call ImClearOam
    call ImResetCounts
    call ImLcdOn
    call ImPadSync
    call ImStatsLoop
    ld a, SND_SGCOCK
    call PlaySound

    ; ---- 2: map with the splats, "Finished"
    call ImLcdOff
    call ImClearMap
    call ImDrawMapImage
    ld hl, wImNameA
    ld de, .fin
    call ImCaption
    call ImClearOam
    call ImPlaceSplats
    call ImPlaceBuildings
    call ImLcdOn
    call ImPadSync
.w2:
    call ImFrame
    jr nc, .w2
    ld a, SND_SGCOCK
    call PlaySound

    ; ---- 3: entering, arrow + text blinking
    call ImLcdOff
    call ImClearMap
    call ImDrawMapImage
    ld hl, wImNameB
    ld de, .ent
    call ImCaptionEntering
    call ImClearOam
    call ImPlaceSplats
    call ImPlaceBuildings
    call ImPlaceArrow
    xor a
    ld [wImTick], a
    ld [wImVb], a
    inc a
    ld [wImArrowOn], a
    ld [wImShown], a
    call ImLcdOn
    call ImPadSync
.w3:
    call ImFrame
    jr c, .out
    jr .w3
.out:
    ld a, SND_SGCOCK
    call PlaySound
    jp ImExit

.fin: db "Finished", 0
.ent: db "Entering", 0

; ---- screen 1: Doom WI_updateStats ----------------------------------------------------------------------------

; Returns when A is pressed in the wait state. The values are drawn by ImFrame (right after the VBlank starts) on the
; frame after the tick that changed them.
ImStatsLoop:
.f:
    call ImFrame                    ; carry: A pressed
    jr nc, .noA
    ld a, [wImState]
    cp ST_WAIT
    ret z
    call ImFinishCounts             ; skip: final numbers, barrel, wait state
    ld a, SND_RXPLOD
    call PlaySound
    jr .dirty
.noA:
    ld a, [wImVb]
    cp TICK_VB
    jr c, .f
    xor a
    ld [wImVb], a
    ld hl, wImTick
    inc [hl]
    call ImStatsTick
.dirty:
    ld a, 1
    ld [wImDirty], a
    jr .f

ImResetCounts:
    ld a, HIDDEN
    ld [wImCntK], a
    ld [wImCntI], a
    ld [wImCntS], a
    ld [wImCntT + 1], a
    ld [wImCntP + 1], a
    ld a, ST_PAUSE_K
    ld [wImState], a
    ld a, PAUSE_TICKS
    ld [wImPause], a
    xor a
    ld [wImTick], a
    ld [wImVb], a
    ld [wImArrowOn], a
    ld [wImDirty], a
    ret

; All counts to their targets (Doom: accelerate), state = wait.
ImFinishCounts:
    ld a, [wImTgtK]
    ld [wImCntK], a
    ld a, [wImTgtI]
    ld [wImCntI], a
    ld a, [wImTgtS]
    ld [wImCntS], a
    ld a, [wImTgtT]
    ld [wImCntT], a
    ld a, [wImTgtT + 1]
    ld [wImCntT + 1], a
    ld a, [wImTgtP]
    ld [wImCntP], a
    ld a, [wImTgtP + 1]
    ld [wImCntP + 1], a
    ld a, ST_WAIT
    ld [wImState], a
    ret

; One tick of the state machine.
ImStatsTick:
    ld a, [wImState]
    cp ST_WAIT
    ret z
    bit 0, a
    jr z, .count
    ld hl, wImPause                 ; odd: pause one second, then the next stat
    dec [hl]
    ret nz
    ld a, [wImState]
    inc a
    ld [wImState], a
    ld a, PAUSE_TICKS
    ld [wImPause], a
    ret
.count:
    ld a, [wImTick]                 ; pistol every 4th tick while counting
    and 3
    jr nz, .nosnd
    ld a, SND_PISTOL
    call PlaySound
.nosnd:
    ld a, [wImState]
    cp ST_KILLS
    ld hl, wImCntK
    ld de, wImTgtK
    jr z, .pct
    cp ST_ITEMS
    ld hl, wImCntI
    ld de, wImTgtI
    jr z, .pct
    cp ST_SECRET
    ld hl, wImCntS
    ld de, wImTgtS
    jr z, .pct
    jr .time
.pct:                               ; Doom: -1, then +2 per tick
    ld a, [hl]
    cp HIDDEN
    jr nz, .inc
    ld a, 1
    jr .add
.inc:
    add 2
.add:
    ld b, a
    ld a, [de]
    ld c, a
    ld a, b
    cp c
    jr c, .store
    ld a, c                         ; reached: clamp, barrel, next state
    ld [hl], a
    ld a, SND_RXPLOD
    call PlaySound
    jr .next
.store:
    ld [hl], a
    ret
.next:
    ld a, [wImState]
    inc a
    ld [wImState], a
    ld a, PAUSE_TICKS
    ld [wImPause], a
    ret
.time:                              ; time and par together, +3 seconds each
    ld a, [wImCntT + 1]
    cp HIDDEN
    jr nz, .tinc
    xor a
    ld [wImCntT], a
    ld [wImCntT + 1], a
    ld [wImCntP], a
    ld [wImCntP + 1], a
    jr .tcheck
.tinc:
    ld hl, wImCntT
    ld de, wImTgtT
    call ImAdd3Clamp
    ld hl, wImCntP
    ld de, wImTgtP
    call ImAdd3Clamp
.tcheck:
    ld hl, wImCntT                  ; both at their targets?
    ld de, wImTgtT
    call ImEq16
    ret nz
    ld hl, wImCntP
    ld de, wImTgtP
    call ImEq16
    ret nz
    ld a, SND_RXPLOD
    call PlaySound
    jr .next

; [hl..hl+1] += 3, clamped to [de..de+1].
ImAdd3Clamp:
    ld a, [hl+]
    add 3
    ld c, a
    ld a, [hl]
    adc 0
    ld b, a                         ; BC = value + 3, HL -> high byte
    ld a, [de]
    sub c
    inc de
    ld a, [de]
    sbc b                           ; carry: target < BC
    jr nc, .keep
    ld a, [de]                      ; clamp to the target
    ld b, a
    dec de
    ld a, [de]
    ld c, a
.keep:
    ld a, b
    ld [hl-], a
    ld a, c
    ld [hl], a
    ret

; Z if [hl..] == [de..] (16-bit).
ImEq16:
    ld a, [de]
    cp [hl]
    ret nz
    inc hl
    inc de
    ld a, [de]
    cp [hl]
    ret

; ---- targets ---------------------------------------------------------------------------------------------

ImTargets:
    ld a, [wImLast]                 ; stats record = InterStats + 3 * level
    ld c, a
    add a
    add c
    ld e, a
    ld d, 0
    ld hl, InterStats
    add hl, de
    ld a, [hl+]                     ; kills total
    ld c, a
    ld a, [wImFoundK]
    call ImPercent
    ld [wImTgtK], a
    ld a, [hl+]                     ; items total
    ld c, a
    ld a, [wImFoundI]
    call ImPercent
    ld [wImTgtI], a
    ld a, [wImTotS]                 ; secrets: found / secret triggers in the level
    ld c, a
    ld a, [wImFoundS]
    call ImPercent
    ld [wImTgtS], a
    ld a, [wImSec]                  ; level time, seconds
    ld [wImTgtT], a
    ld a, [wImSec + 1]
    ld [wImTgtT + 1], a
    ld a, [hl]                      ; par seconds
    ld [wImTgtP], a
    xor a
    ld [wImTgtP + 1], a
    ret

; A = found, C = total -> A = found * 100 / total, 100 when the total is 0, at most 100. Keeps HL.
ImPercent:
    push hl
    ld b, a
    ld a, c
    and a
    jr z, .full
    ld a, b
    cp c
    jr nc, .full
    ld hl, 0                        ; HL = found * 100
    ld de, 100
.m:
    ld a, b
    and a
    jr z, .md
    add hl, de
    dec b
    jr .m
.md:
    ld d, h
    ld e, l
    ld b, 0
    call Div24x8                    ; DE = B:D:E / C
    ld a, e
    pop hl
    ret
.full:
    pop hl
    ld a, 100
    ret

; ---- one frame ---------------------------------------------------------------------------------------------

; VBlank wait, sound tick, blink, A edge. Carry = A pressed (a new press; not one held from before the screen).
ImFrame:
    call WaitVBlank
    ld a, [wImDirty]                ; VRAM first, while the VBlank is young
    and a
    jr z, .clean
    xor a
    ld [wImDirty], a
    call ImDrawValues
.clean:
    call ImBlink
    call SndTick                    ; one envelope step per frame (the game does this from the STAT interrupt)
    ld a, [wImVb]
    inc a
    ld [wImVb], a
    ld a, [wImArrowOn]
    and a
    jr z, .pad
    ld a, [wImVb]                   ; entering screen: the blink counter runs here
    cp TICK_VB
    jr c, .pad
    xor a
    ld [wImVb], a
    ld hl, wImTick
    inc [hl]
.pad:
IF DEF(INTERTEST)
    jp ImTestPad
ENDC
    ld a, [wPadLive]
    ld b, a
    di
    ld a, [wPadLatch]
    ld c, a
    xor a
    ld [wPadLatch], a
    ei
    ld a, [wImPadPrev]
    ld d, a
    ld a, b
    ld [wImPadPrev], a
    bit 4, b                        ; A held now
    jr z, .rel
    bit 4, d
    jr nz, .no                      ; still held from before
    scf
    ret
.rel:
    bit 4, d
    jr nz, .no                      ; released this frame: not a press
    bit 4, c
    jr z, .no
    scf                             ; a tap shorter than a frame (latched)
    ret
.no:
    and a
    ret

; Forget A held / latched from before the screen: a held button is not a press.
ImPadSync:
    ld a, [wPadLive]
    ld [wImPadPrev], a
    xor a
    ld [wPadLatch], a
    ld [wImVb], a
    ld [wImDirty], a
IF DEF(INTERTEST)
    ld [wImDbg], a
    ld hl, wImScr
    inc [hl]
ENDC
    ret

IF DEF(INTERTEST)
; Screenshot tests (tools/gbc_intercheck.py): no pad; A "pressed" at frame 200 and 250 of each screen, and a
; breakpoint label at frame INTER_BRK of screen INTER_SCR.
ImDbgBreak::
    nop
    ret

ImTestPad:
    ld a, [wImDbg]
    inc a
    ld [wImDbg], a
    ld b, a
    ld a, [wImScr]
    cp INTER_SCR
    jr nz, .p
    ld a, b
    cp INTER_BRK
    jr nz, .p
    call ImDbgBreak
.p:
    ld a, b
    cp 200
    jr z, .press
    cp 250
    jr z, .press
    and a
    ret
.press:
    scf
    ret
ENDC

; Entering screen: arrow + text on while tick & 31 < 20 (Doom snl_pointeron). IM_OAM entries 0..3.
ImBlink:
    ld a, [wImArrowOn]
    and a
    ret z
    ld a, [wImTick]
    and 31
    cp 20
    ld a, 0
    jr nc, .off
    inc a
.off:
    ld b, a
    ld a, [wImShown]
    cp b
    ret z
    ld a, b
    ld [wImShown], a
    and a
    jr z, .hide
    ld hl, wImNode                  ; show: y values from the node record (tile, arrow y / x, text y / x at +2..+6)
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    inc hl
    inc hl
    inc hl
    ld a, [hl+]
    ld [IM_OAM], a                     ; arrow y (+3)
    inc hl                          ; skip the x (+4)
    ld a, [hl]                      ; text y (+5)
    ld [IM_OAM + 4], a
    ld [IM_OAM + 8], a
    ld [IM_OAM + 12], a
    ret
.hide:
    xor a
    ld [IM_OAM], a
    ld [IM_OAM + 4], a
    ld [IM_OAM + 8], a
    ld [IM_OAM + 12], a
    ret

; ---- drawing -----------------------------------------------------------------------------------------------

; Map (both banks) blank, red attribute (blank tile in bank 1 is black in either palette).
ImClearMap:
    xor a
    ldh [rVBK], a
    ld hl, $9800
    ld bc, $0400
.t:
    ld a, IM_BLANK
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .t
    ld a, 1
    ldh [rVBK], a
    ld hl, $9800
    ld bc, $0400
.a:
    ld a, ATTR_RED
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .a
    xor a
    ldh [rVBK], a
    ret

; HL = NUL-terminated ASCII, B = attribute, D = row, E = column. LCD off or VBlank.
ImPutText:
    push hl
    push bc
    call ImAddr                     ; DE = map address
    pop bc
    pop hl
    push de
    push hl
.t:                                 ; tiles (bank 0): tile = ASCII + 96
    ld a, [hl+]
    and a
    jr z, .td
    add 96
    ld [de], a
    inc de
    jr .t
.td:
    pop hl
    pop de
    ld a, 1
    ldh [rVBK], a
.a:                                 ; attributes (bank 1)
    ld a, [hl+]
    and a
    jr z, .ad
    ld a, b
    ld [de], a
    inc de
    jr .a
.ad:
    xor a
    ldh [rVBK], a
    ret

; HL = text, returns the length in B.
ImLen:
    ld b, 0
.l:
    ld a, [hl+]
    and a
    ret z
    inc b
    jr .l

; Centred caption: HL = first line (name: white), DE = second line (red); rows 0 / 1.
ImCaption:
    push de
    ld c, ATTR_WHITE
    ld d, 0
    call ImCenterLine
    pop hl
    ld c, ATTR_RED
    ld d, 1
    jp ImCenterLine

; Entering: HL = next level's name, DE = "Entering": "Entering" (red) on row 0, the name (white) on row 1.
ImCaptionEntering:
    push hl
    ld h, d
    ld l, e
    ld c, ATTR_RED
    ld d, 0
    call ImCenterLine
    pop hl
    ld c, ATTR_WHITE
    ld d, 1
    jp ImCenterLine

; HL = text, C = attribute, D = row: centred on the 20 columns.
ImCenterLine:
    push hl
    call ImLen
    ld a, 20
    sub b
    srl a
    ld e, a
    ld b, c
    pop hl
    jp ImPutText

; Stats screen: name / Finished, labels.
ImDrawStatsText:
    ld hl, wImNameA
    ld de, .fin
    call ImCaption
    ld hl, .kills
    ld b, ATTR_RED
    ld d, ROW_K
    ld e, COL_LABEL
    call ImPutText
    ld hl, .items
    ld b, ATTR_RED
    ld d, ROW_I
    ld e, COL_LABEL
    call ImPutText
    ld hl, .secret
    ld b, ATTR_RED
    ld d, ROW_S
    ld e, COL_LABEL
    call ImPutText
    ld hl, .time
    ld b, ATTR_RED
    ld d, ROW_T
    ld e, COL_LABEL
    call ImPutText
    ld hl, .par
    ld b, ATTR_RED
    ld d, ROW_P
    ld e, COL_LABEL
    jp ImPutText
.fin:    db "Finished", 0
.kills:  db "Kills", 0
.items:  db "Items", 0
.secret: db "Secret", 0
.time:   db "Time", 0
.par:    db "Par", 0

; The shown values (VBlank or LCD off): percentages and times that have started.
ImDrawValues:
    ld a, [wImCntK]
    ld d, ROW_K
    call ImPutPct
    ld a, [wImCntI]
    ld d, ROW_I
    call ImPutPct
    ld a, [wImCntS]
    ld d, ROW_S
    call ImPutPct
    ld a, [wImCntT + 1]
    cp HIDDEN
    ret z
    ld hl, wImCntT
    ld d, ROW_T
    ld e, COL_TIMEV
    call ImPutTime
    ld hl, wImCntP
    ld d, ROW_P
    ld e, COL_TIMEV
    jp ImPutTime

; DE = BG map address of row D, column E.
ImAddr:
    ld l, d
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, e
    add l
    ld l, a
    ld a, h
    adc HIGH($9800)
    ld d, a
    ld e, l
    ret

; A = percentage ($FF hidden), D = row: digits right-aligned to column COL_PCT - 1, '%' at COL_PCT.
ImPutPct:
    cp HIDDEN
    ret z
    ld b, a
    ld e, COL_PCT
    push bc
    call ImAddr
    pop bc
    ld a, '%' + 96
    ld [de], a
    dec de
    ld a, b                         ; ones
    ld c, 0
.t:
    cp 10
    jr c, .o
    sub 10
    inc c
    jr .t
.o:
    add '0' + 96
    ld [de], a
    dec de
    ld a, c                         ; tens (C = value / 10: 0..10)
    and a
    ret z
    cp 10
    jr nc, .hund
    add '0' + 96
    ld [de], a
    ret
.hund:                              ; 100: "100"
    ld a, '0' + 96
    ld [de], a
    dec de
    ld a, '1' + 96
    ld [de], a
    ret

; HL = 16-bit seconds, D = row, E = column of the last character: "m:ss" / "mm:ss" right-aligned.
ImPutTime:
    ld a, [hl+]
    ld c, a
    ld b, [hl]                      ; BC = seconds
    call ImAddr                     ; DE = address of the last digit
    ld h, 0                         ; H = minutes
.m:
    ld a, b
    and a
    jr nz, .sub
    ld a, c
    cp 60
    jr c, .md
.sub:
    ld a, c
    sub 60
    ld c, a
    ld a, b
    sbc 0
    ld b, a
    inc h
    jr .m
.md:
    ld a, c                         ; seconds 0..59
    ld b, 0
.s10:
    cp 10
    jr c, .s1
    sub 10
    inc b
    jr .s10
.s1:
    add '0' + 96
    ld [de], a
    dec de
    ld a, b
    add '0' + 96
    ld [de], a
    dec de
    ld a, ':' + 96
    ld [de], a
    dec de
    ld a, h                         ; minutes
    ld b, 0
.m10:
    cp 10
    jr c, .m1
    sub 10
    inc b
    jr .m10
.m1:
    add '0' + 96
    ld [de], a
    ld a, b
    and a
    ret z
    dec de
    add '0' + 96
    ld [de], a
    ret

; The 160x128 map on rows INTER_MAP_ROW0.. (tiles bank 0, attributes bank 1; LCD off).
ImDrawMapImage:
    ld hl, InterMapId
    ld de, $9800 + INTER_MAP_ROW0 * 32
    call ImMapRows
    ld a, 1
    ldh [rVBK], a
    ld hl, InterMapAttr
    ld de, $9800 + INTER_MAP_ROW0 * 32
    call ImMapRows
    xor a
    ldh [rVBK], a
    ret

ImMapRows:
    ld c, 16
.r:
    ld b, 20
.x:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .x
    ld a, e
    add 32 - 20
    ld e, a
    jr nc, .nc
    inc d
.nc:
    dec c
    jr nz, .r
    ret

; ---- sprites -----------------------------------------------------------------------------------------------

ImClearOam:
    ld hl, IM_OAM
    ld b, 160
    xor a
.l:
    ld [hl+], a
    dec b
    jr nz, .l
    ret

; A = level -> HL = its node record in InterNodes (7 bytes: splat y, x, arrow tile, arrow y, x, text y, x).
; Clobbers A, DE.
ImNodeAt:
    ld e, a
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl
    add hl, hl                      ; * 8
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc 0
    ld h, a                         ; * 7
    ld de, InterNodes
    add hl, de
    ret

; OAM entries 0..3 = arrow (1) + text (3) at the next level's node; entries 4.. = splats.
ImPlaceArrow:
    ld a, [wImLast]
    inc a
    call ImNodeAt
    ld a, l
    ld [wImNode], a
    ld a, h
    ld [wImNode + 1], a
    inc hl
    inc hl                          ; -> arrow tile (+2)
    ld a, [hl+]
    ld [IM_OAM + 2], a
    ld a, [hl+]
    ld [IM_OAM], a                     ; y
    ld a, [hl+]
    ld [IM_OAM + 1], a                 ; x
    ld b, a                         ; arrow x
    ld a, [hl+]
    ld c, a                         ; text y
    ld a, [hl]
    ld d, a                         ; text x
    ld a, 8                         ; OBJ palette 0 (shared red), bank 1
    ld [IM_OAM + 3], a
    ld hl, IM_OAM + 4                  ; text: 3 sprites of 8x16
    ld e, INTER_T_TEXT
    ld b, 3
.t:
    ld a, c
    ld [hl+], a
    ld a, d
    ld [hl+], a
    add 8
    ld d, a
    ld a, e
    ld [hl+], a
    add 2
    ld e, a
    ld a, 8                         ; OBJ palette 0, bank 1
    ld [hl+], a
    dec b
    jr nz, .t
    ret

; A splat (2 sprites) on every finished level 0..last: IM_OAM entries from 4 (arrow entries 0..3 stay free / used).
ImPlaceSplats:
    ld hl, IM_OAM + 16
    ld a, [wImLast]
    inc a
    ld b, a                         ; levels 0..last
    ld c, 0
.n:
    push bc
    push hl
    ld a, c
    call ImNodeAt
    ld d, [hl]                      ; y
    inc hl
    ld e, [hl]                      ; x
    pop hl
    ld a, d                         ; left half
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld a, INTER_T_SPLAT
    ld [hl+], a
    ld a, 8                         ; OBJ palette 0, bank 1
    ld [hl+], a
    ld a, d                         ; right half
    ld [hl+], a
    ld a, e
    add 8
    ld [hl+], a
    ld a, INTER_T_SPLAT + 2
    ld [hl+], a
    ld a, 8
    ld [hl+], a
    pop bc
    inc c
    dec b
    jr nz, .n
    ret

; Building overlay sprites (tools/gbc_genintermission.py) after the splats, so the splats draw over them.
; HL = next free OAM entry (as ImPlaceSplats leaves it).
ImPlaceBuildings:
IF INTER_NBLD > 0
    ld de, InterBld
    ld b, INTER_NBLD * 4
.c:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .c
ENDC
    ret

; ---- video ---------------------------------------------------------------------------------------------------

ImLcdOff:
    ldh a, [rLCDC]
    and LCDCF_ON
    ret z
.w:
    ldh a, [rLY]
    cp 144
    jr c, .w
    xor a
    ldh [rLCDC], a
    ret

ImLcdOn:
    ld a, IM_LCDC
    ldh [rLCDC], a
    ret

; LCD off, no STAT interrupt (it would clip the screen at LY 111), VBlank + timer only; tiles and palettes in.
ImVideoInit:
    di
    call ImLcdOff
    xor a
    ldh [rSTAT], a
    ldh [rIF], a
    ldh [rSCX], a
    ldh [rSCY], a
    ld [wApOk], a                   ; VBlankISR's WpnTick stays out of IM_OAM
    ld a, IEF_VBLANK | IEF_TIMER
    ldh [rIE], a
    ld a, 1
    ldh [rVBK], a
    call ClearVRAMBank
    xor a
    ldh [rVBK], a
    call ClearVRAMBank
    ld hl, InterTiles0              ; bank 0: map tiles 0..255
    ld de, VRAM_TILES
    ld bc, INTER_N_BANK0 * 16
    call ImCopy
    ld a, 1
    ldh [rVBK], a
    ld hl, InterTiles1              ; bank 1: the overflow from 0
    ld de, VRAM_TILES
    ld bc, INTER_N_SPILL * 16
    ld a, b
    or c
    call nz, ImCopy
    ld hl, InterFont                ; bank 1: font at 128..223
    ld de, VRAM_TILES + INTER_FONT_ID0 * 16
    ld bc, 96 * 16
    call ImCopy
    ld hl, InterObjTiles            ; bank 1: sprites at 224..
    ld de, VRAM_TILES + INTER_OBJ_ID0 * 16
    ld bc, INTER_N_OBJ * 16
    call ImCopy
IF INTER_NBLD > 0
    ld hl, InterBldTiles            ; bank 1: building overlay sprites
    ld de, VRAM_TILES + INTER_BLD_ID0 * 16
    ld bc, INTER_N_BLDT * 16
    call ImCopy
ENDC
    xor a
    ldh [rVBK], a
    ld a, $80                       ; BG palettes 0..7
    ldh [rBCPS], a
    ld hl, InterBgPal
    ld b, 64
.bp:
    ld a, [hl+]
    ldh [rBCPD], a
    dec b
    jr nz, .bp
    ld a, $80                       ; OBJ palettes 0..7
    ldh [rOCPS], a
    ld hl, InterObjPal
    ld b, 64
.op:
    ld a, [hl+]
    ldh [rOCPD], a
    dec b
    jr nz, .op
    ei
    ret

ImCopy:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, ImCopy
    ret

; Back to the game: LCD off, VRAM wiped, the view map rebuilt (the Reboot sequence minus the level load).
; LevelUpdate (ROM0) does HudInit and the weapon / interrupt restore.
ImExit:
    di
    call ImLcdOff
    call ImClearOam
    xor a
    ldh [rVBK], a
    ldh [rSCX], a
    ldh [rSCY], a
    ldh [rLCDC], a
    ld a, 1
    ldh [rVBK], a
    call ClearVRAMBank
    xor a
    ldh [rVBK], a
    call ClearVRAMBank
    call InstallFont
    call InitViewMap
    xor a
    ldh [hShow], a
    ldh [hPlane], a
    ld [wPadLatch], a
    ret

ENDC
