-- InstanceGPS overrides: a server's changes to the AzerothCore data, applied before anything is
-- indexed. Any addon can call InstanceGPS:Override (docs/MODULES.md has the format):
--
--   InstanceGPS:Override("My Server", {
--     [409] = false,                                         -- an instance the server doesn't have
--     [229] = {
--       bosses = {
--         ["Urok Doomhowl"] = false,                         -- a boss it doesn't have
--         ["Warchief Rend Blackhand"] = { npcs = { 10429, 990001 } },        -- changed kill credit
--         ["Custom Boss"] = { npcs = { 990002 }, x = 120.5, y = -310.2, f = 2, after = "Gizrul the Slavener" },
--       },
--       hints = { { x = 102.4, y = -319.2, f = 2, text = "..." } },
--       removeHints = { "Kill every Blackhand" },             -- base hints starting with this
--       paths = { ["The Beast"] = { from = "Warchief Rend Blackhand", points = { x, y, f, ... } } },
--     },
--   })
--
-- Positions are world x, y and the dungeon map level f. A boss moved or added without a recorded
-- path gets a rough route: along the existing one to its nearest point, then straight there.
-- tools/build.py --module reads the same file and adds properly worked-out routes ("built").
local _, ns = ...
local DN = ns.DN

local sqrt, huge = math.sqrt, math.huge
local DATA_FORMAT = 1        -- of the "built" instance tables; tools/overlay.py writes the same
local MOVED = 3              -- yards: a boss this close to its old spot hasn't moved
local OFF_FLOOR = 25         -- yards of penalty for a route point on another level
local PATH_JOIN = 40         -- yards: a recorded path must start this close to its "from" stop

DN.overrides = {}

function DN:Override(name, data)
	if type(name) ~= "string" or type(data) ~= "table" then
		error('usage: InstanceGPS:Override("Server name", { [mapId] = {...} })', 2)
	end
	local entry
	for _, o in ipairs(self.overrides) do
		if o.name == name then entry = o end
	end
	if not entry then
		entry = { name = name, data = {} }
		table.insert(self.overrides, entry)
	end
	-- a module can split its data over several files (its built routes and its edits)
	for mapId, t in pairs(data) do
		if t == false then
			entry.data[mapId] = false
		elseif type(t) == "table" then
			local cur = entry.data[mapId]
			if type(cur) ~= "table" then
				cur = {}
				entry.data[mapId] = cur
			end
			for k, v in pairs(t) do cur[k] = v end
		end
	end
end

-- "InstanceGPS 1.0.1", plus the server modules in use: "InstanceGPS 1.0.1 + Synastria"
function DN:Title()
	local t = "InstanceGPS " .. self.version
	for _, o in ipairs(self.overrides) do t = t .. " + " .. o.name end
	return t
end

-------------------------------------------------------------------------------- route editing

local function dist(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return sqrt(dx * dx + dy * dy)
end

local function Mask(level)
	return level and 2 ^ level or nil
end

-- A route as a list of points, each carrying what happens there (boss stops, a teleport to the
-- next point, a hint), so points can be added and removed without stale indices.
local function ToPoints(route)
	local pts, p = {}, route.path
	for i = 1, #p / 3 do
		pts[i] = { x = p[i * 3 - 2], y = p[i * 3 - 1], f = p[i * 3] }
	end
	for k, bi in ipairs(route.order) do
		local v = pts[route.stops[k]]
		if v then
			v.stops = v.stops or {}
			table.insert(v.stops, bi)
		end
	end
	for _, i in ipairs(route.tele or {}) do
		if pts[i] then pts[i].tele = true end
	end
	for i, t in pairs(route.teleText or {}) do
		if pts[i] then pts[i].teleText = t end
	end
	for i, t in pairs(route.hints or {}) do
		if pts[i] then pts[i].hint = t end
	end
	return pts
end

local function FromPoints(route, pts, remap)
	-- nothing after the last stop
	local last = 0
	for i, v in ipairs(pts) do
		if v.stops and #v.stops > 0 then last = i end
	end
	local path, order, stops, tele, teleText, hints, length = {}, {}, {}, {}, {}, {}, 0
	for i = 1, last do
		local v = pts[i]
		path[#path + 1], path[#path + 2], path[#path + 3] = v.x, v.y, v.f
		for _, bi in ipairs(v.stops or {}) do
			local nb = remap[bi]
			if nb then
				order[#order + 1], stops[#stops + 1] = nb, i
			end
		end
		if v.tele and i < last then tele[#tele + 1] = i end
		if v.teleText then teleText[i] = v.teleText end
		if v.hint then hints[i] = v.hint end
		if i > 1 and not pts[i - 1].tele then length = length + dist(pts[i - 1].x, pts[i - 1].y, v.x, v.y) end
	end
	route.path, route.order, route.stops, route.tele = path, order, stops, tele
	route.teleText, route.hints, route.length = teleText, hints, math.floor(length + 0.5)
end

local function StopIndex(pts, bi)
	for i, v in ipairs(pts) do
		for _, s in ipairs(v.stops or {}) do
			if s == bi then return i end
		end
	end
end

-- the stop points before and after point i: the stretch a boss there can move within
local function Neighbours(pts, i)
	local lo, hi = 1, #pts
	for k = i - 1, 1, -1 do
		if pts[k].stops and #pts[k].stops > 0 then lo = k break end
	end
	for k = i + 1, #pts do
		if pts[k].stops and #pts[k].stops > 0 then hi = k break end
	end
	return lo, hi
end

local function RemoveStop(pts, bi)
	for _, v in ipairs(pts) do
		for k = #(v.stops or {}), 1, -1 do
			if v.stops[k] == bi then table.remove(v.stops, k) end
		end
	end
end

-- Rough route to a boss: from the nearest point of pts[lo..hi], straight out to the boss and back.
local function InsertSpur(pts, bi, b, lo, hi)
	local level = DN.FirstFloor(b.f)
	local best, m = huge, nil
	for i = lo, hi do
		local v = pts[i]
		local d = dist(v.x, v.y, b.x, b.y)
		if level and not DN.OnFloor(v.f, level) then d = d + OFF_FLOOR end
		if d < best then best, m = d, i end
	end
	if not m then return end
	local at = pts[m]
	local stop = { x = b.x, y = b.y, f = b.f or at.f, stops = { bi } }
	if m == #pts then
		table.insert(pts, stop)
		return
	end
	-- the way back to the route takes over whatever started at the point (a teleport)
	local back = { x = at.x, y = at.y, f = at.f, tele = at.tele, teleText = at.teleText }
	at.tele, at.teleText = nil, nil
	table.insert(pts, m + 1, stop)
	table.insert(pts, m + 2, back)
end

-- A recorded path to boss bi from the stop of `from` (or the route start): replaces that stretch.
local function ReplaceLeg(pts, bi, from, rec, byName)
	local sB = StopIndex(pts, bi)
	if not sB then return false end
	local sF = 1
	if from then
		sF = byName[from] and StopIndex(pts, byName[from])
		if not sF or sF >= sB then return false end
	end
	local p = rec.points
	if not p or #p < 6 or dist(p[1], p[2], pts[sF].x, pts[sF].y) > PATH_JOIN then return false end
	local teleAt = {}
	for _, i in ipairs(rec.tele or {}) do teleAt[i] = true end
	local new = {}
	for i = 2, #p / 3 do
		new[#new + 1] = { x = p[i * 3 - 2], y = p[i * 3 - 1], f = Mask(p[i * 3]), tele = teleAt[i] }
	end
	if teleAt[1] then pts[sF].tele = true end
	new[#new].stops = pts[sB].stops
	-- hints on the old stretch move to the nearest recorded point
	for i = sF + 1, sB do
		local h = pts[i].hint
		if h then
			local best, at = 15, nil
			for _, v in ipairs(new) do
				local d = dist(v.x, v.y, pts[i].x, pts[i].y)
				if d < best and not v.hint then best, at = d, v end
			end
			if at then at.hint = h end
		end
	end
	for _ = sF + 1, sB do table.remove(pts, sF + 1) end
	for k, v in ipairs(new) do table.insert(pts, sF + k, v) end
	return true
end

-------------------------------------------------------------------------------- applying

local BOSS_FIELDS = { "name", "npcs", "spell", "yells", "noDeath", "friendly", "all", "r", "diff", "stats", "statDiv" }

local function ApplyInstance(inst, t)
	local byName = {}
	for i, b in ipairs(inst.bosses) do byName[b.name] = i end
	local routes = {}
	for r, route in ipairs(inst.routes) do routes[r] = ToPoints(route) end
	local removed, moved, added = {}, {}, {}
	for name, v in pairs(t.bosses or {}) do
		local bi = byName[name]
		if v == false then
			if bi then removed[bi] = true end
		elseif type(v) == "table" then
			if bi then
				local b = inst.bosses[bi]
				for _, k in ipairs(BOSS_FIELDS) do
					if v[k] ~= nil then b[k] = v[k] end
				end
				if v.x and v.y and (not b.x or dist(b.x, b.y, v.x, v.y) > MOVED) then
					b.x, b.y, b.z, b.f = v.x, v.y, v.z, Mask(v.f) or b.f
					b.hx, b.hy, b.hz, b.hf = nil, nil, nil, nil
					moved[bi] = true
				end
			elseif v.x and v.y and v.npcs and #v.npcs > 0 then
				local b = { name = name, id = v.id or 100000 + v.npcs[1], diff = v.diff or 255, npcs = v.npcs,
				            x = v.x, y = v.y, z = v.z, f = Mask(v.f) }
				for _, k in ipairs(BOSS_FIELDS) do
					if v[k] ~= nil and b[k] == nil then b[k] = v[k] end
				end
				table.insert(inst.bosses, b)
				bi = #inst.bosses
				byName[name] = bi
				added[bi] = v.after or true
			end
		end
	end
	for _, pts in ipairs(routes) do
		for bi in pairs(moved) do
			local s = StopIndex(pts, bi)
			if s then
				local lo, hi = Neighbours(pts, s)
				RemoveStop(pts, bi)
				InsertSpur(pts, bi, inst.bosses[bi], lo, hi)
			end
		end
	end
	for bi, after in pairs(added) do
		if after ~= true then
			-- into every route that has the boss it comes after, on the stretch to the next stop
			for _, pts in ipairs(routes) do
				local s = byName[after] and StopIndex(pts, byName[after])
				if s then
					local _, hi = Neighbours(pts, s)
					InsertSpur(pts, bi, inst.bosses[bi], s, hi)
				end
			end
		else
			-- into the route that passes closest
			local best, pick = huge, nil
			local b = inst.bosses[bi]
			for r, pts in ipairs(routes) do
				for _, v in ipairs(pts) do
					local d = dist(v.x, v.y, b.x, b.y)
					if d < best then best, pick = d, r end
				end
			end
			if pick then InsertSpur(routes[pick], bi, b, 1, #routes[pick]) end
		end
	end
	for name, rec in pairs(t.paths or {}) do
		local bi = byName[name]
		if bi and type(rec) == "table" then
			for _, pts in ipairs(routes) do ReplaceLeg(pts, bi, rec.from, rec, byName) end
		end
	end
	if t.removeHints then
		local function gone(text)
			for _, start in ipairs(t.removeHints) do
				if text:sub(1, #start) == start then return true end
			end
		end
		for _, pts in ipairs(routes) do
			for _, v in ipairs(pts) do
				if v.hint and gone(v.hint) then v.hint = nil end
			end
		end
		for k = #(inst.extraHints or {}), 1, -1 do
			if gone(inst.extraHints[k].text) then table.remove(inst.extraHints, k) end
		end
	end
	for _, h in ipairs(t.hints or {}) do
		if h.x and h.y and h.text then
			inst.extraHints = inst.extraHints or {}
			local dup = false
			for _, e in ipairs(inst.extraHints) do
				if e.text == h.text and dist(e.x, e.y, h.x, h.y) < 1 then dup = true end
			end
			if not dup then table.insert(inst.extraHints, { x = h.x, y = h.y, f = Mask(h.f), text = h.text }) end
		end
	end
	-- drop removed bosses, renumber the rest, and rewrite the routes
	local remap, bosses = {}, {}
	for bi, b in ipairs(inst.bosses) do
		if not removed[bi] then
			bosses[#bosses + 1] = b
			remap[bi] = #bosses
		end
	end
	inst.bosses = bosses
	local keep = {}
	for r, route in ipairs(inst.routes) do
		FromPoints(route, routes[r], remap)
		if #route.order > 0 then keep[#keep + 1] = route end
	end
	inst.routes = keep
end

function DN:ApplyOverrides(instances)
	for _, o in ipairs(self.overrides) do
		for mapId, t in pairs(o.data) do
			if t == false then
				instances[mapId] = nil
			else
				if t.built then
					if t.built.format == DATA_FORMAT then
						instances[mapId] = t.built
					else
						self:Print("%s's routes don't match this version of InstanceGPS; update both to the same release.", o.name)
					end
				end
				local inst = instances[mapId]
				if inst then
					local ok, err = pcall(ApplyInstance, inst, t)
					if not ok then self:Print("%s: couldn't apply the changes to %s (%s).", o.name, inst.name, tostring(err)) end
				end
			end
		end
	end
end
