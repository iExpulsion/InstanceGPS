-- Vendored from RouteUtils v0.2.0-9-g645910a. Change it there, then run tools/sync_route.py.
-- MIT License, Copyright (c) 2026 Expulsion.
-- RouteUtils: route ordering and the pieces that guide a player along a route in WoW 3.3.5: a turning arrow,
-- dots along the path on the minimap and the world map, and the geometry behind them. Each addon ships its own
-- copy (RouteUtils/RouteUtils.lua and RouteUtils/Media) and reads it as NS.Route from its addon table.
local ADDON, NS = ...
local R = {}
NS.Route = R

local sqrt, abs, max = math.sqrt, math.abs, math.max
local sin, cos, atan2, fmod, pi = math.sin, math.cos, math.atan2, math.fmod, math.pi

R.MEDIA = "Interface\\AddOns\\" .. (ADDON or "") .. "\\RouteUtils\\Media\\"

-------------------------------------------------------------------------------- geometry

function R.Distance(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return sqrt(dx * dx + dy * dy)
end

-- The clockwise turn (radians, -pi..pi) from the way the player faces to a point, and the distance to it.
-- Facing and bearings count counterclockwise from north, as GetPlayerFacing does; world x is north, y west.
function R.Turn(px, py, facing, x, y)
	local bearing = atan2(y - py, x - px)
	local rel = (facing - bearing + pi) % (2 * pi) - pi
	return rel, R.Distance(px, py, x, y)
end

-- Green straight ahead, yellow and orange to turn, red once arrived
function R.ArrowColor(rel, arrived)
	local off = abs(rel) / pi
	local r, g, b = 1, 0.45, 0.2
	if arrived then
		r, g, b = 1, 0.25, 0.25
	elseif off < 0.15 then
		r, g, b = 0.3, 1, 0.3
	elseif off < 0.5 then
		r, g, b = 1, 0.85, 0.2
	end
	return r, g, b
end

-- Rotates a texture clockwise by `a` radians (texcoords rotate the other way)
function R.SetRotation(t, a)
	local c, s = cos(-a), sin(-a)
	local ulx, uly = 0.5 - 0.5 * c + 0.5 * s, 0.5 - 0.5 * s - 0.5 * c
	local llx, lly = 0.5 - 0.5 * c - 0.5 * s, 0.5 - 0.5 * s + 0.5 * c
	local urx, ury = 0.5 + 0.5 * c + 0.5 * s, 0.5 + 0.5 * s - 0.5 * c
	local lrx, lry = 0.5 + 0.5 * c - 0.5 * s, 0.5 + 0.5 * s + 0.5 * c
	t:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end

-- Calls fn(x, y, dx, dy, along) every `spacing` units along a path of points (x1, y1, x2, y2, ...; n numbers),
-- up to maxLen from its start. Marks are counted from the path's vertices, not its start, so they stay put while
-- the start (the player) moves.
function R.Sample(pts, n, spacing, maxLen, fn)
	if pts and n >= 4 then
		local along, carry = 0, 0
		for i = 1, n - 3, 2 do
			local x1, y1, x2, y2 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
			local dx, dy = x2 - x1, y2 - y1
			local L = sqrt(dx * dx + dy * dy)
			if L > 0 then
				dx, dy = dx / L, dy / L
				local t = i == 1 and fmod(L, spacing) or carry
				if i == 1 and t < 1.5 then t = t + spacing end
				while t < L - 0.01 do
					if along + t > maxLen then return end
					fn(x1 + dx * t, y1 + dy * t, dx, dy, along + t)
					t = t + spacing
				end
				carry = max(0, t - L)
				along = along + L
			end
		end
	end
end

-- Texture pool: Begin(), Get() for each texture drawn, Finish() hides the unused ones
function R.Pool(parent, file, layer)
	local pool = { n = 0, list = {} }
	function pool:Begin() self.n = 0 end
	function pool:Get()
		self.n = self.n + 1
		local t = self.list[self.n]
		if not t then
			t = parent:CreateTexture(nil, layer or "ARTWORK")
			t:SetTexture(file)
			self.list[self.n] = t
		end
		t:ClearAllPoints()
		t:Show()
		return t
	end
	function pool:Finish()
		for i = self.n + 1, #self.list do self.list[i]:Hide() end
	end
	return pool
end

-------------------------------------------------------------------------------- ordering

-- Total cost of visiting `order` from (sx, sy): walking distance plus each stop's stay. With a distance table `d`
-- (Distances), its legs instead of straight lines.
local function Cost(stops, order, sx, sy, d)
	local total, x, y, prev = 0, sx, sy, 0
	for _, i in ipairs(order) do
		local s = stops[i]
		total = total + (d and d[prev][i] or R.Distance(x, y, s.x, s.y)) + (s.stay or 0)
		x, y, prev = s.x, s.y, i
	end
	return total
end
R.Cost = Cost

local NONE = {}

-- Whether every stop comes after the stops in its `after` list (those not in the order don't count). Its table of
-- places is reused: ordering checks thousands of orders.
local at = {}
local function Valid(stops, order)
	for p, i in ipairs(order) do at[i] = p end
	local valid = true
	for p, i in ipairs(order) do
		for _, before in ipairs(valid and stops[i].after or NONE) do
			valid = valid and not (at[before] and at[before] > p)
		end
	end
	for _, i in ipairs(order) do at[i] = nil end
	return valid
end
R.Valid = Valid

local function Greedy(stops, sx, sy, d)
	local placed, order = {}, {}
	local x, y, prev = sx, sy, 0
	for _ = 1, #stops do
		local best, bestCost
		for i, s in ipairs(stops) do
			local ready = not placed[i]
			for _, before in ipairs(ready and s.after or NONE) do
				ready = ready and (placed[before] or not stops[before])
			end
			if ready then
				local c = (d and d[prev][i] or R.Distance(x, y, s.x, s.y)) + (s.stay or 0)
				if not bestCost or c < bestCost then best, bestCost = i, c end
			end
		end
		-- a cycle in the `after` rules leaves nothing ready: take the rest in their own order
		if not best then
			for i = 1, #stops do
				if not best and not placed[i] then best = i end
			end
		end
		placed[best] = true
		order[#order + 1] = best
		x, y, prev = stops[best].x, stops[best].y, best
	end
	return order
end

local function CopyInto(out, t)
	for i = 1, #t do out[i] = t[i] end
	for i = #t + 1, #out do out[i] = nil end
	return out
end

-- Distances between the stops and from the start (index 0), worked out once per ordering: the improvement passes
-- try thousands of orders and each only changes a few legs. `dist(a, b)`, when given, is the leg from stop a (0 for
-- the start) to stop b, else the straight line.
local function Distances(stops, sx, sy, dist)
	local d = {}
	for a = 0, #stops do
		local ax, ay = a == 0 and sx or stops[a].x, a == 0 and sy or stops[a].y
		local row = {}
		for b = 1, #stops do
			row[b] = dist and dist(a, b) or R.Distance(ax, ay, stops[b].x, stops[b].y)
		end
		d[a] = row
	end
	return d
end

-- A try that saves less than this isn't taken; one whose quick reckoning comes within SLACK of it is checked in full
-- (the quick sum can differ from the full one in the last digits)
local SAVING, SLACK = 0.01, 1e-6

-- One pass of improvements: move one stop elsewhere, then reverse a stretch (2-opt), keeping the rules.
-- Returns the better order and whether it changed. Each try is priced by the legs it changes, from the distance
-- table `d`; only a try that looks cheaper is built, priced in full and checked against the rules, so the choices
-- are those of pricing every try in full. Tries are built in `spare`, which swaps with the best order when taken, so
-- a pass makes no tables; returns the spare after.
local function Improve(stops, order, sx, sy, d, spare)
	local best, bestCost = order, Cost(stops, order, sx, sy, d)
	local changed = false
	local n = #order
	for i = 1, n do
		for j = 1, n do
			if i ~= j then
				-- take the stop at i out, then put it back so it ends up at j
				local o = best
				local v, before, after = o[i], o[i - 1] or 0, o[i + 1]
				local delta = -d[before][v] - (after and d[v][after] or 0) + (after and d[before][after] or 0)
				-- the neighbors at j in the order with v taken out
				local pj = j - 1
				local a = pj >= 1 and (pj < i and o[pj] or o[pj + 1]) or 0
				local b = j < n and (j < i and o[j] or o[j + 1]) or nil
				delta = delta + d[a][v] + (b and d[v][b] or 0) - (b and d[a][b] or 0)
				if delta < -SAVING + SLACK then
					local cand = CopyInto(spare, best)
					table.insert(cand, j, table.remove(cand, i))
					local c = Cost(stops, cand, sx, sy, d)
					if c < bestCost - SAVING and Valid(stops, cand) then
						spare, best, bestCost, changed = best, cand, c, true
					end
				end
			end
		end
	end
	for i = 1, n - 1 do
		for j = i + 1, n do
			local o = best
			local p, q = o[i - 1] or 0, o[j + 1]
			local delta = d[p][o[j]] - d[p][o[i]] + (q and d[o[i]][q] - d[o[j]][q] or 0)
			if delta < -SAVING + SLACK then
				local cand = CopyInto(spare, best)
				for k = 0, (j - i - 1) / 2 do
					cand[i + k], cand[j - k] = cand[j - k], cand[i + k]
				end
				local c = Cost(stops, cand, sx, sy, d)
				if c < bestCost - SAVING and Valid(stops, cand) then
					spare, best, bestCost, changed = best, cand, c, true
				end
			end
		end
	end
	return best, changed, spare
end

-- The order to visit stops in, as a list of their indexes, starting from (sx, sy). A stop is { x, y, stay =
-- extra cost of being there (same units as distance), after = { indexes of stops that must come first } }.
-- The route is open: it ends at its last stop. passes limits the improvement rounds (default 4). dist(a, b), when
-- given, prices the leg from stop a (0 for the start) to stop b in place of the straight line: the way around a
-- cliff, say. It's asked once per pair.
function R.Order(stops, sx, sy, passes, dist)
	local d = Distances(stops, sx, sy, dist)
	local order = Greedy(stops, sx, sy, d)
	local changed, spare = true, {}
	local round = 0
	while changed and round < (passes or 4) do
		order, changed, spare = Improve(stops, order, sx, sy, d, spare)
		round = round + 1
	end
	return order
end

-------------------------------------------------------------------------------- minimap

-- Minimap diameter in yards per zoom level, indoors and outdoors
R.MINIMAP_INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }
R.MINIMAP_OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 }

-- The client doesn't say whether the minimap uses its indoor or outdoor zoom: change the other zoom setting for
-- a moment and see which one the minimap follows.
local indoors, checking = false, false
function R.CheckIndoors()
	if not checking and Minimap then
		checking = true
		local zoom = Minimap:GetZoom()
		if GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") then
			Minimap:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
		end
		indoors = tonumber(GetCVar("minimapZoom")) ~= Minimap:GetZoom()
		Minimap:SetZoom(zoom)
		checking = false
	end
	return indoors
end

if CreateFrame and Minimap then
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("MINIMAP_UPDATE_ZOOM")
	watcher:RegisterEvent("ZONE_CHANGED_INDOORS")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", R.CheckIndoors)
end

-- How the minimap shows the world right now: pixels per yard, radius in pixels, whether it's square, and the
-- rotation (cos, sin) when it turns with the player
function R.MinimapView(frame, facing)
	local width = frame:GetWidth()
	local diameter = (indoors and R.MINIMAP_INDOOR or R.MINIMAP_OUTDOOR)[Minimap:GetZoom()] or 300
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE" or false
	local c, s = 1, 0
	if GetCVar("rotateMinimap") == "1" then c, s = cos(facing or 0), sin(facing or 0) end
	return width / diameter, width / 2, square, c, s
end

-- World point -> pixels from the minimap's center (x right, y up)
function R.MinimapScreen(px, py, x, y, scale, c, s)
	local east, north = py - y, x - px
	return (east * c + north * s) * scale, (north * c - east * s) * scale
end

function R.MinimapInside(sx, sy, radius, margin, square)
	local r = radius - margin
	return (square and abs(sx) <= r and abs(sy) <= r) or (not square and sx * sx + sy * sy <= r * r)
end

-- Pins a point that's off the minimap to its edge
function R.MinimapEdge(sx, sy, radius, margin, square)
	local k = square and (radius - margin) / max(abs(sx), abs(sy)) or (radius - margin) / sqrt(sx * sx + sy * sy)
	return sx * k, sy * k
end

-- Gold dots along a path (world points) on the minimap. path:Draw(px, py, facing, pts, n, whole), path:Clear().
-- A path is drawn from its start for as far as the minimap reaches, as a way from the player; `whole` draws every
-- part of it the minimap shows, for a path that doesn't start at the player (a creature's patrol).
function R.NewMinimapPath(color)
	local frame = CreateFrame("Frame", nil, Minimap)
	frame:SetAllPoints(Minimap)
	frame:SetFrameLevel(Minimap:GetFrameLevel() + 4)
	local dots = R.Pool(frame, R.MEDIA .. "Dot", "ARTWORK")
	local col = color or { 1, 0.82, 0.1 }
	local path = { frame = frame }
	-- Draw can run every frame: the dot callback is made once and reads the view from these, so it makes no garbage
	local vx, vy, vscale, vradius, vsquare, vc, vs
	local function mark(x, y)
		local sx, sy = R.MinimapScreen(vx, vy, x, y, vscale, vc, vs)
		if R.MinimapInside(sx, sy, vradius, 3, vsquare) then
			local t = dots:Get()
			t:SetSize(5, 5)
			t:SetVertexColor(col[1], col[2], col[3], 1)
			t:SetPoint("CENTER", frame, "CENTER", sx, sy)
		end
	end
	function path:Draw(px, py, facing, pts, n, whole)
		vscale, vradius, vsquare, vc, vs = R.MinimapView(frame, facing)
		vx, vy = px, py
		dots:Begin()
		R.Sample(pts, n, 7 / vscale, whole and math.huge or 2 * vradius / vscale, mark)
		dots:Finish()
	end
	function path:Clear()
		dots:Begin()
		dots:Finish()
	end
	return path
end

-------------------------------------------------------------------------------- world map

-- How a map path's dots look: the leg being walked bright in `color`, the legs after it small and faint, further
-- apart, so a route that doubles back still reads (InstanceGPS's look)
R.LEG_DOT, R.LATER_DOT, R.LATER_SPACING = 8, 5, 1.6
R.LATER_COLOR = { 0.85, 0.85, 0.85, 0.45 }

-- Dots along a path of 0..1 map points on a map frame (WorldMapButton): path:Draw(pts, n, active), path:Clear().
-- The first `active` coordinates (the leg being walked: 4 for the player and the next stop) are drawn bright, the
-- rest faint; without `active` the whole path is bright. Dots are `spacing` pixels apart at a 1002px wide map.
-- A path with gaps (other map levels, teleports) is drawn in pieces: path:Begin(), path:Add(pts, n, active) for
-- each piece, path:Finish(). path:Dot(x, y) between them places one more dot (frame pixels from the top left) for
-- the caller to size and color.
function R.NewMapPath(parent, color, spacing)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 4)
	local dots = R.Pool(frame, R.MEDIA .. "Dot", "ARTWORK")
	local col = color or { 1, 0.82, 0.1 }
	local path = { frame = frame }
	local leg, later = {}, {}
	local size, c
	local function mark(x, y)
		local t = dots:Get()
		t:SetSize(size, size)
		t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		t:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
	end
	function path:Begin()
		dots:Begin()
	end
	function path:Add(pts, n, active)
		local w, h = parent:GetWidth(), parent:GetHeight()
		local gap = (spacing or 9) * w / 1002
		local split = math.min(active or n, n)
		local nLater = 0
		for i = 1, n, 2 do
			local x, y = pts[i] * w, pts[i + 1] * h
			if i < split then
				leg[i], leg[i + 1] = x, y
			end
			if i >= split - 1 then
				later[nLater + 1], later[nLater + 2] = x, y
				nLater = nLater + 2
			end
		end
		size, c = R.LEG_DOT, col
		R.Sample(leg, split, gap, math.huge, mark)
		size, c = R.LATER_DOT, R.LATER_COLOR
		R.Sample(later, nLater, gap * R.LATER_SPACING, math.huge, mark)
	end
	function path:Dot(x, y)
		local t = dots:Get()
		t:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
		return t
	end
	function path:Finish()
		dots:Finish()
	end
	function path:Draw(pts, n, active)
		self:Begin()
		self:Add(pts, n, active)
		self:Finish()
	end
	function path:Clear()
		dots:Begin()
		dots:Finish()
	end
	return path
end

-- How a numbered stop ring looks in each state: size in pixels and color (InstanceGPS's look)
R.STOP_LOOK = {
	next = { 26, 1, 0.82, 0 },     -- where the route goes next
	stop = { 20, 1, 0.25, 0.2 },   -- later stops on the route
	other = { 16, 0.6, 0.6, 0.6 }, -- off the route, unnumbered
	done = { 18, 0.3, 0.9, 0.3 },  -- done, with a check in place of its number
}

-- Numbered stop rings on a map frame: stops:Begin(), stops:Add(x, y, state, text) for each (x, y in the frame's
-- pixels from its top left, state a key of R.STOP_LOOK), stops:Finish() hides the rest. Add returns the ring, a
-- button the caller can keep its own fields on. opts: onEnter(ring), onLeave(ring), onClick(ring, button).
function R.NewMapStops(parent, opts)
	opts = opts or {}
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 5)
	local rings, used = {}, 0
	local stops = { frame = frame, rings = rings }
	local function Ring(i)
		local p = rings[i]
		if not p then
			p = CreateFrame("Button", nil, frame)
			p:SetFrameLevel(frame:GetFrameLevel() + 2)
			p.ring = p:CreateTexture(nil, "ARTWORK")
			p.ring:SetAllPoints()
			p.ring:SetTexture(R.MEDIA .. "Ring")
			p.num = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			p.num:SetPoint("CENTER")
			p.check = p:CreateTexture(nil, "OVERLAY")
			p.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
			p.check:SetSize(14, 14)
			p.check:SetPoint("CENTER")
			p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			p:SetScript("OnEnter", function(self) if opts.onEnter then opts.onEnter(self) end end)
			p:SetScript("OnLeave", function(self) if opts.onLeave then opts.onLeave(self) end end)
			p:SetScript("OnClick", function(self, button) if opts.onClick then opts.onClick(self, button) end end)
			rings[i] = p
		end
		return p
	end
	function stops:Begin() used = 0 end
	function stops:Add(x, y, state, text)
		used = used + 1
		local p = Ring(used)
		local look = R.STOP_LOOK[state] or R.STOP_LOOK.stop
		p.state = state
		p:SetSize(look[1], look[1])
		p.ring:SetVertexColor(look[2], look[3], look[4])
		p.num:SetText(text or "")
		if state == "done" then
			p.check:Show()
			p.num:Hide()
		else
			p.check:Hide()
			p.num:Show()
		end
		p:ClearAllPoints()
		p:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
		p:Show()
		return p
	end
	function stops:Finish()
		for i = used + 1, #rings do rings[i]:Hide() end
	end
	function stops:Clear()
		self:Begin()
		self:Finish()
	end
	return stops
end

-------------------------------------------------------------------------------- arrow

-- How fast (radians a second) and how high (pixels) the arrow bobs in arrow:Here()
R.BOB_SPEED, R.BOB_HEIGHT = 4, 10

-- A movable arrow with a title and two lines under it. opts: name (global frame name), onClick(arrow) on
-- left-click (not after a drag), onMenu(arrow) on right-click, onTooltip(tooltip) to fill its tooltip,
-- position = saved { point, relPoint, x, y } or nil, onMoved(position).
-- arrow:Point(px, py, facing, x, y, arrived) turns it toward a world point; arrow:Here() points it down and bobs it,
-- for a step done where the player stands (call it every frame); arrow:Idle() greys it out;
-- arrow:SetText(title, sub, hint).
function R.NewArrow(opts)
	local arrow = CreateFrame("Button", opts.name, UIParent)
	arrow:SetSize(56, 56)
	arrow:SetFrameStrata("MEDIUM")
	arrow:SetMovable(true)
	arrow:EnableMouse(true)
	arrow:RegisterForDrag("LeftButton")
	arrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	arrow:SetClampedToScreen(true)
	arrow:Hide()

	local tex = arrow:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints()
	tex:SetTexture(R.MEDIA .. "Arrow")
	local title = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
	local sub = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -1)
	local hint = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOP", sub, "BOTTOM", 0, -1)
	hint:SetWidth(260)
	hint:SetTextColor(1, 0.6, 0.2)
	arrow.tex, arrow.title, arrow.sub, arrow.hint = tex, title, sub, hint

	local p = opts.position
	if p then
		arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		-- bottom center, high enough that the labels under the arrow clear the action bars
		arrow:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 310)
	end

	local dragged = false
	arrow:SetScript("OnDragStart", function(self)
		dragged = true
		if not (opts.locked and opts.locked()) then self:StartMoving() end
	end)
	arrow:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		if opts.onMoved then opts.onMoved({ point, relPoint, x, y }) end
	end)
	arrow:SetScript("OnClick", function(self, button)
		if button == "RightButton" and opts.onMenu then
			opts.onMenu(self)
		elseif button == "LeftButton" and not dragged and opts.onClick then
			opts.onClick(self)
		end
		dragged = false
	end)
	arrow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		if opts.onTooltip then opts.onTooltip(GameTooltip) end
		GameTooltip:Show()
	end)
	arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local bobbing = false
	local function Settle()
		if bobbing then
			bobbing = false
			tex:ClearAllPoints()
			tex:SetAllPoints()
		end
	end
	function arrow:Point(px, py, facing, x, y, arrived)
		Settle()
		local rel, dist = R.Turn(px, py, facing, x, y)
		R.SetRotation(tex, rel)
		tex:SetVertexColor(R.ArrowColor(rel, arrived))
		return dist
	end
	function arrow:Here()
		bobbing = true
		R.SetRotation(tex, pi)
		tex:SetVertexColor(0.3, 1, 0.3)
		local dy = abs(sin(GetTime() * R.BOB_SPEED)) * R.BOB_HEIGHT
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", arrow, "TOPLEFT", 0, dy)
		tex:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 0, dy)
	end
	function arrow:Idle()
		Settle()
		R.SetRotation(tex, 0)
		tex:SetVertexColor(0.5, 0.5, 0.5)
	end
	function arrow:SetText(t, s, h)
		title:SetText(t or "")
		sub:SetText(s or "")
		hint:SetText(h or "")
	end
	return arrow
end

-- A button beside an arrow that uses an item or casts a spell (a quest item to use there, a profession to open).
-- Using either is protected, so it's a secure button on UIParent, laid over the spot right of the arrow at the
-- arrow's scale, strata and own frame level (one level up shows through a windowed world map covering the arrow),
-- and changed only out of combat: during a fight it stays as it was. It goes when the arrow hides, once out of
-- combat. button:Set(kind, value), with kind "item" (value an item ID) or "spell" (a spell name), or nil to hide;
-- call it every frame: it changes nothing, and makes no garbage, while what it shows and where stay the same.
-- opts.tooltip(tip, kind, value) fills its tooltip (default: the item's, or "Open <spell>").
function R.NewArrowButton(arrow, name, opts)
	opts = opts or {}
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:SetSize(30, 30)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	b.icon, b.count, b.cooldown = icon, count, cooldown
	b:Hide()

	local kind, value, placedX, placedY, placedLevel, shownCount

	local function ShowCooldown()
		local start, duration, enable = 0, 0, 0
		if kind == "item" then
			start, duration, enable = GetItemCooldown(value)
		elseif kind == "spell" then
			start, duration, enable = GetSpellCooldown(value)
		end
		CooldownFrame_SetTimer(cooldown, start or 0, duration or 0, enable or 0)
	end
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if opts.tooltip then
			opts.tooltip(GameTooltip, kind, value)
		elseif kind == "item" then
			GameTooltip:SetHyperlink("item:" .. value)
		else
			GameTooltip:AddLine("Open " .. tostring(value))
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	function b:Set(newKind, newValue)
		local shown = newKind ~= nil and newValue ~= nil
		local x, y, level = arrow:GetRight(), select(2, arrow:GetCenter()), arrow:GetFrameLevel()
		local moved = shown and (x ~= placedX or y ~= placedY or level ~= placedLevel)
		if not InCombatLockdown() and (newKind ~= kind or newValue ~= value or moved) then
			kind, value = shown and newKind or nil, shown and newValue or nil
			placedX, placedY, placedLevel, shownCount = x, y, level, nil
			if shown and x then
				b:SetAttribute("type", kind)
				b:SetAttribute("item", kind == "item" and ("item:" .. value) or nil)
				b:SetAttribute("spell", kind == "spell" and value or nil)
				local tex = kind == "item" and GetItemIcon(value) or (kind == "spell" and select(3, GetSpellInfo(value)))
				icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
				-- at the arrow's scale, so the arrow's own coordinates place it
				b:SetScale(arrow:GetEffectiveScale() / UIParent:GetEffectiveScale())
				b:ClearAllPoints()
				b:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x + 6, y)
				b:SetFrameStrata(arrow:GetFrameStrata())
				b:SetFrameLevel(level)
				b:Show()
			else
				kind, value = nil, nil
				b:Hide()
			end
			ShowCooldown()
		end
		if kind == "item" and kind == newKind and value == newValue then
			local n = GetItemCount(value) or 0
			if n ~= shownCount then
				shownCount = n
				count:SetText(n > 1 and n or "")
			end
		end
	end

	-- a hidden arrow takes its button with it, once out of combat
	arrow:HookScript("OnHide", function() b:Set(nil) end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("BAG_UPDATE_COOLDOWN")
	events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" and not arrow:IsVisible() then
			b:Set(nil)
		elseif event ~= "PLAYER_REGEN_ENABLED" and kind then
			ShowCooldown()
		end
	end)
	return b
end

-- "42 yd", "1.5k yd"
function R.FormatDistance(d)
	return d and (d >= 1000 and ("%.1fk yd"):format(d / 1000) or ("%d yd"):format(d)) or ""
end
