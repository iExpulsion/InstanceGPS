-- Switching InstanceGPS off in an instance (and back on), and the Instances options page.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
MOCK.Fire("PLAYER_ENTERING_WORLD")
local MAP = 36   -- Deadmines
local inst = NS.Instances[MAP]
MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
local p = inst.routes[1].path
local lv = DN.FirstFloor(p[3]) or 0
MOCK.level = lv
MOCK.mx, MOCK.my = DN:WorldToMap(inst, lv, p[1], p[2])
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
MOCK.Tick(0.3)
print("on at first:", DN.inst == inst)
local b = inst.bosses[inst.routes[1].order[1]]
DN:MarkKilled(b, "death")

SlashCmdList.INSTANCEGPS("off")
MOCK.Tick(0.3)
print("off:", DN.inst == nil and DN.offHere == inst, "tracker hidden:", not DN.tracker.shown, "arrow hidden:", not DN.arrow.shown)
MOCK.Fire("ZONE_CHANGED_NEW_AREA")
print("stays off:", DN.inst == nil and DN.offHere == inst)

SlashCmdList.INSTANCEGPS("on")
MOCK.Tick(0.3)
print("back on:", DN.inst == inst, "kill kept:", DN:IsKilled(b))

-- the options page lists every instance, ticked unless it's off
DN:SetOff(MAP, true)
InstanceGPSInstances.scripts.OnShow(InstanceGPSInstances)
local n, count = 0, 0
for _ in pairs(NS.Instances) do count = count + 1 end
local cb36
for k, v in pairs(_G) do
	if type(k) == "string" and k:match("^InstanceGPSInst_%d+$") then
		n = n + 1
		if k == "InstanceGPSInst_36" then cb36 = v end
	end
end
print("listed:", n == count, "off unticked:", cb36 and not cb36:GetChecked())
cb36:SetChecked(true)
cb36.scripts.OnClick(cb36)
print("ticked back on:", DN.inst == inst)
print("instances test done")
