; Streamed Zombie chase / flesh-throw / knockdown. Linked at AI_LINK_BASE.
!cpu 6502
!to "../enemies/ai_zombie.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_zombie_entry
	cmp #AI_CMD_ATTACK_TICK
	beq .tick
	cmp #AI_CMD_ATTACK_END
	bne +
	jmp .attack_end
+
	cmp #AI_CMD_APPROACH_MOVE
	beq .approach_move
	cmp #AI_CMD_APPROACH_ATTACK
	beq .approach_attack
	cmp #AI_CMD_APPROACH_ENTER
	beq .approach_enter
	cmp #AI_CMD_ANIM_FIRE
	bne +
	jmp .anim_fire
+
	cmp #AI_CMD_RED_ON
	bne +
	lda #$49				; eor #m
	jmp .z_ops
+
	cmp #AI_CMD_RED_OFF
	bne +
	lda #$09				; ora #m
	jmp .z_ops
+
	rts

; Throw is the anim step that crosses the last frame, not this think.
.tick
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
	cmp #>ZOMBIE_STEP_MS
	bcc .done
	bne .go
	lda en_step,x
	cmp #<ZOMBIE_STEP_MS
	bcc .done
.go
	sec
	lda en_step,x
	sbc #<ZOMBIE_STEP_MS
	sta en_step,x
	lda en_step_h,x
	sbc #>ZOMBIE_STEP_MS
	sta en_step_h,x
	jsr enemy_try_step
	ldx enemy_idx
	jmp .slp
.done
	ldx enemy_idx
	lda #AI_AP_STAND
	rts

.approach_attack
	jsr .flesh_live
	bcs .aa_rts
	jsr .throw_busy
	bcs .aa_rts
	jsr enemy_shot_clear
	bcs +
.aa_rts
	rts
+
	jmp enemy_enter_attack

.approach_enter
	ldx enemy_idx
	lda #<ZOMBIE_ATK_MS
	sta en_timer,x
	lda #>ZOMBIE_ATK_MS
	sta en_timer_h,x
	jmp select_dodge_dir

.fire
	jsr .flesh_live
	bcc +
	rts
+
	ldx enemy_idx
	lda en_frame,x
	pha
	jsr pain_var_off
	lda enemy_attack_len,y
	sec
	sbc #3				; melee sound: two frames before the last
	ldx enemy_idx
	sta en_frame,x
	stx obj_i
	+lda_mx en_type
	sta ent_type
	ldy #GREN_WRIST_L
	jsr ent_vert_world
	lda org_yh
	pha
	ldy #GREN_WRIST_R
	jsr ent_vert_world
	pla
	cmp org_yh
	bcc .fire_hand
	beq .fire_hand
	ldy #GREN_WRIST_L
	jsr ent_vert_world
.fire_hand
	ldx enemy_idx
	pla
	sta en_frame,x
	jsr gren_alloc
	bcc .fire_rts
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
	lda #GREN_OWN_EN
	jsr gren_fill_slot
	ldx obj_i
	lda #GREN_F_FLESH
	sta gr_flags,x
	jmp .z_aim
.fire_rts
	rts

; Straight line to the chest at speed 16. Same length estimate as lava
; (max + 3/8 of the other two). component << 12 is speed*256.
; d = chest - slot. Velocity bytes are 4 apart per slot, axes 8 apart.
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
	sbc gr_yh,x			; cam_yh - gr_yh - 1: chest
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
	sta zc_t			; (sum-max)/4
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
	ror div_n1			; << 12 → speed 16
	sta div_n2
	jsr div24u8			; keeps Y
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

; Old frame in en_sfx_old, new frame in en_frame. A = 0: this bank owns the decision.
; Throw frame is this variant's melee sound frame (attack_len - 3).
.anim_fire
	ldx enemy_idx
	lda en_frame,x
	jsr pain_var_off
	lda enemy_attack_len,y
	sec
	sbc #3
	jsr .crossed
	bcc .af_own
	jsr .fire
.af_own
	lda #0
	rts

; A = fire frame. C=1 if en_sfx_old < frame <= en_frame.
.crossed
	bmi .cr_no
	cmp en_sfx_old
	beq .cr_no
	bcc .cr_no
	sta rot1
	ldx enemy_idx
	lda en_frame,x
	cmp rot1
	rts
.cr_no
	clc
	rts

.flesh_live
	ldx #0
.fl
	lda gr_on,x
	beq .fl_n
	lda gr_flags,x
	and #GREN_F_FLESH
	beq .fl_n
	sec
	rts
.fl_n
	inx
	cpx #GREN_MAX
	bcc .fl
	clc
	rts

; C=1 if another zombie in this room is already in EN_ATTACK.
.throw_busy
	ldx #0
.tb
	cpx map_nenemies
	bcs .tb_no
	cpx enemy_idx
	beq .tb_n
	lda en_state,x
	cmp #EN_ATTACK
	bne .tb_n
	+lda_mx en_room
	cmp room_idx
	bne .tb_n
	+lda_mx en_type
	cmp #ENT_ZOMBIE
	beq .tb_yes
.tb_n
	inx
	bne .tb
.tb_no
	clc
	rts
.tb_yes
	sec
	rts

.attack_end
	ldx enemy_idx
	jmp enemy_enter_approach

; Line bodies are lda (colptr),y / ora #m / sta (colptr),y. eor over paper %01 gives %10 (COLPF1 red).
.z_ops
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

; Data after all code so genaimeta's opcode walk stays aligned.
zc_sg	!byte 0, 0, 0		; signed dx, dy, dz
zc_ad	!byte 0, 0, 0		; magnitudes
zc_t	!byte 0
zc_mx	!byte 0
