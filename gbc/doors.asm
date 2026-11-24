; Doors: locks, blocking and room transit. Spec: tools/gbc_world.py (door_* / try_door_wish).
;
; In the A8 engine a door has no open/close animation. An unlocked door is a passage: a
; wall-ward move that was blocked is tested against the door slab, and with forward held, the
; right heading and the key the player is placed just past the slab in the other room. Locked
; doors are solid (SolidAt -> DoorBlocks). door_key / door_type are read from the payload
; (WRAM bank 2) so switches and triggers can change them later.

INCLUDE "hw.inc"
INCLUDE "map_fields.inc"

DEF HAVE_YELLOW  EQU 1
DEF HAVE_BLUE    EQU 2
DEF HAVE_RED     EQU 4
DEF DOOR_Y_SLACK EQU 1
DEF DOOR_AIM     EQU 32

SECTION "doors", ROM0

; A = global door index. Carry = unlocked: no key needed, or the player holds it.
; Remote doors (key 3) open only from a switch / trigger (payload door_key cleared).
DoorUnlocked::
    ld c, a
    ld a, F_DOOR_KEY
    call MapGet
    and a
    jr z, .yes
    cp 3
    jr z, .no
    cp 2
    jr z, .blue
    cp 4
    jr z, .red
    ld a, [wHaveKeys]
    and HAVE_YELLOW
    jr z, .no
    jr .yes
.blue:
    ld a, [wHaveKeys]
    and HAVE_BLUE
    jr z, .no
    jr .yes
.red:
    ld a, [wHaveKeys]
    and HAVE_RED
    jr z, .no
.yes:
    scf
    ret
.no:
    and a
    ret

; Carry = (wColX, wColZ) inside a locked door slab of this room.
DoorBlocks::
    ld a, [wDrN]
    and a
    jr z, .no
    xor a
    ld [wDoorI], a
.l:
    ld a, [wDoorI]
    ld e, a
    ld d, 0
    ld hl, wDrIdx
    add hl, de
    ld a, [hl]
    call DoorUnlocked
    jr c, .next
    ld a, [wDoorI]
    ld c, a
    ld b, 0
    ld hl, wDrX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wDrZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wDrSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wDrSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInBoxXZ
    jr c, .yes
.next:
    ld a, [wDoorI]
    inc a
    ld [wDoorI], a
    ld b, a
    ld a, [wDrN]
    cp b
    jr nz, .l
.no:
    and a
    ret
.yes:
    scf
    ret

; Carry = |feet - door_y| <= DOOR_Y_SLACK for door wDoorI.
DoorYOk:
    ld a, [wDoorI]
    ld c, a
    ld b, 0
    ld hl, wDrY
    add hl, bc
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    sub [hl]
    cp DOOR_Y_SLACK + 1
    jr c, .yes
    cp 256 - DOOR_Y_SLACK
    jr c, .no
.yes:
    scf
    ret
.no:
    and a
    ret

; Through-heading per face: PZ, MZ, PX, MX.
ThruYaw:
    db 128, 0, 192, 64

; Carry = forward held, yaw within DOOR_AIM of the through-heading, wish pointing through
; door wDoorI.
DoorThru:
    ldh a, [hJoy]
    bit 2, a
    jr z, .no
    ld a, [wDoorI]
    ld c, a
    ld b, 0
    ld hl, wDrFace
    add hl, bc
    ld a, [hl]
    ld [wVal], a
    and 3
    ld e, a
    ld d, 0
    ld hl, ThruYaw
    add hl, de
    ld a, [hl]
    ld b, a
    ld a, [wYaw]
    sub b
    cp 128
    jr c, .aim
    cpl
    inc a
.aim:
    cp DOOR_AIM + 1
    jr nc, .no
    ld a, [wVal]
    bit 1, a
    jr nz, .xax
    ld a, [wWishZ]
    ld c, a
    ld a, [wWishZ + 1]
    jr .have
.xax:
    ld a, [wWishX]
    ld c, a
    ld a, [wWishX + 1]
.have:
    ld b, a                         ; wish high byte, C = low byte
    ld a, [wVal]
    bit 0, a
    jr nz, .minus
    bit 7, b
    jr nz, .yes                     ; plus face: wish toward -axis
    jr .no
.minus:
    ld a, b
    or c
    jr z, .no
    bit 7, b
    jr nz, .no
.yes:
    scf
    ret
.no:
    and a
    ret

; Put the player just past the slab of door wDoorI on its through axis (fraction 0).
DoorSnap:
    ld a, [wDoorI]
    ld c, a
    ld b, 0
    ld hl, wDrFace
    add hl, bc
    ld a, [hl]
    ld [wVal], a
    bit 1, a
    jr nz, .x
    ld hl, wDrZ
    add hl, bc
    ld a, [hl]
    ld d, a
    ld a, [wVal]
    bit 0, a
    jr nz, .zminus
    ld a, d
    sub 2
    jr nc, .zset
    xor a
    jr .zset
.zminus:
    ld hl, wDrSZ
    add hl, bc
    ld a, d
    add [hl]
    inc a
.zset:
    ld [wCamZ + 1], a
    xor a
    ld [wCamZ], a
    ret
.x:
    ld hl, wDrX
    add hl, bc
    ld a, [hl]
    ld d, a
    ld a, [wVal]
    bit 0, a
    jr nz, .xminus
    ld a, d
    sub 2
    jr nc, .xset
    xor a
    jr .xset
.xminus:
    ld hl, wDrSX
    add hl, bc
    ld a, d
    add [hl]
    inc a
.xset:
    ld [wCamX + 1], a
    xor a
    ld [wCamX], a
    ret

; A blocked wall-ward wish may pass through an unlocked, visible door. Carry = transited
; (room, mesh and cache switched). Uses wDoorBlk from ApplyWish and the wish from ApplyInput.
TryDoorWish::
    ld a, [wDoorBlk]
    and a
    ret z
    ld a, [wWishX]
    ld b, a
    ld a, [wWishX + 1]
    or b
    ld b, a
    ld a, [wWishZ]
    or b
    ld b, a
    ld a, [wWishZ + 1]
    or b
    ret z
    ld a, [wCamX]
    ld [wTdwSave], a
    ld a, [wCamX + 1]
    ld [wTdwSave + 1], a
    ld a, [wCamZ]
    ld [wTdwSave + 2], a
    ld a, [wCamZ + 1]
    ld [wTdwSave + 3], a
    ld a, [wDoorBlk]
    bit 0, a
    jr z, .noX
    ld a, [wCamX]
    ld b, a
    ld a, [wWishX]
    add b
    ld [wCamX], a
    ld a, [wCamX + 1]
    ld b, a
    ld a, [wWishX + 1]
    adc b
    ld [wCamX + 1], a
.noX:
    ld a, [wDoorBlk]
    bit 1, a
    jr z, .scan
    ld a, [wCamZ]
    ld b, a
    ld a, [wWishZ]
    add b
    ld [wCamZ], a
    ld a, [wCamZ + 1]
    ld b, a
    ld a, [wWishZ + 1]
    adc b
    ld [wCamZ + 1], a
.scan:
    ld a, [wDrN]
    and a
    jp z, .miss
    xor a
    ld [wDoorI], a
.l:
    ld a, [wDoorI]
    ld e, a
    ld d, 0
    ld hl, wDrIdx
    add hl, de
    ld a, [hl]
    ld c, a
    ld a, F_DOOR_TYPE
    call MapGet
    bit 7, a
    jr nz, .next                    ; hidden: not a candidate
    ld a, [wDoorI]
    ld c, a
    ld b, 0
    ld hl, wDrX
    add hl, bc
    ld a, [hl]
    and a
    jr z, .x0
    dec a
.x0:
    ld [wBoxX], a
    ld hl, wDrSX
    add hl, bc
    ld a, [hl]
    add 2
    ld [wBoxSX], a
    ld hl, wDrZ
    add hl, bc
    ld a, [hl]
    and a
    jr z, .z0
    dec a
.z0:
    ld [wBoxZ], a
    ld hl, wDrSZ
    add hl, bc
    ld a, [hl]
    add 2
    ld [wBoxSZ], a
    ld a, [wCamX + 1]
    ld [wColX], a
    ld a, [wCamZ + 1]
    ld [wColZ], a
    call PointInBoxXZ
    jr nc, .next
    call DoorYOk
    jr nc, .next
    call DoorThru
    jr nc, .next
    ld a, [wDoorI]
    ld e, a
    ld d, 0
    ld hl, wDrIdx
    add hl, de
    ld a, [hl]
    call DoorUnlocked
    jr nc, .locked
    ld a, [wDoorI]
    ld e, a
    ld d, 0
    ld hl, wDrOther
    add hl, de
    ld a, [hl]
    cp $FF
    jr z, .next
    push af
    call DoorSnap
    pop af
    call EnterRoom
    xor a
    ld [wDoorBlk], a
    scf
    ret
.next:
    ld a, [wDoorI]
    inc a
    ld [wDoorI], a
    ld b, a
    ld a, [wDrN]
    cp b
    jp nz, .l
.miss:
    ld a, [wTdwSave]
    ld [wCamX], a
    ld a, [wTdwSave + 1]
    ld [wCamX + 1], a
    ld a, [wTdwSave + 2]
    ld [wCamZ], a
    ld a, [wTdwSave + 3]
    ld [wCamZ + 1], a
    and a
    ret
.locked:                            ; A8 door.asm .tdw_lock: hud_key_req, then the miss path
    ld a, [wDoorI]
    ld e, a
    ld d, 0
    ld hl, wDrIdx
    add hl, de
    ld c, [hl]
    ld a, F_DOOR_KEY
    call MapGet
    call HudKeyReq
    jr .miss
