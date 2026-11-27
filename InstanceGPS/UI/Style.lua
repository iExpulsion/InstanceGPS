-- Vendored from MaterialCraftUI v1.8.0-1-gb5356b0. Change it there, then run tools/sync_style.py.
-- MIT License, Copyright (c) 2026 Expulsion: https://github.com/iExpulsion/MaterialCraftUI
-- MaterialCraftUI: a flat dark style kit for WoW 3.3.5 addons on Material 3 color roles: one accent color, 1px
-- borders, state layers and a few button kinds. Each addon ships its own copy, listed in its .toc, and reads it
-- as NS.Style from its addon table; font objects are named after the addon, so copies never clash.
local ADDON, NS = ...
local S = {}
NS.Style = S

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function rgb(hex, alpha)
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, alpha or 1 }
end

-- `over` laid on `base` at `alpha`: Material's state layers (hover 8%, pressed 12%, disabled fill 12%).
local function blend(base, over, alpha)
	local out = {}
	for i = 1, 3 do out[i] = base[i] + (over[i] - base[i]) * alpha end
	out[4] = base[4]
	return out
end

-- Material 3's baseline dark scheme (seed #6750a4). It has no success or warning roles, so those are custom
-- colors, as are red, blue, green and yellow: hues for telling groups apart (S.Table's headerColor), light enough
-- to read on any surface.
local DEFAULT_SCHEME = {
	surfaceLowest = rgb("0f0d13"),
	surface = rgb("141218"),
	surfaceLow = rgb("1d1b20"),
	surfaceContainer = rgb("211f26"),
	surfaceHigh = rgb("2b2930"),
	onSurface = rgb("e6e0e9"),
	onSurfaceVariant = rgb("cac4d0"),
	outline = rgb("938f99"),
	outlineVariant = rgb("49454f"),
	primary = rgb("d0bcff"),
	onPrimary = rgb("381e72"),
	error = rgb("f2b8b5"),
	errorContainer = rgb("8c1d18"),
	success = rgb("78dc77"),
	warning = rgb("ffb870"),
	red = rgb("ffb4ab"),
	blue = rgb("a8c7fa"),
	green = rgb("8fdb8d"),
	yellow = rgb("eccb6f"),
}

local M3 = {}
S.colors = {}
local BUTTONS, DISABLED = {}, {}
local qualityColors = {}
-- the skin in use: how controls are drawn, set by S.UseSkin; the flat Material one is filled in further down
local skin = {}
local skins = {}

local function withAlpha(c, a)
	return { c[1], c[2], c[3], a }
end

-- Text on an accent the scheme didn't give one for: a dark shade of a light accent, a light tint of a dark one.
local function onColor(c)
	local light = 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] > 0.5
	return light and blend(c, { 0, 0, 0 }, 0.75) or blend(c, { 1, 1, 1 }, 0.9)
end

-- Fills S.colors and the button kinds from M3. S.colors is filled in place, so tables addons hold on to stay live
-- and colors they added stay put.
local function build()
	local c = S.colors
	c.window = withAlpha(M3.surface, 0.97)
	c.sidebar = M3.surfaceLow
	c.panel = M3.surfaceContainer
	c.well = M3.surfaceLowest
	c.border = M3.outlineVariant
	c.outline = M3.outline
	c.hover = withAlpha(M3.onSurface, 0.08)
	c.selected = withAlpha(M3.primary, 0.12)
	c.accent = M3.primary
	c.accentHover = blend(M3.primary, M3.onPrimary, 0.08)
	c.onAccent = M3.onPrimary
	c.text = M3.onSurface
	c.heading = M3.primary
	c.muted = M3.onSurfaceVariant
	c.disabled = withAlpha(M3.onSurface, 0.38)
	c.good = M3.success
	c.warn = M3.warning
	c.bad = M3.error
	c.badDim = M3.errorContainer
	c.red, c.blue, c.green, c.yellow = M3.red, M3.blue, M3.green, M3.yellow
	-- roles a skin can set apart from the scheme: table rows, the selected entry of a navigation list, dropdown
	-- arrows and scroll bars
	c.rowHover = c.hover
	c.rowSelected = c.selected
	c.navSelected = c.heading
	c.arrow = c.muted
	c.scrollThumb = c.border
	c.scrollThumbHover = c.outline
	c.scrollTrack = withAlpha(M3.onSurface, 0.04)
	if skin.colors then skin.colors(c, M3) end

	-- Filled (primary, one per view), tonal (secondary), text (ghost), and the selected side of a segmented button
	-- (selected: a primary tint with primary text); hover is an 8% layer of the label color.
	local selectedBg = blend(M3.surfaceHigh, M3.primary, 0.16)
	BUTTONS.primary = { bg = M3.primary, hover = c.accentHover, border = M3.primary, text = M3.onPrimary }
	BUTTONS.secondary = { bg = M3.surfaceHigh, hover = blend(M3.surfaceHigh, M3.onSurface, 0.08), border = M3.outlineVariant, text = M3.onSurface }
	BUTTONS.selected = { bg = selectedBg, hover = blend(selectedBg, M3.primary, 0.08), border = blend(M3.outlineVariant, M3.primary, 0.4), text = M3.primary }
	BUTTONS.danger = { bg = M3.surfaceHigh, hover = blend(M3.surfaceHigh, M3.error, 0.08), border = M3.outlineVariant, text = M3.error }
	BUTTONS.ghost = { bg = { 0, 0, 0, 0 }, hover = c.hover, border = { 0, 0, 0, 0 }, text = M3.onSurfaceVariant }
	-- Disabled buttons of every kind look the same, as Material has it: a 12% onSurface fill with 38% onSurface
	-- text, so faded text never sits on a bright fill.
	DISABLED = { bg = blend(M3.surface, M3.onSurface, 0.12), border = M3.outlineVariant, text = c.disabled }
	for q in pairs(qualityColors) do qualityColors[q] = nil end
end

-- Sets the Material 3 roles the kit is drawn from, by name, as "rrggbb" hex or { r, g, b }; roles left out keep
-- the default scheme, and S.SetTheme() goes back to it. A primary given without an onPrimary gets one worked out.
-- Call it before building any frames: frames take their colors as they're made.
function S.SetTheme(roles)
	for role, color in pairs(DEFAULT_SCHEME) do M3[role] = color end
	for role, color in pairs(roles or {}) do
		if not DEFAULT_SCHEME[role] then error("MaterialCraftUI: unknown theme role " .. tostring(role), 2) end
		M3[role] = type(color) == "string" and rgb((color:gsub("^#", ""))) or { color[1], color[2], color[3], color[4] or 1 }
	end
	if roles and roles.primary and not roles.onPrimary then M3.onPrimary = onColor(M3.primary) end
	build()
end
S.SetTheme()

-- One spacing scale for every panel: PAD inside a panel's edges (the same on all sides), GAP between neighboring
-- controls, and one height for every button, input and dropdown so rows line up.
S.PAD, S.GAP, S.CONTROL_H = 12, 8, 24
-- a checkbox's size: smaller than the other controls, which a box that tall overpowers, but big enough to read
S.CHECK_H = 18

-- What a skin's frame decoration takes up: edge, the border S.Frame draws around a "window", which its content
-- stays inside; inset, the padding inside a "popup"; navInset, how far in from a sidebar's sides its entries sit;
-- wellInset, extra padding inside an S.Well for its frame; menuInset, how far in from a "menu" frame's edges its rows
-- sit, clear of its border; tabPad, the room either side of a tab's label.
local METRICS = { edge = 0, inset = S.PAD, navInset = 0, wellInset = 0, menuInset = 1, tabPad = S.PAD }
S.metrics = {}
for k, v in pairs(METRICS) do S.metrics[k] = v end

-- "1 item", "3 items".
function S.Count(n, singular, plural)
	return ("%d %s"):format(n, n == 1 and singular or (plural or singular .. "s"))
end

-- The 3.3.5 client's ITEM_QUALITY_COLORS stops at Artifact (6), though heirloom links are colored e6cc80.
local MISSING_QUALITY = { [7] = rgb("e6cc80") }

-- An item quality's color as { r, g, b, a }, made once per quality since tables ask for it on every redraw.
function S.QualityColor(q)
	local color = qualityColors[q or -1]
	if not color then
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
		color = c and { c.r, c.g, c.b, 1 } or MISSING_QUALITY[q] or S.colors.text
		qualityColors[q or -1] = color
	end
	return color
end

function S.Hex(c, text)
	return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
end

function S.Panel(frame, bg, border)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = border and WHITE or nil, edgeSize = 1 })
	frame:SetBackdropColor(unpack(bg))
	if border then frame:SetBackdropBorderColor(unpack(border)) end
end

function S.Solid(parent, layer, color)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(WHITE)
	t:SetVertexColor(unpack(color))
	return t
end

-- Pixels. The client lays out in UI units, and one unit is effective scale x screen height / 768 screen pixels,
-- rarely a whole number, so a 1px border or an edge can fall between two pixel rows and blur or shift. A window
-- given S.PixelScale is scaled so one of its units is a whole number of screen pixels, the number nearest to the
-- UI scale; then every whole-unit position and size inside it lands on real pixels.
local function screenHeight()
	local h = tonumber(((GetCVar and GetCVar("gxResolution")) or ""):match("%d+x(%d+)"))
	if not h and GetScreenResolutions and GetCurrentResolution then
		h = tonumber((select(GetCurrentResolution(), GetScreenResolutions()) or ""):match("%d+x(%d+)"))
	end
	return h or 768
end

-- One screen pixel, in a region's own units.
function S.PixelSize(region)
	return 768 / (screenHeight() * region:GetEffectiveScale())
end

-- A length or offset in a region's units, rounded to whole screen pixels.
function S.Snap(region, v)
	local p = S.PixelSize(region)
	return math.floor(v / p + 0.5) * p
end

-- frame -> true when it snaps to whole pixels, false when it only takes the window scale
local pixelFrames = {}

-- The player's size for this addon's windows (S.SetWindowScale), on top of the UI scale and pixel snapping.
S.windowScale = 1
-- A scaled pixel-snapped window snaps again only when a whole number of pixels per unit is this close to the size
-- asked for; otherwise it takes the exact size and its borders may blur.
local SNAP_SLACK = 0.05

local function applyScale(frame)
	local scale = S.windowScale
	if pixelFrames[frame] then
		local parent = frame:GetParent() or UIParent
		local perUnit = parent:GetEffectiveScale() * screenHeight() / 768
		local want = math.max(1, math.floor(perUnit + 0.5)) * S.windowScale
		local whole = math.max(1, math.floor(want + 0.5))
		scale = (math.abs(whole / want - 1) <= SNAP_SLACK and whole or want) / perUnit
	end
	frame:SetScale(scale)
end

-- Moves a frame so its top left corner sits on a screen pixel, anchored to UIParent's bottom left. Run it after
-- the frame is placed and after it's dragged.
function S.SnapPosition(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", S.Snap(frame, left), S.Snap(frame, top))
	end
end

-- Where windows open by default: centered across the screen, their tops S.WINDOW_TOP of UIParent's units below the
-- screen's top, so windows of different heights, and different addons', line up.
S.WINDOW_TOP = 128

-- Puts a window at that spot. The offset is converted from UIParent's units, so a window with a scale of its own
-- (S.PixelScale) lands in the same place as one without.
function S.PlaceWindow(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOP", UIParent, "TOP", 0, -S.WINDOW_TOP * UIParent:GetEffectiveScale() / frame:GetEffectiveScale())
end

-- Scales a top-level window so its units are whole screen pixels, and keeps it so when the UI scale or the screen
-- size changes. Either way it takes S.windowScale; on = false leaves out the snapping.
function S.PixelScale(frame, on)
	pixelFrames[frame] = on ~= false
	applyScale(frame)
	return frame
end

-- Where a frame's anchor point (TOPRIGHT, CENTER, ...) is, in its own units from the screen's bottom left.
local function anchorSpot(frame, point)
	local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if left and right and top and bottom then
		local x = point:find("LEFT") and left or point:find("RIGHT") and right or (left + right) / 2
		local y = point:find("TOP") and top or point:find("BOTTOM") and bottom or (top + bottom) / 2
		return x, y
	end
end

-- Sets the size of every window given S.PixelScale, from 1 (their designed size). Each keeps the point it's
-- anchored by where it is on the screen, so a window pinned by its top right corner grows to the left.
function S.SetWindowScale(scale)
	S.windowScale = scale
	for frame, snap in pairs(pixelFrames) do
		local point = frame:GetPoint(1) or "TOPLEFT"
		local x, y = anchorSpot(frame, point)
		local before = frame:GetEffectiveScale()
		applyScale(frame)
		if x then
			local ratio = before / frame:GetEffectiveScale()
			x, y = x * ratio, y * ratio
			if snap then x, y = S.Snap(frame, x), S.Snap(frame, y) end
			frame:ClearAllPoints()
			frame:SetPoint(point, UIParent, "BOTTOMLEFT", x, y)
		end
	end
end

local function uiScaleChanged()
	for frame, snap in pairs(pixelFrames) do
		applyScale(frame)
		if snap then S.SnapPosition(frame) end
	end
end

local pixelWatch = CreateFrame("Frame")
pixelWatch:RegisterEvent("UI_SCALE_CHANGED")
pixelWatch:RegisterEvent("DISPLAY_SIZE_CHANGED")
pixelWatch:SetScript("OnEvent", uiScaleChanged)
-- UI addons that set their own UI scale call UIParent:SetScale, which fires no UI_SCALE_CHANGED.
hooksecurefunc(UIParent, "SetScale", uiScaleChanged)

-- Atlases: painted pieces packed into one texture by tools/pack_art.py, which writes the RegisterAtlas call. Each
-- piece is u0, u1, v0, v1 on the atlas, then how much trimming took off its left, top, right and bottom, as
-- fractions of its original size. The texture sits in the addon at UI\Skins\<file>\<file>.
local atlases = {}

function S.RegisterAtlas(name, file, pieces)
	atlases[name] = { path = "Interface\\AddOns\\" .. ADDON .. "\\UI\\Skins\\" .. file .. "\\" .. file, pieces = pieces }
end

-- Points a texture at a piece of an atlas, or at part of it: fu0..fu1 and fv0..fv1 are fractions of the piece's
-- original size (default: all of it).
function S.Art(tex, atlas, piece, fu0, fu1, fv0, fv1)
	local a = atlases[atlas]
	local p = a.pieces[piece]
	local u0, u1, v0, v1, l, t, r, b = unpack(p)
	local function along(f, lo, hi, cut0, cut1) return lo + (hi - lo) * (f - cut0) / (1 - cut0 - cut1) end
	tex:SetTexture(a.path)
	tex:SetTexCoord(along(fu0 or 0, u0, u1, l, r), along(fu1 or 1, u0, u1, l, r),
		along(fv0 or 0, v0, v1, t, b), along(fv1 or 1, v0, v1, t, b))
end

-- Places a texture showing a piece as if the piece were untrimmed and drawn at x, y (down from the frame's top
-- left) at w by h. One anchor and an explicit size, which draws painted art at the size asked for on this client.
function S.PlaceArt(tex, frame, atlas, piece, x, y, w, h)
	local _, _, _, _, l, t, r, b = unpack(atlases[atlas].pieces[piece])
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x + w * l, -(y + h * t))
	tex:SetWidth(math.max(w * (1 - l - r), 1))
	tex:SetHeight(math.max(h * (1 - t - b), 1))
end

-- A piece's original size in pixels.
function S.ArtSize(atlas, piece)
	local p = atlases[atlas].pieces[piece]
	return p[9], p[10]
end

-- The size in pixels of what's left of a piece after trimming: the art itself, for centering it.
function S.ArtTrimmedSize(atlas, piece)
	local p = atlases[atlas].pieces[piece]
	return p[9] * (1 - p[5] - p[7]), p[10] * (1 - p[6] - p[8])
end

-- Shows part of a piece, given in its own pixels (x0..x1, y0..y1), at x, y (down from the frame's top left) at
-- w by h.
function S.ArtPart(tex, frame, atlas, piece, x0, x1, y0, y1, x, y, w, h)
	local pw, ph = S.ArtSize(atlas, piece)
	S.Art(tex, atlas, piece, x0 / pw, x1 / pw, y0 / ph, y1 / ph)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
	tex:SetWidth(math.max(w, 1))
	tex:SetHeight(math.max(h, 1))
end

-- A nine-slice of a piece: corners `cut` pixels of the art square (or { left, top, right, bottom }), drawn at
-- `scale` (default: whatever fits the frame's height), edges stretched only along their length, the middle
-- filling the rest. :SetPiece swaps in another piece with the same cuts; :Layout(w, h, x, y) lays it over a w by h
-- area of the frame (x, y in from its top left, default 0); :SetVertexColor, :SetAlpha, :SetBlendMode, :Show and
-- :Hide apply to all nine.
function S.NineSlice(frame, layer, atlas, piece, cut, scale)
	local cuts = type(cut) == "table" and cut or { cut, cut, cut, cut }
	local ns = { textures = {}, piece = piece }
	for i = 1, 9 do ns.textures[i] = frame:CreateTexture(nil, layer) end
	local function each(method, ...)
		for _, t in ipairs(ns.textures) do t[method](t, ...) end
	end
	function ns:SetVertexColor(...) each("SetVertexColor", ...) end
	function ns:SetAlpha(a) each("SetAlpha", a) end
	function ns:SetBlendMode(m) each("SetBlendMode", m) end
	function ns:Show() each("Show") end
	function ns:Hide() each("Hide") end
	function ns:SetPiece(p) self.piece = p if self.w then self:Layout(self.w, self.h, self.x, self.y) end end
	function ns:Layout(w, h, x, y)
		x, y = x or 0, y or 0
		self.w, self.h, self.x, self.y = w, h, x, y
		local pw, ph = S.ArtSize(atlas, self.piece)
		local k = scale or h / ph
		local sx = { 0, cuts[1], pw - cuts[3], pw }
		local sy = { 0, cuts[2], ph - cuts[4], ph }
		local dl, dt, dr, db = cuts[1] * k, cuts[2] * k, cuts[3] * k, cuts[4] * k
		local dx = { x, x + dl, x + w - dr, x + w }
		local dy = { y, y + dt, y + h - db, y + h }
		for row = 1, 3 do
			for col = 1, 3 do
				S.ArtPart(self.textures[(row - 1) * 3 + col], frame, atlas, self.piece, sx[col], sx[col + 1],
					sy[row], sy[row + 1], dx[col], dy[row], dx[col + 1] - dx[col], dy[row + 1] - dy[row])
			end
		end
	end
	return ns
end

-- A divider line in the skin's look, as a texture and its thickness. kind: "rule" under a title bar or a panel's
-- header (a skin whose frames are drawn borders can leave it out), "tabs" under a tab bar, "header" under a table's
-- column headers, "heading" beside a section heading.
local function line(parent, kind)
	return (skin.line or skins.material.line)(parent, kind)
end

-- A divider for a layout of your own: a texture to anchor and the thickness to give it. kind as above (default
-- "heading", a divider between groups of content).
function S.Divider(parent, kind)
	return line(parent, kind or "heading")
end

-- A vertical divider between two panes side by side: a frame to anchor by its top and bottom, centered in the gap
-- between them, and its width. A skin without a split of its own stands its divider line on end.
function S.VerticalDivider(parent)
	local holder = CreateFrame("Frame", nil, parent)
	local width
	if skin.split then
		width = skin.split(holder)
	else
		local t
		t, width = line(holder, "heading")
		t:SetAllPoints()
	end
	holder:SetWidth(width)
	return holder, width
end

-- A divider along one edge of a frame. kind: "rule" (default) under a title bar or a panel's header, "tabs" under a
-- tab bar, which a skin with tab art can draw where it leaves out the other rules.
function S.Rule(parent, where, kind)
	local t, h = line(parent, kind or "rule")
	t:SetHeight(h)
	t:SetPoint(where .. "LEFT")
	t:SetPoint(where .. "RIGHT")
	return t
end

local hidden = CreateFrame("Frame")
hidden:Hide()

-- Restyles a UIPanelScrollFrameTemplate bar as a thin flat track and thumb. ScrollFrame_OnScrollRangeChanged
-- shows the arrow buttons again on every range change, so they go under a hidden parent instead.
function S.ScrollBar(scroll, scrollName)
	local bar = _G[scrollName .. "ScrollBar"]
	_G[scrollName .. "ScrollBarScrollUpButton"]:SetParent(hidden)
	_G[scrollName .. "ScrollBarScrollDownButton"]:SetParent(hidden)
	bar:SetWidth(6)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	local track = S.Solid(bar, "BACKGROUND", S.colors.scrollTrack)
	track:SetAllPoints()
	bar:SetThumbTexture(WHITE)
	local thumb = bar:GetThumbTexture()
	thumb:SetSize(6, 40)
	thumb:SetVertexColor(unpack(S.colors.scrollThumb))
	bar:HookScript("OnEnter", function() thumb:SetVertexColor(unpack(S.colors.scrollThumbHover)) end)
	bar:HookScript("OnLeave", function() thumb:SetVertexColor(unpack(S.colors.scrollThumb)) end)
	return bar
end

-- The stock fonts' faces and sizes without their drop shadow, which smears dark text on light fills and blurs
-- small text on flat panels. S.SetFont gives a font string or edit box one of them, setting the face and size on
-- it directly as well as the font object: in game, with the stock fonts restyled by ElvUI, a font string given only
-- the object could be left with no font, and SetText then fails with "Font not set". S.FONTS[size] is the object.
local STOCK = { small = "GameFontHighlightSmall", normal = "GameFontHighlight", large = "GameFontHighlightLarge",
	huge = "GameFontNormalHuge", edit = "ChatFontNormal" }
local FALLBACK_SIZE = { small = 10, normal = 12, large = 16, huge = 20, edit = 14 }
S.FONTS = {}
for size in pairs(STOCK) do
	S.FONTS[size] = CreateFont(ADDON .. "Font" .. size:sub(1, 1):upper() .. size:sub(2))
end
local FONTS = S.FONTS
local specs = {}

-- Reads the stock fonts again. UI addons restyle them after this file loads, so windows run it as they're built.
function S.RefreshFonts()
	for size, base in pairs(STOCK) do
		local stock = _G[base]
		local face, height, flags
		if stock then face, height, flags = stock:GetFont() end
		local spec = { face = face or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
			height = (height or 0) > 0 and height or FALLBACK_SIZE[size], flags = flags or "" }
		specs[size] = spec
		local font = FONTS[size]
		font:SetFont(spec.face, spec.height, spec.flags)
		font:SetTextColor(1, 1, 1)
		font:SetShadowOffset(0, 0)
		font:SetShadowColor(0, 0, 0, 0)
	end
end
S.RefreshFonts()

function S.SetFont(region, size)
	local spec = specs[size or "normal"]
	region:SetFontObject(FONTS[size or "normal"])
	region:SetFont(spec.face, spec.height, spec.flags)
	region:SetShadowOffset(0, 0)
end

function S.FontString(parent, size, layer)
	local fs = parent:CreateFontString(nil, layer or "ARTWORK")
	S.SetFont(fs, size)
	return fs
end

function S.Text(parent, size, color, layer)
	local fs = S.FontString(parent, size, layer)
	fs:SetTextColor(unpack(color or S.colors.text))
	fs:SetJustifyH("LEFT")
	return fs
end

-- Text that wraps to its width and is as tall as its lines, for descriptions, notes and status lines that can run
-- long with a big font or a narrow skin. Give it a width (an S.Stack row does) and :Measure() is its height. It
-- must never be given a height: the client cuts text to fit one, with "...". Without one the client sizes it to its
-- wrapped lines. Its height can lag a width or text change until the client next draws it, which S.Stack allows for.
function S.Wrapped(parent, size, color, layer)
	local fs = S.Text(parent, size, color, layer)
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	fs:SetNonSpaceWrap(true)
	fs.wraps = true
	function fs:Measure()
		return math.ceil(math.max(self:GetHeight() or 0, self:GetStringHeight() or 0))
	end
	return fs
end

-- A column of regions placed top to bottom inside `parent`, each below the one before, so text that wraps to more
-- lines pushes everything under it down. opts: left, top (the first row's offset, default the skin's inset), width
-- (default the parent's width less the inset on both sides). :Add(region, { gap, indent, fill, height }) adds a row:
-- `gap` above it (default S.GAP, none for the first), `indent` from the left, `fill` to give it the column's width
-- (S.Wrapped text always gets it), `height` for a row whose height isn't its own (a fixed number, or a function).
-- :Layout() places the shown rows and returns where the column ends, from the parent's top, to size the parent by.
-- Wrapped text measures its new lines only once the client has drawn it, so the stack lays out again on the next
-- frame; opts.onLayout(bottom) runs after each pass, the place to size the parent.
local Stack = {}
Stack.__index = Stack

function S.Stack(parent, opts)
	opts = opts or {}
	local inset = S.metrics.inset
	local self = setmetatable({ parent = parent, rows = {}, left = opts.left or inset, top = opts.top or inset,
		width = opts.width, onLayout = opts.onLayout }, Stack)
	self.later = CreateFrame("Frame")
	self.later:Hide()
	self.later:SetScript("OnUpdate", function(later)
		later:Hide()
		self:Place()
	end)
	return self
end

function Stack:Width()
	return self.width or ((self.parent:GetWidth() or 0) - 2 * S.metrics.inset)
end

-- A filled row gets its width at once, so the client can start wrapping its text before the first layout.
function Stack:Add(region, opts)
	opts = opts or {}
	local row = { region = region, gap = opts.gap, indent = opts.indent or 0, fill = opts.fill or region.wraps == true,
		height = opts.height }
	self.rows[#self.rows + 1] = row
	if row.fill and self:Width() > 0 then region:SetWidth(self:Width() - row.indent) end
	return region
end

local function rowHeight(row)
	local h = row.height
	if type(h) == "function" then h = h(row.region) end
	return h or (row.region.wraps and row.region:Measure()) or row.region:GetHeight() or 0
end

-- One pass: places the shown rows and tells onLayout where the column ends.
function Stack:Place()
	local width = self:Width()
	local y, first = self.top, true
	for _, row in ipairs(self.rows) do
		local region = row.region
		if region:IsShown() then
			if not first then y = y + (row.gap or S.GAP) end
			first = false
			region:ClearAllPoints()
			region:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.left + row.indent, -y)
			if row.fill then region:SetWidth(width - row.indent) end
			y = y + rowHeight(row)
		end
	end
	if self.onLayout then self.onLayout(y) end
	return y
end

function Stack:Layout()
	self.later:Show()
	return self:Place()
end

-- Widgets are painted by the skin that built them: one made before the saved skin goes on (an Interface Options
-- panel built at file load) has only that skin's textures.
local function paint(b)
	b.skin.paintButton(b, b:IsEnabled() == 1 or b:IsEnabled() == true)
end

-- `template` makes it from a frame template; a secure one keeps the template's own click handler, so onClick is
-- left unset (hook OnClick instead).
function S.Button(parent, label, kind, width, onClick, tooltip, template)
	local b = CreateFrame("Button", nil, parent, template)
	b:SetSize(width or 90, S.CONTROL_H)
	b.kind = kind or "secondary"
	b.skin = skin
	skin.button(b)
	b.label = S.FontString(b, "small")
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b.tooltipText = tooltip
	if not template then b:SetScript("OnClick", onClick) end
	-- held down, for skins with a pressed look
	b:HookScript("OnMouseDown", function(self)
		self.down = true
		paint(self)
	end)
	b:HookScript("OnMouseUp", function(self)
		self.down = false
		paint(self)
	end)
	b:SetScript("OnEnter", function(self)
		self.hovered = true
		paint(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hovered = false
		self.down = false
		paint(self)
		GameTooltip:Hide()
	end)
	b:HookScript("OnEnable", paint)
	b:HookScript("OnDisable", paint)
	-- a segmented button's halves overlap by their shared 1px border; the selected half sits one level up so
	-- its tinted border is drawn whole
	function b:SetKind(newKind)
		self.kind = newKind
		self:SetFrameLevel(parent:GetFrameLevel() + (newKind == "selected" and 2 or 1))
		paint(self)
	end
	function b:SetLabel(text)
		self.label:SetText(text)
		self:SetWidth(math.max(self.minWidth or 70, self.label:GetStringWidth() + 24))
		paint(self)
	end
	-- changes the label and keeps the width; the button's own SetText would set a text it doesn't show
	function b:SetText(text)
		self.label:SetText(text)
	end
	b.minWidth = width
	paint(b)
	return b
end

-- a skin without its own checkbox draws Material's
local function checkSkin() return skin.check and skin or skins.material end

local function paintCheck(b)
	b.skin.paintCheck(b)
end

-- Square checkbox, S.CHECK_H by default: SetChecked(on) and SetEnabled(on) repaint it; clicks
-- go to onClick(box).
function S.Check(parent, size, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or S.CHECK_H, size or S.CHECK_H)
	b.on, b.usable = false, true
	b.skin = checkSkin()
	b.skin.check(b)
	function b:SetChecked(on) self.on = on and true or false paintCheck(self) end
	function b:SetEnabled(on) self.usable = on and true or false paintCheck(self) end
	b:SetScript("OnEnter", function(self)
		self.hovered = true
		paintCheck(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hovered = false
		paintCheck(self)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		if self.usable and onClick then onClick(self) end
	end)
	paintCheck(b)
	return b
end

-- a skin without its own slider draws Material's
local function sliderSkin() return skin.slider and skin or skins.material end

local function paintSlider(s)
	s.skin.paintSlider(s)
end

-- the room a slider's value text takes to its right, past S.GAP
S.SLIDER_VALUE_W = 40

-- Horizontal slider from min to max in steps of step, `width` wide and S.CONTROL_H tall; click the track or drag
-- the handle. Its value shows to its right (s.valueText, S.SLIDER_VALUE_W wide, S.GAP away), written by
-- format(value) or as a number. onChange(value, s) runs for the user's changes only; s:SetValue(v) sets it quietly.
-- s:SetEnabled(on) greys it out.
function S.Slider(parent, width, min, max, step, onChange, format)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width, S.CONTROL_H)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:EnableMouse(true)
	s.min, s.max, s.step, s.usable = min, max, step, true
	s.format = format or function(v) return tostring(v) end
	s.valueText = S.Text(s, "small")
	s.valueText:SetPoint("LEFT", s, "RIGHT", S.GAP, 0)
	s.valueText:SetWidth(S.SLIDER_VALUE_W)
	s.skin = sliderSkin()
	s.skin.slider(s)
	-- the client's own value drifts off the steps while dragging: snap it, and drop float noise
	local function snap(v)
		local n = math.floor((v - min) / step + 0.5)
		return tonumber(("%.4f"):format(math.max(min, math.min(max, min + n * step))))
	end
	local quiet = false
	local setValue = s.SetValue
	function s:SetValue(v)
		self.value = snap(v)
		quiet = true
		setValue(self, self.value)
		quiet = false
		self.valueText:SetText(self.format(self.value))
	end
	function s:GetValue() return self.value end
	function s:SetEnabled(on)
		self.usable = on and true or false
		self:EnableMouse(self.usable)
		paintSlider(self)
	end
	s:SetScript("OnValueChanged", function(self, v)
		local value = snap(v)
		if not quiet and value ~= self.value then
			self.value = value
			self.valueText:SetText(self.format(value))
			if onChange then onChange(value, self) end
		end
	end)
	s:SetScript("OnEnter", function(self)
		self.hovered = true
		paintSlider(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	s:SetScript("OnLeave", function(self)
		self.hovered = false
		paintSlider(self)
		GameTooltip:Hide()
	end)
	s:SetValue(min)
	paintSlider(s)
	return s
end

-- a skin without its own progress bar draws Material's
local function progressSkin() return skin.progressBar and skin or skins.material end

-- A bar filled to how much of something is done, `width` by `height` (4 by default): p:SetValue(done, total) fills
-- it to done / total and turns it the good color once all is done. Writes nothing when the value is unchanged, so it
-- can be set every frame.
function S.ProgressBar(parent, width, height)
	local p = CreateFrame("Frame", nil, parent)
	p:SetSize(width, height or 4)
	p.share, p.complete = 0, false
	p.skin = progressSkin()
	p.skin.progressBar(p)
	local function layout(self)
		local w = (self:GetWidth() or 0) * self.share
		if w > 0 then
			self.fill:SetWidth(w)
			self.fill:Show()
		else
			self.fill:Hide()
		end
	end
	function p:SetValue(done, total)
		local share = (total or 0) > 0 and math.max(0, math.min(1, done / total)) or 0
		local complete = (total or 0) > 0 and done >= total
		if share ~= self.share or complete ~= self.complete then
			self.share, self.complete = share, complete
			layout(self)
			self.skin.paintProgress(self)
		end
	end
	function p:GetValue() return self.share end
	p:SetScript("OnSizeChanged", layout)
	layout(p)
	p.skin.paintProgress(p)
	return p
end

local menus, inputs, dismissers = {}, {}, {}

-- Runs fn whenever S.Dismiss does, for other things that shouldn't outlive their view.
function S.OnDismiss(fn)
	dismissers[#dismissers + 1] = fn
end

-- A popup that closes like a dropdown menu: on a click outside it and its popup.owner, and on S.Dismiss.
function S.TrackPopup(popup)
	menus[#menus + 1] = popup
end

function S.CloseMenus()
	for _, menu in ipairs(menus) do menu:Hide() end
end

-- Edit boxes S.Dismiss and outside clicks clear. S.Input tracks its own; the other edit boxes call this once their
-- scripts are set. `area` is what counts as clicking on it, for a box inside a larger panel (default: the box).
function S.TrackInput(e, area)
	e:HookScript("OnEditFocusGained", function(self) self.focused = true end)
	e:HookScript("OnEditFocusLost", function(self) self.focused = false end)
	e.clickArea = area
	inputs[#inputs + 1] = e
end

-- Closes every dropdown menu and takes keyboard focus from every edit box. Neither goes away when its view is
-- covered or replaced (a menu only hides with its dropdown, and a hidden edit box keeps the keyboard), so views
-- that do that (switching tabs, opening a dialog, closing the window) call this.
function S.Dismiss()
	S.CloseMenus()
	for _, e in ipairs(inputs) do
		if e.focused then e:ClearFocus() end
	end
	for _, fn in ipairs(dismissers) do fn() end
end

-- A mouse press anywhere else closes an open menu and takes focus from an edit box. The client has no event for
-- presses outside a frame, so this watches for a button going down while either is open.
function S.ClickedAway()
	for _, menu in ipairs(menus) do
		if menu:IsShown() and not MouseIsOver(menu) and not MouseIsOver(menu.owner) then menu:Hide() end
	end
	for _, e in ipairs(inputs) do
		if e.focused and not MouseIsOver(e.clickArea or e) then e:ClearFocus() end
	end
end

local wasDown = false
local clicks = CreateFrame("Frame")
clicks:SetScript("OnUpdate", function()
	local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
	if down and not wasDown then S.ClickedAway() end
	wasDown = down
end)

-- A section heading in a navigation list: small dim text with a rule running from it to the right edge, so it
-- reads as a divider rather than one of the entries under it.
function S.SectionHeading(parent, text, x, y, rightInset)
	local label = S.Text(parent, "small", S.colors.outline)
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(text)
	local rule, h = line(parent, "heading")
	rule:SetHeight(h)
	rule:SetPoint("LEFT", label, "RIGHT", 6, 0)
	rule:SetPoint("RIGHT", parent, "RIGHT", -(rightInset or x), 0)
	return label, rule
end

-- Gives a button a dropdown's arrow and left-aligned label, for buttons that open a list (a menu or a picker).
function S.AddArrow(b)
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetPoint("RIGHT", -24, 0)
	b.label:SetJustifyH("LEFT")
	local arrow = b:CreateTexture(nil, "OVERLAY")
	-- Blizzard's sort arrow, cropped and sized as its auction column headers do (the arrow fills the left 9/16 of
	-- the texture); its point sits near the top of that box, so it's dropped 2px to line up with the label's middle
	arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
	arrow:SetTexCoord(0, 0.5625, 0, 1)
	arrow:SetSize(9, 8)
	arrow:SetPoint("RIGHT", -10, -2)
	arrow:SetDesaturated(true)
	arrow:SetVertexColor(unpack(S.colors.arrow))
	b.arrow = arrow
	return b
end

-- The preview card beside a dropdown's menu, while an item with a preview is hovered.
local shownPreview
local function showPreview(menu, card)
	if shownPreview and shownPreview ~= card then shownPreview:Hide() end
	shownPreview = card
	if card then
		card:SetScale(menu:GetEffectiveScale() / UIParent:GetEffectiveScale())
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", menu, "TOPRIGHT", 4, 0)
		card:Show()
	end
end

-- Flat dropdown: a button showing the current choice that opens a menu below it. SetOptions takes
-- { { value, text, tooltip, preview } }, preview() giving a frame shown beside the menu while the item is hovered,
-- in place of its tooltip; picking one calls onSelect(value) and closes the menu. Opening one closes the others.
function S.Dropdown(parent, width, onSelect)
	local b = S.AddArrow(S.Button(parent, "", "secondary", width))

	local menu = CreateFrame("Frame", nil, b)
	-- above DIALOG, so the menu covers the controls of the dialog it opens from
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(width)
	S.Frame(menu, "menu")
	menu:EnableMouse(true)
	menu:Hide()
	menu:SetScript("OnHide", function(m) showPreview(m, nil) end)
	menus[#menus + 1] = menu
	menu.owner = b
	b.menu, b.items = menu, {}

	function b:SetText(text) self.label:SetText(text) end
	function b:SetOptions(options)
		for i, opt in ipairs(options) do
			local item = self.items[i]
			if not item then
				item = CreateFrame("Button", nil, menu)
				item:SetHeight(S.CONTROL_H)
				local m = S.metrics.menuInset
				item:SetPoint("TOPLEFT", m, -m - (i - 1) * S.CONTROL_H)
				item:SetPoint("TOPRIGHT", -m, -m - (i - 1) * S.CONTROL_H)
				S.Highlight(item)
				item.text = S.Text(item, "small")
				item.text:SetPoint("LEFT", 8, 0)
				item.text:SetPoint("RIGHT", -8, 0)
				item:SetScript("OnClick", function(it)
					menu:Hide()
					onSelect(it.value)
				end)
				item:SetScript("OnEnter", function(it)
					if it.preview then
						showPreview(menu, it.preview())
					elseif it.tooltip then
						GameTooltip:SetOwner(it, "ANCHOR_RIGHT")
						GameTooltip:SetText(it.tooltip, nil, nil, nil, nil, true)
						GameTooltip:Show()
					end
				end)
				item:SetScript("OnLeave", function()
					showPreview(menu, nil)
					GameTooltip:Hide()
				end)
				self.items[i] = item
			end
			item.value, item.tooltip, item.preview = opt.value, opt.tooltip, opt.preview
			item.text:SetText(opt.text)
			item:Show()
		end
		for i = #options + 1, #self.items do self.items[i]:Hide() end
		menu:SetHeight(#options * S.CONTROL_H + 2 * S.metrics.menuInset)
	end
	b:SetScript("OnClick", function()
		local open = menu:IsShown()
		S.CloseMenus()
		if not open then
			-- opened on UIParent at the dropdown's scale: inside a scroll frame the menu would stay in the scroll
			-- frame's layer, under the controls after it, and be clipped at its edge
			menu:SetParent(UIParent)
			menu:SetScale(b:GetEffectiveScale() / UIParent:GetEffectiveScale())
			menu:SetFrameStrata("FULLSCREEN_DIALOG")
			menu:Show()
		end
	end)
	b:HookScript("OnHide", function() menu:Hide() end)
	return b
end

-- Right-click menu: one menu serves any number of rows. menu:Open(owner, options, side) shows it beside owner
-- (the clicked row), on its right for side "RIGHT", else its left, with options { { text, action, disabled,
-- danger, tooltip } }; danger draws an item in the error color. Picking one closes the menu and runs its action.
-- Opening it closes the other menus; a click elsewhere closes it, as a dropdown's does.
local CONTEXT_MIN_W = 150
function S.ContextMenu()
	local menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetWidth(CONTEXT_MIN_W)
	S.Frame(menu, "menu")
	menu:EnableMouse(true)
	menu:Hide()
	menus[#menus + 1] = menu
	menu.items = {}

	local function item(i)
		local it = menu.items[i]
		if not it then
			it = CreateFrame("Button", nil, menu)
			it:SetHeight(S.CONTROL_H)
			local m = S.metrics.menuInset
			it:SetPoint("TOPLEFT", m, -m - (i - 1) * S.CONTROL_H)
			it:SetPoint("TOPRIGHT", -m, -m - (i - 1) * S.CONTROL_H)
			S.Highlight(it)
			it.text = S.Text(it, "small")
			it.text:SetPoint("LEFT", 8, 0)
			it.text:SetPoint("RIGHT", -8, 0)
			it:SetScript("OnClick", function(self)
				menu:Hide()
				self.action()
			end)
			it:SetScript("OnEnter", function(self)
				if self.tooltip then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true)
					GameTooltip:Show()
				end
			end)
			it:SetScript("OnLeave", function() GameTooltip:Hide() end)
			menu.items[i] = it
		end
		return it
	end

	function menu:Open(owner, options, side)
		local c, width = S.colors, CONTEXT_MIN_W
		for i, opt in ipairs(options) do
			local it = item(i)
			it.text:SetText(opt.text)
			it.text:SetTextColor(unpack(opt.disabled and c.disabled or opt.danger and c.bad or c.text))
			it.action, it.tooltip = opt.action, opt.tooltip
			if opt.disabled then it:Disable() else it:Enable() end
			it:Show()
			width = math.max(width, it.text:GetStringWidth() + 16 + 2 * S.metrics.menuInset)
		end
		for i = #options + 1, #self.items do self.items[i]:Hide() end
		self:SetWidth(width)
		self:SetHeight(#options * S.CONTROL_H + 2 * S.metrics.menuInset)
		S.CloseMenus()
		self.owner = owner
		-- at the row's scale, on UIParent so a scroll frame neither clips it nor layers it under what follows
		self:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
		self:ClearAllPoints()
		if side == "RIGHT" then
			self:SetPoint("TOPLEFT", owner, "TOPRIGHT", 2, 0)
		else
			self:SetPoint("TOPRIGHT", owner, "TOPLEFT", -2, 0)
		end
		self:Show()
	end
	return menu
end

-- Input with a placeholder shown while it's empty and unfocused. Never takes focus on its own. With lines above 1
-- it's a taller box whose text wraps; Enter still finishes, and GetText turns any line break into a space.
-- A multi-line edit box sizes its own height to its text, so a tall one is pinned by both corners inside e.box, a
-- frame at the height asked for, which its box is drawn on. Placing or sizing the input places or sizes e.box, so
-- the edit box, and anything anchored to it, keeps that height.
function S.Input(parent, name, width, placeholder, maxLetters, lines)
	local e = CreateFrame("EditBox", name, parent)
	local tall = (lines or 1) > 1
	local wi = tall and S.metrics.wellInset or 0
	local height = tall and (lines * 13 + 12 + 2 * wi) or S.CONTROL_H
	S.SetFont(e, "small")
	e:SetAutoFocus(false)
	e:SetMaxLetters(maxLetters or 40)
	if tall then
		local box = CreateFrame("Frame", nil, parent)
		box:SetSize(width, height)
		box:EnableMouse(true)
		box:SetScript("OnMouseDown", function() e:SetFocus() end)
		e:SetFrameLevel(box:GetFrameLevel() + 1)
		e:SetPoint("TOPLEFT", box, "TOPLEFT")
		e:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
		local show, hide = e.Show, e.Hide
		function e:Show() show(self) box:Show() end
		function e:Hide() hide(self) box:Hide() end
		for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "GetPoint", "SetSize", "SetWidth",
			"SetHeight", "GetWidth", "GetHeight" }) do
			e[method] = function(_, ...) return box[method](box, ...) end
		end
		e.box = box
	else
		e:SetSize(width, height)
	end
	e.skin = skin
	skin.input(e, tall)
	e.placeholder = S.Text(e, "small", S.colors.muted)
	if tall then
		e:SetMultiLine(true)
		e:SetTextInsets(8 + wi, 8 + wi, 6 + wi, 6 + wi)
		e.placeholder:SetPoint("TOPLEFT", 8 + wi, -6 - wi)
		e.placeholder:SetPoint("TOPRIGHT", -8 - wi, -6 - wi)
		local getText = e.GetText
		e.GetText = function(self) return ((getText(self) or ""):gsub("[\r\n]", " ")) end
		e:SetScript("OnEnterPressed", e.ClearFocus)
	else
		e:SetTextInsets(8, 8, 0, 0)
		e.placeholder:SetPoint("LEFT", 8, 0)
		e.placeholder:SetPoint("RIGHT", -8, 0)
	end
	e.placeholder:SetJustifyH("LEFT")
	e.placeholder:SetWordWrap(false)
	e.placeholder:SetText(placeholder or "")
	local function update(self)
		if self.focused or self:GetText() ~= "" then self.placeholder:Hide() else self.placeholder:Show() end
		self.skin.paintInput(self)
	end
	e:SetScript("OnEditFocusGained", function(self) self.focused = true update(self) end)
	e:SetScript("OnEditFocusLost", function(self) self.focused = false update(self) end)
	e:SetScript("OnEnter", function(self) self.hovered = true update(self) end)
	e:SetScript("OnLeave", function(self) self.hovered = false update(self) end)
	if tall then
		e.box:SetScript("OnEnter", function() e.hovered = true update(e) end)
		e.box:SetScript("OnLeave", function() e.hovered = false update(e) end)
	end
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:HookScript("OnTextChanged", update)
	e.UpdatePlaceholder = update
	update(e)
	inputs[#inputs + 1] = e
	return e
end

-- Frame decoration in the skin's look. role: "window" for a main window (S.metrics.edge says how far in its
-- content has to start), "popup" for a dialog or picker (S.metrics.inset is the padding inside it), "menu" for a
-- small list that drops from a control.
function S.Frame(frame, role)
	skin.frame(frame, role or "popup")
	return frame
end

-- A sunken area holding text or a list, such as a multi-line text box's surround.
function S.Well(frame)
	skin.well(frame)
	return frame
end

-- The background of a window's navigation sidebar, with its dividing edge on the right.
function S.Sidebar(side)
	skin.sidebar(side)
	return side
end

-- The hover look for a clickable row: a menu item, a list entry, a column heading.
function S.Highlight(frame)
	skin.highlight(frame)
	return frame
end

local function rowSkin() return skin.row and skin or skins.material end

-- A list or table row's hover and selected look; bar asks for an accent bar on the selected row where the skin
-- draws one. S.PaintRow(row, on) shows it selected or not.
function S.Row(row, bar)
	row.skin = rowSkin()
	row.skin.row(row, bar)
	S.PaintRow(row, false)
	return row
end

function S.PaintRow(row, on)
	(row.skin or rowSkin()).paintRow(row, on)
end

-- An entry in a navigation sidebar: its label (b.label, in the "normal" size) and its hover and selected look.
-- With an icon texture, b.icon sits where the skin puts the label and the label moves right of it.
-- b:SetSelected(on) repaints it.
local NAV_ICON = 18
function S.NavEntry(b, text, icon)
	b.label = S.Text(b, "normal")
	b.label:SetText(text)
	b.skin = skin
	skin.navEntry(b)
	if icon then
		local _, _, _, x = b.label:GetPoint()
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(NAV_ICON, NAV_ICON)
		b.icon:SetPoint("LEFT", x or S.PAD, 0)
		-- crops the uneven dark frame around Blizzard's icon art
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.icon:SetTexture(icon)
		b.label:ClearAllPoints()
		b.label:SetPoint("LEFT", (x or S.PAD) + NAV_ICON + 6, 0)
	end
	function b:SetSelected(on)
		self.selected = on
		self.skin.paintNav(self, on)
		self.label:SetTextColor(unpack(on and S.colors.navSelected or S.colors.text))
	end
	b:SetSelected(false)
	return b
end

-- A tab in a tab bar: its label (b.label, in the "normal" size, S.metrics.tabPad in from its left) and the skin's
-- hover and selected look, in a button the caller has given its height. b:SetSelected(on) repaints it. The caller
-- sizes the tabs (tabPad either side of the label), places them, and draws the bar's S.Rule of kind "tabs".
function S.Tab(b, text)
	b.label = S.Text(b, "normal")
	b.label:SetPoint("LEFT", S.metrics.tabPad, 0)
	b.label:SetText(text)
	local paintTab = skin.paintTab or skins.material.paintTab
	local drawTab = skin.tab or skins.material.tab
	drawTab(b)
	function b:SetSelected(on)
		self.selected = on
		paintTab(self, on)
		self.label:SetTextColor(unpack(on and S.colors.text or S.colors.muted))
	end
	b:SetSelected(false)
	return b
end

-- A grip: two columns of three dots, the usual sign that something drags. It's a frame 6 wide and 12 tall, in the
-- muted color unless given one; SetColor recolors it.
local GRIP_DOT, GRIP_STEP_X, GRIP_STEP_Y = 2, 4, 5
function S.Grip(parent, color)
	local grip = CreateFrame("Frame", nil, parent)
	grip:SetSize(GRIP_DOT + GRIP_STEP_X, GRIP_DOT + 2 * GRIP_STEP_Y)
	grip.dots = {}
	for col = 0, 1 do
		for line = 0, 2 do
			local dot = S.Solid(grip, "ARTWORK", color or S.colors.muted)
			dot:SetSize(GRIP_DOT, GRIP_DOT)
			dot:SetPoint("TOPLEFT", col * GRIP_STEP_X, -line * GRIP_STEP_Y)
			grip.dots[#grip.dots + 1] = dot
		end
	end
	function grip:SetColor(c)
		for _, dot in ipairs(self.dots) do dot:SetVertexColor(unpack(c)) end
	end
	return grip
end

-- Drag to reorder: rows of a list dragged into a new order. A row is any frame with moveIndex set (its item's
-- index, 1 to n; nil for a row that doesn't move, like a header), so pooled and scrolling lists work as long as they
-- keep moveIndex current. While a row is dragged it dims, an accent line marks the gap it would land in, its name
-- follows the cursor, and holding it at the top or bottom edge of the list's area scrolls. Letting go anywhere
-- drops it. opts: rows (an array of the row frames; rows added to it later count too), lineParent (the frame the
-- line draws in, the rows' parent, so a scroll frame clips it), area (the frame whose edges scroll), scroll(step)
-- (-1 up, 1 down), onMove(from, to) (to is the index after the move; the caller moves the item).
local Reorder = {}
S.Reorder = Reorder

local REORDER_SCROLL_EVERY, REORDER_EDGE, DRAGGED_ALPHA = 0.08, 12, 0.4

-- The gap under the cursor: the number of items above it, from 0 to the last index.
local function reorderSlot(self, y)
	local slot, last = nil, 0
	for _, row in ipairs(self.rows) do
		local i, top, bottom = row.moveIndex, row:GetTop(), row:GetBottom()
		if i and top and bottom and row:IsShown() then
			if i > last then last = i end
			if y / row:GetEffectiveScale() > (top + bottom) / 2 and (not slot or i - 1 < slot) then slot = i - 1 end
		end
	end
	return slot or last
end

local function rowAt(self, index)
	for _, row in ipairs(self.rows) do
		if row.moveIndex == index and row:IsShown() then return row end
	end
	return nil
end

local function placeLine(self)
	local mark, slot, from = self.line, self.slot, self.from
	local below = rowAt(self, slot + 1)
	local above = not below and rowAt(self, slot)
	mark:ClearAllPoints()
	if slot ~= from and slot ~= from - 1 and (below or above) then
		local edge = below and "TOP" or "BOTTOM"
		mark:SetPoint("LEFT", below or above, edge .. "LEFT", 0, 0)
		mark:SetPoint("RIGHT", below or above, edge .. "RIGHT", 0, 0)
		mark:Show()
	else
		mark:Hide()
	end
end

local function updateReorder(self)
	if self.from and IsMouseButtonDown("LeftButton") then
		local x, y = GetCursorPosition()
		local area, now = self.area, GetTime()
		local scale = area and area:GetEffectiveScale() or 1
		local top, bottom = area and area:GetTop(), area and area:GetBottom()
		local step = (top and y / scale > top - REORDER_EDGE and -1) or (bottom and y / scale < bottom + REORDER_EDGE and 1) or 0
		if step ~= 0 and self.scroll and now >= self.scrollAt then
			self.scrollAt = now + REORDER_SCROLL_EVERY
			self.scroll(step)
		end
		self.slot = reorderSlot(self, y)
		placeLine(self)
		for _, row in ipairs(self.rows) do row:SetAlpha(row.moveIndex == self.from and DRAGGED_ALPHA or 1) end
		local ui = UIParent:GetEffectiveScale()
		self.ghost:ClearAllPoints()
		self.ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / ui + 14, y / ui)
	else
		self:Stop(true)
	end
end

function Reorder.New(opts)
	local C = S.colors
	local self = setmetatable({ rows = opts.rows, area = opts.area, scroll = opts.scroll, onMove = opts.onMove },
		{ __index = Reorder })
	local layer = CreateFrame("Frame", nil, opts.lineParent)
	layer:SetAllPoints(opts.lineParent)
	layer:SetFrameLevel(opts.lineParent:GetFrameLevel() + 6)
	layer:Hide()
	layer:SetScript("OnUpdate", function() updateReorder(self) end)
	layer:SetScript("OnHide", function() self:Stop(false) end)
	self.layer = layer
	self.line = S.Solid(layer, "OVERLAY", C.accent)
	self.line:SetHeight(2)
	self.line:Hide()
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	S.Solid(ghost, "BACKGROUND", C.panel):SetAllPoints()
	S.Solid(ghost, "BORDER", C.rowSelected):SetAllPoints()
	ghost.text = S.Text(ghost, "small")
	ghost.text:SetPoint("LEFT", 8, 0)
	ghost:Hide()
	self.ghost = ghost
	return self
end

-- Makes button start a drag of row (the button itself unless given), with label(row) as the text by the cursor.
function Reorder:Attach(button, label, row)
	row = row or button
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function() self:Start(row, label and label(row) or "") end)
	button:SetScript("OnDragStop", function() self:Stop(true) end)
end

function Reorder:Start(row, text)
	if row.moveIndex then
		GameTooltip:Hide()
		self.from, self.slot, self.scrollAt = row.moveIndex, row.moveIndex, 0
		self.ghost.text:SetText(text or "")
		self.ghost:SetSize(math.ceil(self.ghost.text:GetStringWidth()) + 16, 20)
		row:SetAlpha(DRAGGED_ALPHA)
		self.layer:Show()
		self.ghost:Show()
	end
end

function Reorder:Stop(drop)
	local from, slot = self.from, self.slot
	self.from = nil
	self.layer:Hide()
	self.ghost:Hide()
	if from then
		self.endedAt = GetTime()
		for _, row in ipairs(self.rows) do row:SetAlpha(1) end
		local to = slot < from and slot + 1 or slot
		if drop and to ~= from then self.onMove(from, to) end
	end
end

-- True while a row is dragged and on the frame a drag ended, when the release that ends it isn't a click.
function Reorder:Busy()
	return self.from ~= nil or self.endedAt == GetTime()
end

-- Tables: a virtual table, a fixed pool of rows drawn over any number of items, with sortable column headers, a
-- thin scroll bar and mouse wheel scrolling, in an S.Well. The first column can carry an icon.
local Table = {}
S.Table = Table

local HEADER_H, WHEEL_ROWS, BAR_SPACE = 22, 3, 10

local function newRow(self, i)
	local C = S.colors
	local row = CreateFrame("Button", nil, self.content)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHeight(self.rowH)
	row:SetPoint("TOPLEFT", 0, -self.bodyTop - (i - 1) * self.rowH)
	row:SetPoint("TOPRIGHT", 0, -self.bodyTop - (i - 1) * self.rowH)
	if i % 2 == 0 then
		local stripe = S.Solid(row, "BACKGROUND", { C.text[1], C.text[2], C.text[3], 0.025 })
		stripe:SetAllPoints()
	end
	S.Row(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(self.rowH - 4, self.rowH - 4)
	-- crops the dark frame Blizzard's icon art has around its edge, which is uneven and makes icons look off-center
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.cells = {}
	for c, col in ipairs(self.columns) do
		local fs = S.Text(row, "small")
		fs:SetJustifyH(col.justify or "LEFT")
		fs:SetHeight(self.rowH)
		row.cells[c] = fs
	end
	if self.icons then row.icon:SetPoint("LEFT", row, "LEFT", self.columns[1].x + 6, 0) end
	-- a group header row: one label across the row on the header color
	row.headerTex = S.Solid(row, "BACKGROUND", C.panel)
	row.headerTex:SetDrawLayer("BACKGROUND", 1)
	row.headerTex:SetAllPoints()
	row.headerTex:Hide()
	row.headerText = S.Text(row, "small", C.heading)
	row.headerText:SetPoint("LEFT", 6, 0)
	row.headerText:SetPoint("RIGHT", -6 - BAR_SPACE, 0)
	row.headerText:Hide()
	if self.headerColor then
		row.headerRule = S.Solid(row, "ARTWORK", C.heading)
		row.headerRule:SetHeight(1)
		row.headerRule:SetPoint("BOTTOMLEFT", 6, 0)
		row.headerRule:SetPoint("BOTTOMRIGHT", -6 - BAR_SPACE, 0)
		row.headerRule:Hide()
	end
	if i == 1 and self.stickyHeaders then
		-- marks the top row's header as held in place, with the group's rows passing under it
		local rule, ruleH = line(row, "header")
		rule:SetHeight(ruleH)
		rule:SetPoint("BOTTOMLEFT")
		rule:SetPoint("BOTTOMRIGHT")
		rule:Hide()
		row.stickyRule = rule
	end

	-- the row's item, or nil for an empty row or a group heading, which get no tooltip and no clicks unless the
	-- table takes header clicks
	local function itemOf(r)
		local item = r.item
		return item and (self.headerClicks or not (self.header and self.header(item))) and item or nil
	end
	row:SetScript("OnEnter", function(r)
		local item = itemOf(r)
		if item and self.tooltip then
			GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
			self.tooltip(GameTooltip, item)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(r, button)
		local item = itemOf(r)
		-- the release that ends a drag isn't a click
		if item and self.onClick and not (self.reorder and self.reorder:Busy()) then self.onClick(item, button, r) end
	end)
	if self.reorder then
		self.reorder:Attach(row, function(r) return r.item and self.cell(r.item, self.columns[1].key) end)
	end
	return row
end

local function paintHeader(self)
	for _, h in ipairs(self.headers) do
		local on = self.sortKey == h.col.key
		h.label:SetTextColor(unpack(on and S.colors.heading or S.colors.muted))
		if on then
			h.arrow:SetTexCoord(0, 0.5625, self.sortDesc and 0 or 1, self.sortDesc and 1 or 0)
			h.arrow:Show()
		else
			h.arrow:Hide()
		end
	end
end

-- The narrowest a column can be and still show its whole header: the label, its padding and the sort arrow's
-- space, plus the scroll bar's for the last column.
local function headerWidth(self, c, col)
	local need = 0
	if col.label and col.label ~= "" then
		need = math.ceil(self.headers[c].label:GetStringWidth()) + 6 + 16 + 2 + (col.barInset or 0)
	end
	return need
end

-- Places the shown columns left to right. Each is at least as wide as its header needs; the shown column marked
-- stretch (else the first shown, usually the primary one) takes the spare width, such as a hidden column's, or
-- gives up what the others needed. The last shown keeps its text clear of the scroll bar, since the rows run under
-- the bar to the table's edge.
local function layout(self)
	local first, last, stretch = nil, nil, nil
	for _, col in ipairs(self.columns) do
		col.width, col.barInset = col.baseWidth, nil
		if not col.hidden then
			first = first or col
			last = col
			if col.stretch and not stretch then stretch = col end
		end
	end
	stretch = stretch or first
	if last then
		last.barInset = BAR_SPACE
		local used = 0
		for c, col in ipairs(self.columns) do
			if not col.hidden then
				col.width = math.max(col.width, headerWidth(self, c, col))
				used = used + col.width
			end
		end
		stretch.width = stretch.width + self.innerW - used
	end
	local x = 0
	for _, col in ipairs(self.columns) do
		col.x = x
		if not col.hidden then x = x + col.width end
	end
	for c, col in ipairs(self.columns) do
		local h = self.headers[c]
		h:SetSize(col.width, HEADER_H)
		h:SetPoint("TOPLEFT", col.x, 0)
		h.label:SetPoint("RIGHT", -16 - (col.barInset or 0), 0)
		h.arrow:SetPoint("RIGHT", -4 - (col.barInset or 0), 0)
		if col.hidden or self.plain then h:Hide() else h:Show() end
		local inset = (c == 1 and self.icons) and self.rowH or 0
		for _, row in ipairs(self.rows) do
			local fs = row.cells[c]
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", row, "LEFT", col.x + 6 + inset, 0)
			fs:SetWidth(col.width - 12 - (col.barInset or 0) - inset)
			if col.hidden then fs:Hide() else fs:Show() end
		end
	end
end

-- opts: columns = { { key, label, width, justify, sortable, defaultDesc, tooltip, stretch } }, rowH, icons (the
-- first column has an icon), cell(item, key) -> text, color, icon(item) -> texture, tooltip(tt, item),
-- onClick(item, button, row) (row: the clicked row, to open an S.ContextMenu beside), onSort(key, desc), header(item) -> label when the item is a group header row,
-- headerClicks (group header rows also get tooltip and onClick, to collapse a group or act on all of it),
-- stickyHeaders (once a group's header scrolls off, the top row shows it over the group's rows),
-- headerColor(item) -> color for a group header's label and the rule under it (S.colors' red, blue, green and
-- yellow are there for this), or nil for the usual heading color and no rule,
-- isSelected(item), plain (a bare list for inside a menu or popup: no well frame and no column headers),
-- onMove(from, to) (rows can be dragged to reorder; from and to are item indexes, to as it is after the move, and
-- the table leaves moving the item to the caller). The table's frame is .frame; its contents sit inside the well's
-- border.
function Table.New(parent, name, width, height, opts)
	local C = S.colors
	-- the well's border, then its own 1px
	local inset = opts.plain and 0 or 1 + S.metrics.wellInset
	local self = setmetatable({ columns = opts.columns, rowH = opts.rowH or 20, icons = opts.icons, cell = opts.cell,
		iconOf = opts.icon, tooltip = opts.tooltip, onClick = opts.onClick, onSort = opts.onSort, header = opts.header,
		headerClicks = opts.headerClicks, stickyHeaders = opts.stickyHeaders, headerColor = opts.headerColor,
		isSelected = opts.isSelected, plain = opts.plain, onMove = opts.onMove, items = {}, width = width,
		innerW = width - 2 * inset,
		offset = 0, rows = {}, headers = {} }, { __index = Table })
	local columns = {}
	for i, def in ipairs(opts.columns) do
		local col = {}
		for k, v in pairs(def) do col[k] = v end
		col.x, col.baseWidth = 0, col.width
		columns[i] = col
	end
	self.columns = columns

	self.frame = CreateFrame("Frame", name, parent)
	self.frame:SetSize(width, height)
	if not opts.plain then S.Well(self.frame) end
	self.content = CreateFrame("Frame", nil, self.frame)
	self.content:SetPoint("TOPLEFT", inset, -inset)
	self.content:SetPoint("BOTTOMRIGHT", -inset, inset)

	-- rows start below the header and its rule, so a highlighted first row doesn't cover the rule; a plain list's
	-- start at the top
	self.bodyTop = 0
	if not opts.plain then
		local header = S.Solid(self.content, "BACKGROUND", C.panel)
		header:SetPoint("TOPLEFT")
		header:SetPoint("TOPRIGHT")
		header:SetHeight(HEADER_H)
		local rule, ruleH = line(self.content, "header")
		rule:SetHeight(ruleH)
		rule:SetPoint("TOPLEFT", 0, -HEADER_H)
		rule:SetPoint("TOPRIGHT", 0, -HEADER_H)
		self.bodyTop = HEADER_H + ruleH
	end
	for _, col in ipairs(self.columns) do
		local h = CreateFrame("Button", nil, self.content)
		h.col = col
		h.label = S.Text(h, "small", C.muted)
		h.label:SetPoint("LEFT", 6, 0)
		h.label:SetJustifyH(col.justify or "LEFT")
		h.label:SetText(col.label or "")
		h.arrow = h:CreateTexture(nil, "OVERLAY")
		h.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
		h.arrow:SetSize(9, 8)
		h.arrow:SetDesaturated(true)
		h.arrow:SetVertexColor(unpack(C.heading))
		h.arrow:Hide()
		if col.sortable ~= false then
			S.Highlight(h)
			h:SetScript("OnClick", function()
				if self.sortKey == col.key then
					self.sortDesc = not self.sortDesc
				else
					self.sortKey, self.sortDesc = col.key, col.defaultDesc or false
				end
				paintHeader(self)
				if self.onSort then self.onSort(self.sortKey, self.sortDesc) end
			end)
		end
		if col.tooltip then
			h:SetScript("OnEnter", function()
				GameTooltip:SetOwner(h, "ANCHOR_TOP")
				GameTooltip:SetText(col.tooltip, nil, nil, nil, nil, true)
				GameTooltip:Show()
			end)
			h:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		self.headers[#self.headers + 1] = h
	end

	self.visible = math.floor((height - 2 * inset - self.bodyTop) / self.rowH)
	if self.onMove then
		self.reorder = Reorder.New({ rows = self.rows, lineParent = self.content, area = self.content,
			scroll = function(step) self:ScrollTo(self.offset + step) end,
			onMove = function(from, to)
				if from <= #self.items and to <= #self.items then self.onMove(from, to) end
			end })
	end
	for i = 1, self.visible do self.rows[i] = newRow(self, i) end
	layout(self)

	local bar = CreateFrame("Slider", nil, self.frame)
	bar:SetFrameLevel(self.content:GetFrameLevel() + 5)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(6)
	-- the same 2px gap below the header's rule as above the bottom border
	bar:SetPoint("TOPRIGHT", -inset - 2, -inset - self.bodyTop - 2)
	bar:SetPoint("BOTTOMRIGHT", -inset - 2, inset + 2)
	local track = S.Solid(bar, "BACKGROUND", C.scrollTrack)
	track:SetAllPoints()
	bar:SetThumbTexture(WHITE)
	local thumb = bar:GetThumbTexture()
	thumb:SetSize(6, 40)
	thumb:SetVertexColor(unpack(C.scrollThumb))
	bar:SetScript("OnEnter", function() thumb:SetVertexColor(unpack(S.colors.scrollThumbHover)) end)
	bar:SetScript("OnLeave", function() thumb:SetVertexColor(unpack(S.colors.scrollThumb)) end)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetValue(0)
	bar:SetScript("OnValueChanged", function(_, value)
		local offset = math.floor(value + 0.5)
		if offset ~= self.offset then
			self.offset = offset
			self:Redraw()
		end
	end)
	self.bar = bar

	self.frame:EnableMouseWheel(true)
	self.frame:SetScript("OnMouseWheel", function(_, delta)
		self:ScrollTo(self.offset - delta * (IsShiftKeyDown() and self.visible or WHEEL_ROWS))
	end)

	self.empty = S.Text(self.content, "normal", C.muted)
	self.empty:SetPoint("TOP", 0, -self.bodyTop - 40)
	self.empty:SetJustifyH("CENTER")
	return self
end

function Table:SetColumnLabel(key, text)
	for _, h in ipairs(self.headers) do
		if h.col.key == key then h.label:SetText(text) end
	end
end

function Table:SetColumnShown(key, shown)
	local changed = false
	for _, col in ipairs(self.columns) do
		if col.key == key and not col.hidden ~= shown then
			col.hidden = not shown
			changed = true
		end
	end
	if changed then layout(self) end
end

function Table:SetSort(key, desc)
	self.sortKey, self.sortDesc = key, desc
	paintHeader(self)
end

function Table:ScrollTo(offset)
	local max = math.max(0, #self.items - self.visible)
	offset = math.max(0, math.min(max, offset))
	self.bar:SetValue(offset)
	if offset ~= self.offset then
		self.offset = offset
		self:Redraw()
	end
end

-- Shows new items; keepScroll leaves the scroll position where it is (clamped) instead of going to the top.
function Table:SetItems(items, emptyText, keepScroll)
	self.items = items
	local max = math.max(0, #items - self.visible)
	self.bar:SetMinMaxValues(0, max)
	if max > 0 then self.bar:Show() else self.bar:Hide() end
	self.offset = keepScroll and math.min(self.offset, max) or 0
	self.bar:SetValue(self.offset)
	self.empty:SetText(#items == 0 and (emptyText or "") or "")
	self:Redraw()
end

-- The header of the group the top row is in, once that header has scrolled off: its item and label, or nil.
local function stickyHeader(self)
	local top = self.items[self.offset + 1]
	if self.stickyHeaders and self.header and top and not self.header(top) then
		for index = self.offset, 1, -1 do
			local item = self.items[index]
			local label = self.header(item)
			if label then return item, label end
		end
	end
end

function Table:Redraw()
	local stuckItem, stuckLabel = stickyHeader(self)
	for i, row in ipairs(self.rows) do
		local item = self.items[self.offset + i]
		local header = item and self.header and self.header(item)
		if i == 1 and stuckItem then item, header = stuckItem, stuckLabel end
		if i == 1 and self.stickyHeaders then
			if stuckItem then row.stickyRule:Show() else row.stickyRule:Hide() end
		end
		row.item = item
		row.moveIndex = item and not header and self.offset + i or nil
		if header then
			for _, fs in ipairs(row.cells) do fs:SetText("") end
			row.icon:Hide()
			row.headerText:SetText(header)
			row.headerText:Show()
			row.headerTex:Show()
		else
			row.headerText:Hide()
			row.headerTex:Hide()
		end
		local groupColor = header and self.headerColor and self.headerColor(item)
		row.headerText:SetTextColor(unpack(groupColor or S.colors.heading))
		if self.headerColor then
			if groupColor then
				row.headerRule:SetVertexColor(unpack(groupColor))
				row.headerRule:Show()
			else
				row.headerRule:Hide()
			end
		end
		if item and not header then
			for c, col in ipairs(self.columns) do
				local text, color = self.cell(item, col.key)
				row.cells[c]:SetText(text or "")
				row.cells[c]:SetTextColor(unpack(color or S.colors.text))
			end
			if self.icons then
				local tex = self.iconOf and self.iconOf(item)
				row.icon:SetTexture(tex)
				if tex then row.icon:Show() else row.icon:Hide() end
			end
		end
		if item then
			S.PaintRow(row, self.isSelected and self.isSelected(item) or false)
			row:Show()
		else
			row:Hide()
		end
	end
	if GameTooltip:IsOwned(self.rows[1]) then GameTooltip:Hide() end
end

function Table:Show() self.frame:Show() end
function Table:Hide() self.frame:Hide() end

-------------------------------------------------------------------------------- list

-- A scrolling list of flat rows for short mixed lists (navigation, pickers, editors), beside S.Table's data grids:
-- optional icon, text with an optional second line, right-aligned status, tooltip, click and cursor drop. Rows can
-- be headers (collapsible, colored, sticky), carry a checkbox, a remove button, or be dragged into order; the
-- selected row gets an accent bar. It scrolls by pixels and keeps a frame per row it has shown, so rows can differ
-- in height; S.Table is the one for long lists.
local List = {}
S.List = List

local LIST_STYLES = {
	content = { rowH = 22, subRowH = 36, header = "small", row = "small" },
	sidebar = { rowH = 22, subRowH = 36, header = "small", row = "normal" },
}

-- A hovered row keeps the skin's highlight lit (also while the mouse is on its remove button) and, when it can be
-- removed, shows its remove button in place of its status. A list has one hovered row: rows share edges, and the
-- next row can be entered before the last one is left.
local function listHover(row, on)
	local list = row.list
	local removable = on and row.onRemove ~= nil
	if on then
		if list.hoverRow and list.hoverRow ~= row then listHover(list.hoverRow, false) end
		list.hoverRow = row
		row:LockHighlight()
	else
		if list.hoverRow == row then list.hoverRow = nil end
		row:UnlockHighlight()
	end
	if removable then row.remove:Show() row.status:Hide() else row.remove:Hide() row.status:Show() end
end

local function listEnter(row)
	listHover(row, true)
	if row.tooltip then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		row.tooltip(GameTooltip)
		GameTooltip:Show()
	end
end

-- Moving onto the remove button leaves the row; the row stays hovered while the mouse is over either. The button
-- sits inside the row's edges, so the mouse on the edge shared with the next row is never over it.
local function listLeave(row)
	local onRemove = row.remove:IsShown() and (GetMouseFocus() == row.remove or MouseIsOver(row.remove))
	if not onRemove then listHover(row, false) end
	GameTooltip:Hide()
end

local function listDropOrClick(row, button)
	local kind, a, b = GetCursorInfo()
	if kind and row.onDrop then
		ClearCursor()
		row.onDrop(kind, a, b)
	elseif row.onClick and not (row.list.reorder and row.list.reorder:Busy()) then
		row.onClick(row, button)
	end
end

local function listDragLabel(row) return row.dragLabel end

local function listRow(self, parent)
	local style = self.style
	local row = CreateFrame("Button", nil, parent or self.content)
	row.list = self
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if self.reorder and not parent then self.reorder:Attach(row, listDragLabel) end

	S.Highlight(row)
	S.Row(row, true)

	row.toggle = S.Text(row, "normal", S.colors.muted)
	row.toggle:SetWidth(12)
	row.toggle:SetJustifyH("CENTER")
	row.check = S.Check(row, nil, function() if row.onCheck then row.onCheck(row) end end)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)

	row.status = S.FontString(row, "small")
	row.status:SetPoint("RIGHT", -S.PAD, 0)
	row.status:SetJustifyH("RIGHT")
	row.text = S.FontString(row, style.row)
	row.text:SetJustifyH("LEFT")
	row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	row.sub = S.Text(row, "small", S.colors.muted)
	row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
	row.sub:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	-- a colored header's rule
	row.rule = S.Solid(row, "ARTWORK", S.colors.heading)
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT", S.PAD, 0)
	row.rule:SetPoint("BOTTOMRIGHT", -S.PAD, 0)
	row.rule:Hide()

	-- shown on hover for rows added with onRemove, over the status
	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(S.CONTROL_H, style.rowH - 6)
	row.remove:SetPoint("RIGHT", -S.PAD + 6, 0)
	row.remove.label = S.Text(row.remove, "normal", S.colors.muted)
	row.remove.label:SetPoint("CENTER")
	row.remove.label:SetText("X")
	row.remove:Hide()
	row.remove:SetScript("OnClick", function() if row.onRemove then row.onRemove(row) end end)
	row.remove:SetScript("OnEnter", function(b)
		b.label:SetTextColor(unpack(S.colors.bad))
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetText(row.removeTip or "Remove", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", function(b)
		b.label:SetTextColor(unpack(S.colors.muted))
		GameTooltip:Hide()
		if GetMouseFocus() ~= row then listHover(row, false) end
	end)

	row:SetScript("OnClick", listDropOrClick)
	row:SetScript("OnReceiveDrag", function(r) listDropOrClick(r, "LeftButton") end)
	row:SetScript("OnEnter", listEnter)
	row:SetScript("OnLeave", listLeave)
	return row
end

-- A flat bar that only shows when there's something to scroll, for any UIPanelScrollFrameTemplate scroll frame;
-- onToggle(shown), if given, runs with each update. Returns the update function.
function List.AutoHideBar(scroll, scrollName, onToggle)
	local bar = S.ScrollBar(scroll, scrollName)
	local function update()
		local shown = (scroll:GetVerticalScrollRange() or 0) > 0
		if shown then bar:Show() else bar:Hide() end
		if onToggle then onToggle(shown) end
	end
	scroll:HookScript("OnScrollRangeChanged", update)
	update()
	return update
end

-- style: "content" (default) or "sidebar" (larger row text). `width` leaves room on the right for the scroll bar;
-- `gutter` is that room, which the rows take over while there's nothing to scroll and the bar is hidden.
function List.New(parent, name, width, height, style, gutter)
	local self = setmetatable({ rows = {}, headers = {}, headerCount = 0, count = 0, height = 0,
		style = LIST_STYLES[style or "content"], width = width, name = name }, { __index = List })
	self.scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	self.scroll:SetSize(width, height)
	self.content = CreateFrame("Frame", nil, self.scroll)
	self.content:SetSize(width, height)
	self.scroll:SetScrollChild(self.content)
	self.updateBar = List.AutoHideBar(self.scroll, name, function(shown)
		local w = shown and width or width + (gutter or 0)
		self.scroll:SetWidth(w)
		self.content:SetWidth(w)
	end)
	return self
end

-- The overlay row's copy of the header the list has scrolled past: shown while any of that header is above the
-- top, hidden at the top or above the first header.
local function updateSticky(self)
	local stuck = self.stuck
	local offset = self.scroll:GetVerticalScroll() or 0
	local source
	for i = 1, self.headerCount do
		local row = self.headers[i]
		if row.y < offset then source = row end
	end
	stuck.source = source
	if source then
		S.SetFont(stuck.text, self.style.header)
		stuck.text:SetText(source.text:GetText() or "")
		stuck.text:SetTextColor(source.text:GetTextColor())
		stuck.status:SetText(source.status:GetText() or "")
		if source.rule:IsShown() then
			stuck.rule:SetVertexColor(source.rule:GetVertexColor())
			stuck.rule:Show()
		else
			stuck.rule:Hide()
		end
		stuck:Show()
	else
		stuck:Hide()
	end
end

-- Keeps the header of the section scrolled into on an overlay at the top, with a rule under it, until the next
-- header reaches the top (S.Table's stickyHeaders). Clicks and the tooltip go to the header itself.
function List:SetSticky()
	local stuck = listRow(self, self.scroll)
	stuck:SetFrameLevel(self.content:GetFrameLevel() + 3)
	stuck:SetPoint("TOPLEFT", self.scroll, "TOPLEFT")
	stuck:SetPoint("TOPRIGHT", self.scroll, "TOPRIGHT")
	stuck:SetHeight(self.style.rowH)
	stuck.bg = S.Solid(stuck, "BACKGROUND", S.colors.panel)
	stuck.bg:SetDrawLayer("BACKGROUND", -1)
	stuck.bg:SetAllPoints()
	local divider, thickness = S.Divider(stuck, "header")
	divider:SetHeight(thickness)
	divider:SetPoint("BOTTOMLEFT")
	divider:SetPoint("BOTTOMRIGHT")
	stuck.text:ClearAllPoints()
	stuck.text:SetPoint("LEFT", S.PAD, 0)
	stuck.text:SetPoint("RIGHT", stuck.status, "LEFT", -6, 0)
	stuck.toggle:Hide()
	stuck.check:Hide()
	stuck.icon:Hide()
	stuck.sub:Hide()
	stuck:SetScript("OnClick", function(r, button)
		if r.source and r.source.onClick then r.source.onClick(r.source, button) end
	end)
	stuck.tooltip = function(tt) if stuck.source and stuck.source.tooltip then stuck.source.tooltip(tt) end end
	stuck:Hide()
	self.stuck = stuck
	self.scroll:HookScript("OnVerticalScroll", function() updateSticky(self) end)
end

-- Rows added with a move index can be dragged into a new order; onMove(from, to) gets the drop.
function List:SetReorder(onMove)
	local scroll = self.scroll
	self.reorder = Reorder.New({ rows = self.rows, lineParent = self.content, area = scroll, onMove = onMove,
		scroll = function(step)
			local y = scroll:GetVerticalScroll() + step * self.style.rowH
			scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, y)))
		end })
	for _, row in ipairs(self.rows) do self.reorder:Attach(row, listDragLabel) end
end

-- Starts a redraw: Add each entry, then End.
function List:Begin()
	self.count = 0
	self.height = 0
	self.headerCount = 0
end

-- entry: text, sub, status, icon, header, color (a header's text and rule color, such as S.colors.red), collapsed
-- (true/false shows +/-), indent, selected, check (true/false shows a checkbox), checkEnabled, checkTooltip,
-- onCheck(row), tooltip(tt), onClick(row, button), onDrop(kind, ...) with GetCursorInfo's values for whatever is
-- dropped on it, move (the index it drags from, with SetReorder), dragLabel (the text by the cursor while it's
-- dragged), and onRemove(row) with removeTip (an X shown over the status while the row is hovered)
function List:Add(entry)
	local style = self.style
	self.count = self.count + 1
	local row = self.rows[self.count]
	if not row then
		row = listRow(self)
		self.rows[self.count] = row
	end
	local h = entry.sub and style.subRowH or style.rowH
	if entry.header and self.count > 1 then self.height = self.height + 6 end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.height)
	row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.height)
	row:SetHeight(h)
	row.y = self.height
	self.height = self.height + h
	if entry.header then
		self.headerCount = self.headerCount + 1
		self.headers[self.headerCount] = row
	end

	local x = S.PAD + (entry.indent or 0)
	if entry.collapsed ~= nil then
		row.toggle:SetText(entry.collapsed and "+" or "-")
		row.toggle:ClearAllPoints()
		row.toggle:SetPoint("LEFT", x - 2, 0)
		row.toggle:Show()
		x = x + 16
	else
		row.toggle:Hide()
	end
	if entry.check ~= nil then
		row.check:ClearAllPoints()
		row.check:SetPoint("LEFT", x, 0)
		row.check:SetChecked(entry.check)
		row.check:SetEnabled(entry.checkEnabled ~= false)
		row.check.tooltipText = entry.checkTooltip
		row.check:Show()
		x = x + S.CHECK_H + 6
	else
		row.check:Hide()
	end
	row.icon:ClearAllPoints()
	row.text:ClearAllPoints()
	row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	if entry.icon then
		row.icon:SetTexture(entry.icon)
		row.icon:SetPoint("LEFT", x, 0)
		row.icon:Show()
		x = x + 20
	else
		row.icon:Hide()
	end
	if entry.sub then
		-- two lines (about 24px of text) centered in the taller row
		row.text:SetPoint("TOPLEFT", x, -(style.subRowH - 24) / 2)
		row.sub:SetText(entry.sub)
		row.sub:Show()
	else
		row.text:SetPoint("LEFT", x, 0)
		row.sub:Hide()
	end

	S.SetFont(row.text, entry.header and style.header or style.row)
	row.text:SetText(entry.text or "")
	-- rows are reused, so both kinds set their color; a header left to its font would keep an entry's white
	row.text:SetTextColor(unpack(entry.header and (entry.color or S.colors.heading) or S.colors.text))
	if entry.header and entry.color then
		row.rule:SetVertexColor(unpack(entry.color))
		row.rule:Show()
	else
		row.rule:Hide()
	end
	row.status:SetText(entry.status or "")
	S.PaintRow(row, entry.selected and true or false)

	row.tooltip, row.onClick, row.onDrop, row.onCheck = entry.tooltip, entry.onClick, entry.onDrop, entry.onCheck
	row.onRemove, row.removeTip = entry.onRemove, entry.removeTip
	-- rows are reused, so a redraw under the mouse keeps the hover the new entry should have
	listHover(row, row:IsShown() and MouseIsOver(row) or false)
	row.moveIndex, row.dragLabel = entry.move, entry.dragLabel
	row:Show()
	return row
end

-- Ends a redraw: rows past the last entry hide and the scroll range follows the new height.
function List:End()
	for i = self.count + 1, #self.rows do self.rows[i]:Hide() end
	self.content:SetHeight(math.max(1, self.height))
	self.scroll:UpdateScrollChildRect()
	self.updateBar()
	if self.stuck then updateSticky(self) end
end

function List:Show() self.scroll:Show() end
function List:Hide() self.scroll:Hide() end

-------------------------------------------------------------------------------- picker

-- A searchable, scrolling list that opens under a button, for choices too many for a dropdown: a search box over a
-- plain S.Table in a menu frame. It closes like a dropdown menu. In multi mode clicking toggles entries and it
-- stays open.
local Picker = {}
S.Picker = Picker
local PICKER_W, PICKER_H = 300, 360
local picker, pickerSpec

local function pickerRefresh()
	local q = picker.search:GetText() or ""
	local items
	if pickerSpec.search then
		items = pickerSpec.search(q)
	else
		items = {}
		local lower = q:lower()
		for _, item in ipairs(pickerSpec.items or {}) do
			if lower == "" or item.text:lower():find(lower, 1, true) then items[#items + 1] = item end
		end
	end
	picker.list:SetItems(items, pickerSpec.emptyText or "Nothing Matches", picker.keepScroll)
	picker.keepScroll = nil
end

-- The list and search keep their size in every skin; the menu grows around them by its border.
local function pickerCreate()
	local C = S.colors
	local inset, innerW, innerH = S.metrics.menuInset + 4, PICKER_W - 2 * S.PAD, PICKER_H - 2 * S.PAD
	picker = CreateFrame("Frame", ADDON .. "Picker", UIParent)
	picker:SetSize(innerW + 2 * inset, innerH + 2 * inset)
	picker:SetFrameStrata("FULLSCREEN_DIALOG")
	picker:SetToplevel(true)
	picker:EnableMouse(true)
	S.Frame(picker, "menu")
	tinsert(UISpecialFrames, ADDON .. "Picker")

	picker.search = S.Input(picker, ADDON .. "PickerSearch", innerW, "Search", 60)
	picker.search:SetPoint("TOPLEFT", inset, -inset)
	picker.search:HookScript("OnTextChanged", function(_, user)
		if user then pickerRefresh() end
	end)

	picker.list = Table.New(picker, nil, innerW, innerH - S.GAP - S.CONTROL_H, {
		plain = true,
		columns = { { key = "text", label = "", width = innerW, sortable = false } },
		cell = function(item)
			local on = pickerSpec.isSelected and pickerSpec.isSelected(item.value)
			if pickerSpec.multi then return (on and "|cffffc400+|r  " or "    ") .. item.text, on and C.heading or C.text end
			return item.text, on and C.heading or C.text
		end,
		icon = function(item) return item.icon end,
		tooltip = function(tt, item)
			if item.link then
				tt:SetHyperlink(item.link)
			elseif item.tooltip then
				tt:SetText(item.text, 1, 1, 1)
				tt:AddLine(item.tooltip, nil, nil, nil, true)
			end
		end,
		onClick = function(item)
			if not pickerSpec.multi then picker:Hide() end
			if pickerSpec.onPick then pickerSpec.onPick(item.value) end
			if pickerSpec.multi then
				picker.keepScroll = true
				pickerRefresh()
			end
		end,
	})
	picker.list.frame:SetPoint("TOPLEFT", picker.search, "BOTTOMLEFT", 0, -S.GAP)
	picker:SetScript("OnHide", function() picker.search:ClearFocus() end)
	S.TrackPopup(picker)
end

-- Opens under anchor, at its scale; opening it from the same button again closes it. spec: items = { { value,
-- text, tooltip, icon, link } } or search(text) -> items, placeholder, multi, isSelected(value), onPick(value),
-- emptyText.
function Picker.Open(anchor, spec)
	if not picker then pickerCreate() end
	local open = picker:IsShown() and picker.owner == anchor
	S.CloseMenus()
	if not open then
		pickerSpec = spec
		picker.owner = anchor
		picker:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
		picker:ClearAllPoints()
		picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		picker.search:SetText("")
		picker.search.placeholder:SetText(spec.placeholder or "Search")
		picker.search:UpdatePlaceholder()
		pickerRefresh()
		picker:Show()
	end
end

function Picker.Close()
	if picker then picker:Hide() end
end

-- A dropdown-looking button that opens the picker: getSpec() returns the spec each time it opens, so the choices
-- and the selection are current. b:SetText(text) shows the current choice.
function S.PickerButton(parent, width, getSpec)
	local b = S.AddArrow(S.Button(parent, "", "secondary", width))
	function b:SetText(text) self.label:SetText(text) end
	b:SetScript("OnClick", function(self) Picker.Open(self, getSpec()) end)
	b:HookScript("OnHide", function(self)
		if picker and picker.owner == self then picker:Hide() end
	end)
	return b
end

-- Skins: how the controls above are drawn. A skin can carry a scheme of its own (roles, as S.SetTheme takes them),
-- set colors apart from the scheme (colors(c, M3), run after the scheme fills S.colors), and change S.metrics.
-- label names it in a picker, credit says who made it. The drawing functions: button(b) and
-- paintButton(b, enabled) (b.kind, b.hovered, b.down), frame(f, role), well(f), line(parent, kind) -> texture,
-- thickness (kind "rule", "header" or "heading"), optionally split(holder) -> width for S.VerticalDivider,
-- sidebar(side), highlight(f), optionally tab(b) and paintTab(b, on) (falling back to Material's), navEntry(b) and
-- paintNav(b, on), input(e, tall) and paintInput(e) (e.focused, e.hovered; a tall one draws on e.box), and
-- optionally check(b) and
-- paintCheck(b) (b.on, b.usable, b.hovered); a skin without them gets Material's checkbox. Likewise optionally
-- slider(s) and paintSlider(s) (s.usable, s.hovered; the handle is s:GetThumbTexture()), else Material's slider,
-- and row(r, bar) and paintRow(r, on) for list and table rows (hover and selected; bar: the list would like an
-- accent bar on the selected row), else Material's.
function S.RegisterSkin(key, def)
	skins[key] = def
end

-- Switches to a skin and its scheme; `roles` is the scheme for a skin without one of its own (default: the kit's).
-- Like S.SetTheme, call it before building any frames.
function S.UseSkin(key, roles)
	local def = skins[key] or error("MaterialCraftUI: unknown skin " .. tostring(key), 2)
	skin = def
	for k, v in pairs(METRICS) do S.metrics[k] = v end
	for k, v in pairs(def.metrics or {}) do S.metrics[k] = v end
	S.SetTheme(def.roles or roles)
end

function S.Skin()
	for key, def in pairs(skins) do
		if def == skin then return key end
	end
end

-- Every registered skin as { key, label, credit }, Material first and the rest by label.
function S.Skins()
	local list = {}
	for key, def in pairs(skins) do list[#list + 1] = { key = key, label = def.label or key, credit = def.credit } end
	table.sort(list, function(a, b)
		if (a.key == "material") ~= (b.key == "material") then return a.key == "material" end
		return a.label < b.label
	end)
	return list
end

local PREVIEW_W, PREVIEW_ROW_H = 200, 22
local previews = {}

-- The card's contents, top to bottom inside the skin's popup padding: name, credit, two buttons, a checkbox, and a
-- well with a selected row and a hovered one. Nothing in it takes the mouse.
local function buildPreview(def)
	local C, m = S.colors, S.metrics
	local inset = m.inset
	local card = CreateFrame("Frame", nil, UIParent)
	card:SetFrameStrata("FULLSCREEN_DIALOG")
	card:SetWidth(PREVIEW_W + 2 * inset)
	S.Frame(card, "popup")
	local y = inset
	local function place(region, h, gap)
		region:SetPoint("TOPLEFT", inset, -y)
		y = y + h + (gap or S.GAP)
		return region
	end

	local title = place(S.Text(card, "normal", C.heading), 16, 4)
	title:SetHeight(16)
	title:SetText(def.label or "")
	if def.credit then
		local credit = place(S.Text(card, "small", C.muted), 26)
		credit:SetWidth(PREVIEW_W)
		credit:SetHeight(26)
		credit:SetJustifyH("LEFT")
		credit:SetJustifyV("TOP")
		credit:SetText(def.credit)
	end

	local second = math.floor((PREVIEW_W - S.GAP) / 2)
	local primary = place(S.Button(card, "Apply", "primary", PREVIEW_W - S.GAP - second), S.CONTROL_H)
	local secondary = S.Button(card, "Cancel", "secondary", second)
	secondary:SetPoint("LEFT", primary, "RIGHT", S.GAP, 0)

	local check = place(S.Check(card), S.CHECK_H)
	check:SetChecked(true)
	local checkLabel = S.Text(card, "small")
	checkLabel:SetPoint("LEFT", check, "RIGHT", 6, 0)
	checkLabel:SetText("An Option")

	local pad = m.wellInset + 2
	local well = place(S.Well(CreateFrame("Frame", nil, card)), 2 * PREVIEW_ROW_H + 2 * pad, 0)
	well:SetSize(PREVIEW_W, 2 * PREVIEW_ROW_H + 2 * pad)
	card.rows = {}
	for i, text in ipairs({ "Selected Row", "Hovered Row" }) do
		local row = CreateFrame("Button", nil, well)
		card.rows[i] = row
		row:SetSize(PREVIEW_W - 2 * pad, PREVIEW_ROW_H)
		row:SetPoint("TOPLEFT", pad, -pad - (i - 1) * PREVIEW_ROW_H)
		S.Row(row, true)
		local label = S.Text(row, "small")
		label:SetPoint("LEFT", S.PAD, 0)
		label:SetText(text)
		if i == 1 then S.PaintRow(row, true) else row:LockHighlight() end
		row:EnableMouse(false)
	end

	for _, control in ipairs({ primary, secondary, check }) do control:EnableMouse(false) end
	card:SetHeight(y + inset)
	card:Hide()
	return card
end

-- A small card drawn in a skin, to show what a theme looks like before reloading into it. A skin's art is made with
-- each frame, so the card is built once per skin by switching to it for a moment and back; its controls take no
-- mouse, so the skin in use never repaints them. roles: the scheme for a skin without its own, as for S.UseSkin.
function S.SkinPreview(key, roles)
	local card = previews[key]
	if not card and skins[key] then
		local current = S.Skin()
		S.UseSkin(key, roles)
		local ok, built = pcall(buildPreview, skins[key])
		S.UseSkin(current, roles)
		if not ok then error(built, 0) end
		card = built
		previews[key] = card
	end
	return card
end

-- The flat Material look: 1px borders, state layers and tinted fills.
S.RegisterSkin("material", {
	label = "Material",
	button = function(b)
		b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	end,
	paintButton = function(b, enabled)
		local kind = enabled and BUTTONS[b.kind] or DISABLED
		b:SetBackdropColor(unpack(b.hovered and enabled and kind.hover or kind.bg))
		b:SetBackdropBorderColor(unpack(kind.border))
		b.label:SetTextColor(unpack(kind.text))
	end,
	frame = function(f, role)
		S.Panel(f, role == "window" and S.colors.window or S.colors.panel, S.colors.border)
	end,
	well = function(f)
		S.Panel(f, S.colors.well, S.colors.border)
	end,
	-- every divider is a 1px line in the border color
	line = function(parent)
		return S.Solid(parent, "BORDER", S.colors.border), 1
	end,
	sidebar = function(side)
		local fill = S.Solid(side, "BACKGROUND", S.colors.sidebar)
		fill:SetPoint("TOPLEFT", 1, 0)
		fill:SetPoint("BOTTOMRIGHT", 0, 1)
		local edge = S.Solid(side, "BORDER", S.colors.border)
		edge:SetWidth(1)
		edge:SetPoint("TOPRIGHT")
		edge:SetPoint("BOTTOMRIGHT")
	end,
	highlight = function(f)
		S.Solid(f, "HIGHLIGHT", S.colors.hover):SetAllPoints()
	end,
	-- the hover tint, and an accent underline under the selected tab
	tab = function(b)
		S.Highlight(b)
		b.underline = S.Solid(b, "OVERLAY", S.colors.accent)
		b.underline:SetHeight(2)
		b.underline:SetPoint("BOTTOMLEFT", 6, 0)
		b.underline:SetPoint("BOTTOMRIGHT", -6, 0)
	end,
	paintTab = function(b, on)
		if on then b.underline:Show() else b.underline:Hide() end
	end,
	-- a tint and an accent bar on the selected entry, whose label sits in from its section heading
	navEntry = function(b)
		S.Highlight(b)
		b.selectedTex = S.Solid(b, "BACKGROUND", S.colors.selected)
		b.selectedTex:SetAllPoints()
		b.bar = S.Solid(b, "BORDER", S.colors.accent)
		b.bar:SetWidth(3)
		b.bar:SetPoint("TOPLEFT")
		b.bar:SetPoint("BOTTOMLEFT")
		b.label:SetPoint("LEFT", S.PAD + 8, 0)
	end,
	paintNav = function(b, on)
		if on then b.bar:Show() b.selectedTex:Show() else b.bar:Hide() b.selectedTex:Hide() end
	end,
	-- a list or table row: the hover tint, and selected, a tint with an accent bar where the list asks for one
	row = function(r, bar)
		S.Highlight(r)
		r.selectedTex = S.Solid(r, "BACKGROUND", S.colors.rowSelected)
		r.selectedTex:SetAllPoints()
		r.bar = false
		if bar then
			r.bar = S.Solid(r, "BORDER", S.colors.accent)
			r.bar:SetWidth(3)
			r.bar:SetPoint("TOPLEFT")
			r.bar:SetPoint("BOTTOMLEFT")
		end
	end,
	paintRow = function(r, on)
		if on then r.selectedTex:Show() else r.selectedTex:Hide() end
		if r.bar then
			if on then r.bar:Show() else r.bar:Hide() end
		end
	end,
	input = function(e)
		S.Panel(e.box or e, S.colors.well, S.colors.border)
	end,
	-- a square well with an accent fill while checked, outlined in the accent on hover
	check = function(b)
		S.Panel(b, S.colors.well, S.colors.outline)
		b.fill = S.Solid(b, "ARTWORK", S.colors.accent)
		-- the gap round the fill grows with the box, 3 at 14
		local gap = math.floor((b:GetWidth() or 14) * 0.22 + 0.5)
		b.fill:SetPoint("TOPLEFT", gap, -gap)
		b.fill:SetPoint("BOTTOMRIGHT", -gap, gap)
		b.fill:Hide()
	end,
	paintCheck = function(b)
		if b.on then b.fill:Show() else b.fill:Hide() end
		b.fill:SetAlpha(b.usable and 1 or 0.4)
		b:SetBackdropBorderColor(unpack(b.hovered and b.usable and S.colors.accent or S.colors.outline))
	end,
	-- a thin track, the accent up to an accent bar handle, which brightens on hover
	slider = function(s)
		local thumb = s:CreateTexture(nil, "OVERLAY")
		thumb:SetTexture(WHITE)
		thumb:SetSize(6, 16)
		s:SetThumbTexture(thumb)
		s.track = S.Solid(s, "BACKGROUND", S.colors.border)
		s.track:SetHeight(4)
		s.track:SetPoint("LEFT")
		s.track:SetPoint("RIGHT")
		s.fill = S.Solid(s, "ARTWORK", S.colors.accent)
		s.fill:SetHeight(4)
		s.fill:SetPoint("LEFT")
		s.fill:SetPoint("RIGHT", thumb, "CENTER")
	end,
	paintSlider = function(s)
		local thumb = s:GetThumbTexture()
		local c = not s.usable and S.colors.disabled or s.hovered and S.colors.accentHover or S.colors.accent
		thumb:SetVertexColor(unpack(c))
		s.fill:SetVertexColor(unpack(s.usable and S.colors.accent or S.colors.disabled))
		s.valueText:SetTextColor(unpack(s.usable and S.colors.text or S.colors.disabled))
	end,
	-- a flat track with the accent filling it from the left, the good color once complete
	progressBar = function(p)
		p.track = S.Solid(p, "BACKGROUND", S.colors.border)
		p.track:SetAllPoints()
		p.fill = S.Solid(p, "ARTWORK", S.colors.accent)
		p.fill:SetPoint("TOPLEFT")
		p.fill:SetPoint("BOTTOMLEFT")
	end,
	paintProgress = function(p)
		p.fill:SetVertexColor(unpack(p.complete and S.colors.good or S.colors.accent))
	end,
	-- the soft border at rest, the stronger outline on hover, the accent while focused
	paintInput = function(e)
		(e.box or e):SetBackdropBorderColor(unpack(e.focused and S.colors.accent or e.hovered and S.colors.outline or S.colors.border))
	end,
})
skin = skins.material

-------------------------------------------------------------------------------- text area

-- A scrolling multi-line edit box in a well, for notes and export strings: clicking anywhere in the well types in
-- it, and its scroll bar shows only when the text runs past the bottom. Returns the well, with .edit and .scroll,
-- :SetValue(text) (left alone while being typed in) and :SetReadOnly(on). opts: font ("small"), pad (the space
-- inside the well's frame, default 8), onInput(text) (as the player types), onTextChanged(edit, userInput) (on
-- every change, typed or set), onEscape(edit) (default: stop typing), selectOnFocus (select all on click, for a
-- string to copy).
function S.TextArea(parent, name, width, height, opts)
	opts = opts or {}
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(width, height)
	S.Well(box)
	local pad = (opts.pad or 8) + S.metrics.wellInset
	local scroll = CreateFrame("ScrollFrame", name, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", pad, -pad)
	scroll:SetPoint("BOTTOMRIGHT", -pad - 10, pad)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	S.SetFont(edit, opts.font or "small")
	edit:SetWidth(width - 2 * pad - 10)
	edit:SetScript("OnEscapePressed", function(self)
		if opts.onEscape then opts.onEscape(self) else self:ClearFocus() end
	end)
	edit:SetScript("OnEditFocusGained", function(self)
		self.focused = true
		if opts.selectOnFocus then self:HighlightText() end
	end)
	edit:SetScript("OnEditFocusLost", function(self) self.focused = false end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if opts.onTextChanged then opts.onTextChanged(self, userInput) end
		if userInput and opts.onInput then opts.onInput(self:GetText()) end
	end)
	scroll:SetScrollChild(edit)
	S.TrackInput(edit, box)
	List.AutoHideBar(scroll, name)
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() edit:SetFocus() end)
	box.edit, box.scroll = edit, scroll
	function box:SetValue(text)
		if not edit.focused then edit:SetText(text or "") end
	end
	function box:SetReadOnly(on)
		edit:EnableMouse(not on)
		box:EnableMouse(not on)
		if on then edit:ClearFocus() end
	end
	return box
end

-------------------------------------------------------------------------------- minimap button

-- Which quadrants of each minimap shape are round, in the order GetMinimapShape addons use.
local MINIMAP_SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- The game's round minimap button with an icon: drag moves it around the minimap's edge (any shape), Shift-drag
-- frees it to sit anywhere on screen, even with the minimap hidden. Where it is and whether it's hidden are kept in
-- opts.db, a saved table (angle, free = { x, y }, hide). opts: name (the frame's name), icon, angle (where it starts,
-- in degrees), onClick(button, mouse), tooltip(tt) (the lines above the drag hint), hint (a last tooltip line, such
-- as the command that hides it), onDragStart(), onReparent(button) (after it moves between the minimap and
-- UIParent). Returns the button, with :Place(), :Refresh() (shown unless db.hide) and :ResetPosition(). Dragging
-- runs on a child frame, so the button's OnUpdate stays free for the addon.
function S.MinimapButton(opts)
	local db = opts.db
	local button = CreateFrame("Button", opts.name, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(opts.icon)
	button.icon:SetSize(17, 17)
	button.icon:SetPoint("TOPLEFT", 7, -6)
	button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	function button:Place()
		local free = db.free
		local parent = free and UIParent or Minimap
		if self:GetParent() ~= parent then
			self:SetParent(parent)
			self:SetFrameStrata("MEDIUM")
			self:SetFrameLevel(8)
			if opts.onReparent then opts.onReparent(self) end
		end
		self:ClearAllPoints()
		if free then
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", free.x, free.y)
		else
			local angle = math.rad(db.angle or opts.angle or 225)
			local x, y = math.cos(angle), math.sin(angle)
			local quadrant = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
			local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
			local radius = Minimap:GetWidth() / 2 + 5
			if (MINIMAP_SHAPES[shape] or MINIMAP_SHAPES.ROUND)[quadrant] then
				x, y = x * radius, y * radius
			else
				local diagonal = math.sqrt(2 * radius * radius) - 10
				x = math.max(-radius, math.min(x * diagonal, radius))
				y = math.max(-radius, math.min(y * diagonal, radius))
			end
			self:SetPoint("CENTER", Minimap, "CENTER", x, y)
		end
	end

	function button:Refresh()
		if db.hide then self:Hide() else self:Show() end
	end

	function button:ResetPosition()
		db.free, db.angle = nil, nil
		self:Place()
	end

	-- follows the cursor until the button is let go, which ends it even when a reparent mid-drag costs OnDragStop
	local dragger = CreateFrame("Frame", nil, button)
	dragger:Hide()
	dragger:SetScript("OnUpdate", function(self)
		if IsMouseButtonDown("LeftButton") then
			local px, py = GetCursorPosition()
			if db.free then
				local scale = UIParent:GetEffectiveScale()
				db.free.x, db.free.y = px / scale, py / scale
			else
				local mx, my = Minimap:GetCenter()
				local scale = Minimap:GetEffectiveScale()
				db.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
			end
			button:Place()
		else
			self:Hide()
		end
	end)
	button.dragger = dragger

	button:SetScript("OnClick", function(self, mouse) if opts.onClick then opts.onClick(self, mouse) end end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if opts.tooltip then opts.tooltip(GameTooltip) end
		GameTooltip:AddLine("Drag to move it around the minimap, Shift-drag to place it anywhere.", 0.6, 0.6, 0.66)
		if opts.hint then GameTooltip:AddLine(opts.hint, 0.6, 0.6, 0.66) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function()
		GameTooltip:Hide()
		if opts.onDragStart then opts.onDragStart() end
		db.free = IsShiftKeyDown() and (db.free or {}) or nil
		dragger:Show()
	end)
	button:SetScript("OnDragStop", function() dragger:Hide() end)
	button:Place()
	button:Refresh()
	return button
end

-------------------------------------------------------------------------------- settings

-- The player's look for the addon, kept in its saved table: skin (a change applies after a reload, which it offers),
-- windowScale (the size of its windows) and pixelScale (whether they snap to whole pixels). Settings.Use runs once
-- the saved table exists and before any frame is built; frames made through Settings.PixelScale follow both.
local Settings = { SCALES = { 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2 } }
S.Settings = Settings
local MIN_SCALE, MAX_SCALE = 0.5, 3
local RELOAD_POPUP = ADDON:upper() .. "_THEME_RELOAD"
local settingsDb, settingsOpts = {}, {}
-- frame -> the function that puts it back after its scale changes, or false to snap it by its top left
local scaledFrames = {}
local settingsBar

local function skinLabel(key)
	for _, s in ipairs(S.Skins()) do
		if s.key == key then return s.label end
	end
end

local function paintSettingsBar()
	if settingsBar then
		settingsBar.size:SetText(Settings.ScaleLabel(settingsDb.windowScale))
		settingsBar.snap:SetChecked(settingsDb.pixelScale)
	end
end

-- After the scale changes: frames with a place of their own are put back (the rest snap, when asked), then the
-- addon's onRescaled runs and the title bar controls show the saved values.
local function rescaled(snap)
	for frame, place in pairs(scaledFrames) do
		if place then place() elseif snap then Settings.SnapPosition(frame) end
	end
	if settingsOpts.onRescaled then settingsOpts.onRescaled() end
	paintSettingsBar()
end

-- opts: theme (S.SetTheme roles for the skins without a scheme of their own), name (the addon's name in the
-- reload prompt), onRescaled() (after the size or pixel snapping changes, to place the addon's windows again).
-- Missing or unknown values in db get their defaults.
function Settings.Use(db, opts)
	settingsDb, settingsOpts = db, opts or {}
	if not skinLabel(db.skin) then db.skin = "material" end
	if db.pixelScale == nil then db.pixelScale = true end
	if db.windowScale == nil then db.windowScale = 1 end
	S.UseSkin(db.skin, settingsOpts.theme)
	S.SetWindowScale(db.windowScale)
	StaticPopupDialogs[RELOAD_POPUP] = {
		text = (settingsOpts.name or ADDON) .. " switches to the %s theme after a reload. Reload now?",
		button1 = "Reload", button2 = "Later",
		OnAccept = function() ReloadUI() end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
end

-- Pixel-scales a frame as the player has it (S.PixelScale). A frame that keeps an anchor of its own, such as a
-- tracker pinned by a corner, passes place(), which puts it back after its scale changes; the others snap by their
-- top left.
function Settings.PixelScale(frame, place)
	scaledFrames[frame] = place or false
	S.PixelScale(frame, settingsDb.pixelScale)
	return frame
end

-- Snaps a window's position to whole pixels, when pixel snapping is on.
function Settings.SnapPosition(frame)
	if settingsDb.pixelScale then S.SnapPosition(frame) end
end

function Settings.SetPixelScale(on)
	settingsDb.pixelScale = on
	for frame in pairs(scaledFrames) do S.PixelScale(frame, on) end
	rescaled(true)
end

function Settings.ScaleLabel(scale)
	return ("%d%%"):format(math.floor(scale * 100 + 0.5))
end

-- Sets the size of the addon's windows; false when it's not a number from 0.5 to 3.
function Settings.SetWindowScale(scale)
	local ok = type(scale) == "number" and scale >= MIN_SCALE and scale <= MAX_SCALE
	if ok then
		settingsDb.windowScale = scale
		S.SetWindowScale(scale)
		rescaled(false)
	end
	return ok
end

-- Every skin as a dropdown option, each with a preview card in the addon's scheme beside the menu on hover.
function Settings.SkinOptions()
	local options = {}
	for _, s in ipairs(S.Skins()) do
		local key = s.key
		options[#options + 1] = { value = key, text = s.label, tooltip = s.credit,
			preview = function() return S.SkinPreview(key, settingsOpts.theme) end }
	end
	return options
end

-- Saves a skin for the next load and offers to reload; false for a skin that doesn't exist.
function Settings.SetSkin(key)
	local label = skinLabel(key)
	if label and key ~= settingsDb.skin then
		settingsDb.skin = key
		StaticPopup_Show(RELOAD_POPUP, label)
	end
	return label ~= nil
end

local settingsWatch = CreateFrame("Frame")
settingsWatch:RegisterEvent("UI_SCALE_CHANGED")
settingsWatch:RegisterEvent("DISPLAY_SIZE_CHANGED")
settingsWatch:SetScript("OnEvent", function() rescaled(false) end)
hooksecurefunc(UIParent, "SetScale", function() rescaled(false) end)

local function barLabel(bar, anchor, text, gap)
	local label = S.Text(bar, "small", S.colors.muted)
	label:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
	label:SetText(text)
	return label
end

-- A window's title bar settings, left to right from anchor: a Theme dropdown (each skin, who made it on hover), a
-- Size dropdown and a Snap to Pixels box. They show the saved values and set them. Returns { theme, size, snap }
-- and the last control, to place more after it.
function Settings.TitleBar(bar, anchor)
	local controls = {}
	local options = Settings.SkinOptions()
	local inUse = skinLabel(S.Skin())
	local themeLabel = barLabel(bar, anchor, "Theme", 2 * S.GAP)
	controls.theme = S.Dropdown(bar, 96, function(key)
		Settings.SetSkin(key)
		controls.theme:SetText(skinLabel(key) or key)
	end)
	controls.theme:SetOptions(options)
	controls.theme:SetText(inUse or "")
	controls.theme:SetPoint("LEFT", themeLabel, "RIGHT", S.GAP, 0)

	local sizeLabel = barLabel(bar, controls.theme, "Size", 2 * S.GAP)
	local sizes = {}
	for _, scale in ipairs(Settings.SCALES) do sizes[#sizes + 1] = { value = scale, text = Settings.ScaleLabel(scale) } end
	controls.size = S.Dropdown(bar, 64, function(scale) Settings.SetWindowScale(scale) end)
	controls.size:SetOptions(sizes)
	controls.size:SetPoint("LEFT", sizeLabel, "RIGHT", S.GAP, 0)

	controls.snap = S.Check(bar, nil, function() Settings.SetPixelScale(not settingsDb.pixelScale) end)
	controls.snap:SetPoint("LEFT", controls.size, "RIGHT", 2 * S.GAP, 0)
	local snapLabel = barLabel(bar, controls.snap, "Snap to Pixels", 6)
	controls.snap:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Snap to Pixels", 1, 1, 1)
		GameTooltip:AddLine("Lines the window up with whole screen pixels so its borders stay crisp. It can make the "
			.. "window a little larger or smaller than the rest of your UI; turn it off to match the UI scale exactly.",
			nil, nil, nil, true)
		GameTooltip:Show()
	end)
	controls.snap:HookScript("OnLeave", function() GameTooltip:Hide() end)
	settingsBar = controls
	paintSettingsBar()
	return controls, snapLabel
end
