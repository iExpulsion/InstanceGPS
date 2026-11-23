-- Each character's runs live in the account file by GUID, so characters sharing a name (and the client's
-- per-character file) keep their own. The old per-character file is taken over only by the character that stamped
-- it; with the GUID unknown at load (a fresh login), the data is found at PLAYER_LOGIN and copied in place.
local DN = NS.DN
local me = "0x0000000000000001"

-- another same-named character's old file isn't taken over
InstanceGPSDB = {}
InstanceGPSCharDB = { guid = "0x00000000000000B0", runs = { [7] = { killed = {} } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("other character's file left:", tostring(DN.char.runs[7] == nil and InstanceGPSCharDB.runs[7] ~= nil
    and InstanceGPSDB.chars[me] == DN.char))

-- this character's old file is taken over, then dropped
InstanceGPSDB = {}
InstanceGPSCharDB = { guid = me, runs = { [7] = { killed = {} } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("own file adopted:", tostring(DN.char.runs[7] ~= nil and InstanceGPSCharDB == nil and DN.char.guid == nil))

-- another character's saved runs stay theirs
InstanceGPSDB = { chars = { ["0x00000000000000B0"] = { runs = { [8] = { killed = {} } } } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("same name, own runs:", tostring(DN.char.runs[8] == nil and InstanceGPSDB.chars["0x00000000000000B0"].runs[8] ~= nil))

-- with no GUID at load, the saved runs are filled in at PLAYER_LOGIN into the table already in use
MOCK.noGuid = true
InstanceGPSDB = { chars = { [me] = { runs = { [7] = { killed = {} } } } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local runs = DN.char.runs
print("unknown at load, empty:", tostring(next(runs) == nil))
MOCK.noGuid = nil
MOCK.Fire("PLAYER_LOGIN")
print("filled at login in place:", tostring(runs[7] ~= nil and DN.char.runs == runs and InstanceGPSDB.chars[me] == DN.char))
print("chardb test done")
