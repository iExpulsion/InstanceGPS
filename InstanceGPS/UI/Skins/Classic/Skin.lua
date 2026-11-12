-- Vendored from MaterialCraftUI v1.4.0. Change it there, then run tools/sync_style.py.
-- Classic: the default UI's own look, drawn entirely from textures the 3.3.5 client ships, so there's no art in
-- this folder. Dialog-box windows, red panel buttons, gold text, tooltip-bordered menus and lists, and the quest
-- log's row highlight. Load it after Style.lua; S.UseSkin("classic") switches to it.
local _, NS = ...
local S = NS.Style

local DIALOG_BG = "Interface\\DialogFrame\\UI-DialogBox-Background"
local DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local TOOLTIP_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local BUTTON = "Interface\\Buttons\\UI-Panel-Button-"
local INPUT = "Interface\\Common\\Common-Input-Border"
-- the quest log's title row highlight, made for list rows (the quest greeting's highlight glows past a short row)
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local CHECK = "Interface\\Buttons\\UI-CheckBox-"
local SLIDER, SLIDER_H = "Interface\\Buttons\\UI-SliderBar-", 17
-- the Interface Options tabs, as their template crops them: 20 pixel caps, 0.15625 of the art each side, 24 tall
local TAB = "Interface\\OptionsFrame\\UI-OptionsFrame-"
local TAB_CAP, TAB_U, TAB_H, TAB_DROP = 20, 0.15625, 24, 3
local TAB_HIGHLIGHT = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight"
-- how much larger than the checkbox its art is drawn: the stock box fills about the middle 60% of its texture
local CHECK_ART = 1.7

-- How far a window's content starts in from its edges: inside the dialog border's 11 pixels.
local EDGE = 12
-- how much black goes over the dialog background, a window's and a popup's
local WINDOW_FILL, POPUP_FILL = 0.5, 0.8
-- The panel button art's caps, as the stock template crops them: 12 of 128 pixels each side, 22 of 32 tall.
local CAP, CAP_U, MID_U, ART_V = 12, 0.09375, 0.53125, 0.6875
local BUTTON_RIGHT = 0.625

-- Label colors for each button kind, from the stock fonts: gold, white when it's the selected one, red for danger.
local GOLD, WHITE, GRAY = { 1, 0.82, 0, 1 }, { 1, 1, 1, 1 }, { 0.5, 0.5, 0.5, 1 }
local LABEL = { primary = GOLD, secondary = GOLD, ghost = GOLD, selected = WHITE, danger = { 1, 0.35, 0.3, 1 } }

local function tooltipPanel(f, alpha)
	f:SetBackdrop({ bgFile = TOOLTIP_BG, edgeFile = TOOLTIP_EDGE, tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	f:SetBackdropColor(0, 0, 0, alpha or 0.9)
	f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

-- Three slices of a texture across a frame: fixed caps of `cap` pixels, the middle stretching. With `height`, they
-- run along the frame's bottom at that height instead of filling it.
local function threeSlice(frame, layer, texture, cap, u0, u1, u2, u3, v1, height)
	local parts = {}
	for i = 1, 3 do parts[i] = frame:CreateTexture(nil, layer) end
	parts[1]:SetTexCoord(u0, u1, 0, v1)
	parts[2]:SetTexCoord(u1, u2, 0, v1)
	parts[3]:SetTexCoord(u2, u3, 0, v1)
	if height then
		parts[1]:SetPoint("BOTTOMLEFT")
		parts[1]:SetHeight(height)
		parts[3]:SetPoint("BOTTOMRIGHT")
		parts[3]:SetHeight(height)
	else
		parts[1]:SetPoint("TOPLEFT")
		parts[1]:SetPoint("BOTTOMLEFT")
		parts[3]:SetPoint("TOPRIGHT")
		parts[3]:SetPoint("BOTTOMRIGHT")
	end
	parts[1]:SetWidth(cap)
	parts[3]:SetWidth(cap)
	parts[2]:SetPoint("TOPLEFT", parts[1], "TOPRIGHT")
	parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "BOTTOMLEFT")
	local set = { parts = parts }
	function set:SetTexture(path) for _, t in ipairs(parts) do t:SetTexture(path) end end
	function set:SetVertexColor(...) for _, t in ipairs(parts) do t:SetVertexColor(...) end end
	if texture then set:SetTexture(texture) end
	return set
end

-- The quest log's highlight over a row, shown while the mouse is over it.
local function rowHighlight(f)
	local t = f:CreateTexture(nil, "HIGHLIGHT")
	t:SetTexture(ROW_HIGHLIGHT)
	t:SetBlendMode("ADD")
	t:SetAllPoints()
	return t
end

S.RegisterSkin("classic", {
	label = "Classic",
	credit = "The default UI's own frames, buttons and fonts.",
	roles = {
		surfaceLowest = "000000", surface = "0b0b0b", surfaceLow = "111111", surfaceContainer = "161616",
		surfaceHigh = "262626", onSurface = "ffffff", onSurfaceVariant = "bfbfbf", outline = "999999",
		outlineVariant = "4d4d4d", primary = "ffd100", onPrimary = "000000", error = "ff3a30", errorContainer = "5a1210",
		success = "1eff00", warning = "ff8000",
	},
	-- rows take a blue wash on hover and a gold one when selected, as the quest log does
	colors = function(c)
		c.heading = GOLD
		c.disabled = GRAY
		c.rowHover = { 0.25, 0.45, 0.95, 0.22 }
		c.rowSelected = { 1, 0.82, 0, 0.18 }
		c.navSelected = WHITE
		c.arrow = GOLD
		c.scrollThumb = { 0.55, 0.55, 0.55, 1 }
		c.scrollThumbHover = { 0.85, 0.85, 0.85, 1 }
	end,
	-- the tooltip border on menus, wells and the sidebar is 4 pixels; rows sit inside it
	metrics = { edge = EDGE, inset = 16, navInset = 4, wellInset = 4, menuInset = 4, tabPad = TAB_CAP },
	-- the red panel button: its normal, pushed and disabled faces in three slices, and the stock additive highlight
	button = function(b)
		b.face = threeSlice(b, "BORDER", BUTTON .. "Up", CAP, 0, CAP_U, MID_U, BUTTON_RIGHT, ART_V)
		local glow = b:CreateTexture(nil, "HIGHLIGHT")
		glow:SetTexture(BUTTON .. "Highlight")
		glow:SetTexCoord(0, BUTTON_RIGHT, 0, ART_V)
		glow:SetBlendMode("ADD")
		glow:SetAllPoints()
		b.glow = glow
	end,
	-- a selected segment shows the pushed face, so the row reads as a set of toggles
	paintButton = function(b, enabled)
		local face = not enabled and "Disabled" or (b.down or b.kind == "selected") and "Down" or "Up"
		b.face:SetTexture(BUTTON .. face)
		b.glow:SetAlpha(enabled and 1 or 0)
		b.label:SetTextColor(unpack(enabled and (LABEL[b.kind] or GOLD) or GRAY))
	end,
	frame = function(f, role)
		if role == "menu" then
			tooltipPanel(f, 0.95)
		else
			f:SetBackdrop({ bgFile = DIALOG_BG, edgeFile = DIALOG_EDGE, tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 } })
			f:SetBackdropColor(1, 1, 1, 1)
			f:SetBackdropBorderColor(1, 1, 1, 1)
			-- the dialog background is see-through in its art; black over it inside the border makes a window
			-- readable over the world, and a popup over the window behind it
			local fill = f:CreateTexture(nil, "BACKGROUND")
			fill:SetTexture("Interface\\Buttons\\WHITE8X8")
			fill:SetVertexColor(0, 0, 0, role == "popup" and POPUP_FILL or WINDOW_FILL)
			fill:SetPoint("TOPLEFT", 11, -12)
			fill:SetPoint("BOTTOMRIGHT", -12, 11)
			f.fill = fill
		end
	end,
	well = function(f)
		tooltipPanel(f, 0.75)
	end,
	-- no rule under a title bar, which the dialog frame already sets apart; a soft gray line under tab bars, table
	-- headers and beside section headings, like the tooltip border's
	line = function(parent, kind)
		local t = parent:CreateTexture(nil, "BORDER")
		t:SetTexture("Interface\\Buttons\\WHITE8X8")
		t:SetVertexColor(0.6, 0.6, 0.6, 0.45)
		if kind == "rule" then t:Hide() end
		return t, 1
	end,
	sidebar = function(side)
		tooltipPanel(side, 0.6)
	end,
	highlight = function(f)
		rowHighlight(f)
	end,
	-- hover is the quest log's highlight; the selected entry keeps it lit in gold
	navEntry = function(b)
		rowHighlight(b)
		b.selectedTex = b:CreateTexture(nil, "BACKGROUND")
		b.selectedTex:SetTexture(ROW_HIGHLIGHT)
		b.selectedTex:SetBlendMode("ADD")
		b.selectedTex:SetVertexColor(1, 0.82, 0)
		b.selectedTex:SetAllPoints()
		b.label:SetPoint("LEFT", S.PAD, 0)
	end,
	paintNav = function(b, on)
		if on then b.selectedTex:Show() else b.selectedTex:Hide() end
	end,
	-- the Interface Options tabs along the bar's bottom: the open-bottomed active tab while selected, the inactive one
	-- otherwise, with the character frame's tab glow on hover and the label centered on the art
	tab = function(b)
		local function art(name)
			return threeSlice(b, "BORDER", TAB .. name, TAB_CAP, 0, TAB_U, 1 - TAB_U, 1, 1, TAB_H)
		end
		b.active, b.inactive = art("ActiveTab"), art("InActiveTab")
		local glow = b:CreateTexture(nil, "HIGHLIGHT")
		glow:SetTexture(TAB_HIGHLIGHT)
		glow:SetBlendMode("ADD")
		glow:SetPoint("BOTTOMLEFT", TAB_CAP / 2, 0)
		glow:SetPoint("BOTTOMRIGHT", -TAB_CAP / 2, 0)
		glow:SetHeight(TAB_H)
		b.labelY = -math.floor(((b:GetHeight() or TAB_H) - TAB_H) / 2)
	end,
	-- the inactive tab is drawn lower in its art than the active one, so its label drops to match, as the stock
	-- tabs' does
	paintTab = function(b, on)
		for _, t in ipairs(b.active.parts) do if on then t:Show() else t:Hide() end end
		for _, t in ipairs(b.inactive.parts) do if on then t:Hide() else t:Show() end end
		b.label:SetPoint("LEFT", S.metrics.tabPad, b.labelY - (on and 0 or TAB_DROP))
	end,
	-- the stock checkbox, its art drawn larger than the box, since the box fills only the middle of it
	check = function(b)
		local size = (b:GetWidth() or 14) * CHECK_ART
		local function layer(name, path)
			local t = b:CreateTexture(nil, name)
			t:SetTexture(path)
			t:SetPoint("CENTER")
			t:SetWidth(size)
			t:SetHeight(size)
			return t
		end
		b.box = layer("BACKGROUND", CHECK .. "Up")
		b.tick = layer("ARTWORK", CHECK .. "Check")
		b.glow = layer("HIGHLIGHT", CHECK .. "Highlight")
		b.glow:SetBlendMode("ADD")
	end,
	paintCheck = function(b)
		if b.on then b.tick:Show() else b.tick:Hide() end
		b.tick:SetTexture(CHECK .. (b.usable and "Check" or "Check-Disabled"))
		b.box:SetDesaturated(not b.usable)
		b.glow:SetAlpha(b.usable and 1 or 0)
	end,
	-- the Interface Options slider: its bordered groove, 17 tall in the middle of the control, and its knob
	slider = function(s)
		s.bar = CreateFrame("Frame", nil, s)
		s.bar:SetHeight(SLIDER_H)
		s.bar:SetPoint("LEFT")
		s.bar:SetPoint("RIGHT")
		s.bar:SetFrameLevel(s:GetFrameLevel())
		s.bar:SetBackdrop({ bgFile = SLIDER .. "Background", edgeFile = SLIDER .. "Border", tile = true, tileSize = 8,
			edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
		local thumb = s:CreateTexture(nil, "OVERLAY")
		thumb:SetTexture(SLIDER .. "Button-Horizontal")
		thumb:SetSize(32, 32)
		s:SetThumbTexture(thumb)
	end,
	paintSlider = function(s)
		local thumb = s:GetThumbTexture()
		local shade = not s.usable and 0.45 or s.hovered and 1 or 0.85
		thumb:SetVertexColor(shade, shade, shade)
		thumb:SetDesaturated(not s.usable)
		if s.usable then s.valueText:SetTextColor(1, 1, 1) else s.valueText:SetTextColor(0.5, 0.5, 0.5) end
	end,
	-- one-line fields are the stock edit box border; tall ones a tooltip-bordered box
	input = function(e, tall)
		e.tall = tall
		if tall then
			tooltipPanel(e.box, 0.75)
		else
			e.border = threeSlice(e, "BACKGROUND", INPUT, 8, 0, 0.0625, 0.9375, 1, 0.625)
		end
	end,
	-- a field brightens while hovered or focused; a tall box's border turns gold while focused
	paintInput = function(e)
		if e.tall then
			if e.focused then e.box:SetBackdropBorderColor(1, 0.82, 0, 1) else e.box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end
		else
			local v = (e.focused or e.hovered) and 1 or 0.8
			e.border:SetVertexColor(v, v, v)
		end
	end,
})
