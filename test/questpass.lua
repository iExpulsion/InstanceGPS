-- A quest stop the route passes more than once (run with DN_BEFORE=fixtures/questgps_mock.lua): Dire Maul West
-- passes the Shen'dralar Ancient on the way to Tendris Warpwood and again, a little nearer, on the way to
-- Immol'thar; the turn-in is offered on the first pass.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 429
local inst = NS.Instances[MAP]
local route, tendris
for _, r in ipairs(inst.routes) do
	for k, bi in ipairs(r.order) do
		if inst.bosses[bi].name == "Tendris Warpwood" then route, tendris = r, k end
	end
end
local p = route.path
local function place(x, y, f)
	MOCK.level = DN.FirstFloor(f) or 0
	MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, x, y)
	MOCK.Tick(0.2)
end

QuestGPS.objectives[MAP] = {
	{ id = "7461:0", qid = 7461, index = 0, title = "The Madness Within", text = "Turn In The Madness Within",
		kind = "turnin", points = { 12, 396 }, heights = { 0 } },
}
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
place(p[1], p[2], p[3])
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
MOCK.Tick(0.2)

-- the stop sits on the leg to Tendris Warpwood, not the later one to Immol'thar
local stop = DN.questStops[1]
local lo, hi = route.stops[tendris - 1], route.stops[tendris]
print("first pass:", stop ~= nil and stop.onRoute == route and stop.anchor > lo and stop.anchor <= hi,
	stop and stop.anchor, lo, hi)
print("questpass test done")
