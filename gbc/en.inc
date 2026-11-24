; Enemy states and A8 constants. The values are the A8's (src/mem.asm EN_*), generated into
; a8const.inc by tools/gbc_a8const.py: EN_IDLE 0, EN_ALERT 2, EN_APPROACH 3, EN_ATTACK 4,
; EN_PAIN 5, EN_DYING 6, EN_DEAD 7, EN_GONE 8.
INCLUDE "a8const.inc"

DEF PR_N      EQU 4                 ; fireball slots
DEF ITEM_FIREBALL EQU 23           ; ItemTab index of the synthetic fireball mesh
