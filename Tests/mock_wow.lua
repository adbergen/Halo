--[[ Halo — Tests/mock_wow.lua

	A small stand-in for the World of Warcraft Lua environment so the addon's
	own code can be loaded and exercised by a plain Lua interpreter in CI. It
	stubs CreateFrame (with a permissive frame mock), the global APIs we touch,
	and fake LibStub libraries.

	The goal is *not* to emulate WoW faithfully — it is to catch syntax errors,
	load-order mistakes, and nil-global references before the addon ever reaches
	the game. Run via Tests/run.lua.
]]

unpack = unpack or table.unpack -- luacheck: ignore (5.2+ compatibility)

local M = {}
M.frames = {} -- every created frame, for event dispatch

-- ─── Frame mock ──────────────────────────────────────────────────────

local FrameMT = {}
local methods = {}

local FRAME_TYPES = {
	Frame = true, Button = true, ScrollFrame = true, Slider = true,
	CheckButton = true, EditBox = true, StatusBar = true,
}

local function newObject(objType, parent, name)
	local o = setmetatable({
		__type = objType, __parent = parent, __name = name,
		__scripts = {}, __events = {}, __children = {}, __nregions = 0,
		__shown = true,
	}, FrameMT)
	if parent and type(parent) == "table" and parent.__children then
		if FRAME_TYPES[objType] then
			table.insert(parent.__children, o)
		else
			parent.__nregions = parent.__nregions + 1
		end
	end
	if FRAME_TYPES[objType] then table.insert(M.frames, o) end
	if name then _G[name] = o end
	return o
end
M.newObject = newObject

local function noop(self) return self end
FrameMT.__index = function(_, key) return methods[key] or noop end

-- getters that must return real values
function methods.GetName(self) return self.__name end
function methods.GetObjectType(self) return self.__type or "Frame" end
function methods.IsObjectType(self, t) return (self.__type or "Frame") == t end
function methods.GetParent(self) return self.__parent end
function methods.SetParent(self, p) self.__parent = p; return self end
function methods.GetChildren(self) return unpack(self.__children) end
function methods.GetNumRegions(self) return self.__nregions or 0 end
function methods.GetNumChildren(self) return #self.__children end
function methods.GetWidth(self) return self.__width or 0 end
function methods.GetHeight(self) return self.__height or 0 end
function methods.SetWidth(self, w) self.__width = w; return self end
function methods.SetHeight(self, h) self.__height = h; return self end
function methods.SetSize(self, w, h) self.__width, self.__height = w, h; return self end
function methods.GetNumPoints() return 0 end
function methods.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods.GetScale() return 1 end
function methods.GetEffectiveScale() return 1 end
function methods.GetCenter() return 400, 300 end
function methods.GetFrameLevel() return 0 end
function methods.GetVerticalScroll() return 0 end
function methods.GetValue(self) return self.__value or 0 end
function methods.SetValue(self, v) self.__value = v; return self end
function methods.IsForbidden() return false end
function methods.IsShown(self) return self.__shown ~= false end
function methods.IsVisible(self) return self.__shown ~= false end
function methods.Show(self) self.__shown = true; return self end
function methods.Hide(self) self.__shown = false; return self end
function methods.SetShown(self, b) self.__shown = b and true or false; return self end

function methods.SetText(self, txt)
	self.__text = txt
	if self.__type == "FontString" then
		self.__height = 12
		self.__width = #tostring(txt or "") * 6
	end
	return self
end
function methods.GetText(self) return self.__text end
function methods.GetStringWidth(self) return self.__width or (#tostring(self.__text or "") * 6) end
function methods.GetStringHeight() return 12 end

function methods.SetScript(self, name, fn) self.__scripts[name] = fn; return self end
function methods.GetScript(self, name) return self.__scripts[name] end
function methods.HookScript(self, name, fn)
	local prev = self.__scripts[name]
	self.__scripts[name] = function(...)
		if prev then prev(...) end
		return fn(...)
	end
	return self
end
function methods.RegisterEvent(self, e) self.__events[e] = true; return self end
function methods.UnregisterEvent(self, e) self.__events[e] = nil; return self end
function methods.RegisterForClicks() return end

function methods.CreateTexture(self) return newObject("Texture", self) end
function methods.CreateFontString(self) return newObject("FontString", self) end
function methods.CreateAnimationGroup(self) return newObject("AnimationGroup", self) end
function methods.CreateAnimation(self) return newObject("Animation", self) end
function methods.SetScrollChild(self, c) self.__scrollchild = c; return self end

-- ─── Globals ─────────────────────────────────────────────────────────

function CreateFrame(objType, name, parent)
	return newObject(objType or "Frame", parent, name)
end

function hooksecurefunc(arg1, arg2, arg3)
	local tbl, key, post
	if type(arg1) == "table" then
		tbl, key, post = arg1, arg2, arg3
	else
		tbl, key, post = _G, arg1, arg2
	end
	local orig = tbl[key]
	tbl[key] = function(...)
		if orig then orig(...) end
		return post(...)
	end
end

C_Timer = { After = function(_, fn) if fn then fn() end end } -- run synchronously

C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "1.0.0-test" or "" end }
function GetAddOnMetadata(_, key) return key == "Version" and "1.0.0-test" or "" end

function MouseIsOver() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

SlashCmdList = {}

Settings = {
	RegisterCanvasLayoutCategory = function(_, name)
		return { ID = name, GetID = function() return name end }
	end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function() end,
}

-- ─── Fake libraries ──────────────────────────────────────────────────

local function deepcopy(src)
	if type(src) ~= "table" then return src end
	local dst = {}
	for k, v in pairs(src) do dst[k] = deepcopy(v) end
	return dst
end

local fakeAceDB = {
	New = function(_, _, defaults)
		local db
		db = {
			profile = deepcopy(defaults.profile),
			RegisterCallback = function() end,
			ResetProfile = function() db.profile = deepcopy(defaults.profile) end,
		}
		return db
	end,
}

-- Stateful enough to reproduce real behavior: registering a launcher creates a
-- minimap button and exposes it through GetButtonList/GetMinimapButton, so the
-- test catches the addon collecting its own launcher.
local registered = {}
local fakeLibDBIcon = {
	Register = function(_, name)
		local b = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
		b:SetSize(31, 31)
		registered[name] = b
		return b
	end,
	Hide = function() end,
	Show = function() end,
	Refresh = function() end,
	IsRegistered = function(_, name) return registered[name] ~= nil end,
	GetButtonList = function()
		local t = {}
		for n in pairs(registered) do t[#t + 1] = n end
		return t
	end,
	GetMinimapButton = function(_, name) return registered[name] end,
}

local fakeLDB = {
	NewDataObject = function(_, _, t) return t end,
}

local LIBS = {
	["AceDB-3.0"] = fakeAceDB,
	["LibDBIcon-1.0"] = fakeLibDBIcon,
	["LibDataBroker-1.1"] = fakeLDB,
}

function LibStub(name) return LIBS[name] end

-- ─── World frames ────────────────────────────────────────────────────

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1024, 768)
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", Minimap)

GameTooltip = CreateFrame("Frame", "GameTooltip", UIParent)
GameTooltip.AddLine = function() end
GameTooltip.SetOwner = function() end

-- ─── Test helpers ────────────────────────────────────────────────────

function M.fireEvent(event, ...)
	for _, frame in ipairs(M.frames) do
		if frame.__events[event] and frame.__scripts.OnEvent then
			frame.__scripts.OnEvent(frame, event, ...)
		end
	end
end

--- Create a fake legacy addon button on the minimap for collection tests.
function M.fakeMinimapButton(name)
	local b = CreateFrame("Button", name, Minimap)
	b:SetSize(31, 31)
	b:CreateTexture() -- give it a region so it looks button-ish
	return b
end

return M
