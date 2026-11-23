; HRAM variables (127 bytes at $FF80-$FFFE) and WRAM reservations.
;
; WRAM map: WRAM0 $C000-$CDFF framebuffer, $CE00-$CEFF free (hot vars), $CF00-$CFFF stack.
;           WRAMX bank 1 (always mapped): engine state. WRAMX bank 2: packed map payload,
;           mapped only inside MapGet-style bursts (SVBK = 2) and back to 1 afterwards.

SECTION "hram", HRAM

hFrame::     ds 1
hVBlank::    ds 1
hJoy::       ds 1
hSpeed::     ds 1
hSavedSP::   ds 2
hShow::      ds 1                   ; VRAM bank currently displayed
hLastFrame:: ds 1                   ; hFrame at the end of the previous game frame

; DrawLine scratch
hPhase::     ds 1
hPtrH::      ds 1
hPtrL::      ds 1
hKind::      ds 1

; Benchmark timer
hOver::      ds 1                   ; TIMA overflow count (timer ISR)
hLoop::      ds 1

; Math scratch
hSign::      ds 1
hT0::        ds 1
hT1::        ds 1
hT2::        ds 1
hT3::        ds 1
hR::         ds 2                   ; reciprocal for ProjectMul
hS::         ds 1                   ; shift for ProjectMul

; Framebuffer: 16 columns x 224 B at $C000-$CDFF. $CE00-$CEFF is free (hot vars);
; the stack owns $CF00-$CFFF (STACK_TOP = $D000).
SECTION "framebuffer", WRAM0[$C000]
wFB::        ds $0E00

SECTION "benchram", WRAMX, BANK[1]
wBenchMagic:: ds 4
wBenchOut::   ds 32

; Render pages: 16-bit arrays at fixed offsets so index*2 + offset is the low byte.
;   wUniq : UXC@0 UXS@16 UZC@32 UZS@48 (8 entries each); magic @240
;   wCols : CX@0 CZ@32 CSX@64 CR@96 (16 entries each); CS@128 CF@144 (bytes); magic @240
;   wVerts: VX@0 VY@32 VZ@64 VSX@96 VSY@128 (16 entries); VF@160 (bytes); magic @240
SECTION "wpages", WRAMX, BANK[1], ALIGN[8]
wUniq::      ds 256
wCols::      ds 256
wVerts::     ds 256

SECTION "wpts", WRAMX, BANK[1], ALIGN[3]
wPts::       ds 8                   ; x0 y0 x1 y1 (16-bit each)

; Current room mesh (loaded by LoadMesh): caps 8 unique X/Z, 16 cols, 16 verts, 32 edges.
SECTION "scenebuf", WRAMX, BANK[1]
wSceneNUX::   ds 1
wSceneNUZ::   ds 1
wSceneNC::    ds 1
wSceneNV::    ds 1
wSceneNE::    ds 1
wSceneUX::    ds 8
wSceneUZ::    ds 8
wSceneCols::  ds 32
wSceneVerts:: ds 32
wSceneEdges:: ds 64

SECTION "rvars", WRAMX, BANK[1]
wCamX::      ds 2
wCamY::      ds 2
wCamZ::      ds 2
wYaw::       ds 1
wSin::       ds 1
wCos::       ds 1
wI::         ds 1
wXid::       ds 1
wZid::       ds 1
wVa::        ds 1
wVb::        ds 1
wFa::        ds 1
wFb::        ds 1
wMe::        ds 1
wOth::       ds 1
wDst::       ds 2
wOc0::       ds 1
wOc1::       ds 1
wGuard::     ds 1
wBnd::       ds 2
wTa::        ds 2
wTb::        ds 2
wTc::        ds 2
wTx::        ds 2
wTy::        ds 2
wPoseI::     ds 1
wPosePtr::   ds 2
wOutPtr::    ds 2
wPoseMagic:: ds 4
wPoseTicks:: ds 2
wPoseOut::   ds 1024
wCamSave::   ds 8
wTestCnt::   ds 2
wTestRoom::  ds 1
wFindOut::   ds 400
wDbgOut::    ds 160
wScriptPtr:: ds 2
wStepCnt::   ds 1

; Level / world state
SECTION "worldvars", WRAMX, BANK[1]
wLevel::      ds 1
wRoom::       ds 1                  ; current room index ($FF = none)
wMapHdr::     ds 23                 ; packed header (H_* offsets in map_fields.inc)
wRoomTab::    ds 2                  ; ROM pointer: per-room mesh record table
wLoadSrc::    ds 2
wLoadLen::    ds 2
wFOffPtr::    ds 2
wFieldPtr::   ds 240                ; NUM_FIELDS (120) words: column base inside wMap (bank 2)
wMoveDt::     ds 1

; The packed map payload (<= 3901 B for the largest level) in its own WRAM bank.
SECTION "mapram", WRAMX, BANK[2]
wMap::        ds 4096

; Current room's collision data, copied from the cooker's 159-byte record (gbc_world.room_record).
; Layout must match exactly: colliders (4-entry arrays), join masks, crates, solid platforms, slopes.
SECTION "roomcache", WRAMX, BANK[1]
wRoomCache::
wRcX::        ds 4
wRcY::        ds 4
wRcZ::        ds 4
wRcSX::       ds 4
wRcSY::       ds 4
wRcSZ::       ds 4
wRcJ::        ds 12                 ; [collider*4 + face], face 0 xmin 1 xmax 2 zmin 3 zmax; bit j = sibling j
wCrN::        ds 1
wCrX::        ds 8
wCrY::        ds 8
wCrZ::        ds 8
wCrSX::       ds 8
wCrSY::       ds 8
wCrSZ::       ds 8
wPlN::        ds 1
wPlX::        ds 8
wPlY::        ds 8
wPlZ::        ds 8
wPlSX::       ds 8
wPlSZ::       ds 8
wSlN::        ds 1
wSlX::        ds 4
wSlY::        ds 4
wSlZ::        ds 4
wSlSX::       ds 4
wSlSY::       ds 4
wSlSZ::       ds 4
wSlAxis::     ds 4
wSlDir::      ds 4
wRoomCacheEnd::

SECTION "collvars", WRAMX, BANK[1]
wCollTab::    ds 2
wColX::       ds 1
wColZ::       ds 1
wBoxX::       ds 1
wBoxY::       ds 1
wBoxZ::       ds 1
wBoxSX::      ds 1
wBoxSY::      ds 1
wBoxSZ::      ds 1
wJk::         ds 1
wJf::         ds 1
wJmask::      ds 1
wVal::        ds 1
wFound::      ds 1
wFloorTmp::   ds 1
wTmpY::       ds 1
wRun::        ds 1
wFrac::       ds 1
wSlYv::       ds 1
wSlI::        ds 1
wFloorY::     ds 1
wFloorYL::    ds 1
wFloorSlope:: ds 1
wFalling::    ds 1
wFallVL::     ds 1
wFallVH::     ds 1
wFallAcc::    ds 1
wFallY0::     ds 1
wAcc::        ds 1
wDtMs::       ds 1
wLedgeI::     ds 1
wLedgeSaveY:: ds 1
wWishX::      ds 2
wWishZ::      ds 2
wSaveX::      ds 2
wF1::         ds 1
wF2::         ds 1
