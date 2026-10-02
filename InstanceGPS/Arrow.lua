-- InstanceGPS arrow: points at the next waypoint on the route.
local _, ns = ...
local DN = ns.DN

local sin, cos, atan2, abs, pi = math.sin, math.cos, math.atan2, math.abs, math.pi

local arrow = CreateFrame("Button", "InstanceGPSArrow", UIParent)
arrow:SetSize(56, 56)
arrow:SetFrameStrata("MEDIUM")
arrow:SetMovable(true)
arrow:EnableMouse(true)
arrow:RegisterForDrag("LeftButton")
arrow:RegisterForClicks("RightButtonUp")
arrow:SetClampedToScreen(true)
arrow:Hide()
DN.arrow = arrow

local tex = arrow:CreateTexture(nil, "OVERLAY")
tex:SetAllPoints()
tex:SetTexture(DN.MEDIA .. "Arrow")

local title = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
local sub = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sub:SetPoint("TOP", title, "BOTTOM", 0, -1)
local hint = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOP", sub, "BOTTOM", 0, -1)
hint:SetWidth(260)   -- teleporter hints name the gossip option and can be long
hint:SetTextColor(1, 0.6, 0.2)

-- rotate the texture clockwise by `a` radians (texcoords rotate the other way)
local function SetRotation(t, a)
	local c, s = cos(-a), sin(-a)
	local function tc(x, y)
		return 0.5 + x * c - y * s, 0.5 + x * s + y * c
	end
	local ulx, uly = tc(-0.5, -0.5)
	local llx, lly = tc(-0.5, 0.5)
	local urx, ury = tc(0.5, -0.5)
	local lrx, lry = tc(0.5, 0.5)
	t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end
DN.SetRotation = SetRotation

arrow:SetScript("OnDragStart", function(self)
	if not DN.opt.lockFrames then self:StartMoving() end
end)
arrow:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint()
	DN.db.pos.arrow = { p, rp, x, y }
end)
arrow:SetScript("OnClick", function(_, button)
	if button == "RightButton" then DN:ShowMenu(arrow) end
end)
arrow:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("InstanceGPS")
	GameTooltip:AddLine("Drag to move, right-click for options.", 1, 1, 1)
	GameTooltip:Show()
end)
arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)

local lastUpdate = 0
arrow:SetScript("OnUpdate", function(self, elapsed)
	lastUpdate = lastUpdate + elapsed
	if lastUpdate < 0.03 then return end
	lastUpdate = 0
	local w = DN.wp
	local x, y, f, dist, boss, atBoss, portal = w.x, w.y, w.f, w.dist, w.boss, w.atBoss, w.portal
	if not x then
		tex:SetVertexColor(0.5, 0.5, 0.5)
		SetRotation(tex, 0)
		local b = DN:NextBoss()
		if not b then
			title:SetText(DN.inst and "All Bosses Down" or "")
			sub:SetText("")
		else
			title:SetText(b.name)
			if not b.x then
				sub:SetText("no known position for this fight")
			elseif not DN.px then
				-- the client reports no map position here: this instance has no in-game map
				sub:SetText(DN.inst and DN.inst.needsMapPatch and "needs the WoW Dungeon Maps patch" or "waiting for a map position")
			else
				sub:SetText("")
			end
		end
		hint:SetText("")
		return
	end
	local facing = GetPlayerFacing() or 0
	local bearing = atan2(y - DN.py, x - DN.px)     -- counterclockwise from north
	local rel = facing - bearing                    -- clockwise turn needed
	rel = (rel + pi) % (2 * pi) - pi
	SetRotation(tex, rel)
	local off = abs(rel) / pi                       -- 0 ahead .. 1 behind
	if atBoss and dist < 20 then
		tex:SetVertexColor(1, 0.25, 0.25)
	elseif off < 0.15 then
		tex:SetVertexColor(0.3, 1, 0.3)
	elseif off < 0.5 then
		tex:SetVertexColor(1, 0.85, 0.2)
	else
		tex:SetVertexColor(1, 0.45, 0.2)
	end
	title:SetText(boss.name)
	local remain = atBoss and dist or DN.remaining or dist
	sub:SetText(("%d yd"):format(remain))
	if portal then
		if type(portal) == "string" then
			hint:SetText(portal)
		else
			hint:SetText(dist < 12 and "Use the teleporter here" or ("Teleporter in %d yd"):format(dist))
		end
	elseif f and DN.pfloor and not DN.OnFloor(f, DN.pfloor) and (DN.FirstFloor(f) or 0) ~= 0 then
		hint:SetText(("Level %d"):format(DN.FirstFloor(f)))
	else
		hint:SetText("")
	end
end)

function DN:UpdateArrowVisibility()
	if self.opt.arrow and self:NavOn() then arrow:Show() else arrow:Hide() end
	arrow:SetScale(self.opt.arrowScale or 1)
end

DN:On("LOADED", function()
	local pos = DN.db.pos.arrow
	arrow:ClearAllPoints()
	if pos then
		arrow:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		-- bottom center, high enough that the labels under the arrow clear the action bars
		arrow:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 310)
	end
end)
DN:On("INSTANCE_CHANGED", function() DN:UpdateArrowVisibility() end)
