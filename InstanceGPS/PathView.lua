-- InstanceGPS path views: the route ahead drawn on the minimap, as a HUD around the
-- character, and in a small perspective ("3D") panel. Each one is optional.
local _, ns = ...
local DN, R = ns.DN, ns.Route

local sqrt, abs, min, max = math.sqrt, math.abs, math.min, math.max
local sin, cos, atan2 = math.sin, math.cos, math.atan2
local Pool, Sample = R.Pool, R.Sample

local GOLD = { 1, 0.82, 0.1 }
local TELE = { 0.75, 0.45, 1 }
local BOSS = { 1, 0.25, 0.2 }

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

local mmPath = R.NewMinimapPath(GOLD)
DN.minimapPath = mmPath
local mm = mmPath.frame
local mmEnd = mm:CreateTexture(nil, "OVERLAY")
mmEnd:SetTexture(DN.MEDIA .. "Ring")
mmEnd:SetSize(14, 14)

local function DrawMinimap(px, py, facing)
	mmPath:Draw(px, py, facing, pts, nPts)
	-- the boss or teleporter at the end, pinned to the edge when it's off the minimap
	if endKind then
		local scale, radius, square, c, s = R.MinimapView(mm, facing)
		local sx, sy = R.MinimapScreen(px, py, pts[nPts - 1], pts[nPts], scale, c, s)
		if not R.MinimapInside(sx, sy, radius, 7, square) then
			sx, sy = R.MinimapEdge(sx, sy, radius, 7, square)
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
	local radius = (o.hudSize or 280) / 2
	local range = o.hudRange or 40
	local scale = radius / range
	local c, s = cos(facing), sin(facing)      -- heading up: always turned with the character
	local function screen(x, y)
		local ex, ny = py - y, x - px
		return (ex * c + ny * s) * scale, (ny * c - ex * s) * scale
	end
	hudMarks:Begin()
	Sample(pts, nPts, 18 / scale, range * 1.5, function(x, y, dx, dy)
		local sx, sy = screen(x, y)
		local r = sqrt(sx * sx + sy * sy)
		if r <= radius - 6 then
			local t = hudMarks:Get()
			t:SetSize(14, 14)
			-- fade out toward the rim
			t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], min(1, 1.6 * (1 - r / radius)))
			t:SetPoint("CENTER", hud, "CENTER", sx, sy)
			local ux, uy = screen(x + dx, y + dy)
			DN.SetRotation(t, atan2(ux - sx, uy - sy))
		end
	end)
	hudMarks:Finish()
	if endKind then
		local sx, sy = screen(pts[nPts - 1], pts[nPts])
		local r = sqrt(sx * sx + sy * sy)
		if r > radius - 11 then sx, sy = sx * (radius - 11) / r, sy * (radius - 11) / r end
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
	mmPath:Clear() mmEnd:Hide()
	hudMarks:Begin() hudMarks:Finish() hudEnd:Hide() hudRing:Hide()
	viewMarks:Begin() viewMarks:Finish() viewEnd:Hide() viewBehind:Hide()
	viewTitle:SetText("") viewHint:SetText("")
end

-- the 3D view with nothing to draw says why, like the arrow does
local function ViewIdle()
	local b, text = DN:NextBoss(), nil
	if not b then
		local run = DN.run
		text = run and run.cleared and ("All Bosses Down|n|cffffffffCleared in %s|r"):format(DN.FormatTime(run.cleared))
			or "All Bosses Down"
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
	if not (inst and o.pathMinimap) then mmPath:Clear() mmEnd:Hide() end
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
