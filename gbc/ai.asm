; Enemy AI, in ROM bank 31 (called through AiTick from CombatUpdate): wake / alert / chase with
; octant dodging, line of sight, possessed hitscan, claws and bites, imp / baron fireballs.
; Behaviour follows the A8 build (src/enemy.asm, ai_*.asm); the rules are summarised in gbc/README.md.

INCLUDE "hw.inc"
INCLUDE "en.inc"

DEF PLAYER_H   EQU 4
DEF FALL_LEDGE EQU 1
DEF SIGHT      EQU 32               ; wake distance (cells, Chebyshev)
DEF STEP_VB    EQU 18               ; one cell of walking (300 ms)
DEF ALERT_VB   EQU 30               ; stand and turn after sighting the player

SECTION "ai", ROMX, BANK[31]

; Carry = the enemy (wObjI) may stand at cell (wColX, wColZ): inside its room's colliders and
; not blocked by crates / platforms / locked doors. The collision tests use the player's feet,
; so the eye height is swapped to the enemy's for the call (as the A8 engine does).
EnemyCellOk:
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnY
    add hl, de
    ld a, [hl]
; A = floor y of whoever stands there.
CellOkY:
    ld b, a
    ld a, [wCamY + 1]
    ld [wLedgeSaveY], a
    ld a, b
    add EYE_HEIGHT
    ld [wCamY + 1], a
    call InRoomInset
    jr nc, .no
    call SolidAt
    jr c, .no
    ld a, [wLedgeSaveY]
    ld [wCamY + 1], a
    scf
    ret
.no:
    ld a, [wLedgeSaveY]
    ld [wCamY + 1], a
    and a
    ret

; Move enemy wObjI toward heading wAng by speed * dt; slide on X then Z.
EnemyStep:
    ld a, [wParam]
    ld l, a
    ld a, [wParam + 1]
    ld h, a
    ld a, [hl]                      ; speed
    ld b, a
    ld a, [wMoveDt]
    ld c, a
    ld hl, 0
    ld d, 0
    ld e, b
.mul:
    add hl, de
    dec c
    jr nz, .mul
    ld a, l
    ld [wTa], a
    ld a, h
    ld [wTa + 1], a                 ; step length (8.8)
    ld a, [wAng]
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wSin], a
    ld a, [wAng]
    add 64
    ld l, a
    ld a, [hl]
    ld [wCos], a
    ld a, [wTa]
    ld e, a
    ld a, [wTa + 1]
    ld d, a
    ld a, [wSin]
    ld c, a
    call SMul16
    ld a, e
    ld [wMvX], a
    ld a, d
    ld [wMvX + 1], a
    ld a, [wTa]
    ld e, a
    ld a, [wTa + 1]
    ld d, a
    ld a, [wCos]
    ld c, a
    call SMul16
    ld a, e
    ld [wMvZ], a
    ld a, d
    ld [wMvZ + 1], a
    ; candidate positions
    ld a, [wExL]
    ld b, a
    ld a, [wMvX]
    add b
    ld [wNxL], a
    ld a, [wEx]
    ld b, a
    ld a, [wMvX + 1]
    adc b
    ld [wNx], a
    ld a, [wEzL]
    ld b, a
    ld a, [wMvZ]
    add b
    ld [wNzL], a
    ld a, [wEz]
    ld b, a
    ld a, [wMvZ + 1]
    adc b
    ld [wNz], a
    ; full move
    ld a, [wNx]
    ld [wColX], a
    ld a, [wNz]
    ld [wColZ], a
    call EnemyCellOk
    jr nc, .tryX
    ld a, [wNx]
    ld [wEx], a
    ld a, [wNxL]
    ld [wExL], a
    ld a, [wNz]
    ld [wEz], a
    ld a, [wNzL]
    ld [wEzL], a
    jp StoreEnPos
.tryX:
    ld a, [wNx]
    ld [wColX], a
    ld a, [wEz]
    ld [wColZ], a
    call EnemyCellOk
    jr nc, .tryZ
    ld a, [wNx]
    ld [wEx], a
    ld a, [wNxL]
    ld [wExL], a
    jp StoreEnPos
.tryZ:
    ld a, [wEx]
    ld [wColX], a
    ld a, [wNz]
    ld [wColZ], a
    call EnemyCellOk
    ret nc
    ld a, [wNz]
    ld [wEz], a
    ld a, [wNzL]
    ld [wEzL], a
    jp StoreEnPos


; ---- small helpers ---------------------------------------------------------------------------

; HL = &array[wObjI] (clobbers A, D, E).
MACRO ENPTR
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, \1
    add hl, de
ENDM

; HL = &array[wAiI] (fireball slot; clobbers A, D, E).
MACRO PRPTR
    ld a, [wAiI]
    ld e, a
    ld d, 0
    ld hl, \1
    add hl, de
ENDM

; wDist = max(|wDx|, |wDz|) (8.8): the Chebyshev distance the A8 AI uses.
CalcDist:
    call AbsPair
    ld a, b
    cp d
    jr c, .de
    jr nz, .bc
    ld a, c
    cp e
    jr c, .de
.bc:
    ld a, c
    ld [wDist], a
    ld a, b
    ld [wDist + 1], a
    ret
.de:
    ld a, e
    ld [wDist], a
    ld a, d
    ld [wDist + 1], a
    ret

; A = new state for wObjI; resets the state timer and the fired flag.
EnSetState:
    ld c, a
    ld a, [wObjI]
    ld e, a
    ld d, 0
    ld hl, wEnState
    add hl, de
    ld [hl], c
    ld hl, wEnTimer
    add hl, de
    ld [hl], 0
    ld hl, wEnFrame
    add hl, de
    ld [hl], 0
    ret

; Back to chasing; the next frame picks a fresh walk direction.
EnterChase:
    ld a, EN_CHASE
    call EnSetState
    ENPTR wEnStep
    ld [hl], STEP_VB
    ret

; A = heading (0 = +z, 64 = +x) the enemy should face: mesh yaw = -heading.
SetYawFromHeading:
    ld b, a
    xor a
    sub b
    ld b, a
    ENPTR wEnYaw
    ld [hl], b
    ret

; Carry = the player's floor is within a step of the enemy's.
SameFloor:
    ENPTR wEnY
    ld a, [wFloorY]
    sub [hl]
    jr nc, .p
    cpl
    inc a
.p:
    cp FALL_LEDGE + 1
    ret

; Carry = a fireball is already in flight (one at a time, as on the A8).
FireballAlive:
    ld hl, wPrOn
    ld b, PR_N
.l:
    ld a, [hl+]
    and a
    jr nz, .yes
    dec b
    jr nz, .l
    and a
    ret
.yes:
    scf
    ret

; BC = sign-extended A / 2.
HalfSext:
    ld c, a
    add a
    sbc a
    ld b, a
    sra b
    rr c
    ret

; Carry = nothing solid between the enemy and the player: half-cell samples along the heading
; wAng, each tested as a standable cell for the enemy.
LosClear:
    ld a, [wAng]
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    ld [wLsx], a
    ld a, [wAng]
    add 64
    ld l, a
    ld a, [hl]
    ld [wLsz], a
    ld a, [wDist + 1]
    add a
    inc a
    cp 62
    jr c, .n
    ld a, 62
.n:
    ld [wAiN], a
    ld a, [wExL]
    ld [wLpXL], a
    ld a, [wEx]
    ld [wLpX], a
    ld a, [wEzL]
    ld [wLpZL], a
    ld a, [wEz]
    ld [wLpZ], a
.step:
    ld a, [wLsx]
    ld c, a
    add a
    sbc a
    ld b, a
    ld a, [wLpXL]
    add c
    ld [wLpXL], a
    ld a, [wLpX]
    adc b
    ld [wLpX], a
    ld a, [wLsz]
    ld c, a
    add a
    sbc a
    ld b, a
    ld a, [wLpZL]
    add c
    ld [wLpZL], a
    ld a, [wLpZ]
    adc b
    ld [wLpZ], a
    ld a, [wLpX]
    ld [wColX], a
    ld b, a
    ld a, [wLpZ]
    ld [wColZ], a
    ld c, a
    ld a, [wCamX + 1]
    cp b
    jr nz, .test
    ld a, [wCamZ + 1]
    cp c
    jr z, .clear                    ; reached the player's cell
.test:
    call EnemyCellOk
    ret nc
    ld hl, wAiN
    dec [hl]
    jr nz, .step
.clear:
    scf
    ret

; ---- decisions -------------------------------------------------------------------------------

; Chasing with the cooldown over: pick an attack. Carry = one started.
;   possessed: hitscan within range, line of sight
;   pinky: bite within 3 cells
;   imp / baron: claw within 3 cells, else a fireball (more likely the farther away), one in flight
TryAttack:
    ld a, [wHP]
    and a
    jr z, .no
    ld a, [wParam]
    ld l, a
    ld a, [wParam + 1]
    ld h, a
    inc hl
    inc hl
    ld b, [hl]                      ; range (cells)
    ld a, [wDist + 1]
    cp b
    jr z, .inRange
    jr nc, .no
.inRange:
    ENPTR wEnType
    ld a, [hl]
    ld [wAiT], a
    xor a
    ld [wAiK], a
    ld a, [wAiT]
    and a
    jr z, .los                      ; possessed
    cp 2
    jr nz, .ranged
    call SameFloor                  ; pinky
    jr nc, .no
    jr .los
.ranged:
    call FireballAlive
    jr c, .no
    ld a, [wDist + 1]
    cp 4
    jr nc, .missile
    call SameFloor
    jr c, .los                      ; claw
.missile:
    ld a, [wDist + 1]
    cp 13
    jr c, .m1
    ld a, 12
.m1:
    swap a
    sub 64
    jr c, .mok                      ; close: threshold underflows, always throws
    ld b, a
    call Rnd
    cp b
    jr c, .no                       ; rnd < (dist * 16 - 64): hold fire
.mok:
    ld a, 1
    ld [wAiK], a
.los:
    call LosClear
    jr c, .go
    ENPTR wEnCool
    ld [hl], 10                     ; blocked: look again shortly
.no:
    and a
    ret
.go:
    ld a, [wAiK]
    ld b, a
    ENPTR wEnAtk
    ld [hl], b
    ld a, [wAng]
    call SetYawFromHeading
    ld a, EN_ATTACK
    call EnSetState
    scf
    ret

; Direction table (octant 0 = +z, 2 = +x, 4 = -z, 6 = -x): cell offsets.
DirDX:
    db 0, 1, 1, 1, 0, -1, -1, -1
DirDZ:
    db 1, 1, 0, -1, -1, -1, 0, 1

; Pick a walk octant: toward the player (nearest of eight), grunts and imps close in turn
; away, with a side step now and then; never straight back; first candidate whose next cell
; is standable. wAng = heading to the player.
SelectDir:
    ld a, [wAng]
    add 16
    rlca
    rlca
    rlca
    and 7
    ld b, a
    ENPTR wEnType
    ld a, [hl]
    and a
    jr z, .grunt
    cp 3
    jr nz, .noBack
.grunt:
    ld a, [wDist + 1]
    cp 9
    jr nc, .noBack
    ld a, b
    add 4
    and 7
    ld b, a                         ; back off
.noBack:
    call Rnd
    ld c, a
    ld d, 1
    bit 7, c
    jr z, .s
    ld d, 7
.s:
    ld a, b
    ld [wAiTry], a
    add d
    and 7
    ld [wAiTry + 1], a
    ld a, b
    sub d
    and 7
    ld [wAiTry + 2], a
    ld a, [wAiTry + 1]
    add d
    and 7
    ld [wAiTry + 3], a
    ld a, [wAiTry + 2]
    sub d
    and 7
    ld [wAiTry + 4], a
    ld a, c
    and 3
    jr nz, .noSwap                  ; one time in four: side step first
    ld a, [wAiTry]
    ld b, a
    ld a, [wAiTry + 1]
    ld [wAiTry], a
    ld a, b
    ld [wAiTry + 1], a
.noSwap:
    ENPTR wEnDir
    ld a, [hl]
    cp 8
    jr nc, .noOpp
    add 4
    and 7
.noOpp:
    ld [wAiK], a                    ; the direction we may not take (straight back)
    xor a
    ld [wAiN], a
.try:
    ld a, [wAiN]
    ld e, a
    ld d, 0
    ld hl, wAiTry
    add hl, de
    ld a, [hl]
    ld b, a
    ld a, [wAiK]
    cp b
    jr z, .next
    ld e, b
    ld d, 0
    ld hl, DirDX
    add hl, de
    ld a, [wEx]
    add [hl]
    ld [wColX], a
    ld hl, DirDZ
    add hl, de
    ld a, [wEz]
    add [hl]
    ld [wColZ], a
    push bc
    call EnemyCellOk
    pop bc
    jr nc, .next
    ENPTR wEnDir
    ld [hl], b
    ret
.next:
    ld hl, wAiN
    inc [hl]
    ld a, [hl]
    cp 5
    jr nz, .try
    ENPTR wEnDir
    ld [hl], $FF                    ; boxed in: stand until the next step
    ret

; ---- the attack itself -----------------------------------------------------------------------

; At the fire frame of the attack clip.
Fire:
    ld a, [wHP]
    and a
    ret z
    ENPTR wEnAtk
    ld a, [hl]
    and a
    jp nz, SpawnFireball
    ENPTR wEnType
    ld a, [hl]
    and a
    jr nz, .melee
    call LosClear                   ; possessed: hit when (rnd & 31) > min(dist, 28)
    ret nc
    ld a, [wDist + 1]
    cp 29
    jr c, .d
    ld a, 28
.d:
    ld b, a
    call Rnd
    and 31
    cp b
    ret z
    ret c
    call Rnd
    and 3
    add 2
    ld b, a
    add a
    add b                           ; 6, 9, 12 or 15
    jp PlayerDamage
.melee:
    call SameFloor
    ret nc
    ld a, [wDist + 1]
    cp 4
    ret nc
    call LosClear
    ret nc
    call Rnd
    and 7
    inc a
    ld b, a
    add a
    add b                           ; 3 .. 24
    jp PlayerDamage

; ---- fireballs -------------------------------------------------------------------------------

; A flat shot from the enemy toward the player: a quarter cell per VBlank.
SpawnFireball:
    call FireballAlive
    ret c
    ld hl, wPrOn
    ld b, 0
.f:
    ld a, [hl]
    and a
    jr z, .got
    inc hl
    inc b
    ld a, b
    cp PR_N
    jr nz, .f
    ret
.got:
    ld a, b
    ld [wAiI], a
    PRPTR wPrOn
    ld [hl], 1
    ENPTR wEnType
    ld a, [hl]
    cp 1
    ld a, 0
    jr nz, .nb
    ld a, 1
.nb:
    ld b, a
    PRPTR wPrFl
    ld [hl], b
    ld a, [wRoom]
    ld b, a
    PRPTR wPrRoom
    ld [hl], b
    ld a, [wExL]
    ld b, a
    PRPTR wPrXL
    ld [hl], b
    ld a, [wEx]
    ld b, a
    PRPTR wPrX
    ld [hl], b
    ld a, [wEzL]
    ld b, a
    PRPTR wPrZL
    ld [hl], b
    ld a, [wEz]
    ld b, a
    PRPTR wPrZ
    ld [hl], b
    ENPTR wEnY
    ld a, [hl]
    ld b, a
    PRPTR wPrFlY
    ld [hl], b
    ld a, b
    add 2
    ld b, a
    PRPTR wPrY
    ld [hl], b
    ld b, 250
    PRPTR wPrLife
    ld [hl], b
    ld a, [wAng]
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    call HalfSext
    PRPTR wPrVXL
    ld [hl], c
    PRPTR wPrVXH
    ld [hl], b
    ld a, [wAng]
    add 64
    ld l, a
    ld h, HIGH(SinTab)
    ld a, [hl]
    call HalfSext
    PRPTR wPrVZL
    ld [hl], c
    PRPTR wPrVZH
    ld [hl], b
    ret

; Fly every fireball of this room for wMoveDt VBlanks: a wall clears it, the player takes
; 10 + rnd(16) (baron 30 + rnd(16)) within one cell.
ProjUpdate::
    xor a
    ld [wAiI], a
.pl:
    PRPTR wPrOn
    ld a, [hl]
    and a
    jp z, .pnext
    PRPTR wPrRoom
    ld a, [wRoom]
    cp [hl]
    jp nz, .kill
    PRPTR wPrLife
    ld a, [wMoveDt]
    ld b, a
    ld a, [hl]
    sub b
    jp c, .kill
    ld [hl], a
    ld a, [wMoveDt]
    ld [wAiK], a
.sub:
    PRPTR wPrVXL
    ld c, [hl]
    PRPTR wPrVXH
    ld b, [hl]
    PRPTR wPrXL
    ld a, [hl]
    add c
    ld [hl], a
    PRPTR wPrX
    ld a, [hl]
    adc b
    ld [hl], a
    PRPTR wPrVZL
    ld c, [hl]
    PRPTR wPrVZH
    ld b, [hl]
    PRPTR wPrZL
    ld a, [hl]
    add c
    ld [hl], a
    PRPTR wPrZ
    ld a, [hl]
    adc b
    ld [hl], a
    PRPTR wPrX
    ld a, [hl]
    ld [wColX], a
    PRPTR wPrZ
    ld a, [hl]
    ld [wColZ], a
    PRPTR wPrFlY
    ld a, [hl]
    call CellOkY
    jp nc, .kill
    PRPTR wPrX
    ld a, [wCamX + 1]
    sub [hl]
    jr nc, .ax
    cpl
    inc a
.ax:
    cp 2
    jr nc, .nohit
    PRPTR wPrZ
    ld a, [wCamZ + 1]
    sub [hl]
    jr nc, .az
    cpl
    inc a
.az:
    cp 2
    jr nc, .nohit
    PRPTR wPrFlY
    ld a, [wFloorY]
    sub [hl]
    jr nc, .ay
    cpl
    inc a
.ay:
    cp 2
    jr nc, .nohit
    PRPTR wPrFl
    ld a, [hl]
    and 1
    ld b, 10
    jr z, .dm
    ld b, 30
.dm:
    call Rnd
    and 15
    add b
    call PlayerDamage
    jr .kill
.nohit:
    ld hl, wAiK
    dec [hl]
    jp nz, .sub
    jr .pnext
.kill:
    PRPTR wPrOn
    ld [hl], 0
.pnext:
    ld hl, wAiI
    inc [hl]
    ld a, [hl]
    cp PR_N
    jp nz, .pl
    ret

; ---- per-enemy state machine -----------------------------------------------------------------

AiTick::
    call EnemiesUpdate
    jp ProjUpdate

; Idle: wake on seeing the player (within SIGHT cells and in the facing half-plane, or adjacent),
; alert (stand, turn to face) for ALERT_VB, chase (walk 18 VBlanks per cell in a picked octant,
; attack when the cooldown is over), attack (fires at timer 12, ends at 28), pain, dying.
EnemiesUpdate::
    ld a, [wEnN]
    and a
    ret z
    xor a
    ld [wObjI], a
.loop:
    ENPTR wEnRoom
    ld a, [wRoom]
    cp [hl]
    jp nz, .next
    ENPTR wEnState
    ld a, [hl]
    cp EN_DEAD
    jp z, .next
    ld [wTmpKind], a
    ENPTR wEnTimer
    ld a, [wMoveDt]
    add [hl]
    jr c, .tcap
    cp 250
    jr c, .tstore
.tcap:
    ld a, 250
.tstore:
    ld [hl], a
    ENPTR wEnCool
    ld a, [wMoveDt]
    ld b, a
    ld a, [hl]
    sub b
    jr nc, .cstore
    xor a
.cstore:
    ld [hl], a
    ENPTR wEnType
    ld a, [hl]
    swap a
    ld e, a
    ld d, 0
    ld hl, EnemyParams
    add hl, de
    ld a, l
    ld [wParam], a
    ld a, h
    ld [wParam + 1], a
    call LoadEnPos
    call DeltaToPlayer
    call CalcDist
    ld a, [wTmpKind]
    and a
    jp z, .idle
    cp EN_CHASE
    jp z, .chase
    cp EN_ATTACK
    jp z, .attack
    cp EN_PAIN
    jp z, .pain
    cp EN_ALERT
    jp z, .alert
    jp .dying

.idle:
    ld a, [wDist + 1]
    cp SIGHT
    jp nc, .next
    cp 2
    jr c, .see
    call AngleTo
    ld b, a
    ENPTR wEnYaw
    ld a, [hl]
    add b                           ; heading to the player - facing (facing = -yaw)
    add 64
    cp 129
    jp nc, .next                    ; behind the enemy
.see:
    ld a, EN_ALERT
    call EnSetState
    jp .next

.alert:
    call AngleTo
    call SetYawFromHeading
    ENPTR wEnTimer
    ld a, [hl]
    cp ALERT_VB
    jp c, .next
    call EnterChase
    ENPTR wEnType
    ld a, [hl]
    cp 3
    ld a, 0
    jr z, .d0                       ; imps start throwing at once
    call Rnd
    and 63
.d0:
    ld b, a
    ENPTR wEnCool
    ld [hl], b
    jp .next

.chase:
    call AngleTo
    ld [wAng], a
    ENPTR wEnCool
    ld a, [hl]
    and a
    jr nz, .walk
    call TryAttack
    jp c, .next
.walk:
    ENPTR wEnStep
    ld a, [wMoveDt]
    add [hl]
    ld [hl], a
    cp STEP_VB
    jr c, .have
    ld [hl], 0
    call SelectDir
.have:
    ENPTR wEnDir
    ld a, [hl]
    cp 8
    jp nc, .next                    ; boxed in
    swap a
    add a                           ; heading = octant * 32
    ld [wAng], a
    call SetYawFromHeading
    ld a, [wDist + 1]
    and a
    jp z, .next                     ; on top of the player
    ld a, [wEx]
    ld [wAiO], a
    ld a, [wExL]
    ld [wAiO + 1], a
    ld a, [wEz]
    ld [wAiO + 2], a
    ld a, [wEzL]
    ld [wAiO + 3], a
    call EnemyStep
    ld hl, wAiO
    ld a, [wEx]
    cp [hl]
    jp nz, .next
    inc hl
    ld a, [wExL]
    cp [hl]
    jp nz, .next
    inc hl
    ld a, [wEz]
    cp [hl]
    jp nz, .next
    inc hl
    ld a, [wEzL]
    cp [hl]
    jp nz, .next
    ENPTR wEnStep
    ld [hl], STEP_VB                ; blocked: pick another direction next frame
    jp .next

.attack:
    call AngleTo
    ld [wAng], a
    ENPTR wEnTimer
    ld a, [hl]
    cp 12
    jr c, .atkWait
    ENPTR wEnFrame
    ld a, [hl]
    and a
    jr nz, .atkWait                 ; already fired
    ld [hl], 1
    call Fire
.atkWait:
    ENPTR wEnTimer
    ld a, [hl]
    cp 28
    jp c, .next
    ENPTR wEnAtk
    ld a, [hl]
    and a
    jr nz, .cdMissile
    call Rnd
    and 15
    add 15                          ; shots / bites: ~0.3 s
    jr .cdSet
.cdMissile:
    call Rnd
    and 31
    add 150                         ; fireballs: ~2.5 s
.cdSet:
    ld b, a
    ENPTR wEnCool
    ld [hl], b
    call EnterChase
    jp .next

.pain:
    ENPTR wEnTimer
    ld a, [hl]
    cp 12
    jp c, .next
    call EnterChase
    jp .next

.dying:
    ENPTR wEnTimer
    ld a, [hl]
    cp 28
    jp c, .next
    ld a, EN_DEAD
    call EnSetState
    jp .next

.next:
    ld a, [wObjI]
    inc a
    ld [wObjI], a
    ld b, a
    ld a, [wEnN]
    cp b
    jp nz, .loop
    ret
