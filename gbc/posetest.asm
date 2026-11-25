; Pose test: render every pose, store a Fletcher-16 of the framebuffer per pose,
; then time NumPoses renders. tools/gbc_posetest.py compares against the spec.
; Results (after the "POSE" magic): ticks word, then one word per pose.

INCLUDE "hw.inc"
INCLUDE "map_fields.inc"

SECTION "posetest", ROM0

; D = s1, E = s2 over the whole framebuffer (same as gbc_room.fletcher).
FletcherFB:
    ld hl, FB
    ld bc, FB_SIZE
    ld d, 0
    ld e, 0
.l:
    ld a, [hl+]
    add d
    ld d, a
    add e
    ld e, a
    dec bc
    ld a, b
    or c
    jr nz, .l
    ret

; HL = src, DE = dst, B = count (>0)
CopyBytes:
.l:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .l
    ret

IF DEF(POSETEST)
; Load pose at [wPosePtr] into the camera and advance the pointer.
LoadPose:
    ld a, [wPosePtr]
    ld l, a
    ld a, [wPosePtr + 1]
    ld h, a
    ld a, [hl+]
    ld [wCamX], a
    ld a, [hl+]
    ld [wCamX + 1], a
    ld a, [hl+]
    ld [wCamZ], a
    ld a, [hl+]
    ld [wCamZ + 1], a
    ld a, [hl+]
    ld [wYaw], a
    inc hl
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    xor a
    ld [wCamY], a
    ld a, $18                       ; 24 * 256
    ld [wCamY + 1], a
    ret

RunPoseTest::
    ld hl, TestSceneRec
    call LoadMesh
    ; Magic markers for tools/gbc_posetest.py (arrays live at +0 of each page).
    ld hl, wUniq + 240
    ld a, 'W'
    ld [hl+], a
    ld a, 'U'
    ld [hl+], a
    ld a, 'N'
    ld [hl+], a
    ld a, 'Q'
    ld [hl], a
    ld hl, wCols + 240
    ld a, 'W'
    ld [hl+], a
    ld a, 'C'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'L'
    ld [hl], a
    ld hl, wVerts + 240
    ld a, 'W'
    ld [hl+], a
    ld a, 'V'
    ld [hl+], a
    ld a, 'R'
    ld [hl+], a
    ld a, 'T'
    ld [hl], a
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a

    ; Phase A: checksums.
    ld hl, Poses
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    xor a
    ld [wPoseI], a
.pose:
    call LoadPose
    call ClearFB
    call RenderScene
    call FletcherFB
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, d
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wPoseI]
    inc a
    ld [wPoseI], a
    cp NumPoses
    jr nz, .pose

    ; Phase B: time NumPoses renders (no clear; the plotter cost does not depend on content).
    ld a, IEF_VBLANK | IEF_TIMER
    ldh [rIE], a
    ei
    ld hl, Poses
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    xor a
    ld [wPoseI], a
    call TimerStart
.timed:
    call LoadPose
    call RenderScene
    ld a, [wPoseI]
    inc a
    ld [wPoseI], a
    cp NumPoses
    jr nz, .timed
    call TimerRead
    ld a, c
    ld [wPoseTicks], a
    ld a, b
    ld [wPoseTicks + 1], a
    ret
ENDC

IF DEF(MAPTEST)
; Every entry of MapTestTab: level (loaded when it changes), room mesh, camera, yaw ->
; clear, render, Fletcher; one word per entry after the "POSE" magic (ticks word unused).
; Entry: db level, room; dw camx, camz, camy; db yaw, 0   (10 bytes)
RunMapTest::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    ld hl, MapTestTab
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    xor a
    ld [wPoseI], a
    ld [wPoseI + 0], a
    ld a, 0
    ld [wTestCnt], a                     ; entry counter low
    ld [wTestCnt + 1], a                 ; high
.entry:
    ld a, [wPosePtr]
    ld l, a
    ld a, [wPosePtr + 1]
    ld h, a
    ld a, [hl+]
    ld b, a                         ; level
    ld a, [hl+]
    ld [wTestRoom], a                     ; room
    ld a, [hl+]
    ld [wCamX], a
    ld a, [hl+]
    ld [wCamX + 1], a
    ld a, [hl+]
    ld [wCamZ], a
    ld a, [hl+]
    ld [wCamZ + 1], a
    ld a, [hl+]
    ld [wCamY], a
    ld a, [hl+]
    ld [wCamY + 1], a
    ld a, [hl+]
    ld [wYaw], a
    inc hl
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ; level change? LoadLevel resets the camera, so save/restore it.
    ld a, [wLevel]
    cp b
    jr z, .sameLevel
    push bc
    ld hl, wCamX
    ld de, wCamSave
    ld b, 7
    call CopyBytes
    pop bc
    ld a, b
    call LoadLevel
    ld hl, wCamSave
    ld de, wCamX
    ld b, 7
    call CopyBytes
.sameLevel:
    ; FindRoom must pick the same room as the Python lookup over the packed payload.
    ld a, $FF
    ld [wRoom], a
    call FindRoom
    ld hl, wFindOut
    ld a, [wTestCnt]
    ld c, a
    ld a, [wTestCnt + 1]
    ld b, a
    add hl, bc
    ld a, [wRoom]
    ld [hl], a
    ld a, [wTestRoom]
    call EnterRoom
    ld a, [wTestCnt]
    ld [wSpin], a
    ld [wItemSpin + 1], a           ; pickups' yaw (A8 item_spin) for this case
    call ClearFB
    ei                              ; ClearFB leaves interrupts off (SP fill)
    call RenderScene
    call DrawWorldObjects
    call FletcherFB
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, d
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wTestCnt]
    inc a
    ld [wTestCnt], a
    jr nz, .noCarry
    ld a, [wTestCnt + 1]
    inc a
    ld [wTestCnt + 1], a
.noCarry:
    ld a, [wTestCnt + 1]
    cp HIGH(NumMapTests)
    jp nz, .entry
    ld a, [wTestCnt]
    cp LOW(NumMapTests)
    jp nz, .entry
    ret

ENDC

IF DEF(MOVETEST)
; Script the pad through ApplyMove; store (camx, camz, yaw) after every step (5 bytes).
RunMoveTest::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    ld hl, MoveStart
    ld a, [hl+]
    ld [wCamX], a
    ld a, [hl+]
    ld [wCamX + 1], a
    ld a, [hl+]
    ld [wCamZ], a
    ld a, [hl+]
    ld [wCamZ + 1], a
    ld a, [hl]
    ld [wYaw], a
    ld hl, MoveScript
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    xor a
    ld [wTestCnt], a
.step:
    ld a, [wPosePtr]
    ld l, a
    ld a, [wPosePtr + 1]
    ld h, a
    ld a, [hl+]
    ldh [hJoy], a
    ld a, [hl+]
    ld [wMoveDt], a
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    call HoldsFromJoy
    call ApplyInput
    ld a, [wCamX]                   ; free movement: add the wish with no collision
    ld b, a
    ld a, [wWishX]
    add b
    ld [wCamX], a
    ld a, [wCamX + 1]
    ld b, a
    ld a, [wWishX + 1]
    adc b
    ld [wCamX + 1], a
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
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, [wCamX]
    ld [hl+], a
    ld a, [wCamX + 1]
    ld [hl+], a
    ld a, [wCamZ]
    ld [hl+], a
    ld a, [wCamZ + 1]
    ld [hl+], a
    ld a, [wYaw]
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wTestCnt]
    inc a
    ld [wTestCnt], a
    cp NumMoveSteps
    jr nz, .step
    ; input sampling cases: per case 6 hold counters + hJoy appended to the dump
    ld a, IEF_VBLANK                ; no real ticks while the cases feed the sampler
    ldh [rIE], a
    ld hl, InputCases
.icase:
    ld a, [hl]
    cp $FF
    ret z
.iseg:
    ld a, [hl+]
    ld c, a                         ; pad
    ld a, [hl+]                     ; ticks (0 ends the case)
    and a
    jr z, .iend
    ld b, a
.itick:
    push hl
    push bc
    call InputSample
    pop bc
    pop hl
    dec b
    jr nz, .itick
    jr .iseg
.iend:
    push hl
    call ReadJoy
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld de, wHoldF
    ld b, 6
.icopy:
    ld a, [de]
    ld [hl+], a
    inc de
    dec b
    jr nz, .icopy
    ldh a, [hJoy]
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    pop hl
    jr .icase

; pad, ticks ... ; 0, 0 ends a case ; $FF ends the table
InputCases:
    db $04, 10, $05, 5, 0, 0               ; forward 15, turn right 5
    db $2A, 7, 0, 0                        ; B + down + left: back 7, strafe left 7
    db $03, 3, 0, 0                        ; right and left: both 3
    db $04, 60, 0, 0                       ; clamped at MAX_HOLD
    db $10, 1, $00, 2, 0, 0                ; an A tap shorter than the frame still reaches hJoy
    db $C8, 4, $00, 4, 0, 0                ; Start + Select + down: latched, back 4
    db $04, 2, 0, 0                        ; counters restart after a snapshot
    db $FF
ENDC

IF DEF(WORLDTEST)
; Per scenario (WorldTestTab): load level / room, place the player, run WalkScript through
; ApplyMove, Fletcher-16 over (cam x,z,y, floor_y, flags, yaw) after every step.
; Result per scenario: checksum (2 bytes LE), final camx (2) -> wPoseOut.
; Entry: db level, room; dw camx, camz, camy; db yaw, floor_y   (10 bytes)
FletchByte:
    ld b, a
    ld a, [wF1]
    add b
    ld [wF1], a
    ld b, a
    ld a, [wF2]
    add b
    ld [wF2], a
    ret

RunWorldTest::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
IF DEF(WORLDTIME)
    ld a, IEF_VBLANK | IEF_TIMER
    ldh [rIE], a
    ei
    call TimerStart
ENDC
    ld hl, WorldTestTab
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    xor a
    ld [wTestCnt], a
    ld [wTestCnt + 1], a
.test:
    ld a, [wPosePtr]
    ld l, a
    ld a, [wPosePtr + 1]
    ld h, a
    ld a, [hl+]
    ld b, a                         ; level
    ld a, [hl+]
    ld [wTestRoom], a
    ld a, [hl+]
    ld [wCamX], a
    ld a, [hl+]
    ld [wCamX + 1], a
    ld a, [hl+]
    ld [wCamZ], a
    ld a, [hl+]
    ld [wCamZ + 1], a
    ld a, [hl+]
    ld [wCamY], a
    ld a, [hl+]
    ld [wCamY + 1], a
    ld a, [hl+]
    ld [wYaw], a
    xor a
    ld [wTurnFrac], a               ; the spec starts every case with no carried yaw fraction
    ld a, [hl+]
    ld [wFloorY], a
    ld a, [hl+]
    ld [wTestKeys], a
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ld a, [wLevel]
    cp b
    jr z, .sameLevel
    push bc
    ld hl, wCamX                    ; LoadLevel resets the camera / floor: save and restore
    ld de, wCamSave
    ld b, 7
    call CopyBytes
    ld a, [wFloorY]
    ld [wTmpY], a
    pop bc
    ld a, b
    call LoadLevel
    ld hl, wCamSave
    ld de, wCamX
    ld b, 7
    call CopyBytes
    ld a, [wTmpY]
    ld [wFloorY], a
.sameLevel:
    ld a, [wTestRoom]
    call EnterRoom
    ld a, [wTestKeys]
    ld [wHaveKeys], a
    xor a
    ld [wFloorYL], a
    ld [wFloorSlope], a
    ld [wFalling], a
    ld [wFallVL], a
    ld [wFallVH], a
    ld [wFallAcc], a
    ld [wF1], a
    ld [wF2], a
    ld hl, WalkScript
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
IF DEF(WORLDSTEPS)
    ld a, WORLDSTEPS
ELSE
    ld a, NumWalkSteps
ENDC
    ld [wStepCnt], a
.step:
    ld a, [wScriptPtr]
    ld l, a
    ld a, [wScriptPtr + 1]
    ld h, a
    ld a, [hl+]
    ldh [hJoy], a
    ld a, [hl+]
    ld [wMoveDt], a
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    call HoldsFromJoy
    call ApplyMove
    ld a, [wCamX]
    call FletchByte
    ld a, [wCamX + 1]
    call FletchByte
    ld a, [wCamZ]
    call FletchByte
    ld a, [wCamZ + 1]
    call FletchByte
    ld a, [wCamY]
    call FletchByte
    ld a, [wCamY + 1]
    call FletchByte
    ld a, [wFloorY]
    call FletchByte
    ld a, [wFloorSlope]
    add a
    ld b, a
    ld a, [wFalling]
    or b
    call FletchByte
    ld a, [wYaw]
    call FletchByte
    ld a, [wRoom]
    call FletchByte
    ld a, [wStepCnt]
    dec a
    ld [wStepCnt], a
    jr nz, .step
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, [wF1]
    ld [hl+], a
    ld a, [wF2]
    ld [hl+], a
    ld a, [wCamX]
    ld [hl+], a
    ld a, [wCamX + 1]
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ; debug record (first 12 scenarios): final state, 12 bytes
    ld a, [wTestCnt]
    cp 12
    jr nc, .noDbg
    ld c, a
    ld b, 0
    ld hl, 0
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc
    add hl, bc                      ; hl = 12 * index
    ld de, wDbgOut
    add hl, de
    ld a, [wCamX]
    ld [hl+], a
    ld a, [wCamX + 1]
    ld [hl+], a
    ld a, [wCamZ]
    ld [hl+], a
    ld a, [wCamZ + 1]
    ld [hl+], a
    ld a, [wCamY]
    ld [hl+], a
    ld a, [wCamY + 1]
    ld [hl+], a
    ld a, [wFloorY]
    ld [hl+], a
    ld a, [wFloorYL]
    ld [hl+], a
    ld a, [wFloorSlope]
    add a
    ld b, a
    ld a, [wFalling]
    or b
    ld [hl+], a
    ld a, [wYaw]
    ld [hl+], a
    ld a, [wFallVL]
    ld [hl+], a
    ld a, [wFallVH]
    ld [hl], a
.noDbg:
    ld a, [wTestCnt]
    inc a
    ld [wTestCnt], a
    cp NumWorldTests
    jp nz, .test
IF DEF(WORLDTIME)
    call TimerRead
    ld a, c
    ld [wPoseTicks], a
    ld a, b
    ld [wPoseTicks + 1], a
ENDC
    ret
ENDC

IF DEF(ENTTEST)
; Entity renders: per case, point DrawEntity at an item / enemy-frame mesh in the entity bank,
; clear, draw, Fletcher the framebuffer. One word per case after the "POSE" magic.
; Case: db kind, idx, frame; dw camx, camz, camy; db camyaw; dw ox, oz, oy; db objyaw  (17 bytes)
RunEntTest::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    ld a, [EntBank]
    ld [rROMB0], a
IF DEF(ENTTIME)
    ld a, IEF_VBLANK | IEF_TIMER
    ldh [rIE], a
    ei
    call TimerStart
ENDC
    ld hl, EntTestTab
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    xor a
    ld [wTestCnt], a
.case:
    ld a, [wPosePtr]
    ld l, a
    ld a, [wPosePtr + 1]
    ld h, a
    ld a, [hl+]
    ld [wTestRoom], a               ; kind
    ld a, [hl+]
    ld c, a                         ; idx
    ld a, [hl+]
    ld [wTestKeys], a               ; frame
    ld a, [hl+]
    ld [wCamX], a
    ld a, [hl+]
    ld [wCamX + 1], a
    ld a, [hl+]
    ld [wCamZ], a
    ld a, [hl+]
    ld [wCamZ + 1], a
    ld a, [hl+]
    ld [wCamY], a
    ld a, [hl+]
    ld [wCamY + 1], a
    ld a, [hl+]
    ld [wYaw], a
    ld a, [hl+]
    ld [wEntOX], a
    ld a, [hl+]
    ld [wEntOX + 1], a
    ld a, [hl+]
    ld [wEntOZ], a
    ld a, [hl+]
    ld [wEntOZ + 1], a
    ld a, [hl+]
    ld [wEntOY], a
    ld a, [hl+]
    ld [wEntOY + 1], a
    ld a, [hl+]
    ld [wEntYaw], a
    ld a, l
    ld [wPosePtr], a
    ld a, h
    ld [wPosePtr + 1], a
    ; mesh header
    ld a, [wTestRoom]
    and a
    jr nz, .enemy
    ld b, 0
    ld hl, ItemTab
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; HL = item mesh
    ld a, [hl+]
    ld [wEntNV], a
    ld a, [hl+]
    ld [wEntNE], a
    ld a, [hl+]
    ld [wEntShift], a
    ld a, [hl+]
    ld [wEntRadius], a
    ld a, l
    ld [wEntVP], a
    ld a, h
    ld [wEntVP + 1], a              ; verts follow the 4-byte header
    ld a, [wEntNV]
    ld c, a
    add a
    add c                           ; nv * 3
    ld c, a
    ld b, 0
    add hl, bc
    ld a, l
    ld [wEntEP], a
    ld a, h
    ld [wEntEP + 1], a
    jr .draw
.enemy:
    ld b, 0
    ld hl, EnemyTab
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a                         ; HL = enemy record
    ld a, [hl+]
    ld [wEntNV], a
    ld a, [hl+]
    ld [wEntNE], a
    ld a, [hl+]
    ld [wEntShift], a
    ld a, [hl+]
    ld [wEntRadius], a
    ld bc, 4 + 10                   ; skip nframes, hp, block_r, weapon_vert + clip table
    add hl, bc
    ld a, l
    ld [wEntEP], a
    ld a, h
    ld [wEntEP + 1], a
    ld a, [wEntNE]
    add a
    ld c, a
    ld b, 0
    add hl, bc                      ; HL = frame 0
    ld a, [wEntNV]
    ld c, a
    add a
    add c
    ld c, a                         ; bytes per frame
    ld a, [wTestKeys]
.frame:
    and a
    jr z, .gotFrame
    ld b, 0
    add hl, bc
    dec a
    jr .frame
.gotFrame:
    ld a, l
    ld [wEntVP], a
    ld a, h
    ld [wEntVP + 1], a
.draw:
IF DEF(ENTTIME)
    call DrawEntity
ELSE
    call ClearFB
    call DrawEntity
    call FletcherFB
ENDC
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, d
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wTestCnt]
    inc a
    ld [wTestCnt], a
    cp NumEntTests
    jp nz, .case
IF DEF(ENTTIME)
    call TimerRead
    ld a, c
    ld [wPoseTicks], a
    ld a, b
    ld [wPoseTicks + 1], a
ENDC
    ret
ENDC

IF DEF(SMOKE)
; Headless gameplay scenario (tools/gbc_smoke.py): load a level / room, place the player, run
; SmokeFrames game updates with a scripted pad (no drawing), dump the state after the "POSE"
; magic. Scenario: db level, room; dw camx, camz, camy; db yaw, floor_y, keys, wmask, wcur, hp,
; bullets, shells, rockets, frames, dt ; then frames bytes of pad state.
RunSmoke::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    ld hl, SmokeScenario
    ld a, [hl+]
    ld b, a                         ; level
    ld a, [hl]
    ld [wTestRoom], a
    ld a, b
    call LoadLevel
    call WpnInit
    xor a
    ld [wEmuzSeen], a
    ld [wEmuzMs], a
    ld [wSplatSeen], a
    ld [wSplatDrawn], a
    ld a, [wTestRoom]
    call EnterRoom
    ld hl, SmokeScenario + 2
    ld a, [hl+]
    ld [wCamX], a
    ld a, [hl+]
    ld [wCamX + 1], a
    ld a, [hl+]
    ld [wCamZ], a
    ld a, [hl+]
    ld [wCamZ + 1], a
    ld a, [hl+]
    ld [wCamY], a
    ld a, [hl+]
    ld [wCamY + 1], a
    ld a, [hl+]
    ld [wYaw], a
    xor a
    ld [wTurnFrac], a               ; the spec starts every case with no carried yaw fraction
    ld a, [hl+]
    ld [wFloorY], a
    ld a, [hl+]
    ld [wHaveKeys], a
    ld a, [hl+]
    ld [wHaveWpn], a
    ld a, [hl+]
    ld [wWpnCur], a
    ld a, [hl+]
    ld [wHP], a
    ld a, [hl+]
    ld [wAmmoBul], a
    ld a, [hl+]
    ld [wAmmoShl], a
    ld a, [hl+]
    ld [wAmmoRkt], a
    ld a, [hl+]
    ld [wTestCnt], a                ; frames
    ld a, [hl+]
    ld [wTestCnt + 1], a            ; dt
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    xor a
    ld [wStepCnt], a
    ld [wSpin], a
.frame:
    ld a, [wScriptPtr]
    ld l, a
    ld a, [wScriptPtr + 1]
    ld h, a
    ld a, [hl+]
    ldh [hJoy], a
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
IF DEF(SMOKEDRAW)
    ; the real demo frame: draw, flip, then UpdateMove (real frame time, room changes) and the game
    ldh a, [hJoy]
    ld [wScriptJoy], a
    call ClearFB
    call RenderScene
    call DrawWorldObjects
IF !DEF(SDNODISP)
IF !DEF(SDNOCOPY)
    ldh a, [hShow]
    xor 1
    call CopyFBHBlank
ENDC
IF !DEF(SDNOWAIT)
    call WaitVBlank
ENDC
    ldh a, [hShow]
    xor 1
    ldh [hShow], a
IF !DEF(SDNOSHOW)
    call ShowBank
ENDC
IF !DEF(SDNOWPN)
    call WpnVBlank
ENDC
IF !DEF(SDNOHUD)
    call HudBlit
ENDC
ENDC
IF DEF(SDAPPLY)
    ld a, [wTestCnt + 1]
    ld [wMoveDt], a
    ld b, a
    ld a, [wSpin]
    add b
    ld [wSpin], a
    call HoldsFromJoy
    call ApplyMove
ELSE
    call UpdateMove
ENDC
    call LevelUpdate
    call WpnUpdate
    call PickupScan
    call CombatUpdate
    call HudUpdate
ELSE
    ld a, [wTestCnt + 1]
    ld [wMoveDt], a
    ld b, a
    ld a, [wSpin]
    add b
    ld [wSpin], a
    call HoldsFromJoy
    call ApplyMove
    call WpnUpdate
    call PickupScan
    call CombatUpdate
ENDC
    ld a, [wStepCnt]
    inc a
    ld [wStepCnt], a
    ld b, a
    ld a, [wTestCnt]
    cp b
    jr nz, .frame
    ; ---- dump ----
    ld hl, wPoseOut
    ld a, [wHP]
    ld [hl+], a
    ld a, [wArmor]
    ld [hl+], a
    ld a, [wKills]
    ld [hl+], a
    ld a, [wAmmoBul]
    ld [hl+], a
    ld a, [wAmmoShl]
    ld [hl+], a
    ld a, [wAmmoRkt]
    ld [hl+], a
    ld a, [wHaveWpn]
    ld [hl+], a
    ld a, [wHaveKeys]
    ld [hl+], a
    ld a, [wWpnCur]
    ld [hl+], a
    ld a, [wRoom]
    ld [hl+], a
    ld a, [wCamX]
    ld [hl+], a
    ld a, [wCamX + 1]
    ld [hl+], a
    ld a, [wCamZ]
    ld [hl+], a
    ld a, [wCamZ + 1]
    ld [hl+], a
    ld a, [wCamY]
    ld [hl+], a
    ld a, [wCamY + 1]
    ld [hl+], a
    ld a, [wFloorY]
    ld [hl+], a
    ld a, [wFalling]
    ld [hl+], a
    ld a, [wLevel]
    ld [hl+], a
    ld a, [wEnN]
    ld [hl+], a                     ; offset 19: enemy count
    ld a, [wPkN]
    ld [hl+], a
    ld a, [wPkI]
    ld [hl+], a
    ld a, [wPkIdx]
    ld [hl+], a
    ld a, [wPkType]
    ld [hl+], a
    ld a, [wObjBank]
    ld [hl+], a
    ld a, [wLevelBank]
    ld [hl+], a
    ld a, [wWpnDy]
    ld [hl+], a                     ; offset 26: weapon dy (recoil test)
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
                                    ; debug bytes 20..25, pad to 32
    ld de, wThTaken
    ld b, 32
.th:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .th
    ld de, wEnState
    ld b, 24
.es:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .es
    ld de, wEnHp
    ld b, 24
.eh:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .eh
    ld de, wEnX
    ld b, 24
.ex:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .ex
    ld de, wEnZ
    ld b, 24
.ez:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .ez
    ld de, wEnFrame                 ; offset 160: A8 en_frame
    ld b, 24
.ef:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .ef
    ld de, wEnRot                   ; offset 184: A8 en_rot
    ld b, 24
.er:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .er
    ld de, wEnDir                   ; offset 208: A8 en_dir
    ld b, 24
.ed:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .ed
    ld de, wEnTimer                 ; offset 232: A8 en_timer (low)
    ld b, 24
.et:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .et
    ld a, [wGunshotWake]            ; offset 256
    ld [hl+], a
    ld de, wPrOn                    ; offset 257: fireball slots on / x / z / life
    ld b, 4
.po:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .po
    ld de, wPrX
    ld b, 4
.px:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .px
    ld de, wPrZ
    ld b, 4
.pz:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .pz
    ld de, wPrLifeH                 ; life ms, high byte
    ld b, 4
.pl:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .pl
    ld a, [wPrVXL]                  ; offset 273: slot 0 velocity (x lo, x hi, z lo, z hi), wAng
    ld [hl+], a
    ld a, [wPrVXH]
    ld [hl+], a
    ld a, [wPrVZL]
    ld [hl+], a
    ld a, [wPrVZH]
    ld [hl+], a
    ld a, [wAng]
    ld [hl+], a
    ld a, [wPrXL]
    ld [hl+], a
    ld a, [wPrZL]
    ld [hl+], a
    ld de, wHudRows                 ; offset 280: HUD rows 14-17 (80 tile ids)
    ld b, 80
.hr:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .hr
    ld a, [wHurtMs]                 ; offset 360: hurt flash ms left, border colour, status ms, raw dt
    ld [hl+], a
    ld a, [wHurtMs + 1]
    ld [hl+], a
    ld a, [wPalBorder]
    ld [hl+], a
    ld a, [wStatusMs]
    ld [hl+], a
    ld a, [wStatusMs + 1]
    ld [hl+], a
    ld a, [wRawDt]
    ld [hl+], a
    ld a, [wEmuzSeen]               ; offset 366: muzzle starts, last LOD / column / row
    ld [hl+], a
    ld a, [wEmuzLod]
    ld [hl+], a
    ld a, [wEmuzCol]
    ld [hl+], a
    ld a, [wEmuzY]
    ld [hl+], a
    ld c, 0                         ; offset 370: door key / type of the first 16 doors
.dk:
    ld a, F_DOOR_KEY
    push hl
    call MapGet
    pop hl
    ld [hl+], a
    ld a, F_DOOR_TYPE
    push hl
    call MapGet
    pop hl
    ld [hl+], a
    inc c
    ld a, c
    cp 16
    jr nz, .dk
    ld de, wElevY                   ; offset 402: elevator heights, targets, the car under the player
    ld b, 8
.ey:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .ey
    ld de, wElevTgt
    ld b, 8
.et2:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .et2
    ld a, [wOnElev]
    ld [hl+], a
    ld a, [wFxMs]                   ; offset 419: explosion time left, pixels plotted, velocities
    ld [hl+], a
    ld a, [wFxMs + 1]
    ld [hl+], a
    ld a, [wFxPlots]
    ld [hl+], a
    ld de, wFxVx
    ld b, 48
.fv:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .fv
    ld a, [wSplatSeen]              ; offset 470: splats started, colour, time left, origin cells
    ld [hl+], a
    ld a, [wSplatCol]
    ld [hl+], a
    ld a, [wSplatMs]
    ld [hl+], a
    ld a, [wSplatOrg + 1]
    ld [hl+], a
    ld a, [wSplatOrg + 3]
    ld [hl+], a
    ld a, [wSplatOrg + 5]
    ld [hl+], a
    ld a, [wSplatDrawn]
    ld [hl+], a
    ret
ENDC

IF DEF(PICKUNIT)
; Apply every pickup type in PickUnitTab to a fresh player; after each, store
; (hp, armor, bullets, shells, rockets, weapons, keys) -> wPoseOut, 7 bytes per step.
RunPickUnit::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    call WpnInit
    xor a
    ld [wHaveKeys], a
    ld hl, PickUnitTab
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    xor a
    ld [wTestCnt], a
.next:
    ld a, [wScriptPtr]
    ld l, a
    ld a, [wScriptPtr + 1]
    ld h, a
    ld a, [hl+]
    ld b, a
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    ld a, b
    call ApplyPickup
    ld a, 0
    adc 0                           ; 1 = used up
    ld e, a
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, [wHP]
    ld [hl+], a
    ld a, [wArmor]
    ld [hl+], a
    ld a, [wAmmoBul]
    ld [hl+], a
    ld a, [wAmmoShl]
    ld [hl+], a
    ld a, [wAmmoRkt]
    ld [hl+], a
    ld a, [wHaveWpn]
    ld [hl+], a
    ld a, [wHaveKeys]
    ld [hl+], a
    ld a, [wHavePack]
    ld [hl+], a
    ld a, [wArmorKind]
    ld [hl+], a
    ld a, [wWpnCur]
    ld [hl+], a
    ld a, e
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wTestCnt]
    inc a
    ld [wTestCnt], a
    cp NumPickUnit
    jr nz, .next
    ret
ENDC

IF DEF(COMBUNIT)
; AngleTo and PlayerDamage against tools/gbc_game.py: one angle byte per angle case, then
; (hp, armor) per damage case, all into wPoseOut.
RunCombUnit::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    ld hl, AngCases
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, LOW(NumAngCases)
    ld [wTestCnt], a
    ld a, HIGH(NumAngCases)
    ld [wTestCnt + 1], a
.ang:
    ld a, [wScriptPtr]
    ld l, a
    ld a, [wScriptPtr + 1]
    ld h, a
    ld a, [hl+]
    ld [wDx], a
    ld a, [hl+]
    ld [wDx + 1], a
    ld a, [hl+]
    ld [wDz], a
    ld a, [hl+]
    ld [wDz + 1], a
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    call AngleTo
    ld b, a
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, b
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wTestCnt]
    sub 1
    ld [wTestCnt], a
    ld a, [wTestCnt + 1]
    sbc 0
    ld [wTestCnt + 1], a
    ld b, a
    ld a, [wTestCnt]
    or b
    jr nz, .ang
    ; damage cases
    ld hl, DmgCases
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    ld a, NumDmgCases
    ld [wTestCnt], a
.dmg:
    ld a, [wScriptPtr]
    ld l, a
    ld a, [wScriptPtr + 1]
    ld h, a
    ld a, [hl+]
    ld [wHP], a
    ld a, [hl+]
    ld [wArmor], a
    ld b, [hl]
    inc hl
    ld a, [hl+]
    ld [wArmorKind], a
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    ld a, b
    call PlayerDamage
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld a, [wHP]
    ld [hl+], a
    ld a, [wArmor]
    ld [hl+], a
    ld a, [wArmorKind]
    ld [hl+], a
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wTestCnt]
    dec a
    ld [wTestCnt], a
    jr nz, .dmg
    ret
ENDC

IF DEF(LOSUNIT)
; Enemy line of sight (gbc/ai.asm LineSolidsBlocked) against tools/gbc_losunit.py: per LosCases entry
; (db level, room, ax, ay, az, bx, by, bz) load the level / room, test the segment, store 1 = blocked.
RunLosUnit::
    ld hl, wPoseMagic
    ld a, 'P'
    ld [hl+], a
    ld a, 'O'
    ld [hl+], a
    ld a, 'S'
    ld [hl+], a
    ld a, 'E'
    ld [hl], a
    ld hl, LosCases
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    ld hl, wPoseOut
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, LOW(NumLosCases)
    ld [wTestCnt], a
    ld a, HIGH(NumLosCases)
    ld [wTestCnt + 1], a
.case:
    ld a, BANK(LosCases)
    ld [rROMB0], a
    ld a, [wScriptPtr]
    ld l, a
    ld a, [wScriptPtr + 1]
    ld h, a
    ld de, wDbgOut
    ld b, 8
.cp:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .cp
    ld a, l
    ld [wScriptPtr], a
    ld a, h
    ld [wScriptPtr + 1], a
    ld a, [wDbgOut]
    ld b, a
    ld a, [wLevel]
    cp b
    jr z, .same
    ld a, b
    call LoadLevel
.same:
    ld a, [wDbgOut + 1]
    ld [wRoom], a
    call EnterRoom
    ld hl, wDbgOut + 2
    ld de, wLnA
    ld b, 6
.ab:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .ab
    ld a, BANK(LineSolidsBlocked)
    ld [rROMB0], a
    call LineSolidsBlocked
    ld a, 0
    adc 0                           ; 1 = blocked
    ld b, a
    ld a, [wOutPtr]
    ld l, a
    ld a, [wOutPtr + 1]
    ld h, a
    ld [hl], b
    inc hl
    ld a, l
    ld [wOutPtr], a
    ld a, h
    ld [wOutPtr + 1], a
    ld a, [wTestCnt]
    sub 1
    ld [wTestCnt], a
    ld a, [wTestCnt + 1]
    sbc 0
    ld [wTestCnt + 1], a
    ld b, a
    ld a, [wTestCnt]
    or b
    jp nz, .case
    ret
ENDC
