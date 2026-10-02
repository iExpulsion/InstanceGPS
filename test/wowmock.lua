-- Minimal WoW 3.3.5 API mock for running InstanceGPS logic outside the game.
local mock = {}
_G.MOCK = mock

-- universal stub object: every method exists and returns sensible values
local function Stub(name)
	local o = { __name = name, scripts = {}, shown = false, w = 100, h = 100, events = {} }
	return setmetatable(o, { __index = function(t, k)
		if type(k) ~= "string" or not k:match("^%u") then return nil end
		local f
		if k == "SetScript" then f = function(self, s, fn) self.scripts[s] = fn end
		elseif k == "HookScript" then f = function(self, s, fn) self.scripts[s] = fn end
		elseif k == "GetScript" then f = function(self, s) return self.scripts[s] end
		elseif k == "Show" then f = function(self) self.shown = true end
		elseif k == "Hide" then f = function(self) self.shown = false end
		elseif k == "IsShown" or k == "IsVisible" then f = function(self) return self.shown end
		elseif k == "RegisterEvent" then f = function(self, e) self.events[e] = true; mock.frames[#mock.frames + 1] = self end
		elseif k == "GetWidth" then f = function(self) return self.w end
		elseif k == "GetHeight" then f = function(self) return self.h end
		elseif k == "SetWidth" then f = function(self, v) self.w = v end
		elseif k == "SetHeight" then f = function(self, v) self.h = v end
		elseif k == "GetFrameLevel" then f = function() return 1 end
		elseif k == "GetPoint" then f = function() return "CENTER", nil, "CENTER", 0, 0 end
		elseif k == "SetPoint" then f = function(self, ...) self.point = { ... } end
		elseif k == "ClearAllPoints" then f = function(self) self.point = nil end
		elseif k == "SetTexCoord" then f = function(self, ...) self.tc = { ... } end
		elseif k == "SetVertexColor" then f = function(self, r, g, b, a) self.color = { r, g, b, a or 1 } end
		elseif k == "SetText" then f = function(self, v) self.text = v end
		elseif k == "GetText" then f = function(self) return self.text end
		elseif k == "CreateTexture" then f = function(self, ...)
			local t = Stub(k)
			mock.created[self] = mock.created[self] or {}
			table.insert(mock.created[self], t)
			t.shown = true
			return t
		end
		elseif k == "SetTexture" then f = function(self, v) self.file = v end
		elseif k == "SetSize" then f = function(self, w, h) self.size, self.w, self.h = w, w, h end
		elseif k == "CreateFontString" then f = function(self, ...)
			local t = Stub(k)
			mock.fonts[self] = mock.fonts[self] or {}
			table.insert(mock.fonts[self], t)
			t.shown = true
			return t
		end
		elseif k:match("^Create") then f = function(self, ...) return Stub(k) end
		else f = function(self) return nil end end
		rawset(t, k, f)
		return f
	end })
end
mock.Stub = Stub
mock.frames = {}
mock.created = {}
mock.fonts = {}
mock.all = {}

function CreateFrame(kind, name, parent, template)
	local f = Stub(kind)
	mock.all[#mock.all + 1] = f
	if name then
		_G[name] = f
		for _, part in ipairs({ "Text", "Low", "High" }) do _G[name .. part] = Stub(part) end
	end
	return f
end
UIParent = Stub("UIParent")
WorldMapButton = Stub("WorldMapButton")
WorldMapButton.w, WorldMapButton.h = 1002, 668
WorldMapFrame = Stub("WorldMapFrame")
WorldMapTooltip = Stub("tip")
GameTooltip = Stub("tip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("[chat] " .. tostring(m):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end }
StaticPopupDialogs = {}
SlashCmdList = {}
YES, NO, CLOSE = "Yes", "No", "Close"
INSTANCE_RESET_SUCCESS = "%s has been reset."
function GetAddOnMetadata() return "test" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function time() return mock.now or os.time() end
function GetTime() return mock.now or os.time() end
function SecondsToTime(s) return tostring(s) .. "s" end
function RequestRaidInfo() end
function GetNumSavedInstances() return 0 end
function GetSavedInstanceInfo() end
function IsInInstance() return mock.inInstance, mock.itype end
function GetInstanceInfo() return mock.instName, mock.itype, mock.diff or 1, mock.diffName or "Normal", 5 end
function SetMapToCurrentZone() end
function GetMapInfo() return mock.mapFile end
function GetCurrentMapDungeonLevel() return mock.level or 0 end
function GetPlayerMapPosition() return mock.mx or 0, mock.my or 0 end
function GetPlayerFacing() return mock.facing or 0 end
function UnitExists() return false end
function EasyMenu() end
function CloseDropDownMenus() end
function ReloadUI() end
function StaticPopup_Show(which, a1) mock.popup = { which = which, text = a1 } return mock.popup end
function UnitIsDeadOrGhost() return mock.dead end
function tinsert(t, v) table.insert(t, v) end

-- fire an event on every registered frame
function mock.Fire(event, ...)
	for _, f in ipairs(mock.frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

function mock.Tick(dt)
	for _, f in ipairs(mock.all) do
		if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt or 0.2) end
	end
end
function UnitFactionGroup() return MOCK.faction or "Alliance" end

Minimap = Stub("Minimap"); Minimap.w, Minimap.h = 140, 140
mock.cvars = { minimapZoom = "0", minimapInsideZoom = "2", rotateMinimap = "0" }
mock.zoom = 2
function Minimap:GetZoom() return mock.zoom end
function Minimap:SetZoom(z) mock.zoom = z end
function GetCVar(k) return mock.cvars[k] end
function InterfaceOptions_AddCategory() end
function InterfaceOptionsFrame_OpenToCategory() end
function UnitAffectingCombat() return mock.combat end
-- record texture placement so tests can inspect what the path views draw
mock.placed = 0
-- achievement statistics: mock.stat[id] = count (string "--" when never done, like the client)
mock.stat = {}
function GetStatistic(id) local v = mock.stat[id] return v and tostring(v) or "--" end
mock.achName = {}
function GetAchievementInfo(id) return id, mock.achName[id] or ("Stat " .. id .. " (Test " .. id .. ")") end
