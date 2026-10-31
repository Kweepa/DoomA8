; First-person view-model: 2×2 body (sprites 0–3) + 24×21 flash (4 / 5).
; Native size (no XY expand). Body light grey; flash yellow then red.
; Weapon ids WPN_* live in mem.asm
!zone weapon

POSE_IDLE = 0
POSE_FIRE = 1
POSE_RECOIL = 2
POSE_ANIM = 3
POSE_COCK = 4

PUNCH_MS = 360				; SquareDoom 18 ticks
PUNCH_FIRE_MS = 800			; SquareDoom 40 ticks
; SquareDoom draws these at 2x; ours are native size and two tiles
; left of that image's right edge.
FIST_HAND_X = 200			; 56 wide, two tiles left of 216
FIST_PUNCH_X = 128			; 64 wide, two tiles left of 144
FIST_PUNCH_Y = 218			; 32 rows end on the viewport bottom
SAW_FIRE_MS = 100

RECOIL_NSTEPS = 3
PISTOL_RECOIL_N = 2			; −4 for 300 ms, then −6 for 160 ms
SG_COCK_DELAY = 320			; let DPSHOTGN finish (16 mid-split samples)
COCK_NSTEPS = 3
COCK_X = WPN_X0 - 16			; two character columns left of the gun

; have_wpn bit per weapon id. Fist is 0: switch_weapon allows it with no bit.
wpn_have_bit
	!byte 0, HAVE_SHOT, HAVE_CHAIN, HAVE_ROCKET, HAVE_PIST, HAVE_SAW

wpn_fire_ms_lo
	!byte <PUNCH_FIRE_MS, <600, <100, <1000, <PISTOL_FIRE_MS, <SAW_FIRE_MS
wpn_fire_ms_hi
	!byte >PUNCH_FIRE_MS, >600, >100, >1000, >PISTOL_FIRE_MS, >SAW_FIRE_MS

wpn_sound
	!byte 0, SOUND_SHOTGN, SOUND_PISTOL, SOUND_RLAUNC, SOUND_PISTOL, 0

wpn_idle_x
	!byte FIST_HAND_X, WPN_X0, WPN_X0, WPN_X0, WPN_X0, WPN_X_SAW
wpn_idle_y
	!byte WPN_Y_FISTIDLE, WPN_Y_SHOTIDLE, WPN_Y_CHAINIDLE, WPN_Y_ROCKIDLE, WPN_Y_PISTIDLE, WPN_Y_SAWIDLE

wpn_fr		!byte 0

; added to wpn_y (signed). Chaingun uses the pistol muzzle, centered.
wpn_flashdy
	!byte 0, -FLASH_DY_GUN, -FLASH_DY_GUN, -FLASH_DY_GUN, -FLASH_DY_GUN, 0

WS_EMUZ		= 0
WS_SPLAT	= 1

; LOD 0..2 per slot (emuz then splat)
ws_spr_lo
	!byte <spr_emuz_0, <spr_emuz_1, <spr_emuz_2
	!byte <spr_splat_0, <spr_splat_1, <spr_splat_2
ws_spr_hi
	!byte >spr_emuz_0, >spr_emuz_1, >spr_emuz_2
	!byte >spr_splat_0, >spr_splat_1, >spr_splat_2
ws_msb
	!byte EMUZ_MSB, SPLAT_MSB
ws_ms_l
	!byte <EMUZ_MS, <SPLAT_MS
ws_ms_h
	!byte >EMUZ_MS, >SPLAT_MS
ws_hdr_lo
	!byte <fxh_emuz, <fxh_splat
ws_hdr_hi
	!byte >fxh_emuz, >fxh_splat
ws_vx_lo
	!byte <emuz_vx, <splat_vx
ws_vx_hi
	!byte >emuz_vx, >splat_vx
ws_vy_lo
	!byte <emuz_vy, <splat_vy
ws_vy_hi
	!byte >emuz_vy, >splat_vy
ws_col_lo
	!byte <emuz_col, <splat_col
ws_col_hi
	!byte >emuz_col, >splat_col
ws_xmsb_lo
	!byte <emuz_xmsb, <splat_xmsb
ws_xmsb_hi
	!byte >emuz_xmsb, >splat_xmsb
ws_snd
	!byte SOUND_RLAUNC_E, 0
ws_colsrc
	!byte 0, 1			; 0 = set COL_FX, 1 = leave splat_col

fxh_lo
	!byte <fxh_flash4, <fxh_flash5, <fxh_emuz, <fxh_splat, <fxh_explode
fxh_hi
	!byte >fxh_flash4, >fxh_flash5, >fxh_emuz, >fxh_splat, >fxh_explode
fx_exp_lo
	!byte <flash4_expired, <flash5_expired, <emuz_expired, <splat_expired, <fx_zero_header
fx_exp_hi
	!byte >flash4_expired, >flash5_expired, >emuz_expired, >splat_expired, >fx_zero_header

; Shotgun: snap up for shot, kick down, settle. Rocket: snap down, recover.
recoil_shot_y
	!byte WPN_Y_SHOTIDLE - 10, WPN_Y_SHOTIDLE + 14, WPN_Y_SHOTIDLE + 6
recoil_rkt_y
	!byte WPN_Y_ROCKIDLE + 24, WPN_Y_ROCKIDLE + 16, WPN_Y_ROCKIDLE + 8
recoil_step_ms_lo
	!byte 16, 35, 35
recoil_step_ms_hi
	!byte 0, 0, 0

; SquareDoom pistol: kick up 4 for 300 ms with the flash, then 6 for 160 ms.
recoil_pist_y
	!byte WPN_Y_PISTIDLE - 4, WPN_Y_PISTIDLE - 6
recoil_pist_ms_lo
	!byte <300, <160
recoil_pist_ms_hi
	!byte >300, >160

; Cock: sit on the viewport bottom, dip 5, pop back. DPSGCOCK plays on the dip.
cock_y
	!byte WPN_Y_FLUSH, WPN_Y_FLUSH + 5, WPN_Y_FLUSH
cock_step_ms
	!byte 40, 40, 160

; ------------------------------------------------------------------
; VIC sprite slots / flash state. Does not touch HP, ammo, or weapons.
init_weapon_hw
	lda #0

	sta spr_en
	sta wpn_flash_en
	ldx #0
.iw_fxh
	lda fxh_lo,x
	sta fx_ptr
	lda fxh_hi,x
	sta fx_ptr+1
	lda #0
	ldy #FXH_ON
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	inx
	cpx #FXH_COUNT
	bcc .iw_fxh
	sta cock_ms_l
	sta cock_ms_h
	sta cock_pend
	sta wpn_bob_ph
	sta emuz_xmsb
	sta emuz_vx
	sta emuz_vy
	sta emuz_col
	sta splat_xmsb
	sta splat_vx
	sta splat_vy
	sta splat_col
	lda #$ff
	sta emuz_pending
	sta bite_splat_i
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
	sta mg_frame
	sta wpn_pose
	sta anim_step
	sta in_fire
	sta key_fire
	ldx #3
-
	sta in_wpn_1,x
	sta key_wpn_1,x
	dex
	bpl -
	sta in_wpn_pist
	sta key_wpn_pist
	sta wpn1_held


	rts

; First start: hardware + starting inventory.
init_weapon
	jsr init_weapon_hw
	jsr init_rockets
	jmp reset_loadout

; Pistol equipped. Fist is always owned, selected with key 1.
reset_loadout
	lda #HAVE_START
	sta have_wpn
	lda #AMMO_SHELLS_START
	sta ammo_shells
	lda #AMMO_BULLETS_START
	sta ammo_bullets
	lda #0
	sta ammo_rockets
	lda #PLAYER_HP_START
	sta player_hp
	lda #PLAYER_ARMOUR_START
	sta player_armour
	sta combat_armor
	lda #0
	sta have_keys
	sta have_pack
	sta pu_kind
	sta pu_ms_l
	sta pu_ms_h

	lda #COL_FLASH_Y
	sta flash4_col
	sta flash5_col
	lda #$ff
	sta cur_weapon
	ldx #WPN_PIST
	jmp switch_weapon

; X = weapon id — fist is always owned; others refuse if the bit is clear
switch_weapon
	cpx #WPN_FIST
	beq .sw_own
	lda wpn_have_bit,x
	and have_wpn
	beq .sw_rts
.sw_own
	cpx cur_weapon
	bne .sw_do
.sw_rts
	rts
.sw_do
	stx cur_weapon
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
	sta flash_phase
	sta flash_skip
	sta flash_ms_l
	sta flash_ms_h
	sta flash5_phase
	sta flash5_skip
	sta flash5_ms_l
	sta flash5_ms_h
	sta wpn_flash_en
	sta mg_frame
	sta wpn_pose
	sta anim_step
	sta cock_ms_l
	sta cock_ms_h
	sta cock_pend
	sta saw_flip
	sta saw_bite
	lda #1
	sta saw_amp
	jmp setup_weapon

setup_weapon
	lda #0
	sta wpn_fr
	sta cock_ms_l
	sta cock_ms_h
	sta cock_pend
	ldx cur_weapon
	lda wpn_flashdy,x
	sta wpn_flash_dy
	lda #COL_FLASH_Y
	sta flash4_col
	sta flash5_col
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	rts

; A = src lo, Y = src hi. Both keep the mode-E pointer (no unpack).
blit_world
	ldx ws_slot
	beq .bw_emuz
	sta splat_src
	sty splat_src+1
	rts
.bw_emuz
	sta emuz_src
	sty emuz_src+1
	rts

start_flash
	cmp #FLASH_EN_R
	beq .sf5
	lda #1
	sta flash_phase
	sta flash_skip
	lda #<FLASH_YEL_MS
	sta flash_ms_l
	lda #>FLASH_YEL_MS
	sta flash_ms_h
	lda #COL_FLASH_Y
	sta flash4_col
	lda #0
	sta flash5_phase
	sta flash5_skip
	jmp .sf_xy
.sf5
	lda #1
	sta flash5_phase
	sta flash5_skip
	lda #<FLASH_YEL_MS
	sta flash5_ms_l
	lda #>FLASH_YEL_MS
	sta flash5_ms_h
	lda #COL_FLASH_Y
	sta flash5_col
.sf_xy
	rts

hide_flash
	lda #0
	sta flash_phase
	sta flash_skip
	sta flash_ms_l
	sta flash_ms_h
	sta flash5_phase
	sta flash5_skip
	sta flash5_ms_l
	sta flash5_ms_h
	rts

; ------------------------------------------------------------------
update_weapon
	lda key_wpn_1
	beq .uw_sw
	jsr select_slot1
.uw_sw
	ldy #1
.uw_key
	lda key_wpn_1,y
	beq .uw_swn
	tya
	tax
	jsr switch_weapon
.uw_swn
	iny
	cpy #4
	bcc .uw_key
	lda key_wpn_pist
	beq .uw_fx
	ldx #WPN_PIST
	jsr switch_weapon
.uw_fx
	jsr tick_all_fx
	jsr tick_anim
	jsr tick_cock_wait

	lda fire_rpt_l
	ora fire_rpt_h
	beq .uw_chk
	sec
	lda fire_rpt_l
	sbc dt_ms
	sta fire_rpt_l
	lda fire_rpt_h
	sbc dt_msh
	sta fire_rpt_h
	bcs .uw_chk
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
.uw_chk
	lda key_fire
	beq .uw_up
	lda fire_rpt_l
	ora fire_rpt_h
	bne .uw_done
	ldx cur_weapon
	cpx #WPN_CHAIN
	beq .uw_shot
	lda cock_pend
	bne .uw_done
	lda wpn_pose
	bne .uw_done
.uw_shot
	ldx cur_weapon
	cpx #WPN_FIST
	beq .uw_do_fire
	cpx #WPN_SAW
	beq .uw_do_fire
	jsr try_spend_ammo
	bcc .uw_done
	jsr hud_ammo
.uw_do_fire
	jsr fire_shot
	ldx cur_weapon
	lda wpn_fire_ms_lo,x
	sta fire_rpt_l
	lda wpn_fire_ms_hi,x
	sta fire_rpt_h
.uw_done
	jmp tick_saw_vibe
.uw_up
	lda cur_weapon
	cmp #WPN_CHAIN
	bne .uw_up_saw
	lda wpn_pose
	cmp #POSE_FIRE
	bne .uw_up_saw
	jsr chain_idle
.uw_up_saw
	lda cur_weapon
	cmp #WPN_SAW
	bne .uw_up_rts
	lda #0
	sta saw_bite
	lda #1
	sta saw_amp
.uw_up_rts
	jmp tick_saw_vibe

; Key 1. No chainsaw: fist (already there is a no-op). Owned: toggle, or
; the chainsaw when another gun is out.
select_slot1
	lda have_wpn
	and #HAVE_SAW
	beq .s1_fist
	lda cur_weapon
	cmp #WPN_FIST
	beq .s1_saw
	cmp #WPN_SAW
	beq .s1_fist
	ldx #WPN_SAW
	jmp switch_weapon
.s1_saw
	ldx #WPN_SAW
	jmp switch_weapon
.s1_fist
	ldx #WPN_FIST
	jmp switch_weapon

; Bit 0 is the drop. Fire toggles it every frame. Idle toggles bit 1 every
; frame and bit 0 every other, so the idle shake is half rate. A bite
; rerolls the drop to 2..5 on each down flip. A miss stays at 2.
tick_saw_vibe
	lda cur_weapon
	cmp #WPN_SAW
	bne .tsv_bob
	lda key_fire
	beq .tsv_idle
	lda saw_flip
	and #1
	eor #1
	sta saw_flip
	beq .tsv_bob
	lda saw_bite
	beq .tsv_fire
	jsr rnd8
	and #3
	clc
	adc #2
	sta saw_amp
	jmp tick_wpn_bob
.tsv_fire
	lda #2
	sta saw_amp
	bne .tsv_bob
.tsv_idle
	lda saw_flip
	eor #2
	sta saw_flip
	and #2
	bne .tsv_bob
	lda saw_flip
	eor #1
	sta saw_flip
.tsv_bob
	jmp tick_wpn_bob

; Idle + a move hold: phase += dt>>2, wrapped to the positive half-sine.
; 128 steps × 4 ms = 512 ms per dip. Fire, cock wait, falling, or no hold
; zeros the phase so the stamp adds nothing.
tick_wpn_bob
	lda wpn_pose
	bne .tbb_stop
	lda cock_pend
	ora cock_ms_l
	ora cock_ms_h
	bne .tbb_stop
	lda pl_falling
	bne .tbb_stop
	ldy #7
	lda #0
.tbb_hold
	ora hold_fwd,y
	dey
	bpl .tbb_hold
	tax				; dey cleared Z; test the OR
	beq .tbb_stop
	lda dt_ms
	sta wpn_tmp0
	lda dt_msh
	lsr
	ror wpn_tmp0
	lsr
	ror wpn_tmp0
	lda wpn_bob_ph
	clc
	adc wpn_tmp0
	and #$7f
	sta wpn_bob_ph
	rts
.tbb_stop
	lda #0
	sta wpn_bob_ph
	rts

; Ammo already spent (or fist / chainsaw). X = cur_weapon on entry.
fire_shot
	ldx cur_weapon
	cpx #WPN_FIST
	bne .fs_saw
	jmp start_punch
.fs_saw
	cpx #WPN_SAW
	bne .fs_gun
	jmp start_saw
.fs_gun
	lda #1
	sta gunshot_wake
	lda wpn_sound,x
	jsr play_sound
	ldx cur_weapon
	cpx #WPN_SHOT
	bne .fs_notshot
	jsr shotgun_hitscan
	lda #<SG_COCK_DELAY
	sta cock_ms_l
	lda #>SG_COCK_DELAY
	sta cock_ms_h
	ldx cur_weapon
.fs_notshot
	cpx #WPN_CHAIN
	beq .fs_chain
	cpx #WPN_PIST
	bne .fs_rkt
	jsr pistol_hitscan
	jmp .fs_flash
.fs_rkt
	cpx #WPN_ROCKET
	bne .fs_flash
	jsr spawn_player_rocket
.fs_flash
	lda #FLASH_EN_L
	jsr start_flash
	jmp start_recoil

.fs_chain
	jsr chaingun_hitscan
	lda #POSE_FIRE
	sta wpn_pose
	lda mg_frame
	eor #1
	sta mg_frame
	sta wpn_fr
	lda #FLASH_EN_L
	jmp start_flash

; X = cur_weapon; C=1 spent (or free), C=0 cannot fire
try_spend_ammo
!if  INF_AMMO = 1 {
	sec
	rts
}
	cpx #WPN_SHOT
	beq .ts_shell
	cpx #WPN_CHAIN
	beq .ts_bull
	cpx #WPN_ROCKET
	beq .ts_rkt
	cpx #WPN_PIST
	beq .ts_bull
	sec
	rts
.ts_bull
	lda ammo_bullets
	beq .ts_no
	dec ammo_bullets
	sec
	rts
.ts_shell
	lda ammo_shells
	beq .ts_no
	dec ammo_shells
	sec
	rts
.ts_rkt
	lda ammo_rockets
	beq .ts_no
	dec ammo_rockets
	sec
	rts
.ts_no
	clc
	rts

chain_idle
	lda #POSE_IDLE
	sta wpn_pose
	lda #0
	sta mg_frame
	ldx #WPN_CHAIN
	lda #0
	sta wpn_fr
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	rts

; Pose swap: the fist replaces the hand for PUNCH_MS. One melee test.
start_punch
	lda #POSE_ANIM
	sta wpn_pose
	lda #0
	sta anim_step
	lda #FIST_PUNCH_X
	sta wpn_x
	lda #FIST_PUNCH_Y
	sta wpn_y
	lda #<PUNCH_MS
	sta anim_ms_l
	lda #>PUNCH_MS
	sta anim_ms_h
	jsr punch_try_kill
	bcc .sp_rts
	lda #SOUND_PUNCH
	jsr play_sound
.sp_rts
	rts

; Free, repeating. A hit marks the bite; each later down-flip picks 2..5.
; A miss clears it and stays at 2.
start_saw
	jsr punch_try_kill
	bcc .ss_miss
	lda #1
	sta saw_bite
	lda #SOUND_PUNCH
	jmp play_sound
.ss_miss
	lda #0
	sta saw_bite
	lda #2
	sta saw_amp
	rts

wpn_to_idle
	ldx cur_weapon
	lda #POSE_IDLE
	sta wpn_pose
	lda #0
	sta anim_step
	sta wpn_fr
	cpx #WPN_FIST
	bne .ti_pos
	jsr hide_flash
	ldx cur_weapon
.ti_pos
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	rts

start_recoil
	lda #POSE_RECOIL
	sta wpn_pose
	lda #0
	sta anim_step
	jmp recoil_apply_step

recoil_apply_step
	lda cur_weapon
	cmp #WPN_PIST
	beq .ras_pist
	ldx anim_step
	cpx #RECOIL_NSTEPS
	bcc .ras_ok
	jmp wpn_to_idle
.ras_ok
	lda cur_weapon
	cmp #WPN_SHOT
	bne .ras_rkt
	lda recoil_shot_y,x
	jmp .ras_y
.ras_rkt
	lda recoil_rkt_y,x
.ras_y
	sta wpn_y
	lda recoil_step_ms_lo,x
	sta anim_ms_l
	lda recoil_step_ms_hi,x
	sta anim_ms_h
	rts
.ras_pist
	ldx anim_step
	cpx #PISTOL_RECOIL_N
	bcc .ras_pok
	jmp wpn_to_idle
.ras_pok
	lda recoil_pist_y,x
	sta wpn_y
	lda recoil_pist_ms_lo,x
	sta anim_ms_l
	lda recoil_pist_ms_hi,x
	sta anim_ms_h
	rts

; fx_ptr → 4-byte header. C=1 expired this frame (does not clear +0).
tick_fx
	ldy #FXH_ON
	lda (fx_ptr),y
	beq .tf_idle
	ldy #FXH_SKIP
	lda (fx_ptr),y
	beq .tf_sub
	lda #0
	sta (fx_ptr),y
	clc
	rts
.tf_sub
	ldy #FXH_MS_L
	sec
	lda (fx_ptr),y
	sbc dt_ms
	sta (fx_ptr),y
	iny
	lda (fx_ptr),y
	sbc dt_msh
	sta (fx_ptr),y
	bcc .tf_exp
	dey
	ora (fx_ptr),y
	bne .tf_live
.tf_exp
	sec
	rts
.tf_live
	clc
	rts
.tf_idle
	clc
	rts

tick_all_fx
	ldx #0
.ta_lp
	lda fxh_lo,x
	sta fx_ptr
	lda fxh_hi,x
	sta fx_ptr+1
	jsr tick_fx
	bcc .ta_n
	lda fx_exp_lo,x
	sta rot0
	lda fx_exp_hi,x
	sta rot1
	jsr .ta_go
.ta_n
	inx
	cpx #FXH_COUNT
	bcc .ta_lp
	rts
.ta_go
	jmp (rot0)

fx_zero_header
	lda #0
	ldy #FXH_ON
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	rts

flash4_expired
	lda flash_phase
	cmp #1
	bne fx_zero_header
	lda #2
	sta flash_phase
	lda #COL_FLASH_R
	sta flash4_col
	lda #1
	sta flash_skip
	lda #<FLASH_RED_MS
	sta flash_ms_l
	lda #>FLASH_RED_MS
	sta flash_ms_h
	rts

flash5_expired
	lda flash5_phase
	cmp #1
	bne fx_zero_header
	lda #2
	sta flash5_phase
	lda #COL_FLASH_R
	sta flash5_col
	lda #1
	sta flash5_skip
	lda #<FLASH_RED_MS
	sta flash5_ms_l
	lda #>FLASH_RED_MS
	sta flash5_ms_h
	rts

emuz_expired
	jsr fx_zero_header
	lda #0
	sta emuz_xmsb
	rts

splat_expired
	jsr fx_zero_header
	lda #0
	sta splat_xmsb
	rts

; A = value, X = slot. Store via ws_*_lo/hi pointer tables. Clobbers fx_ptr, Y.
!macro ws_sta .lo, .hi {
	pha
	lda .lo,x
	sta fx_ptr
	lda .hi,x
	sta fx_ptr+1
	pla
	ldy #0
	sta (fx_ptr),y
}

; A = tip viewport sx, Y = tip viewport sy. Depth = rot1 (CAM_ZH of tip vert).
start_enemy_muzzle
	pha
	tya
	pha
	lda rot1
	ldx #WS_EMUZ
	jmp start_world_spr

; A = tip viewport sx, Y = tip viewport sy, X = depth (EMUZ_Z0/Z1 bands).
start_splat
	pha
	tya
	pha
	txa
	ldx #WS_SPLAT
start_world_spr
	pha				; z
	stx ws_slot			; X is slot; lod calc reuses X
	txa
	tay				; Y = slot
	pla				; A = z
	cpy #0
	bne .sws_zok
	cmp #0
	bmi .sws_far
.sws_zok
	ldx #0
	cmp #EMUZ_Z0
	bcc .sws_lod
	inx
	cmp #EMUZ_Z1
	bcc .sws_lod
.sws_far
	ldx #2
.sws_lod
	lda ws_slot
	asl
	clc
	adc ws_slot			; slot*3
	sta wpn_tmp0
	txa
	clc
	adc wpn_tmp0			; + lod
	tax
	lda ws_spr_lo,x
	ldy ws_spr_hi,x
	jsr blit_world
	ldx ws_slot
	pla				; sy
	clc
	adc #VIEW_SPR_Y0 - EMUZ_OY
	+ws_sta ws_vy_lo, ws_vy_hi
	pla				; sx
	clc
	adc #VIEW_SPR_X0 - EMUZ_OX
	pha
	lda #0
	bcc .sws_xlo
	lda ws_msb,x
.sws_xlo
	+ws_sta ws_xmsb_lo, ws_xmsb_hi
	pla
	+ws_sta ws_vx_lo, ws_vx_hi
	lda ws_colsrc,x
	bne .sws_nocol
	lda #COL_FX
	+ws_sta ws_col_lo, ws_col_hi
.sws_nocol
	lda ws_snd,x
	beq .sws_arm
	lda ws_hdr_lo,x
	sta fx_ptr
	lda ws_hdr_hi,x
	sta fx_ptr+1
	ldy #FXH_ON
	lda (fx_ptr),y
	bne .sws_arm
	lda ws_snd,x
	stx wpn_tmp0
	jsr play_sound
	ldx wpn_tmp0
.sws_arm
	lda ws_hdr_lo,x
	sta fx_ptr
	lda ws_hdr_hi,x
	sta fx_ptr+1
	lda #1
	ldy #FXH_ON
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	lda ws_ms_l,x
	ldy #FXH_MS_L
	sta (fx_ptr),y
	lda ws_ms_h,x
	iny
	sta (fx_ptr),y
	rts

; Count the blast, then wait until the kick and the muzzle flash are both gone.
tick_cock_wait
	lda cock_ms_l
	ora cock_ms_h
	beq .tcw_pend
	sec
	lda cock_ms_l
	sbc dt_ms
	sta cock_ms_l
	lda cock_ms_h
	sbc dt_msh
	sta cock_ms_h
	bcc .tcw_due
	lda cock_ms_l
	ora cock_ms_h
	bne .tcw_rts
.tcw_due
	lda #0
	sta cock_ms_l
	sta cock_ms_h
	lda #1
	sta cock_pend
.tcw_pend
	lda cock_pend
	beq .tcw_rts
	lda wpn_pose
	bne .tcw_rts
	lda flash_phase
	ora flash5_phase
	bne .tcw_rts
	jmp start_cock
.tcw_rts
	rts

start_cock
	lda #0
	sta cock_pend
	lda #1
	sta wpn_fr
	lda #POSE_COCK
	sta wpn_pose
	lda #0
	sta anim_step
	lda #COCK_X
	sta wpn_x
	jmp cock_apply_step

cock_apply_step
	ldx anim_step
	cpx #1
	bne .cas_y
	lda #SOUND_SGCOCK
	jsr play_sound
	ldx anim_step
.cas_y
	lda cock_y,x
	sta wpn_y
	lda cock_step_ms,x
	sta anim_ms_l
	lda #0
	sta anim_ms_h
	rts

tick_anim
	lda wpn_pose
	cmp #POSE_ANIM
	beq .ta_tick
	cmp #POSE_RECOIL
	beq .ta_tick
	cmp #POSE_COCK
	bne .ta_rts
.ta_tick
	sec
	lda anim_ms_l
	sbc dt_ms
	sta anim_ms_l
	lda anim_ms_h
	sbc dt_msh
	sta anim_ms_h
	bcc .ta_exp
	ora anim_ms_l
	bne .ta_rts
.ta_exp
	lda wpn_pose
	cmp #POSE_COCK
	beq .ta_cock_done
	inc anim_step
	cmp #POSE_RECOIL
	beq .ta_rec
	jmp wpn_to_idle
.ta_rec
	jmp recoil_apply_step
.ta_cock_done
	inc anim_step
	lda anim_step
	cmp #COCK_NSTEPS
	bcc .ta_cock_step
	jmp wpn_to_idle
.ta_cock_step
	jmp cock_apply_step
.ta_rts
	rts
