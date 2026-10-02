-- InstanceGPS tracker: the boss list for the current instance.
local _, ns = ...
local DN = ns.DN

local ROW_H, WIDTH = 16, 230
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12:12:0:0|t"

local f = CreateFrame("Frame", "InstanceGPSTracker", UIParent)
f:SetWidth(WIDTH)
f:SetHeight(60)
f:SetFrameStrata("LOW")
f:SetMovable(true)
f:SetClampedToScreen(true)
f:Hide()
f:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
f:SetBackdropColor(0, 0, 0, 0.65)
f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
DN.tracker = f

local header = CreateFrame("Button", nil, f)
header:SetPoint("TOPLEFT", 6, -5)
header:SetPoint("TOPRIGHT", -6, -5)
header:SetHeight(16)
header:RegisterForDrag("LeftButton")
header:RegisterForClicks("AnyUp")
header:SetScript("OnDragStart", function()
	if not DN.opt.lockFrames then f:StartMoving() end
end)
-- Pin the tracker by its top-left corner so it grows downward as rows are added
-- (dragging leaves it anchored by whatever point the game picks, usually the center).
local function AnchorTopLeft()
	local left, top = f:GetLeft(), f:GetTop()
	if not left or not top then return end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	DN.db.pos.tracker = { "TOPLEFT", "BOTTOMLEFT", left, top }
end

header:SetScript("OnDragStop", function()
	f:StopMovingOrSizing()
	AnchorTopLeft()
end)
header:SetScript("OnClick", function(self, button)
	if button == "RightButton" then DN:ShowMenu(self) end
end)

local resetBtn = CreateFrame("Button", nil, header)
resetBtn:SetSize(14, 14)
resetBtn:SetPoint("RIGHT", 0, 0)
resetBtn:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
resetBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
resetBtn:SetScript("OnClick", function() StaticPopup_Show("INSTANCEGPS_RESET") end)
resetBtn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Start a new run")
	GameTooltip:AddLine("Clears this run's kills and timer (the instance itself isn't reset).", 1, 1, 1, true)
	GameTooltip:Show()
end)
resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT")
titleText:SetPoint("RIGHT", -70, 0)
titleText:SetJustifyH("LEFT")
local timerText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timerText:SetPoint("RIGHT", resetBtn, "LEFT", -3, 0)

local routeBtn = CreateFrame("Button", nil, f)
routeBtn:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
routeBtn:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
routeBtn:SetHeight(14)
routeBtn:RegisterForClicks("AnyUp")
local routeText = routeBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
routeText:SetAllPoints()
routeText:SetJustifyH("LEFT")
routeBtn:SetScript("OnClick", function(_, button)
	local inst = DN.inst
	if not inst or #inst.routes < 2 then return end
	local n = #inst.routes
	local i = DN.routeIndex or 1
	i = button == "RightButton" and ((i - 2) % n + 1) or (i % n + 1)
	DN:SetRoute(i, true)
end)
routeBtn:SetScript("OnEnter", function(self)
	local inst = DN.inst
	if not inst or #inst.routes < 2 then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Route / wing")
	GameTooltip:AddLine("Click to cycle. The route follows you automatically until you pick one.", 1, 1, 1, true)
	GameTooltip:Show()
end)
routeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local rows = {}

local function RowOnClick(self, button)
	local b = self.boss
	if not b then
		if self.route then DN:SetRoute(self.route, true) end
		return
	end
	if button == "RightButton" then
		if DN:IsKilled(b) then DN:UnmarkKilled(b) else DN:MarkKilled(b, "manual") end
	else
		DN:SetNavTarget(b)
	end
end

local function RowOnEnter(self)
	local b = self.boss
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	if b then
		GameTooltip:AddLine(b.name)
		local run = DN.run
		if run and run.killed[b.id] then
			GameTooltip:AddLine(("Killed at %s into the run"):format(DN.FormatTime(run.killed[b.id])), 0.3, 1, 0.3)
		end
		local diff = run and run.diff
		local here, total = diff and DN:BossKills(b, diff), DN:BossKills(b)
		if here then
			GameTooltip:AddLine(("Kills on %s: %d"):format(DN:StatLabel(b, diff), here), 1, 1, 1)
			if total ~= here then GameTooltip:AddLine(("Kills on all difficulties: %d"):format(total), 1, 1, 1) end
		elseif total then
			GameTooltip:AddLine(("Kills on all difficulties: %d"):format(total), 1, 1, 1)
		end
		if not b.x then GameTooltip:AddLine("No known position for this fight.", 1, 0.5, 0.3) end
		if b.noDeath then GameTooltip:AddLine("This fight ends without a kill; right-click if it isn't detected.", 0.8, 0.8, 0.8, true) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click: navigate here (again to go back to the route)", 0.6, 0.8, 1)
		GameTooltip:AddLine("Right-click: toggle killed", 0.6, 0.8, 1)
	else
		GameTooltip:AddLine("Switch to this wing")
	end
	GameTooltip:Show()
end

local function GetRow(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, f)
	r:SetHeight(ROW_H)
	r:RegisterForClicks("AnyUp")
	r:SetScript("OnClick", RowOnClick)
	r:SetScript("OnEnter", RowOnEnter)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.text:SetPoint("LEFT", 2, 0)
	r.text:SetPoint("RIGHT", -44, 0)
	r.text:SetJustifyH("LEFT")
	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.right:SetPoint("RIGHT", -2, 0)
	r.right:SetJustifyH("RIGHT")
	rows[i] = r
	return r
end

function DN:RefreshTracker()
	local inst, run = self.inst, self.run
	if not inst or not run or not self.opt.tracker or (self.opt.offHidesTracker and not self:NavOn()) then
		f:Hide()
		return
	end
	f:Show()
	local pos = self.db.pos.tracker
	if pos and pos[1] ~= "TOPLEFT" then AnchorTopLeft() end   -- old saved position, first showing
	f:SetScale(self.opt.trackerScale or 1)
	f:SetAlpha(self.opt.trackerAlpha or 1)
	titleText:SetText(inst.name .. (run.diffName and run.diffName ~= "" and (" |cffaaaaaa(" .. run.diffName .. ")|r") or ""))

	local route = self:ActiveRoute() or { order = {}, stops = {} }
	local y = -24
	if #inst.routes > 1 then
		routeText:SetText(("Route: |cffffffff%s|r  |cff888888(%d/%d, click to switch)|r"):format(route.name or "?", self.routeIndex or 1, #inst.routes))
		routeBtn:Show()
		y = y - 14
	else
		routeBtn:Hide()
	end

	local next = self:NextBoss()
	local shown, done, total = 0, 0, 0
	local function add(text, right, boss, routeIdx)
		shown = shown + 1
		local r = GetRow(shown)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 6, y)
		r:SetPoint("TOPRIGHT", -6, y)
		r.text:SetText(text)
		r.right:SetText(right or "")
		r.boss, r.route = boss, routeIdx
		r:Show()
		y = y - ROW_H
	end

	local inRoute = {}
	for k, bi in ipairs(route.order) do
		local b = inst.bosses[bi]
		inRoute[b] = true
		if self:BossAvailable(b) then
			total = total + 1
			local killedAt = run.killed[b.id]
			local text, right
			if killedAt then
				done = done + 1
				text = ("%s |cff888888%d. %s|r"):format(CHECK, k, b.name)
				right = "|cff888888" .. DN.FormatTime(killedAt) .. "|r"
			elseif b == next then
				local col = self.navTarget == b and "|cff66ccff" or "|cffffd100"
				text = ("%s %s%d. %s|r"):format(SKULL, col, k, b.name)
				right = self.remaining and self.px and ("%d yd"):format(self.remaining) or ""
			else
				text = ("|TInterface\\Buttons\\UI-CheckBox-Up:12:12:0:0|t |cffdddddd%d. %s|r"):format(k, b.name)
				if not b.x then right = "|cffff8844?|r" end
			end
			add(text, right, b)
		end
	end
	-- bosses outside the active route: summarise other wings, list stray bosses
	if #inst.routes > 1 then
		for ri, r in ipairs(inst.routes) do
			if ri ~= (self.routeIndex or 1) then
				local d, t = 0, 0
				for _, bi in ipairs(r.order) do
					local b = inst.bosses[bi]
					if self:BossAvailable(b) then
						t = t + 1
						if run.killed[b.id] then d = d + 1 end
					end
				end
				if t > 0 and not (r.order[1] and inRoute[inst.bosses[r.order[1]]]) then
					add(("|cff888888%s wing|r"):format(r.name or ("Route " .. ri)), ("|cff888888%d/%d|r"):format(d, t), nil, ri)
				end
			end
		end
	end
	for _, b in ipairs(inst.bosses) do
		local listed = inRoute[b]
		if not listed then
			for _, r in ipairs(inst.routes) do
				for _, bi in ipairs(r.order) do if inst.bosses[bi] == b then listed = true end end
			end
		end
		if not listed and self:BossAvailable(b) then
			local killed = run.killed[b.id]
			add(("%s |cffaaaaaa%s|r"):format(killed and CHECK or "|TInterface\\Buttons\\UI-CheckBox-Up:12:12:0:0|t", b.name),
				killed and ("|cff888888" .. DN.FormatTime(killed) .. "|r") or (not b.x and "|cffff8844?|r" or ""), b)
		end
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	self.trackerDone, self.trackerTotal = done, total
	f:SetHeight(-y + 6)
end

-- timer + progress text, once a second
local tick = 0
f:SetScript("OnUpdate", function(_, elapsed)
	tick = tick + elapsed
	if tick < 1 then return end
	tick = 0
	local run = DN.run
	if not run then return end
	local t = run.cleared or (time() - run.started)
	timerText:SetText(("%s%d/%d|r %s"):format(run.cleared and "|cff33ff33" or "|cffffffff",
		DN.trackerDone or 0, DN.trackerTotal or 0, DN.FormatTime(t)))
	-- refresh the distance on the next-boss row
	DN:RefreshTracker()
end)

DN:On("LOADED", function()
	local pos = DN.db.pos.tracker
	f:ClearAllPoints()
	if pos then
		f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		-- positions saved before the top-left anchoring: convert, keeping the frame where it is
		if pos[1] ~= "TOPLEFT" then AnchorTopLeft() end
	else
		-- left edge, just below the screen's middle-top: room above for other addons' lists,
		-- and a 15-boss raid still ends well above the chat frame
		f:SetPoint("TOPLEFT", UIParent, "LEFT", 12, 70)
	end
end)
DN:On("RUN_CHANGED", function() DN:RefreshTracker() end)
DN:On("INSTANCE_CHANGED", function() DN:RefreshTracker() end)
