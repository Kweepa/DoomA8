; Enemy states (wEnState).
DEF EN_IDLE   EQU 0
DEF EN_CHASE  EQU 1
DEF EN_ATTACK EQU 2
DEF EN_PAIN   EQU 3
DEF EN_DYING  EQU 4
DEF EN_ALERT  EQU 5                 ; just woke: stands for a moment (drawn as idle), then chases
DEF EN_DEAD   EQU 7

DEF PR_N      EQU 4                 ; fireball slots
DEF ITEM_FIREBALL EQU 23           ; ItemTab index of the synthetic fireball mesh
