; Player pickups (A8 src/world.asm grant_th_type / gb_*): add-type items, guns, armour, powerup, keys,
; backpack, driven by the A8 tables generated into a8pick.inc (tools/gbc_a8const.py). ROMX bank;
; ROM0 stub ApplyPickup (combat.asm) maps it and restores the object bank.

INCLUDE "hw.inc"
INCLUDE "en.inc"

SECTION "player", ROMX

INCLUDE "a8pick.inc"                    ; GbMode, GbAdd, GbMax, GbDbl, GbBits, GbWpn (19 entries each)

; A8 gb_ptr_lo / hi: the variable each add-type thing fills (0 = none).
GbPtr:
    dw wHP, wHP, 0, 0, wAmmoBul, wAmmoShl, wAmmoRkt, wAmmoShl, wAmmoBul, 0, wAmmoRkt, 0, 0, 0, 0, wHP, 0, 0, 0

; A = TH_* type -> carry = used up (taken); NC = refused (stays on the floor).
ApplyPickupB::
    cp TH_LIGHTPOST
    jr c, .ok
    and a
    ret
.ok:
    ld [wApTy], a
    ld c, a
    ld b, 0
    ld hl, GbMode
    add hl, bc
    ld a, [hl]
    cp GB_ADD
    jr z, .add
    cp GB_GUN
    jr z, .gun
    cp GB_ARM
    jr z, .arm
    cp GB_PU
    jr z, .pu
    cp GB_KEY
    jr z, .key
    ; GB_PACK
    ld a, [wHavePack]
    and a
    jr nz, .no
    ld a, 1
    ld [wHavePack], a
    scf
    ret
.no:
    and a
    ret
.add:
    xor a
    jr GbAddAmt
.gun:
    ld hl, GbBits
    add hl, bc
    ld d, [hl]
    ld a, [wHaveWpn]
    and d
    jr z, .newGun
    ld hl, GbAdd
    add hl, bc
    ld a, [hl]
    and a
    jr z, .no                           ; owned, no ammo with it (chainsaw)
    xor a
    jr GbAddAmt
.newGun:
    ld a, [wHaveWpn]
    or d
    ld [wHaveWpn], a
    ld hl, GbAdd
    add hl, bc
    ld a, [hl]
    and a
    jr z, .sw
    ld a, 1
    call GbAddAmt
.sw:
    ld a, [wApTy]
    ld c, a
    ld b, 0
    ld hl, GbWpn
    add hl, bc
    ld a, [hl]
    call SwitchWeaponB
    scf
    ret
.arm:
    ld hl, GbMax
    add hl, bc
    ld a, [wArmor]
    cp [hl]
    jr nc, .no                          ; armour already at least this good
    ld a, [hl]
    ld [wArmor], a
    xor a
    ld [wArmorKind], a
    ld a, c
    cp TH_ARMOR_B
    jr nz, .armDone
    ld a, 1
    ld [wArmorKind], a
.armDone:
    scf
    ret
.pu:
    ld a, c
    ld [wPuKind], a
    ld a, LOW(POWERUP_MS)
    ld [wPuMs], a
    ld a, HIGH(POWERUP_MS)
    ld [wPuMs + 1], a
    scf
    ret
.key:
    ld hl, GbBits
    add hl, bc
    ld d, [hl]
    ld a, [wHaveKeys]
    and d
    jr nz, .no
    ld a, [wHaveKeys]
    or d
    ld [wHaveKeys], a
    scf
    ret

; A8 gb_add_amt: wApTy = type, A = force (1: always add + clamp). Carry = stored. The cap is
; GbMax, doubled (saturating) with the backpack for the ammo types.
GbAddAmt:
    ld [wApForce], a
    ld a, [wApTy]
    ld c, a
    ld b, 0
    ld hl, GbMax
    add hl, bc
    ld e, [hl]
    ld hl, GbDbl
    add hl, bc
    ld a, [hl]
    and a
    jr z, .cap
    ld a, [wHavePack]
    and a
    jr z, .cap
    ld a, e
    add a
    jr nc, .dbl
    ld a, 255
.dbl:
    ld e, a
.cap:
    ld a, e
    ld [wApCap], a
    ld hl, GbPtr
    add hl, bc
    add hl, bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a                             ; HL = the variable
    ld a, [wApForce]
    and a
    jr nz, .add
    ld a, [hl]
    ld d, a
    ld a, [wApCap]
    ld e, a
    ld a, d
    cp e
    jr nc, .refuse                      ; at the cap
.add:
    push hl
    ld hl, GbAdd
    add hl, bc
    ld a, [hl]
    pop hl
    add [hl]
    jr c, .clamp
    ld d, a
    ld a, [wApCap]
    ld e, a
    ld a, d
    cp e
    jr c, .store
    jr z, .store
.clamp:
    ld a, [wApCap]
.store:
    ld [hl], a
    scf
    ret
.refuse:
    and a
    ret

; A8 switch_weapon: A = weapon id (fist is always owned). Clears the weapon timers on a change.
SwitchWeaponB::
    ld c, a
    and a                               ; WPN_FIST
    jr z, .own
    ld b, a
    inc b
    ld a, $80                           ; 1 << id
.sh:
    rlca
    dec b
    jr nz, .sh
    ld b, a
    ld a, [wHaveWpn]
    and b
    ret z
.own:
    ld a, [wWpnCur]
    cp c
    ret z
    ld a, c
    ld [wWpnCur], a
    xor a
    ld [wWpnTimer], a
    ld [wWpnAnim], a
    ld [wFlashTimer], a
    ret
