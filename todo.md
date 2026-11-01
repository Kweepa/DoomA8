# Todo

- [x] Chaingun shots
- [x] Grenade projectile - needs tweaking (stronger gravity, less shot upward)
- [x] Grenade FX: billboard particles (bake view-local vels; project root + scale offsets).
- [x] Ogre behaviour
- [x] Knight behaviour
- [x] Scrag behaviour (flying)
- [ ] Proper map complete screen/message (without going overboard)
- [x] Decide what to do when you die in the game
- [x] Player rocket launcher should launch a rocket projectile
- [x] When producing splat on the center of the screen, the sprite setup delays the screen flip by a raster line. Move the flip earlier so it doesn't have this problem. We can debug this by changing the border colour first thing and seeing where it is happening, so we can tweak its movement.
- [x] Fix shotgun damage vs range. It's too easy to kill someone at a distance.
- [x] Remember to save item selection and camera position for the items tab.
- [x] An arrow showing which way is forward in the items viewport.
- [x] Get rid of the static bitmap at a distance optimization. It doesn't look good and it's not optimizing for the worst case anyway.
- [x] Dropped the $093F IRQ trampoline (sqtab no longer sits on $FFFE). GAME starts at $0900 with no NOP pad.
- [ ] same for the cassette buffer, the space under the stack, some stuff in page 2, and $400-$7ff. use as BSS.
- [x] shooting in some directions doesn't hit the room walls. for example the ends of the corridors in the starting room.
- [x] the player can step up onto a ramp from any height below. fix.