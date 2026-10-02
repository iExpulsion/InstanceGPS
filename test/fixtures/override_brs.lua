-- A module's Overrides.lua exercising every kind of change (test/overrides.lua, ci.py)
InstanceGPS:Override("Test", {
  [409] = false,                                              -- Molten Core: not on this server
  [229] = {                                                   -- Blackrock Spire
    bosses = {
      ["Urok Doomhowl"] = false,
      ["Halycon"] = { name = "Halycon the Wolf" },
      ["Custom Boss"] = { npcs = { 990002 }, x = -59.6, y = -329.2, f = 1, after = "Gizrul the Slavener" },
      ["The Beast"] = { x = 135.0, y = -555.0 },
    },
    hints = { { x = 102.4, y = -319.2, text = "Test hint" } },
    removeHints = { "Kill every Blackhand" },
  },
})
