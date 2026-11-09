-- The right-click menu of the arrow, the tracker's title and the 3D view (also /igps menu): quick switches, the
-- route or wing to follow, this run's progress, and the way into the options window. Drawn in the style kit's menu
-- look; a click anywhere else closes it.
local _, ns = ...
local DN, S = ns.DN, ns.Style
local C = S.colors

local MENU_W, HEADING_H = 210, 20
local menu

local function Build()
	menu = CreateFrame("Frame", "InstanceGPSMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	DN.PixelScale(menu)
	S.Frame(menu, "menu")
	menu:Hide()
	menu.items = {}
	S.TrackPopup(menu)
end

local function Item(i)
	local item = menu.items[i]
	if not item then
		item = CreateFrame("Button", nil, menu)
		S.Highlight(item)
		item.text = S.Text(item, "small")
		item.text:SetPoint("LEFT", 8, 0)
		item.text:SetPoint("RIGHT", -8 - S.CHECK_H, 0)
		item.heading = S.Text(item, "small", C.muted)
		item.heading:SetPoint("LEFT", 8, -2)
		item.check = S.Check(item)
		item.check:SetPoint("RIGHT", -6, 0)
		item.check:EnableMouse(false)
		item:SetScript("OnClick", function(self)
			if not self.keepOpen then menu:Hide() end
			self.action()
			if self.keepOpen then DN:ShowMenu(menu.owner, true) end
		end)
		menu.items[i] = item
	end
	return item
end

local function Toggle(key)
	return function()
		DN.opt[key] = not DN.opt[key]
		DN:ApplyOptions()
	end
end

-- The menu's entries: { text, action, checked = true/false for a switch, keepOpen, danger } or { heading }
local function Entries()
	local o, inst = DN.opt, DN.inst
	local list = {
		{ heading = DN.Window.Title() },
		{ text = "Show Arrow", checked = o.arrow, action = Toggle("arrow"), keepOpen = true },
		{ text = "Show Boss Tracker", checked = o.tracker, action = Toggle("tracker"), keepOpen = true },
		{ text = "Route on the Dungeon Map", checked = o.mapOverlay, action = Toggle("mapOverlay"), keepOpen = true },
		{ text = "Path on the Minimap", checked = o.pathMinimap, action = Toggle("pathMinimap"), keepOpen = true },
		{ text = "Path HUD Around the Character", checked = o.pathHud, action = Toggle("pathHud"), keepOpen = true },
		{ text = "3D Path View", checked = o.pathView, action = Toggle("pathView"), keepOpen = true },
		{ text = "Lock Frames", checked = o.lockFrames, action = Toggle("lockFrames"), keepOpen = true },
	}
	if inst and #inst.routes > 1 then
		list[#list + 1] = { heading = "Route / Wing" }
		for i, r in ipairs(inst.routes) do
			list[#list + 1] = { text = r.name or ("Route " .. i), checked = DN.routeIndex == i,
				action = function() DN:SetRoute(i, true) end }
		end
		list[#list + 1] = { text = "Follow Me (Automatic)", checked = not DN.routeManual,
			action = function() DN.routeManual = false end }
	end
	if inst then
		list[#list + 1] = { heading = inst.name }
		list[#list + 1] = { text = "Navigation Here", checked = not DN:IsOff(inst.mapId), keepOpen = true,
			action = function() DN:SetOff(inst.mapId, not DN:IsOff(inst.mapId)) end }
		list[#list + 1] = { text = "Reset Progress for This Run", danger = true,
			action = function() StaticPopup_Show("INSTANCEGPS_RESET") end }
	end
	list[#list + 1] = { heading = "Options" }
	list[#list + 1] = { text = "Instances...", action = function() DN:OpenOptions(true) end }
	list[#list + 1] = { text = "All Options...", action = function() DN:OpenOptions() end }
	return list
end

-- Opens the menu at the cursor (or where it already is, when `again` redraws it after a switch)
function DN:ShowMenu(anchor, again)
	if not menu then Build() end
	local list = Entries()
	local m = S.metrics.menuInset
	local y = -m
	for i, e in ipairs(list) do
		local item = Item(i)
		local h = e.heading and HEADING_H or S.CONTROL_H
		item:SetHeight(h)
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", m, y)
		item:SetPoint("TOPRIGHT", -m, y)
		y = y - h
		item.action, item.keepOpen = e.action, e.keepOpen
		if e.heading then
			item.heading:SetText(e.heading)
			item.heading:Show()
			item.text:Hide()
			item.check:Hide()
			item:Disable()
		else
			item.heading:Hide()
			item.text:SetText(e.text)
			item.text:SetTextColor(unpack(e.danger and C.bad or C.text))
			item.text:Show()
			if e.checked ~= nil then
				item.check:SetChecked(e.checked and true or false)
				item.check:Show()
			else
				item.check:Hide()
			end
			item:Enable()
		end
		item:Show()
	end
	for i = #list + 1, #menu.items do menu.items[i]:Hide() end
	menu:SetSize(MENU_W + 2 * m, -y + m)
	menu.owner = anchor
	if not again then
		local scale = menu:GetEffectiveScale()
		local x, cy = GetCursorPosition()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, cy / scale)
		S.CloseMenus()
	end
	menu:Show()
end
