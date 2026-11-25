; Player collision, floor following and gravity against the current room's cache.
; Spec: tools/gbc_world.py (bit-exact). Port of src/world.asm static geometry; doors,
; elevators and enemies are not here yet.
;
; Conventions: the cell under test is wColX/wColZ (integer units). Box tests use wBox*.
; Routines return their result in carry. Loop indices live in C unless noted.

INCLUDE "hw.inc"
INCLUDE "map_fields.inc"

INCLUDE "en.inc"                    ; A8 PLAYER_H, STEP_UP, FALL_LEDGE, EN_*

DEF PLAYER_R     EQU 1
DEF FALL_ACCEL   EQU $10
DEF FALL_TICK_MS EQU 32

SECTION "collide", ROM0

; ---- primitives --------------------------------------------------------------------------

; [feet, feet+PLAYER_H) vs [wBoxY, wBoxY+wBoxSY). Carry = overlap. Clobbers A, B, D.
PlayerOverlapsY::
    ld a, [wBoxY]
    ld b, a
    ld a, [wBoxSY]
    add b
    ld d, a                         ; top (8-bit wrap, as on the 6502)
    ld a, [wCamY + 1]
    sub EYE_HEIGHT                  ; feet
    cp d
    jr nc, .no                      ; feet >= top
    add PLAYER_H
    ld d, a                         ; head
    ld a, b
    cp d
    jr nc, .no                      ; box_y >= head
    scf
    ret
.no:
    and a
    ret

; wColX/wColZ inside (wBoxX, wBoxZ, wBoxSX, wBoxSZ). Carry = inside.
; Exclusive max; PointInFloorXZ is inclusive. Clobbers A, B, D, E.
PointInBoxXZ::
    ld b, 0
    jr PibGo
PointInFloorXZ::
    ld b, 1
PibGo:
    ld a, [wBoxX]
    ld d, a
    ld a, [wColX]
    cp d
    jr c, .no                       ; col < box
    ld a, [wBoxSX]
    add d
    ld d, a                         ; top
    ld a, [wColX]
    cp d
    jr c, .xin                      ; col < top
    jr nz, .no                      ; col > top
    bit 0, b
    jr z, .no                       ; col == top, exclusive
.xin:
    ld a, [wBoxZ]
    ld d, a
    ld a, [wColZ]
    cp d
    jr c, .no
    ld a, [wBoxSZ]
    add d
    ld d, a
    ld a, [wColZ]
    cp d
    jr c, .zin
    jr nz, .no
    bit 0, b
    jr z, .no
.zin:
    scf
    ret
.no:
    and a
    ret

; C = collider k. Carry = player Y overlaps it. Preserves C. Clobbers A, B, D, HL.
RcOverlapsY:
    ld b, 0
    ld hl, wRcY
    add hl, bc
    ld a, [hl]
    ld [wBoxY], a
    ld hl, wRcSY
    add hl, bc
    ld a, [hl]
    ld [wBoxSY], a
    jp PlayerOverlapsY

; wJk = collider, wJf = face. Carry = some sibling sharing that face overlaps the player in Y,
; so the face is not inset. Clobbers A, B, C, D, E, HL.
JoinSkip:
    ld a, [wJk]
    add a
    add a
    ld b, a
    ld a, [wJf]
    add b
    ld e, a
    ld d, 0
    ld hl, wRcJ
    add hl, de
    ld a, [hl]
    and a
    ret z                           ; no sibling (carry clear)
    ld [wJmask], a
    ld c, 0
.loop:
    ld hl, .bits
    ld b, 0
    add hl, bc
    ld a, [wJmask]
    and [hl]
    jr z, .next
    call RcOverlapsY
    ret c
.next:
    inc c
    ld a, c
    cp 3
    jr nz, .loop
    and a
    ret
.bits:
    db 1, 2, 4

; C = collider k. Carry = (wColX, wColZ) is inside it, inset by PLAYER_R except on shared faces.
RcInsetOk:
    ld a, c
    ld [wJk], a
    ld b, 0
    ld hl, wRcSX
    add hl, bc
    ld a, [hl]
    and a
    jp z, .no
    call RcOverlapsY
    jp nc, .no
    ; ---- x min
    xor a
    ld [wJf], a
    call JoinSkip
    ld a, [wJk]
    ld c, a
    ld b, 0
    ld a, [wColX]
    jr c, .x0
    sub PLAYER_R
    jp c, .no
.x0:
    ld hl, wRcX
    add hl, bc
    ld d, [hl]
    cp d
    jp c, .no
    ; ---- x max
    ld hl, wRcX
    add hl, bc
    ld a, [hl]
    ld hl, wRcSX
    add hl, bc
    add [hl]
    ld [wVal], a
    ld a, 1
    ld [wJf], a
    call JoinSkip
    ld a, [wJk]
    ld c, a
    ld b, 0
    ld a, [wVal]
    jr c, .x1
    sub PLAYER_R
.x1:
    ld d, a
    ld a, [wColX]
    cp d
    jp nc, .no                      ; need col < top
    ; ---- z min
    ld a, 2
    ld [wJf], a
    call JoinSkip
    ld a, [wJk]
    ld c, a
    ld b, 0
    ld a, [wColZ]
    jr c, .z0
    sub PLAYER_R
    jp c, .no
.z0:
    ld hl, wRcZ
    add hl, bc
    ld d, [hl]
    cp d
    jp c, .no
    ; ---- z max
    ld hl, wRcZ
    add hl, bc
    ld a, [hl]
    ld hl, wRcSZ
    add hl, bc
    add [hl]
    ld [wVal], a
    ld a, 3
    ld [wJf], a
    call JoinSkip
    ld a, [wJk]
    ld c, a
    ld b, 0
    ld a, [wVal]
    jr c, .z1
    sub PLAYER_R
.z1:
    ld d, a
    ld a, [wColZ]
    cp d
    jp nc, .no
    scf
    ret
.no:
    and a
    ret

; Carry = (wColX, wColZ) inset-inside any collider of the current room.
InRoomInset::
    ld c, 0
.l:
    push bc
    call RcInsetOk
    pop bc
    ret c
    inc c
    ld a, c
    cp 3
    jr nz, .l
    and a
    ret

; Carry = some collider of the room contains the cell (exclusive max); wFloorTmp = lowest rc_y.
PeekRcFloor::
    xor a
    ld [wFound], a
    ld c, 0
.l:
    ld b, 0
    ld hl, wRcSX
    add hl, bc
    ld a, [hl]
    and a
    jr z, .next
    ld [wBoxSX], a
    ld hl, wRcX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wRcZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wRcSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInBoxXZ
    jr nc, .next
    ld b, 0
    ld hl, wRcY
    add hl, bc
    ld d, [hl]
    ld a, [wFound]
    and a
    jr nz, .min
    ld a, d
    ld [wFloorTmp], a
    ld a, 1
    ld [wFound], a
    jr .next
.min:
    ld a, [wFloorTmp]
    ld e, a
    ld a, d
    cp e
    jr nc, .next
    ld [wFloorTmp], a
.next:
    inc c
    ld a, c
    cp 3
    jr nz, .l
    ld a, [wFound]
    rra                             ; found (1) -> carry
    ret

; Carry = the destination floor is no more than STEP_UP above the feet (or there is none).
StepUpOk::
    call PeekRcFloor
    jr nc, .yes
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld b, a                         ; feet
    ld a, [wFloorTmp]
    cp b
    jr z, .yes
    jr c, .yes                      ; destination lower or level
    sub b
    cp STEP_UP + 1
    jr c, .yes
    and a
    ret
.yes:
    scf
    ret

; Carry = a crate wall blocks the cell (rise above STEP_UP).
CratesBlock:
    ld a, [wCrN]
    and a
    jr z, .no
    ld c, 0
.l:
    ld b, 0
    ld hl, wCrY
    add hl, bc
    ld a, [hl]
    ld [wBoxY], a
    ld hl, wCrSY
    add hl, bc
    ld a, [hl]
    ld [wBoxSY], a
    call PlayerOverlapsY
    jr nc, .next
    ld a, [wBoxY]
    ld b, a
    ld a, [wBoxSY]
    add b
    ld b, a                         ; crate top
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld d, a                         ; feet
    ld a, b
    sub d                           ; rise
    cp STEP_UP + 1
    jr c, .next                     ; step-up, not a wall
    ld b, 0
    ld hl, wCrX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wCrZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wCrSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wCrSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInBoxXZ
    jr c, .yes
.next:
    inc c
    ld a, [wCrN]
    ld b, a
    ld a, c
    cp b
    jr nz, .l
.no:
    and a
    ret
.yes:
    scf
    ret

; Carry = a solid platform plane blocks the cell.
PlatsBlock:
    ld a, [wPlN]
    and a
    jr z, .no
    ld c, 0
.l:
    ld b, 0
    ld hl, wPlY
    add hl, bc
    ld a, [hl]
    ld [wBoxY], a
    xor a
    ld [wBoxSY], a
    call PlayerOverlapsY
    jr nc, .next
    ld a, [wBoxY]
    ld b, a
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld d, a                         ; feet
    ld a, b
    sub d                           ; rise
    cp STEP_UP + 1
    jr c, .next
    ld b, 0
    ld hl, wPlX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wPlZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wPlSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wPlSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInBoxXZ
    jr c, .yes
.next:
    inc c
    ld a, [wPlN]
    ld b, a
    ld a, c
    cp b
    jr nz, .l
.no:
    and a
    ret
.yes:
    scf
    ret

; Carry = blocked by a crate, a solid platform or a locked door.
SolidAt::
    call CratesBlock
    ret c
    call PlatsBlock
    ret c
    jp DoorBlocks

; Carry = the player may stand at (wColX, wColZ).
PosOk::
    call InRoomInset
    ret nc
    ld a, BANK(EnemiesBlockPlayer)  ; A8 pos_ok: enemies_block_player (gbc/ai.asm)
    ld [rROMB0], a
    call EnemiesBlockPlayer
    ld a, [wLevelBank]              ; the level bank stays mapped (LoadLevel)
    ld [rROMB0], a
    ret nc
    call SolidAt
    jr c, .no
    jp StepUpOk
.no:
    and a
    ret

; ---- movement ----------------------------------------------------------------------------

; Slide on X then Z by the accumulated wish. No movement while falling.
ApplyWish::
    xor a
    ld [wDoorBlk], a
    ld a, [wFalling]
    and a
    ret nz
    ld a, [wCamX + 1]               ; A8 save_xh / save_zh for enemies_block_player
    ld [wPreX], a
    ld a, [wCamZ + 1]
    ld [wPreZ], a
    ld a, [wWishX]
    ld b, a
    ld a, [wWishX + 1]
    or b
    jr z, .z
    ld a, [wCamX]
    ld [wSaveX], a
    ld a, [wCamX + 1]
    ld [wSaveX + 1], a
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
    ld a, [wCamX + 1]
    ld [wColX], a
    ld a, [wCamZ + 1]
    ld [wColZ], a
    call PosOk
    jr c, .z
    ld a, [wSaveX]
    ld [wCamX], a
    ld a, [wSaveX + 1]
    ld [wCamX + 1], a
    ld a, [wDoorBlk]
    or 1
    ld [wDoorBlk], a
.z:
    ld a, [wCamX + 1]
    ld [wPreX], a
    ld a, [wWishZ]
    ld b, a
    ld a, [wWishZ + 1]
    or b
    ret z
    ld a, [wCamZ]
    ld [wSaveX], a
    ld a, [wCamZ + 1]
    ld [wSaveX + 1], a
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
    ld a, [wCamX + 1]
    ld [wColX], a
    ld a, [wCamZ + 1]
    ld [wColZ], a
    call PosOk
    ret c
    ld a, [wSaveX]
    ld [wCamZ], a
    ld a, [wSaveX + 1]
    ld [wCamZ + 1], a
    ld a, [wDoorBlk]
    or 2
    ld [wDoorBlk], a
    ret

; ---- floor -------------------------------------------------------------------------------

; A = surface y (caller checked y > floor_y). Carry = adopt: feet >= y, or rise <= STEP_UP.
; Clobbers A, B, D.
AdoptTest:
    ld b, a
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld d, a                         ; feet
    cp b
    jr nc, .yes                     ; feet >= y
    ld a, b
    sub d
    cp STEP_UP + 1
    jr c, .yes
    and a
    ret
.yes:
    scf
    ret

; C = slope index. wSlYv = integer surface, wFrac = fraction.
SlopeHeight::
    ld a, c
    ld [wSlI], a
    ld b, 0
    ld hl, wSlAxis
    add hl, bc
    ld a, [hl]
    and a
    jr nz, .z
    ld hl, wSlX
    add hl, bc
    ld a, [wCamX + 1]
    sub [hl]
    ld d, a                         ; yhi
    ld a, [wCamX]
    ld e, a                         ; ylo
    ld hl, wSlSX
    add hl, bc
    ld a, [hl]
    ld [wRun], a
    jr .have
.z:
    ld hl, wSlZ
    add hl, bc
    ld a, [wCamZ + 1]
    sub [hl]
    ld d, a
    ld a, [wCamZ]
    ld e, a
    ld hl, wSlSZ
    add hl, bc
    ld a, [hl]
    ld [wRun], a
.have:
    ld hl, wSlDir
    add hl, bc
    ld a, [hl]
    and a
    jr nz, .nodir
    ld a, 0
    sub e
    ld e, a
    ld a, [wRun]
    sbc d
    ld d, a                         ; run*256 - pos
.nodir:
    ld a, [wRun]
    and a
    jr z, .flat
    ld hl, wSlSY
    add hl, bc
    ld a, [hl]
    ld b, a                         ; sy
    push de
    ld a, e
    call Mul8u                      ; ylo * sy
    ld a, l
    ldh [hT0], a
    ld a, h
    ldh [hT1], a
    pop de
    ld a, d
    call Mul8u                      ; yhi * sy
    ldh a, [hT1]
    add l
    ldh [hT1], a
    ld a, h
    adc 0
    ldh [hT2], a
    ldh a, [hT0]
    ld e, a
    ldh a, [hT1]
    ld d, a
    ldh a, [hT2]
    ld b, a
    ld a, [wRun]
    ld c, a
    call Div24x8                    ; DE = sy * pos / run
    ld a, e
    ld [wFrac], a
    ld a, [wSlI]
    ld c, a
    ld b, 0
    ld hl, wSlY
    add hl, bc
    ld a, [hl]
    add d
    ld [wSlYv], a
    ret
.flat:
    xor a
    ld [wFrac], a
    ld a, [wSlI]
    ld c, a
    ld b, 0
    ld hl, wSlY
    add hl, bc
    ld a, [hl]
    ld [wSlYv], a
    ret

UpdateFloor::
    ld a, [wOnElev]                 ; A8 update_floor: the car we rode last frame, then none
    ld [wPrevElev], a
    ld a, $FF
    ld [wOnElev], a
    xor a
    ld [wFloorYL], a
    ld [wFloorSlope], a
    ld a, [wCamX + 1]
    ld [wColX], a
    ld a, [wCamZ + 1]
    ld [wColZ], a
    call PeekRcFloor
    jr nc, .noRc
    ld a, [wFloorTmp]
    ld [wFloorY], a
.noRc:
    ; ---- crate tops
    ld a, [wCrN]
    and a
    jr z, .plats
    ld c, 0
.cr:
    ld b, 0
    ld hl, wCrX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wCrZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wCrSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wCrSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInFloorXZ
    jr nc, .crn
    ld b, 0
    ld hl, wCrY
    add hl, bc
    ld a, [hl]
    ld hl, wCrSY
    add hl, bc
    add [hl]
    ld [wTmpY], a                   ; top
    ld b, a
    ld a, [wFloorY]
    ld d, a
    ld a, b
    cp d
    jr z, .crn
    jr c, .crn                      ; top <= floor_y
    ld a, b
    call AdoptTest
    jr nc, .crn
    ld a, [wTmpY]
    ld [wFloorY], a
.crn:
    inc c
    ld a, [wCrN]
    ld b, a
    ld a, c
    cp b
    jr nz, .cr
.plats:
    ld a, [wPlN]
    and a
    jr z, .slopes
    ld c, 0
.pl:
    ld b, 0
    ld hl, wPlX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wPlZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wPlSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wPlSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInFloorXZ
    jr nc, .pln
    ld b, 0
    ld hl, wPlY
    add hl, bc
    ld a, [hl]
    ld [wTmpY], a
    ld b, a
    ld a, [wFloorY]
    ld d, a
    ld a, b
    cp d
    jr z, .pln
    jr c, .pln                      ; plane <= floor_y
    ld a, b
    call AdoptTest
    jr nc, .pln
    ld a, [wTmpY]
    ld [wFloorY], a
.pln:
    inc c
    ld a, [wPlN]
    ld b, a
    ld a, c
    cp b
    jr nz, .pl
.slopes:
    ld a, BANK(ElevFloorB)          ; elevator tops (gbc/level.asm), then the slopes
    ld [rROMB0], a
    call ElevFloorB
    ld a, [wLevelBank]
    ld [rROMB0], a
    ld a, [wSlN]
    and a
    ret z
    ld c, 0
.sl:
    ld a, c
    ld [wSlI], a
    ld b, 0
    ld hl, wSlX
    add hl, bc
    ld a, [hl]
    ld [wBoxX], a
    ld hl, wSlZ
    add hl, bc
    ld a, [hl]
    ld [wBoxZ], a
    ld hl, wSlSX
    add hl, bc
    ld a, [hl]
    ld [wBoxSX], a
    ld hl, wSlSZ
    add hl, bc
    ld a, [hl]
    ld [wBoxSZ], a
    call PointInFloorXZ
    jr nc, .sln
    call SlopeHeight                ; clobbers C; index is in wSlI
    ld a, [wSlYv]
    ld e, a                         ; cy
    ld a, [wFloorY]
    ld d, a
    ld a, e
    cp d
    jr c, .sln                      ; below the current floor
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld d, a                         ; feet
    ld a, e
    cp d
    jr z, .adopt
    jr c, .adopt                    ; cy <= feet
    sub d                           ; rise
    cp STEP_UP + 1
    jr nc, .sln
.adopt:
    ld a, e
    ld [wFloorY], a
    ld a, [wFrac]
    ld [wFloorYL], a
    xor a
    ld [wFloorSlope], a
    ld a, d
    cp e
    jr c, .sln                      ; step-up: not a ramp ride
    sub e                           ; gap
    cp FALL_LEDGE + 1
    jr nc, .sln
    ld a, 1
    ld [wFloorSlope], a
.sln:
    ld a, [wSlI]
    ld c, a
    inc c
    ld a, [wSlN]
    ld b, a
    ld a, c
    cp b
    jr nz, .sl
    ret

SyncEye::
    ld a, [wFloorY]
    add EYE_HEIGHT
    ld [wCamY + 1], a
    ld a, [wFloorYL]
    ld [wCamY], a
    ret

; ---- ledge unstick -----------------------------------------------------------------------

; A = cam coordinate, B = delta (0, 1, 255). Carry = would wrap; else A = coordinate + delta.
LedgeAxis:
    ld c, a
    ld a, b
    and a
    jr z, .same
    cp 1
    jr z, .inc
    ld a, c
    and a
    jr z, .wrap
    dec a
    and a
    ret
.inc:
    ld a, c
    cp $FF
    jr z, .wrap
    inc a
    and a
    ret
.same:
    ld a, c
    and a
    ret
.wrap:
    scf
    ret

LedgeDX:
    db $FF, 1, 0, 0, $FF, 1, $FF, 1
LedgeDZ:
    db 0, 0, $FF, 1, $FF, $FF, 1, 1

; The landed eye is inside the room box but outside the PLAYER_R inset: step to the first
; neighbouring cell (cardinals, then diagonals) that is walkable at floor_y.
LedgeUnstick::
    ld a, [wCamY + 1]
    ld [wLedgeSaveY], a
    ld a, [wFloorY]
    add EYE_HEIGHT
    ld [wCamY + 1], a
    ld a, [wCamX + 1]
    ld [wColX], a
    ld a, [wCamZ + 1]
    ld [wColZ], a
    call InRoomInset
    jr c, .out
    xor a
    ld [wLedgeI], a
.n:
    ld a, [wLedgeI]
    ld e, a
    ld d, 0
    ld hl, LedgeDX
    add hl, de
    ld a, [hl]
    ld b, a
    ld a, [wCamX + 1]
    call LedgeAxis
    jr c, .skip
    ld [wColX], a
    ld a, [wLedgeI]
    ld e, a
    ld d, 0
    ld hl, LedgeDZ
    add hl, de
    ld a, [hl]
    ld b, a
    ld a, [wCamZ + 1]
    call LedgeAxis
    jr c, .skip
    ld [wColZ], a
    call InRoomInset
    jr nc, .skip
    call StepUpOk
    jr nc, .skip
    call SolidAt
    jr c, .skip
    jr .take
.skip:
    ld a, [wLedgeI]
    inc a
    ld [wLedgeI], a
    cp 8
    jr nz, .n
    jr .out
.take:
    ld a, [wCamX + 1]
    ld d, a                         ; old x
    ld a, [wColX]
    cp d
    jr z, .tz
    ld [wCamX + 1], a
    ld a, 0
    jr nc, .fx
    ld a, $FF                       ; moved down: park on the near edge
.fx:
    ld [wCamX], a
.tz:
    ld a, [wCamZ + 1]
    ld d, a
    ld a, [wColZ]
    cp d
    jr z, .out
    ld [wCamZ + 1], a
    ld a, 0
    jr nc, .fz
    ld a, $FF
.fz:
    ld [wCamZ], a
.out:
    ld a, [wLedgeSaveY]
    ld [wCamY + 1], a
    ret

; ---- gravity -----------------------------------------------------------------------------

; Snap to the floor, step up, or fall (FALL_ACCEL every FALL_TICK_MS). Uses wMoveDt (VBlanks).
UpdateFall::
    ld a, [wMoveDt]
    ld b, a
    swap a
    add b                           ; dt * 17 ms
    ld [wDtMs], a
    ld a, [wFalling]
    and a
    jr nz, .air
    ld a, [wFloorSlope]
    and a
    jr nz, .sync
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld b, a                         ; feet
    ld a, [wFloorY]
    cp b
    jr z, .sync
    jr nc, .up                      ; floor above the feet
    ld a, b
    ld c, a
    ld a, [wFloorY]
    ld d, a
    ld a, c
    sub d                           ; gap
    cp FALL_LEDGE + 1
    jr c, .sync
    call LedgeUnstick
    ld a, 1
    ld [wFalling], a
    xor a
    ld [wFallVL], a
    ld [wFallVH], a
    ld [wFallAcc], a
    ld a, [wCamY + 1]
    ld [wFallY0], a
    jr .air
.up:
    ld a, [wOnElev]
    inc a
    jr nz, .sync                    ; riding an elevator: always snap
    ld a, [wFloorY]
    sub b                           ; rise
    cp STEP_UP + 1
    ret nc
.sync:
    call LedgeUnstick
    jp SyncEye
.air:
    ld a, [wFallAcc]
    ld b, a
    ld a, [wDtMs]
    add b
    ld [wAcc], a
.tick:
    ld a, [wAcc]
    cp FALL_TICK_MS
    jr c, .done
    sub FALL_TICK_MS
    ld [wAcc], a
    ld a, [wFallVL]
    add FALL_ACCEL
    ld [wFallVL], a
    ld a, [wFallVH]
    adc 0
    ld [wFallVH], a
    ld a, [wCamY]
    ld b, a
    ld a, [wFallVL]
    ld c, a
    ld a, b
    sub c
    ld [wCamY], a
    ld a, [wCamY + 1]
    ld b, a
    ld a, [wFallVH]
    ld c, a
    ld a, b
    sbc c
    ld [wCamY + 1], a
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld b, a
    ld a, [wFloorY]
    cp b
    jr nc, .land                    ; feet <= floor
    jr .tick
.done:
    ld a, [wAcc]
    ld [wFallAcc], a
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld b, a
    ld a, [wFloorY]
    cp b
    ret c                           ; still above the floor
.land:
    call SyncEye
    xor a
    ld [wFalling], a
    ld [wFallVL], a
    ld [wFallVH], a
    ld [wFallAcc], a
    ld a, [wFallY0]                 ; A8: eye drop over FALL_SAFE hurts FALL_DAMAGE
    ld b, a
    ld a, [wCamY + 1]
    ld c, a
    ld a, b
    sub c
    cp FALL_SAFE + 1
    ret c
    ld a, FALL_DAMAGE
    jp PlayerDamage
