local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
print("default hardModes:", DN.opt.hardModes)
local inst = NS.Instances[615]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local p = inst.allRoutes and inst.allRoutes[1].path or inst.routes[1].path
MOCK.level = DN.FirstFloor(p[3]) or 0
MOCK.mx, MOCK.my = DN:WorldToMap(inst, MOCK.level, p[1], p[2])
MOCK.Fire("ZONE_CHANGED_NEW_AREA"); MOCK.Tick(0.2)
local function show(tag)
	local r = DN:ActiveRoute()
	local names = {}
	for _, bi in ipairs(r.order) do names[#names + 1] = inst.bosses[bi].name end
	print(tag, "routes:", #inst.routes, "active:", r.name or "normal", "order:", table.concat(names, " > "), "next:", DN:NextBoss().name)
end
show("normal")
-- toggle via the options-panel checkbox
InstanceGPSOpt_hardModes.GetChecked = function() return true end
InstanceGPSOpt_hardModes.scripts.OnClick(InstanceGPSOpt_hardModes)
MOCK.Tick(0.2)
show("hard  ")
-- drakes die during Sartharion: credited, route cleared after Sartharion
for _, b in ipairs(inst.bosses) do DN:MarkKilled(b) end
print("cleared:", DN.run.cleared ~= nil)
DN.opt.hardModes = false; DN:ApplyHardModes(); MOCK.Tick(0.2)
print("back to normal, routes:", #inst.routes, "active order length:", #DN:ActiveRoute().order)
-- ICC still faction-filtered, unaffected
print("ICC routes:", #NS.Instances[631].routes, "allRoutes:", #NS.Instances[631].allRoutes)
