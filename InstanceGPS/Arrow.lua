-- InstanceGPS arrow: points at the next waypoint on the route (RouteUtils' arrow).
local _, ns = ...
local DN, R = ns.DN, ns.Route

local floor = math.floor

-- Yards from the boss within which the arrow points down at the player
DN.AT_BOSS_YARDS = 20

local arrow = R.NewArrow({
	name = "InstanceGPSArrow",
	locked = function() return DN.opt.lockFrames end,
	onMoved = function(pos) DN.db.pos.arrow = pos end,
	onMenu = function(self) DN:ShowMenu(self) end,
	onTooltip = function(tip)
		tip:AddLine("InstanceGPS")
		local b = DN.inst and (DN.wp.boss or DN:NextBoss())
		if b and b.quest then
			tip:AddLine(b.title, 1, 1, 1)
			tip:AddLine(b.name, 0.8, 0.8, 0.8)
		elseif b then
			DN:Fire("BOSS_TOOLTIP", b, tip)
		end
		DN.HintLines(tip, not DN.opt.lockFrames and "Drag: Move", "Right-Click: Options")
	end,
})
DN.arrow = arrow
DN.SetRotation = R.SetRotation

-- The lines under the arrow change only when what they say does: each is a fixed string or a format and its value
local shownTitle, shownSub, shownSubValue, shownHint, shownHintValue
local function SetLines(title, sub, subValue, hint, hintValue)
	if title ~= shownTitle or sub ~= shownSub or subValue ~= shownSubValue or hint ~= shownHint
		or hintValue ~= shownHintValue then
		shownTitle, shownSub, shownSubValue, shownHint, shownHintValue = title, sub, subValue, hint, hintValue
		arrow:SetText(title, subValue and sub:format(subValue) or sub, hintValue and hint:format(hintValue) or hint)
	end
end

local function IdleLines()
	local b = DN:NextBoss()
	if not b then
		SetLines(DN.inst and "All Bosses Down" or "", "")
	elseif not b.x then
		SetLines(b.name, "No Known Position for This Fight")
	elseif not DN.px then
		-- the client reports no map position here: this instance has no in-game map
		SetLines(b.name, DN.inst and DN.inst.needsMapPatch and "Needs the WoW Dungeon Maps Patch" or "Waiting for a Map Position")
	else
		SetLines(b.name, "")
	end
end

local function HintLine(w)
	local f, dist, portal = w.f, w.dist, w.portal
	if type(portal) == "string" then
		return portal
	elseif portal and dist < 12 then
		return "Use the Teleporter Here"
	elseif portal then
		return "Teleporter in %d yd", floor(dist)
	elseif f and DN.inst and DN.pfloor and not DN.OnFloor(f, DN.pfloor)
		and (DN.FirstFloor(DN.OwnLevels(DN.inst, f)) or 0) ~= 0 then
		return "Level %d", DN.FirstFloor(DN.OwnLevels(DN.inst, f))
	elseif w.boss and w.boss.note then
		-- a quest stop's item to use (QuestGPS.lua), which says more than a patrol nearby
		return w.boss.note
	end
	local patrol = DN:NearPatrol()
	return patrol and "|cffff5050Patrols:|r %s" or "", patrol
end

-- The first of a hint's items the player carries (DN.hintItems), else a quest stop's item while carried
local function CarriedItem(text, stop)
	local items = text and DN.hintItems[text]
	if items then
		for _, id in ipairs(items) do
			if GetItemCount(id) > 0 then return id end
		end
	end
	local item = stop and stop.item
	return item and GetItemCount(item) > 0 and item or nil
end

-- A hint's item beside the arrow (Omokk's Head at Urok's pile): using an item that casts a spell is protected, so
-- it's a secure button on UIParent, placed over that spot on the arrow's layer and changed only out of combat (it
-- stays as it was during a fight)
local itemButton, shownItem, itemX, itemY, itemLevel, itemCount
local function ItemButton()
	if not itemButton then
		local b = CreateFrame("Button", "InstanceGPSArrowItem", UIParent, "SecureActionButtonTemplate")
		b:SetSize(30, 30)
		b:SetAttribute("type", "item")
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.count:SetPoint("BOTTOMRIGHT", -2, 2)
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:" .. shownItem)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:Hide()
		itemButton, DN.itemButton = b, b
	end
	return itemButton
end

local function ShowItem(id)
	local x, y, level = arrow:GetRight(), select(2, arrow:GetCenter()), arrow:GetFrameLevel()
	if not InCombatLockdown() and (id ~= shownItem or (id and (x ~= itemX or y ~= itemY or level ~= itemLevel))) then
		local b = ItemButton()
		shownItem, itemX, itemY, itemLevel, itemCount = id, x, y, level, nil
		if id and x then
			b:SetAttribute("item", "item:" .. id)
			b.icon:SetTexture(GetItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
			-- at the arrow's scale, so its own offsets are the arrow's
			b:SetScale(arrow:GetEffectiveScale() / UIParent:GetEffectiveScale())
			b:ClearAllPoints()
			b:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x + 6, y)
			b:SetFrameStrata(arrow:GetFrameStrata())
			b:SetFrameLevel(level + 1)
			b:Show()
		else
			shownItem = nil
			b:Hide()
		end
	end
	if shownItem and shownItem == id then
		local n = GetItemCount(id)
		if n ~= itemCount then
			itemCount = n
			itemButton.count:SetText(n > 1 and n or "")
		end
	end
end

-- a hidden arrow takes its item with it, once out of combat
arrow:HookScript("OnHide", function() ShowItem(nil) end)
local combatEnd = CreateFrame("Frame")
combatEnd:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEnd:SetScript("OnEvent", function()
	if not arrow:IsVisible() then ShowItem(nil) end
end)

local sinceUpdate = 0
arrow:SetScript("OnUpdate", function(self, elapsed)
	sinceUpdate = sinceUpdate + elapsed
	if sinceUpdate >= 0.03 then
		sinceUpdate = 0
		local w = DN.wp
		if w.x then
			local dist, atBoss = w.dist, w.atBoss
			-- at the boss the arrow points down at the player and bobs, as QuestGPS's does in an objective's area
			if atBoss and dist < DN.AT_BOSS_YARDS then
				self:Here()
			else
				self:Point(DN.px, DN.py, GetPlayerFacing() or 0, w.x, w.y, false)
			end
			local remain = atBoss and dist or DN.remaining or dist
			local hint, hintValue = HintLine(w)
			SetLines(w.boss.name, "%d yd", floor(remain), hint, hintValue)
			ShowItem(CarriedItem(type(w.portal) == "string" and w.portal or nil, w.boss))
		else
			self:Idle()
			IdleLines()
			ShowItem(nil)
		end
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
