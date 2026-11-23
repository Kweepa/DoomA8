; HRAM variables (127 bytes at $FF80-$FFFE) and WRAM reservations.

SECTION "hram", HRAM

hFrame::     ds 1
hVBlank::    ds 1
hJoy::       ds 1
hSpeed::     ds 1
hSavedSP::   ds 2

; DrawLine scratch
hPhase::     ds 1
hPtrH::      ds 1
hPtrL::      ds 1
hKind::      ds 1

; Benchmark timer
hOver::      ds 1                   ; TIMA overflow count (timer ISR)
hLoop::      ds 1

; The framebuffer owns all of WRAM0 ($C000-$CFFF).
SECTION "framebuffer", WRAM0[$C000]
wFB::        ds $1000

SECTION "benchram", WRAMX
wBenchMagic:: ds 4
wBenchOut::   ds 32
