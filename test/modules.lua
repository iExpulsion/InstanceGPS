-- Server modules' options (InstanceGPS:ModuleOptions): defaults before the settings load, a page in the options
-- window with a checkbox and a dropdown, changes saved and announced, a long list of choices in a picker, and a
-- module that registers after the window is built.
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

-- the page sits under Modules at the bottom of the sidebar; General is first
local O = DN.Options
local KEY = "module:Test Server"
O.Open(KEY)
local nav = O.frame.nav
local def
for _, d in ipairs(O.PAGES) do if d.key == KEY then def = d end end
print("page:", defaults and nav[1].key == "general" and nav[#nav].key == KEY and O.GroupOf(def) == "Modules"
	and O.Page(KEY):IsShown())

-- the checkbox: shows the value when the page opens, saves a click
local cb = O.Row(KEY, "Extra Rows").control
local shown = cb.on == true
cb.scripts.OnClick(cb)
print("checkbox:", shown and opt.rows == false and cb.on == false and DN.db.modules["Test Server"].rows == false
	and heard[1] == "Test Server:rows=false")

-- the dropdown: shows the current choice's label, saves a pick
local dd = O.Row(KEY, "Loot List").control
local label = dd.label.text
dd.items[2].scripts.OnClick(dd.items[2])
print("dropdown:", label == "Show All" and opt.mode == "some" and dd.label.text == "Show Some"
	and heard[2] == "Test Server:mode=some")

-- a module registering after the window is built gets its page in the sidebar straight away, with saved values kept;
-- its long list of choices opens a searchable picker
local choices = {}
for i = 1, 20 do choices[i] = { i, "Choice " .. i } end
local late = DN:ModuleOptions("Late Server", {
	{ key = "on", label = "On", default = false },
	{ key = "pick", label = "Pick", default = 3, choices = choices },
})
local lateListed = O.frame.nav[#O.frame.nav].key == "module:Late Server"
O.Open("module:Late Server")
local picker = O.Row("module:Late Server", "Pick").control
print("late module:", lateListed and late.on == false and late.pick == 3 and opt.rows == false
	and picker.items == nil and picker.label.text == "Choice 3")
print("modules test done")
