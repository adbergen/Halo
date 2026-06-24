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
	MiniMapLFGFrame = true, LFGMinimapFrame = true, LFGMinimapFrameBorder = true,
	MiniMapInstanceDifficulty = true, MiniMapInstanceDifficultyText = true,
	GuildInstanceDifficulty = true, MiniMapChallengeMode = true,
	GameTimeFrame = true, TimeManagerClockButton = true, CalendarButtonFrame = true,
	QueueStatusMinimapButton = true, QueueStatusButton = true,
	MinimapZoomIn = true, MinimapZoomOut = true, BattlefieldMinimap = true,
	MinimapZoneTextButton = true, MinimapBackdrop = true, MinimapCluster = true,
	MinimapNorthTag = true, MiniMapVoiceChatFrame = true,
	HelpOpenTicketButton = true, HelpOpenWebTicketButton = true,
	ExpansionLandingPageMinimapButton = true, GarrisonLandingPageMinimapButton = true,
	MinimapCompassTexture = true, Minimap = true,
}

-- Name prefixes that mark a Blizzard/system frame regardless of suffix.
local BLIZZARD_PREFIX = {
	"MiniMap", "Minimap", "LFG", "QueueStatus", "GameTime", "TimeManager",
	"Calendar", "Garrison", "ExpansionLandingPage", "BattlefieldMinimap",
}

-- Substrings that almost always mark a Blizzard/system frame.
local BLIZZARD_PATTERN = { "Difficulty", "VoiceChat", "PvPTimer" }

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
	for _, pattern in ipairs(BLIZZARD_PATTERN) do
		if name:find(pattern) then return true end
	end
	return false
end
Detector.isBlizzard = isBlizzard -- exposed for the /halo scan diagnostic

--- A real minimap button responds to clicks; quest/tracking/POI blips do not.
-- This is the line that separates buttons from minimap noise.
local function isClickable(frame)
	if not frame.GetScript then return false end
	return frame:GetScript("OnClick")
		or frame:GetScript("OnMouseUp")
		or frame:GetScript("OnMouseDown")
		or false
end
Detector.isClickable = isClickable

--- Heuristic: does this look like a third-party minimap button?
function Detector:IsLegacyCandidate(frame)
	if type(frame) ~= "table" or not frame.GetObjectType then return false end
	if frame:IsObjectType("Texture") or frame:IsObjectType("FontString") then return false end

	local name = frame.GetName and frame:GetName()
	if not name then return false end                 -- anonymous frames are unaddressable
	if isBlizzard(name) then return false end
	if self:IsLibDBIconButton(frame) then return false end -- handled by the clean path

	-- Must be clickable: rejects non-interactive decorative frames.
	if not isClickable(frame) then return false end

	-- Size band: real minimap buttons are ~31px. Quest/POI pins (e.g. Questie's
	-- w=11 markers) are much smaller, so a floor of 20 filters them out while
	-- keeping genuine buttons.
	local w, h = frame:GetWidth(), frame:GetHeight()
	if not w or not h or w < 20 or w > 48 or h < 20 or h > 48 then return false end

	return true
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

--- Everything collectable right now, keyed by button name.
-- Each value is { frame = <frame>, source = "libdbicon"|"legacy" }.
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
	return result
end

--- Human-readable report of every minimap child and why we did/didn't take it.
-- Surfaced via `/halo scan` to diagnose missing or false-positive buttons.
function Detector:Dump()
	local lines = { "|cff66b3ffHalo|r minimap scan:" }
	for _, parent in ipairs({ Minimap, _G.MinimapBackdrop }) do
		if parent and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				local name = (child.GetName and child:GetName()) or "<anonymous>"
				local objType = (child.GetObjectType and child:GetObjectType()) or "?"
				local w = (child.GetWidth and math.floor((child:GetWidth() or 0) + 0.5)) or 0
				local mouse = child.IsMouseEnabled and child:IsMouseEnabled()
				local verdict
				if self:IsLibDBIconButton(child) then
					verdict = "|cff66b3ffLibDBIcon|r"
				elseif name ~= "<anonymous>" and isBlizzard(name) then
					verdict = "|cff999999Blizzard (skip)|r"
				elseif self:IsLegacyCandidate(child) then
					verdict = "|cff66ff66legacy (take)|r"
				else
					verdict = "|cffff6666ignored|r"
				end
				lines[#lines + 1] = ("  %s [%s] w=%d mouse=%s → %s")
					:format(name, objType, w, tostring(mouse and true or false), verdict)
			end
		end
	end
	local ldb = {}
	for n in pairs(self:GetLibDBIconButtons()) do ldb[#ldb + 1] = n end
	table.sort(ldb)
	lines[#lines + 1] = "LibDBIcon buttons: " .. (#ldb > 0 and table.concat(ldb, ", ") or "(none)")
	return lines
end
