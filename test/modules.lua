-- Server modules' options (InstanceGPS:ModuleOptions): defaults before the settings load, a page
-- under InstanceGPS's with a checkbox and a dropdown, changes saved and announced, and a module
-- that registers after loading.
local DN = NS.DN
MOCK.now = 1000000

-- registered before the settings have loaded, like a module's files in game
local opt = DN:ModuleOptions("Test Server", {
	{ key = "rows", label = "Extra Rows", default = true, tip = "Rows under the boss list." },
	{ key = "mode", label = "Loot List", default = "all", choices = { { "all", "Show All" }, { "some", "Show Some" } } },
})
local defaults = opt.rows == true and opt.mode == "all"
local heard = {}
DN:On("MODULE_OPTION", function(module, key, value) heard[#heard + 1] = module .. ":" .. key .. "=" .. tostring(value) end)
MOCK.Fire("ADDON_LOADED", "InstanceGPS")

local page = MOCK.categories[#MOCK.categories]
print("page:", defaults and page.name == "Test Server" and page.parent == "InstanceGPS")

-- the checkbox: shows the value when the page opens, saves a click
local cb = _G.InstanceGPSModOpt_TestServer_rows
page.scripts.OnShow(page)
local shown = cb.checked == 1
cb.checked = nil
cb.scripts.OnClick(cb)
print("checkbox:", shown and opt.rows == false and DN.db.modules["Test Server"].rows == false and heard[1] == "Test Server:rows=false")

-- the dropdown: shows the current choice's label, saves a pick
local dd = _G.InstanceGPSModOpt_TestServer_mode
local label = dd.ddText
MOCK.ddButtons = {}
dd.init()
local some = MOCK.ddButtons[2]
some.func()
print("dropdown:", label == "Show All" and #MOCK.ddButtons == 2 and MOCK.ddButtons[1].checked == true
	and opt.mode == "some" and dd.ddText == "Show Some" and heard[2] == "Test Server:mode=some")

-- a module registering after the settings loaded gets its page straight away, with saved values kept
local n = #MOCK.categories
local late = DN:ModuleOptions("Late Server", { { key = "on", label = "On", default = false } })
print("late module:", #MOCK.categories == n + 1 and late.on == false and opt.rows == false)
print("modules test done")
