-- Navigation off in an instance (and back on): the arrow and path views go, the boss tracker stays
-- unless offHidesTracker is set; and the Instances options page, by expansion.
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
print("on at first:", DN:NavOn(), "arrow shown:", DN.arrow.shown)
local b = inst.bosses[inst.routes[1].order[1]]

SlashCmdList.INSTANCEGPS("off")
MOCK.Tick(0.3)
print("nav off:", DN.inst == inst and not DN:NavOn(), "arrow hidden:", not DN.arrow.shown,
	"HUD hidden:", not InstanceGPSHUD.shown, "tracker kept:", DN.tracker.shown)
DN:MarkKilled(b, "death")
print("kills tracked while off:", DN:IsKilled(b))
DN.opt.offHidesTracker = true
DN:NavChanged()
print("tracker hidden by option:", not DN.tracker.shown)
DN.opt.offHidesTracker = false
DN:NavChanged()

SlashCmdList.INSTANCEGPS("on")
MOCK.Tick(0.3)
print("back on:", DN:NavOn(), "arrow back:", DN.arrow.shown, "kill kept:", DN:IsKilled(b))

-- every instance knows its expansion; the options page lists them all, ticked unless off
local noExp = 0
for _, i in pairs(NS.Instances) do if i.exp == nil then noExp = noExp + 1 end end
print("expansions known:", noExp == 0)
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
print("ticked back on:", DN:NavOn())
print("instances test done")
