; One rect per graphic: x_byte, y, width, height, then row-major bytes.
; Bodies are inverted (ink %00, clear %11) and ANDed, so the gun is black.
; Flashes, splats, and the enemy muzzle are ink %11. ORA paints line colour;
; red writes pixel %10 (COLPF1). X is phase 0 (a multiple of 8 hires).
!zone a8stamp

stamp_x		!byte 0
stamp_xh	!byte 0
stamp_y		!byte 0
stamp_w		!byte 0
stamp_h		!byte 0
stamp_xb	!byte 0
stamp_and	!byte 0			; 1 = AND the plane (black body)
stamp_red	!byte 0			; 1 = pixel %10
stamp_bl	!byte 0			; world-sprite byte column, signed
stamp_bh	!byte 0
stamp_tmp	!byte 0

stamp_view
	lda wpn_x
	sec
	sbc #VIEW_SPR_X0
	lsr
	lsr
	lsr
	sta stamp_xb
	lda wpn_y
	sec
	sbc #VIEW_SPR_Y0
	sta stamp_y
	ldx cur_weapon
	lda wpn_fr_base,x
	clc
	adc wpn_fr
	tax
	lda wpn_fr_lo,x
	sta init_ptr
	lda wpn_fr_hi,x
	sta init_ptr+1
	lda #1
	sta stamp_and
	lda #0
	sta stamp_red
	jsr blit_rect

	lda wpn_pose
	cmp #POSE_COCK
	beq .no5
	lda flash_phase
	beq .no4
	ldx cur_weapon
	lda wpn_fl4_lo,x
	sta init_ptr
	lda wpn_fl4_hi,x
	sta init_ptr+1
	lda flash_phase
	jsr stamp_flash
.no4
	lda flash5_phase
	beq .no5
	lda #<spr_chain_fr_b
	sta init_ptr
	lda #>spr_chain_fr_b
	sta init_ptr+1
	lda flash5_phase
	jsr stamp_flash
.no5
	lda emuz_on
	beq .noe
	lda emuz_vx
	ldx emuz_xmsb
	jsr stamp_set_xmsb
	lda emuz_vy
	jsr stamp_set_y
	jsr stamp_emuz
.noe
	lda splat_on
	beq .nos
	lda splat_vx
	ldx splat_xmsb
	jsr stamp_set_xmsb
	lda splat_vy
	jsr stamp_set_y
	jsr stamp_splat
.nos
	rts

; init_ptr set. A is the phase (1 = line colour, 2 = red). X is absolute,
; so the anchor byte is 0 and the header x_byte is the viewport column.
stamp_flash
	ldx #0
	cmp #2
	bne .yel
	inx
.yel
	stx stamp_red
	lda #0
	sta stamp_and
	sta stamp_xb
	lda wpn_y
	sec
	sbc #VIEW_SPR_Y0
	sta stamp_y
	jmp blit_rect

; init_ptr = one rect. stamp_xb / stamp_y are the anchor; the header
; x_byte and y are added. Rows at y >= 128 are skipped so a stock can
; hang off the bottom. The op is chosen once per row.
blit_rect
	ldy #0
	lda (init_ptr),y
	clc
	adc stamp_xb
	sta stamp_xb
	iny
	lda (init_ptr),y
	clc
	adc stamp_y
	sta stamp_y
	iny
	lda (init_ptr),y
	sta stamp_w
	iny
	lda (init_ptr),y
	sta stamp_h
	clc
	lda init_ptr
	adc #4
	sta src_ptr
	lda init_ptr+1
	adc #0
	sta src_ptr+1
.row
	lda stamp_y
	cmp #128
	bcs .adv
	jsr blit_scan
.adv
	clc
	lda src_ptr
	adc stamp_w
	sta src_ptr
	bcc .src_ok
	inc src_ptr+1
.src_ok
	inc stamp_y
	dec stamp_h
	bne .row
	rts

blit_scan
	lda #0
	sta dst_ptr+1
	lda stamp_y
	sta dst_ptr
	ldx #5
-
	asl dst_ptr
	rol dst_ptr+1
	dex
	bne -
	clc
	lda dst_ptr
	adc #BMP_MARGIN
	adc stamp_xb
	sta dst_ptr
	lda dst_ptr+1
	adc #0
	adc bmp_hi
	sta dst_ptr+1
	lda stamp_and
	bne .and
	lda stamp_red
	bne .red
	ldy #0
.ora
	lda (dst_ptr),y
	ora (src_ptr),y
	sta (dst_ptr),y
	iny
	cpy stamp_w
	bne .ora
	rts
.and
	ldy #0
-
	lda (dst_ptr),y
	and (src_ptr),y
	sta (dst_ptr),y
	iny
	cpy stamp_w
	bne -
	rts
.red
	ldy #0
-
	lda (src_ptr),y
	sta stamp_tmp
	and #$55
	pha
	lda (dst_ptr),y
	ora stamp_tmp
	sta stamp_tmp
	pla
	eor stamp_tmp
	sta (dst_ptr),y
	iny
	cpy stamp_w
	bne -
	rts

; A = VIC x, X = msb flag (nonzero → +256)
stamp_set_xmsb
	sec
	sbc #VIEW_SPR_X0
	sta stamp_x
	lda #0
	sbc #0
	cpx #1
	bcc .nm
	clc
	adc #1
.nm
	sta stamp_xh
	rts

; A = VIC y
stamp_set_y
	sec
	sbc #VIEW_SPR_Y0
	sta stamp_y
	rts

; Enemy muzzle. Always pixel %10. Anchor is the uncropped 24×21.
stamp_emuz
	lda emuz_src
	sta init_ptr
	lda emuz_src+1
	sta init_ptr+1
	lda #0
	sta stamp_and
	lda #1
	sta stamp_red
	jmp stamp_anchor

; Splat. Hit writes %10. Miss ORs. Same uncropped anchor as the muzzle.
stamp_splat
	lda splat_src
	sta init_ptr
	lda splat_src+1
	sta init_ptr+1
	lda #0
	sta stamp_and
	sta stamp_red
	lda splat_col
	cmp #COL_SPLAT_HIT
	bne stamp_anchor
	inc stamp_red

; Snap the uncropped left (tip − EMUZ_OX, already in stamp_x) to a byte
; and keep that 24×21 box inside the viewport. blit_rect then adds the
; header crop, so the ink stays on the tip.
stamp_anchor
	clc
	lda stamp_x
	adc #4
	sta stamp_bl
	lda stamp_xh
	adc #0
	sta stamp_bh
	ldx #3
-
	lda stamp_bh
	cmp #$80
	ror stamp_bh
	ror stamp_bl			; signed (hires+4)>>3, nearest byte
	dex
	bne -
	lda stamp_bh
	bmi .xlo
	bne .xhi
	lda stamp_bl
	cmp #BMP_DRAW_W-2		; 3 bytes must end by column 23
	bcc .xin
.xhi
	lda #BMP_DRAW_W-3
	sta stamp_xb
	jmp .yfix
.xlo
	lda #0
	sta stamp_xb
	jmp .yfix
.xin
	lda stamp_bl
	sta stamp_xb
.yfix
	lda stamp_y
	bpl .ypos
	lda #0
	sta stamp_y
	beq .go
.ypos
	cmp #128-20
	bcc .go
	lda #128-21
	sta stamp_y
.go
	jmp blit_rect
