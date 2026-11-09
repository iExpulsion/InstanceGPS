-- The options window: a sidebar of pages in groups, each page sections of settings that apply as they change, with
-- a line under each saying what it does. /igps options, the right-click menu and Interface Options > AddOns >
-- InstanceGPS open it. Server modules' options (InstanceGPS:ModuleOptions) get pages of their own.
local _, ns = ...
local DN, S = ns.DN, ns.Style
local C = S.colors

local O = {}
DN.Options = O

local W, H, NAV_H = 640, 480, 26
local ROW_H, PLAIN_H, SECTION_H, CONTROL_W, INDENT = 40, 30, 30, 200, 16
-- a page's width inside its padding and scroll bar, less a few pixels: the scroll frame clips at its edge, and a
-- check box's outline reaches just past its bounds
local CLIP_MARGIN = 4
local NAV_W = DN.Window.SIDEBAR_W
local CONTENT_W = W - NAV_W - 2 * S.PAD - 10 - CLIP_MARGIN
local GROUP_ORDER = { "Guide", "Bosses", "Server Modules", "Other" }
-- a dropdown's menu doesn't scroll: longer lists of choices open a searchable picker instead
local PICKER_AFTER = 12

local frame, current

------------------------------------------------------------------------ the settings

local function Apply()
	DN:ApplyOptions()
end

local function Field(field, apply)
	return function() return DN.opt[field] end, function(v)
		DN.opt[field] = v
		apply()
	end, function()
		DN.opt[field] = DN.defaults[field]
		apply()
	end
end

-- A check, slider or dropdown on one of DN.opt's fields, applied by `apply` (default: everything) after a change;
-- Reset This Page puts back DN.defaults
local function Check(label, tip, field, apply, enabledIf)
	local get, set, reset = Field(field, apply or Apply)
	return { kind = "check", label = label, tip = tip, enabledIf = enabledIf, get = get, set = set, reset = reset }
end

-- `scale` turns the stored value into the shown one (100 for a fraction shown as a percent)
local function Slider(label, tip, field, min, max, step, format, enabledIf, scale)
	local k = scale or 1
	local get, set, reset = Field(field, Apply)
	return {
		kind = "slider", label = label, tip = tip, enabledIf = enabledIf, min = min, max = max, step = step,
		format = format, reset = reset,
		get = function() return math.floor(get() * k + 0.5) end,
		set = function(v) set(v / k) end,
	}
end

local function Section(label)
	return { kind = "section", label = label }
end

-- style: the button kind ("secondary" unless given, "danger" for one that undoes settings)
local function Button(label, text, tip, action, style)
	return { kind = "button", label = label, text = text, tip = tip, set = action, style = style }
end

local function Indent(setting)
	setting.indent = true
	return setting
end

local function Percent(v)
	return v .. "%"
end

local function Yards(v)
	return v .. " yd"
end

local function Pixels(v)
	return v .. " px"
end

local function On(field)
	return function() return DN.opt[field] end
end

local function HardModesChanged()
	DN:ApplyHardModes()
	Apply()
end

local function ResetFramePositions()
	DN.db.pos = {}
	ReloadUI()
end

O.PAGES = {
	{
		key = "arrow", title = "Arrow", group = "Guide",
		settings = {
			Section("Show"),
			Check("Navigation Arrow", "Points along the route to the next boss.", "arrow"),
			Indent(Check("Patrol Warnings",
				"Under the arrow, names the patrols whose path crosses the route where you are, so you can wait for them to pass.",
				"patrols", nil, On("arrow"))),
			Section("Size"),
			Slider("Arrow Size", "How big the arrow and its lines are.", "arrowScale", 50, 200, 5, Percent, On("arrow"), 100),
		},
	},
	{
		key = "route", title = "Route", group = "Guide",
		settings = {
			Section("Dungeon Map"),
			Check("Route on the Dungeon Map", "Draws the route and numbered bosses on the world map.", "mapOverlay"),
			Section("Routes"),
			Check("Hard-Mode Routes",
				"Where a hard mode changes the way through an instance, follow it: in The Obsidian Sanctum, go straight to Sartharion and leave the drakes up.",
				"hardModes", HardModesChanged),
		},
	},
	{
		key = "path", title = "Path Views", group = "Guide",
		settings = {
			Section("Minimap"),
			Check("Path on the Minimap", "Dots along the route on the minimap, with the boss or teleporter at the end.",
				"pathMinimap"),
			Section("HUD"),
			Check("Path HUD Around the Character",
				"A see-through radar in the middle of the screen with the path under your feet, turned to the way you face.",
				"pathHud"),
			Indent(Check("Hide the HUD in Combat", nil, "hudHideCombat", nil, On("pathHud"))),
			Indent(Slider("HUD Size", "How wide the HUD is.", "hudSize", 160, 500, 10, Pixels, On("pathHud"))),
			Indent(Slider("HUD Range", "How far around you the HUD shows the path.", "hudRange", 15, 100, 5, Yards,
				On("pathHud"))),
			Indent(Slider("HUD Opacity", "How solid the HUD is.", "hudAlpha", 10, 100, 5, Percent, On("pathHud"), 100)),
			Indent(Slider("HUD Height", "How far above or below the middle of the screen the HUD sits.", "hudOffset",
				-250, 250, 5, nil, On("pathHud"))),
			Section("3D View"),
			Check("3D Path View",
				"A small panel showing the path ahead in perspective. Drag to move, right-click for options.", "pathView"),
			Indent(Slider("3D View Size", "How big the panel is.", "pathViewScale", 60, 200, 5, Percent, On("pathView"),
				100)),
		},
	},
	{
		key = "tracker", title = "Boss Tracker", group = "Bosses",
		settings = {
			Section("Show"),
			Check("Boss Tracker", "Bosses, kills and the run timer.", "tracker"),
			Indent(Check("Also Hide It Where Navigation Is Off",
				"In the instances unticked on the Instances page, the tracker goes too.", "offHidesTracker",
				function() DN:NavChanged() end, On("tracker"))),
			Section("Size"),
			Slider("Tracker Size", "How big the tracker is.", "trackerScale", 50, 200, 5, Percent, On("tracker"), 100),
			Section("Chat"),
			Check("Announce Kills in Chat", "A line in chat with each kill's time into the run.", "announce",
				function() end),
		},
	},
	{ key = "instances", title = "Instances", group = "Bosses", custom = "instances" },
	{
		key = "general", title = "General", group = "Other",
		settings = {
			Section("Look"),
			{
				kind = "dropdown", label = "Theme",
				tip = "How InstanceGPS's windows and menus are drawn. A new theme applies after a reload.",
				choices = function()
					local list = {}
					for _, skin in ipairs(S.Skins()) do
						list[#list + 1] = { value = skin.key, text = skin.label, tooltip = skin.credit }
					end
					return list
				end,
				get = function() return DN.db.skin end,
				set = function(v) DN.SetSkin(v) end,
			},
			{
				kind = "check", label = "Snap to Screen Pixels",
				tip = "Scales InstanceGPS's windows so their edges and thin lines land on whole screen pixels, sharp at any UI scale.",
				get = function() return DN.db.pixelScale end,
				set = function(v) DN.SetPixelScale(v) end,
				reset = function() DN.SetPixelScale(true) end,
			},
			Section("Frames"),
			Check("Lock Frames", "Stops the arrow, tracker and 3D view from being dragged.", "lockFrames",
				function() end),
			Button("Frame Positions", "Reset", "Puts the arrow, tracker, 3D view and windows back where they start. Reloads the UI.",
				ResetFramePositions),
			Section("Reset"),
			Button("Every Setting", "Reset All", "Puts every InstanceGPS setting, on every page, back to its default.",
				function() StaticPopup_Show("INSTANCEGPS_RESET_ALL") end, "danger"),
		},
	},
}

StaticPopupDialogs.INSTANCEGPS_RESET_ALL = {
	text = "Put every InstanceGPS setting back to its default?",
	button1 = YES, button2 = NO,
	OnAccept = function() O.ResetAll() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

------------------------------------------------------------------------ server modules' pages

-- InstanceGPS:ModuleOptions(name, list) gives a server module a page of options, saved with InstanceGPS's settings
-- (docs/MODULES.md). Each option is { key =, label =, tip =, default = }, plus choices = { { value, label }, ... }
-- for a dropdown; without choices it's a checkbox. The returned table reads the current values;
-- InstanceGPS:On("MODULE_OPTION", function(module, key, value) end) tells of changes.
local function Saved(page)
	local all = DN.db and DN.db.modules
	return all and all[page.name]
end

local function SetModuleOption(page, key, value)
	DN.db.modules = DN.db.modules or {}
	DN.db.modules[page.name] = DN.db.modules[page.name] or {}
	DN.db.modules[page.name][key] = value
	DN:Fire("MODULE_OPTION", page.name, key, value)
	Apply()
end

local function ModulePage(page)
	local settings = {}
	for _, o in ipairs(page.list) do
		local get = function() return page.values[o.key] end
		local set = function(v) SetModuleOption(page, o.key, v) end
		local reset = function() SetModuleOption(page, o.key, o.default) end
		if o.choices then
			local choices = {}
			for _, c in ipairs(o.choices) do choices[#choices + 1] = { value = c[1], text = c[2] } end
			settings[#settings + 1] = { kind = "dropdown", label = o.label, tip = o.tip, get = get, set = set,
				reset = reset, choices = function() return choices end }
		else
			settings[#settings + 1] = { kind = "check", label = o.label, tip = o.tip, get = get, set = set, reset = reset }
		end
	end
	return { key = "module:" .. page.name, title = page.name, group = "Server Modules", settings = settings }
end

local BuildNav

function DN:ModuleOptions(name, list)
	local page = { name = name, list = list }
	local defaults = {}
	for _, o in ipairs(list) do defaults[o.key] = o.default end
	page.values = setmetatable({}, { __index = function(_, key)
		local saved = Saved(page)
		local v = saved and saved[key]
		if v == nil then v = defaults[key] end
		return v
	end })
	page.def = ModulePage(page)
	-- before the General page, which stays last
	table.insert(O.PAGES, #O.PAGES, page.def)
	if frame then BuildNav(frame.side) end
	return page.values
end

------------------------------------------------------------------------ rows

local function ChoiceText(setting, value)
	for _, c in ipairs(setting.choices()) do
		if c.value == value then return c.text end
	end
	return ""
end

local function Usable(setting)
	return not setting.enabledIf or setting.enabledIf()
end

-- Puts a row's controls in line with its setting's values and whether it can be changed now
local function RefreshRow(row)
	local setting, control = row.setting, row.control
	local usable = Usable(setting)
	if row.label then row.label:SetTextColor(unpack(usable and C.text or C.disabled)) end
	if row.desc then row.desc:SetTextColor(unpack(usable and C.muted or C.disabled)) end
	if setting.kind == "check" then
		control:SetChecked(setting.get())
		control:SetEnabled(usable)
	elseif setting.kind == "slider" then
		control:SetValue(setting.get())
		control:SetEnabled(usable)
	elseif setting.kind == "dropdown" then
		control:SetText(ChoiceText(setting, setting.get()))
		if usable then control:Enable() else control:Disable() end
	end
end

local function RefreshPage(page)
	for _, row in ipairs(page.rows) do RefreshRow(row) end
	if page.Refresh then page.Refresh() end
end

local function DropdownControl(row, setting, changed)
	local control
	if #setting.choices() > PICKER_AFTER then
		control = S.PickerButton(row, CONTROL_W, function()
			return {
				items = setting.choices(),
				placeholder = "Search",
				isSelected = function(value) return value == setting.get() end,
				onPick = changed,
			}
		end)
	else
		control = S.Dropdown(row, CONTROL_W, changed)
		control:SetOptions(setting.choices())
	end
	return control
end

local function NewSection(page, setting, y)
	local row = CreateFrame("Frame", nil, page.content)
	row:SetPoint("TOPLEFT", 0, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(SECTION_H)
	row.setting = setting
	S.SectionHeading(row, setting.label, 0, -12, 0)
	return row
end

local function NewRow(page, setting, y)
	local row = CreateFrame("Frame", nil, page.content)
	local x = setting.indent and INDENT or 0
	row:SetPoint("TOPLEFT", x, y)
	row:SetPoint("TOPRIGHT", 0, y)
	row:SetHeight(setting.tip and ROW_H or PLAIN_H)
	row.setting = setting
	row.desc = false
	row.label = S.Text(row, "normal")
	row.label:SetText(setting.label)
	local function changed(v)
		setting.set(v)
		RefreshPage(page)
	end
	local control
	if setting.kind == "check" then
		control = S.Check(row, nil, function(box) changed(not box.on) end)
		control:SetPoint("RIGHT", 0, 0)
	elseif setting.kind == "slider" then
		control = S.Slider(row, CONTROL_W - S.SLIDER_VALUE_W - S.GAP, setting.min, setting.max, setting.step,
			changed, setting.format)
		control:SetPoint("RIGHT", -(S.SLIDER_VALUE_W + S.GAP), 0)
	elseif setting.kind == "dropdown" then
		control = DropdownControl(row, setting, changed)
		control:SetPoint("RIGHT", 0, 0)
	else
		control = S.Button(row, setting.text, setting.style or "secondary", 90, function() setting.set() end)
		control:SetPoint("RIGHT", 0, 0)
	end
	control.tooltipText = setting.tip
	row.control = control
	-- the label and its line run up to their own control: a check or button takes less room than a dropdown
	local controlW = (setting.kind == "check" and S.CHECK_H) or (setting.kind == "button" and 90) or CONTROL_W
	local textW = CONTENT_W - x - controlW - 2 * S.GAP
	row.label:SetWidth(textW)
	row.label:SetJustifyH("LEFT")
	if setting.tip then
		row.label:SetPoint("TOPLEFT", 0, -4)
		-- a width alone, no right anchor, so a long line wraps and the row grows to fit it
		row.desc = S.Text(row, "small", C.muted)
		row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
		row.desc:SetWidth(textW)
		row.desc:SetJustifyH("LEFT")
		row.desc:SetText(setting.tip)
		local lines = (row.label:GetStringHeight() or 12) + (row.desc:GetStringHeight() or 12)
		row:SetHeight(math.max(ROW_H, lines + 14))
	else
		row.label:SetPoint("LEFT", 0, 0)
	end
	return row
end

-- Puts every setting on a page back to its default
local function ResetPage(page)
	for _, row in ipairs(page.rows) do
		if row.setting.reset then row.setting.reset() end
	end
	if page.Reset then page.Reset() end
	RefreshPage(page)
end

local function PageFrame(def, scrolls)
	local page = CreateFrame("Frame", nil, frame.main)
	page:SetAllPoints(frame.main)
	page.rows = {}
	if scrolls then
		local name = "InstanceGPSOptionsScroll" .. def.key:gsub("%W", "")
		page.scroll = CreateFrame("ScrollFrame", name, page, "UIPanelScrollFrameTemplate")
		page.scroll:SetPoint("TOPLEFT", S.PAD, -S.PAD)
		page.scroll:SetPoint("BOTTOMRIGHT", -S.PAD - 10, S.PAD)
		page.content = CreateFrame("Frame", nil, page.scroll)
		page.content:SetWidth(CONTENT_W)
		page.scroll:SetScrollChild(page.content)
		page.bar = S.ScrollBar(page.scroll, name)
	else
		page.content = CreateFrame("Frame", nil, page)
		page.content:SetPoint("TOPLEFT", S.PAD, -S.PAD)
		page.content:SetPoint("BOTTOMRIGHT", -S.PAD, S.PAD)
	end
	-- Reset This Page sits across from the heading, in the danger color, a little inside the content's top edge:
	-- the scroll frame clips anything past it
	local top = 2
	page.reset = S.Button(page.content, "Reset This Page", "danger", 120, function() ResetPage(page) end,
		"Puts this page's settings back to their defaults.")
	page.reset:SetPoint("TOPRIGHT", 0, -top)
	local heading = S.Text(page.content, "large", C.heading)
	heading:SetPoint("LEFT", page.content, "TOPLEFT", 0, -top - S.CONTROL_H / 2)
	heading:SetText(def.title)
	page.top = -top - S.CONTROL_H - 12
	page:Hide()
	return page
end

local function SettingsPage(def)
	local page = PageFrame(def, true)
	local y = page.top
	for _, setting in ipairs(def.settings) do
		local row = setting.kind == "section" and NewSection(page, setting, y) or NewRow(page, setting, y)
		if setting.kind ~= "section" then page.rows[#page.rows + 1] = row end
		y = y - (setting.kind == "section" and SECTION_H or row:GetHeight())
	end
	page.content:SetHeight(-y)
	local fits = -y <= H - 2 * S.PAD
	if fits then page.bar:Hide() end
	page.scroll:HookScript("OnScrollRangeChanged", function()
		if fits then page.bar:Hide() end
	end)
	return page
end

------------------------------------------------------------------------ the Instances page

-- Where navigation (arrow, path views, route on the map, hints) is on: a table of every instance by expansion, a
-- click on a row switching it, a click on an expansion's heading switching all of its instances
local EXPANSIONS = { [0] = "Classic", [1] = "The Burning Crusade", [2] = "Wrath of the Lich King", [99] = "Other" }
local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:16:16:0:0|t"

local function InstanceItems()
	local groups = {}
	for mapId, inst in pairs(ns.Instances) do
		local e = EXPANSIONS[inst.exp] and inst.exp or 99
		groups[e] = groups[e] or {}
		table.insert(groups[e], { mapId = mapId, name = inst.name, raid = inst.type == "raid" })
	end
	local items = {}
	for _, e in ipairs({ 0, 1, 2, 99 }) do
		local list = groups[e]
		if list then
			-- dungeons first, then raids, each by name
			table.sort(list, function(a, b)
				return (a.raid ~= b.raid and not a.raid) or (a.raid == b.raid and a.name < b.name)
			end)
			local header = { header = EXPANSIONS[e], members = list }
			items[#items + 1] = header
			for _, item in ipairs(list) do items[#items + 1] = item end
		end
	end
	return items
end

local function SetMany(list, on)
	DN.db.off = DN.db.off or {}
	for _, item in ipairs(list) do DN.db.off[item.mapId] = not on or nil end
	DN:NavChanged()
end

local function AnyOn(list)
	for _, item in ipairs(list) do
		if not DN:IsOff(item.mapId) then return true end
	end
	return false
end

local function InstancesPage(def)
	local page = PageFrame(def, false)
	local note = S.Text(page.content, "small", C.muted)
	note:SetPoint("TOPLEFT", 0, page.top)
	note:SetWidth(W - NAV_W - 2 * S.PAD)
	note:SetJustifyH("LEFT")
	note:SetText("Navigation (the arrow, path views, route on the map and hints) works in the instances ticked here. "
		.. "In the others the boss tracker still runs.")
	local items = InstanceItems()
	local all = {}
	for _, item in ipairs(items) do
		if not item.header then all[#all + 1] = item end
	end
	local y = page.top - 34
	local allOn = S.Button(page.content, "All On", "secondary", 70, function()
		SetMany(all, true)
		page.Refresh()
	end)
	allOn:SetPoint("TOPLEFT", 0, y)
	local allOff = S.Button(page.content, "All Off", "secondary", 70, function()
		SetMany(all, false)
		page.Refresh()
	end)
	allOff:SetPoint("LEFT", allOn, "RIGHT", S.GAP, 0)

	local width = W - NAV_W - 2 * S.PAD
	local height = H - 2 * S.PAD + y - S.CONTROL_H - S.GAP
	local tbl
	tbl = S.Table.New(page.content, "InstanceGPSInstancesTable", width, height, {
		columns = {
			{ key = "on", label = "On", width = 36, justify = "CENTER", sortable = false },
			{ key = "name", label = "Instance", width = 120, stretch = true, sortable = false },
			{ key = "kind", label = "Type", width = 80, sortable = false },
		},
		header = function(item) return item.header end,
		cell = function(item, key)
			local on = not DN:IsOff(item.mapId)
			if key == "on" then return on and CHECK or "" end
			if key == "kind" then return item.raid and "Raid" or "Dungeon", C.muted end
			return item.name, on and C.text or C.muted
		end,
		tooltip = function(tip, item)
			local list = item.members
			tip:AddLine(item.header or item.name)
			if list then
				DN.HintLines(tip, AnyOn(list) and "Click: Turn All Off" or "Click: Turn All On")
			else
				DN.HintLines(tip, DN:IsOff(item.mapId) and "Click: Turn Navigation On" or "Click: Turn Navigation Off")
			end
		end,
		onClick = function(item)
			if item.members then
				SetMany(item.members, not AnyOn(item.members))
			else
				DN:SetOff(item.mapId, not DN:IsOff(item.mapId))
			end
			tbl:Redraw()
		end,
	})
	tbl.frame:SetPoint("TOPLEFT", allOn, "BOTTOMLEFT", 0, -S.GAP)
	tbl:SetItems(items)
	page.table = tbl
	page.Refresh = function() tbl:Redraw() end
	page.Reset = function() SetMany(all, true) end
	return page
end

------------------------------------------------------------------------ the window

local navRoot

-- The sidebar: pages under their group's heading, in GROUP_ORDER, leaving out groups with no pages. Built again
-- when a server module adds a page later.
function BuildNav(side)
	if navRoot then navRoot:Hide() end
	navRoot = CreateFrame("Frame", nil, side)
	navRoot:SetAllPoints(side)
	local inset = 1 + S.metrics.navInset
	local y = -S.GAP
	frame.nav = {}
	local first = true
	for _, group in ipairs(GROUP_ORDER) do
		local any = false
		for _, def in ipairs(O.PAGES) do any = any or def.group == group end
		if any then
			y = y - (first and 0 or S.GAP)
			first = false
			S.SectionHeading(navRoot, group, inset + S.PAD - 1, y - 4)
			y = y - DN.Window.SECTION_H
			for _, def in ipairs(O.PAGES) do
				if def.group == group then
					local b = CreateFrame("Button", nil, navRoot)
					b:SetHeight(NAV_H)
					b:SetPoint("TOPLEFT", inset, y)
					b:SetPoint("TOPRIGHT", -inset, y)
					S.NavEntry(b, def.title)
					b.key = def.key
					b:SetScript("OnClick", function() O.Open(def.key) end)
					b:SetSelected(def.key == current)
					frame.nav[#frame.nav + 1] = b
					y = y - NAV_H
				end
			end
		end
	end
end

local function Create()
	frame = DN.Window.New({ name = "InstanceGPSOptionsWindow", subtitle = "Options", width = W, height = H,
		positionKey = "options", sidebar = true })
	O.frame = frame
	frame.pages = {}
	BuildNav(frame.side)
	return frame
end

-- Opens the window on a page (default: the last one shown)
function O.Open(key)
	frame = frame or Create()
	S.Dismiss()
	current = key or current or O.PAGES[1].key
	for _, def in ipairs(O.PAGES) do
		local page = frame.pages[def.key]
		if def.key == current then
			page = page or (def.custom == "instances" and InstancesPage(def) or SettingsPage(def))
			frame.pages[def.key] = page
			RefreshPage(page)
			page:Show()
		elseif page then
			page:Hide()
		end
	end
	for _, b in ipairs(frame.nav) do b:SetSelected(b.key == current) end
	DN.Window.Show(frame)
end

function O.Toggle()
	if frame and frame:IsShown() then frame:Hide() else O.Open() end
end

function O.Page(key)
	return frame and frame.pages[key]
end

-- A built page's row for the setting with this label
function O.Row(key, label)
	local page = O.Page(key)
	for _, row in ipairs(page and page.rows or {}) do
		if row.setting.label == label then return row end
	end
end

O.ResetPage = ResetPage

-- Every page's settings back to their defaults
function O.ResetAll()
	for _, def in ipairs(O.PAGES) do
		for _, setting in ipairs(def.settings or {}) do
			if setting.reset then setting.reset() end
		end
	end
	SetMany(InstanceItems(), true)
	DN.Window.ResetPositions()
	if frame and frame.pages[current] then RefreshPage(frame.pages[current]) end
end

-- toInstances: open the Instances page
function DN:OpenOptions(toInstances)
	O.Open(toInstances and "instances" or nil)
end

------------------------------------------------------------------------ Interface Options > AddOns

local panel = CreateFrame("Frame", "InstanceGPSOptions")
panel.name = "InstanceGPS"
DN:On("LOADED", function()
	local panelTitle = S.Text(panel, "large", C.heading)
	panelTitle:SetPoint("TOPLEFT", 16, -16)
	panelTitle:SetText("InstanceGPS")
	local panelText = S.Text(panel, "small", C.muted)
	panelText:SetPoint("TOPLEFT", panelTitle, "BOTTOMLEFT", 0, -8)
	panelText:SetText("InstanceGPS keeps its settings in its own window, also opened with /igps options.")
	local open = S.Button(panel, "Open InstanceGPS Options", "primary", 190, function()
		HideUIPanel(InterfaceOptionsFrame)
		HideUIPanel(GameMenuFrame)
		O.Open()
	end)
	open:SetPoint("TOPLEFT", panelText, "BOTTOMLEFT", 0, -12)
	InterfaceOptions_AddCategory(panel)
end)
