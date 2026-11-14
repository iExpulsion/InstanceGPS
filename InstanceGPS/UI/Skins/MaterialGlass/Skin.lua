-- Vendored from MaterialCraftUI v1.5.0. Change it there, then run tools/sync_style.py.
-- MIT License, Copyright (c) 2026 Expulsion: https://github.com/iExpulsion/MaterialCraftUI
-- Material Glass: Material's flat controls on see-through glass. Windows are a light-tinted, translucent pane with
-- a faint cloudy frost, a soft sheen down from the top and a lit top edge; wells, inputs and menus stay near solid
-- so text in them reads over anything. The 3.3.5 client can't blur what's behind a frame, so the frost texture
-- stands in for it. Load it after Style.lua; S.UseSkin("materialglass") switches to it.
local ADDON, NS = ...
local S = NS.Style

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GRAIN = "Interface\\AddOns\\" .. ADDON .. "\\UI\\Skins\\MaterialGlass\\MaterialGlass"
-- the units one tile of the frost texture covers: its 128 pixels drawn at twice their size, so its clouds stay soft
local GRAIN_SIZE = 256
-- how see-through a window is, and how strongly the frost, the sheen and the lit top edge show on it; the frost
-- stays faint, as a stronger one reads as static
local WINDOW_ALPHA, GRAIN_ALPHA, SHEEN_ALPHA, SHINE_ALPHA = 0.8, 0.05, 0.07, 0.2
-- how far down a window the sheen fades out, as a share of its height, and at most
local SHEEN_SHARE, SHEEN_MAX = 0.4, 160
-- the outer edge of a window, popup or menu: dark, so the pane stands off a bright background
local EDGE = { 0, 0, 0, 0.55 }
-- wells and inputs: the same border as buttons and dropdowns, so a row of fields shares one edge, and a fainter lit
-- top edge, so their dark fill looks set into the glass rather than cut out of it
local FIELD_BORDER, FIELD_SHINE = { 1, 1, 1, 0.14 }, 0.06

-- button kinds, filled from the scheme in colors(): fill, hover fill, border, label, and its lit top edge's alpha
local KINDS = {}

local function mix(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function tint(c, a)
	return { c[1], c[2], c[3], a }
end

local function white(a)
	return { 1, 1, 1, a }
end

-- Runs layout(w, h) now and whenever the frame is resized or shown.
local function follow(frame, layout)
	local function run()
		local w, h = frame:GetWidth(), frame:GetHeight()
		if w and h and w > 0 and h > 0 then layout(w, h) end
	end
	frame:HookScript("OnSizeChanged", run)
	frame:HookScript("OnShow", run)
	run()
end

-- A one-unit light line along the inside of a frame's top edge.
local function shine(f, alpha)
	local t = S.Solid(f, "BORDER", white(alpha))
	t:SetHeight(1)
	t:SetPoint("TOPLEFT", 1, -1)
	t:SetPoint("TOPRIGHT", -1, -1)
	return t
end

-- Covers w by h inside the frame's edge with grain tiles, the last row and column cropped. The 3.3.5 client clamps
-- texture coordinates past 1 instead of wrapping them, so one stretched texture would smear its edge pixels.
-- Tiles are kept for reuse and only made when a resize needs more.
local function tileGrain(f, w, h)
	local tiles = f.grain
	local cols, rows = math.ceil(w / GRAIN_SIZE), math.ceil(h / GRAIN_SIZE)
	local n = 0
	for row = 1, rows do
		for col = 1, cols do
			n = n + 1
			local t = tiles[n]
			if not t then
				t = f:CreateTexture(nil, "BORDER")
				t:SetTexture(GRAIN)
				t:SetVertexColor(1, 1, 1, GRAIN_ALPHA)
				tiles[n] = t
			end
			local x, y = (col - 1) * GRAIN_SIZE, (row - 1) * GRAIN_SIZE
			local tw, th = math.min(GRAIN_SIZE, w - x), math.min(GRAIN_SIZE, h - y)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", f, "TOPLEFT", 1 + x, -1 - y)
			t:SetWidth(tw)
			t:SetHeight(th)
			t:SetTexCoord(0, tw / GRAIN_SIZE, 0, th / GRAIN_SIZE)
			t:Show()
		end
	end
	for i = n + 1, #tiles do tiles[i]:Hide() end
end

-- The glass: a translucent fill in the dark edge, the grain tiled over it, the sheen and the lit top edge.
local function glass(f, fill)
	S.Panel(f, fill, EDGE)
	f.grain = {}
	f.sheen = S.Solid(f, "BORDER", white(1))
	f.sheen:SetGradientAlpha("VERTICAL", 1, 1, 1, 0, 1, 1, 1, SHEEN_ALPHA)
	f.sheen:SetPoint("TOPLEFT", 1, -1)
	f.sheen:SetPoint("TOPRIGHT", -1, -1)
	f.shine = shine(f, SHINE_ALPHA)
	follow(f, function(w, h)
		tileGrain(f, w - 2, h - 2)
		f.sheen:SetHeight(math.min(h * SHEEN_SHARE, SHEEN_MAX))
	end)
end

S.RegisterSkin("materialglass", {
	label = "Material Glass",
	-- the scheme's surfaces made see-through: the window a pane lifted a little toward the text color, popups and
	-- cards nearly solid, wells and inputs dark enough to read in; lines and outlines are light, as on glass, and
	-- muted text is lifted toward the text color, since whatever is behind the glass can be bright
	colors = function(c, M3)
		c.window = tint(mix(M3.surface, M3.onSurface, 0.05), WINDOW_ALPHA)
		c.muted = tint(mix(M3.onSurfaceVariant, M3.onSurface, 0.35), 1)
		c.sidebar = { 0, 0, 0, 0.18 }
		c.panel = tint(M3.surfaceContainer, 0.9)
		c.well = tint(M3.surfaceLowest, 0.8)
		c.border = white(0.1)
		c.outline = white(0.3)
		c.scrollThumb = white(0.18)
		c.scrollThumbHover = white(0.32)
		KINDS.primary = { bg = c.accent, hover = c.accentHover, border = c.accent, text = c.onAccent, shine = 0.3 }
		KINDS.secondary = { bg = white(0.06), hover = white(0.11), border = white(0.14), text = c.text, shine = 0.12 }
		KINDS.selected = { bg = tint(c.accent, 0.2), hover = tint(c.accent, 0.28), border = tint(c.accent, 0.55),
			text = c.accent, shine = 0.1 }
		KINDS.danger = { bg = white(0.06), hover = tint(c.bad, 0.14), border = white(0.14), text = c.bad, shine = 0.12 }
		KINDS.ghost = { bg = white(0), hover = c.hover, border = white(0), text = c.muted, shine = 0 }
		KINDS.disabled = { bg = white(0.03), hover = white(0.03), border = white(0.12), text = c.disabled, shine = 0 }
	end,
	-- a translucent fill in a light border, with a lit top edge
	button = function(b)
		b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		b.shine = shine(b, 1)
	end,
	paintButton = function(b, enabled)
		local kind = enabled and KINDS[b.kind] or KINDS.disabled
		b:SetBackdropColor(unpack(b.hovered and enabled and kind.hover or kind.bg))
		b:SetBackdropBorderColor(unpack(kind.border))
		b.shine:SetAlpha(kind.shine)
		b.label:SetTextColor(unpack(kind.text))
	end,
	-- a window is the glass; a popup, which sits over a window, the same glass nearly solid, so the window doesn't
	-- show through it; a menu a near-solid panel with a lit top edge
	frame = function(f, role)
		if role == "window" then
			glass(f, S.colors.window)
		elseif role == "popup" then
			local c = S.colors.window
			glass(f, { c[1], c[2], c[3], 0.96 })
		else
			S.Panel(f, tint(S.colors.panel, 0.97), EDGE)
			f.shine = shine(f, SHINE_ALPHA)
		end
	end,
	well = function(f)
		S.Panel(f, S.colors.well, FIELD_BORDER)
		f.shine = shine(f, FIELD_SHINE)
	end,
	line = function(parent)
		return S.Solid(parent, "BORDER", S.colors.border), 1
	end,
	-- a darker pane inside the window's edge, with a light line on its right
	sidebar = function(side)
		local fill = S.Solid(side, "BACKGROUND", S.colors.sidebar)
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMRIGHT", 0, 1)
		local edge = S.Solid(side, "BORDER", S.colors.border)
		edge:SetWidth(1)
		edge:SetPoint("TOPRIGHT")
		edge:SetPoint("BOTTOMRIGHT")
	end,
	highlight = function(f)
		S.Solid(f, "HIGHLIGHT", S.colors.hover):SetAllPoints()
	end,
	-- Material's: a tint and an accent bar on the selected entry
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
	input = function(e)
		local box = e.box or e
		S.Panel(box, S.colors.well, FIELD_BORDER)
		box.shine = shine(box, FIELD_SHINE)
	end,
	-- the field border at rest, brighter on hover, the accent while focused
	paintInput = function(e)
		(e.box or e):SetBackdropBorderColor(unpack(e.focused and S.colors.accent or e.hovered and S.colors.outline or FIELD_BORDER))
	end,
})
