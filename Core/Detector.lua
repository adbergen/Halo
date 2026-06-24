--[[ Halo — Core/Detector.lua

	Finds the buttons that *should* be collected, from two sources:

	  1. LibDBIcon-1.0 buttons — the modern standard. Enumerated cleanly via
	     the library's own API, so no guessing required.
	  2. Legacy buttons — frames an addon parented to the Minimap by hand.
	     Identified heuristically and filtered against a blacklist of Blizzard's
	     own minimap frames so we never touch those.

	The detector only *reports* buttons; Collector.lua decides what to do with
	them. Keeping detection pure makes it easy to test and reason about.
]]

local _, ns = ...

local Detector = {}
ns.Detector = Detector

local LibDBIcon = LibStub("LibDBIcon-1.0", true)

-- Blizzard's own minimap children — never collect these (exact names).
local BLIZZARD = {
	MiniMapTracking = true, MiniMapTrackingButton = true, MiniMapTrackingFrame = true,
	MiniMapMailFrame = true, MiniMapMailIcon = true,
	MiniMapBattlefieldFrame = true, MiniMapWorldMapButton = true,
	MiniMapLFGFrame = true, LFGMinimapFrame = true, MiniMapInstanceDifficulty = true,
	GuildInstanceDifficulty = true, MiniMapChallengeMode = true,
	GameTimeFrame = true, TimeManagerClockButton = true,
	QueueStatusMinimapButton = true, QueueStatusButton = true,
	MinimapZoomIn = true, MinimapZoomOut = true,
	MinimapZoneTextButton = true, MinimapBackdrop = true, MinimapCluster = true,
	MinimapNorthTag = true, MiniMapVoiceChatFrame = true,
	ExpansionLandingPageMinimapButton = true, GarrisonLandingPageMinimapButton = true,
	MinimapCompassTexture = true, Minimap = true,
}

-- Name prefixes that mark a Blizzard/system frame regardless of suffix.
local BLIZZARD_PREFIX = { "MiniMap", "Minimap" }

-- Blizzard minimap frames the user can opt into collecting (Config setting key →
-- candidate frame names, first existing one wins). Off by default.
local OPTIONAL_BLIZZARD = {
	lfg         = { "LFGMinimapFrame", "MiniMapLFGFrame" },
	mail        = { "MiniMapMailFrame" },
	tracking    = { "MiniMapTracking", "MiniMapTrackingButton" },
	battlefield = { "MiniMapBattlefieldFrame", "MiniMapBattlefieldButton" },
}

-- A LibDBIcon button is named like "LibDBIcon10_Questie".
local LIBDBICON_PREFIX = "LibDBIcon10_"

local function startsWith(str, prefix)
	return str:sub(1, #prefix) == prefix
end

--- Is this frame one of LibDBIcon's managed buttons?
function Detector:IsLibDBIconButton(frame)
	local name = frame and frame.GetName and frame:GetName()
	return name ~= nil and startsWith(name, LIBDBICON_PREFIX)
end

--- Should this minimap child be ignored as a Blizzard/system frame?
local function isBlizzard(name)
	if BLIZZARD[name] then return true end
	for _, prefix in ipairs(BLIZZARD_PREFIX) do
		if startsWith(name, prefix) then return true end
	end
	return false
end

--- Heuristic: does this look like a third-party minimap button?
function Detector:IsLegacyCandidate(frame)
	if type(frame) ~= "table" or not frame.GetObjectType then return false end
	if frame:IsObjectType("Texture") or frame:IsObjectType("FontString") then return false end

	local name = frame.GetName and frame:GetName()
	if not name then return false end                 -- anonymous frames are unaddressable
	if isBlizzard(name) then return false end
	if self:IsLibDBIconButton(frame) then return false end -- handled by the clean path

	-- Real minimap buttons are ~31px. A floor of 20 filters out small map
	-- markers and quest pins (e.g. NWBNaxxMarkerMini w=13, Questie pins w=11).
	local w, h = frame:GetWidth(), frame:GetHeight()
	if not w or not h or w < 20 or w > 48 or h < 20 or h > 48 then return false end

	local hasTexture = (frame.GetNumRegions and frame:GetNumRegions() > 0)
		or frame:IsObjectType("Button")
	return hasTexture and true or false
end

--- All currently-registered LibDBIcon buttons as { name = frame } pairs.
function Detector:GetLibDBIconButtons()
	local found = {}
	if not LibDBIcon then return found end
	for _, name in ipairs(LibDBIcon:GetButtonList()) do
		if name ~= ns.ADDON then -- never collect Halo's own launcher
			local button = LibDBIcon:GetMinimapButton(name)
			if button then found[name] = button end
		end
	end
	return found
end

--- Legacy candidates parented directly to the Minimap (and its backdrop).
function Detector:GetLegacyButtons()
	local found = {}
	local parents = { Minimap, _G.MinimapBackdrop }
	for _, parent in ipairs(parents) do
		if parent and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				if self:IsLegacyCandidate(child) then
					found[child:GetName()] = child
				end
			end
		end
	end
	return found
end

--- Is this frame name an opted-in Blizzard frame right now?
function Detector:IsOptedIn(name)
	local collect = ns.db.profile.collect
	for key, names in pairs(OPTIONAL_BLIZZARD) do
		if collect[key] then
			for _, candidate in ipairs(names) do
				if candidate == name then return true end
			end
		end
	end
	return false
end

--- The opted-in Blizzard frames that currently exist, keyed by name.
function Detector:GetOptedInBlizzard()
	local found = {}
	local collect = ns.db.profile.collect
	for key, names in pairs(OPTIONAL_BLIZZARD) do
		if collect[key] then
			for _, name in ipairs(names) do
				local frame = _G[name]
				if frame and frame.GetObjectType then
					found[name] = frame
					break -- one frame per category
				end
			end
		end
	end
	return found
end

--- Everything collectable right now, keyed by button name.
-- Each value is { frame = <frame>, source = "libdbicon"|"legacy"|"blizzard" }.
function Detector:Scan()
	local result = {}
	for name, frame in pairs(self:GetLibDBIconButtons()) do
		result[name] = { frame = frame, source = "libdbicon" }
	end
	for name, frame in pairs(self:GetLegacyButtons()) do
		if not result[name] then
			result[name] = { frame = frame, source = "legacy" }
		end
	end
	-- Opt-in Blizzard frames bypass the blacklist and size floor entirely.
	for name, frame in pairs(self:GetOptedInBlizzard()) do
		if not result[name] then
			result[name] = { frame = frame, source = "blizzard" }
		end
	end
	return result
end
