-- InstanceGPS slash commands and statistics output. The options window, the right-click menu and server modules'
-- option pages are in UI/.
local _, ns = ...
local DN = ns.DN

StaticPopupDialogs["INSTANCEGPS_RESET"] = {
	text = "Reset InstanceGPS progress for this instance?\n(The instance itself is not reset.)",
	button1 = YES, button2 = NO,
	OnAccept = function() DN:ResetRun() end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Shows every option's effect: the arrow, path views, tracker and map route
function DN:ApplyOptions()
	self:UpdateArrowVisibility()
	self:UpdatePathViews()
	self:RefreshTracker()
	if WorldMapFrame:IsShown() then self:RefreshMap() end
end
local function ApplyVisibility() DN:ApplyOptions() end

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
			DN:Print("Not in a dungeon or raid. /igps instances lists them all.")
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
			"/igps options - the options window",
			"/igps minimap | hud | view - toggle the path on the minimap / around you / 3D view",
			"/igps lock - lock/unlock frames",  "/igps resetpos - reset frame positions",
			"/igps off | on - switch navigation (arrow, paths, map route, hints) off or on in this instance",
			"/igps instances - choose the instances with navigation, by expansion",
			"/igps record - record a route to fix or add one for your server (/igps record for more)",
		}
		for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
	end
end
