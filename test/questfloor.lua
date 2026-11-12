-- Quest stops on a map with an overview level (run with DN_BEFORE=fixtures/questgps_mock.lua), on Sunken Temple:
-- level 1 shows the whole temple, so the entrance (levels 1 and 2) and the lower ring (1 and 3) share only it. The
-- Atal'ai Haze mobs (Zapper Fuel) live on the lower ring, some 40 yards under the entrance, and the stop must not
-- be put at the entrance.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 109
local inst = NS.Instances[MAP]
local route = inst.routes[1]
local p = route.path

-- Murk Worms, Saturated Oozes and Deep Lurkers, from AzerothCore's spawns
local points = { -306.3, 95.8, -288.9, 108.5, -286.7, 117.3, -463.1, 92.9, -469.3, 104.4, -425.7, 88.6, -440.7, 53.7,
	-372.9, 90.4, -405.9, 99.1, -373.1, 77.3, -417.4, 88.5, -434.1, 53.8 }
local heights = { -173, -173, -173, -189.7, -189.7, -176.1, -173.7, -172.9, -172.9, -148.8, -148.7, -148.7 }
QuestGPS.objectives[MAP] = {
	{ id = "4146:2", qid = 4146, index = 2, title = "Zapper Fuel", text = "Atal'ai Haze: 0/5", kind = "objective",
		points = points, heights = heights },
}
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
MOCK.level = DN.FirstFloor(DN.OwnLevels(inst, p[3])) or 0
MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, p[1], p[2])
MOCK.Tick(0.2)
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
MOCK.Tick(0.2)
local stop = DN.questStops[1]

-- level 1 is Sunken Temple's overview level, and the entrance's own level is 2
print("overview:", DN.OverviewLevels(inst) == 2, DN.OverviewLevels(inst), DN.OwnLevels(inst, p[3]))
-- the stop isn't at the entrance, but where the route reaches the haze mobs' own level
print("not at the entrance:", stop ~= nil and stop.anchor > 1
	and DN.OnFloor(DN.OwnLevels(inst, p[stop.anchor * 3]), 3), stop and stop.anchor, stop and p[stop.anchor * 3])
-- the arrow names the stop's own level, not the overview
print("own level shown:", stop ~= nil and DN.FirstFloor(DN.OwnLevels(inst, stop.f)) == 3, stop and stop.f)
print("questfloor test done")
