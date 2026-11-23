; Generated data: math tables (page aligned), the test scene and test poses.

INCLUDE "room_tables.inc"

SECTION "scene", ROM0
INCLUDE "scene.inc"
IF DEF(POSETEST) || DEF(MOVETEST)
INCLUDE "poses.inc"
ENDC

INCLUDE "maps.inc"
INCLUDE "worldrec.inc"
IF DEF(WORLDTEST)
INCLUDE "worldtest.inc"
ENDC
IF DEF(MAPTEST)
INCLUDE "maptest.inc"
ENDC
