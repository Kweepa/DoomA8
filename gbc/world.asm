; World: level loading, room meshes, player movement.
; Map payload lives in WRAM bank 2 (wMap); everything else is in bank 1. Reads from the
; payload go through MapGet (SVBK 2 for one read, back to 1).

INCLUDE "hw.inc"
INCLUDE "map_fields.inc"

DEF MOVE_SPEED   EQU 33            ; 8.8 world units per VBlank = 8.25 per input tick (A8: ~7.75 units/s)
DEF TURN_TICK    EQU 67            ; 8.8 yaw units per input tick (A8: 1 yaw unit per 16 ms)

SECTION "world", ROM0

; HL = src, DE = dst, B = count. Advances HL and DE. Clobbers A, B.
CopyN:
    ld a, b
    and a
    ret z
.l:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .l
    ret

; HL = mesh record (ROM, mapped). Fills the wScene* buffer.
LoadMesh::
    ld a, [hl+]
    ld [wSceneNUX], a
    ld a, [hl+]
    ld [wSceneNUZ], a
    ld a, [hl+]
    ld [wSceneNC], a
    ld a, [hl+]
    ld [wSceneNV], a
    ld a, [hl+]
    ld [wSceneNE], a
    ld a, [wSceneNUX]
    ld b, a
    ld de, wSceneUX
    call CopyN
    ld a, [wSceneNUZ]
    ld b, a
    ld de, wSceneUZ
    call CopyN
    ld a, [wSceneNC]
    add a
    ld b, a
    ld de, wSceneCols
    call CopyN
    ld a, [wSceneNV]
    add a
    ld b, a
    ld de, wSceneVerts
    call CopyN
    ld a, [wSceneNE]
    add a
    ld b, a
    ld de, wSceneEdges
    jp CopyN

; A = room index. Loads that room's mesh from the mapped level bank.
LoadRoomMesh::
    ld [wRoom], a
    add a
    ld c, a
    ld b, 0
    ld a, [wRoomTab]
    ld l, a
    ld a, [wRoomTab + 1]
    ld h, a
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    jp LoadMesh

; A = room. Makes it the current room: mesh for the renderer, collision cache.
EnterRoom::
    ld b, a
    xor a
    ld [wTrigInside], a             ; bits are room-local: a stale one would block the same-numbered trigger here
    ld a, [wLevelBank]
    ld [rROMB0], a
    ld a, b
    push af
    call LoadRoomMesh
    pop af
    ; fall through

; A = room. Copies the cooker's 159-byte collision record into the WRAM room cache.
LoadRoomCache::
    add a
    ld c, a
    ld b, 0
    ld a, [wCollTab]
    ld l, a
    ld a, [wCollTab + 1]
    ld h, a
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld de, wRoomCache
    ld b, wRoomCacheEnd - wRoomCache
    jp CopyN

; A = level index. Maps the level's ROM bank (stays mapped), copies the packed map into
; WRAM bank 2, binds the field pointer table, spawns the player.
LoadLevel::
    push af
    call SndStopEnemy               ; A8 stop_streamed_sfx: enemy sounds end with the level
    pop af
    ld [wLevel], a
    ld e, a
    ld d, 0
    ld hl, LevelBank
    add hl, de
    ld a, [hl]
    ld [wLevelBank], a
    ld [rROMB0], a
    ld a, [wLevel]
    add a
    ld c, a
    ld b, 0                         ; BC = level * 2
    ld hl, LevelPayload
    add hl, bc
    ld a, [hl+]
    ld [wLoadSrc], a
    ld a, [hl]
    ld [wLoadSrc + 1], a
    ld hl, LevelPayloadLen
    add hl, bc
    ld a, [hl+]
    ld [wLoadLen], a
    ld a, [hl]
    ld [wLoadLen + 1], a
    ld hl, LevelFieldOffs
    add hl, bc
    ld a, [hl+]
    ld [wFOffPtr], a
    ld a, [hl]
    ld [wFOffPtr + 1], a
    ld hl, LevelRoomTab
    add hl, bc
    ld a, [hl+]
    ld [wRoomTab], a
    ld a, [hl]
    ld [wRoomTab + 1], a
    ld hl, LevelCollTab
    add hl, bc
    ld a, [hl+]
    ld [wCollTab], a
    ld a, [hl]
    ld [wCollTab + 1], a
    ld hl, LevelObjTab
    add hl, bc
    ld a, [hl+]
    ld [wObjTab], a
    ld a, [hl]
    ld [wObjTab + 1], a
    ld a, [ObjBank0]
    ld b, a
    ld a, [wLevel]
    add b
    ld [wObjBank], a

    ; header -> wMapHdr (bank 1)
    ld a, [wLoadSrc]
    ld l, a
    ld a, [wLoadSrc + 1]
    ld h, a
    ld de, wMapHdr
    ld b, 23
    call CopyN

    ; payload -> wMap (bank 2)
    ld a, [wLoadSrc]
    ld l, a
    ld a, [wLoadSrc + 1]
    ld h, a
    ld a, [wLoadLen]
    ld c, a
    ld a, [wLoadLen + 1]
    ld b, a
    ld de, wMap
    ld a, 2
    ldh [rSVBK], a
.copy:
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .copy
    ld a, 1
    ldh [rSVBK], a

    ; field pointers = wMap + offset
    ld a, [wFOffPtr]
    ld l, a
    ld a, [wFOffPtr + 1]
    ld h, a
    ld de, wFieldPtr
    ld b, NUM_FIELDS
.bind:
    ld a, [hl+]
    add LOW(wMap)
    ld [de], a
    inc de
    ld a, [hl+]
    adc HIGH(wMap)
    ld [de], a
    inc de
    dec b
    jr nz, .bind

    ; Spawn: eye at (spawn_x + 1, spawn_y + EYE, spawn_z + 1), yaw = rot * 32.
    xor a
    ld [wCamX], a
    ld [wCamY], a
    ld [wCamZ], a
    ld a, [wMapHdr + H_SPAWN_X]
    inc a
    ld [wCamX + 1], a
    ld a, [wMapHdr + H_SPAWN_Z]
    inc a
    ld [wCamZ + 1], a
    ld a, [wMapHdr + H_SPAWN_Y]
    add EYE_HEIGHT
    ld [wCamY + 1], a
    ld a, [wMapHdr + H_SPAWN_ROT]
    swap a
    add a
    ld [wYaw], a
    ld a, [wMapHdr + H_SPAWN_Y]
    ld [wFloorY], a
    xor a
    ld [wFloorYL], a
    ld [wFloorSlope], a
    ld [wFalling], a
    ld [wFallVL], a
    ld [wFallVH], a
    ld [wFallAcc], a
    ld hl, wThTaken
    ld b, 32
    xor a
.clrTh:
    ld [hl+], a
    dec b
    jr nz, .clrTh
    ld hl, wKills                   ; level statistics for the intermission (a death reload starts them over)
    ld [hl+], a                     ; wKills, wStItems, wStMs (2), wStSec (2), wStSecrets are contiguous
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
    call LoadEnemies
    ld a, [wMapHdr + H_SPAWN_ROOM]
    jp EnterRoom

; A = field id, C = index -> A = payload byte. Preserves BC and DE. Clobbers HL.
MapGet::
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
    ld a, [hl]
    ld l, a
    ld a, 1
    ldh [rSVBK], a
    ld a, l
    ret

; A = position field (F_ROOM_X/Y/Z), C = room, wTc = coordinate (high byte of the camera).
; Carry set if 0 <= coord - pos < size (size field = position field + 3).
InAxis:
    ld [wTb], a
    call MapGet
    ld b, a
    ld a, [wTc]
    sub b
    ld [wTc + 1], a
    ld a, [wTb]
    add 3
    call MapGet
    ld b, a
    ld a, [wTc + 1]
    cp b
    ret

; Switch wRoom (and its mesh) to the room whose AABB holds the camera. Keeps the current
; room when the camera is in none.
FindRoom::
    xor a
    ld [wI], a
.r:
    ld a, [wI]
    ld c, a
    ld a, [wCamX + 1]
    ld [wTc], a
    ld a, F_ROOM_X
    call InAxis
    jr nc, .next
    ld a, [wCamZ + 1]
    ld [wTc], a
    ld a, F_ROOM_Z
    call InAxis
    jr nc, .next
    ld a, [wCamY + 1]
    ld [wTc], a
    ld a, F_ROOM_Y
    call InAxis
    jr nc, .next
    ld a, [wI]
    ld b, a
    ld a, [wRoom]
    cp b
    ret z
    ld a, b
    jp EnterRoom
.next:
    ld a, [wI]
    inc a
    ld [wI], a
    ld b, a
    ld a, [wMapHdr + H_NROOMS]
    cp b
    jr nz, .r
    ret

; In: B = dx multiplier, C = dz multiplier (signed 8-bit, +-127 = 1.0), wTa = distance (8.8).
; wWishX += wTa * B >> 7, wWishZ += wTa * C >> 7.
MoveAlong:
    ld a, c
    ld [wTb], a
    ld c, b
    ld a, [wTa]
    ld e, a
    ld a, [wTa + 1]
    ld d, a
    call SMul16
    ld a, [wWishX]
    add e
    ld [wWishX], a
    ld a, [wWishX + 1]
    adc d
    ld [wWishX + 1], a
    ld a, [wTb]
    ld c, a
    ld a, [wTa]
    ld e, a
    ld a, [wTa + 1]
    ld d, a
    call SMul16
    ld a, [wWishZ]
    add e
    ld [wWishZ], a
    ld a, [wWishZ + 1]
    adc d
    ld [wWishZ + 1], a
    ret

; Poll the pad, advance yaw / position by the number of VBlanks since the last call
; (1..4), so speed is the same at any frame rate. No collision yet.
UpdateMove::
    ldh a, [hFrame]
    ld b, a
    ldh a, [hLastFrame]
    ld c, a
    ld a, b
    ldh [hLastFrame], a
    sub c
    ld [wRawDt], a                  ; frame time in VBlanks, for the HUD
    cp 13
    jr c, .dtOk
    ld a, 12
.dtOk:
    and a
    jr nz, .dtNz
    inc a
.dtNz:
    ld [wMoveDt], a
    ld b, a
    ld a, [wSpin]
    add b
    ld [wSpin], a
    ld a, b                         ; A8 dt_ms (NTSC: VBI ticks * 17)
    swap a
    add b
    ld [wDtMs], a
    ld l, a                         ; A8 update_item_spin: item_spin += dt_ms << 4 (8.8)
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, [wItemSpin]
    add l
    ld [wItemSpin], a
    ld a, [wItemSpin + 1]
    adc h
    ld [wItemSpin + 1], a
    ld a, [wHP]                     ; A8 death_restart: no input or movement while dead
    and a
    ret z
    call ReadJoy
IF DEF(DEBUG)
    ldh a, [hJoy]                   ; debug cheat: Start = all keys
    bit 7, a
    jr z, .noCheat
    ld a, 7
    ld [wHaveKeys], a
.noCheat:
ENDC
    ; fall through

; hJoy and wMoveDt set: input -> turn/wish -> collide -> floor -> gravity.
ApplyMove::
    call ApplyInput
    call ApplyWish
    call TryDoorWish
    jr nc, .walk
    call CrackSuppressBorn          ; A8 apply_move_world: transit ate the bump, drop a mark born this frame
    call CrackClearHold
    jr .moved
.walk:
    ld a, [wDoorBlk]
    and a
    call z, CrackClearHold          ; contact ended
.moved:
    call ElevPre
    call UpdateFloor
    jp UpdateFall

; wHold* set (ReadJoy, or HoldsFromJoy in the tests): turn, then accumulate the movement wish from
; the time each direction was held (ticks, 12 world units per tick). No collision.
ApplyInput::
    xor a
    ld [wWishX], a
    ld [wWishX + 1], a
    ld [wWishZ], a
    ld [wWishZ + 1], a

    ; turn: net hold (right - left) ticks * TURN_TICK (67/256 yaw unit) into the 8.8 yaw
    ; accumulator wTurnFrac:wYaw (A8: 1 yaw unit per 16 ms)
    ld a, [wHoldTR]
    ld b, a
    ld a, [wHoldTL]
    ld c, a
    ld a, b
    sub c                           ; net, -48..48
    ld e, a
    add a
    sbc a
    ld d, a                         ; DE = net (signed 16)
    ld h, d
    ld l, e
    add hl, hl
    add hl, de                      ; 3 net
    ld b, h
    ld c, l
    ld h, d
    ld l, e
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl                      ; 64 net
    add hl, bc                      ; 67 net
    ld a, [wTurnFrac]
    add l
    ld [wTurnFrac], a
    ld a, h
    adc 0
    ld b, a
    ld a, [wYaw]
    add b
    ld [wYaw], a
    ; sin / cos of the (new) yaw
    ld a, [wYaw]
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wSin], a
    ld a, [wYaw]
    add 64
    ld l, a
    ld a, [hl]
    ld [wCos], a

    ld a, [wHoldF]                  ; forward = (sin, cos)
    and a
    jr z, .notUp
    call HoldDist
    ld a, [wSin]
    ld b, a
    ld a, [wCos]
    ld c, a
    call MoveAlong
.notUp:
    ld a, [wHoldB]                  ; back
    and a
    jr z, .notDown
    call HoldDist
    ld a, [wSin]
    cpl
    inc a
    ld b, a
    ld a, [wCos]
    cpl
    inc a
    ld c, a
    call MoveAlong
.notDown:
    ld a, [wHoldSR]                 ; strafe right = (cos, -sin)
    and a
    jr z, .notSR
    call HoldDist
    ld a, [wCos]
    ld b, a
    ld a, [wSin]
    cpl
    inc a
    ld c, a
    call MoveAlong
.notSR:
    ld a, [wHoldSL]                 ; strafe left = (-cos, sin)
    and a
    ret z
    call HoldDist
    ld a, [wCos]
    cpl
    inc a
    ld b, a
    ld a, [wSin]
    ld c, a
    jp MoveAlong

; A = ticks held -> wTa = A * 8.25 (8.8 world units; 4 ticks = one VBlank = MOVE_SPEED 33).
; A8: (sin * ms) >> 6 = 2 units per ms at full sin, a tick is 4.17 ms.
HoldDist:
    ld c, a
    srl a
    srl a
    ld b, a                         ; ticks >> 2
    ld l, c
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, l
    add b
    ld l, a
    ld a, h
    adc 0
    ld [wTa + 1], a
    ld a, l
    ld [wTa], a
    ret
