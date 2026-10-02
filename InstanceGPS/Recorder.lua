-- InstanceGPS route recorder: walk a route once and get it as an override (Override.lua) to paste
-- into a server module. A recording is split into legs, boss to boss: each kill ends a leg. When a
-- leg ends it's cleaned up: detours that come back to where they left (a dead end, running back for
-- loot, circling in a fight) are cut, and the wobble is straightened out.
local _, ns = ...
local DN = ns.DN

local sqrt, floor = math.sqrt, math.floor
local STEP = 2          -- yards between recorded points
local JUMP = 20         -- yards: a bigger jump between two samples is a teleport (or a death)
local LOOP_NEAR = 4     -- yards: coming back this close to an earlier point closes a loop...
local LOOP_MIN = 12     -- ...when the detour was at least this much longer than the direct way
local SIMPLIFY = 1.5    -- yards of wobble straightened out
local UNDO = 20         -- yards dropped by undo when there's no mark to go back to
local TICK = 0.25

local rec                  -- the recording in progress: { map, leg, paused, dead }

local function dist(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

local function Store(map)
	local all = DN.db.recordings or {}
	DN.db.recordings = all
	all[map] = all[map] or { legs = {} }
	return all[map]
end

-------------------------------------------------------------------------------- cleanup

local function Protected(p)
	return p.mark or p.tele
end

-- Cut detours: from each point, the farthest later point it comes back to (same level, nothing
-- marked or teleported in between) closes a loop, and everything in between goes.
local function CutLoops(pts)
	local cum
	local function measure()
		cum = { 0 }
		for k = 2, #pts do cum[k] = cum[k - 1] + dist(pts[k - 1], pts[k]) end
	end
	measure()
	local i = 1
	while i <= #pts - 3 do
		local a, cut = pts[i], nil
		if not a.tele then
			-- a loop can end at a mark or a teleport, but not pass one
			local last = #pts
			for j = i + 1, #pts - 1 do
				if Protected(pts[j]) then last = j break end
			end
			for j = last, i + 3, -1 do
				local b = pts[j]
				if b.l == a.l and dist(a, b) < LOOP_NEAR and cum[j] - cum[i] > dist(a, b) + LOOP_MIN then
					cut = j
					break
				end
			end
		end
		if cut then
			for _ = i + 1, cut - 1 do table.remove(pts, i + 1) end
			measure()
		else
			i = i + 1
		end
	end
end

-- Douglas-Peucker between points that must stay (marks, teleports, level changes).
local function Simplify(pts)
	local keep = { [1] = true, [#pts] = true }
	for i, p in ipairs(pts) do
		if Protected(p) or (pts[i + 1] and pts[i + 1].l ~= p.l) or (pts[i - 1] and pts[i - 1].l ~= p.l) then keep[i] = true end
	end
	local function seg(p, a, b)
		local dx, dy = b.x - a.x, b.y - a.y
		local L2 = dx * dx + dy * dy
		local t = L2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / L2)) or 0
		local qx, qy = a.x + t * dx - p.x, a.y + t * dy - p.y
		return sqrt(qx * qx + qy * qy)
	end
	local function rdp(lo, hi)
		local best, at = 0, nil
		for k = lo + 1, hi - 1 do
			local d = seg(pts[k], pts[lo], pts[hi])
			if d > best then best, at = d, k end
		end
		if at and best > SIMPLIFY then
			keep[at] = true
			rdp(lo, at)
			rdp(at, hi)
		end
	end
	local prev = 1
	for i = 2, #pts do
		if keep[i] then
			rdp(prev, i)
			prev = i
		end
	end
	local out = {}
	for i, p in ipairs(pts) do
		if keep[i] then out[#out + 1] = p end
	end
	return out
end

function DN.CleanLeg(pts)
	CutLoops(pts)
	return Simplify(pts)
end

-------------------------------------------------------------------------------- recording

local function Here()
	if not DN.px then return nil end
	return { x = floor(DN.px * 10 + 0.5) / 10, y = floor(DN.py * 10 + 0.5) / 10, l = DN.pfloor or 0 }
end

local function NewLeg(from)
	rec.leg = { from = from, pts = {} }
	local p = Here()
	if p then rec.leg.pts[1] = p end
end

local function Add(p, force)
	local pts = rec.leg.pts
	local last = pts[#pts]
	if last then
		local d = dist(last, p)
		if d < STEP and not force and last.l == p.l then return end
		if d > JUMP then
			last.tele = true
			if rec.dead then
				DN:Print("Recording: you moved %d yards after dying. Check that stretch on the map, or /igps record undo.", floor(d))
			end
		end
	end
	pts[#pts + 1] = p
	rec.dead = false
	DN.recordVersion = (DN.recordVersion or 0) + 1   -- redraws the map
end

-- End the current leg at boss `to` and keep it (cleaned up); the next leg starts there.
local function FinishLeg(to, custom)
	local leg = rec.leg
	local p = Here()
	if p then Add(p, true) end
	if #leg.pts < 2 then
		NewLeg(to)
		return
	end
	leg.to, leg.custom = to, custom
	local before = #leg.pts
	leg.pts = DN.CleanLeg(leg.pts)
	local store = Store(rec.map)
	-- recording the same leg again replaces it
	for k = #store.legs, 1, -1 do
		if store.legs[k].to == to and store.legs[k].from == leg.from then table.remove(store.legs, k) end
	end
	table.insert(store.legs, leg)
	DN:Print("Recorded %s -> %s: %d points (%d before cleanup).", leg.from or "the entrance", to, #leg.pts, before)
	NewLeg(to)
	if WorldMapFrame:IsShown() then DN:RefreshMap() end
end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if since < TICK then return end
	since = 0
	if not rec or rec.paused then return end
	if not DN.inst or DN.inst.mapId ~= rec.map then return end
	if UnitIsDeadOrGhost("player") then
		rec.dead = true
		return
	end
	local p = Here()
	if p then Add(p) end
end)

DN:On("BOSS_KILLED", function(b, how)
	if rec and not rec.paused and DN.inst and DN.inst.mapId == rec.map and how ~= "manual" then FinishLeg(b.name) end
end)

-------------------------------------------------------------------------------- export

local function num(v)
	local s = ("%.1f"):format(v)
	return (s:gsub("%.0$", ""))
end

local function quote(s)
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- The recordings as an InstanceGPS:Override block for a module's Overrides.lua.
function DN:RecordingExport()
	local all = self.db.recordings or {}
	local L = { "-- Recorded with /igps record. Paste into your module's Overrides.lua.",
	            'InstanceGPS:Override("My Server", {' }
	local maps = {}
	for map in pairs(all) do maps[#maps + 1] = map end
	table.sort(maps)
	for _, map in ipairs(maps) do
		local legs = all[map].legs
		if #legs > 0 then
			local inst = ns.Instances[map]
			local known = {}
			for _, b in ipairs(inst and inst.bosses or {}) do known[b.name] = true end
			L[#L + 1] = ("  [%d] = { -- %s"):format(map, inst and inst.name or "?")
			L[#L + 1] = "    paths = {"
			local hints, custom = {}, {}
			for _, leg in ipairs(legs) do
				local coords, tele = {}, {}
				for i, p in ipairs(leg.pts) do
					coords[#coords + 1] = num(p.x) .. "," .. num(p.y) .. "," .. p.l
					if p.tele then tele[#tele + 1] = i end
					if p.mark then hints[#hints + 1] = p end
				end
				L[#L + 1] = ("      [%s] = { from = %s, points = { %s }%s },"):format(quote(leg.to),
					leg.from and quote(leg.from) or "nil", table.concat(coords, ", "),
					#tele > 0 and (", tele = { " .. table.concat(tele, ", ") .. " }") or "")
				if leg.custom and not known[leg.to] then
					local p = leg.pts[#leg.pts]
					custom[#custom + 1] = ("      [%s] = { x = %s, y = %s, f = %d, after = %s, npcs = { --[[ creature ids that give the kill ]] } },"):format(
						quote(leg.to), num(p.x), num(p.y), p.l, leg.from and quote(leg.from) or "nil")
				end
			end
			L[#L + 1] = "    },"
			if #hints > 0 then
				L[#L + 1] = "    hints = {"
				for _, p in ipairs(hints) do
					L[#L + 1] = ("      { x = %s, y = %s, f = %d, text = %s },"):format(num(p.x), num(p.y), p.l, quote(p.mark))
				end
				L[#L + 1] = "    },"
			end
			if #custom > 0 then
				L[#L + 1] = "    bosses = {"
				for _, line in ipairs(custom) do L[#L + 1] = line end
				L[#L + 1] = "    },"
			end
			L[#L + 1] = "  },"
		end
	end
	L[#L + 1] = "})"
	return table.concat(L, "\n")
end

local exportFrame
local function ShowExport(text)
	if not exportFrame then
		local f = CreateFrame("Frame", "InstanceGPSExport", UIParent)
		f:SetSize(560, 380)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
		                insets = { left = 11, right = 12, top = 12, bottom = 11 } })
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		title:SetPoint("TOP", 0, -16)
		title:SetText("InstanceGPS recording: Ctrl+A, Ctrl+C to copy")
		local scroll = CreateFrame("ScrollFrame", "InstanceGPSExportScroll", f, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 20, -40)
		scroll:SetPoint("BOTTOMRIGHT", -38, 46)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetFontObject(ChatFontNormal)
		edit:SetWidth(490)
		edit:SetAutoFocus(true)
		edit:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(edit)
		f.edit = edit
		local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		close:SetSize(100, 22)
		close:SetPoint("BOTTOM", 0, 16)
		close:SetText(CLOSE or "Close")
		close:SetScript("OnClick", function() f:Hide() end)
		exportFrame = f
	end
	exportFrame.edit:SetText(text)
	exportFrame.edit:HighlightText()
	exportFrame:Show()
end

-------------------------------------------------------------------------------- map

-- recorded legs on the dungeon map: green, the one being recorded brighter
DN.mapLayers = DN.mapLayers or {}
table.insert(DN.mapLayers, function(inst, level, toMap, Dot)
	local store = DN.db and DN.db.recordings and DN.db.recordings[inst.mapId]
	local legs = {}
	for _, leg in ipairs(store and store.legs or {}) do legs[#legs + 1] = { pts = leg.pts } end
	if rec and rec.map == inst.mapId then legs[#legs + 1] = { pts = rec.leg.pts, live = true } end
	if not (DN.showRecording or rec) then return end
	for _, leg in ipairs(legs) do
		local pts = leg.pts
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			if not a.tele and (a.l == level or b.l == level) then
				local x1, y1 = toMap(a.x, a.y)
				local x2, y2 = toMap(b.x, b.y)
				local dx, dy = x2 - x1, y2 - y1
				local len = sqrt(dx * dx + dy * dy)
				local d = 0
				while d < len do
					local t = Dot(x1 + dx * d / len, y1 + dy * d / len)
					t:SetSize(6, 6)
					if leg.live then t:SetVertexColor(0.3, 1, 0.4, 1) else t:SetVertexColor(0.2, 0.8, 0.3, 0.8) end
					d = d + 7
				end
			end
			if a.mark and a.l == level then
				local x, y = toMap(a.x, a.y)
				local t = Dot(x, y)
				t:SetSize(12, 12)
				t:SetVertexColor(0.4, 0.8, 1, 1)
			end
		end
	end
end)

-------------------------------------------------------------------------------- commands

StaticPopupDialogs["INSTANCEGPS_RECORD_CLEAR"] = {
	text = "Delete the recorded legs for %s?",
	button1 = YES, button2 = NO,
	OnAccept = function(self, map)
		if DN.db.recordings then DN.db.recordings[map] = nil end
		DN:Print("Recording deleted.")
		if WorldMapFrame:IsShown() then DN:RefreshMap() end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true,
}

local HELP = {
	"/igps record start - start recording this instance's route (a leg ends at each boss kill)",
	"/igps record pause | resume - stop recording while you go off the route",
	"/igps record mark <text> - a hint at this spot (kept when detours are cut)",
	"/igps record undo - drop back to the last mark (or the last 20 yards)",
	"/igps record boss <name> - end the leg here, at a boss that isn't detected (a custom one)",
	"/igps record drop - delete the last recorded leg to record it again",
	"/igps record show - show the recorded legs on the map (also while recording)",
	"/igps record export - the recording as an override to paste into a module",
	"/igps record stop | clear - stop recording | delete this instance's recording",
}

function DN:RecordCommand(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local inst = self.inst
	if cmd == "start" then
		if not inst then return self:Print("Recording works inside a dungeon or raid.") end
		if not self.px then return self:Print("No map position here; recording needs one (see the dungeon map patch note).") end
		local from
		if self.run then
			-- start from the last boss killed this run, if any
			local best = -1
			for _, b in ipairs(inst.bosses) do
				local t = self.run.killed[b.id]
				if t and t > best then best, from = t, b.name end
			end
		end
		rec = { map = inst.mapId }
		NewLeg(from)
		self:Print("Recording from %s. Each boss kill ends a leg; /igps record for the commands.", from or "here")
	elseif cmd == "help" or cmd == "" then
		if rec then
			self:Print("Recording%s: %d points in this leg (from %s).", rec.paused and " (paused)" or "", #rec.leg.pts, rec.leg.from or "the start")
		end
		for _, l in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
	elseif cmd == "show" then
		self.showRecording = not self.showRecording
		self:Print("Recorded legs %s on the map.", self.showRecording and "shown" or "hidden")
		if WorldMapFrame:IsShown() then self:RefreshMap() end
	elseif cmd == "export" then
		ShowExport(self:RecordingExport())
	elseif cmd == "clear" then
		if not inst then return self:Print("Clear works inside the instance whose recording it is.") end
		StaticPopup_Show("INSTANCEGPS_RECORD_CLEAR", inst.name).data = inst.mapId
	elseif cmd == "drop" then
		local store = inst and self.db.recordings and self.db.recordings[inst.mapId]
		local leg = store and table.remove(store.legs)
		self:Print(leg and ("Dropped the leg %s -> %s."):format(leg.from or "the entrance", leg.to) or "No recorded leg to drop here.")
		if WorldMapFrame:IsShown() then self:RefreshMap() end
	elseif not rec then
		self:Print("Not recording. /igps record start to begin.")
	elseif cmd == "stop" then
		rec = nil
		self:Print("Recording stopped. /igps record export when you're done.")
	elseif cmd == "pause" then
		rec.paused = true
		self:Print("Recording paused.")
	elseif cmd == "resume" then
		rec.paused = false
		self:Print("Recording resumed.")
	elseif cmd == "mark" then
		local p = Here()
		if not p then return end
		p.mark = rest ~= "" and rest or "?"
		Add(p, true)
		self:Print("Marked: %s", p.mark)
	elseif cmd == "undo" then
		local pts = rec.leg.pts
		local walked = 0
		while #pts > 1 do
			local last = table.remove(pts)
			if pts[#pts].mark then break end
			walked = walked + dist(last, pts[#pts])
			if walked >= UNDO then break end
		end
		self:Print("Undone: %d points left in this leg.", #pts)
	elseif cmd == "boss" then
		if rest == "" then return self:Print("/igps record boss <name>") end
		FinishLeg(rest, true)
	else
		self:Print("Unknown record command; /igps record for the list.")
	end
end
