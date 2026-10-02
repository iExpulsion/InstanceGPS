-- InstanceGPS core: instance detection, run state, kill tracking, player position.
local ADDON, ns = ...
local DN = CreateFrame("Frame", "InstanceGPSCore")
ns.DN = DN
_G.InstanceGPS = DN

local floor, sqrt, huge = math.floor, math.sqrt, math.huge
local pairs, ipairs, tonumber, time, GetTime = pairs, ipairs, tonumber, time, GetTime

DN.version = GetAddOnMetadata(ADDON, "Version") or "?"
DN.MEDIA = "Interface\\AddOns\\InstanceGPS\\Media\\"
DN.callbacks = {}
DN.wp = {}   -- current waypoint: x, y, f, dist, boss, atBoss, portal

local RUN_STALE = 30 * 60        -- an instance left empty this long has been unloaded by the server: fresh run
local ALIVE_RESET_GRACE = 60     -- a "killed" boss seen alive this long after the kill means a fresh instance

local defaults = {
	arrow = true, tracker = true, mapOverlay = true, lockFrames = false,
	arrowScale = 1, trackerScale = 1, trackerAlpha = 1, announce = true,
	-- path views
	pathMinimap = true, pathHud = true, pathView = false,
	hudSize = 280, hudRange = 40, hudAlpha = 0.7, hudOffset = -30, hudHideCombat = true,
	pathViewScale = 1,
	hardModes = false,   -- hard-mode route variants (Obsidian Sanctum: Sartharion with the drakes up)
}

-------------------------------------------------------------------------------- utils

function DN:Print(msg, ...)
	if select("#", ...) > 0 then msg = msg:format(...) end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffInstanceGPS|r: " .. tostring(msg))
end

function DN:On(event, fn)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], fn)
end

function DN:Fire(event, ...)
	local list = self.callbacks[event]
	if not list then return end
	for _, fn in ipairs(list) do fn(...) end
end

-- 3.3.5 GUIDs: "0xF130" .. 6 hex digits entry .. 6 hex digits counter (F15 = vehicles).
function DN.NpcID(guid)
	if not guid then return nil end
	local t = guid:sub(3, 5)
	if t ~= "F13" and t ~= "F15" then return nil end
	return tonumber(guid:sub(7, 12), 16)
end

function DN.FormatTime(sec)
	sec = floor(sec or 0)
	if sec >= 3600 then
		return ("%d:%02d:%02d"):format(sec / 3600, (sec % 3600) / 60, sec % 60)
	end
	return ("%d:%02d"):format(sec / 60, sec % 60)
end

-------------------------------------------------------------------------------- instance data indexes

local byFile, byName, npcIndex, spellIndex, yellIndex = {}, {}, {}, {}, {}

-- Waypoints and bosses carry the map levels they show on as a bitmask (bit n = level n).
function DN.OnFloor(mask, level)
	return mask ~= nil and level ~= nil and floor(mask / 2 ^ level) % 2 == 1
end

-- Lowest level in a mask (for "go to level N" hints).
function DN.FirstFloor(mask)
	for level = 0, 20 do
		if DN.OnFloor(mask, level) then return level end
	end
end

-- The routes on offer in an instance:
--  * our faction's (ICC gunship);
--  * the ones for this difficulty, where the bosses differ (heroic-only Amanitar, Yor, ...);
--  * where an instance has a hard-mode variant (Obsidian Sanctum: Sartharion with the drakes
--    up), either the normal routes or the hard-mode ones, per the hardModes option.
-- Outside the instance (the map overlay) the normal-difficulty routes are shown.
local function FilterRoutes(inst)
	local faction = UnitFactionGroup("player")
	local hasHard = false
	for _, route in ipairs(inst.allRoutes) do
		if route.hard then hasHard = true end
	end
	local wantHard = hasHard and DN.opt and DN.opt.hardModes or false
	local bit = inst == DN.inst and DN.diffBit or 1
	local function pick(checkDiff)
		local routes = {}
		for _, route in ipairs(inst.allRoutes) do
			if (not route.faction or route.faction == faction) and (route.hard or false) == wantHard
				and (not checkDiff or not route.diffs or route.diffs % (bit * 2) >= bit) then
				table.insert(routes, route)
			end
		end
		return routes
	end
	local routes = pick(true)
	if #routes == 0 then
		-- a difficulty no route was made for (a server's custom one): the first boss set's routes
		local first
		for _, route in ipairs(pick(false)) do
			first = first or route.diffs
			if route.diffs == first then table.insert(routes, route) end
		end
	end
	inst.routes = routes
	-- the route each boss belongs to, and its position in that route
	for _, b in ipairs(inst.bosses) do b.route = nil end
	for r, route in ipairs(inst.routes) do
		route.index = r
		route.teleAt = {}
		for _, i in ipairs(route.tele or {}) do route.teleAt[i] = true end
		for k, bi in ipairs(route.order) do
			local b = inst.bosses[bi]
			b.route = b.route or r
		end
	end
end

local indexed = false
local function BuildIndexes()
	if indexed then return end
	indexed = true
	DN:ApplyOverrides(ns.Instances)   -- server modules (Override.lua), before anything is indexed
	local faction = UnitFactionGroup("player")
	for mapId, inst in pairs(ns.Instances) do
		inst.mapId = mapId
		inst.allRoutes = inst.routes
		if inst.file then byFile[inst.file:lower()] = mapId end
		byName[inst.name:lower()] = mapId
		npcIndex[mapId], spellIndex[mapId], yellIndex[mapId] = {}, {}, {}
		inst.bossById = {}
		for i, b in ipairs(inst.bosses) do
			b.index = i
			inst.bossById[b.id] = b
			if b.hx and faction == "Horde" then
				b.x, b.y, b.z, b.f = b.hx, b.hy, b.hz, b.hf
			end
			for _, npc in ipairs(b.npcs) do
				npcIndex[mapId][npc] = npcIndex[mapId][npc] or {}
				table.insert(npcIndex[mapId][npc], b)
			end
			if b.all then
				for _, group in ipairs(b.all) do
					for _, npc in ipairs(group) do
						npcIndex[mapId][npc] = npcIndex[mapId][npc] or {}
						local list, found = npcIndex[mapId][npc], false
						for _, x in ipairs(list) do if x == b then found = true end end
						if not found then table.insert(list, b) end
					end
				end
			end
			if b.spell then spellIndex[mapId][b.spell] = b end
			for _, text in ipairs(b.yells or {}) do yellIndex[mapId][text] = b end
		end
		FilterRoutes(inst)
	end
end

-- The hard-mode option changed: swap the routes everywhere, and restart the current one.
function DN:ApplyHardModes()
	if not indexed then return end
	for _, inst in pairs(ns.Instances) do FilterRoutes(inst) end
	local inst = self.inst
	if inst then
		self.routeIndex, self.routeManual, self.navTarget, self.progress = 1, false, nil, nil
		if self.run then self.run.route = nil end
		if #inst.routes > 1 and self.px then self.routeIndex = self:NearestRoute() end
		if self.run then self.run.route = self.routeIndex end
		self:Fire("ROUTE_CHANGED")
		self:Fire("RUN_CHANGED")
	end
end

-------------------------------------------------------------------------------- position

-- Converts in-game map coordinates on a floor into world x (north), y (west).
function DN:MapToWorld(inst, level, mx, my)
	local r = inst.floors[level] or inst.floors[0]
	if not r then return nil end
	-- r = minY, maxY, minX, maxX
	return r[4] - my * (r[4] - r[3]), r[2] - mx * (r[2] - r[1])
end

function DN:WorldToMap(inst, level, x, y)
	local r = inst.floors[level] or inst.floors[0]
	if not r then return nil end
	return (r[2] - y) / (r[2] - r[1]), (r[4] - x) / (r[4] - r[3])
end

-- Player world position inside the current instance: x, y, floor (nil when unknown).
function DN:UpdatePlayerPosition()
	local inst = self.inst
	if not inst then self.px = nil return end
	if WorldMapFrame and WorldMapFrame:IsShown() then
		-- don't fight the user over the displayed map; only read it when it shows our map
		local file = GetMapInfo()
		if not file or not inst.file or file:lower() ~= inst.file:lower() then return self.px ~= nil end
	else
		SetMapToCurrentZone()
	end
	local mx, my = GetPlayerMapPosition("player")
	if not mx or (mx == 0 and my == 0) then return self.px ~= nil end
	local level = GetCurrentMapDungeonLevel() or 0
	if not inst.floors[level] then level = inst.floors[0] and 0 or level end
	local x, y = self:MapToWorld(inst, level, mx, my)
	if not x then return false end
	self.px, self.py, self.pfloor = x, y, level
	return true
end

-------------------------------------------------------------------------------- run state

function DN:DiffBit()
	local _, _, diffIndex = GetInstanceInfo()
	diffIndex = diffIndex or 1
	local inst = self.inst
	local bit = 2 ^ (diffIndex - 1)
	if inst then
		-- unknown difficulties (e.g. server custom ones) fall back to the highest one that exists
		for d = diffIndex, 1, -1 do
			local b = 2 ^ (d - 1)
			for _, boss in ipairs(inst.bosses) do
				if boss.diff % (b * 2) >= b then return b end
			end
		end
	end
	return bit
end

function DN:BossAvailable(b)
	local bit = self.diffBit or 1
	return b.diff % (bit * 2) >= bit
end

function DN:NewRun(inst, why)
	local _, _, diffIndex, diffName = GetInstanceInfo()
	local run = {
		started = time(), lastSeen = time(), diff = diffIndex, diffName = diffName,
		killed = {}, dead = {}, lockId = nil,
	}
	self.char.runs[inst.mapId] = run
	if why then self:Print("New %s run started (%s).", inst.name, why) end
	return run
end

function DN:GetLock(inst)
	local _, _, diffIndex = GetInstanceInfo()
	for i = 1, GetNumSavedInstances() do
		local name, id, reset, diff, locked = GetSavedInstanceInfo(i)
		if name and name:lower() == inst.name:lower() and diff == diffIndex and locked then
			return id, reset
		end
	end
end

-- Decide whether entering `inst` continues the stored run or starts a fresh one.
-- 3.3.5 has no instance ID for dungeons without a lockout, so this goes by what we know:
-- a new Dungeon Finder group, a finished run, the instance having been empty long enough
-- to unload, a different difficulty or lockout.
function DN:EnterInstance(inst)
	local run = self.char.runs[inst.mapId]
	local _, _, diffIndex = GetInstanceInfo()
	local lockId = self:GetLock(inst)
	local char = self.char
	if run then
		if char.newGroupAt then   -- set when a Dungeon Finder group formed; consumed below
			run = self:NewRun(inst, "new Dungeon Finder group")
		elseif run.diff ~= diffIndex then
			run = self:NewRun(inst, "different difficulty")
		elseif lockId and run.lockId and lockId ~= run.lockId then
			run = self:NewRun(inst, "new lockout")
		elseif not lockId and not run.lockId and (run.lfgDone or run.cleared) and run.left then
			run = self:NewRun(inst, "previous run finished")
		elseif not lockId and not run.lockId and time() - (run.lastSeen or 0) > RUN_STALE then
			run = self:NewRun(inst, "instance was empty for over 30 minutes")
		end
	else
		run = self:NewRun(inst)
	end
	char.newGroupAt = nil
	run.left = nil
	if lockId then run.lockId = lockId end
	run.lastSeen = time()
	self.run = run
end

function DN:ResetRun(silent)
	if not self.inst then return end
	self.run = self:NewRun(self.inst, not silent and "manual reset" or nil)
	self.navTarget = nil
	self:Fire("RUN_CHANGED")
end

function DN:IsKilled(b)
	return self.run and self.run.killed[b.id] ~= nil
end

function DN:MarkKilled(b, how)
	local run = self.run
	if not run or run.killed[b.id] then return end
	run.killed[b.id] = time() - run.started
	if self.navTarget == b then self.navTarget = nil end
	if self.opt.announce and how ~= "manual" then
		self:Print("%s defeated at %s.", b.name, DN.FormatTime(run.killed[b.id]))
	end
	self:CheckCleared()
	self:Fire("BOSS_KILLED", b, how)
	self:Fire("RUN_CHANGED")
end

function DN:UnmarkKilled(b)
	if self.run and self.run.killed[b.id] then
		self.run.killed[b.id] = nil
		self:Fire("RUN_CHANGED")
	end
end

function DN:CheckCleared()
	local run, inst = self.run, self.inst
	if run.cleared then return end
	local route = self:ActiveRoute()
	if not route then return end
	for _, bi in ipairs(route.order) do
		local b = inst.bosses[bi]
		if self:BossAvailable(b) and not run.killed[b.id] then return end
	end
	run.cleared = time() - run.started
	self:Print("%s%s cleared in %s.", inst.name, route.name and (" " .. route.name) or "", DN.FormatTime(run.cleared))
end

-------------------------------------------------------------------------------- statistics

-- Lifetime kills come from the character's achievement statistics (Achievements >
-- Statistics), which the server keeps; Data.lua links each boss to its statistics per
-- difficulty. Most Classic and Burning Crusade dungeon bosses have none.

-- Kills of boss b on difficulty `diff` (every difficulty when nil); nil when untracked.
function DN:BossKills(b, diff)
	if not b.stats then return nil end
	local total, tracked = 0, false
	for d, ids in pairs(b.stats) do
		if not diff or d == diff then
			tracked = true
			for _, id in ipairs(ids) do
				total = total + (tonumber(GetStatistic(id)) or 0)   -- "--" when never done
			end
		end
	end
	if not tracked then return nil end
	return floor(total / (b.statDiv or 1))
end

-- The difficulty a statistic counts, from its name: "Heroic Icecrown 10 player"
function DN:StatLabel(b, diff)
	local id = b.stats and b.stats[diff] and b.stats[diff][1]
	local name = id and select(2, GetAchievementInfo(id))
	return name and name:match("%(([^)]*)%)%s*$") or (diff == 1 and "Normal" or ("Difficulty " .. diff))
end

-------------------------------------------------------------------------------- kill detection

local function GroupDone(dead, group)
	for _, npc in ipairs(group) do
		if dead[npc] then return true end
	end
	return false
end

function DN:OnNpcDied(npc)
	local run, inst = self.run, self.inst
	if not run or not inst then return end
	local list = npcIndex[inst.mapId][npc]
	if not list then return end
	run.dead[npc] = true
	-- several encounters may share npcs (e.g. Violet Hold prisoners): credit the first open one
	for _, b in ipairs(list) do
		if not run.killed[b.id] and self:BossAvailable(b) then
			if b.all then
				local done = true
				for _, group in ipairs(b.all) do
					if not GroupDone(run.dead, group) then done = false break end
				end
				if done then self:MarkKilled(b) return end
			else
				self:MarkKilled(b)
				return
			end
		end
	end
end

function DN:OnSpell(spellId)
	local inst = self.inst
	if not inst then return end
	local b = spellIndex[inst.mapId][spellId]
	if b and not self:IsKilled(b) then self:MarkKilled(b) end
end

-- A boss we think is dead shows up alive: the instance was reset behind our back.
-- Bosses that turn friendly on defeat are credited when seen friendly.
function DN:CheckUnit(unit)
	local inst, run = self.inst, self.run
	if not inst or not run or not UnitExists(unit) then return end
	local npc = DN.NpcID(UnitGUID(unit))
	local list = npc and npcIndex[inst.mapId][npc]
	if not list then return end
	for _, b in ipairs(list) do
		local killedAt = run.killed[b.id]
		if b.friendly and not killedAt and UnitIsFriend("player", unit) and self.bossSeenHostile and self.bossSeenHostile[b.id] then
			self:MarkKilled(b)
		elseif not UnitIsFriend("player", unit) then
			self.bossSeenHostile = self.bossSeenHostile or {}
			self.bossSeenHostile[b.id] = true
			if killedAt and not b.all and not b.noDeath and not UnitIsDead(unit)
				and time() - (run.started + killedAt) > ALIVE_RESET_GRACE and UnitHealth(unit) == UnitHealthMax(unit) then
				self:ResetRun(true)
				self:Print("%s is alive again - the instance was reset, starting a new run.", b.name)
				return
			end
		end
	end
end

-------------------------------------------------------------------------------- routes

function DN:ActiveRoute()
	local inst = self.inst
	if not inst then return nil end
	return inst.routes[self.routeIndex or 1]
end

function DN:SetRoute(index, manual)
	if not self.inst or not self.inst.routes[index] then return end
	self.routeIndex = index
	self.routeManual = manual
	if self.run then self.run.route = index end
	self.progress = nil
	self:Fire("ROUTE_CHANGED")
	self:Fire("RUN_CHANGED")
end

-- Nearest route to the player (used for wings / multiple entrances).
function DN:NearestRoute()
	local inst, px, py = self.inst, self.px, self.py
	if not inst or not px or #inst.routes < 2 then return 1 end
	local best, bestD = 1, huge
	for r, route in ipairs(inst.routes) do
		local p = route.path
		for i = 1, #p, 3 do
			local dx, dy = p[i] - px, p[i + 1] - py
			local d = dx * dx + dy * dy
			if d < bestD then best, bestD = r, d end
		end
	end
	return best, sqrt(bestD)
end

function DN:AutoRoute()
	local inst = self.inst
	if not inst or #inst.routes < 2 or self.routeManual then return end
	local best, bestD = self:NearestRoute()
	local cur = self.routeIndex or 1
	if best ~= cur then
		-- hysteresis: only switch when clearly closer to the other route
		local curRoute = inst.routes[cur]
		local p, dCur = curRoute.path, huge
		for i = 1, #p, 3 do
			local dx, dy = p[i] - self.px, p[i + 1] - self.py
			dCur = math.min(dCur, dx * dx + dy * dy)
		end
		if sqrt(dCur) > bestD + 40 then self:SetRoute(best) end
	end
end

-- The next boss to go for: the manual pick, else the first open boss in route order.
function DN:NextBoss()
	local inst, run = self.inst, self.run
	if not inst or not run then return nil end
	if self.navTarget and not self:IsKilled(self.navTarget) then return self.navTarget end
	local route = self:ActiveRoute()
	if not route then return nil end
	for k, bi in ipairs(route.order) do
		local b = inst.bosses[bi]
		if self:BossAvailable(b) and not run.killed[b.id] then return b, k end
	end
end

function DN:SetNavTarget(b)
	if self.navTarget == b then self.navTarget = nil else self.navTarget = b end
	if b and b.route and b.route ~= self.routeIndex then self:SetRoute(b.route, true) end
	self:Fire("RUN_CHANGED")
end

-------------------------------------------------------------------------------- events

-- Instances switched off (Interface > AddOns > InstanceGPS > Instances, the menu, /igps off): in
-- one, InstanceGPS acts as if you weren't in an instance at all. Account-wide.
function DN:IsOff(mapId)
	return self.db and self.db.off and self.db.off[mapId] or false
end

function DN:SetOff(mapId, off)
	self.db.off = self.db.off or {}
	self.db.off[mapId] = off and true or nil
	self:DetectInstance()
	if WorldMapFrame:IsShown() then self:RefreshMap() end
end

function DN:DetectInstance()
	local inInstance, itype = IsInInstance()
	local inst
	local wasOff = self.offHere
	self.offHere = nil
	if inInstance and (itype == "party" or itype == "raid") then
		local name = GetInstanceInfo()
		if not (WorldMapFrame and WorldMapFrame:IsShown()) then SetMapToCurrentZone() end
		local file = GetMapInfo()
		-- names first: some instances share a map file (Trial of the Crusader / Champion)
		local id = (name and byName[name:lower()]) or (file and byFile[file:lower()])
		inst = id and ns.Instances[id]
	end
	if inst and self:IsOff(inst.mapId) then
		self.offHere, inst = inst, nil
		if wasOff ~= self.offHere then
			self:Print("Off in %s. /igps on to turn it back on here.", self.offHere.name)
		end
	end
	-- a Dungeon Finder teleport can take us from one copy of a dungeon straight into a new copy
	local regroup = inst and inst == self.inst and self.char.newGroupAt
	if inst ~= self.inst or regroup then
		if self.inst and self.run then
			self.run.lastSeen = time()
			if inst ~= self.inst then self.run.left = true end
		end
		self.inst, self.run, self.navTarget, self.progress, self.px = inst, nil, nil, nil, nil
		self.bossSeenHostile, self.recentDeaths, self.remaining = nil, {}, nil
		wipe(self.wp)
		if inst then
			self:EnterInstance(inst)
			self.diffBit = self:DiffBit()
			FilterRoutes(inst)
			self.routeManual = false
			if self.run.route and not inst.routes[self.run.route] then self.run.route = nil end
			self.routeIndex = self.run.route or 1
			if not self.run.route and #inst.routes > 1 and self:UpdatePlayerPosition() then
				-- pick the route whose start is nearest to where we zoned in
				local best, bestD = 1, huge
				for r, route in ipairs(inst.routes) do
					local dx, dy = route.path[1] - self.px, route.path[2] - self.py
					local d = dx * dx + dy * dy
					if d < bestD then best, bestD = r, d end
				end
				self.routeIndex = best
				self.run.route = best
			end
		end
		self:Fire("INSTANCE_CHANGED", inst)
		self:Fire("RUN_CHANGED")
	elseif inst then
		local bit = self:DiffBit()
		if bit ~= self.diffBit then
			-- difficulty changed while inside: the routes may differ (heroic-only bosses)
			self.diffBit = bit
			self:ApplyHardModes()
		end
	end
end

local events = {}

function events:ADDON_LOADED(name)
	if name ~= ADDON then return end
	InstanceGPSDB = InstanceGPSDB or {}
	InstanceGPSCharDB = InstanceGPSCharDB or {}
	local db, char = InstanceGPSDB, InstanceGPSCharDB
	db.opt = db.opt or {}
	for k, v in pairs(defaults) do
		if db.opt[k] == nil then db.opt[k] = v end
	end
	db.stats = nil   -- lifetime kills now come from the achievement statistics
	db.pos = db.pos or {}
	-- new default frame positions: start everyone from them once
	if (db.posVersion or 1) < 3 then
		db.pos = {}
		db.posVersion = 3
	end
	-- the 3D path view became opt-in after testing
	if not db.pathViewOptIn then
		db.opt.pathView = false
		db.pathViewOptIn = true
	end
	char.runs = char.runs or {}
	DN.db, DN.char, DN.opt = db, char, db.opt
	DN:Fire("LOADED")
end

function events:PLAYER_ENTERING_WORLD()
	BuildIndexes()   -- needs the player's faction, which isn't known at ADDON_LOADED
	RequestRaidInfo()
	DN:DetectInstance()
end
events.ZONE_CHANGED_NEW_AREA = events.PLAYER_ENTERING_WORLD
events.PLAYER_DIFFICULTY_CHANGED = events.PLAYER_ENTERING_WORLD

function events:UPDATE_INSTANCE_INFO()
	if DN.inst and DN.run then
		local lockId = DN:GetLock(DN.inst)
		if lockId and not DN.run.lockId then DN.run.lockId = lockId end
	end
end

local RESET_PATTERN
function events:CHAT_MSG_SYSTEM(msg)
	RESET_PATTERN = RESET_PATTERN or "^" .. INSTANCE_RESET_SUCCESS:gsub("%%s", "(.+)") .. "$"
	local name = msg:match(RESET_PATTERN)
	if not name then return end
	local id = byName[name:lower()]
	if id and DN.char.runs[id] then
		DN.char.runs[id] = nil
		DN:Print("%s was reset; progress cleared.", name)
		DN:Fire("RUN_CHANGED")
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED(_, event, srcGUID, _, _, destGUID, _, _, spellId)
	if not DN.inst then return end
	if event == "UNIT_DIED" or event == "PARTY_KILL" then
		local npc = DN.NpcID(destGUID)
		if npc then
			DN.recentDeaths = DN.recentDeaths or {}
			if DN.recentDeaths[destGUID] then return end
			DN.recentDeaths[destGUID] = true
			DN:OnNpcDied(npc)
		end
	elseif spellId and (event == "SPELL_CAST_SUCCESS" or event == "SPELL_AURA_APPLIED" or event == "SPELL_DAMAGE"
		or event == "SPELL_ENERGIZE" or event == "SPELL_HEAL" or event == "SPELL_CAST_START") then
		DN:OnSpell(spellId)
	end
end

-- fights that end without a death the client can see (gunship, keepers, ...) end with a line
local function OnBossLine(_, msg)
	local inst = DN.inst
	local b = inst and msg and yellIndex[inst.mapId][msg]
	if b and DN.run and not DN:IsKilled(b) then DN:MarkKilled(b) end
end
events.CHAT_MSG_MONSTER_YELL = OnBossLine
events.CHAT_MSG_MONSTER_SAY = OnBossLine
events.CHAT_MSG_RAID_BOSS_EMOTE = OnBossLine

-- Dungeon Finder: a group forming means the next instance is a fresh copy; a completed
-- dungeon means this run is over.
function events:LFG_PROPOSAL_SUCCEEDED()
	DN.char.newGroupAt = time()
end

function events:LFG_COMPLETION_REWARD()
	if DN.run then DN.run.lfgDone = true end
end

-- remember when we were last inside, also across logouts
function events:PLAYER_LEAVING_WORLD()
	if DN.run then DN.run.lastSeen = time() end
end
events.PLAYER_LOGOUT = events.PLAYER_LEAVING_WORLD

function events:PLAYER_TARGET_CHANGED() DN:CheckUnit("target") end
function events:UPDATE_MOUSEOVER_UNIT() DN:CheckUnit("mouseover") end
function events:UNIT_FLAGS(unit) if unit == "target" or unit == "focus" then DN:CheckUnit(unit) end end
function events:UNIT_FACTION(unit) if unit == "target" or unit == "focus" then DN:CheckUnit(unit) end end

DN:SetScript("OnEvent", function(_, event, ...) events[event](events, ...) end)
for e in pairs(events) do DN:RegisterEvent(e) end

-- position/route ticker
local acc = 0
DN:SetScript("OnUpdate", function(self, elapsed)
	acc = acc + elapsed
	if acc < 0.1 then return end
	acc = 0
	if not self.inst then return end
	if self.run and time() - (self.run.lastSeen or 0) >= 30 then self.run.lastSeen = time() end
	if self:UpdatePlayerPosition() then
		self:AutoRoute()
		local w = self.wp
		w.x, w.y, w.f, w.dist, w.boss, w.atBoss, w.portal = self:NextWaypoint()
		self:Fire("POSITION", self.px, self.py, self.pfloor)
	end
end)
