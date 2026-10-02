# How the routes are made

`Data.lua` is generated offline by `tools/build.py` from the 3.3.5a client files and the AzerothCore world database. The builder works in these steps:

1. **Bosses** come from `DungeonEncounter.dbc` and AzerothCore's `instance_encounters`, which say which creature's death or which credit spell ends each fight. A boss's position is its spawn point. Bosses that are summoned by a script use the summon position from the AzerothCore scripts instead.
2. **Walking paths** come from AzerothCore's navmesh (the `mmaps` the server itself uses for creature pathing). The builder finds the shortest route over the navmesh polygons and pulls it tight around corners, the same way the server does. Instance teleporters are added as shortcuts. Where the navmesh has no connection (a drop, an elevator, a door the mesh treats as closed), the builder adds a straight hop and reports it as `NAV-BRIDGED`.
3. **Teleporters are only used once they're unlocked.** The unlock rules come from AzerothCore's scripts:
   - **Icecrown Citadel:** Oratory after Marrowgar, Rampart after Deathwhisper, Deathbringer's Rise after the Gunship, Upper Spire after Saurfang, Sindragosa's Lair after Valithria, and the Frozen Throne after Putricide, Lana'thel and Sindragosa.
   - **Ulduar:** each teleporter by its boss.
   - **Naxxramas:** each wing's portal after its last boss, and the Sapphiron orb after all four wings.
4. **Difficulty-specific bosses get separate routes.** Six dungeons have a heroic-only boss: Shattered Halls, Sethekk Halls, Mana-Tombs, The Nexus, Gundrak and Ahn'kahet. Each gets a normal route and a heroic route, and the addon follows the one for your difficulty.
5. **Faction-specific fights get separate routes.** Icecrown Citadel has an Alliance route and a Horde route, because you board your own gunship (the Skybreaker or Orgrim's Hammer) from opposite ends of the Rampart of Skulls. The addon uses the route for your character's faction.
6. **Boss order** is the shortest walk from the entrance that visits every boss. Where the game requires an order, the route respects it: the final boss comes last, and prerequisites apply (Naxxramas wings before Sapphiron, the Icecrown Citadel gates, Ulduar's keepers before Vezax). Event instances follow their fixed encounter order.
7. The shortest path hugs walls and clips corners, so it is **pulled into the middle of its corridors** (`tools/centre.py`):
   - Every point is pushed away from navmesh walls closer than 8 yd. The pushes from the walls on both sides of a corridor balance out in its middle.
   - The path is smoothed against its neighbours.
   - Every moved point is checked to still be on walkable ground.
   - Wherever a straight line would do, the path is then straightened. The line has to stay on walkable ground and at least 5 yd from walls, or nearly as far as the centred path in narrow spots. That way straight corridors don't bow into arcs.

   Climbing onto ground steeper than 55°, which creatures can do but players can't, is avoided wherever there's another way.
8. The resulting path is simplified into waypoints and converted to map coordinates with `DungeonMap.dbc` / `WorldMapArea.dbc`.
9. **Map levels** are assigned the way the client does it. Each point is looked up in the instance's WMO building pieces (read from the map's WDT/ADT placements and WMO group files), and `DungeonMapChunk.dbc` maps that piece to a level. A point also shows on overview levels that contain it, such as Naxxramas' "Lower Necropolis".

**Where the map data comes from:** Blizzard's 3.3.5 files are used wherever they have a map. Classic and TBC instances have no Blizzard map on 3.3.5. For those, the data includes the maps from the WoW Dungeon Maps (WDM) client patch, which Project Reforged also bundles; they only take effect for players who have that patch installed. Without it, those instances still get kill tracking and the boss list, and the arrow explains that there's no map position. Set `DUNGEON_MAP_PATCH = False` in `tools/config.py` to leave them out.

Instances without a navmesh (only The Eye of Eternity) fall back to an approximation: a graph of creature spawns and patrol points, with hops checked against the dungeon map texture's wall outlines.

A navmesh path is correct for walking, but it knows nothing about a server's own changes to an instance. Use the map overlay to sanity-check a new instance.

To rebuild the data or change a route, see [BUILDING.md](BUILDING.md).
