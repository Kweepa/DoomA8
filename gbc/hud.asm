; HUD contents, message line and palettes (A8 src/hud.asm, src/a8irq.asm, src/enemy.asm hurt flash),
; in a ROMX bank; ROM0 entry points are in combat.asm (HudInit, HudUpdate, HudGot, HudKeyReq) and
; HudBlit writes the shadow rows / staged palettes in VBlank.
;
; Layout (BG rows; the viewport is rows 0-13, cols 2-17). Steve's GBC layout: numbers and icons, no
; labels / title / map name; one 20-column message row with shortened text.
;   Doom-style block (Steve): ammo column left, health, armour, key cards column right.
;   row 14:      message, centred       "+<item>", "Need a <key> keycard", "Opened elsewhere"
;   row 15:  {bul                 ]     A8 ammo icons '{' '|' '}' (HUD_CH_BULLET / SHELL / ROCKET)
;   row 16:  |shl  ^hp  ~arm      \     '^' health, '~' armour (GBC glyphs)
;   row 17:  }rkt       ms<ms>    [     frame time (ms per game frame); keys blue / yellow / red
; HUD tiles are the A8 UI charset at $9000 (bank 0), tile id = ASCII - 32; the STAT interrupt
; switches the HUD rows to $8800 (signed) tile addressing (main.asm StatISR / VBlankISR).
;
; Colours (Steve: the A8 scheme). A8 viewport: paper = room_bg, ink = same hue at lum $C, red $46
; (blood / fireball), black. Palette 0 viewport, 1 border (black, COL_HURT_A8 for HURT_FLASH_MS),
; 2 HUD stats (A8 text mode: hue of HUD_PF2_STAT with lum HUD_PF1_STAT on HUD_PF2_STAT), 3 message
; (lum HUD_PF1_MSG). A8 bytes -> BGR555 through A8Pal (tools/gbc_hudfont.py, editor A8_HEX).

INCLUDE "hw.inc"
INCLUDE "map_fields.inc"
INCLUDE "en.inc"

DEF HUD_ROW      EQU 14                 ; first shadow row (rows 14-17)
DEF HUD_W        EQU 20
DEF HUD_MSG      EQU 0                  ; message row (14) offset in wHudRows
DEF HUD_R15      EQU 1 * HUD_W
DEF HUD_R16      EQU 2 * HUD_W
DEF HUD_R17      EQU 3 * HUD_W
DEF COL_AMMO     EQU 2                  ; icon column; digits follow
DEF COL_HEALTH   EQU 7
DEF COL_ARMOUR   EQU 12
DEF COL_KEYS     EQU 17
DEF CH_HEALTH    EQU $5E                ; '^'
DEF CH_ARMOUR    EQU $7E                ; '~'
DEF A8_RED       EQU $46                ; a8irq.asm dli_blood: COLPF1 blood (pixel %10)
DEF A8_BLACK     EQU $00
DEF ROOM_BG_DEFAULT EQU $24             ; tools/genmap.py: rooms with no a8Bg
DEF HUD_STAT_INK EQU (HUD_PF2_STAT & $F0) | HUD_PF1_STAT
DEF HUD_MSG_INK  EQU (HUD_PF2_STAT & $F0) | HUD_PF1_MSG
DEF TH_NTYPES_   EQU TH_BARREL + 1

SECTION "hud", ROMX

INCLUDE "hudfont.inc"                   ; HudFontTiles, A8Pal

; LCD off. HUD font into VRAM bank 0 $9000; attributes: border palette 1, viewport palette 0,
; message row 14 palette 3, stat rows 15-17 palette 2; empty HUD; palettes built and written.
HudInitB::
    xor a
    ldh [rVBK], a
    ld hl, HudFontTiles
    ld de, $9000
    ld bc, HudFontTilesEnd - HudFontTiles
.font:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .font
    ld a, 1
    ldh [rVBK], a
    ld hl, VRAM_MAP0
    ld bc, 32 * 18
.border:
    ld a, 1
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .border
    ld hl, VRAM_MAP0 + VIEW_MAPX        ; viewport cells: palette 0 (ShowBank keeps it so)
    ld c, VIEW_ROWS
.vr:
    ld b, VIEW_COLS
    xor a
.vc:
    ld [hl+], a
    dec b
    jr nz, .vc
    ld de, 32 - VIEW_COLS
    add hl, de
    dec c
    jr nz, .vr
    ld hl, VRAM_MAP0 + 32 * HUD_ROW
    ld b, 32
    ld a, 3
.msg:
    ld [hl+], a
    dec b
    jr nz, .msg
    ld b, 32 * 3
    ld a, 2
.stat:
    ld [hl+], a
    dec b
    jr nz, .stat
    xor a
    ldh [rVBK], a
    ld hl, wHudRows
    ld b, 4 * HUD_W
.clr:
    ld [hl+], a
    dec b
    jr nz, .clr
    ld [wStatusMs], a
    ld [wStatusMs + 1], a
    ld [wHurtMs], a
    ld [wHurtMs + 1], a
    ld a, $FF                           ; force the first palette build
    ld [wPalBorder], a
    ld [wPalRoom], a
    call PaletteUpdate
    ld a, $80                           ; LCD is off: write the palettes now
    ldh [rBCPS], a
    ld hl, wPalStage
    ld b, 32
.pal:
    ld a, [hl+]
    ldh [rBCPD], a
    dec b
    jr nz, .pal
    xor a
    ld [wPalDirty], a
    ret

; ---- per frame -------------------------------------------------------------------------------

; Stats and keys into the shadow rows, message timer (A8 update_status), palettes.
HudUpdateB::
    ; A8 update_status: blank the message when STATUS_MS runs out
    ld a, [wStatusMs]
    ld b, a
    ld a, [wStatusMs + 1]
    or b
    jr z, .rows
    ld a, [wDtMs]
    ld b, a
    ld a, [wStatusMs]
    sub b
    ld [wStatusMs], a
    ld a, [wStatusMs + 1]
    sbc 0
    ld [wStatusMs + 1], a
    jr nc, .rows
    xor a
    ld [wStatusMs], a
    ld [wStatusMs + 1], a
    call MsgBlank
.rows:
    ld hl, wHudRows + HUD_R15           ; rows 15-17: spaces, then the fields
    ld b, 3 * HUD_W
    xor a
.blank:
    ld [hl+], a
    dec b
    jr nz, .blank
    ld hl, wHudRows + HUD_R15 + COL_AMMO    ; ammo column
    ld a, HUD_CH_BULLET - 32
    ld [hl+], a
    ld a, [wAmmoBul]
    call PutNum3
    ld hl, wHudRows + HUD_R16 + COL_AMMO
    ld a, HUD_CH_SHELL - 32
    ld [hl+], a
    ld a, [wAmmoShl]
    call PutNum3
    ld hl, wHudRows + HUD_R17 + COL_AMMO
    ld a, HUD_CH_ROCKET - 32
    ld [hl+], a
    ld a, [wAmmoRkt]
    call PutNum3
    ld hl, wHudRows + HUD_R16 + COL_HEALTH  ; health
    ld a, CH_HEALTH - 32
    ld [hl+], a
    ld a, [wHP]
    call PutNum3
    ld hl, wHudRows + HUD_R16 + COL_ARMOUR  ; armour
    ld a, CH_ARMOUR - 32
    ld [hl+], a
    ld a, [wArmor]
    call PutNum3
    ld hl, wHudRows + HUD_R17 + COL_ARMOUR - 1  ; frame time under the armour: "ms" + 3 digits
    ld a, 'm' - 32
    ld [hl+], a
    ld a, 's' - 32
    ld [hl+], a
    call FrameMs
    call PutNum3
    ld a, [wHaveKeys]                   ; key column, A8 hud_keys order: blue, yellow, red
    ld b, a
    bit 1, b                            ; HAVE_BLUE
    jr z, .noBlu
    ld a, HUD_CH_KEY_BLU - 32
    ld [wHudRows + HUD_R15 + COL_KEYS], a
.noBlu:
    bit 0, b                            ; HAVE_YELLOW
    jr z, .noYel
    ld a, HUD_CH_KEY_YEL - 32
    ld [wHudRows + HUD_R16 + COL_KEYS], a
.noYel:
    bit 2, b                            ; HAVE_RED
    jr z, PaletteUpdate
    ld a, HUD_CH_KEY_RED - 32
    ld [wHudRows + HUD_R17 + COL_KEYS], a
    ; fall through
ASSERT HAVE_YELLOW == 1 && HAVE_BLUE == 2 && HAVE_RED == 4

; A8 update_hurt_flash, then rebuild the staged palettes when the room or the border colour changed
; (A8 maybe_room_palette). HudBlit uploads them in VBlank.
PaletteUpdate:
    ld a, [wHurtMs]
    ld b, a
    ld a, [wHurtMs + 1]
    or b
    jr z, .border
    ld a, [wDtMs]
    ld b, a
    ld a, [wHurtMs]
    sub b
    ld [wHurtMs], a
    ld a, [wHurtMs + 1]
    sbc 0
    ld [wHurtMs + 1], a
    jr nc, .border
    xor a
    ld [wHurtMs], a
    ld [wHurtMs + 1], a
.border:
    ld a, [wPuMs]                       ; A8 update_powerup: the radsuit runs out
    ld b, a
    ld a, [wPuMs + 1]
    or b
    jr z, .puOff
    ld a, [wDtMs]
    ld b, a
    ld a, [wPuMs]
    sub b
    ld [wPuMs], a
    ld a, [wPuMs + 1]
    sbc 0
    ld [wPuMs + 1], a
    jr nc, .puOn
    xor a
    ld [wPuMs], a
    ld [wPuMs + 1], a
.puOff:
    xor a
    ld [wPuKind], a
.puOn:
    ld a, [wHurtMs]
    ld b, a
    ld a, [wHurtMs + 1]
    or b
    ld b, COL_HURT_A8                   ; COLBK: bright red while hurt, else dark green under the radsuit
    jr nz, .b
    ld b, A8_BLACK
    ld a, [wPuKind]
    and a
    jr z, .b
    ld b, COL_SUIT_A8
.b:
    ld a, [wPalBorder]
    cp b
    jr nz, .rebuild
    ld a, [wRoom]
    ld c, a
    ld a, [wPalRoom]
    cp c
    ret z
.rebuild:
    ld a, b
    ld [wPalBorder], a
    ld a, [wRoom]
    ld [wPalRoom], a
    ld c, ROOM_BG_DEFAULT
    cp $FF
    jr z, .bg
    ld c, a
    ld a, F_ROOM_BG
    call MapGet
    ld c, a                             ; C = A8 room paper
.bg:
    ld hl, wPalStage
    ld a, c                             ; palette 0: paper, ink (same hue, lum $C), red, black
    call PutA8
    ld a, c
    and $F0
    or $0C
    call PutA8
    ld a, A8_RED
    call PutA8
    ld a, A8_RED                        ; red over ink stays red (A8 stamps %10 over the pixel)
    call PutA8
    ld a, [wPalBorder]                  ; palette 1: border
    call PutA8
    ld a, A8_BLACK
    call PutA8
    ld a, A8_BLACK
    call PutA8
    ld a, A8_BLACK
    call PutA8
    ld a, HUD_PF2_STAT                  ; palette 2: stat rows
    call PutA8
    ld a, HUD_STAT_INK
    call PutA8
    ld a, HUD_STAT_INK
    call PutA8
    ld a, HUD_STAT_INK
    call PutA8
    ld a, HUD_PF2_STAT                  ; palette 3: message row
    call PutA8
    ld a, HUD_MSG_INK
    call PutA8
    ld a, HUD_MSG_INK
    call PutA8
    ld a, HUD_MSG_INK
    call PutA8
    ld a, 1
    ld [wPalDirty], a
    ret

; A = A8 colour byte, HL = dest -> BGR555 word, HL += 2. Keeps BC.
PutA8:
    srl a
    ld e, a
    ld d, 0
    push hl
    ld hl, A8Pal
    add hl, de
    add hl, de
    ld a, [hl+]
    ld d, [hl]
    pop hl
    ld [hl+], a
    ld a, d
    ld [hl+], a
    ret

; A = ms the last game frame took: wRawDt VBlanks * 16.75 (17n - n/4), 255 max. Keeps HL.
FrameMs:
    ld a, [wRawDt]
    cp 16
    jr c, .ok
    ld a, 255
    ret
.ok:
    ld b, a
    swap a
    add b                               ; 17 * n
    ld c, a
    ld a, b
    srl a
    srl a
    ld b, a
    ld a, c
    sub b                               ; - n / 4
    ret

; A = 0..255, HL = dest -> three digit tiles with leading zeros (A8 hud.asm), HL += 3.
PutNum3:
    ld b, '0' - 32
.h:
    cp 100
    jr c, .hd
    sub 100
    inc b
    jr .h
.hd:
    ld [hl], b
    inc hl
    ld b, '0' - 32
.t:
    cp 10
    jr c, .td
    sub 10
    inc b
    jr .t
.td:
    ld [hl], b
    inc hl
    add '0' - 32
    ld [hl+], a
    ret

; ---- message line ----------------------------------------------------------------------------

; A8 hud_msg_blank.
MsgBlank:
    ld hl, wHudRows + HUD_MSG
    ld b, HUD_W
    xor a
.l:
    ld [hl+], a
    dec b
    jr nz, .l
    ret

; HL = NUL-terminated text -> centred on the message row for STATUS_MS (A8 hud_msg_center + timer).
MsgShow:
    push hl
    call MsgBlank
    pop hl
    push hl
    ld b, 0
.len:
    ld a, [hl+]
    and a
    jr z, .got
    inc b
    ld a, b
    cp HUD_W
    jr c, .len
.got:
    ld a, HUD_W
    sub b
    srl a                               ; first column = (W - len) / 2
    ld e, a
    ld d, 0
    ld hl, wHudRows + HUD_MSG
    add hl, de
    ld d, h
    ld e, l
    pop hl
.cp:
    ld a, b
    and a
    jr z, .timer
    ld a, [hl+]
    sub 32
    ld [de], a
    inc de
    dec b
    jr .cp
.timer:
    ld a, LOW(STATUS_MS)
    ld [wStatusMs], a
    ld a, HIGH(STATUS_MS)
    ld [wStatusMs + 1], a
    ret

; A = TH_* type -> "+<name>" (A8 hud_got: "You got the <name>", shortened for 20 columns).
HudGotB::
    cp TH_NTYPES_
    ret nc
    add a
    ld e, a
    ld d, 0
    ld hl, ThNames
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, wMsgTmp
    ld bc, StrGot
.pre:
    ld a, [bc]
    inc bc
    and a
    jr z, .name
    ld [de], a
    inc de
    jr .pre
.name:
    ld a, [hl+]
    ld [de], a
    inc de
    and a
    jr nz, .name
    ld hl, wMsgTmp
    jr MsgShow

; A = door key (1 yellow, 2 blue, 4 red, 3 remote) -> A8 hud_key_req, shortened.
HudKeyReqB::
    ld hl, StrNeedRemote
    cp 3
    jr z, MsgShow
    ld hl, StrNeedBlue
    cp 2
    jr z, MsgShow
    ld hl, StrNeedRed
    cp 4
    jr z, MsgShow
    ld hl, StrNeedYellow
    jr MsgShow

StrGot:        db "+", 0
StrNeedYellow: db "Need a \\ keycard", 0
StrNeedBlue:   db "Need a ] keycard", 0
StrNeedRed:    db "Need a [ keycard", 0
StrNeedRemote: db "Opened elsewhere", 0

; A8 hud.asm thn_* (th_name_lo / hi), TH_* order.
ThNames:
    dw .hsm, .hlg, .ag, .ab, .bul, .shl, .rkt, .shot, .chain, .saw, .rl, .pack
    dw .red, .yel, .blu, .soul, .suit, .lamp, .barrel
.hsm:    db "stimpack", 0
.hlg:    db "medikit", 0
.ag:     db "security armor", 0
.ab:     db "combat armor", 0
.bul:    db "ammo box", 0
.shl:    db "shells", 0
.rkt:    db "box of rockets", 0
.shot:   db "shotgun", 0
.chain:  db "chaingun", 0
.saw:    db "chainsaw", 0
.rl:     db "rocket launcher", 0
.pack:   db "backpack", 0
.red:    db "[ keycard", 0
.yel:    db "\\ keycard", 0
.blu:    db "] keycard", 0
.soul:   db "soulsphere", 0
.suit:   db "radsuit", 0
.lamp:   db "lightpost", 0
.barrel: db "barrel", 0
