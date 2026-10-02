local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local inst = NS.Instances[389]
local function enter() MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file; MOCK.Fire("PLAYER_ENTERING_WORLD") end
local function leave() MOCK.inInstance = false; MOCK.Fire("PLAYER_LEAVING_WORLD"); MOCK.Fire("PLAYER_ENTERING_WORLD") end
local function kills() local n = 0; for _ in pairs(DN.run.killed) do n = n + 1 end return n end
local function kill() DN:MarkKilled(inst.bosses[1], "manual") end
local function check(label, want) local k = kills(); print((k == want and "ok  " or "FAIL") .. "  " .. label .. ": kills=" .. k) end

enter(); kill()
leave(); MOCK.now = MOCK.now + 300; enter();                      check("re-enter after 5 min keeps the run", 1)
leave(); MOCK.Fire("LFG_PROPOSAL_SUCCEEDED"); MOCK.now = MOCK.now + 60; enter(); check("new Dungeon Finder group starts fresh", 0)
kill(); MOCK.Fire("LFG_PROPOSAL_SUCCEEDED"); MOCK.now = MOCK.now + 30
MOCK.Fire("PLAYER_LEAVING_WORLD"); MOCK.Fire("PLAYER_ENTERING_WORLD");  check("ported straight into a new copy", 0)
kill(); MOCK.Fire("PLAYER_LOGOUT"); MOCK.now = MOCK.now + 10 * 60; MOCK.Fire("PLAYER_ENTERING_WORLD"); check("log back in after 10 min keeps it", 1)
-- simulate a fresh UI session: logout, 40 minutes, login inside
MOCK.Fire("PLAYER_LOGOUT"); MOCK.now = MOCK.now + 40 * 60
DN.inst = nil; MOCK.Fire("PLAYER_ENTERING_WORLD");                 check("log back in after 40 min starts fresh", 0)
for _, b in ipairs(inst.bosses) do DN:MarkKilled(b, "manual") end
leave(); MOCK.now = MOCK.now + 120; enter();                       check("re-enter a cleared dungeon starts fresh", 0)
kill(); MOCK.Fire("LFG_COMPLETION_REWARD"); leave(); MOCK.now = MOCK.now + 60; enter(); check("re-enter after Dungeon Finder completion starts fresh", 0)
