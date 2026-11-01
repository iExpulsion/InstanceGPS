local DN = NS.DN
MOCK.now = 1000000
MOCK.faction = os.getenv("DN_FACTION") or "Alliance"
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
for _, id in ipairs({36, 189, 533, 649, 650}) do
	local inst = NS.Instances[id]
	MOCK.inInstance, MOCK.itype, MOCK.instName, MOCK.mapFile = true, inst.type, inst.name, inst.file
	local p = inst.routes[1].path
	local lv = DN.FirstFloor(p[3]) or 0
	MOCK.level = lv; MOCK.mx, MOCK.my = DN:WorldToMap(inst, lv, p[1], p[2])
	MOCK.Fire("ZONE_CHANGED_NEW_AREA")
	assert(DN.inst == inst, "detect " .. inst.name)
	MOCK.Tick(1.2)
	WorldMapFrame.shown = true
	DN:RefreshMap()
	WorldMapFrame.shown = false
	DN:ShowMenu()
	DN:SetNavTarget(inst.bosses[#inst.bosses]); MOCK.Tick(0.2)
	DN:SetNavTarget(inst.bosses[#inst.bosses])
	if #inst.routes > 1 then DN:SetRoute(2, true); MOCK.Tick(0.2) end
	print("ok", inst.name, DN.tracker.shown, DN.arrow.shown)
end
-- hovering a tracker row or the arrow hands its boss to BOSS_TOOLTIP listeners (server modules)
local hovered = {}
DN:On("BOSS_TOOLTIP", function(b, tip) hovered[#hovered + 1] = b.name .. (tip == GameTooltip and "" or " (wrong tooltip)") end)
local row
for _, fr in ipairs(MOCK.all) do
	if fr.boss and fr.scripts.OnEnter then row = row or fr end
end
row.scripts.OnEnter(row)
DN.arrow.scripts.OnEnter(DN.arrow)
print("boss tooltip fired:", #hovered == 2 and hovered[1] == row.boss.name and hovered[2] == (DN.wp.boss or DN:NextBoss()).name)

-- a module's row under the boss list: shown with its text, its own tooltip on hover, gone again on nil
local noteTip
DN:SetTrackerNote("test", { text = "Module Row", right = "7", tooltip = function(tip) noteTip = tip end })
local noteRow
for _, fr in ipairs(MOCK.all) do
	if fr.note and fr.shown then noteRow = fr end
end
if noteRow then noteRow.scripts.OnEnter(noteRow) end
DN:SetTrackerNote("test", nil)
print("tracker note:", noteRow ~= nil and noteRow.text.text == "Module Row" and noteRow.right.text == "7"
	and noteTip == GameTooltip and not noteRow.shown)
-- a patrol crossing the route names itself under the arrow nearby, not further off or with the option off
local inst = DN.inst
inst.patrols = { { x = DN.px + 10, y = DN.py, f = 2 ^ (DN.pfloor or 0), text = "Test Guard x2" } }
local near = DN:NearPatrol()
DN.wp.x, DN.wp.y, DN.wp.dist, DN.wp.boss = DN.px + 30, DN.py, 30, inst.bosses[1]
DN.arrow.scripts.OnUpdate(DN.arrow, 1)
local hintText = MOCK.fonts[DN.arrow][3].text or ""
inst.patrols[1].x = DN.px + 40
local far = DN:NearPatrol()
inst.patrols[1].x = DN.px + 10
DN.opt.patrols = false
local off = DN:NearPatrol()
DN.opt.patrols = true
inst.patrols = nil
print("patrol warning:", near == "Test Guard x2" and hintText:find("Patrol crosses here", 1, true) ~= nil
	and hintText:find("Test Guard x2", 1, true) ~= nil and far == nil and off == nil)
for _, c in ipairs({"", "", "arrow", "arrow", "map", "map", "stats", "saved", "help", "route library", "next", "lock", "lock"}) do SlashCmdList.INSTANCEGPS(c) end
