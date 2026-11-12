-- InstanceGPS arrow: points at the next waypoint on the route (RouteUtils' arrow).
local _, ns = ...
local DN, R = ns.DN, ns.Route

local floor = math.floor

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
	end
	local patrol = DN:NearPatrol()
	return patrol and "|cffff5050Patrols:|r %s" or "", patrol
end

local sinceUpdate = 0
arrow:SetScript("OnUpdate", function(self, elapsed)
	sinceUpdate = sinceUpdate + elapsed
	if sinceUpdate >= 0.03 then
		sinceUpdate = 0
		local w = DN.wp
		if w.x then
			local dist, atBoss = w.dist, w.atBoss
			self:Point(DN.px, DN.py, GetPlayerFacing() or 0, w.x, w.y, atBoss and dist < 20)
			local remain = atBoss and dist or DN.remaining or dist
			local hint, hintValue = HintLine(w)
			SetLines(w.boss.name, "%d yd", floor(remain), hint, hintValue)
		else
			self:Idle()
			IdleLines()
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
