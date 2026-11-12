-- Quest stops the route passes more than once (run with DN_BEFORE=fixtures/questgps_mock.lua), on Dire Maul West:
-- the Shen'dralar Ancient is passed on the way to Tendris Warpwood and again, a little nearer, on the way to
-- Immol'thar, and the turn-in is offered on the first pass; the Treasure of the Shen'dralar lies under the Court of
-- the Highborne, and a pass over it on the floor above doesn't take its stop from the one on its own level.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 429
local inst = NS.Instances[MAP]
local route, legOf = nil, {}
for _, r in ipairs(inst.routes) do
	for k, bi in ipairs(r.order) do
		if inst.bosses[bi].name == "Tendris Warpwood" then route = r end
		legOf[inst.bosses[bi].name] = k
	end
end
local p = route.path
local function place(x, y, f)
	MOCK.level = DN.FirstFloor(f) or 0
	MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, x, y)
	MOCK.Tick(0.2)
end
local function onLeg(stop, boss)
	local k = legOf[boss]
	return stop ~= nil and stop.onRoute == route and stop.anchor > route.stops[k - 1] and stop.anchor <= route.stops[k]
end

-- (heights as QuestGPS's data has them)
QuestGPS.objectives[MAP] = {
	{ id = "7461:0", qid = 7461, index = 0, title = "The Madness Within", text = "Turn In The Madness Within",
		kind = "turnin", points = { 12, 396 }, heights = { 25 } },
	{ id = "7877:0", qid = 7877, index = 0, title = "The Treasure of the Shen'dralar",
		text = "Turn In The Treasure of the Shen'dralar", kind = "turnin", points = { 129, 545 }, heights = { -48 } },
}
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
place(p[1], p[2], p[3])
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
MOCK.Tick(0.2)
local ancient, treasure
for _, s in ipairs(DN.questStops) do
	if s.qid == 7461 then ancient = s elseif s.qid == 7877 then treasure = s end
end

-- the Ancient sits on the leg to Tendris Warpwood, not the later one to Immol'thar
print("first pass:", onLeg(ancient, "Tendris Warpwood"), ancient and ancient.anchor)
-- the Treasure sits on its own level, on the way to Prince Tortheldrin, not under the Court on the way to Illyanna
print("own level:", onLeg(treasure, "Prince Tortheldrin") and DN.OnFloor(p[treasure.anchor * 3], 4),
	treasure and treasure.anchor)
print("questpass test done")
