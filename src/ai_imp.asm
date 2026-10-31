; Streamed Imp. Claw in melee, fireball in missile. Linked at AI_LINK_BASE.
!cpu 6502
!to "../enemies/ai_imp.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_imp_entry
	cmp #AI_CMD_FIRE
	bne +
	jmp .fire
+
	cmp #AI_CMD_ATTACK_END
	bne +
	jmp .attack_end
+
	cmp #AI_CMD_APPROACH_MOVE
	beq .approach_move
	cmp #AI_CMD_APPROACH_ATTACK
	bne +
	jmp .approach_attack
+
	cmp #AI_CMD_APPROACH_ENTER
	bne +
	jmp .approach_enter
+
	rts

.approach_move
	ldx enemy_idx
	clc
	lda en_step,x
	adc dt_ms
	sta en_step,x
	lda en_step_h,x
	adc dt_msh
	sta en_step_h,x
.slp
	lda en_step_h,x
	cmp #>DOOM_STEP_MS
	bcc .done
	bne .go
	lda en_step,x
	cmp #<DOOM_STEP_MS
	bcc .done
.go
	sec
	lda en_step,x
	sbc #<DOOM_STEP_MS
	sta en_step,x
	lda en_step_h,x
	sbc #>DOOM_STEP_MS
	sta en_step_h,x
	jsr enemy_try_step
	ldx enemy_idx
	jmp .slp
.done
	lda #AI_AP_STAND
	rts

.approach_attack
	jsr .fireball_live
	bcs .aa_rts
	jsr enemy_shot_clear
	bcc .aa_rts
	jsr enemy_chebyshev
	cmp #DEMON_MELEE_R
	bcs .aa_miss
	jsr enemy_same_floor
	bcc .aa_miss
	ldx enemy_idx
	lda #0
	sta atk_kind,x
	jmp enemy_enter_demon_attack
.aa_miss
	jsr .missile_ok
	bcc .aa_rts
	ldx enemy_idx
	lda #1
	sta atk_kind,x
	jmp enemy_enter_demon_attack
.aa_rts
	rts

; dist capped at 12. (dist<<4)-64. Borrow always fires. rnd8 < dist fails.
.missile_ok
	jsr enemy_chebyshev
	cmp #13
	bcc +
	lda #12
+
	asl
	asl
	asl
	asl
	sec
	sbc #64
	bcc .mok_yes
	cmp #201
	bcc +
	lda #200
+
	sta .thr
	jsr rnd8
	cmp .thr
	bcc .mok_no
.mok_yes
	sec
	rts
.mok_no
	clc
	rts

.approach_enter
	ldx enemy_idx
	lda #<IMP_ATK_MS
	sta en_timer,x
	lda #>IMP_ATK_MS
	sta en_timer_h,x
	jmp select_dodge_dir

; Melee claws. Missile throws one fireball. Same attack clip.
.fire
	ldx enemy_idx
	lda atk_kind,x
	bne .throw
	jsr enemy_same_floor
	bcc .fire_rts
	jsr enemy_chebyshev
	cmp #DEMON_MELEE_R
	bcs .fire_rts
	jsr enemy_shot_clear
	bcc .fire_rts
	jsr rnd8
	and #7
	clc
	adc #1
	sta rot1
	asl
	clc
	adc rot1
	jmp take_damage
.fire_rts
	rts

.throw
	jsr .fireball_live
	bcs .throw_rts
	ldx enemy_idx
	stx obj_i
	+lda_mx en_type
	sta ent_type
	ldy #RKT_WRIST_L
	jsr ent_vert_world
	lda org_yh
	pha
	ldy #RKT_WRIST_R
	jsr ent_vert_world
	pla
	cmp org_yh
	bcc .fire_hand
	beq .fire_hand
	ldy #RKT_WRIST_L
	jsr ent_vert_world
.fire_hand
	jsr rkt_alloc
	bcc .throw_rts
	stx obj_i
	lda cam_xh
	sec
	sbc org_xh
	sta rot0
	lda cam_zh
	sec
	sbc org_zh
	sta rot1
	jsr atan2_yaw
	sta rot2
	ldx obj_i
	lda #RKT_OWN_EN
	jsr rkt_fill_slot
	ldx obj_i
	lda #RKT_F_FIREBALL
	sta gr_flags,x
	jmp .z_aim
.throw_rts
	rts

; Straight line to the chest at speed 16. component << 12 is speed*256.
!if (gr_vxh != gr_vxl + 4) | (gr_vyl != gr_vxl + 8) | (gr_vzl != gr_vxl + 16) | (gr_vzh != gr_vxl + 20) {
	!error "gr_v* layout"
}
.z_aim
	ldx obj_i
	lda cam_xh
	sec
	sbc gr_xh,x
	sta zc_sg
	lda cam_yh
	clc
	sbc gr_yh,x
	sta zc_sg+1
	lda cam_zh
	sec
	sbc gr_zh,x
	sta zc_sg+2
	ldy #2
.za_abs
	lda zc_sg,y
	jsr .z_abs
	sta zc_ad,y
	dey
	bpl .za_abs
	lda zc_ad
	clc
	adc zc_ad+1
	adc zc_ad+2
	sta zc_t
	lda zc_ad
	cmp zc_ad+1
	bcs +
	lda zc_ad+1
+
	cmp zc_ad+2
	bcs +
	lda zc_ad+2
+
	sta zc_mx
	lda zc_t
	sec
	sbc zc_mx
	lsr
	lsr
	sta zc_t
	lsr
	clc
	adc zc_t
	clc
	adc zc_mx
	bne +
	lda #1
+
	sta dlo
	ldy #0
.za_ax
	lda #0
	sta div_n0
	sta div_n1
	lda zc_ad,y
	lsr
	ror div_n1
	lsr
	ror div_n1
	lsr
	ror div_n1
	lsr
	ror div_n1
	sta div_n2
	jsr div24u8
	lda zc_sg,y
	bpl .za_pos
	sec
	lda #0
	sbc div_n0
	sta div_n0
	lda #0
	sbc div_n1
	sta div_n1
.za_pos
	tya
	asl
	asl
	asl
	clc
	adc obj_i
	tax
	lda div_n0
	sta gr_vxl,x
	lda div_n1
	sta gr_vxh,x
	iny
	cpy #3
	bne .za_ax
	rts

.z_abs
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts

.fireball_live
	ldx #0
.fl
	lda gr_on,x
	beq .fl_n
	lda gr_flags,x
	and #RKT_F_FIREBALL
	beq .fl_n
	sec
	rts
.fl_n
	inx
	cpx #RKT_MAX
	bcc .fl
	clc
	rts

.attack_end
	jmp enemy_enter_approach

; After every opcode so the reloc walk stays aligned.
.thr	!byte 0
zc_sg	!byte 0, 0, 0
zc_ad	!byte 0, 0, 0
zc_t	!byte 0
zc_mx	!byte 0
