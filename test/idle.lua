local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("pathView default:", DN.opt.pathView)
DN.opt.pathView = true
local inst = NS.Instances[389]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local p = inst.routes[1].path
MOCK.level = DN.FirstFloor(p[3]) or 0
MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, p[1], p[2])
MOCK.Fire("ZONE_CHANGED_NEW_AREA"); MOCK.Tick(0.2)
local function idleText()
	for _, f in ipairs(MOCK.all) do end
	return DN.wp.x
end
print("has waypoint before:", DN.wp.x ~= nil)
MOCK.now = MOCK.now + 754
for _, b in ipairs(inst.bosses) do DN:MarkKilled(b) end
MOCK.Tick(0.2); MOCK.Tick(0.05)
print("has waypoint after:", DN.wp.x ~= nil)
for _, fs in ipairs(MOCK.fonts[InstanceGPSPathView]) do
	if fs.shown and fs.text and fs.text ~= "" then print("view text:", (fs.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " / "))) end
end
local marks = 0
for _, t in ipairs(MOCK.created[InstanceGPSPathView]) do if t.shown and type(t.file) == "string" and t.file:find("Chevron") then marks = marks + 1 end end
print("marks shown:", marks, "HUD shown:", InstanceGPSHUD.shown)
