-- InstanceGPS with QuestGPS (an optional dependency, through QuestGPS.API: docs/MODULES.md "Other Addons" in
-- QuestGPS):
-- * the quest objectives QuestGPS knows inside this instance become stops on the route (DN.questStops), led to by
--   the arrow and shown on the dungeon map;
-- * while QuestGPS's tracker is on, InstanceGPS's boss tracker steps aside for a card at the top of QuestGPS's;
-- * while InstanceGPS's arrow leads, QuestGPS's steps aside (SetInstanceGuide).
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
-- yards: a level point further than this (heights counting extra) says nothing of a spawn's level
local LEVEL_REACH = 25
local NONE = {}
local OnFloor = DN.OnFloor

-- QuestGPS's API, looked up at use time; nil without QuestGPS, or with one older than it
function DN:QuestGPS()
	local q = _G.QuestGPS
	local api = type(q) == "table" and q.API
	return api and (api.version or 0) >= 1 and api or nil
end

-------------------------------------------------------------------------------- quest stops

-- An objective's key: QuestGPS's id ("qid:index"), the same while its count goes up
local function StopKey(e)
	return e.id
end

-- The levels two masks share, as a mask (0 for none)
local function Common(a, b)
	local m, bit = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then m = m + bit end
		a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
	end
	return m
end

-- Each route vertex's levels without the overview levels, worked out once per route
local function OwnMasks(inst, route)
	if not route.ownMasks then
		local p, own = route.path, {}
		for i = 1, #p / 3 do own[i] = DN.OwnLevels(inst, p[i * 3]) end
		route.ownMasks = own
	end
	return route.ownMasks
end

-- The map levels of a spawn at height z: those of the build's level point nearest it (every creature and object
-- spawn, LEVEL_REACH at most), else of the boss nearest it, heights counting extra. nil when the height is unknown (0).
local function LevelsAt(inst, x, y, z)
	local known = z and z ~= 0
	local pts = known and DN.LevelPoints(inst) or NONE
	local best, bd = nil, LEVEL_REACH * LEVEL_REACH
	for i = 1, #pts - 3, 4 do
		local dx, dy, dz = pts[i] - x, pts[i + 1] - y, (pts[i + 2] - z) * HEIGHT_WEIGHT
		local d = dx * dx + dy * dy + dz * dz
		if d < bd then best, bd = pts[i + 3], d end
	end
	local bossD
	for _, b in ipairs(known and not best and inst.bosses or NONE) do
		if b.x and b.z and b.f then
			local dx, dy, dz = b.x - x, b.y - y, (b.z - z) * HEIGHT_WEIGHT
			local d = dx * dx + dy * dy + dz * dz
			if not bossD or d < bossD then best, bossD = b.f, d end
		end
	end
	return best
end

-- Whether a spawn at height z belongs to another route: the boss nearest it, heights counting extra, is on another
-- route and not this one (Lower Blackrock Spire's route runs right under the Darkstone Tablet, beside Solakar
-- Flamewreath 33 yards up)
local function OtherRoute(inst, route, x, y, z)
	local best, bd, bi
	for i, b in ipairs(z and z ~= 0 and inst.bosses or NONE) do
		if b.x and b.z and b.f then
			local dx, dy, dz = b.x - x, b.y - y, (b.z - z) * HEIGHT_WEIGHT
			local d = dx * dx + dy * dy + dz * dz
			if not bd or d < bd then best, bd, bi = b, d, i end
		end
	end
	local function Holds(r)
		for _, k in ipairs(r.order or NONE) do
			if k == bi then return true end
		end
		return false
	end
	local elsewhere = false
	for _, r in ipairs(best and not Holds(route) and inst.routes or NONE) do
		elsewhere = elsewhere or (r ~= route and Holds(r))
	end
	return elsewhere
end

-- The spawn nearest the route and the route vertex it's met at, a vertex on another level than the spawn counting
-- OFF_FLOOR further (overview levels left out: Sunken Temple's entrance and its lower ring share only the
-- overview, and a Murk Worm 40 yards under the entrance took the stop there): the first vertex on the nearest one's terms (the spawn's level, or not) within FIRST_PASS of
-- the nearest distance. Returns x, y, vertex, distance, the spawn's levels as a mask.
local function Nearest(inst, route, pts, heights)
	local p, nearest, nearestSame = route.path, math.huge, false
	local own = OwnMasks(inst, route)
	local function Each(fn)
		for j = 1, #pts - 1, 2 do
			local x, y = pts[j], pts[j + 1]
			local z = heights and heights[(j + 1) / 2]
			local levels = LevelsAt(inst, x, y, z)
			local ownLevels = levels and DN.OwnLevels(inst, levels)
			for i = 1, OtherRoute(inst, route, x, y, z) and 0 or #p / 3 do
				local dx, dy = p[i * 3 - 2] - x, p[i * 3 - 1] - y
				local d = math.sqrt(dx * dx + dy * dy)
				local mask = p[i * 3]
				local same = not levels or Common(own[i], ownLevels) ~= 0
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

-- Where each objective meets each route, by route and then by objective and spawn count: a kill or a loot changes
-- an objective's count, not its spawns, so its stop needn't be worked out again (that took a moment per kill)
local placed = setmetatable({}, { __mode = "k" })

local function Place(inst, route, e)
	local byRoute = placed[route]
	if not byRoute then
		byRoute = {}
		placed[route] = byRoute
	end
	local pts = e.points or NONE
	local key = StopKey(e) .. ":" .. #pts
	local spot = byRoute[key]
	if not spot then
		local x, y, anchor, d, levels = Nearest(inst, route, pts, e.heights)
		spot = { x, y, anchor, d, levels }
		byRoute[key] = spot
	end
	return spot[1], spot[2], spot[3], spot[4], spot[5]
end

-- Puts this instance's open quest objectives on the active route, in route order
function DN:UpdateQuestStops()
	local q, inst = self:QuestGPS(), self.inst
	local route = inst and self.opt and self.opt.questStops and self:ActiveRoute()
	local entries = q and route and q.InstanceObjectives(inst.mapId) or NONE
	local list = {}
	for _, e in ipairs(entries) do
		local x, y, anchor, d, levels = Place(inst, route, e)
		if anchor and d <= QUEST_REACH then
			list[#list + 1] = {
				quest = true, key = StopKey(e), qid = e.qid, kind = e.kind, name = e.text, title = e.title,
				x = x, y = y, f = levels, anchor = anchor, onRoute = route,
				-- what QuestGPS says to use there ("Use Filled Cerulean Vial on a Vylestem Vine"), and the item
				note = e.note, item = e.item,
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
-- Whether InstanceGPS's arrow leads now, for QuestGPS's to step aside
function DN:Guiding()
	return self.inst ~= nil and self.arrow ~= nil and self.arrow:IsShown() and true or false
end

DN:On("LOADED", function()
	local q = DN:QuestGPS()
	if q then
		-- the log, the focus (a quest not taken yet can start in here) or where to go changing
		q.OnInstanceObjectivesChanged(Changed)
		q.AddLevelHook(function(mapId, x, y, z, level) return DN:LevelOf(mapId, x, y, z, level) end)
		q.SetInstanceGuide(function() return DN:Guiding() end)
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
	return (q and self.opt.questTracker and q.TrackerInDungeon()) and true or false
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

-- How many bosses on the active route are down (Progress's count, with no list made)
function DN:BossesDown()
	local inst, run, route = self.inst, self.run, self:ActiveRoute()
	local done = 0
	for _, bi in ipairs(inst and run and route and route.order or NONE) do
		local b = inst.bosses[bi]
		done = done + ((self:BossAvailable(b) and run.killed[b.id]) and 1 or 0)
	end
	return done
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

-- QuestGPS draws the card when asked: once a second when the card would say something else (the next target, the
-- yards left, the bosses down), at once on events. RefreshCards redraws just the cards.
local shownTarget, shownYards, shownDone, shownOn
function DN:RefreshQuestCard(force)
	local q = self:QuestGPS()
	if q then
		local on = self:InQuestTracker() and self.inst ~= nil and self.run ~= nil
		local w = self.wp
		local target = on and w.boss or nil
		local yards = on and self.remaining and math.floor(self.remaining) or nil
		local done = on and self:BossesDown() or nil
		if force or on ~= shownOn or target ~= shownTarget or yards ~= shownYards or done ~= shownDone then
			shownOn, shownTarget, shownYards, shownDone = on, target, yards, done
			q.RefreshCards()
		end
	end
end

do
	local q = DN:QuestGPS()
	if q then q.AddCard(function() return DN:QuestCard() end) end
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
