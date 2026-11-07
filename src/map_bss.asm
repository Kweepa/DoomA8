; Runtime map header + SoA pointers (filled by bind_map).
; Labels are RAM at $0400 (not emitted in GAME). From room_x through slope_flags
; they are pointers into the packed map — columns only via +lda_mx / +sta_mx /
; +cmp_mx / *_my (mapacc.asm). Never lda en_x,x (that loads the pointer word).
!zone map_bss

; Packed header bytes 0..22 — must stay contiguous (bind_map copies 23 bytes).
; $0417 is unused so room_x stays word-aligned at $0418.
map_nrooms	= $0400
map_ndoors	= $0401
map_ncrates	= $0402
map_nslopes	= $0403
map_nplats	= $0404
map_nswitches	= $0405
map_nelevs	= $0406
map_nenemies	= $0407
map_ntrigs	= $0408
map_nthings	= $0409
; unused streaming type pad (was the crusher count)
map_type0	= $040A
map_type1	= $040B
map_type2	= $040C
map_nux	= $040D
map_nuz	= $040E
map_nvert	= $040F
map_nedge	= $0410

spawn_x	= $0411
spawn_y	= $0412
spawn_z	= $0413
spawn_rot	= $0414
spawn_room	= $0415
spawn_id	= $0416
!if spawn_id - map_nrooms != 22 {
	!error "map header BSS is not 23 packed bytes"
}

; 16-bit pointers into the packed map blob
room_x	= $0418
room_y	= $041A
room_z	= $041C
room_sx	= $041E
room_sy	= $0420
room_sz	= $0422
room_bg	= $0424
slope_flags	= $0426		; was room_line
; Dead slots (room_fx / room_wpn / room_id, room_evert, room_efaces, door_id)
; were closed up; field ids are address-derived, so everything below is dense.
rc_x	= $0428
rc_y	= $042A
rc_z	= $042C
rc_sx	= $042E
rc_sy	= $0430
rc_sz	= $0432
rb_x	= $0434
rb_y	= $0436
rb_z	= $0438
rb_sx	= $043A
rb_sy	= $043C
rb_sz	= $043E
room_nv	= $0440
room_ne	= $0442
room_vo	= $0444
room_eo	= $0446
room_nx	= $0448
room_nz	= $044A
room_uo	= $044C
room_zo	= $044E
room_door_o	= $0450
room_ndoor	= $0452
room_ux	= $0454
room_uz	= $0456
room_vy	= $0458
room_xid	= $045A
room_zid	= $045C
room_col	= $045E
room_e0	= $0460
room_e1	= $0462
door_x	= $0464
door_y	= $0466
door_z	= $0468
door_sx	= $046A
door_sy	= $046C
door_sz	= $046E
door_face	= $0470
door_key	= $0472
door_type	= $0474
door_other	= $0476
door_tag	= $0478
crate_x	= $047A
crate_y	= $047C
crate_z	= $047E
crate_sx	= $0480
crate_sy	= $0482
crate_sz	= $0484
crate_room	= $0486
crate_flags	= $0488		; nonzero = stroke all 12 edges
slope_x	= $048A
slope_y	= $048C
slope_z	= $048E
slope_sx	= $0490
slope_sy	= $0492
slope_sz	= $0494
slope_axis	= $0496
slope_dir	= $0498
slope_room	= $049A
room_slope_o	= $049C
plat_x	= $049E
plat_y	= $04A0
plat_z	= $04A2
plat_sx	= $04A4
plat_sz	= $04A6
plat_room	= $04A8
plat_solid	= $04AA
room_plat_o	= $04AC
elev_x	= $04AE
elev_y0	= $04B0
elev_z	= $04B2
elev_sx	= $04B4
elev_sy	= $04B6
elev_sz	= $04B8
elev_home	= $04BA
elev_dest	= $04BC
elev_room	= $04BE
elev_id	= $04C0
sw_x	= $04C2
sw_y	= $04C4
sw_z	= $04C6
sw_sx	= $04C8
sw_sy	= $04CA
sw_sz	= $04CC
sw_kind	= $04CE
sw_tag	= $04D0
sw_room	= $04D2
sw_face	= $04D4
en_tag	= $04D6		; cooked enemy tag id; 0 = untagged. Hole was sw_id.
en_x	= $04D8
en_y	= $04DA
en_z	= $04DC
en_type	= $04DE
en_rot	= $04E0
en_room	= $04E2
elev_grp	= $04E4		; cooked tag group; 0 = none. Hole was en_patrol.
elev_flags	= $04E6		; bit0 = quarter speed. Hole was en_id.
tr_x	= $04E8
tr_y	= $04EA
tr_z	= $04EC
tr_sx	= $04EE
tr_sy	= $04F0
tr_sz	= $04F2
tr_room	= $04F4
tr_purpose	= $04F6
tr_arg	= $04F8
room_trig_o	= $04FA
th_x	= $04FC
th_y	= $04FE
th_z	= $0500
th_type	= $0502
th_room	= $0504
room_th_o	= $0506
map_name	= $0508
map_text	= $050A
!if (map_text - room_x) & 1 {
	!error "map pointer table is not aligned words"
}
!if (map_text - room_x) / 2 > 255 {
	!error "map pointer table exceeds 256 fields"
}
; MAP_BSS_END = $050C  size=268
; $050C..$0523 is a gap; play BSS still starts at $0524.
