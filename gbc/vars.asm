; HRAM variables (127 bytes at $FF80-$FFFE) and WRAM reservations.

SECTION "hram", HRAM

hFrame::     ds 1
hVBlank::    ds 1
hJoy::       ds 1
hSpeed::     ds 1
hSavedSP::   ds 2
hShow::      ds 1                   ; VRAM bank currently displayed

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

; The framebuffer owns all of WRAM0 ($C000-$CFFF).
SECTION "framebuffer", WRAM0[$C000]
wFB::        ds $1000

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
