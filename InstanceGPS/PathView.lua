-- InstanceGPS path views: the route ahead drawn on the minimap, as a HUD around the
-- character, and in a small perspective ("3D") panel. Each one is optional.
local _, ns = ...
local DN = ns.DN

local sqrt, floor, abs, min, max = math.sqrt, math.floor, math.abs, math.min, math.max
local sin, cos, atan2, fmod = math.sin, math.cos, math.atan2, math.fmod

local GOLD = { 1, 0.82, 0.1 }
local TELE = { 0.75, 0.45, 1 }
local BOSS = { 1, 0.25, 0.2 }

-------------------------------------------------------------------------------- helpers

-- texture pool: Begin(), Get() for each texture drawn, Finish() hides the unused ones
local function Pool(parent, file, layer)
	local pool = { n = 0, list = {} }
	function pool:Begin() self.n = 0 end
	function pool:Get()
		self.n = self.n + 1
		local t = self.list[self.n]
		if not t then
			t = parent:CreateTexture(nil, layer or "ARTWORK")
			t:SetTexture(file)
			self.list[self.n] = t
		end
		t:ClearAllPoints()
		t:Show()
		return t
	end
	function pool:Finish()
		for i = self.n + 1, #self.list do self.list[i]:Hide() end
	end
	return pool
end

-- Calls fn(x, y, dx, dy, along) every `spacing` yards along the path (dx, dy = direction,
-- along = distance from the player). Marks are anchored to the route's vertices, not to the
-- player, so they stay put in the world while you walk.
local function Sample(pts, n, spacing, maxLen, fn)
	if not pts or n < 4 then return end
	local along, carry = 0, 0
	for i = 1, n - 3, 2 do
		local x1, y1, x2, y2 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
		local dx, dy = x2 - x1, y2 - y1
		local L = sqrt(dx * dx + dy * dy)
		if L > 0 then
			dx, dy = dx / L, dy / L
			-- first piece (player -> first vertex): count back from the vertex
			local t = i == 1 and fmod(L, spacing) or carry
			if i == 1 and t < 1.5 then t = t + spacing end
			while t < L - 0.01 do
				if along + t > maxLen then return end
				fn(x1 + dx * t, y1 + dy * t, dx, dy, along + t)
				t = t + spacing
			end
			carry = max(0, t - L)
			along = along + L
		end
	end
end

local pts, nPts, endKind = {}, 0, nil

-- player position at frame rate (the core only samples it every 0.1 s)
local function PlayerPos()
	local inst, px, py = DN.inst, DN.px, DN.py
	if not inst or not px or (WorldMapFrame and WorldMapFrame:IsShown()) then return px, py end
	local mx, my = GetPlayerMapPosition("player")
	if not mx or (mx == 0 and my == 0) then return px, py end
	local x, y = DN:MapToWorld(inst, DN.pfloor or 0, mx, my)
	return x or px, y or py
end

local function Refresh(px, py, maxLen)
	local list, n, kind = DN:PathAhead(px, py, maxLen, pts)
	nPts, endKind = list and n or 0, kind
	return nPts >= 4
end

-------------------------------------------------------------------------------- 1. minimap

-- minimap diameter in yards per zoom level (indoors / outdoors)
local MM_INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
local MM_OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 }

local mm = CreateFrame("Frame", "InstanceGPSMinimapPath", Minimap)
mm:SetAllPoints(Minimap)
mm:SetFrameLevel(Minimap:GetFrameLevel() + 4)
local mmDots = Pool(mm, DN.MEDIA .. "Dot", "ARTWORK")
local mmEnd = mm:CreateTexture(nil, "OVERLAY")
mmEnd:SetTexture(DN.MEDIA .. "Ring")
mmEnd:SetSize(14, 14)

-- The client doesn't say whether the minimap uses its indoor or outdoor zoom: change the
-- other zoom setting for a moment and see which one the minimap follows.
local indoors, checking = true, false
local function CheckIndoors()
	if checking then return end
	checking = true
	local zoom = Minimap:GetZoom()
	if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
		Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
	end
	indoors = tonumber(GetCVar("minimapZoom")) ~= Minimap:GetZoom()
	Minimap:SetZoom(zoom)
	checking = false
end
mm:RegisterEvent("MINIMAP_UPDATE_ZOOM")
mm:RegisterEvent("ZONE_CHANGED_INDOORS")
mm:RegisterEvent("PLAYER_ENTERING_WORLD")
mm:SetScript("OnEvent", CheckIndoors)

local function DrawMinimap(px, py, facing)
	local W = mm:GetWidth()
	local diam = (indoors and MM_INDOOR or MM_OUTDOOR)[Minimap:GetZoom()] or 300
	local scale = W / diam                     -- pixels per yard
	local R = W / 2
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	local c, s = 1, 0
	if GetCVar("rotateMinimap") == "1" then c, s = cos(facing), sin(facing) end
	local function screen(x, y)
		local ex, ny = py - y, x - px          -- east, north
		return (ex * c + ny * s) * scale, (ny * c - ex * s) * scale
	end
	local function inside(sx, sy, m)
		if square then return abs(sx) <= R - m and abs(sy) <= R - m end
		return sx * sx + sy * sy <= (R - m) * (R - m)
	end
	mmDots:Begin()
	Sample(pts, nPts, 7 / scale, diam, function(x, y)
		local sx, sy = screen(x, y)
		if inside(sx, sy, 3) then
			local t = mmDots:Get()
			t:SetSize(5, 5)
			t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
			t:SetPoint("CENTER", mm, "CENTER", sx, sy)
		end
	end)
	mmDots:Finish()
	-- the boss or teleporter at the end, pinned to the edge when it's off the minimap
	if endKind then
		local sx, sy = screen(pts[nPts - 1], pts[nPts])
		if not inside(sx, sy, 7) then
			if square then
				local k = (R - 7) / max(abs(sx), abs(sy))
				sx, sy = sx * k, sy * k
			else
				local k = (R - 7) / sqrt(sx * sx + sy * sy)
				sx, sy = sx * k, sy * k
			end
		end
		local col = endKind == "tele" and TELE or BOSS
		mmEnd:SetVertexColor(col[1], col[2], col[3])
		mmEnd:ClearAllPoints()
		mmEnd:SetPoint("CENTER", mm, "CENTER", sx, sy)
		mmEnd:Show()
	else
		mmEnd:Hide()
	end
end

-------------------------------------------------------------------------------- 2. HUD

local hud = CreateFrame("Frame", "InstanceGPSHUD", UIParent)
hud:SetFrameStrata("BACKGROUND")
hud:EnableMouse(false)
local hudRing = hud:CreateTexture(nil, "BACKGROUND")
hudRing:SetTexture(DN.MEDIA .. "Ring")
hudRing:SetAllPoints()
hudRing:SetVertexColor(1, 1, 1, 0.12)
local hudMarks = Pool(hud, DN.MEDIA .. "Chevron", "ARTWORK")
local hudEnd = hud:CreateTexture(nil, "OVERLAY")
hudEnd:SetTexture(DN.MEDIA .. "Ring")
hudEnd:SetSize(22, 22)

local function DrawHUD(px, py, facing)
	local o = DN.opt
	local R = (o.hudSize or 280) / 2
	local range = o.hudRange or 40
	local scale = R / range
	local c, s = cos(facing), sin(facing)      -- heading up: always turned with the character
	local function screen(x, y)
		local ex, ny = py - y, x - px
		return (ex * c + ny * s) * scale, (ny * c - ex * s) * scale
	end
	hudMarks:Begin()
	Sample(pts, nPts, 18 / scale, range * 1.5, function(x, y, dx, dy)
		local sx, sy = screen(x, y)
		local r = sqrt(sx * sx + sy * sy)
		if r <= R - 6 then
			local t = hudMarks:Get()
			t:SetSize(14, 14)
			-- fade out toward the rim
			t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], min(1, 1.6 * (1 - r / R)))
			t:SetPoint("CENTER", hud, "CENTER", sx, sy)
			local ux, uy = screen(x + dx, y + dy)
			DN.SetRotation(t, atan2(ux - sx, uy - sy))
		end
	end)
	hudMarks:Finish()
	if endKind then
		local sx, sy = screen(pts[nPts - 1], pts[nPts])
		local r = sqrt(sx * sx + sy * sy)
		if r > R - 11 then sx, sy = sx * (R - 11) / r, sy * (R - 11) / r end
		local col = endKind == "tele" and TELE or BOSS
		hudEnd:SetVertexColor(col[1], col[2], col[3])
		hudEnd:ClearAllPoints()
		hudEnd:SetPoint("CENTER", hud, "CENTER", sx, sy)
		hudEnd:Show()
	else
		hudEnd:Hide()
	end
end

-------------------------------------------------------------------------------- 3. perspective view

local VIEW_W, VIEW_H = 220, 130
local CAM_BACK, CAM_H = 7, 4          -- yards: the virtual camera behind and above the player
local HORIZON = 0.24                  -- fraction of the height from the top
local FOOT = 0.84                     -- where the player's feet show
local VIEW_RANGE = 90

local view = CreateFrame("Button", "InstanceGPSPathView", UIParent)
view:SetSize(VIEW_W, VIEW_H)
view:SetFrameStrata("MEDIUM")
view:SetMovable(true)
view:EnableMouse(true)
view:SetClampedToScreen(true)
view:RegisterForDrag("LeftButton")
view:RegisterForClicks("RightButtonUp")
view:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
view:SetBackdropColor(0.05, 0.07, 0.12, 0.85)
view:SetBackdropBorderColor(0.5, 0.5, 0.55, 0.9)
view:Hide()

local ground = view:CreateTexture(nil, "BACKGROUND", nil)
ground:SetTexture(1, 1, 1)
ground:SetPoint("TOPLEFT", 4, -VIEW_H * HORIZON)
ground:SetPoint("BOTTOMRIGHT", -4, 4)
ground:SetGradientAlpha("VERTICAL", 0.16, 0.2, 0.14, 0.9, 0.08, 0.1, 0.08, 0.5)
local horizon = view:CreateTexture(nil, "BORDER")
horizon:SetTexture(1, 1, 1, 0.25)
horizon:SetHeight(1)
horizon:SetPoint("TOPLEFT", 4, -VIEW_H * HORIZON)
horizon:SetPoint("TOPRIGHT", -4, -VIEW_H * HORIZON)

local viewMarks = Pool(view, DN.MEDIA .. "Chevron", "ARTWORK")
local viewEnd = view:CreateTexture(nil, "OVERLAY")
viewEnd:SetTexture(DN.MEDIA .. "Ring")
local viewMe = view:CreateTexture(nil, "OVERLAY")
viewMe:SetTexture(DN.MEDIA .. "Arrow")
viewMe:SetSize(14, 14)
viewMe:SetVertexColor(0.4, 0.8, 1)
local viewTitle = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
viewTitle:SetPoint("TOPLEFT", 8, -6)
viewTitle:SetPoint("TOPRIGHT", -8, -6)
viewTitle:SetJustifyH("LEFT")
local viewHint = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
viewHint:SetPoint("BOTTOMLEFT", 8, 6)
viewHint:SetPoint("BOTTOMRIGHT", -8, 6)
viewHint:SetTextColor(1, 0.6, 0.2)
local viewBehind = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
viewBehind:SetPoint("CENTER", 0, -8)
viewBehind:SetText("Turn around")
-- shown instead of the path when there's nothing to follow
local viewIdle = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
viewIdle:SetPoint("CENTER", 0, 0)
viewIdle:SetWidth(VIEW_W - 20)

local F = (FOOT - HORIZON) * VIEW_H * CAM_BACK / CAM_H   -- focal length in pixels

local function DrawView(px, py, facing)
	local c, s = cos(facing), sin(facing)
	local halfW = VIEW_W / 2 - 6
	-- world -> panel offsets from TOP (y up), and the depth
	local function project(x, y)
		local dN, dW = x - px, y - py
		local z = dN * c + dW * s + CAM_BACK
		if z < 1.5 then return nil end
		local right = dN * s - dW * c
		return right * F / z, -(VIEW_H * HORIZON + CAM_H * F / z), z
	end
	viewIdle:Hide()
	viewMe:Show()
	viewMarks:Begin()
	local drawn, lastX, lastY = 0, nil, nil
	Sample(pts, nPts, 2, VIEW_RANGE, function(x, y, dx, dy, along)
		local sx, sy, z = project(x, y)
		if not sx or abs(sx) > halfW or sy < -(VIEW_H - 8) then return end
		local ux, uy = project(x + dx, y + dy)
		if not ux then return end
		local size = max(4, min(22, 1.6 * F / z))
		-- keep marks apart on screen: far away, many yards fit in a few pixels
		if lastX and (sx - lastX) ^ 2 + (sy - lastY) ^ 2 < (size * 1.1) ^ 2 then return end
		lastX, lastY = sx, sy
		local t = viewMarks:Get()
		t:SetSize(size, size)
		t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1 - 0.55 * along / VIEW_RANGE)
		t:SetPoint("CENTER", view, "TOP", sx, sy)
		DN.SetRotation(t, atan2(ux - sx, uy - sy))
		drawn = drawn + 1
	end)
	viewMarks:Finish()
	viewMe:SetPoint("CENTER", view, "TOP", 0, -(VIEW_H * HORIZON + CAM_H * F / CAM_BACK))
	viewEnd:Hide()
	if endKind then
		local sx, sy, z = project(pts[nPts - 1], pts[nPts])
		if sx and abs(sx) <= halfW then
			local size = max(8, min(30, 3 * F / z))
			local col = endKind == "tele" and TELE or BOSS
			viewEnd:SetSize(size, size)
			viewEnd:SetVertexColor(col[1], col[2], col[3])
			viewEnd:ClearAllPoints()
			viewEnd:SetPoint("CENTER", view, "TOP", sx, sy)
			viewEnd:Show()
		end
	end
	-- nothing ahead of us: the path starts behind
	if drawn == 0 and nPts >= 4 then viewBehind:Show() else viewBehind:Hide() end
	local w = DN.wp
	viewTitle:SetText(("%s  |cffffffff%d yd|r"):format(w.boss.name, w.atBoss and w.dist or DN.remaining or w.dist or 0))
	viewHint:SetText(type(w.portal) == "string" and w.portal
		or (w.portal and (w.dist < 12 and "Use the teleporter here" or "Teleporter ahead")) or "")
end

view:SetScript("OnDragStart", function(self)
	if not DN.opt.lockFrames then self:StartMoving() end
end)
view:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint()
	DN.db.pos.pathView = { p, rp, x, y }
end)
view:SetScript("OnClick", function(self, button)
	if button == "RightButton" then DN:ShowMenu(self) end
end)

-------------------------------------------------------------------------------- driver

local function ClearAll()
	mmDots:Begin() mmDots:Finish() mmEnd:Hide()
	hudMarks:Begin() hudMarks:Finish() hudEnd:Hide() hudRing:Hide()
	viewMarks:Begin() viewMarks:Finish() viewEnd:Hide() viewBehind:Hide()
	viewTitle:SetText("") viewHint:SetText("")
end

-- the 3D view with nothing to draw says why, like the arrow does
local function ViewIdle()
	local b, text = DN:NextBoss(), nil
	if not b then
		local run = DN.run
		text = run and run.cleared and ("All bosses down|n|cffffffffCleared in %s|r"):format(DN.FormatTime(run.cleared))
			or "All bosses down"
	elseif not b.x then
		text = b.name .. "|n|cffffffffno known position for this fight|r"
	else
		text = b.name .. "|n|cffffffff" .. (DN.inst and DN.inst.needsMapPatch and not DN.px
			and "needs the WoW Dungeon Maps patch" or "waiting for a map position") .. "|r"
	end
	viewIdle:SetText(text)
	viewIdle:Show()
	viewMe:Hide()
end

local driver = CreateFrame("Frame")
local since = 0
driver:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if since < 0.025 then return end
	since = 0
	local o = DN.opt
	if not o or not DN:NavOn() then return end
	local px, py = PlayerPos()
	local hudOn = o.pathHud and not (o.hudHideCombat and UnitAffectingCombat("player"))
	if not px or not DN.wp.x then
		ClearAll()
		hud:Hide()
		if o.pathView then ViewIdle() end
		return
	end
	local range = 0
	if o.pathMinimap then range = 300 end
	if hudOn then range = max(range, (o.hudRange or 40) * 1.5) end
	if o.pathView then range = max(range, VIEW_RANGE) end
	if range == 0 or not Refresh(px, py, range + 20) then ClearAll() hud:Hide() return end
	local facing = GetPlayerFacing() or 0
	if o.pathMinimap then DrawMinimap(px, py, facing) end
	if hudOn then
		hudRing:Show()
		DrawHUD(px, py, facing)
		hud:Show()
	else
		hud:Hide()
	end
	if o.pathView then DrawView(px, py, facing) end
end)

function DN:UpdatePathViews()
	local o, inst = self.opt, self:NavOn() and self.inst
	if not o then return end
	if not (inst and o.pathMinimap) then mmDots:Begin() mmDots:Finish() mmEnd:Hide() end
	local size = o.hudSize or 280
	hud:SetSize(size, size)
	hud:ClearAllPoints()
	hud:SetPoint("CENTER", UIParent, "CENTER", 0, o.hudOffset or -30)
	hud:SetAlpha(o.hudAlpha or 0.7)
	if inst and o.pathHud then hud:Show() else hud:Hide() end
	view:SetScale(o.pathViewScale or 1)
	if inst and o.pathView then view:Show() else view:Hide() end
	if inst and (o.pathMinimap or o.pathHud or o.pathView) then driver:Show() else driver:Hide() ClearAll() end
end

DN:On("LOADED", function()
	local pos = DN.db.pos.pathView
	view:ClearAllPoints()
	if pos then
		view:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		-- beside the arrow
		view:SetPoint("BOTTOM", UIParent, "BOTTOM", 200, 290)
	end
	DN:UpdatePathViews()
end)
DN:On("INSTANCE_CHANGED", function() DN:UpdatePathViews() end)
