; Bouncing rockets: player rocket launcher. Faction owner (contact skips
; allies; splash does not). One explosion at a time via fx_on.
; Fireballs are imp and baron shots: no bounce, direct hit only.
!zone rocket

init_rockets
	ldx #RKT_MAX - 1
	lda #0
.ig
	sta gr_on,x
	dex
	bpl .ig
	rts

; C=1 X=free slot; C=0 full
rkt_alloc
	ldx #0
.ga
	lda gr_on,x
	beq .ga_ok
	inx
	cpx #RKT_MAX
	bcc .ga
	clc
	rts
.ga_ok
	sec
	rts

; A = yaw. Y = horizontal speed. X = slot. Upward RKT_SPEED_Y.
rkt_set_vel
	stx obj_i
	sta rot2
	sty rot0
	tay
	lda SINTAB,y
	ldy rot0
	jsr smul7
	ldx obj_i
	sta gr_vxh,x
	lda #0
	sta gr_vxl,x
	ldy rot2
	lda COSTAB,y
	ldy rot0
	jsr smul7
	ldx obj_i
	sta gr_vzh,x
	lda #0
	sta gr_vzl,x
	lda #RKT_SPEED_Y
	sta gr_vyh,x
	lda #0
	sta gr_vyl,x
	rts

; X=slot. org_* = pos. rot2 = aim yaw. A = owner.
rkt_fill_slot
	sta gr_owner,x
	lda org_xl
	sta gr_xl,x
	lda org_xh
	sta gr_xh,x
	lda org_yl
	sta gr_yl,x
	lda org_yh
	sta gr_yh,x
	lda org_zl
	sta gr_zl,x
	lda org_zh
	sta gr_zh,x
	lda #0
	sta gr_flags,x
	sta gr_acc,x
	sta gr_fuse_l,x
	sta gr_fuse_h,x
	lda #<RKT_LIFE_MS
	sta gr_life_l,x
	lda #>RKT_LIFE_MS
	sta gr_life_h,x
	lda #1
	sta gr_on,x
	ldy #RKT_SPEED
	lda gr_owner,x
	bne +
	ldy #RKT_SPEED_PL
+
	lda rot2
	jmp rkt_set_vel

; Player center: cam xz, Y = feet + 2 (eye − (EYE_HEIGHT − 2)).
spawn_player_rocket
	jsr rkt_alloc
	bcc .spg_rts
	stx obj_i
	lda cam_xl
	sta org_xl
	lda cam_xh
	sta org_xh
	lda cam_zl
	sta org_zl
	lda cam_zh
	sta org_zh
	lda cam_yl
	sta org_yl
	lda cam_yh
	sec
	sbc #EYE_HEIGHT - 2
	sta org_yh
	ldx obj_i
	lda yaw
	sta rot2
	lda #RKT_OWN_PL
	jsr rkt_fill_slot
.spg_rts
	rts

update_rockets
	ldx #0
.ug
	cpx #RKT_MAX
	bcs .ug_rts
	lda gr_on,x
	beq .ug_n
	jsr rkt_tick
	ldx obj_i
.ug_n
	inx
	bne .ug
.ug_rts
	rts

rkt_tick
	stx obj_i
	lda room_idx
	sta col_room
	clc
	lda gr_acc,x
	adc dt_ms
	sta proc_tmp0
	lda #0
	adc dt_msh
	sta proc_tmp1
.gt_tick
	lda proc_tmp1
	bne .gt_step
	lda proc_tmp0
	cmp #RKT_TICK_MS
	bcc .gt_tdone
.gt_step
	sec
	lda proc_tmp0
	sbc #RKT_TICK_MS
	sta proc_tmp0
	lda proc_tmp1
	sbc #0
	sta proc_tmp1
	ldx obj_i
	lda gr_flags,x
	and #RKT_F_FIREBALL
	bne .gt_move
	sec
	lda gr_vyl,x
	sbc #<RKT_GRAV
	sta gr_vyl,x
	lda gr_vyh,x
	sbc #>RKT_GRAV
	sta gr_vyh,x
.gt_move
	jsr rkt_move_x
	jsr rkt_move_z
	jsr rkt_move_y
	ldx obj_i
	lda gr_owner,x
	bne .gt_vspl
	jsr rkt_hit_enemies
	jmp .gt_hitd
.gt_vspl
	jsr rkt_hit_player
.gt_hitd
	ldx obj_i
	lda gr_on,x
	beq .gt_rts
	lda gr_flags,x
	and #RKT_F_PEND
	bne .gt_tdone
	jmp .gt_tick
.gt_tdone
	ldx obj_i
	lda proc_tmp0
	sta gr_acc,x
	jsr rkt_contact
	ldx obj_i
	lda gr_on,x
	beq .gt_rts
	lda gr_flags,x
	and #RKT_F_PEND
	beq .gt_fuse
	lda fx_on
	bne .gt_life
	jsr rkt_explode
	jmp .gt_rts
.gt_fuse
	lda gr_flags,x
	and #RKT_F_BOUNCE
	beq .gt_life
	sec
	lda gr_fuse_l,x
	sbc dt_ms
	sta gr_fuse_l,x
	lda gr_fuse_h,x
	sbc dt_msh
	sta gr_fuse_h,x
	bcs .gt_life
	jsr rkt_explode
	jmp .gt_rts
.gt_life
	ldx obj_i
	sec
	lda gr_life_l,x
	sbc dt_ms
	sta gr_life_l,x
	lda gr_life_h,x
	sbc dt_msh
	sta gr_life_h,x
	bcs .gt_rts
	jsr rkt_explode
.gt_rts
	rts

rkt_asr_ay
	sta nlo
	sty nhi
rkt_asr5
	ldy #5
.ga5
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	dey
	bne .ga5
	rts

!if (gr_vxh != gr_vxl + 4) | (gr_vyl != gr_vxl + 8) | (gr_vyh != gr_vyl + 4) | (gr_vzl != gr_vxl + 16) | (gr_vzh != gr_vzl + 4) {
	!error "gr_v* layout"
}
; A = <vel_lo (Y unused). Negate and asr1.
rkt_bounce
	pha
	ldx obj_i
	lda gr_flags,x
	and #RKT_F_FIREBALL
	beq .gb_n
	pla
	jmp rkt_clear
.gb_n
	pla
	; A = <gr_v?l. The arrays are 4 apart per slot, axes 8 apart, hi = lo + 4,
	; and they straddle a page, so index off gr_vxl instead of patching low bytes.
	sec
	sbc #<gr_vxl
	clc
	adc obj_i
	tax
	sec
	lda #0
	sbc gr_vxl,x
	sta gr_vxl,x
	lda #0
	sbc gr_vxl+4,x
	sta gr_vxl+4,x
	cmp #$80
	ror gr_vxl+4,x
	ror gr_vxl,x
	ldx obj_i
	lda gr_flags,x
	and #RKT_F_BOUNCE
	bne .gmb_rts
	lda gr_flags,x
	ora #RKT_F_BOUNCE
	sta gr_flags,x
	lda #<RKT_FUSE_MS
	sta gr_fuse_l,x
	lda #>RKT_FUSE_MS
	sta gr_fuse_h,x
.gmb_rts
	rts

; Signed ASR vx and vz (floor hop only).
rkt_floor_xz
	ldx obj_i
	ldy #RKT_FLOOR_XZ_ASR
.gfx
	lda gr_vxh,x
	cmp #$80
	ror gr_vxh,x
	ror gr_vxl,x
	dey
	bne .gfx
	ldy #RKT_FLOOR_XZ_ASR
.gfz
	lda gr_vzh,x
	cmp #$80
	ror gr_vzh,x
	ror gr_vzl,x
	dey
	bne .gfz
	rts

rkt_move_x
	ldx obj_i
	lda gr_vxl,x
	ldy gr_vxh,x
	jsr rkt_asr_ay
	clc
	lda gr_xl,x
	adc nlo
	sta save_xl
	lda gr_xh,x
	adc nhi
	sta save_xh
	sta col_x
	lda gr_zh,x
	sta col_z
	lda #0
	beq rkt_xz_done

rkt_move_z
	ldx obj_i
	lda gr_vzl,x
	ldy gr_vzh,x
	jsr rkt_asr_ay
	clc
	lda gr_zl,x
	adc nlo
	sta save_xl
	lda gr_zh,x
	adc nhi
	sta save_xh
	lda gr_xh,x
	sta col_x
	lda save_xh
	sta col_z
	lda #1
rkt_xz_done
	sta pv2
	jsr rkt_pos_ok
	bcs .ok
	lda pv2
	bne .bz
	lda #<gr_vxl
	ldy #<gr_vxh
	jmp rkt_bounce
.bz
	lda #<gr_vzl
	ldy #<gr_vzh
	jmp rkt_bounce
.ok
	ldx obj_i
	lda pv2
	bne .sz
	lda save_xl
	sta gr_xl,x
	lda save_xh
	sta gr_xh,x
	rts
.sz
	lda save_xl
	sta gr_zl,x
	lda save_xh
	sta gr_zh,x
	rts

rkt_move_y
	ldx obj_i
	lda gr_vyl,x
	ldy gr_vyh,x
	jsr rkt_asr_ay
	clc
	lda gr_yl,x
	adc nlo
	sta save_xl
	lda gr_yh,x
	adc nhi
	sta save_xh
	lda gr_vyh,x
	bmi .gmy_down
	ldy room_idx
	jsr load_box_room
	clc
	lda box_y
	adc box_sy
	cmp save_xh
	beq .gmy_ceil
	bcc .gmy_ceil
	jmp rkt_try_y
.gmy_ceil
	lda #<gr_vyl
	ldy #<gr_vyh
	jmp rkt_bounce
.gmy_down
	jsr rkt_col_xz
	ldx obj_i
	lda gr_yh,x
	sta fb_probe_y
	ldy col_room
	lda proc_tmp0			; tick ms remainder: peek_rc_floor zeroes it
	pha
	jsr floor_below_y
	pla
	sta proc_tmp0			; PLA/STA keep C
	bcc rkt_try_y
	lda proc_tmp2
	cmp save_xh
	beq .gmy_land
	bcc rkt_try_y
.gmy_land
	ldx obj_i
	lda #0
	sta gr_yl,x
	lda proc_tmp2
	sta gr_yh,x
	jsr rkt_floor_xz
	lda #<gr_vyl
	ldy #<gr_vyh
	jmp rkt_bounce

rkt_try_y
	ldx obj_i
	lda gr_yl,x
	sta pv0
	lda gr_yh,x
	sta pv1
	lda save_xl
	sta gr_yl,x
	lda save_xh
	sta gr_yh,x
	jsr rkt_col_xz
	jsr rkt_solid_at
	ldx obj_i
	bcc .gty_ok
	lda pv0
	sta gr_yl,x
	lda pv1
	sta gr_yh,x
	lda #<gr_vyl
	ldy #<gr_vyh
	jmp rkt_bounce
.gty_ok
	rts

rkt_col_xz
	ldx obj_i
	lda gr_xh,x
	sta col_x
	lda gr_zh,x
	sta col_z
	rts

; C=1 allowed (room colliders only — doors do not pass rockets)
rkt_pos_ok
	; Rockets are points: the PLAYER_R wall margin killed them at the launcher.
	lda col_room
	jsr room_mul3
	tax
	jsr point_in_rc_xz
	bcs .gpo_sol
	inx
	jsr point_in_rc_xz
	bcs .gpo_sol
	inx
	jsr point_in_rc_xz
	bcc .gpo_no
.gpo_sol
	jsr rkt_solid_at
	bcs .gpo_no
	sec
	rts
.gpo_no
	clc
	rts

; Point as player AABB of height PLAYER_H at rocket Y (feet).
rkt_solid_at
	lda cam_yh
	pha
	ldx obj_i
	clc
	lda gr_yh,x
	adc #EYE_HEIGHT
	sta cam_yh
	ldy #0
	jsr solid_at_col
	pla
	sta cam_yh
	rts

rkt_contact
	ldx obj_i
	lda gr_owner,x
	bne rkt_hit_player

rkt_hit_enemies
	jsr rkt_touch_barrel
	ldx obj_i
	lda gr_on,x
	beq .ghe_rts
	ldx #0
.ghe
	cpx	map_nenemies
	bcs .ghe_rts
	stx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcs .ghe_n
	+lda_mx en_x
	sta pv0
	+lda_mx en_z
	sta pv1
	ldx enemy_idx
	lda #RKT_HIT_R + 1
	jsr rkt_near_lim
	bcs .ghe_n
	ldx enemy_idx
	+lda_mx en_y
	sta pv0
	lda #ENEMY_CULL_H
	clc
	adc pv0
	sta pv1
	jsr rkt_in_y
	bcc .ghe_n
	ldx enemy_idx
	jmp rkt_explode
.ghe_n
	ldx enemy_idx
	inx
	bne .ghe
.ghe_rts
	rts

rkt_hit_player
	ldx obj_i
	lda cam_xh
	sta pv0
	lda cam_zh
	sta pv1
	jsr rkt_near_xz
	bcs .ghp_rts
	lda cam_yh
	sec
	sbc #EYE_HEIGHT
	sta pv0
	clc
	adc #PLAYER_H
	sta pv1
	jsr rkt_in_y
	bcc .ghp_rts
	ldx obj_i
	lda gr_flags,x
	and #RKT_F_FIREBALL
	bne rkt_fireball_hit
	jmp rkt_explode
.ghp_rts
	rts

rkt_fireball_hit
	ldx obj_i
	lda gr_flags,x
	and #RKT_F_BARON
	beq +
	lda #30
	bne ++
+
	lda #10
++
	sta rot0
	jsr rnd8
	and #15
	clc
	adc rot0
	jsr take_damage
	jmp rkt_clear

rkt_clear
	ldx obj_i
	lda #0
	sta gr_on,x
	rts

; pv0/pv1 = other x/z. C=1 miss. Limit is RKT_HIT_R+1.
rkt_near_xz
	lda #RKT_HIT_R + 1
; A = exclusive chebyshev limit. C=1 miss.
rkt_near_lim
	sta pv2
	ldx obj_i
	lda gr_xh,x
	sec
	sbc pv0
	jsr rkt_abs
	cmp pv2
	bcs .gnx_no
	lda gr_zh,x
	sec
	sbc pv1
	jsr rkt_abs
	cmp pv2
.gnx_no
	rts

; pv0 inclusive, pv1 exclusive. C=1 inside.
rkt_in_y
	ldx obj_i
	lda gr_yh,x
	cmp pv0
	bcc .giy_no
	cmp pv1
	bcs .giy_no
	sec
	rts
.giy_no
	clc
	rts

rkt_abs
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts

rkt_explode
	ldx obj_i
	lda gr_flags,x
	and #RKT_F_FIREBALL
	beq +
	jmp rkt_clear
+
	lda fx_on
	beq .gex_go
	lda gr_flags,x
	ora #RKT_F_PEND
	sta gr_flags,x
	rts
.gex_go
	jsr rkt_place
	jsr rkt_splash
	jsr start_explosion
	lda #SOUND_RXPLOD
	jsr play_sound
	ldx obj_i
	lda #0
	sta gr_on,x
	rts

rkt_place
	ldx obj_i
	lda gr_xl,x
	sta fx_oxl
	lda gr_xh,x
	sta fx_ox
	sta ent_wx
	lda gr_yl,x
	sta fx_oyl
	lda gr_yh,x
	sta fx_oy
	sta ent_wy
	lda gr_zl,x
	sta fx_ozl
	lda gr_zh,x
	sta fx_oz
	sta ent_wz
	rts

; Chebyshev 3D vs blast origin ent_wx/wy/wz. pv0/1/2 = target. nlo = d.
rkt_cheby
	lda ent_wx
	sec
	sbc pv0
	jsr rkt_abs
	sta nlo
	lda ent_wy
	sec
	sbc pv1
	jsr rkt_abs
	cmp nlo
	bcc +
	sta nlo
+
	lda ent_wz
	sec
	sbc pv2
	jsr rkt_abs
	cmp nlo
	bcc +
	sta nlo
+
	lda nlo
	rts

rkt_splash
	ldx #0
.gsp_lp
	cpx	map_nenemies
	bcs .gsp_rts
	stx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcs .gsp_n
	+lda_mx en_x
	sta pv0
	+lda_mx en_y
	sta pv1
	+lda_mx en_z
	sta pv2
	jsr rkt_cheby
	cmp #RKT_RAD
	bcs .gsp_n
	jsr rnd8
	and #31
	clc
	adc #RKT_DMG_BASE
	ldx enemy_idx
	jsr damage_enemy
.gsp_n
	ldx enemy_idx
	inx
	bne .gsp_lp
.gsp_rts
	rts

; Player rocket only (caller is rkt_hit_enemies). Overlap consumes the
; rocket with its own splash, then detonates the barrel. Not rkt_explode:
; that pends on fx_on and would wait out the chain.
rkt_touch_barrel
	ldx #0
.gtb
	cpx	map_nthings
	bcs .gtb_rts
	lda th_taken,x
	bne .gtb_n
	+lda_mx th_type
	cmp #TH_BARREL
	bne .gtb_n
	+lda_mx th_x
	sta box_x
	+lda_mx th_y
	sta box_y
	+lda_mx th_z
	sta box_z
	jsr set_th_foot_box
	ldy obj_i
	lda gr_xh,y
	sta col_x
	lda gr_zh,y
	sta col_z
	lda #RKT_HIT_R
	jsr near_box_xz
	bcc .gtb_n
	+lda_mx th_y
	sta pv0
	clc
	adc #TH_FOOT_SY
	sta pv1
	txa
	pha
	jsr rkt_in_y
	pla
	tax
	bcc .gtb_n
	lda obj_i
	pha
	txa
	pha
	jsr rkt_place
	jsr rkt_clear
	jsr rkt_splash
	pla
	tax
	jsr barrel_explode
	pla
	sta obj_i
	rts
.gtb_n
	inx
	jmp .gtb
.gtb_rts
	rts

; X = thing index. Splash now, graphic restarts here. Neighbours wait
; BARREL_CHAIN_MS. A taken barrel only drops its pending bit.
barrel_explode
	lda th_taken,x
	beq .bx_go
	jsr barrel_clr_bit
	jmp barrel_arm
.bx_go
	lda #1
	sta th_taken,x
	jsr barrel_clr_bit
	jsr barrel_place
	jsr rkt_splash
	jsr barrel_queue
	jsr start_explosion
	lda #SOUND_RXPLOD
	jsr play_sound
	jmp barrel_arm

; X = thing. Mesh centre → fx origin and ent_w* (splash / graphic).
barrel_place
	jsr barrel_pv
	lda #0
	sta fx_oxl
	sta fx_oyl
	sta fx_ozl
	lda pv0
	sta fx_ox
	sta ent_wx
	lda pv1
	sta fx_oy
	sta ent_wy
	lda pv2
	sta fx_oz
	sta ent_wz
	rts

; X = thing. Centre → pv0/1/2. Preserves X.
barrel_pv
	+lda_mx th_x
	clc
	adc #ITEM_BIAS
	sta pv0
	+lda_mx th_y
	clc
	adc #1
	sta pv1
	+lda_mx th_z
	clc
	adc #ITEM_BIAS
	sta pv2
	rts

; Live barrels whose centres are inside RKT_RAD of ent_w*.
barrel_queue
	ldx #0
.bq
	cpx	map_nthings
	bcs .bq_rts
	lda th_taken,x
	bne .bq_n
	+lda_mx th_type
	cmp #TH_BARREL
	bne .bq_n
	jsr barrel_pv
	jsr rkt_cheby
	cmp #RKT_RAD
	bcs .bq_n
	jsr barrel_set_bit
.bq_n
	inx
	bne .bq
.bq_rts
	rts

; Start the chain delay. An empty queue pops nothing when it expires.
; A direct hit restarts a countdown already running.
barrel_arm
	lda #<BARREL_CHAIN_MS
	sta barrel_ch_l
	lda #>BARREL_CHAIN_MS
	sta barrel_ch_h
	rts

update_barrel_chain
	lda barrel_ch_l
	ora barrel_ch_h
	bne .ubc_go
	rts
.ubc_go
	sec
	lda barrel_ch_l
	sbc dt_ms
	sta barrel_ch_l
	lda barrel_ch_h
	sbc dt_msh
	sta barrel_ch_h
	bcs .ubc_rts
	lda #0
	sta barrel_ch_l
	sta barrel_ch_h
	jsr barrel_pop
	bcc .ubc_rts
	jmp barrel_explode
.ubc_rts
	rts

; C=1, X = lowest set thing index. C=0 none.
barrel_pop
	ldx #0
.bpop
	cpx	map_nthings
	bcs .bpop_none
	jsr barrel_mask
	and barrel_pend,y
	bne .bpop_got
	inx
	bne .bpop
.bpop_none
	clc
	rts
.bpop_got
	sec
	rts

; X = thing index. A = 1<<(X&7), Y = X>>3. Preserves X.
barrel_mask
	txa
	and #7
	tay
	lda barrel_bit,y
	pha
	txa
	lsr
	lsr
	lsr
	tay
	pla
	rts

; X = thing index. Preserves X.
barrel_set_bit
	jsr barrel_mask
	ora barrel_pend,y
	sta barrel_pend,y
	rts

barrel_clr_bit
	jsr barrel_mask
	eor #$ff
	and barrel_pend,y
	sta barrel_pend,y
	rts

barrel_bit
	!byte $01, $02, $04, $08, $10, $20, $40, $80

draw_rockets
	jsr draw_rockets_red
	ldx #0
	stx pv0
.dgr
	cpx #RKT_MAX
	bcs .dgr_rts
	lda gr_on,x
	beq .dgr_n
	lda pv0
	bne .dgr_go
	inc pv0
	stx obj_i
	jsr load_view_trig
	ldx obj_i
.dgr_go
	jsr rkt_draw_one
	jmp .dgr_ld
.dgr_ld
	ldx obj_i
.dgr_n
	inx
	bne .dgr
.dgr_rts
	jmp rkt_red_off

; Every rocket draws red. Restore ora before return so later lines stay paper.
draw_rockets_red
	lda #$49
	bne rkt_red_ops
rkt_red_off
	lda #$09
rkt_red_ops
	sta esd0+2
	sta esd1+2
	sta esd2+2
	sta esd3+2
	sta esu0+2
	sta esu1+2
	sta esu2+2
	sta esu3+2
	sta etd0+2
	sta etd1+2
	sta etd2+2
	sta etd3+2
	sta etu0+2
	sta etu1+2
	sta etu2+2
	sta etu3+2
	rts

; One projected centre, then a screen triangle of half-extent RKT_R.
; Edges are clipped; off-screen corners are not pulled onto the border.
rkt_draw_one
	stx obj_i
	lda gr_xl,x
	sta org_xl
	lda gr_xh,x
	sta org_xh
	lda gr_yl,x
	sta org_yl
	lda gr_yh,x
	sta org_yh
	lda gr_zl,x
	sta org_zl
	lda gr_zh,x
	sta org_zh
	ldx #0
	jsr xform_world_vert88
	jsr cam0_proj_xy
	bcc .gdo_rts
	lda ox0l
	sta gdo_cx
	lda ox0h
	sta gdo_cxh
	lda oy0l
	sta gdo_cy
	lda oy0h
	sta gdo_cyh
	lda #RKT_R
	sta ylo
	lda #0
	sta yhi
	jsr persp88
	sta gdo_r
	jsr .gdo_tl
	jsr .gdo_lr
	jmp .gdo_rt
.gdo_rts
	rts

; Centered space: top (cx, cy+r), left (cx−r, cy−r), right (cx+r, cy−r).
.gdo_tl
	lda gdo_cx
	sta ox0l
	lda gdo_cxh
	sta ox0h
	clc
	lda gdo_cy
	adc gdo_r
	sta oy0l
	lda gdo_cyh
	adc #0
	sta oy0h
	sec
	lda gdo_cx
	sbc gdo_r
	sta ox1l
	lda gdo_cxh
	sbc #0
	sta ox1h
	sec
	lda gdo_cy
	sbc gdo_r
	sta oy1l
	lda gdo_cyh
	sbc #0
	sta oy1h
	jmp clip_draw_xy
.gdo_lr
	sec
	lda gdo_cx
	sbc gdo_r
	sta ox0l
	lda gdo_cxh
	sbc #0
	sta ox0h
	sec
	lda gdo_cy
	sbc gdo_r
	sta oy0l
	lda gdo_cyh
	sbc #0
	sta oy0h
	clc
	lda gdo_cx
	adc gdo_r
	sta ox1l
	lda gdo_cxh
	adc #0
	sta ox1h
	sec
	lda gdo_cy
	sbc gdo_r
	sta oy1l
	lda gdo_cyh
	sbc #0
	sta oy1h
	jmp clip_draw_xy
.gdo_rt
	clc
	lda gdo_cx
	adc gdo_r
	sta ox0l
	lda gdo_cxh
	adc #0
	sta ox0h
	sec
	lda gdo_cy
	sbc gdo_r
	sta oy0l
	lda gdo_cyh
	sbc #0
	sta oy0h
	lda gdo_cx
	sta ox1l
	lda gdo_cxh
	sta ox1h
	clc
	lda gdo_cy
	adc gdo_r
	sta oy1l
	lda gdo_cyh
	adc #0
	sta oy1h
	jmp clip_draw_xy

gdo_cx	!byte 0
gdo_cxh	!byte 0
gdo_cy	!byte 0
gdo_cyh	!byte 0
gdo_r	!byte 0

rocket_end = *
