-- The per-character file follows the character GUID: one left by another character with this name (a deleted
-- character's name reused) loses its runs at load, this character's own keeps them, and either way it's stamped.
local DN = NS.DN

InstanceGPSCharDB = { guid = "0x00000000000000B0", runs = { [7] = { killed = {} } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("other character's file reset:", tostring(DN.char.runs[7] == nil and DN.char.guid == "0x0000000000000001"))

InstanceGPSCharDB = { guid = "0x0000000000000001", runs = { [7] = { killed = {} } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("own file kept:", tostring(DN.char.runs[7] ~= nil and InstanceGPSCharDB == DN.char))
print("chardb test done")
