# InstanceGPS

A dungeon and raid helper for WoW 3.3.5a, built on AzerothCore's data. InstanceGPS guides you through every Classic, Burning Crusade and Wrath of the Lich King dungeon and raid along the shortest route that visits every boss. It also tracks your boss kills and times your run.

Type `/igps` for the tracker and `/igps help` for every command.

## Installing

1. Download `InstanceGPS-<version>.zip` from the [latest release](../../releases/latest) and extract it into `World of Warcraft\Interface\AddOns`. You should end up with `Interface\AddOns\InstanceGPS\InstanceGPS.toc`.
2. Restart the game, or `/reload` if you're already logged in.

### Recommended: a dungeon map patch

The 3.3.5 client has no maps for Classic and Burning Crusade instances, and without a map the game doesn't tell addons where you are inside them. Install one of these to get the arrow and the path views there:

- **[WoW Dungeon Maps (WDM)](https://github.com/Trimitor/WDM-addons):** put `patch-enUS-M.MPQ` (or your language's version) in `Data\enUS`. WDM's own addon is only needed for its optional Caverns & Mines add-on.
- **[Project Reforged](https://projectreforged.github.io/wotlk/downloads/):** its optional Patch-M (Maps & Loading Screens) includes the same maps.

Without a map patch, everything works in Wrath instances. In Classic and Burning Crusade instances you still get the boss tracker, run timer and kill counts, and the arrow says it needs the map patch.

InstanceGPS doesn't need any other addons or libraries.

## What you get

- **Boss tracker.** A small window that lists the instance's bosses in route order. It shows:
  - which bosses are dead, with the run time of each kill;
  - the next boss and how far away it is;
  - a run timer and kill count (e.g. `3/7 12:41`).

  It fills in automatically from the combat log. It also handles:
  - **multi-boss fights** such as The Lost Dwarves, The Four Horsemen, Iron Council or the Blood Prince Council, which count once all members are dead;
  - **fights where the boss doesn't die**, such as Hodir, Thorim, Freya, Mimiron, Algalon, Valithria or the Gunship;
  - **Violet Hold's random prisoners**, counted as the First and Second Prisoner.
- **Navigation arrow.** It points along the route and shows the next boss and the walking distance left. Green means straight ahead, yellow and orange mean turn, and red means you've arrived. It tells you when to take a teleporter (Naxxramas portals, Icecrown Citadel and Ulduar teleporters) and when the way continues on another map level.
- **Route on the dungeon map.** Open the map inside an instance to see:
  - the leg you're on as a bright dotted line, and later legs as faint dots;
  - numbered boss pins in route order: yellow for the next boss, red for the rest, green with a check mark for kills.

  Click a pin to navigate straight to that boss.
- **Path to follow.** The route ahead, drawn three ways. Each can be turned on or off:
  - **On the minimap:** gold dots along the route, with a ring for the boss or teleporter at the end.
  - **HUD around your character:** a see-through radar in the middle of the screen, turned to the way you face, with chevrons along the path. You can set its size, range, opacity and height, and it hides in combat by default.
  - **3D path view (off by default):** a small panel showing the path ahead in perspective. Drag it to move it.

  Addons in 3.3.5 can't draw in the game world itself, so these are the closest an addon can get.
- **Event hints.** Where you have to do something for a boss to appear or a way to open, the arrow tells you what when you reach the spot. This covers about 100 events, for example:
  - objects to click: the Sunken Temple statues in order, the Gundrak altars, the Zul'Aman gong;
  - NPCs to talk to, with the gossip line to pick: Majordomo Executus, Barrett Ramsey, Arthas in The Culling of Stratholme;
  - escorts and events: Brann in Halls of Stone, Thrall in Old Hillsbrad, the Disciple of Naralex, the Zul'Farrak prisoners;
  - groups to kill to open a door: the Stratholme ziggurats, the Dire Maul pylons.
- **Hard-mode routes (off by default).** Where a hard mode changes the way through an instance, the route can follow it instead. So far that's The Obsidian Sanctum: straight to Sartharion with the three drakes left up.
- **Kill statistics.** `/igps stats` shows your lifetime kills of each boss per difficulty, read from your achievement statistics. The tracker shows the same count when you hover over a boss. Every Wrath boss has a statistic; in Classic and Burning Crusade only the raid bosses and some dungeon bosses do.
- **Progress that survives logging out and zoning.** A 5-man run starts over when the instance is reset or a new group forms. Raid and heroic kills follow your lockout. The ↻ button on the tracker starts a new run by hand, and `/igps saved` lists your lockouts with the bosses you killed.

## Using it

| Action | How |
|---|---|
| Navigate to a specific boss | Left-click it in the tracker (click again to go back to the route), or click its pin on the map |
| Fix a missed or wrong kill | Right-click the boss in the tracker |
| Switch wing or route | Click the "Route:" line in the tracker, or `/igps route library` |
| Options | Interface > AddOns > InstanceGPS (`/igps options`), or right-click the tracker title or the arrow |
| Move frames | Drag the tracker title or the arrow (`/igps lock` to lock them) |

The route follows you automatically. Dire Maul, Scarlet Monastery and Blackrock Spire have separate wings, and Stratholme and Maraudon have more than one entrance. InstanceGPS picks the route that starts where you came in and switches if you walk into another wing. Picking a route yourself turns this off; "Follow me" in the menu turns it back on.

## Commands

```
/igps               toggle the boss tracker
/igps arrow         toggle the arrow
/igps map           toggle the route on the dungeon map
/igps route [name]  switch wing/route
/igps next          mark the next boss killed (if detection missed it)
/igps reset         forget this run's kills (the instance itself isn't reset)
/igps stats [name]  lifetime kills from your achievement statistics
/igps saved         lockouts with recorded kills
/igps options       all options (Interface > AddOns > InstanceGPS)
/igps menu          quick options menu
/igps minimap       toggle the path on the minimap
/igps hud           toggle the path HUD around the character
/igps view          toggle the 3D path view
/igps lock          lock / unlock frames
/igps resetpos      reset frame positions
```

## Notes

- Routes are worked out from AzerothCore's navigation data and world database, so they fit AzerothCore-based 3.3.5 servers. A server that moves bosses or changes an instance may get some wrong routes.
- Classic and Burning Crusade dungeon maps are from [WoW Dungeon Maps](https://github.com/Trimitor/WDM-addons).

## Building from source

The routes, hints and boss data in `InstanceGPS/Data.lua` are generated from the 3.3.5a client files and AzerothCore's navmesh and world database. See [docs/BUILDING.md](docs/BUILDING.md) to rebuild them or fix a route, and [docs/ROUTES.md](docs/ROUTES.md) for how routes are worked out.

Found a route that doesn't work? Open an issue with the instance, the bosses involved and a screenshot of the map.

## License

GPL-2.0, like AzerothCore, whose data the routes and hints are built from. See [LICENSE](LICENSE).

Made by Expulsion.
