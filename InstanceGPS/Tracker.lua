-- InstanceGPS tracker: the boss list for the current instance, in the style kit's window look.
local _, ns = ...
local DN, S = ns.DN, ns.Style

local ROW_H, WIDTH = 16, 230
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:12:12:0:0|t"
-- the room between the frame's edge and its rows: the skin's window edge (0 for Material) plus a little
local inset = 6

local f = CreateFrame("Frame", "InstanceGPSTracker", UIParent)
f:SetWidth(WIDTH)
f:SetHeight(60)
f:SetFrameStrata("LOW")
f:SetMovable(true)
f:SetClampedToScreen(true)
f:Hide()
DN.tracker = f

local header = CreateFrame("Button", nil, f)
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
header:SetScript("OnEnter", function(self)
	local inst, run = DN.inst, DN.run
	if inst then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(inst.name)
		if run and run.diffName and run.diffName ~= "" then GameTooltip:AddLine(run.diffName, 1, 1, 1) end
		DN.HintLines(GameTooltip, not DN.opt.lockFrames and "Drag: Move", "Right-Click: Options")
		GameTooltip:Show()
	end
end)
header:SetScript("OnLeave", function() GameTooltip:Hide() end)

local resetBtn = CreateFrame("Button", nil, header)
resetBtn:SetSize(14, 14)
resetBtn:SetPoint("RIGHT", 0, 0)
resetBtn:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
resetBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
resetBtn:SetScript("OnClick", function() StaticPopup_Show("INSTANCEGPS_RESET") end)
resetBtn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Start a New Run")
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
	GameTooltip:AddLine("Route / Wing")
	GameTooltip:AddLine("The route follows you automatically until you pick one.", 1, 1, 1, true)
	DN.HintLines(GameTooltip, "Click: Next Route", "Right-Click: Previous Route")
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
	local b, note = self.boss, self.note
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
		DN:Fire("BOSS_TOOLTIP", b, GameTooltip)
		GameTooltip:AddLine(" ")
		DN.HintLines(GameTooltip, DN.navTarget == b and "Click: Back to the Route" or "Click: Navigate Here",
			DN:IsKilled(b) and "Right-Click: Mark Alive" or "Right-Click: Mark Killed")
	elseif note then
		if note.tooltip then note.tooltip(GameTooltip) else GameTooltip:AddLine(note.text) end
	else
		DN.HintLines(GameTooltip, "Click: Switch to This Wing")
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
	S.Highlight(r)
	r.text = S.Text(r, "small")
	r.text:SetPoint("LEFT", 2, 0)
	r.text:SetPoint("RIGHT", -44, 0)
	r.text:SetJustifyH("LEFT")
	r.right = S.Text(r, "small")
	r.right:SetPoint("RIGHT", -2, 0)
	r.right:SetJustifyH("RIGHT")
	rows[i] = r
	return r
end

-- The difficulty after the instance name, shorter than the client's own ("5 Player (Heroic)"):
-- Normal or Heroic in a dungeon, the size (and Heroic) in a raid, and nothing where an instance
-- has only one difficulty. A difficulty the client doesn't have (a server's own) keeps its name.
local function DiffLabel(inst, run)
	local several = false
	for _, b in ipairs(inst.bosses) do
		if b.diff > 1 then several = true end
	end
	local d = run.diff or 1
	local _, _, _, _, maxPlayers = GetInstanceInfo()
	local name = run.diffName ~= "" and run.diffName or nil
	if d > 4 or (inst.type == "party" and d > 2) then
		return name
	elseif not several and d == 1 then
		return nil
	elseif inst.type == "party" then
		return d == 2 and "Heroic" or "Normal"
	end
	return maxPlayers and maxPlayers > 0 and (maxPlayers .. (d >= 3 and " Heroic" or "")) or name
end

-- Rows a server module adds under the boss list, by key: { text =, right =, tooltip = function(tooltip) }.
-- nil removes the row.
DN.trackerNotes = {}
function DN:SetTrackerNote(key, note)
	self.trackerNotes[key] = note
	self:RefreshTracker()
end

-- Short marks a server module puts after boss names, by key: { [boss] = text }. nil removes them.
DN.bossMarks = {}
function DN:SetBossMarks(key, marks)
	self.bossMarks[key] = marks
	self:RefreshTracker()
end

local function Marks(b)
	local s = ""
	for _, marks in pairs(DN.bossMarks) do
		if marks[b] then s = s .. " " .. marks[b] end
	end
	return s
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
	local label = DiffLabel(inst, run)
	titleText:SetText(inst.name .. (label and (" |cffaaaaaa(" .. label .. ")|r") or ""))

	local route = self:ActiveRoute() or { order = {}, stops = {} }
	local y = -(inset - 1) - 19
	if #inst.routes > 1 then
		routeText:SetText(("Route: |cffffffff%s|r  (%d/%d)"):format(route.name or "?", self.routeIndex or 1, #inst.routes))
		routeBtn:Show()
		y = y - 14
	else
		routeBtn:Hide()
	end

	local next = self:NextBoss()
	local shown, done, total = 0, 0, 0
	local function add(text, right, boss, routeIdx, note)
		shown = shown + 1
		local r = GetRow(shown)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", inset, y)
		r:SetPoint("TOPRIGHT", -inset, y)
		r.text:SetText(text)
		r.right:SetText(right or "")
		r.boss, r.route, r.note = boss, routeIdx, note
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
			add(text .. Marks(b), right, b)
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
			add(("%s |cffaaaaaa%s|r"):format(killed and CHECK or "|TInterface\\Buttons\\UI-CheckBox-Up:12:12:0:0|t", b.name) .. Marks(b),
				killed and ("|cff888888" .. DN.FormatTime(killed) .. "|r") or (not b.x and "|cffff8844?|r" or ""), b)
		end
	end
	local keys = {}
	for key in pairs(self.trackerNotes) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local note = self.trackerNotes[key]
		add(note.text, note.right, nil, nil, note)
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	self.trackerDone, self.trackerTotal = done, total
	f:SetHeight(-y + inset)
end

-- timer + progress text, once a second
local tick = 0
f:SetScript("OnUpdate", function(_, elapsed)
	tick = tick + elapsed
	local run = DN.run
	if tick >= 1 and run then
		tick = 0
		local t = run.cleared or (time() - run.started)
		timerText:SetText(("%s%d/%d|r %s"):format(run.cleared and "|cff33ff33" or "|cffffffff",
			DN.trackerDone or 0, DN.trackerTotal or 0, DN.FormatTime(t)))
		-- refresh the distance on the next-boss row
		DN:RefreshTracker()
	end
end)

-- The look comes from the skin, which goes on as the settings load
DN:On("LOADED", function()
	local C = S.colors
	inset = 6 + S.metrics.edge
	S.Frame(f, "window")
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", inset, -(inset - 1))
	header:SetPoint("TOPRIGHT", -inset, -(inset - 1))
	S.SetFont(titleText, "normal")
	titleText:SetTextColor(unpack(C.heading))
	S.SetFont(timerText, "small")
	timerText:SetTextColor(unpack(C.text))
	S.SetFont(routeText, "small")
	routeText:SetTextColor(unpack(C.muted))
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
