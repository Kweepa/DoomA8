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
hPlane::     ds 1                   ; DrawLine bitplane: 0 ink, 1 red (fireballs)

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
wSpin::       ds 1                  ; VBlank counter (demo / tests)
wItemSpin::   ds 2                  ; A8 item_spin (8.8 yaw): += dt_ms << 4, ~1 rev / 4.1 s
wEdgeN::      ds 1                  ; edge list for DrawEdges
wEdgePtr::    ds 2
wThTaken::    ds 32
wEnN::        ds 1
wEnX::        ds 24
wEnY::        ds 24
wEnZ::        ds 24
wEnType::     ds 24
wEnRoom::     ds 24
wEnRot::      ds 24                  ; A8 en_rot: heading 0 = +z, 64 = +x (mesh yaw = -en_rot)
wEnState::    ds 24
wEnFrame::    ds 24                  ; A8 en_frame: frame within the current clip
wEnHp::       ds 24
wEnXL::       ds 24
wEnZL::       ds 24
wEnTimer::    ds 24                  ; A8 en_timer / en_timer_h: attack pause ms
wEnTimerH::   ds 24
wEnStepH::    ds 24                  ; A8 en_step_h (low byte: wEnStep)
wEnPainI::    ds 24                  ; A8 en_pain_i: pain / death variant
wAnimAcc::    ds 2                   ; A8 anim_acc: ms toward ANIM_MS
wDoomAnimPh:: ds 1                   ; A8 doom_anim_ph
wGunshotWake:: ds 1                  ; A8 gunshot_wake: a gun fired this frame
wEnSfxOld::   ds 1                   ; A8 en_sfx_old: frame before this anim step
wEnNewFrame:: ds 1                   ; frame after this anim step (attack fire check)
wAiTurn::     ds 1                   ; A8 ai_turn / dodge_dx / dodge_dz / dodge_i / ai_probe
wDodgeDx::    ds 1
wDodgeDz::    ds 1
wDodgeI::     ds 1
wAiProbe::    ds 1
wPreX::       ds 1                   ; A8 save_xh / save_zh: player cell before this move axis
wPreZ::       ds 1
; A8 line_* segment test (gbc/ai.asm LineSolidsBlocked)
wLnA::        ds 3                   ; ln_ax / ay / az
wLnB::        ds 3                   ; ln_bx / by / bz
wLBox::       ds 6                   ; box_x, y, z, sx, sy, sz
wLnM::        ds 3                   ; ln_mx / my / mz (exclusive max)
wLnOc0::      ds 1
wLnOc1::      ds 1
wLnBit::      ds 1
wLnFace::     ds 1
wLnPlane::    ds 1
wLnT::        ds 1
wLnBest::     ds 1
wLdSign::     ds 1
wLnT0::       ds 1
wLnT1::       ds 1
wLnD::        ds 1
wLnPx::       ds 1
wLnCam::      ds 4
wLnI::        ds 1
wLnH0::       ds 1
wLnH1::       ds 1
wLnRel0::     ds 1
wLnRel1::     ds 1
wOrgX::       ds 2                   ; A8 org_*: world 8.8 of a bone (EnVertWorld)
wOrgY::       ds 2
wOrgZ::       ds 2
wRkAcc::      ds 2                   ; rkt_tick ms accumulator
wRkNew::      ds 2                   ; save_xl / save_xh: candidate coordinate
wRkOld::      ds 2
wZcSg::       ds 3                   ; .z_aim: signed / absolute deltas
wZcAd::       ds 3
wEmuzMs::     ds 1                   ; A8 world-sprite timer for the enemy muzzle (ms left)
wEmuzLod::    ds 1
wEmuzCol::    ds 1                   ; byte column of the 24x21 box (0 .. VIEW_COLS - 3)
wEmuzY::      ds 1
wEmuzK::      ds 1
wEmuzSeen::   ds 1                   ; smoke builds: muzzle starts

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
wWpnDy::      ds 1                  ; signed: overhang + bob + recoil
wSawFlip::    ds 1
wOx::         ds 1
wOy::         ds 1
wFx::         ds 1
wFy::         ds 1
wCnt::        ds 1
wTile::       ds 1
wDec::        ds 3
wHudRows::    ds 80                  ; HUD map rows 14-17 (20 tiles each; row 14 = message), gbc/hud.asm
wMsgTmp::     ds 32                  ; message text being assembled (ASCII, NUL)
wStatusMs::   ds 2                   ; A8 status_ms: message time left
wHurtMs::     ds 2                   ; A8 hurt_flash: red border time left
wPalStage::   ds 32                  ; BG palettes 0-3 (BGR555) for HudBlit
wPalDirty::   ds 1
wPalRoom::    ds 1                   ; room / border colour the staged palettes were built for
wPalBorder::  ds 1
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
wDeadMs::     ds 2                   ; A8 death_wait: ms since the player died
wHavePack::   ds 1                   ; A8 have_pack: backpack doubles the ammo caps
wArmorKind::  ds 1                   ; A8 combat_armor: 1 blue (saves 1/2), 0 green (5/16)
wPuKind::     ds 1                   ; A8 pu_kind: 0 or TH_RADSUIT
wPuMs::       ds 2                   ; A8 pu_ms: powerup time left
wPickupMs::   ds 2                   ; A8 pickup_ms: no grabs while > 0
wApTy::       ds 1                   ; ApplyPickupB scratch
wApCap::      ds 1
wApForce::    ds 1
wPkX::        ds 1
wPkY::        ds 1
wPkZ::        ds 1
wScanLim::    ds 2                   ; GunScan: flat cone half-width (tan 8.8)
wScanAim::    ds 1                   ; pellet column, signed px (A8 scan_aim)
wScanPel::    ds 1                   ; 1 = pellet test
wScanCnt::    ds 1
wScanBest::   ds 1                   ; A8 shot_hit_i / shot_hit_z
wScanBestZ::  ds 1
wShF::        ds 2                   ; forward / lateral of the enemy in view space (8.8)
wShL::        ds 2
wShLSign::    ds 1
wTgt::        ds 3                   ; ScanCand target cell (x, y, z)
wTgtR::       ds 1                   ; its body radius (units)
wScanId::     ds 1                   ; candidate id: enemy index, or $40 + thing index (barrel)
wBlast::      ds 3                   ; A8 ent_wx / wy / wz: blast origin (cells)
wBlastRoom::  ds 1
wFxMs::       ds 2                   ; A8 fx_on: explosion graphic time left (one at a time)
wBarrelCh::   ds 2                   ; A8 barrel_ch: ms to the next chained barrel
wBarrelPend:: ds 4                   ; A8 barrel_pend: one bit per thing
wDvN::        ds 3                   ; Div24x16 numerator / quotient

; Enemy AI + fireballs (gbc/ai.asm). $CE00-$CEFF is the free page between the framebuffer and the stack.
SECTION "aivars", WRAM0[$CE00]
wEnDir::      ds 24                  ; A8 en_dir: octant 0..7 (0 = +z, 2 = +x)
wEnStep::     ds 24                  ; A8 en_step: walk ms accumulator (low byte)
wEnAtk::      ds 24                  ; A8 atk_kind: 0 claw / bite / shot, 1 fireball
; A8 rocket slots (gr_*, RKT_MAX): enemy fireballs. Position / velocity 8.8 world units; the move
; per RKT_TICK_MS tick is velocity >> 5.
wPrOn::       ds 4
wPrFl::       ds 4                   ; RKT_F_FIREBALL | RKT_F_BARON | RKT_F_PEND
wPrOwn::      ds 4                   ; RKT_OWN_PL / RKT_OWN_EN
wPrXL::       ds 4
wPrX::        ds 4
wPrYL::       ds 4
wPrY::        ds 4
wPrZL::       ds 4
wPrZ::        ds 4
wPrVXL::      ds 4
wPrVXH::      ds 4
wPrVYL::      ds 4
wPrVYH::      ds 4
wPrVZL::      ds 4
wPrVZH::      ds 4
wPrLifeL::    ds 4                   ; ms left
wPrLifeH::    ds 4
wPrAcc::      ds 4                   ; ms toward the next tick
wAiI::        ds 1
wAiT::        ds 1
wAiK::        ds 1
wAiN::        ds 1
wAiTry::      ds 5
wAiO::        ds 4                   ; position before a step: x, xl, z, zl
wCellFy::     ds 1
wRawDt::      ds 1                   ; VBlanks the last frame took (unclamped)
wScriptJoy::  ds 1

; Input hold times. The timer interrupt (INPUT_HZ, 4 ticks per VBlank) adds a tick to the counter of
; every direction held at that moment; ReadJoy snapshots them into wHold* once per game frame.
; Order is fixed: forward, back, turn right, turn left, strafe right, strafe left.
wAccF::       ds 1
wAccB::       ds 1
wAccTR::      ds 1
wAccTL::      ds 1
wAccSR::      ds 1
wAccSL::      ds 1
wHoldF::      ds 1
wHoldB::      ds 1
wHoldTR::     ds 1
wHoldTL::     ds 1
wHoldSR::     ds 1
wHoldSL::     ds 1
wPadLive::    ds 1                   ; pad as of the last timer tick (hJoy layout)
wPadLatch::   ds 1                   ; A / Select / Start seen since the last frame (taps shorter than a frame)
wTurnFrac::   ds 1                   ; fractional yaw (1/256 unit) carried between frames

SECTION "fbvars", WRAMX, BANK[1]
wFbProbe::    ds 1                  ; FloorBelow: highest surface y to consider
wAiOldY::     ds 1                  ; enemy feet y before the step (EnemyMoveOk)
wAiFloorY::   ds 1                  ; floor y at the step destination
