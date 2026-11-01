Enemies are Possessed, Imp, Pinky, and Baron: one skeleton layout, different proportions and poses. Vertex 12 is a weapon tip parented to the right wrist.

Animation poses are authored in the editor from shareware Doom MDLs: bind mesh verts to the 13 stick joints, then **Copy selected frames**. The Animation tab previews every original MDL clip; checkboxes choose which clips to copy. Defaults keep the first pain and first death variant (extra `painb` / `deathb` clips start unchecked). In-game pain and death each pick at random among whatever matching clips were exported.

Poses are stored as variable-length frame arrays plus a per-enemy `clips` table (`name`, `start`, `len`). Animation frames are defined in local space, with signed byte offsets from the base of the creature. Overlay scale defaults to **0.7**.

With 45° baked rotation tables, budget is roughly **65 bytes per pose** (13×3 + 13×2 for gx45/gz45). Typical kept clip counts land around 54–97 poses per character (~3.5–6.3 KB).

`tools/genenemies.py` writes the Possessed, Baron, Pinky, and Imp clip sets into `src/enemy_data.asm`. Role windows (stand / alert / walk / attack / …) are looked up by clip name. Pain and death are per-type variant tables (`PAIN_MAX` slots); AI rolls among `enemy_pain_n` / `enemy_death_n` exported clips.

A room holds at most two of those four (`ROOM_MAX_TYPES`).
