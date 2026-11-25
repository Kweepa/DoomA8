; Level mechanics (A8 src/world.asm try_proximity / fire_switch / update_triggers / trig_enter,
; src/door.asm door_unlock_tag / door_hide_tag / door_unhide_tag / door_unhide_tick): switches that are
; bumped, trigger volumes, remote doors, spawn / unhide / unlock / hurt / end triggers. ROMX bank; the
; ROM0 stub LevelUpdate (combat.asm) maps it, and performs the level change itself (LoadLevel remaps
; banks, so banked code can only ask for it with wNextLevelReq).
; Not ported: message triggers (the map text is not in the GBC payload; every shipped message trigger has
; empty text), elevator triggers / switches until elevators (gbc/elev in this file when added).

INCLUDE "hw.inc"
INCLUDE "sndids.inc"
INCLUDE "map_fields.inc"
INCLUDE "en.inc"

SECTION "level", ROMX

; A = field, C = index, B = value -> the map payload byte (WRAM bank 2). Keeps BC.
MapPut:
    add a
    ld l, a
    ld h, HIGH(wFieldPtr)
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, c
    add l
    ld l, a
    ld a, h
    adc 0
    ld h, a
    ld a, 2
    ldh [rSVBK], a
    ld [hl], b
    ld a, 1
    ldh [rSVBK], a
    ret

LevelUpdateB::
    call TryProximity
    call CrackClearBorn
    call UpdateTriggers
    call ElevTick
    jp DoorUnhideTick

; ---- doors by tag ---------------------------------------------------------------------------------

; A = tag: every remote door with that tag loses its lock and its hidden bit. Carry = at least one.
DoorUnlockTag:
    ld [wLvTag], a
    xor a
    ld [wLvCnt], a
    ld a, [wMapHdr + H_NDOORS]
    and a
    jr z, .done
    ld [wLvN], a
    ld c, 0
.l:
    ld a, F_DOOR_TAG
    call MapGet
    ld b, a
    ld a, [wLvTag]
    cp b
    jr nz, .n
    ld a, F_DOOR_KEY
    call MapGet
    cp DOOR_KEY_REMOTE
    jr nz, .n
    ld b, 0
    ld a, F_DOOR_KEY
    call MapPut
    ld a, F_DOOR_TYPE
    call MapGet
    and $FF - DOOR_HIDDEN
    ld b, a
    ld a, F_DOOR_TYPE
    call MapPut
    ld hl, wLvCnt
    inc [hl]
.n:
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .l
.done:
    ld a, [wLvCnt]
    cp 1
    ccf
    ret

; A = tag, wUhHide: set (1) or clear (0) DOOR_HIDDEN on every door of that tag.
DoorHideTag:
    ld [wLvTag], a
    ld a, [wMapHdr + H_NDOORS]
    and a
    ret z
    ld [wLvN], a
    xor a
    ld [wDhChg], a
    ld c, 0
.l:
    ld a, F_DOOR_TAG
    call MapGet
    ld b, a
    ld a, [wLvTag]
    cp b
    jr nz, .n
    ld a, F_DOOR_TYPE
    call MapGet
    ld b, a
    ld a, [wUhHide]
    and a
    ld a, b
    jr nz, .hide
    and $FF - DOOR_HIDDEN
    jr .st
.hide:
    or DOOR_HIDDEN
.st:
    cp b
    ld b, a
    jr z, .put
    ld a, 1                          ; a hidden bit flipped
    ld [wDhChg], a
.put:
    ld a, F_DOOR_TYPE
    call MapPut
.n:
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .l
    ld a, [wDhChg]                   ; A8 door_hide_tag: one open / close sound if a bit flipped
    and a
    ret z
    ld a, SND_DOROPN
    ld hl, wUhHide
    ld b, [hl]
    inc b
    dec b
    jr z, .snd
    ld a, SND_DORCLS
.snd:
    jp PlaySound

; A = tag: show those doors for DOOR_UNHIDE_MS (entering again restarts the timer).
DoorUnhideTag:
    ld [wLvTag], a
    ld c, 0
.find:
    ld hl, wUhTag
    ld b, 0
    add hl, bc
    ld a, [hl]
    ld d, a
    ld a, [wLvTag]
    cp d
    jr z, .arm
    inc c
    ld a, c
    cp UNHIDE_MAX
    jr nz, .find
    ld c, 0
.free:
    ld hl, wUhTag
    ld b, 0
    add hl, bc
    ld a, [hl]
    and a
    jr z, .take
    inc c
    ld a, c
    cp UNHIDE_MAX
    jr nz, .free
    ret                              ; no free slot: leave them hidden
.take:
    ld a, [wLvTag]
    ld [hl], a
.arm:
    ld b, 0
    ld hl, wUhLo
    add hl, bc
    ld [hl], LOW(DOOR_UNHIDE_MS)
    ld hl, wUhHi
    add hl, bc
    ld [hl], HIGH(DOOR_UNHIDE_MS)
    xor a
    ld [wUhHide], a
    ld a, [wLvTag]
    jp DoorHideTag

; One frame off each live unhide timer; expired ones hide their doors again.
DoorUnhideTick:
    ld c, 0
.l:
    ld b, 0
    ld hl, wUhTag
    add hl, bc
    ld a, [hl]
    and a
    jr z, .n
    ld a, [wDtMs]
    ld e, a
    push hl
    ld hl, wUhLo
    add hl, bc
    ld a, [hl]
    sub e
    ld [hl], a
    ld hl, wUhHi
    add hl, bc
    ld a, [hl]
    sbc 0
    ld [hl], a
    pop hl
    jr nc, .n
    ld a, [hl]
    ld [hl], 0
    push bc
    ld d, a
    ld a, 1
    ld [wUhHide], a
    ld a, d
    call DoorHideTag
    pop bc
.n:
    inc c
    ld a, c
    cp UNHIDE_MAX
    jr nz, .l
    ret

; ---- triggers -------------------------------------------------------------------------------------

; A = enable tag (1..15): clear the gate bits of every trigger waiting on it.
TrigArmTag:
    ld [wLvTag], a
    ld a, [wMapHdr + H_NTRIGS]
    and a
    ret z
    ld [wLvN], a
    ld c, 0
.l:
    ld a, F_TR_PURPOSE
    call MapGet
    ld b, a
    swap a
    and $0F
    ld d, a
    ld a, [wLvTag]
    cp d
    jr nz, .n
    ld a, b
    and TRIG_PURPOSE_MASK
    ld b, a
    ld a, F_TR_PURPOSE
    call MapPut
.n:
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .l
    ret

; Every trigger of the player's room: enter fires once per visit, hurt triggers tick while inside.
; wTrigInside bit = the room-local trigger index.
UpdateTriggers:
    xor a
    ld [wTrigSeen], a
    ld a, [wRoom]
    ld c, a
    ld a, F_ROOM_TRIG_O
    call MapGet
    ld [wLvI], a
    ld a, [wRoom]
    inc a
    ld c, a
    ld a, F_ROOM_TRIG_O
    call MapGet
    ld [wLvEnd], a
    ld a, 1
    ld [wLvMask], a
.ut:
    ld a, [wLvI]
    ld hl, wLvEnd
    cp [hl]
    ret nc
    ld c, a
    ld a, F_TR_PURPOSE
    call MapGet
    ld [wLvPur], a
    and TRIG_GATED_MASK
    jp nz, .out                      ; gated: no fire
    ld hl, wBoxX                     ; the volume
    ld a, F_TR_X
    ld b, 6
.box:
    push af
    push hl
    push bc
    call MapGet
    pop bc
    pop hl
    ld [hl+], a
    pop af
    inc a
    dec b
    jr nz, .box
    ld a, [wCamX + 1]
    ld [wColX], a
    ld a, [wCamZ + 1]
    ld [wColZ], a
    call PointInBoxXZ
    jp nc, .out
    call PlayerOverlapsY
    jp nc, .out
    ld a, [wTrigInside]
    ld hl, wLvMask
    and [hl]
    jr nz, .hold
    ld a, [wTrigInside]
    or [hl]
    ld [wTrigInside], a
    call TrigEnter
    jr .adv
.hold:
    ld a, [wLvPur]
    cp TRIG_HURT
    jr z, .hurt
    cp TRIG_HURT_SM
    jr nz, .adv
.hurt:
    ld a, [wTrigSeen]
    rrca
    jr c, .adv                       ; one tick per frame for overlapping hurt volumes
    ld a, [wTrigSeen]
    or 1
    ld [wTrigSeen], a
    ld a, [wDtMs]
    ld b, a
    ld a, [wTrigHurtMs]
    sub b
    ld [wTrigHurtMs], a
    ld a, [wTrigHurtMs + 1]
    sbc 0
    ld [wTrigHurtMs + 1], a
    jr nc, .adv
    ld a, LOW(HURT_MS)
    ld [wTrigHurtMs], a
    ld a, HIGH(HURT_MS)
    ld [wTrigHurtMs + 1], a
    call HurtDamage
    jr .adv
.out:
    ld a, [wLvMask]
    cpl
    ld hl, wTrigInside
    and [hl]
    ld [hl], a
.adv:
    ld hl, wLvMask
    sla [hl]
    ld hl, wLvI
    inc [hl]
    jp .ut

; HURT_LG_HP / HURT_SM_HP unless the radsuit runs.
HurtDamage:
    ld a, [wPuKind]
    and a
    ret nz
    ld a, [wLvPur]
    cp TRIG_HURT_SM
    ld a, HURT_LG_HP
    jr nz, .go
    ld a, HURT_SM_HP
.go:
    jp PlayerDamage

; wLvI = trigger, wLvPur = its purpose: on-entry dispatch (A8 trig_enter).
TrigEnter:
    ld a, [wLvPur]
    cp TRIG_HURT
    jr z, .hurt
    cp TRIG_HURT_SM
    jr z, .hurt
    cp TRIG_END
    jr z, .end
    cp TRIG_UNLOCK
    jr z, .unlock
    cp TRIG_UNHIDE
    jr z, .unhide
    cp TRIG_SPAWN
    jr z, .spawn
    cp TRIG_ELEV
    jr z, .elev
    cp TRIG_SUMMON
    jr z, .summon
    ret                              ; message (no text in the GBC payload)
.summon:
    call TrigArg
    ld c, a
    jp ElevSummon
.elev:                               ; every car of group arg; two or more is a stair: latch gate 15
    call TrigArg
    ld [wLvTag], a
    xor a
    ld [wLvCnt], a
    ld a, [wMapHdr + H_NELEVS]
    and a
    ret z
    ld [wLvN], a
    ld c, 0
.el:
    ld a, F_ELEV_GRP
    call MapGet
    ld b, a
    ld a, [wLvTag]
    cp b
    jr nz, .eln
    push bc
    call ElevActivate
    pop bc
    jr c, .eln
    ld hl, wLvCnt
    inc [hl]
.eln:
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .el
    ld a, [wLvCnt]
    cp 2
    ret c
    ld a, [wLvI]
    ld c, a
    ld a, [wLvPur]
    or $F0
    ld b, a
    ld a, F_TR_PURPOSE
    jp MapPut
.hurt:
    ld a, LOW(HURT_MS)
    ld [wTrigHurtMs], a
    ld a, HIGH(HURT_MS)
    ld [wTrigHurtMs + 1], a
    jp HurtDamage
.end:
    ld a, 1
    ld [wNextLevelReq], a
    ret
.unlock:
    call TrigArg
    jp DoorUnlockTag
.unhide:
    call TrigArg
    jp DoorUnhideTag
.spawn:                              ; one-shot: latch gate 15, wake every EN_GONE enemy with this tag
    call TrigArg
    ld [wLvTag], a
    ld a, [wLvI]
    ld c, a
    ld a, [wLvPur]
    or $F0
    ld b, a
    ld a, F_TR_PURPOSE
    call MapPut
    ld a, [wEnN]
    and a
    ret z
    ld [wLvN], a
    ld c, 0
.sp:
    ld a, F_EN_TAG
    call MapGet
    ld b, a
    ld a, [wLvTag]
    cp b
    jr nz, .spn
    ld hl, wEnState
    ld b, 0
    add hl, bc
    ld a, [hl]
    cp EN_GONE
    jr nz, .spn
    ld [hl], EN_IDLE
.spn:
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .sp
    ret

; -> A = tr_arg of trigger wLvI.
TrigArg:
    ld a, [wLvI]
    ld c, a
    ld a, F_TR_ARG
    jp MapGet

; ---- switches -------------------------------------------------------------------------------------

; A8 try_proximity: a blocked move (wDoorBlk) into a use switch, one fire per press.
TryProximity:
    ld a, [wDoorBlk]
    and a
    jr nz, .blocked
    ld [wKeyUseWas], a
    ret
.blocked:
    ld a, [wKeyUseWas]
    and a
    ret nz                           ; still pressing
    ld a, 1
    ld [wKeyUseWas], a
    ld a, [wMapHdr + H_NSWITCHES]
    and a
    ret z
    ld [wLvN], a
    ld c, 0
.s:
    ld a, c
    ld [wLvI], a
    ld a, F_SW_ROOM
    call MapGet
    ld b, a
    ld a, [wRoom]
    cp b
    jr nz, .sn
    call ProxSwitch
    jr nc, .sn
    ld a, [wLvI]
    ld c, a
    ld a, F_SW_KIND
    call MapGet
    bit 7, a
    jr z, .go
    and $7F
    cp SW_DEST_END + 1
    jr c, .sn                        ; shootable: a bump does not fire it
.go:
    call SwPush
    jr nc, .sn
    ld a, [wLvI]
    ld c, a
    call FireSwitch
    jp CrackSuppressBorn             ; one switch per press; a mark born this frame is dropped
.sn:
    ld a, [wLvI]
    ld c, a
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .s
    ret

; C = switch: A8 fire_switch. The low 7 bits of sw_kind are the destination.
FireSwitch:
    ld a, F_SW_KIND
    call MapGet
    and $7F
    jr nz, .nk
    ld a, F_SW_TAG
    call MapGet
    call DoorUnlockTag
    ld a, SND_SWTCHN                 ; A8 fire_switch: DOROPN if a door unlocked, else the switch sound
    jr nc, .sfx
    ld a, SND_DOROPN
.sfx:
    jp PlaySound
.nk:
    cp SW_DEST_TRIG
    jr z, .trig
    cp SW_DEST_ELEV
    jr z, .elev
    cp SW_DEST_END
    ret nz
    ld a, 1
    ld [wNextLevelReq], a
    ret
.elev:                               ; the switch tag is the car
    ld a, F_SW_TAG
    call MapGet
    ld c, a
    call ElevActivate
    ret c                            ; refused: silent
    ld a, SND_SWTCHN
    jp PlaySound
.unusedEnd:
    ld a, 1
    ld [wNextLevelReq], a
    ret
.trig:
    ld a, F_SW_TAG
    call MapGet
    call TrigArmTag
    ld a, SND_SWTCHN
    jp PlaySound

; B = point, C = box start, D = size -> A = distance to [box, box + size) (A8 near_box_xz axis).
NearAxisSz:
    ld a, b
    cp c
    jr c, .lo
    ld a, c
    add d
    ld e, a
    ld a, b
    cp e
    jr nc, .hi
    xor a
    ret
.lo:
    ld a, c
    sub b
    ret
.hi:
    sub e
    ret

; Loads switch C's box into wBoxX.. (x, y, z, sx, sy, sz).
SwBox:
    ld hl, wBoxX
    ld a, F_SW_X
    ld b, 6
.l:
    push af
    push hl
    push bc
    call MapGet
    pop bc
    pop hl
    ld [hl+], a
    pop af
    inc a
    dec b
    jr nz, .l
    ret

; A8 .prox_switch: carry = within SW_USE_RANGE of the pad in XZ, overlapping in Y, facing it. wLvI = C.
ProxSwitch:
    ld a, [wLvI]
    ld c, a
    call SwBox
    ld a, [wCamX + 1]
    ld b, a
    ld a, [wBoxX]
    ld c, a
    ld a, [wBoxSX]
    ld d, a
    call NearAxisSz
    cp SW_USE_RANGE + 1
    ret nc
    ld a, [wCamZ + 1]
    ld b, a
    ld a, [wBoxZ]
    ld c, a
    ld a, [wBoxSZ]
    ld d, a
    call NearAxisSz
    cp SW_USE_RANGE + 1
    ret nc
    call PlayerOverlapsY
    ret nc
    ld a, [wLvI]
    ld c, a
    ld a, F_SW_FACE
    call MapGet
    ld d, a
    ld a, [wYaw]
    ld e, a
    ld a, d
    cp FACE_PX
    jr nc, .x
    cp FACE_MZ
    jr z, .mz
    ld a, e                          ; FACE_PZ: yaw < 64 or >= 192
    cp 64
    jr c, .yes
    cp 192
    jr nc, .yes
    and a
    ret
.mz:
    ld a, e
    cp 64
    jr c, .no
    cp 192
    jr c, .yes
.no:
    and a
    ret
.x:
    cp FACE_MX
    jr z, .mx
    ld a, e                          ; FACE_PX: 0..127
    cp 128
    jr c, .yes
    and a
    ret
.mx:
    ld a, e
    cp 128
    jr nc, .yes
    and a
    ret
.yes:
    scf
    ret

; A8 .sw_push: carry = the blocked move pushes into the switch face from its air side. The box is
; loaded (ProxSwitch); wLvI = the switch.
SwPush:
    ld a, [wLvI]
    ld c, a
    ld a, F_SW_FACE
    call MapGet
    ld d, a                          ; face
    and 2
    jr z, .z
    ld a, [wDoorBlk]
    rrca
    jr nc, .no                       ; X not blocked
    ld a, [wWishX]
    ld b, a
    ld a, [wWishX + 1]
    or b
    jr z, .no
    ld a, [wWishX + 1]
    ld e, 0                          ; axis 0 = X
    jr .sgn
.z:
    ld a, [wDoorBlk]
    and 2
    jr z, .no
    ld a, [wWishZ]
    ld b, a
    ld a, [wWishZ + 1]
    or b
    jr z, .no
    ld a, [wWishZ + 1]
    ld e, 1                          ; axis 1 = Z
.sgn:
    bit 7, a                         ; wish sign
    jr nz, .neg
    bit 0, d
    jr nz, .no                       ; +wish into a min face
    ld a, e                          ; exclusive plane = box + size
    and a
    jr nz, .pz
    ld a, [wBoxX]
    ld hl, wBoxSX
    add [hl]
    ld b, a
    ld a, [wCamX + 1]
    jr .cmpPos
.pz:
    ld a, [wBoxZ]
    ld hl, wBoxSZ
    add [hl]
    ld b, a
    ld a, [wCamZ + 1]
.cmpPos:
    cp b
    jr z, .no                        ; on the plane is past the face
    jr nc, .no                       ; cam must be < plane
    scf
    ret
.neg:
    bit 0, d
    jr z, .no                        ; -wish into a max face
    ld a, e
    and a
    jr nz, .nz
    ld a, [wCamX + 1]
    ld hl, wBoxX
    jr .cmpNeg
.nz:
    ld a, [wCamZ + 1]
    ld hl, wBoxZ
.cmpNeg:
    cp [hl]                          ; carry set if cam < box: want cam >= box
    ccf
    ret
.no:
    and a
    ret

; ---- elevators (A8 src/elevator.asm) ---------------------------------------------------------------
; Per car: wElevY (current height), wElevTgt ($FF idle, else the stop it is moving to), wElevAcc (ms
; toward the next one-unit step: ELEV_STEP_MS, or 4x for elev_flags bit 0). The A8 runs these as process
; slots; the free-slot limit is not modelled. Things on a car are not carried (the GBC object lists are
; ROM); enemies and the player ride.

; C = car -> A = F_ELEV field value via MapGet (index in C kept).

; C = car: A8 elev_activate. Carry = refused (moving). One-shot to the other stop (home <-> dest).
ElevActivate:
    ld b, 0
    ld hl, wElevTgt
    add hl, bc
    ld a, [hl]
    cp $FF
    jr nz, .fail
    ld hl, wElevY
    add hl, bc
    ld a, [hl]
    ld [wLvTag], a                   ; current height
    ld a, F_ELEV_HOME
    call MapGet
    ld d, a                          ; home
    ld a, [wLvTag]
    cp d
    jr nz, .toHome
    ld a, F_ELEV_DEST                ; at home: go to the dest stop
    call MapGet
    jr .start
.toHome:
    ld a, d
.start:
    ld b, 0
    ld hl, wElevTgt
    add hl, bc
    ld [hl], a
    ld hl, wElevAcc
    add hl, bc
    add hl, bc
    xor a
    ld [hl+], a
    ld [hl], a
    and a
    ret
.fail:
    scf
    ret

; C = car: A8 elev_summon. Carry = nothing started (moving, or already at the nearer stop).
ElevSummon:
    ld b, 0
    ld hl, wElevTgt
    add hl, bc
    ld a, [hl]
    cp $FF
    jr nz, .fail
    ld a, [wCamY + 1]
    sub EYE_HEIGHT
    ld [wLvTag], a                   ; feet
    ld a, F_ELEV_DEST
    call MapGet
    call AbsDiff
    ld [wLvCnt], a                   ; |feet - dest|
    ld a, F_ELEV_HOME
    call MapGet
    ld e, a
    call AbsDiff
    ld hl, wLvCnt
    cp [hl]
    ld a, e                          ; home unless dest is strictly nearer
    jr c, .tgt
    jr z, .tgt
    ld a, F_ELEV_DEST
    call MapGet
.tgt:
    ld e, a
    ld b, 0
    ld hl, wElevY
    add hl, bc
    ld a, [hl]
    cp e
    jr z, .fail                      ; already there
    ld hl, wElevTgt
    add hl, bc
    ld [hl], e
    ld hl, wElevAcc
    add hl, bc
    add hl, bc
    xor a
    ld [hl+], a
    ld [hl], a
    and a
    ret
.fail:
    scf
    ret

; A = y -> A = |y - wLvTag|.
AbsDiff:
    ld hl, wLvTag
    sub [hl]
    ret nc
    cpl
    inc a
    ret

; Per frame: every moving car steps one unit per ELEV_STEP_MS (x4 when slow), carrying enemies on top.
ElevTick:
    ld a, [wMapHdr + H_NELEVS]
    and a
    ret z
    ld [wLvN], a
    xor a
    ldh [hElevMov], a                ; A8 elev_noise_n: the rumble plays while a car moves
    ld c, 0
.car:
    ld b, 0
    ld hl, wElevTgt
    add hl, bc
    ld a, [hl]
    cp $FF
    jp z, .next
    ld a, 1
    ldh [hElevMov], a
    call ElevThr                     ; wElThr
    ld b, 0
    ld hl, wElevAcc
    add hl, bc
    add hl, bc
    ld a, [wDtMs]
    add [hl]
    ld [hl+], a
    ld a, [hl]
    adc 0
    ld [hl], a
.step:
    ld b, 0
    ld hl, wElevAcc
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld d, [hl]
    ld e, a                          ; DE = acc
    ld a, [wElThr + 1]
    cp d
    jr c, .go                        ; thr < acc
    jr nz, .next                     ; thr > acc
    ld a, [wElThr]
    cp e
    jr nc, .nextIfLess               ; thr >= acc: only equal steps
    jr .go
.nextIfLess:
    jr nz, .next
.go:
    ld a, [wElThr]
    ld b, a
    ld a, e
    sub b
    ld e, a
    ld a, [wElThr + 1]
    ld b, a
    ld a, d
    sbc b
    ld d, a
    ld b, 0
    ld hl, wElevAcc
    add hl, bc
    add hl, bc
    ld a, e
    ld [hl+], a
    ld [hl], d
    call ElevOne
    ld b, 0
    ld hl, wElevTgt
    add hl, bc
    ld a, [hl]
    cp $FF
    jr nz, .step
.next:
    inc c
    ld a, [wLvN]
    cp c
    jp nz, .car
    ret

; Car C -> wElThr = ELEV_STEP_MS, x4 for a slow car.
ElevThr:
    ld a, F_ELEV_FLAGS
    call MapGet
    and ELEV_FLAG_SLOW
    ld a, LOW(ELEV_STEP_MS)
    ld [wElThr], a
    ld a, HIGH(ELEV_STEP_MS)
    ld [wElThr + 1], a
    ret z
    ld a, LOW(ELEV_STEP_MS * 4)
    ld [wElThr], a
    ld a, HIGH(ELEV_STEP_MS * 4)
    ld [wElThr + 1], a
    ret

; C = car: one unit toward the target, carrying enemies on the top; done at the target.
ElevOne:
    ld b, 0
    ld hl, wElevY
    add hl, bc
    ld a, [hl]
    ld d, a                          ; y
    ld hl, wElevTgt
    add hl, bc
    ld a, [hl]
    cp d
    jr z, .arrive
    ld a, 1                          ; dy = +1 up, -1 down
    jr nc, .dy
    ld a, $FF
.dy:
    ld [wLvMask], a
    call ElevCarry
    ld b, 0
    ld hl, wElevY
    add hl, bc
    ld a, [wLvMask]
    add [hl]
    ld [hl], a
    ld d, a
    ld hl, wElevTgt
    add hl, bc
    ld a, [hl]
    cp d
    ret nz
.arrive:
    ld b, 0
    ld hl, wElevTgt
    add hl, bc
    ld [hl], $FF
    ret

; C = car, wLvMask = dy: live enemies of the car's room standing on its top (en_y == y + sy) inside
; its footprint move with it.
ElevCarry:
    ld a, [wEnN]
    and a
    ret z
    ld a, F_ELEV_ROOM
    call MapGet
    ld [wLvEnd], a
    ld a, F_ELEV_SY
    call MapGet
    ld b, 0
    ld hl, wElevY
    add hl, bc
    add [hl]
    ld [wLvPur], a                   ; the top
    ld hl, wBoxX
    ld a, F_ELEV_X
    ld b, 6
.box:
    push af
    push hl
    push bc
    call MapGet
    pop bc
    pop hl
    ld [hl+], a
    pop af
    inc a
    dec b
    jr nz, .box
    ld a, [wEnN]
    ld [wLvN2], a
    ld e, 0
.en:
    ld d, 0
    ld hl, wEnState
    add hl, de
    ld a, [hl]
    cp EN_GONE
    jr z, .nx
    ld hl, wEnRoom
    add hl, de
    ld a, [wLvEnd]
    cp [hl]
    jr nz, .nx
    ld hl, wEnY
    add hl, de
    ld a, [wLvPur]
    cp [hl]
    jr nz, .nx
    ld hl, wEnX
    add hl, de
    ld a, [hl]
    ld [wColX], a
    ld hl, wEnZ
    add hl, de
    ld a, [hl]
    ld [wColZ], a
    push de
    push bc
    call PointInFloorXZ
    pop bc
    pop de
    jr nc, .nx
    ld hl, wEnY
    add hl, de
    ld a, [wLvMask]
    add [hl]
    ld [hl], a
.nx:
    inc e
    ld a, [wLvN2]
    cp e
    jr nz, .en
    ret

; ROM0 stub target: board the elevator under the player. Called from UpdateFloor (collide.asm) after
; the crate / platform floors, with wFloorY the floor found so far. A8 elev_update_floor.
ElevFloorB::
    ld a, [wMapHdr + H_NELEVS]
    and a
    ret z
    ld [wLvN], a
    ld c, 0
.car:
    ld a, F_ELEV_ROOM
    call MapGet
    ld b, a
    ld a, [wRoom]
    cp b
    jr nz, .next
    ld hl, wBoxX                     ; x, y, z, sx, sy, sz of the car
    ld a, F_ELEV_X
    ld b, 6
.box:
    push af
    push hl
    push bc
    call MapGet
    pop bc
    pop hl
    ld [hl+], a
    pop af
    inc a
    dec b
    jr nz, .box
    ld a, [wCamX + 1]
    ld [wColX], a
    ld a, [wCamZ + 1]
    ld [wColZ], a
    push bc
    call PointInFloorXZ
    pop bc
    jr nc, .next
    ld b, 0
    ld hl, wElevY
    add hl, bc
    ld a, [wBoxSY]
    add [hl]                         ; the top
    ld [wLvPur], a
    ld hl, wFloorY
    ld b, a
    ld a, [hl]
    ld d, a
    ld a, b
    cp d
    jr c, .next                      ; below the current floor
    ld a, [wPrevElev]
    cp c
    jr z, .on                        ; already riding: the feet lag while it moves
    ld a, [wCamY + 1]
    sub EYE_HEIGHT                   ; feet
    ld b, 0
    ld hl, wElevY
    add hl, bc
    cp [hl]
    jr c, .next                      ; feet below the car: walking under it
.on:
    ld a, [wLvPur]
    ld [wFloorY], a
    ld a, c
    ld [wOnElev], a
.next:
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .car
    ret

; GBC level start: every car at its start height, idle.
ElevInitB::
    ld a, $FF
    ld hl, wElevTgt
    ld b, 8
.t:
    ld [hl+], a
    dec b
    jr nz, .t
    xor a
    ld hl, wElevAcc
    ld b, 16
.a:
    ld [hl+], a
    dec b
    jr nz, .a
    ld a, $FF
    ld [wOnElev], a
    ld [wPrevElev], a
    ld a, [wMapHdr + H_NELEVS]
    and a
    ret z
    ld [wLvN], a
    ld c, 0
.y:
    ld a, F_ELEV_Y0
    call MapGet
    ld b, 0
    ld hl, wElevY
    add hl, bc
    ld [hl], a
    inc c
    ld a, [wLvN]
    cp c
    jr nz, .y
    ret
