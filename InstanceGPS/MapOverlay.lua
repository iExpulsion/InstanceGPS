-- InstanceGPS map overlay: route and boss rings on the dungeon map (RouteUtils' map path and stops).
local _, ns = ...
local DN, R = ns.DN, ns.Route

local overlay = CreateFrame("Frame", "InstanceGPSMapOverlay", WorldMapButton)

-- a quest stop's ring (QuestGPS.lua): the quest, the objective, and a click to skip it or bring it back
local function QuestOnEnter(self)
	local q = self.quest
	WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT")
	WorldMapTooltip:AddLine(q.title)
	WorldMapTooltip:AddLine(q.name, 1, 1, 1)
	if DN:QuestSkipped(q) then WorldMapTooltip:AddLine("Skipped", 0.6, 0.6, 0.6) end
	DN.HintLines(WorldMapTooltip, DN:QuestSkipped(q) and "Click: Put Back on the Route" or "Click: Skip This Stop")
	WorldMapTooltip:Show()
end

local function BossOnEnter(self)
	local b = self.boss
	WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT")
	WorldMapTooltip:AddLine((self.order > 0 and (self.order .. ". ") or "") .. b.name)
	if self.killedAt then
		WorldMapTooltip:AddLine(("Killed (%s into the run)"):format(DN.FormatTime(self.killedAt)), 0.3, 1, 0.3)
	elseif self.isNext then
		WorldMapTooltip:AddLine("Next on the Route", 1, 0.82, 0)
	end
	DN.HintLines(WorldMapTooltip, "Click: Navigate Here")
	WorldMapTooltip:Show()
end

local function RingOnEnter(self)
	if self.quest then QuestOnEnter(self) else BossOnEnter(self) end
end

local function RingOnClick(self, button)
	if button == "LeftButton" and self.quest then
		DN:SkipQuest(self.quest)
	elseif button == "LeftButton" and DN.inst and DN.inst.bosses[self.boss.index] == self.boss then
		DN:SetNavTarget(self.boss)
	end
end

local mapPath = R.NewMapPath(WorldMapButton)
local mapStops = R.NewMapStops(WorldMapButton, {
	onEnter = RingOnEnter,
	onLeave = function() WorldMapTooltip:Hide() end,
	onClick = RingOnClick,
})
DN.mapPath, DN.mapStops = mapPath, mapStops
local function LayerDot(x, y) return mapPath:Dot(x, y) end

-- One unbroken stretch of the route on this level, as 0..1 map points, and how many of its coordinates are the
-- leg being walked
local piece, nPiece, nActive = {}, 0, 0

local function DrawMap(self, inst, level, navOff, current, route, killed)
	local W, H = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
	-- the ring in the "next" look is where the arrow leads: the next boss, or a quest stop before it
	local nextBoss = current and self:NextTarget()

	local function toMap(x, y)
		local mx, my = self:WorldToMap(inst, level, x, y)
		return mx * W, my * H
	end

	-- The leg being walked (last boss -> next boss) is bright; later legs are faint and
	-- finished ones hidden, so a route that doubles back reads clearly.
	local legFrom, legTo = 1, 0
	local leg = current and self.leg
	if leg and leg.route == route then
		legFrom, legTo = leg.from, leg.to
	else
		for k, bi in ipairs(route.order) do
			if not killed[inst.bosses[bi].id] then
				legFrom, legTo = k > 1 and route.stops[k - 1] or 1, route.stops[k]
				break
			end
		end
	end

	-- a segment changing levels (stairs, doorways, drops) shows on both of them; teleports and other levels break
	-- the path into pieces
	local p = route.path
	local OnFloor = DN.OnFloor
	nPiece, nActive = 0, 0
	for i = 1, #p / 3 - 1 do
		local a, b = (i - 1) * 3, i * 3
		if not navOff and i >= legFrom and not route.teleAt[i] and (OnFloor(p[a + 3], level) or OnFloor(p[b + 3], level)) then
			if nPiece == 0 then
				piece[1], piece[2] = self:WorldToMap(inst, level, p[a + 1], p[a + 2])
				nPiece = 2
			end
			piece[nPiece + 1], piece[nPiece + 2] = self:WorldToMap(inst, level, p[b + 1], p[b + 2])
			nPiece = nPiece + 2
			if i < legTo then nActive = nPiece end
		elseif nPiece > 0 then
			mapPath:Add(piece, nPiece, nActive)
			nPiece, nActive = 0, 0
		end
	end
	if nPiece > 0 then mapPath:Add(piece, nPiece, nActive) end

	-- other layers (the route recorder's legs): fn(inst, level, toMap(x, y) -> px, py, Dot(px, py))
	for _, fn in ipairs(self.mapLayers or {}) do fn(inst, level, toMap, LayerDot) end

	-- boss rings, numbered in route order (other bosses get no number)
	local numOf = {}
	for k, bi in ipairs(route.order) do numOf[bi] = k end
	for bi, b in ipairs(inst.bosses) do
		if b.x and OnFloor(b.f, level) and (not current or self:BossAvailable(b)) then
			local x, y = toMap(b.x, b.y)
			local killedAt, isNext = killed[b.id], b == nextBoss
			local state = killedAt and "done" or isNext and "next" or numOf[bi] and "stop" or "other"
			local ring = mapStops:Add(x, y, state, numOf[bi])
			ring.boss, ring.order, ring.killedAt, ring.isNext, ring.quest = b, numOf[bi] or 0, killedAt, isNext, nil
		end
	end

	-- quest stops: small gray rings ("!" an objective, "?" a turn-in), the next one gold with a bright line out to it
	-- from the route
	for _, q in ipairs(current and not navOff and self.questStops or {}) do
		if OnFloor(q.f, level) then
			local isNext = q == nextBoss
			if isNext then
				local o = q.anchor * 3
				piece[1], piece[2] = self:WorldToMap(inst, level, p[o - 2], p[o - 1])
				piece[3], piece[4] = self:WorldToMap(inst, level, q.x, q.y)
				mapPath:Add(piece, 4, 4)
			end
			local x, y = toMap(q.x, q.y)
			local ring = mapStops:Add(x, y, isNext and "next" or "other", q.kind == "turnin" and "?" or "!")
			ring.quest, ring.boss, ring.isNext = q, nil, isNext
		end
	end
end

-- The instance whose map is shown, if InstanceGPS draws on it: navigation off there shows boss rings only (and
-- nothing if the tracker's hidden there too)
local function ShownInstance(self)
	local file = self.opt and self.opt.mapOverlay and WorldMapFrame:IsShown() and GetMapInfo()
	local inst = file and self.inst
	if file and not (inst and inst.file and inst.file:lower() == file:lower()) then
		inst = nil
		for _, i in pairs(ns.Instances) do
			if i.file and i.file:lower() == file:lower() then inst = i break end
		end
	end
	local navOff = inst and self:IsOff(inst.mapId)
	if inst and not (navOff and self.opt.offHidesTracker) then return inst, navOff end
end

function DN:RefreshMap()
	mapPath:Begin()
	mapStops:Begin()
	local inst, navOff = ShownInstance(self)
	local level = inst and self:MapLevel(inst)
	local current = inst == self.inst
	local run = inst and (current and self.run or self.char.runs[inst.mapId])
	local routeIndex = inst and (current and self.routeIndex or (run and run.route) or 1)
	local route = inst and (inst.routes[routeIndex] or inst.routes[1])
	if route and inst.floors[level] and WorldMapButton:GetWidth() > 0 then
		DrawMap(self, inst, level, navOff, current, route, run and run.killed or {})
	end
	mapPath:Finish()
	mapStops:Finish()
end

overlay:RegisterEvent("WORLD_MAP_UPDATE")
overlay:SetScript("OnEvent", function() DN:RefreshMap() end)

-- Redraw whenever the shown map or level changes (the level dropdown doesn't always fire
-- WORLD_MAP_UPDATE), and refresh the leg highlight as you move.
local shownMap, shownLevel, shownLeg, shownRoute, shownRecord
local sinceRedraw = 0
overlay:SetScript("OnUpdate", function(_, elapsed)
	sinceRedraw = sinceRedraw + elapsed
	if sinceRedraw >= 0.25 then
		sinceRedraw = 0
		local map, level, legTo = GetMapInfo(), GetCurrentMapDungeonLevel(), DN.leg and DN.leg.to
		if map ~= shownMap or level ~= shownLevel or legTo ~= shownLeg or DN.routeIndex ~= shownRoute
			or DN.recordVersion ~= shownRecord then
			shownMap, shownLevel, shownLeg, shownRoute, shownRecord = map, level, legTo, DN.routeIndex, DN.recordVersion
			DN:RefreshMap()
		end
	end
end)
WorldMapFrame:HookScript("OnShow", function() DN:RefreshMap() end)
DN:On("RUN_CHANGED", function() if WorldMapFrame:IsShown() then DN:RefreshMap() end end)
DN:On("ROUTE_CHANGED", function() if WorldMapFrame:IsShown() then DN:RefreshMap() end end)
