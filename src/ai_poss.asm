; Streamed Possessed approach / reattack / hitscan. Linked at AI_LINK_BASE.
!cpu 6502
!to "../enemies/ai_poss.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_poss_entry
	cmp #AI_CMD_DEATH
	bne +
	jmp .death
+
	cmp #AI_CMD_FIRE
	beq .fire
	cmp #AI_CMD_ATTACK_END
	beq .attack_end
	cmp #AI_CMD_APPROACH_MOVE
	beq .approach_move
	cmp #AI_CMD_APPROACH_ATTACK
	beq .approach_attack
	cmp #AI_CMD_APPROACH_ENTER
	beq .approach_enter
	rts

.approach_move
	jmp .step

.approach_attack
	jsr enemy_shot_clear
	bcs .attack_go
	rts
.attack_go
	jmp enemy_enter_attack

.approach_enter
	ldx enemy_idx
	lda #<GRUNT_ATK_MS
	sta en_timer,x
	lda #>GRUNT_ATK_MS
	sta en_timer_h,x
	jmp select_dodge_dir

; LOS, then miss if rnd8 < dist*4. Hit is 8–15. Muzzle is this same call.
.fire
	lda enemy_idx
	sta emuz_pending
	jsr enemy_shot_clear
	bcc .fire_rts
	ldx enemy_idx
	jsr enemy_chebyshev
	asl
	asl
	bcs .fire_rts		; dist ≥ 64
	sta rot1
	jsr rnd8
	cmp rot1
	bcc .fire_rts
	and #7
	clc
	adc #8
	jmp take_damage
.fire_rts
	rts

.attack_end
	jmp enemy_enter_approach

.death
	lda #BP_SHELLS
	jmp spawn_death_drop

.step
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
