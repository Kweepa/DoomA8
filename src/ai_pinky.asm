; Streamed Pinky. Bite only. Linked at AI_LINK_BASE.
!cpu 6502
!to "../enemies/ai_pinky.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_pinky_entry
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
	jsr enemy_same_floor
	bcc .aa_rts
	jsr enemy_chebyshev
	cmp #DEMON_MELEE_R
	bcs .aa_rts
	jsr enemy_shot_clear
	bcc .aa_rts
	lda #0
	jmp enemy_enter_demon_attack
.aa_rts
	rts

.approach_enter
	ldx enemy_idx
	lda #<DOOM_ATK_MS
	sta en_timer,x
	lda #>DOOM_ATK_MS
	sta en_timer_h,x
	jmp select_dodge_dir

; Bite. Damage (rnd & 7)+1, times 3.
.fire
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

.attack_end
	jmp enemy_enter_approach
