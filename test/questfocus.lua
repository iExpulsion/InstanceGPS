-- A quest focused in QuestGPS but not taken yet, whose starting item drops inside (Baron Aquanis in Blackfathom
-- Deeps, by the Fathom Stone): once QuestGPS says the focus changed, its pickup is a stop on the route, led to even
-- once the bosses past it are down; unfocused, it goes.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 48   -- Blackfathom Deeps
local inst = NS.Instances[MAP]
local route = inst.routes[1]
local p = route.path
local function vertex(i) return p[i * 3 - 2], p[i * 3 - 1], p[i * 3] end
local function place(x, y, f)
	MOCK.level = DN.FirstFloor(f) or 0
	MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, x, y)
	MOCK.Tick(0.2)
end

MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
place(vertex(1))
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
place(vertex(2))
print("nothing focused:", #DN.questStops == 0)

-- QuestGPS's entry for the focus, at Baron Aquanis's spawn (QuestGPS's data, height -45)
QuestGPS.objectives[MAP] = {
	{ id = "6922:start", qid = 6922, index = "start", title = "Baron Aquanis", text = "Loot Strange Water Globe",
		kind = "pickup", points = { -776, -74 }, heights = { -45 } },
}
QuestGPS.Fire("QGPS_FOCUS_CHANGED")
local stop = DN.questStops[1]
print("focus stop:", #DN.questStops == 1 and stop.name == "Loot Strange Water Globe" and stop.kind == "pickup",
	#DN.questStops)

-- With Old Serra'kis down (past the Fathom Stone on the route), the arrow still leads back to it, from the route's
-- start, rather than on to Twilight Lord Kelris
for i = 1, 5 do DN:MarkKilled(inst.bosses[i]) end
MOCK.Tick(0.2)
local next = DN:NextTarget()
print("focus behind:", next == stop and stop.legStart == 1 and stop.anchor < route.stops[5], next and (next.name or next.text))
-- Standing by Kelris, the arrow has a waypoint on the way back to the stop
place(vertex(route.stops[6] - 1))
local wx, wy, _, wd, wboss = DN:NextWaypoint()
print("way back:", wx ~= nil and wboss == stop and wd < math.huge, wd)

QuestGPS.objectives[MAP] = {}
QuestGPS.Fire("QGPS_FOCUS_CHANGED")
print("unfocused:", #DN.questStops == 0)
print("questfocus test done")
