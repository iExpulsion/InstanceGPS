-- Quest stops in an instance whose map levels can't tell places apart (run with DN_BEFORE=fixtures/questgps_mock.lua),
-- on Blackrock Spire: the Darkstone Tablet, 33 yards above the Lower route by Solakar Flamewreath, goes on the Upper
-- route only; a spawn down by the Lower route's bosses stays on it
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
print("questroute test done")
