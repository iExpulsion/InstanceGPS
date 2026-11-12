-- InstanceGPS with QuestGPS (an optional dependency, docs/MODULES.md "Other Addons" in QuestGPS):
-- * the quest objectives QuestGPS knows inside this instance become stops on the route (DN.questStops), led to by
--   the arrow and shown on the dungeon map;
-- * while QuestGPS's tracker is on, InstanceGPS's boss tracker steps aside for a card at the top of QuestGPS's.
-- QuestGPS has no position inside instances, so its arrow is already gone in here; InstanceGPS's takes over.
local _, ns = ...
local DN = ns.DN

-- yards: an objective's spawn this far from the route isn't put on it (a straight spur that long would cross walls)
local QUEST_REACH = 80
-- yards added to a route point's distance when it's on another map level than the spawn
local OFF_FLOOR = 25
-- yards a route's earlier pass may be further from a spawn than its nearest point and still take the stop, so a
-- route that passes a spot twice offers it the first time (Dire Maul West's Shen'dralar Ancient, on the way to
-- Tendris Warpwood and again to Immol'thar). Only a pass on the spawn's own level counts: the Court of the
-- Highborne runs right over the Treasure of the Shen'dralar.
local FIRST_PASS = 20
-- a height difference counts this many times its yards when matching a spawn to a boss's level
local HEIGHT_WEIGHT = 3
local NONE = {}
local OnFloor = DN.OnFloor

local function Q()
	return _G.QuestGPS
end

-- QuestGPS with the hooks InstanceGPS uses (older versions have none)
function DN:QuestGPS()
	local q = Q()
	return q and q.InstanceObjectives and q.TrackerFrame and q.TrackerFrame.AddCard and q or nil
end

-------------------------------------------------------------------------------- quest stops

-- An objective's key: QuestGPS's id ("qid:index"), the same while its count goes up. Before QuestGPS gave ids, the
-- quest, its kind and the text without its count ("Vault Keeper slain: 0/2" -> "Vault Keeper slain").
local function StopKey(e)
	return e.id or (e.qid .. ":" .. e.kind .. ":" .. ((e.text or ""):gsub(":%s*%d+%s*/%s*%d+%s*$", "")))
end

-- The levels two masks share, as a mask (0 for none)
local function Common(a, b)
	local m = 0
	for level = 0, 20 do
		if OnFloor(a, level) and OnFloor(b, level) then m = m + 2 ^ level end
	end
	return m
end

-- The map levels of a spawn at height z: those of the boss nearest it, heights counting extra. The route carries
-- levels but no heights; the bosses have both. nil when the height is unknown (0).
local function LevelsAt(inst, x, y, z)
	local best, bd
	for _, b in ipairs(z and z ~= 0 and inst.bosses or NONE) do
		if b.x and b.z and b.f then
			local dx, dy, dz = b.x - x, b.y - y, (b.z - z) * HEIGHT_WEIGHT
			local d = dx * dx + dy * dy + dz * dz
			if not bd or d < bd then best, bd = b.f, d end
		end
	end
	return best
end

-- The spawn nearest the route and the route vertex it's met at, a vertex on another level than the spawn counting
-- OFF_FLOOR further (overview levels left out: Sunken Temple's entrance and its lower ring share only the
-- overview, and a Murk Worm 40 yards under the entrance took the stop there): the first vertex on the nearest one's terms (the spawn's level, or not) within FIRST_PASS of
-- the nearest distance. Returns x, y, vertex, distance, the spawn's levels as a mask.
local function Nearest(inst, route, pts, heights)
	local p, nearest, nearestSame = route.path, math.huge, false
	local function Each(fn)
		for j = 1, #pts - 1, 2 do
			local x, y = pts[j], pts[j + 1]
			local levels = LevelsAt(inst, x, y, heights and heights[(j + 1) / 2])
			for i = 1, #p / 3 do
				local dx, dy = p[i * 3 - 2] - x, p[i * 3 - 1] - y
				local d = math.sqrt(dx * dx + dy * dy)
				local mask = p[i * 3]
				local same = not levels or Common(DN.OwnLevels(inst, mask), DN.OwnLevels(inst, levels)) ~= 0
				local shared = levels and Common(mask, levels) or mask
				fn(x, y, i, same and d or d + OFF_FLOOR, same and shared or levels, same)
			end
		end
	end
	Each(function(_, _, _, d, _, same)
		if d < nearest then nearest, nearestSame = d, same end
	end)
	local bx, by, bi, bd, bf
	Each(function(x, y, i, d, f, same)
		if d <= nearest + FIRST_PASS and (same or not nearestSame) and (not bi or i < bi or (i == bi and d < bd)) then
			bx, by, bi, bd, bf = x, y, i, d, f
		end
	end)
	return bx, by, bi, bd, bf
end

-- Where a spawn at (x, y, z) on instance map `mapId` is from map level `level` (QuestGPS says so in the tooltip of
-- the game's minimap icon for it): "here", "above" or "below" by the heights of the bosses on each level, "other"
-- when the player's level has none, and the spawn's level; nil when the spawn's level can't be told
function DN:LevelOf(mapId, x, y, z, level)
	local inst = ns.Instances and ns.Instances[mapId]
	local mask = inst and LevelsAt(inst, x, y, z)
	local sum, n = 0, 0
	for _, b in ipairs(mask and inst.bosses or NONE) do
		if b.z and b.f and OnFloor(b.f, level) then sum, n = sum + b.z, n + 1 end
	end
	local where = mask and ((OnFloor(mask, level) and "here") or (n == 0 and "other")
		or (z > sum / n and "above") or "below")
	return where, where and DN.FirstFloor(mask) or nil
end

-- Puts this instance's open quest objectives on the active route, in route order
function DN:UpdateQuestStops()
	local q, inst = self:QuestGPS(), self.inst
	local route = inst and self.opt and self.opt.questStops and self:ActiveRoute()
	local entries = q and route and q.InstanceObjectives(inst.mapId) or NONE
	local list = {}
	for _, e in ipairs(entries) do
		local x, y, anchor, d, levels = Nearest(inst, route, e.points or NONE, e.heights)
		if anchor and d <= QUEST_REACH then
			list[#list + 1] = {
				quest = true, key = StopKey(e), qid = e.qid, kind = e.kind, name = e.text, title = e.title,
				x = x, y = y, f = levels, anchor = anchor, onRoute = route,
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
	if q and q.AddLevelHook then
		q.AddLevelHook(function(mapId, x, y, z, level) return DN:LevelOf(mapId, x, y, z, level) end)
	end
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

-- QuestGPS draws the card when asked: once a second when the card would say something else, at once on events.
-- RefreshCards redraws just the cards (the whole tracker only when a card comes or goes); a QuestGPS without it
-- redraws the whole tracker, so the distance counts in steps of 5 yards there.
local shownKey
function DN:RefreshQuestCard(force)
	local q = self:QuestGPS()
	local tf = q and q.TrackerFrame
	local redraw = tf and (tf.RefreshCards or tf.Refresh)
	if redraw then
		local key = "none"
		if self:InQuestTracker() and self.inst and self.run then
			local w = self.wp
			local _, done = Progress(self)
			local step = tf.RefreshCards and 1 or 5
			key = ("%s|%s|%d"):format(tostring(w.boss and w.boss.name),
				tostring(self.remaining and math.floor(self.remaining / step)), done)
		end
		if force or key ~= shownKey then
			shownKey = key
			redraw()
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
