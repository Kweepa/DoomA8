; Pose test: render every pose, store a Fletcher-16 of the framebuffer per pose,
; then time NumPoses renders. tools/gbc_posetest.py compares against the spec.
; Results (after the "POSE" magic): ticks word, then one word per pose.

INCLUDE "hw.inc"

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
    call LoadRoomMesh
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

; HL = src, DE = dst, B = count (>0)
CopyBytes:
.l:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .l
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
    call ApplyMove
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
    ret
ENDC
