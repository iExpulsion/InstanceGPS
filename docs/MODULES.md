# Server modules

InstanceGPS is built from AzerothCore's data. Where your server differs (a boss it moved, a custom boss, a door that works differently, an instance it doesn't have), a **server module** carries the difference. It's a small addon of its own that players of your server install next to InstanceGPS. Nothing in it needs any tools: it's one Lua file you write by hand, or record in game.

Modules live in repos of their own. [InstanceGPS-Synastria](https://github.com/iExpulsion/InstanceGPS-Synastria) is one to copy: the addon folder, a check for the file, and a workflow that releases a zip when its version goes up.

## Making one

1. Make a folder `Interface\AddOns\InstanceGPS_<YourServer>` with two files.

   `InstanceGPS_<YourServer>.toc`:
   ```
   ## Interface: 30300
   ## Title: InstanceGPS: <Your Server>
   ## Dependencies: InstanceGPS

   Overrides.lua
   ```

   `Overrides.lua`:
   ```lua
   InstanceGPS:Override("<Your Server>", {
       -- changes, per instance (see below)
   })
   ```
2. `/reload`. The options panel title now reads "InstanceGPS 1.0.1 + <Your Server>".

Instances are keyed by their map ID: `[229]` is Blackrock Spire. The map IDs are the `[n] = {` keys in `InstanceGPS/Data.lua`, next to each instance's name.

## What you can change

```lua
InstanceGPS:Override("My Server", {
    [409] = false,                       -- an instance the server doesn't have

    [229] = {                            -- Blackrock Spire
        bosses = {
            -- a boss the server doesn't have
            ["Urok Doomhowl"] = false,

            -- change a boss: rename it, or how its kill is detected
            ["Halycon"] = { name = "Halycon the Wolf" },
            ["Warchief Rend Blackhand"] = { npcs = { 10429, 990001 } },

            -- a boss somewhere else
            ["The Beast"] = { x = 135.0, y = -555.0, f = 3 },

            -- a custom boss: the creature IDs that give the kill, where it is, and which boss it comes after
            ["Custom Boss"] = { npcs = { 990002 }, x = -59.6, y = -329.2, f = 1, after = "Gizrul the Slavener" },
        },

        -- hints the arrow shows within 15 yards of a spot
        hints = {
            { x = 102.4, y = -319.2, f = 2, text = "Pull the lever to open the gate" },
        },

        -- remove built-in hints, by how their text starts
        removeHints = { "Kill every Blackhand" },

        -- a recorded way to a boss, from the previous one (see "Recording routes")
        paths = {
            ["The Beast"] = { from = "Warchief Rend Blackhand", points = { 90.1, -440.2, 3, 92.5, -455.0, 3 } },
        },
    },
})
```

**Positions** are world `x`, `y` and the dungeon map level `f`: the level's number in the world map's level dropdown, or 0 in an instance with a single map. The easiest way to get them is `/igps record`, which writes them for you. A GM's `.gps` command shows `x` and `y` too.

**Boss fields** you can set: `name`, `npcs` (creature IDs whose death counts as the kill), `spell` (a spell whose cast counts as the kill, for fights where nobody dies), `yells` (a boss yell that counts as the kill), `noDeath`, `friendly`, `diff` (difficulties, as a bitmask: 1 = normal or 10-player, 2 = heroic or 25-player, 4 = 10-player heroic, 8 = 25-player heroic).

**Moved and custom bosses** get a rough route straight away: along InstanceGPS's route to its nearest point, then straight to the boss and back. Where that cuts through a wall, record the way (below) or have the module's routes built (further down).

## Recording routes

In game, inside the instance:

| Command | |
|---|---|
| `/igps record start` | Start recording. Each boss kill ends a leg: the way from the previous boss to that one. |
| `/igps record pause` / `resume` | Stop recording while you go off the route (to loot, vendor or regroup). |
| `/igps record mark <text>` | A hint at this spot ("Pull the lever"). Detours through a mark are kept. |
| `/igps record undo` | Drop back to the last mark, or the last 20 yards. |
| `/igps record boss <name>` | End the leg here, at a boss InstanceGPS doesn't detect (a custom one). The export adds it as a custom boss; fill in its creature IDs. |
| `/igps record drop` | Delete the last leg, to record it again. |
| `/igps record show` | Show the recorded legs on the map (in green). |
| `/igps record export` | The recording as an `InstanceGPS:Override` block: Ctrl+A, Ctrl+C, and paste it into `Overrides.lua`. |

When a leg ends it's cleaned up. Detours that come back to where they left (a dead end, running back for loot, circling in a fight) are cut, and the wobble is straightened out. A teleport or death in the middle is kept as a jump, not a walked line. Recordings are saved with your settings, so they survive `/reload` and logging out.

A recording follows the way you walked it, so walk the way you'd want others to go.

## Built routes (optional)

The game can only give rough routes to moved and custom bosses. InstanceGPS's own routes are worked out on AzerothCore's navmesh, and the same tools can do that for a module. That needs the build setup in [BUILDING.md](BUILDING.md): a 3.3.5 client, an AzerothCore checkout and its navmesh. Then, from InstanceGPS's `tools/`, pointing at your module (its repo or its addon folder):

```
python build.py --module ../../InstanceGPS-YourServer --dbc ../dbc --cache ../cache
```

It reads the same `Overrides.lua`, routes every instance whose bosses it changes, and writes `Routes.lua` next to it (and lists it in the `.toc`). `Routes.lua` notes the InstanceGPS version and the version of each instance it was built from; the module template's check warns when InstanceGPS has changed one of them since, so you know to build again. In game the overrides then apply on top of those routes. Three more keys only the build uses:

```lua
[229] = {
    order = { { "Gizrul the Slavener", "Custom Boss" } },                       -- A before B
    doors = { { x = 93.0, y = -435.6, z = 111.0, r = 6, after = { "Warchief Rend Blackhand" } } },  -- shut until they die
    links = { { x1 = 0, y1 = 0, z1 = 0, x2 = 10, y2 = 0, z2 = -5 } },          -- a drop the navmesh lacks (both = true: walkable both ways)
},
```

These need a height `z`, which `.gps` shows.

## Sharing it

- **Your own repo:** copy [InstanceGPS-Synastria](https://github.com/iExpulsion/InstanceGPS-Synastria), rename the folder and the `.toc`, and put your changes in `Overrides.lua`. Raising `## Version` and pushing releases a zip. Its check runs `tools/check.py` against InstanceGPS's latest data, so a typo in a boss name or a key is caught before players see it.
- **A module that already exists:** send it a pull request, saying where each change comes from (seen in game, a patch note).
- **Tell us:** open an issue on InstanceGPS with a link, and it goes in the list of modules in the README.

A module works with any InstanceGPS release that has `InstanceGPS:Override`. If it has built routes and a later release changes their format, InstanceGPS says so in chat and uses its own routes with the module's other changes until the module is rebuilt.
