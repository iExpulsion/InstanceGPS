-- Overrides (Override.lua): removed instances and bosses, renames, custom and moved bosses, hints.
-- Run with DN_MODULES=fixtures/override_brs.lua.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
MOCK.Fire("PLAYER_ENTERING_WORLD")

local inst = NS.Instances[229]
local function boss(name)
	for i, b in ipairs(inst.bosses) do if b.name == name then return b, i end end
end
print("title:", DN:Title())
print("instance removed:", NS.Instances[409] == nil)
print("boss removed:", boss("Urok Doomhowl") == nil)
print("boss renamed:", boss("Halycon") == nil and boss("Halycon the Wolf") ~= nil)

-- every route still hangs together: a stop per boss in order, at the boss, indices in range
local ok = true
local function fail(msg) ok = false print("FAIL", msg) end
for _, r in ipairs(inst.allRoutes) do
	local n = #r.path / 3
	if #r.stops ~= #r.order then fail(r.name .. " stops/order") end
	for k, s in ipairs(r.stops) do
		if s < 1 or s > n or (k > 1 and s < r.stops[k - 1]) then fail(r.name .. " stop " .. k) end
		local b = inst.bosses[r.order[k]]
		local o = (s - 1) * 3
		if not b then fail(r.name .. " order " .. k)
		elseif math.abs(r.path[o + 1] - b.x) > 30 or math.abs(r.path[o + 2] - b.y) > 30 then fail(r.name .. " stop far from " .. b.name) end
	end
	for _, i in ipairs(r.tele) do if i < 1 or i >= n then fail(r.name .. " tele " .. i) end end
	for i in pairs(r.hints) do if i < 1 or i > n then fail(r.name .. " hint " .. i) end end
end
print("routes consistent:", ok)

-- the custom boss comes right after Gizrul, with its stop at its own spot
local lower
for _, r in ipairs(inst.allRoutes) do if r.name == "Lower" then lower = r end end
local cb, ci = boss("Custom Boss")
local _, gi = boss("Gizrul the Slavener")
local after = false
for k, bi in ipairs(lower.order) do
	if bi == gi and lower.order[k + 1] == ci then
		local o = (lower.stops[k + 1] - 1) * 3
		after = lower.path[o + 1] == cb.x and lower.path[o + 2] == cb.y
	end
end
print("custom boss after Gizrul:", after, "npc detected:", cb.npcs[1] == 990002)

-- the moved boss's stop is at its new spot
local beast, bi = boss("The Beast")
local moved = false
for _, r in ipairs(inst.allRoutes) do
	for k, b in ipairs(r.order) do
		if b == bi then
			local o = (r.stops[k] - 1) * 3
			moved = r.path[o + 1] == 135 and r.path[o + 2] == -555
		end
	end
end
print("boss moved:", moved and beast.x == 135)

local removedHint = true
for _, r in ipairs(inst.allRoutes) do
	for _, t in pairs(r.hints) do if t:find("^Kill every Blackhand") then removedHint = false end end
end
print("hint removed:", removedHint)

-- the added hint shows on the arrow at its spot
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
MOCK.level = 2
MOCK.mx, MOCK.my = DN:WorldToMap(inst, 2, 103, -318)
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
DN:SetRoute(2, true)
for _, r in ipairs(inst.routes) do if r.name == "Upper" then DN:SetRoute(r.index, true) end end
MOCK.Tick(0.3)
local _, _, _, _, _, _, hint = DN:NextWaypoint()
print("hint shown:", hint == "Test hint")
print("overrides test done")
