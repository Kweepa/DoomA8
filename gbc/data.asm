; Generated data: math tables (page aligned), the test scene and test poses.

INCLUDE "room_tables.inc"

SECTION "scene", ROM0
INCLUDE "scene.inc"
IF DEF(POSETEST) || DEF(MOVETEST)
INCLUDE "poses.inc"
ENDC

INCLUDE "maps.inc"
INCLUDE "ents.inc"
INCLUDE "wpn.inc"
INCLUDE "aitab.inc"
IF DEF(SMOKE)
INCLUDE "smoke.inc"
ENDC
IF DEF(PICKUNIT)
INCLUDE "pickunit.inc"
ENDC
IF DEF(COMBUNIT)
INCLUDE "combunit.inc"
ENDC
INCLUDE "objects.inc"
IF DEF(ENTTEST)
INCLUDE "enttest.inc"
ENDC
INCLUDE "worldrec.inc"
IF DEF(WORLDTEST)
INCLUDE "worldtest.inc"
ENDC
IF DEF(MAPTEST)
INCLUDE "maptest.inc"
ENDC
