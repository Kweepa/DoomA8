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
