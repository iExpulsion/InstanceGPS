-- Quest stops in an instance whose map levels can't tell places apart (run with DN_BEFORE=fixtures/questgps_mock.lua),
-- on Blackrock Spire: the Darkstone Tablet, 33 yards above the Lower route by Solakar Flamewreath, goes on the Upper
-- route only; a spawn down by the Lower route's bosses stays on it; spawns take their level from the build's level
-- points
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 229
local inst = NS.Instances[MAP]
local lower, upper
for _, r in ipairs(inst.routes) do
	if r.name == "Lower" then lower = r elseif r.name == "Upper" then upper = r end
end

-- (heights as QuestGPS's data has them; the second is a made-up spawn by Highlord Omokk)
QuestGPS.objectives[MAP] = {
	{ id = "4768:1", qid = 4768, index = 1, title = "The Darkstone Tablet", text = "Darkstone Tablet: 0/1",
		kind = "object", points = { 65, -280 }, heights = { 94 } },
	{ id = "9999:1", qid = 9999, index = 1, title = "Made Up", text = "Made Up: 0/1",
		kind = "object", points = { -20, -310 }, heights = { 32 } },
}
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local p = lower.path
MOCK.level = DN.FirstFloor(p[3]) or 0
MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, p[1], p[2])
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
MOCK.Tick(0.2)

local function stops(route)
	for i, r in ipairs(inst.routes) do
		if r == route then DN:SetRoute(i, true) end
	end
	DN:UpdateQuestStops()
	local out = {}
	for _, s in ipairs(DN.questStops) do out[s.qid] = s.onRoute == route end
	return out
end

-- on the Lower route the tablet is left out and the spawn by Omokk kept; on the Upper route the tablet is a stop
local onLower, onUpper = stops(lower), stops(upper)
print("tablet upper only:", onLower[4768] == nil and onUpper[4768] == true, onLower[4768], onUpper[4768])
print("lower spawn kept:", onLower[9999] == true, onLower[9999])
-- from the Scarshield room by the entrance (level 4) the tablet is above, on level 6
local where, level = DN:LevelOf(MAP, 65, -280, 94, 4)
print("tablet above:", where == "above" and level == 6, where, level)
-- a spawn's level comes from the build's level points, not the nearest boss: a bonfire 20 yards over Overlord
-- Wyrmthalak (level 6) is on level 7, above him
where, level = DN:LevelOf(MAP, 21.6, -506.6, 110.9, 6)
print("level point:", where == "above" and level == 7, where, level)
-- Karazhan's masks reach past the packing's offset and come back whole
local most = 0
local kara = DN.LevelPoints(NS.Instances[532])
for i = 4, #kara, 4 do most = math.max(most, kara[i]) end
print("big masks:", most > 20000 and most < 2 ^ 20, most)
print("questroute test done")
