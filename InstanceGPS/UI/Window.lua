-- InstanceGPS's windows: the frame in the skin's window style, a title bar that drags it and holds the title, the
-- version and Close, an optional sidebar, and the main area. Windows sit on MEDIUM with the game's panels, raise
-- when opened, close with Escape and remember where they were dragged.
local _, ns = ...
local DN, S = ns.DN, ns.Style
local C = S.colors

local Window = {}
DN.Window = Window

Window.TITLE_H, Window.SIDEBAR_W, Window.NAV_H, Window.SECTION_H = 30, 150, 26, 20

local windows = {}

-- "InstanceGPS <subtitle>", with GPS in the accent color as on every window of these addons
function Window.Title(subtitle)
	return "Instance" .. S.Hex(C.accent, "GPS") .. (subtitle and (" " .. subtitle) or "")
end

local function Place(f)
	local p = DN.db.pos[f.positionKey]
	if p then
		f:ClearAllPoints()
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		S.PlaceWindow(f)
	end
	DN.SnapPosition(f)
end

-- After a window's scale changes: a dragged one keeps its spot, saved again in its new units; others go back to
-- the default spot.
local function Rescaled(f)
	if DN.db.pos[f.positionKey] then
		DN.SnapPosition(f)
		local point, _, relPoint, x, y = f:GetPoint(1)
		DN.db.pos[f.positionKey] = { point, relPoint, x, y }
	else
		Place(f)
	end
end

-- opts: name (global frame name), subtitle, width, height (inside the frame's border), positionKey (where in
-- DN.db.pos the dragged position is kept), sidebar (true for a sidebar). Returns the frame, with .bar, .side, .main.
function Window.New(opts)
	S.RefreshFonts()
	local edge = S.metrics.edge
	local f = CreateFrame("Frame", opts.name, UIParent)
	f.positionKey = opts.positionKey
	f:SetSize(opts.width + 2 * edge, opts.height + 2 * edge)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	DN.PixelScale(f, function() Rescaled(f) end)
	Place(f)
	S.Frame(f, "window")
	tinsert(UISpecialFrames, opts.name)
	f:Hide()

	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", edge, -edge)
	bar:SetPoint("TOPRIGHT", -edge, -edge)
	bar:SetHeight(Window.TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		S.Dismiss()
		f:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		DN.SnapPosition(f)
		local point, _, relPoint, x, y = f:GetPoint(1)
		DN.db.pos[f.positionKey] = { point, relPoint, x, y }
	end)
	S.Rule(bar, "BOTTOM")
	local title = S.Text(bar, "normal")
	title:SetPoint("LEFT", S.PAD, 0)
	title:SetText(Window.Title(opts.subtitle))
	local version = S.Text(bar, "small", C.muted)
	version:SetPoint("LEFT", title, "RIGHT", S.GAP, 0)
	-- the version, and the server modules loaded on top ("v1.1.0 + Synastria")
	version:SetText((DN:Title():gsub("^InstanceGPS ", "v")))
	f.close = S.Button(bar, "Close", "ghost", 56, function() f:Hide() end)
	f.close:SetPoint("RIGHT", -(Window.TITLE_H - S.CONTROL_H) / 2, 0)
	f.bar = bar

	local left = edge
	if opts.sidebar then
		local side = CreateFrame("Frame", nil, f)
		side:SetPoint("TOPLEFT", edge, -edge - Window.TITLE_H)
		side:SetPoint("BOTTOMLEFT", edge, edge)
		side:SetWidth(Window.SIDEBAR_W)
		S.Sidebar(side)
		f.side = side
		left = edge + Window.SIDEBAR_W
	end
	f.main = CreateFrame("Frame", nil, f)
	f.main:SetPoint("TOPLEFT", left, -edge - Window.TITLE_H)
	f.main:SetPoint("BOTTOMRIGHT", -edge, edge)

	f:SetScript("OnShow", function() PlaySound("igCharacterInfoOpen") end)
	f:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		S.Dismiss()
		-- closing mid-drag (Escape) can skip OnDragStop
		f:StopMovingOrSizing()
	end)
	windows[#windows + 1] = f
	return f
end

-- Shows a window in front of the others
function Window.Show(f)
	S.Dismiss()
	f:Show()
	f:Raise()
end

-- Forgets every window's dragged position and puts them back at the default spot
function Window.ResetPositions()
	for _, f in ipairs(windows) do
		DN.db.pos[f.positionKey] = nil
		Place(f)
	end
end
