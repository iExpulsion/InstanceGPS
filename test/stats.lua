local DN = NS.DN
MOCK.now = 1000000
InstanceGPSDB = { stats = { [36] = { kills = { [1] = 3 } } } }
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("old local stats removed:", InstanceGPSDB.stats == nil)
MOCK.achName[4639] = "Lord Marrowgar kills (Icecrown 10 player)"
MOCK.achName[4640] = "Lord Marrowgar kills (Heroic Icecrown 10 player)"
MOCK.achName[4653] = "The Lich King kills (Icecrown 10 player)"
MOCK.stat[4639], MOCK.stat[4640], MOCK.stat[4653] = 5, 2, 1
-- Grand Champions: 2 runs x 3 champions on normal
MOCK.stat[4018], MOCK.stat[4048], MOCK.stat[4050], MOCK.stat[4052], MOCK.stat[4054] = 2, 1, 1, 1, 1
local icc, toc5 = NS.Instances[631], NS.Instances[650]
local mg = icc.bosses[1]
print("Marrowgar 10N:", DN:BossKills(mg, 1), "all:", DN:BossKills(mg), "25N:", DN:BossKills(mg, 2), "label:", DN:StatLabel(mg, 3))
for _, b in ipairs(toc5.bosses) do if b.name == "Grand Champions" then print("Grand Champions runs:", DN:BossKills(b, 1)) end end
print("untracked boss:", DN:BossKills(NS.Instances[389].bosses[1]))
SlashCmdList.INSTANCEGPS("stats")
SlashCmdList.INSTANCEGPS("stats icecrown")
SlashCmdList.INSTANCEGPS("stats deadmines")
SlashCmdList.INSTANCEGPS("stats ragefire")
-- run clear message no longer uses local stats
local inst = NS.Instances[389]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
for _, b in ipairs(inst.bosses) do DN:MarkKilled(b) end
-- tracker tooltip
GameTooltip.AddLine = function(_, t) print("[tip] " .. t) end
MOCK.mx = nil
for _, f in ipairs(MOCK.all) do if f.boss and f.scripts.OnEnter then f.scripts.OnEnter(f) end end
print("stats test done")
