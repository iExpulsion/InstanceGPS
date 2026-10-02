-- InstanceGPS options menu, slash commands and statistics output.
local _, ns = ...
local DN = ns.DN
local floor = math.floor

StaticPopupDialogs["INSTANCEGPS_RESET"] = {
	text = "Reset InstanceGPS progress for this instance?\n(The instance itself is not reset.)",
	button1 = YES, button2 = NO,
	OnAccept = function() DN:ResetRun() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

local function Toggle(key, after)
	return function()
		DN.opt[key] = not DN.opt[key]
		if after then after() end
	end
end

local function ApplyVisibility()
	DN:UpdateArrowVisibility()
	DN:UpdatePathViews()
	DN:RefreshTracker()
	if WorldMapFrame:IsShown() then DN:RefreshMap() end
end

local menuFrame = CreateFrame("Frame", "InstanceGPSMenu", UIParent, "UIDropDownMenuTemplate")

function DN:ShowMenu(anchor)
	local o = self.opt
	local menu = {
		{ text = "InstanceGPS", isTitle = true, notCheckable = true },
		{ text = "Show Arrow", checked = o.arrow, func = Toggle("arrow", ApplyVisibility), keepShownOnClick = true },
		{ text = "Show Boss Tracker", checked = o.tracker, func = Toggle("tracker", ApplyVisibility), keepShownOnClick = true },
		{ text = "Route on the Dungeon Map", checked = o.mapOverlay, func = Toggle("mapOverlay", ApplyVisibility), keepShownOnClick = true },
		{ text = "Path on the Minimap", checked = o.pathMinimap, func = Toggle("pathMinimap", ApplyVisibility), keepShownOnClick = true },
		{ text = "Path HUD Around the Character", checked = o.pathHud, func = Toggle("pathHud", ApplyVisibility), keepShownOnClick = true },
		{ text = "3D Path View", checked = o.pathView, func = Toggle("pathView", ApplyVisibility), keepShownOnClick = true },
		{ text = "Hard-Mode Routes", checked = o.hardModes, func = Toggle("hardModes", function() DN:ApplyHardModes() ApplyVisibility() end), keepShownOnClick = true },
		{ text = "Announce Kills in Chat", checked = o.announce, func = Toggle("announce"), keepShownOnClick = true },
		{ text = "Lock Frames", checked = o.lockFrames, func = Toggle("lockFrames"), keepShownOnClick = true },
	}
	local scales = {}
	for _, s in ipairs({ 0.75, 1, 1.25, 1.5 }) do
		table.insert(scales, { text = ("%d%%"):format(s * 100), checked = o.arrowScale == s,
			func = function() o.arrowScale = s ApplyVisibility() end })
	end
	table.insert(menu, { text = "Arrow Size", hasArrow = true, notCheckable = true, menuList = scales })
	local tscales = {}
	for _, s in ipairs({ 0.8, 0.9, 1, 1.1, 1.25 }) do
		table.insert(tscales, { text = ("%d%%"):format(s * 100), checked = o.trackerScale == s,
			func = function() o.trackerScale = s ApplyVisibility() end })
	end
	table.insert(menu, { text = "Tracker Size", hasArrow = true, notCheckable = true, menuList = tscales })
	local inst = self.inst
	if inst and #inst.routes > 1 then
		local routes = {}
		for i, r in ipairs(inst.routes) do
			table.insert(routes, { text = r.name or ("Route " .. i), checked = self.routeIndex == i,
				func = function() DN:SetRoute(i, true) end })
		end
		table.insert(routes, { text = "Follow Me (Automatic)", checked = not self.routeManual,
			func = function() DN.routeManual = false end })
		table.insert(menu, { text = "Route / Wing", hasArrow = true, notCheckable = true, menuList = routes })
	end
	if inst then
		table.insert(menu, { text = "Reset Progress for This Run", notCheckable = true,
			func = function() StaticPopup_Show("INSTANCEGPS_RESET") end })
		local off = self:IsOff(inst.mapId)
		table.insert(menu, { text = "Navigation in " .. inst.name, checked = not off, keepShownOnClick = true,
			func = function() DN:SetOff(inst.mapId, not DN:IsOff(inst.mapId)) end })
	end
	table.insert(menu, { text = "Instances...", notCheckable = true, func = function() DN:OpenOptions(true) end })
	table.insert(menu, { text = "All Options...", notCheckable = true, func = function() DN:OpenOptions() end })
	table.insert(menu, { text = CLOSE, notCheckable = true, func = function() CloseDropDownMenus() end })
	EasyMenu(menu, menuFrame, anchor or "cursor", 0, 0, "MENU")
end

-------------------------------------------------------------------------------- stats

-- Lifetime kills from the character's achievement statistics. Without a filter: one line per
-- instance with the final boss's kills per difficulty; with one: every boss of the matches.
function DN:PrintStats(filter)
	local list = {}
	for _, inst in pairs(ns.Instances) do
		if not filter or inst.name:lower():find(filter, 1, true) then table.insert(list, inst) end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	local function counts(b)
		local parts, diffs = {}, {}
		for d in pairs(b.stats) do table.insert(diffs, d) end
		table.sort(diffs)
		for _, d in ipairs(diffs) do
			local k = DN:BossKills(b, d)
			if k > 0 or filter then table.insert(parts, ("%s %d"):format(DN:StatLabel(b, d), k)) end
		end
		return table.concat(parts, ", ")
	end
	local shown, untracked = 0, {}
	for _, inst in ipairs(list) do
		local tracked, killed, last = 0, 0, nil
		for _, b in ipairs(inst.bosses) do
			if b.stats then
				tracked, last = tracked + 1, b
				if self:BossKills(b) > 0 then killed = killed + 1 end
			end
		end
		if tracked == 0 then table.insert(untracked, inst.name) end
		if tracked > 0 and (killed > 0 or filter) then
			shown = shown + 1
			if filter then
				self:Print("|cffffd100%s|r (from your statistics):", inst.name)
				for _, b in ipairs(inst.bosses) do
					local k = b.stats and self:BossKills(b)
					DEFAULT_CHAT_FRAME:AddMessage(("   %s%s|r  %s"):format(k and k > 0 and "|cff66ff66" or "|cff888888", b.name,
						b.stats and counts(b) or "no statistic"))
				end
			else
				local c = counts(last)
				self:Print("|cffffd100%s|r: %d/%d bosses killed%s", inst.name, killed, tracked,
					c ~= "" and ("; " .. last.name .. ": " .. c) or "")
			end
		end
	end
	if filter and #untracked > 0 then
		self:Print("The game keeps no kill statistics for %s.", table.concat(untracked, ", "))
	end
	if shown == 0 and not (filter and #untracked > 0) then
		self:Print("No boss kills in your statistics%s yet.", filter and (" for '" .. filter .. "'") or "")
	elseif not filter then
		DEFAULT_CHAT_FRAME:AddMessage("   Only bosses with a statistic count; /igps stats <instance> lists them all.")
	end
end

-- Saved lockouts together with the kills we recorded for them.
function DN:PrintSaved()
	RequestRaidInfo()
	local n = GetNumSavedInstances()
	if n == 0 then self:Print("No saved instances.") return end
	for i = 1, n do
		local name, id, reset, diff, locked, _, _, _, _, diffName = GetSavedInstanceInfo(i)
		if locked then
			local inst
			for _, x in pairs(ns.Instances) do if x.name:lower() == name:lower() then inst = x end end
			local run = inst and self.char.runs[inst.mapId]
			local line = ("|cffffd100%s|r %s - resets in %s"):format(name, diffName or "", SecondsToTime(reset))
			if run and run.lockId == id then
				local done, names = 0, {}
				for _, b in ipairs(inst.bosses) do
					if run.killed[b.id] then done = done + 1 table.insert(names, b.name) end
				end
				line = line .. (": %d/%d (%s)"):format(done, #inst.bosses, table.concat(names, ", "))
			end
			self:Print(line)
		end
	end
end

-------------------------------------------------------------------------------- slash

SLASH_INSTANCEGPS1 = "/igps"
SLASH_INSTANCEGPS2 = "/instancegps"
SlashCmdList.INSTANCEGPS = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local o = DN.opt
	if cmd == "" or cmd == "tracker" then
		o.tracker = not o.tracker
		ApplyVisibility()
		if not DN.inst then DN:Print("Tracker %s (shows inside dungeons and raids).", o.tracker and "on" or "off") end
	elseif cmd == "arrow" then
		o.arrow = not o.arrow
		ApplyVisibility()
	elseif cmd == "map" then
		o.mapOverlay = not o.mapOverlay
		ApplyVisibility()
	elseif cmd == "lock" then
		o.lockFrames = not o.lockFrames
		DN:Print("Frames %s.", o.lockFrames and "locked" or "unlocked")
	elseif cmd == "reset" then
		if DN.inst then StaticPopup_Show("INSTANCEGPS_RESET") else DN:Print("Not in a dungeon or raid.") end
	elseif cmd == "route" or cmd == "wing" then
		if not DN.inst then return end
		local inst = DN.inst
		for i, r in ipairs(inst.routes) do
			if r.name and r.name:lower():find(rest:lower(), 1, true) then DN:SetRoute(i, true) return end
		end
		if #inst.routes > 1 then DN:SetRoute((DN.routeIndex or 1) % #inst.routes + 1, true) end
	elseif cmd == "next" then
		local b = DN:NextBoss()
		if b and DN.navTarget ~= b then DN:MarkKilled(b, "manual") end
	elseif cmd == "stats" then
		DN:PrintStats(rest ~= "" and rest:lower() or nil)
	elseif cmd == "saved" then
		DN:PrintSaved()
	elseif cmd == "menu" then
		DN:ShowMenu()
	elseif cmd == "config" or cmd == "options" then
		DN:OpenOptions()
	elseif cmd == "hud" or cmd == "minimap" or cmd == "view" then
		local key = cmd == "hud" and "pathHud" or cmd == "minimap" and "pathMinimap" or "pathView"
		o[key] = not o[key]
		ApplyVisibility()
	elseif cmd == "resetpos" then
		DN.db.pos = {}
		ReloadUI()
	elseif cmd == "record" then
		DN:RecordCommand(rest)
	elseif cmd == "off" or cmd == "on" then
		local here = DN.inst
		if not here then
			DN:Print("Not in a dungeon or raid. Interface > AddOns > InstanceGPS > Instances lists them all.")
		else
			DN:SetOff(here.mapId, cmd == "off")
			DN:Print("Navigation %s in %s.", cmd, here.name)
		end
	elseif cmd == "instances" then
		DN:OpenOptions(true)
	else
		DN:Print("%s commands:", DN:Title())
		local lines = {
			"/igps - toggle the boss tracker",
			"/igps arrow - toggle the navigation arrow",
			"/igps map - toggle the route on the dungeon map",
			"/igps route [name] - switch wing/route (Library, Armory, East, ...)",
			"/igps next - mark the next boss as killed (if detection missed it)",
			"/igps reset - forget this run's kills",
			"/igps stats [instance] - lifetime kills from your achievement statistics",
			"/igps saved - raid/heroic lockouts with recorded kills",
			"/igps menu - quick options menu (also right-click the tracker title or arrow)",
			"/igps options - all options (Interface > AddOns > InstanceGPS)",
			"/igps minimap | hud | view - toggle the path on the minimap / around you / 3D view",
			"/igps lock - lock/unlock frames",  "/igps resetpos - reset frame positions",
			"/igps off | on - switch navigation (arrow, paths, map route, hints) off or on in this instance",
			"/igps instances - choose the instances with navigation, by expansion",
			"/igps record - record a route to fix or add one for your server (/igps record for more)",
		}
		for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
	end
end

-------------------------------------------------------------------------------- Interface Options panel

local panel = CreateFrame("Frame", "InstanceGPSOptions", UIParent)
panel.name = "InstanceGPS"
panel:Hide()
local controls = {}

local function Header(text, y)
	local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	h:SetPoint("TOPLEFT", 16, y)
	h:SetText(text)
end

local function Check(key, label, tip, x, y, after)
	local name = "InstanceGPSOpt_" .. key
	local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x, y)
	_G[name .. "Text"]:SetText(label)
	cb.tooltipText = label
	cb.tooltipRequirement = tip
	cb:SetScript("OnClick", function(self)
		DN.opt[key] = self:GetChecked() and true or false
		if after then after() end
		ApplyVisibility()
	end)
	cb.Refresh = function() cb:SetChecked(DN.opt[key]) end
	table.insert(controls, cb)
	return cb
end

local function Slider(key, label, lo, hi, step, fmt, x, y)
	local name = "InstanceGPSOpt_" .. key
	local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", x, y)
	s:SetWidth(180)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	_G[name .. "Low"]:SetText(fmt:format(lo))
	_G[name .. "High"]:SetText(fmt:format(hi))
	local text = _G[name .. "Text"]
	s:SetScript("OnValueChanged", function(self, v)
		v = floor(v / step + 0.5) * step
		text:SetText(label .. ": " .. fmt:format(v))
		if DN.opt[key] ~= v then
			DN.opt[key] = v
			ApplyVisibility()
		end
	end)
	s.Refresh = function()
		s:SetValue(DN.opt[key])
		text:SetText(label .. ": " .. fmt:format(DN.opt[key]))
	end
	table.insert(controls, s)
	return s
end

local title
local function BuildPanel()
	title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)

	Header("General", -46)
	Check("arrow", "Navigation Arrow", "Points along the route to the next boss.", 16, -64)
	Check("tracker", "Boss Tracker", "Bosses, kills and the run timer.", 16, -90)
	Check("mapOverlay", "Route on the Dungeon Map", "Draws the route and numbered bosses on the world map.", 16, -116)
	Check("announce", "Announce Kills in Chat", nil, 16, -142)
	Check("hardModes", "Hard-Mode Routes",
		"Where a hard mode changes the way through an instance, follow it: in The Obsidian Sanctum, go straight to Sartharion and leave the drakes up.",
		330, -168, function() DN:ApplyHardModes() end)
	Check("lockFrames", "Lock Frames", "Stops the arrow, tracker and 3D view from being dragged.", 16, -168)
	Slider("arrowScale", "Arrow Size", 0.5, 2, 0.05, "%.2f", 330, -74)
	Slider("trackerScale", "Tracker Size", 0.5, 2, 0.05, "%.2f", 330, -120)

	Header("Path to Follow", -206)
	Check("pathMinimap", "Path on the Minimap", "Dots along the route on the minimap, with the boss or teleporter at the end.", 16, -224)
	Check("pathHud", "Path HUD Around the Character",
		"A see-through radar in the middle of the screen with the path under your feet, turned to the way you face.", 16, -250)
	Check("hudHideCombat", "Hide the HUD in Combat", nil, 40, -276)
	Check("pathView", "3D Path View",
		"A small panel showing the path ahead in perspective. Drag to move, right-click for options.", 16, -302)
	Slider("hudSize", "HUD Size", 160, 500, 10, "%d px", 330, -234)
	Slider("hudRange", "HUD Range", 15, 100, 5, "%d yd", 330, -280)
	Slider("hudAlpha", "HUD Opacity", 0.1, 1, 0.05, "%.2f", 330, -326)
	Slider("hudOffset", "HUD Height", -250, 250, 5, "%d", 330, -372)
	Slider("pathViewScale", "3D View Size", 0.6, 2, 0.05, "%.2f", 16, -352)

	local reset = DN.Button(panel, "Reset Frame Positions", function() DN.db.pos = {} ReloadUI() end)
	reset:SetPoint("TOPLEFT", 16, -410)
end

panel:SetScript("OnShow", function()
	title:SetText(DN:Title())   -- server modules register after this panel is built
	for _, c in ipairs(controls) do c.Refresh() end
end)

-------------------------------------------------------------------------------- Instances panel

-- Where navigation (arrow, path views, route on the map, hints) is on: a tick per instance, by
-- expansion, dungeons and raids side by side. The list is made the first time it's shown, once
-- server modules have added or removed instances.
local instPanel = CreateFrame("Frame", "InstanceGPSInstances", UIParent)
instPanel.name = "Instances"
instPanel.parent = "InstanceGPS"
instPanel:Hide()
local instChecks = {}
local EXPANSIONS = { [0] = "Classic", [1] = "The Burning Crusade", [2] = "Wrath of the Lich King" }

local function SetMany(checks, on)
	DN.db.off = DN.db.off or {}
	for _, cb in ipairs(checks) do
		DN.db.off[cb.mapId] = not on or nil
		cb:SetChecked(on)
	end
	DN:NavChanged()
end

local function SmallButton(parent, text, w, fn)
	return DN.Button(parent, text, fn, w)
end

local SHORT = { [0] = "Classic", [1] = "Burning Crusade", [2] = "Wrath", [99] = "Other" }

local function BuildInstances()
	local t = instPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText("Instances")
	local sub = instPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", 16, -40)
	sub:SetWidth(440)
	sub:SetJustifyH("LEFT")
	sub:SetText("Navigation (the arrow, path views, route on the map and hints) works in the instances ticked here. "
		.. "In the others the boss tracker still runs.")
	SmallButton(instPanel, "All On", 70, function() SetMany(instChecks, true) end):SetPoint("TOPRIGHT", -92, -16)
	SmallButton(instPanel, "All Off", 70, function() SetMany(instChecks, false) end):SetPoint("TOPRIGHT", -16, -16)
	local name = "InstanceGPSOpt_offHidesTracker"
	local hide = CreateFrame("CheckButton", name, instPanel, "InterfaceOptionsCheckButtonTemplate")
	hide:SetPoint("TOPLEFT", 12, -66)
	_G[name .. "Text"]:SetText("Also Hide the Boss Tracker Where Navigation Is Off")
	hide:SetScript("OnClick", function(self)
		DN.opt.offHidesTracker = self:GetChecked() and true or false
		DN:NavChanged()
	end)
	hide.Refresh = function() hide:SetChecked(DN.opt.offHidesTracker) end
	instPanel.hide = hide

	-- expansion -> { party = {...}, raid = {...} }; anything a server module added without one: "Other"
	local groups, order = {}, {}
	for mapId, inst in pairs(ns.Instances) do
		local e = EXPANSIONS[inst.exp] and inst.exp or 99
		if not groups[e] then
			groups[e] = { party = {}, raid = {}, checks = {} }
		end
		table.insert(groups[e][inst.type == "raid" and "raid" or "party"], { mapId = mapId, name = inst.name })
	end
	for _, e in ipairs({ 0, 1, 2, 99 }) do
		if groups[e] then order[#order + 1] = e end
	end

	-- On / Off per expansion, in a row that doesn't scroll (buttons in a scrolling list land on
	-- fractions of a pixel, and their text wobbles as it scrolls)
	local x = 16
	for _, e in ipairs(order) do
		local checks = groups[e].checks
		local label = instPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("TOPLEFT", x, -101)
		label:SetText(SHORT[e])
		x = x + label:GetStringWidth() + 6
		local on = SmallButton(instPanel, "On", 44, function() SetMany(checks, true) end)
		on:SetPoint("TOPLEFT", x, -96)
		local off = SmallButton(instPanel, "Off", 44, function() SetMany(checks, false) end)
		off:SetPoint("TOPLEFT", on, "TOPRIGHT", 2, 0)
		x = x + on:GetWidth() + 2 + off:GetWidth() + 20
	end

	local scroll = CreateFrame("ScrollFrame", "InstanceGPSInstancesScroll", instPanel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -126)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(560, 10)
	scroll:SetScrollChild(child)

	local y = 0
	for _, e in ipairs(order) do
		local g = groups[e]
		local h = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		h:SetPoint("TOPLEFT", 4, -y - 3)
		h:SetText(EXPANSIONS[e] or "Other")
		y = y + 22
		local rows = 0
		for col, kind in ipairs({ "party", "raid" }) do
			local list = g[kind]
			table.sort(list, function(a, b) return a.name < b.name end)
			local label = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			label:SetPoint("TOPLEFT", (col - 1) * 280 + 8, -y)
			label:SetText(kind == "raid" and "Raids" or "Dungeons")
			for k, i in ipairs(list) do
				local cname = "InstanceGPSInst_" .. i.mapId
				local cb = CreateFrame("CheckButton", cname, child, "InterfaceOptionsCheckButtonTemplate")
				cb:SetPoint("TOPLEFT", (col - 1) * 280, -(y + 14 + (k - 1) * 22))
				_G[cname .. "Text"]:SetText(i.name)
				cb.mapId = i.mapId
				cb:SetScript("OnClick", function(self) DN:SetOff(self.mapId, not self:GetChecked()) end)
				g.checks[#g.checks + 1] = cb
				instChecks[#instChecks + 1] = cb
			end
			rows = math.max(rows, #list)
		end
		y = y + 14 + rows * 22 + 14
	end
	child:SetHeight(y)
end

instPanel:SetScript("OnShow", function()
	if #instChecks == 0 then BuildInstances() end
	for _, cb in ipairs(instChecks) do cb:SetChecked(not DN:IsOff(cb.mapId)) end
	instPanel.hide.Refresh()
end)

DN:On("LOADED", function()
	BuildPanel()
	InterfaceOptions_AddCategory(panel)
	InterfaceOptions_AddCategory(instPanel)
end)

-- toInstances: open the Instances page instead of the main one
function DN:OpenOptions(toInstances)
	local p = toInstances and instPanel or panel
	-- called twice: the first call only opens the frame on some clients
	InterfaceOptionsFrame_OpenToCategory(p)
	InterfaceOptionsFrame_OpenToCategory(p)
end
