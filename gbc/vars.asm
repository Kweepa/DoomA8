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
hSh::        ds 1                   ; SMulSh8 product shift
hRnd::        ds 1                   ; LFSR state (never 0)

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
wTestKeys::  ds 1

; Level / world state
SECTION "worldvars", WRAMX, BANK[1]
wLevel::      ds 1
wRoom::       ds 1                  ; current room index ($FF = none)
wMapHdr::     ds 23                 ; packed header (H_* offsets in map_fields.inc)
wRoomTab::    ds 2                  ; ROM pointer: per-room mesh record table
wLoadSrc::    ds 2
wLoadLen::    ds 2
wFOffPtr::    ds 2
wMoveDt::     ds 1

; Field pointer table: NUM_FIELDS (120) words, base of each column inside wMap (bank 2).
; Page aligned so MapGet can index it with one `ld l`.
SECTION "fieldptr", WRAMX, BANK[1], ALIGN[8]
wFieldPtr::   ds 240

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
wDrN::        ds 1
wDrIdx::      ds 8                  ; global door index (payload door_key / door_type)
wDrX::        ds 8
wDrY::        ds 8
wDrZ::        ds 8
wDrSX::       ds 8
wDrSZ::       ds 8
wDrFace::     ds 8
wDrOther::    ds 8
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
wHaveKeys::   ds 1                  ; HAVE_YELLOW 1 / HAVE_BLUE 2 / HAVE_RED 4
wDoorBlk::    ds 1                  ; bit0 = X move rejected, bit1 = Z
wDoorI::      ds 1
wTdwSave::    ds 4

; Entity draw state (entity.asm)
SECTION "entvars", WRAMX, BANK[1]
wEntOX::      ds 2
wEntOZ::      ds 2
wEntOY::      ds 2
wEntYaw::     ds 1
wEntVP::      ds 2                  ; local vertex array (signed x,y,z bytes)
wEntEP::      ds 2                  ; edge array (a,b bytes)
wEntNV::      ds 1
wEntNE::      ds 1
wEntShift::   ds 1                  ; S: local units are 2^-S world units
wEntRadius::  ds 1
wEntSh::      ds 1
wEntX0::      ds 2
wEntY0::      ds 2
wEntZ0::      ds 2
wEntX::       ds 2
wEntY::       ds 2
wEntZ::       ds 2
wEntAX::      ds 2
wEntAZ::      ds 2
wEntSin::     ds 1
wEntCos::     ds 1
wEntI::       ds 1
wEntLX::      ds 1
wEntLY::      ds 1
wEntLZ::      ds 1
wEntCur::     ds 2

; World objects / enemies (objects.asm)
SECTION "objvars", WRAMX, BANK[1]
wObjTab::     ds 2                  ; ROM pointer: per-room static/thing lists (object bank)
wObjBank::    ds 1
wLevelBank::  ds 1
wObjN::       ds 1
wObjI::       ds 1
wObjPtr::     ds 2
wTmpMesh::    ds 2
wTmpKind::    ds 1
wTmpAux::     ds 1
wTmpFrame::   ds 1
wSpin::       ds 1                  ; animation counter (VBlanks)
wEdgeN::      ds 1                  ; edge list for DrawEdges
wEdgePtr::    ds 2
wThTaken::    ds 32
wEnN::        ds 1
wEnX::        ds 24
wEnY::        ds 24
wEnZ::        ds 24
wEnType::     ds 24
wEnRoom::     ds 24
wEnYaw::      ds 24
wEnState::    ds 24
wEnFrame::    ds 24
wEnHp::       ds 24
wEnXL::       ds 24
wEnZL::       ds 24
wEnTimer::    ds 24
wEnCool::     ds 24

; Player / weapons (wpn.asm)
SECTION "wpnvars", WRAMX, BANK[1]
wHP::         ds 1
wArmor::      ds 1
wKills::      ds 1
wHaveWpn::    ds 1                  ; bit per weapon id
wWpnCur::     ds 1
wAmmoNone::   ds 1                  ; always 0 (ammo slot of weapons that need none)
wAmmoBul::    ds 1
wAmmoShl::    ds 1
wAmmoRkt::    ds 1
wWpnTimer::   ds 1                  ; VBlanks until the next shot
wWpnAnim::    ds 1
wWpnAnimLen:: ds 1
wFlashTimer:: ds 1
wFlashSel::   ds 1
wWpnSelPrev:: ds 1
wBobPhase::   ds 1
wFireEvent::  ds 1                  ; set by WpnUpdate when a shot fires this frame
wOamUsed::    ds 1
wUsedNow::    ds 1
wLoadedBody:: ds 1
wLoadedFlash:: ds 1
wBodyFrame::  ds 1
wFlashFrame:: ds 1
wBodyN::      ds 1
wBodyW::      ds 1
wBodyH::      ds 1
wFlashN::     ds 1
wFlashW::     ds 1
wFlashH::     ds 1
wWpnW::       ds 1
wWpnH::       ds 1
wBodyPlace::  ds 32
wFlashPlace:: ds 16
wBobX::       ds 1
wBobY::       ds 1
wKick::       ds 1
wOx::         ds 1
wOy::         ds 1
wFx::         ds 1
wFy::         ds 1
wCnt::        ds 1
wTile::       ds 1
wDec::        ds 3
wHud::        ds 15
wPkN::        ds 1
wPkI::        ds 1
wPkIdx::      ds 1
wPkType::     ds 1
wEx::         ds 1
wExL::        ds 1
wEz::         ds 1
wEzL::        ds 1
wDx::         ds 2
wDz::         ds 2
wDist::       ds 2
wAng::        ds 1
wAngSw::      ds 1
wDmg::        ds 1
wShRange::    ds 1
wShMin::      ds 1
wShMask::     ds 1
wShSplash::   ds 1
wShDmg::      ds 1
wBestF::      ds 2
wBestI::      ds 1
wTgtI::       ds 1
wTgtX::       ds 1
wTgtZ::       ds 1
wParam::      ds 2
wMvX::        ds 2
wMvZ::        ds 2
wNx::         ds 1
wNxL::        ds 1
wNz::         ds 1
wNzL::        ds 1
wDeadTimer::  ds 1

; Enemy AI + fireballs (gbc/ai.asm). $CE00-$CEFF is the free page between the framebuffer and the stack.
SECTION "aivars", WRAM0[$CE00]
wEnDir::      ds 24                  ; walk octant 0..7 (0 = +z, 2 = +x), $FF = none yet
wEnStep::     ds 24                  ; VBlanks walked in the current direction
wEnAtk::      ds 24                  ; attack kind: 0 melee / hitscan, 1 fireball
wPrOn::       ds 4
wPrFl::       ds 4                   ; bit 0: baron fireball
wPrRoom::     ds 4
wPrXL::       ds 4
wPrX::        ds 4
wPrZL::       ds 4
wPrZ::        ds 4
wPrY::        ds 4                   ; chest height (cells)
wPrFlY::      ds 4                   ; floor of the thrower
wPrVXL::      ds 4                   ; 8.8 per VBlank
wPrVXH::      ds 4
wPrVZL::      ds 4
wPrVZH::      ds 4
wPrLife::     ds 4
wAiI::        ds 1
wAiT::        ds 1
wAiK::        ds 1
wAiN::        ds 1
wAiTry::      ds 5
wAiO::        ds 4                   ; position before a step: x, xl, z, zl
wLpXL::       ds 1
wLpX::        ds 1
wLpZL::       ds 1
wLpZ::        ds 1
wLsx::        ds 1
wLsz::        ds 1
wCellFy::     ds 1
wRawDt::      ds 1                   ; VBlanks the last frame took (unclamped)
wScriptJoy::  ds 1
