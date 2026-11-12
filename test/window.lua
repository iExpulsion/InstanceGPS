-- The style kit's windows and menu: the options window on MEDIUM, top-level, closing with Escape and building
-- every page; settings applying as they change and Reset This Page putting them back; the theme picker and window size; the
-- right-click menu's switches; and the Interface Options stub that opens the window.
local DN = NS.DN
MOCK.now = 1000000
MOCK.Fire("ADDON_LOADED", "InstanceGPS")
local O = DN.Options

-- the window follows the kit's conventions
DN:OpenOptions()
local f = O.frame
local escape = false
for _, name in ipairs(UISpecialFrames) do escape = escape or name == "InstanceGPSOptionsWindow" end
print("window:", f.shown and f.strata == "MEDIUM" and f.toplevel == true and escape)

-- every page builds and shows alone
local built = true
for _, def in ipairs(O.PAGES) do
	O.Open(def.key)
	local page = O.Page(def.key)
	built = built and page ~= nil and page.shown
	for _, other in ipairs(O.PAGES) do
		if other ~= def and O.Page(other.key) then built = built and not O.Page(other.key).shown end
	end
end
print("pages:", built)

-- the sidebar: General first, then Guide and Bosses; no Modules heading without a server module
local order = {}
for _, b in ipairs(O.frame.nav) do order[#order + 1] = b.key end
print("sidebar:", table.concat(order, ",") == "general,arrow,route,path,tracker,instances")

-- the Instances table ends inside the page's bottom padding, above the window's edge
local page = O.Page("instances")
local S = NS.Style
local bottom = -page.tableTop + page.table.frame.h
print("table fits:", bottom <= O.PAGE_H - 2 * S.PAD and bottom > O.PAGE_H - 2 * S.PAD - 1, bottom, O.PAGE_H)

-- a check applies at once: the arrow goes when its check is cleared; Reset This Page brings it back
O.Open("arrow")
local arrowCheck = O.Row("arrow", "Navigation Arrow").control
arrowCheck.scripts.OnClick(arrowCheck)
local off = DN.opt.arrow == false
O.ResetPage(O.Page("arrow"))
print("check and reset:", off and DN.opt.arrow == true and arrowCheck.on == true)

-- a slider shows a fraction as a percent and stores it back as a fraction
O.Open("tracker")
local size = O.Row("tracker", "Tracker Size").setting
size.set(125)
print("slider:", DN.opt.trackerScale == 1.25 and size.get() == 125)
size.reset()

-- the theme picker lists the skins and offers a reload for a new one
O.Open("general")
local theme = O.Row("general", "Theme").setting
local skins = theme.choices()
theme.set("classic")
print("theme:", #skins >= 3 and DN.db.skin == "classic" and MOCK.popup and MOCK.popup.which == "INSTANCEGPS_RELOAD")

-- the window size starts at 100%, lists the sizes, sizes every window when picked and resets to 100%
local sizeRow = O.Row("general", "Window Size")
local sizes = sizeRow.setting.choices()
local startsAt100 = DN.db.windowScale == 1 and sizeRow.control.label.text == "100%"
sizeRow.setting.set(1.5)
local picked = DN.db.windowScale == 1.5 and NS.Style.windowScale == 1.5
sizeRow.setting.reset()
print("window size:", startsAt100 and #sizes == #DN.WINDOW_SCALES and sizes[1].text == "80%" and picked
	and DN.db.windowScale == 1 and NS.Style.windowScale == 1)

-- the right-click menu: a switch flips its option and the menu stays open on it
DN:ShowMenu(DN.arrow)
local menu = InstanceGPSMenu
local item
for _, it in ipairs(menu.items) do
	if it.text.text == "Show Boss Tracker" then item = it end
end
local before = DN.opt.tracker
item.scripts.OnClick(item)
print("menu:", menu.shown and DN.opt.tracker == not before and item.check.on == DN.opt.tracker)

-- Interface Options > AddOns > InstanceGPS is a page with a button to the window
local panel
for _, p in ipairs(MOCK.categories) do if p.name == "InstanceGPS" then panel = p end end
print("stub panel:", panel ~= nil and #MOCK.categories == 1)
print("window test done")
