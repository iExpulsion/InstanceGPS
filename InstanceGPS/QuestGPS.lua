-- InstanceGPS with QuestGPS (an optional dependency, docs/MODULES.md "Other Addons" in QuestGPS):
-- * the quest objectives QuestGPS knows inside this instance become stops on the route (DN.questStops), led to by
--   the arrow and shown on the dungeon map;
-- * while QuestGPS's tracker is on, InstanceGPS's boss tracker steps aside for a card at the top of QuestGPS's.
-- QuestGPS has no position inside instances, so its arrow is already gone in here; InstanceGPS's takes over.
local _, ns = ...
local DN = ns.DN

-- yards: an objective's spawn this far from the route isn't put on it (a straight spur that long would cross walls)
local QUEST_REACH = 80
local NONE = {}

local function Q()
	return _G.QuestGPS
end

-- QuestGPS with the hooks InstanceGPS uses (older versions have none)
function DN:QuestGPS()
	local q = Q()
	return q and q.InstanceObjectives and q.TrackerFrame and q.TrackerFrame.AddCard and q or nil
end

-------------------------------------------------------------------------------- quest stops

-- The same objective keeps its key as its count goes up ("Vault Keeper slain: 0/2" -> "1/2")
local function StopKey(e)
	return e.qid .. ":" .. e.kind .. ":" .. ((e.text or ""):gsub(":%s*%d+%s*/%s*%d+%s*$", ""))
end

-- The spawn nearest the route, and the route vertex it's nearest: x, y, vertex, distance
local function Nearest(route, pts)
	local p, bx, by, bi, bd = route.path, nil, nil, nil, math.huge
	for j = 1, #pts - 1, 2 do
		local x, y = pts[j], pts[j + 1]
		for i = 1, #p / 3 do
			local dx, dy = p[i * 3 - 2] - x, p[i * 3 - 1] - y
			local d = dx * dx + dy * dy
			if d < bd then bx, by, bi, bd = x, y, i, d end
		end
	end
	return bx, by, bi, math.sqrt(bd)
end

-- Puts this instance's open quest objectives on the active route, in route order
function DN:UpdateQuestStops()
	local q, inst = self:QuestGPS(), self.inst
	local route = inst and self.opt and self.opt.questStops and self:ActiveRoute()
	local entries = q and route and q.InstanceObjectives(inst.mapId) or NONE
	local list = {}
	for _, e in ipairs(entries) do
		local x, y, anchor, d = Nearest(route, e.points or NONE)
		if anchor and d <= QUEST_REACH then
			list[#list + 1] = {
				quest = true, key = StopKey(e), qid = e.qid, kind = e.kind, name = e.text, title = e.title,
				x = x, y = y, f = route.path[anchor * 3], anchor = anchor, onRoute = route,
			}
		end
	end
	table.sort(list, function(a, b) return a.anchor < b.anchor end)
	self.questStops = list
	self:Fire("QUESTS_CHANGED")
end

-- Skipping a quest stop (map ring, menu) sends the arrow on; a second skip brings it back. Forgotten on a new run.
function DN:SkipQuest(stop)
	self.questSkips = self.questSkips or {}
	self.questSkips[stop.key] = not self.questSkips[stop.key] or nil
	self:Fire("QUESTS_CHANGED")
end

local function Changed()
	DN:UpdateQuestStops()
end
DN:On("INSTANCE_CHANGED", Changed)
DN:On("ROUTE_CHANGED", Changed)
DN:On("LOADED", function()
	local q = DN:QuestGPS()
	if q and q.On then q.On("QGPS_STATE_CHANGED", Changed) end
end)
DN:On("QUESTS_CHANGED", function()
	if WorldMapFrame:IsShown() then DN:RefreshMap() end
end)

-------------------------------------------------------------------------------- QuestGPS's tracker

-- Whether QuestGPS's tracker shows in here and InstanceGPS's card is on it instead of the boss tracker. QuestGPS
-- can fold or hide its tracker in dungeons; then InstanceGPS's own stays.
function DN:InQuestTracker()
	local q = self:QuestGPS()
	local s = q and q.db and q.db.tracker
	return (s and s.enabled and self.opt.questTracker and s.inDungeon ~= "hide" and s.inDungeon ~= "minimize")
		and true or false
end

-- The bosses on the active route: how many there are, how many are down, and the ones after `from` still open
local function Progress(self, from)
	local inst, run, route = self.inst, self.run, self:ActiveRoute()
	local total, done, after, seen = 0, 0, {}, from == nil
	for _, bi in ipairs(route and route.order or NONE) do
		local b = inst.bosses[bi]
		if self:BossAvailable(b) then
			total = total + 1
			if run.killed[b.id] then done = done + 1 end
			if seen and b ~= from and not run.killed[b.id] then after[#after + 1] = b.name end
			seen = seen or b == from
		end
	end
	return total, done, after
end

local function CardMenu()
	local inst, target = DN.inst, DN.wp.boss
	local items = {}
	if target and target.quest then
		items[#items + 1] = { text = "Skip This Quest Stop", action = function() DN:SkipQuest(target) end }
	end
	if inst and #inst.routes > 1 then
		for i, r in ipairs(inst.routes) do
			items[#items + 1] = { text = "Route: " .. (r.name or ("Route " .. i)), disabled = DN.routeIndex == i,
				action = function() DN:SetRoute(i, true) end }
		end
		items[#items + 1] = { text = "Follow Me (Automatic)", disabled = not DN.routeManual,
			action = function() DN.routeManual = false end }
	end
	if inst then
		local off = DN:IsOff(inst.mapId)
		items[#items + 1] = { text = off and "Turn On Navigation Here" or "Turn Off Navigation Here",
			action = function() DN:SetOff(inst.mapId, not off) end }
	end
	items[#items + 1] = { text = "Show InstanceGPS's Tracker", action = function()
		DN.opt.questTracker = false
		DN:ApplyOptions()
		DN:RefreshQuestCard()
	end }
	items[#items + 1] = { text = "InstanceGPS Options", action = function() DN:OpenOptions() end }
	if inst then
		items[#items + 1] = { text = "Reset Progress for This Run", danger = true,
			action = function() StaticPopup_Show("INSTANCEGPS_RESET") end }
	end
	return items
end

-- The card: where the arrow leads (a boss or a quest stop) and how far, the run's progress, and what comes after
function DN:QuestCard()
	local inst, run, w = self.inst, self.run, self.wp
	local card
	if inst and run and self:InQuestTracker() then
		local boss = self:NextBoss()
		local target = w.boss or self:NextTarget() or boss
		local total, done, after = Progress(self, boss)
		local later = {}
		if target and target.quest and boss then later[1] = boss.name end
		for i = 1, 2 - #later do later[#later + 1] = after[i] end
		card = {
			title = target and target.name or inst.name,
			right = w.x and self.remaining and ("%d yd"):format(self.remaining) or "",
			where = boss and ("%s, Boss %d of %d"):format(inst.name, done + 1, total) or
				("%s, All Bosses Down"):format(inst.name),
			later = #later > 0 and ("Then " .. table.concat(later, ", ")) or "",
			menu = CardMenu,
		}
	end
	return card
end

-- QuestGPS draws the card when its tracker refreshes: ask for one when the card would say something else. The
-- distance counts in steps of 5 yards, so walking doesn't redraw the tracker every frame.
local shownKey
function DN:RefreshQuestCard(force)
	local q = self:QuestGPS()
	if q and q.TrackerFrame.Refresh then
		local key = "none"
		if self:InQuestTracker() and self.inst and self.run then
			local w = self.wp
			local _, done = Progress(self)
			key = ("%s|%s|%d"):format(tostring(w.boss and w.boss.name),
				tostring(self.remaining and math.floor(self.remaining / 5)), done)
		end
		if force or key ~= shownKey then
			shownKey = key
			q.TrackerFrame.Refresh()
		end
	end
end

do
	local q = DN:QuestGPS()
	if q then q.TrackerFrame.AddCard(function() return DN:QuestCard() end) end
end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if since >= 1 then
		since = 0
		if DN.inst then DN:RefreshQuestCard() end
	end
end)
local function Force() DN:RefreshQuestCard(true) end
DN:On("RUN_CHANGED", Force)
DN:On("INSTANCE_CHANGED", Force)
DN:On("ROUTE_CHANGED", Force)
DN:On("QUESTS_CHANGED", Force)
