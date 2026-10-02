-- InstanceGPS map overlay: route and boss pins on the dungeon map.
local _, ns = ...
local DN = ns.DN

local sqrt, floor = math.sqrt, math.floor
local DOT_SPACING = 9     -- pixels between route dots (at 1002px map width)

local overlay = CreateFrame("Frame", "InstanceGPSMapOverlay", WorldMapButton)
overlay:SetAllPoints(WorldMapButton)
overlay:SetFrameLevel(WorldMapButton:GetFrameLevel() + 5)

local dots, pins = {}, {}
local nDots = 0

local function Dot()
	nDots = nDots + 1
	local t = dots[nDots]
	if not t then
		t = overlay:CreateTexture(nil, "ARTWORK")
		t:SetTexture(DN.MEDIA .. "Dot")
		t:SetSize(7, 7)
		dots[nDots] = t
	end
	t:Show()
	return t
end

local function PinOnEnter(self)
	local b = self.boss
	WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT")
	WorldMapTooltip:AddLine((self.order > 0 and (self.order .. ". ") or "") .. b.name)
	if self.killedAt then
		WorldMapTooltip:AddLine(("Killed (%s into the run)"):format(DN.FormatTime(self.killedAt)), 0.3, 1, 0.3)
	elseif self.isNext then
		WorldMapTooltip:AddLine("Next on the route", 1, 0.82, 0)
	end
	WorldMapTooltip:AddLine("Click: navigate here", 0.6, 0.8, 1)
	WorldMapTooltip:Show()
end

local function PinOnClick(self)
	if DN.inst and DN.inst.bosses[self.boss.index] == self.boss then DN:SetNavTarget(self.boss) end
end

local function Pin(i)
	local p = pins[i]
	if p then return p end
	p = CreateFrame("Button", nil, overlay)
	p:SetSize(20, 20)
	p:SetFrameLevel(overlay:GetFrameLevel() + 2)
	p.ring = p:CreateTexture(nil, "ARTWORK")
	p.ring:SetAllPoints()
	p.ring:SetTexture(DN.MEDIA .. "Ring")
	p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.num:SetPoint("CENTER", 0, 0)
	p.check = p:CreateTexture(nil, "OVERLAY")
	p.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	p.check:SetSize(14, 14)
	p.check:SetPoint("CENTER")
	p:SetScript("OnEnter", PinOnEnter)
	p:SetScript("OnLeave", function() WorldMapTooltip:Hide() end)
	p:SetScript("OnClick", PinOnClick)
	pins[i] = p
	return p
end

local function Clear()
	for i = 1, nDots do dots[i]:Hide() end
	nDots = 0
	for _, p in ipairs(pins) do p:Hide() end
end

function DN:RefreshMap()
	Clear()
	if not self.opt or not self.opt.mapOverlay or not WorldMapFrame:IsShown() then return end
	local file = GetMapInfo()
	if not file then return end
	local inst = self.inst
	if not (inst and inst.file and inst.file:lower() == file:lower()) then
		inst = nil
		for _, i in pairs(ns.Instances) do
			if i.file and i.file:lower() == file:lower() then inst = i break end
		end
	end
	if not inst or self:IsOff(inst.mapId) then return end
	local level = GetCurrentMapDungeonLevel() or 0
	if not inst.floors[level] then
		if inst.floors[0] then level = 0 else return end
	end
	local W, H = overlay:GetWidth(), overlay:GetHeight()
	if W == 0 then return end
	local current = inst == self.inst
	local run = current and self.run or self.char.runs[inst.mapId]
	local routeIndex = current and self.routeIndex or (run and run.route) or 1
	local route = inst.routes[routeIndex] or inst.routes[1]
	if not route then return end
	local killed = run and run.killed or {}
	local nextBoss = current and self:NextBoss()

	local function px(x, y)
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

	local p = route.path
	local spacing = DOT_SPACING * W / 1002
	local carry = 0
	local OnFloor = DN.OnFloor
	for i = 1, #p / 3 - 1 do
		local a, b = (i - 1) * 3, i * 3
		local done = i < legFrom
		-- a segment changing levels (stairs, doorways, drops) shows on both of them
		if not done and not route.teleAt[i] and (OnFloor(p[a + 3], level) or OnFloor(p[b + 3], level)) then
			local x1, y1 = px(p[a + 1], p[a + 2])
			local x2, y2 = px(p[b + 1], p[b + 2])
			local dx, dy = x2 - x1, y2 - y1
			local len = sqrt(dx * dx + dy * dy)
			local d = carry
			local active = i < legTo
			local sp = active and spacing or spacing * 1.6
			while d < len do
				local t = Dot()
				t:ClearAllPoints()
				t:SetPoint("CENTER", overlay, "TOPLEFT", x1 + dx * d / len, -(y1 + dy * d / len))
				if active then
					t:SetSize(8, 8)
					t:SetVertexColor(1, 0.82, 0.1, 1)
				else
					t:SetSize(5, 5)
					t:SetVertexColor(0.85, 0.85, 0.85, 0.45)
				end
				d = d + sp
			end
			carry = d - len
		else
			carry = 0
		end
	end

	-- other layers (the route recorder's legs): fn(inst, level, toMap(x, y) -> px, py, Dot(px, py))
	local function DotAt(x, y)
		local t = Dot()
		t:ClearAllPoints()
		t:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
		return t
	end
	for _, fn in ipairs(self.mapLayers or {}) do fn(inst, level, px, DotAt) end

	-- boss pins, numbered in route order (other bosses get no number)
	local numOf = {}
	for k, bi in ipairs(route.order) do numOf[bi] = k end
	local n = 0
	for bi, b in ipairs(inst.bosses) do
		if b.x and DN.OnFloor(b.f, level) and (not current or self:BossAvailable(b)) then
			n = n + 1
			local pin = Pin(n)
			local x, y = px(b.x, b.y)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
			pin.boss, pin.order, pin.killedAt, pin.isNext = b, numOf[bi] or 0, killed[b.id], b == nextBoss
			pin.num:SetText(numOf[bi] or "")
			if pin.killedAt then
				pin.ring:SetVertexColor(0.3, 0.9, 0.3)
				pin.check:Show()
				pin.num:Hide()
				pin:SetSize(18, 18)
			else
				pin.check:Hide()
				pin.num:Show()
				if pin.isNext then
					pin.ring:SetVertexColor(1, 0.82, 0)
					pin:SetSize(26, 26)
				elseif numOf[bi] then
					pin.ring:SetVertexColor(1, 0.25, 0.2)
					pin:SetSize(20, 20)
				else
					pin.ring:SetVertexColor(0.6, 0.6, 0.6)
					pin:SetSize(16, 16)
				end
			end
			pin:Show()
		end
	end
end

overlay:RegisterEvent("WORLD_MAP_UPDATE")
overlay:SetScript("OnEvent", function() DN:RefreshMap() end)

-- Redraw whenever the shown map or level changes (the level dropdown doesn't always fire
-- WORLD_MAP_UPDATE), and refresh the leg highlight as you move.
local shownKey, sinceRedraw = nil, 0
overlay:SetScript("OnUpdate", function(_, elapsed)
	sinceRedraw = sinceRedraw + elapsed
	if sinceRedraw < 0.25 then return end
	sinceRedraw = 0
	local key = (GetMapInfo() or "") .. ":" .. (GetCurrentMapDungeonLevel() or 0) .. ":" ..
		tostring(DN.leg and DN.leg.to) .. ":" .. tostring(DN.routeIndex) .. ":" .. (DN.recordVersion or 0)
	if key ~= shownKey then
		shownKey = key
		DN:RefreshMap()
	end
end)
WorldMapFrame:HookScript("OnShow", function() DN:RefreshMap() end)
DN:On("RUN_CHANGED", function() if WorldMapFrame:IsShown() then DN:RefreshMap() end end)
DN:On("ROUTE_CHANGED", function() if WorldMapFrame:IsShown() then DN:RefreshMap() end end)
