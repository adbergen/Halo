--[[ Halo — Core/Compartment.lua

	Blizzard's addon menu: the button beside the minimap clock on Retail and
	WoW Forever that lists addons in a drop-down. Addons get into it two ways:
	an `AddonCompartmentFunc` line in their toc, or a call to
	`AddonCompartmentFrame:RegisterAddon` (LibDBIcon's "show in compartment"
	uses this). Some addons now appear only there, with no minimap button, so a
	button bag that only sweeps the minimap leaves them out.

	This module gives each menu entry a stand-in button drawn like a LibDBIcon
	minimap button, and the detector reports the stand-ins like any other
	button, so the tray holds every launcher. An entry whose addon already has a
	button among the detected ones is skipped, so nothing shows twice.

	A click on a stand-in does what the menu does. For a toc entry Halo calls
	the addon's named global itself: Blizzard's wrapper for those entries also
	calls `forceinsecure`, which belongs to Blizzard's menu code, and from addon
	code the global runs the same way without it. For a registered entry Halo
	calls the entry's own callbacks, passing the stand-in where the menu passes
	its frame.

	Blizzard's menu button itself is left alone.
]]

local _, ns = ...

local Compartment = {}
ns.Compartment = Compartment

-- Collected-button names for menu entries start with this.
Compartment.PREFIX = "AddonMenu_"

local QUESTION_MARK = 134400 -- icon for an entry without one

local holder        -- hidden parent of stand-ins that are not in the tray
local standIns = {} -- button name -> stand-in
local entryOf = {}  -- stand-in -> { entry, toc, label }: kept here, not on the frame

local function menu()
	local frame = _G.AddonCompartmentFrame
	if frame and type(frame.registeredAddons) == "table" then return frame end
	return nil
end

--- Does this client have Blizzard's addon menu?
function Compartment:IsAvailable()
	return menu() ~= nil
end

--- Entry text without color codes, textures or links.
local function plain(text)
	text = tostring(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|H.-|h(.-)|h", "%1")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Letters and digits only, lower case: "Atlas Loot" matches "AtlasLoot".
local function matchKey(text)
	return (plain(text):lower():gsub("[^%w]", ""))
end

--- Is `key` (an addon's name) one of the found buttons, or the start of one?
--- Buttons are usually named after their addon: RareScanner's LibDBIcon
--- button is "RareScannerMinimapIcon". Very short names only match exactly.
local function isTaken(buttonKeys, key)
	if key == "" then return false end
	for _, buttonKey in ipairs(buttonKeys) do
		if buttonKey == key or (#key >= 4 and buttonKey:sub(1, #key) == key) then return true end
	end
	return false
end

local function iconKey(icon)
	if icon == nil or icon == QUESTION_MARK then return nil end
	local key = tostring(icon):lower():gsub("/", "\\")
	if key:find("inv_misc_questionmark", 1, true) then return nil end -- shared by many
	return "icon:" .. key
end

--- Addons that put themselves in the menu from their toc, by title (the text
--- Blizzard gives their entries): title -> { addon, func, onEnter, onLeave }.
local function tocEntries()
	local tocByTitle = {}
	local api = C_AddOns
	if not (api and api.GetNumAddOns and api.GetAddOnInfo and api.GetAddOnMetadata) then return tocByTitle end
	for i = 1, api.GetNumAddOns() do
		local func = api.GetAddOnMetadata(i, "AddonCompartmentFunc")
		if func then
			local name, title = api.GetAddOnInfo(i)
			if name and title then
				tocByTitle[title] = {
					addon = name,
					func = func,
					onEnter = api.GetAddOnMetadata(i, "AddonCompartmentFuncOnEnter"),
					onLeave = api.GetAddOnMetadata(i, "AddonCompartmentFuncOnLeave"),
				}
			end
		end
	end
	return tocByTitle
end

--- Call a toc entry's named global the way Blizzard's menu does: load the
--- addon first if it loads on demand, then pass the addon name.
local function callGlobal(toc, funcName, ...)
	local api = C_AddOns
	if api.IsAddOnLoaded and api.LoadAddOn and not api.IsAddOnLoaded(toc.addon) then
		api.LoadAddOn(toc.addon)
	end
	local fn = _G[funcName]
	if type(fn) == "function" then fn(toc.addon, ...) end
end

local function setIcon(texture, icon)
	if type(icon) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon) then
		texture:SetAtlas(icon)
	else
		texture:SetTexture(icon or QUESTION_MARK)
	end
end

local function onClick(self, mouseButton)
	local entry, toc = entryOf[self].entry, entryOf[self].toc
	if toc then
		callGlobal(toc, toc.func, mouseButton)
	elseif entry.func then
		local input = { buttonName = mouseButton, context = MenuInputContext and MenuInputContext.MouseButton }
		entry.func(nil, input, self)
	end
end

local function onEnter(self)
	local entry, toc = entryOf[self].entry, entryOf[self].toc
	if toc and toc.onEnter then
		callGlobal(toc, toc.onEnter, self)
	elseif not toc and entry.funcOnEnter then
		entry.funcOnEnter(self, entry) -- the menu passes its element, which carries .text
	else
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(entryOf[self].label)
		GameTooltip:Show()
	end
end

local function onLeave(self)
	local entry, toc = entryOf[self].entry, entryOf[self].toc
	if toc and toc.onLeave then
		callGlobal(toc, toc.onLeave, self)
	elseif not toc and entry.funcOnLeave then
		entry.funcOnLeave(self, entry)
	end
	GameTooltip:Hide()
end

--- A button with the same art and size as LibDBIcon's, so stand-ins sit in the
--- tray like the minimap buttons around them.
local function createStandIn()
	if not holder then
		holder = CreateFrame("Frame", nil, UIParent)
		holder:Hide()
	end
	local button = CreateFrame("Button", nil, holder)
	button:SetSize(31, 31)
	button:RegisterForClicks("AnyUp")
	button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
	local icon = button:CreateTexture(nil, "ARTWORK")
	if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
		overlay:SetSize(50, 50)
		overlay:SetPoint("TOPLEFT")
		background:SetSize(24, 24)
		background:SetPoint("CENTER")
		icon:SetSize(18, 18)
		icon:SetPoint("CENTER")
	else
		overlay:SetSize(53, 53)
		overlay:SetPoint("TOPLEFT")
		background:SetSize(20, 20)
		background:SetPoint("TOPLEFT", 7, -5)
		icon:SetSize(17, 17)
		icon:SetPoint("TOPLEFT", 7, -6)
	end
	button.icon = icon

	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", onEnter)
	button:SetScript("OnLeave", onLeave)
	return button
end

--- Stand-ins for the menu's entries, keyed by button name. `found` holds the
--- buttons detected elsewhere; an entry for one of those addons is skipped.
function Compartment:Scan(found)
	local frame = menu()
	if not frame or #frame.registeredAddons == 0 then return {} end

	local buttonKeys, icons = {}, {}
	for name, info in pairs(found) do
		buttonKeys[#buttonKeys + 1] = matchKey(name)
		local dataObject = info.frame and info.frame.dataObject -- LibDBIcon's; legacy frames may hold anything
		local key = type(dataObject) == "table" and iconKey(dataObject.icon)
		if key then icons[key] = true end
	end

	local tocs = tocEntries()
	local result = {}
	for _, entry in ipairs(frame.registeredAddons) do
		local label = plain(entry.text)
		local toc = tocs[entry.text]
		local name = self.PREFIX .. (toc and toc.addon or label)
		local own = label == ns.ADDON or (toc and toc.addon == ns.ADDON)
		local iconMatch = iconKey(entry.icon)
		local duplicate = isTaken(buttonKeys, matchKey(label))
			or (toc and isTaken(buttonKeys, matchKey(toc.addon)))
			or (iconMatch and icons[iconMatch])
		if label ~= "" and not own and not duplicate and not result[name] then
			local button = standIns[name] or createStandIn()
			standIns[name] = button
			entryOf[button] = { entry = entry, toc = toc, label = label }
			setIcon(button.icon, entry.icon)
			result[name] = button
		end
	end
	return result
end

--- The menu's name for a stand-in (colors and textures removed), or nil when
--- the button is not one.
function Compartment:Label(name)
	local button = standIns[name]
	return button and entryOf[button] and entryOf[button].label
end

--- Call onChange whenever the menu's entries change. Blizzard and LibDBIcon
--- both finish every change with UpdateDisplay; several in one frame (the
--- toc entries at world entry) produce one call.
function Compartment:Watch(onChange)
	local frame = menu()
	if not frame or self.watching then return end
	self.watching = true
	local pending = false
	hooksecurefunc(frame, "UpdateDisplay", function()
		if pending then return end
		pending = true
		C_Timer.After(0, function()
			pending = false
			onChange()
		end)
	end)
end
