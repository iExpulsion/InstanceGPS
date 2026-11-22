-- Garbage made by the timed ticks while the player stands still on a route (run with
-- DN_BEFORE=fixtures/questgps_mock.lua, so QuestGPS's card ticks too): the core's position and waypoint tick, the
-- boss tracker's once-a-second refresh, and every frame's ticks together. Each is held to a budget of the garbage
-- it made when this test was written; the target is none, so a budget only goes down.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
DN.opt.pathMinimap, DN.opt.pathHud, DN.opt.pathView = true, true, true
local inst = NS.Instances[36]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local p = inst.routes[1].path
MOCK.level = DN.FirstFloor(p[3]) or 0
MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, (p[1] + p[4]) / 2, (p[2] + p[5]) / 2)
MOCK.Fire("ZONE_CHANGED_NEW_AREA"); MOCK.Tick(0.2)
DN:UpdatePathViews()

-- KB a minute made by `fn`, called `perSecond` times for each of `seconds` seconds
local function PerMinute(fn, perSecond, seconds)
	for _ = 1, perSecond * 5 do fn() end
	MOCK.lean = true
	collectgarbage("collect")
	collectgarbage("stop")
	for _ = 1, perSecond do fn() end
	local before = collectgarbage("count")
	for _ = 1, perSecond * seconds do fn() end
	local made = collectgarbage("count") - before
	collectgarbage("restart")
	return made * 60 / seconds
end

-- (budget KB a minute: what each made when this test was written)
-- (first written at core 267.2, tracker 20.3, all 282.8, before Nav's Locate reused its segment list and scorer and
-- the tracker redrew only what changed; the run timer's text is the one string a second the tracker may write)
local BUDGET = { core = 0, tracker = 0, timer = 21, all = 5 }

local core = PerMinute(function()
	MOCK.now = MOCK.now + 0.1
	DN.scripts.OnUpdate(DN, 0.1)
end, 10, 60)
-- the boss tracker as it's seen: shown, with QuestGPS's tracker not taking its place (a hidden frame gets no ticks
-- in the game). Its run timer changes every second, and writing it is the one string it may make.
QuestGPS.trackerInDungeon = false
DN:RefreshTracker()
local timer = PerMinute(function()
	MOCK.now = MOCK.now + 1
	InstanceGPSTracker.scripts.OnUpdate(InstanceGPSTracker, 1)
end, 1, 120)
-- ...and with the clock held, what's left is the rows: nothing to redraw standing still
local tracker = PerMinute(function()
	InstanceGPSTracker.scripts.OnUpdate(InstanceGPSTracker, 1)
end, 1, 120)
QuestGPS.trackerInDungeon = true
DN:RefreshTracker()
local all = PerMinute(function()
	MOCK.now = MOCK.now + 0.05
	MOCK.Tick(0.05)
end, 20, 60)

print(("core tick: %.1f KB/min, boss tracker: %.1f KB/min, its timer: %.1f KB/min, all ticks: %.1f KB/min")
	:format(core, tracker, timer, all))
print("core tick within budget:", core <= BUDGET.core + 1)
print("boss tracker within budget:", tracker <= BUDGET.tracker + 1 and timer <= BUDGET.timer + 1)
print("all ticks within budget:", all <= BUDGET.all + 1)
print("garbage ticks test done")
