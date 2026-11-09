-- InstanceGPS alongside QuestGPS (run with DN_BEFORE=fixtures/questgps_mock.lua): the boss tracker steps aside for
-- a card on QuestGPS's tracker; quest objectives near the route become stops the arrow leads to before the next
-- boss, with rings on the map; skipping one, finishing one and the options that turn both parts off; and the
-- arrow only inside the instance, where QuestGPS's has no position.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local MAP = 36   -- Deadmines
local inst = NS.Instances[MAP]
local route = inst.routes[1]
local p = route.path
local function vertex(i) return p[i * 3 - 2], p[i * 3 - 1], p[i * 3] end
local function place(x, y, f)
	MOCK.level = DN.FirstFloor(f) or 0
	MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, x, y)
	MOCK.Tick(0.2)
end

-- an objective just off the route between the first and second boss, a turn-in by the entrance, and one too far
-- from the route to lead to
local mid = math.floor((route.stops[1] + route.stops[2]) / 2)
local mx, my = vertex(mid)
local sx, sy = vertex(1)
QuestGPS.objectives[MAP] = {
	{ qid = 214, title = "Red Silk Bandanas", text = "Red Silk Bandana: 0/10", kind = "objective",
		points = { mx + 500, my + 500, mx + 8, my + 6 } },
	{ qid = 166, title = "The Defias Brotherhood", text = "Turn In The Defias Brotherhood", kind = "turnin",
		points = { sx + 5, sy } },
	{ qid = 373, title = "The Unsent Letter", text = "Letter: 0/1", kind = "objective", points = { sx + 900, sy + 900 } },
}

MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
place(vertex(1))
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
place(vertex(2))

-- one card on QuestGPS's tracker in place of the boss tracker
local card = QuestGPS.Card()
print("card:", #QuestGPS.cards == 1 and card ~= nil and not DN.tracker.shown and card.where:find("Boss 1 of") ~= nil
	and type(card.menu) == "function")

-- the two objectives near the route are stops, in route order; the far one isn't
local stops = DN.questStops
print("quest stops:", #stops == 2 and stops[1].kind == "turnin" and stops[2].name == "Red Silk Bandana: 0/10"
	and stops[2].x == mx + 8)

-- the turn-in by the entrance comes before the first boss: the arrow and the card lead there
print("turn-in first:", DN.wp.boss == stops[1] and card.title == "Turn In The Defias Brotherhood"
	and InstanceGPSArrow.title.text == "Turn In The Defias Brotherhood")

-- skipping it moves the arrow on to the first boss; the card's menu offers the skip while it's the target
local skip
for _, item in ipairs(card.menu()) do if item.text == "Skip This Quest Stop" then skip = item end end
skip.action()
MOCK.Tick(0.2)
local first = DN:NextBoss()
print("skipped:", DN.wp.boss == first and DN:QuestSkipped(stops[1]))

-- with the first boss down, the objective on the way to the second comes next, with a gold ring on the map
DN:MarkKilled(first)
MOCK.Tick(0.2)
local objective = DN.questStops[2]
WorldMapFrame.shown = true
MOCK.level = DN.FirstFloor(objective.f) or 0
DN:RefreshMap()
local ring
for _, r in ipairs(DN.mapStops.rings) do if r.shown and r.quest == objective then ring = r end end
print("objective next:", DN.wp.boss == objective and ring ~= nil and ring.state == "next" and ring.num.text == "!")
WorldMapFrame.shown = false

-- standing at it, the arrow says so
place(objective.x, objective.y, objective.f)
print("arrived:", DN.wp.boss == objective and DN.wp.atBoss == true)

-- finished in QuestGPS, it drops off and the arrow goes on to the second boss
QuestGPS.objectives[MAP] = { QuestGPS.objectives[MAP][2] }
QuestGPS.Fire("QGPS_STATE_CHANGED")
MOCK.Tick(0.2)
print("finished:", #DN.questStops == 1 and DN.wp.boss == DN:NextBoss() and not DN.wp.boss.quest)

-- the card refreshes QuestGPS's tracker when it changes, not on every tick
local before = QuestGPS.refreshes
MOCK.Tick(1.1)
MOCK.Tick(1.1)
print("card refreshes:", QuestGPS.refreshes - before <= 1)

-- QuestGPS hiding its tracker in dungeons, or the option off, brings InstanceGPS's own back
QuestGPS.db.tracker.inDungeon = "hide"
DN:RefreshTracker()
local hidden = DN.tracker.shown and QuestGPS.Card() == nil
QuestGPS.db.tracker.inDungeon = "show"
DN.opt.questTracker = false
DN:RefreshTracker()
print("own tracker back:", hidden and DN.tracker.shown and QuestGPS.Card() == nil)
DN.opt.questTracker = true

-- the quest stops option off leaves only the bosses
DN.opt.questStops = false
DN:UpdateQuestStops()
MOCK.Tick(0.2)
print("stops off:", #DN.questStops == 0)

-- outside, at the instance's door, InstanceGPS's arrow is gone: QuestGPS's leads there
MOCK.inInstance = false
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
MOCK.Tick(0.2)
print("outside:", DN.inst == nil and not DN.arrow.shown and QuestGPS.Card() == nil)
print("questgps test done")
