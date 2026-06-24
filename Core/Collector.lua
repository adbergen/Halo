--[[ Halo — Core/Collector.lua

	Owns the lifecycle of every collected button: adopting it off the minimap,
	keeping it pinned inside the tray, and releasing it back when the user opts
	a button out (or disables Halo).

	Safety rules:
	  • Only ever touch non-secure, non-forbidden frames (minimap buttons are).
	  • Remember each button's original parent + anchors so release is lossless.
	  • Re-assert our layout if an addon tries to move "its" button afterwards,
	    using a `placing` guard so our own anchoring never recurses.
]]

local _, ns = ...

local Collector = {}
ns.Collector = Collector

local Detector = ns.Detector
local LibDBIcon = LibStub("LibDBIcon-1.0", true)

Collector.started = false
Collector.order = {}      -- ordered array of button names (tray order)
Collector.byName = {}     -- name  -> record { name, frame, source, origin }
Collector.byFrame = {}    -- frame -> record
Collector.placing = false -- true while *we* anchor buttons (suppresses relock)
Collector.failures = {}   -- name  -> error string (surfaced via /halo scan)

-- ─── Original-state capture (for lossless release) ───────────────────

local function snapshotAnchors(frame)
	local points = {}
	for i = 1, frame:GetNumPoints() do
		points[i] = { frame:GetPoint(i) }
	end
	return { parent = frame:GetParent(), points = points, scale = frame:GetScale() }
end

local function restoreAnchors(frame, origin)
	if not origin then return end
	frame:SetParent(origin.parent or Minimap)
	frame:ClearAllPoints()
	if #origin.points > 0 then
		for _, p in ipairs(origin.points) do
			frame:SetPoint(unpack(p))
		end
	else
		frame:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
	end
	if origin.scale then frame:SetScale(origin.scale) end
end

-- ─── Re-lock: bounce buttons back into the tray if an addon moves them ─

local function queueRelayout()
	if Collector.relayoutQueued then return end
	Collector.relayoutQueued = true
	C_Timer.After(0, function()
		Collector.relayoutQueued = false
		ns.Flyout:ApplyLayout()
	end)
end

local function onExternalSetPoint(frame)
	if Collector.placing then return end           -- our own anchoring, ignore
	if Collector.byFrame[frame] then queueRelayout() end
end

-- ─── Adoption ────────────────────────────────────────────────────────

function Collector:IsIgnored(name)
	return ns.db.profile.ignored[name] == true
end

function Collector:Adopt(name, frame, source)
	if self.byName[name] then return end
	if not frame or frame:IsForbidden() then return end

	local record = {
		name = name,
		frame = frame,
		source = source,
		origin = snapshotAnchors(frame),
	}

	frame:SetParent(ns.Flyout.grid)   -- off the minimap immediately
	frame:SetScale(1)

	if not record.hooked then
		hooksecurefunc(frame, "SetPoint", function() onExternalSetPoint(frame) end)
		record.hooked = true
	end

	self.byName[name] = record
	self.byFrame[frame] = record
	self.order[#self.order + 1] = name
end

function Collector:Release(name)
	local record = self.byName[name]
	if not record then return end

	restoreAnchors(record.frame, record.origin)
	self.byName[name] = nil
	self.byFrame[record.frame] = nil
	for i, n in ipairs(self.order) do
		if n == name then table.remove(self.order, i) break end
	end

	-- Let LibDBIcon re-seat its own button on the minimap edge.
	if record.source == "libdbicon" and LibDBIcon and LibDBIcon:IsRegistered(name) then
		LibDBIcon:Refresh(name)
	end
end

-- ─── Public surface ──────────────────────────────────────────────────

--- Ordered list of collected button records, honoring the saved tray order.
function Collector:GetButtons()
	local saved = ns.db.profile.order
	table.sort(self.order, function(a, b)
		local oa, ob = saved[a] or math.huge, saved[b] or math.huge
		if oa ~= ob then return oa < ob end
		return a < b
	end)
	local list = {}
	for _, name in ipairs(self.order) do
		list[#list + 1] = self.byName[name]
	end
	return list
end

function Collector:Count()
	return #self.order
end

--- Every button name we know about (collected or ignored) — for the options list.
function Collector:GetKnownNames()
	local names, seen = {}, {}
	for name in pairs(self.byName) do
		if not seen[name] then names[#names + 1] = name; seen[name] = true end
	end
	for name in pairs(Detector:Scan()) do
		if not seen[name] then names[#names + 1] = name; seen[name] = true end
	end
	table.sort(names)
	return names
end

--- Adopt anything new, release anything now ignored, then relayout.
-- Every foreign-frame touch is wrapped in pcall so a single misbehaving button
-- can never abort the whole pass (which would leave the rest on the minimap).
function Collector:Rescan()
	if not self.started then return end

	-- Release collected buttons the user now wants back on the minimap.
	-- (Adopted buttons live off the minimap, so the detector can't re-find
	-- them — we must walk our own records to honor a fresh ignore.)
	local toRelease = {}
	for name in pairs(self.byName) do
		if self:IsIgnored(name) then toRelease[#toRelease + 1] = name end
	end
	for _, name in ipairs(toRelease) do pcall(self.Release, self, name) end

	-- Adopt anything newly detected and not opted out.
	local ok, detected = pcall(function() return Detector:Scan() end)
	if not ok then
		self.failures["__scan"] = tostring(detected)
		detected = {}
	end
	for name, info in pairs(detected) do
		if not self:IsIgnored(name) and not self.byName[name] then
			local adopted, err = pcall(self.Adopt, self, name, info.frame, info.source)
			if adopted then
				self.failures[name] = nil
			else
				self.failures[name] = tostring(err)
			end
		end
	end

	pcall(function() ns.Flyout:ApplyLayout() end)
	if ns.Launcher then ns.Launcher:Refresh() end
end

function Collector:Start()
	if self.started then return end
	self.started = true

	-- Catch buttons that register after login (the common case).
	if LibDBIcon then
		hooksecurefunc(LibDBIcon, "Register", function(_, name)
			if name == ns.ADDON then return end -- never collect our own launcher
			C_Timer.After(0, function()
				if self.started and not self:IsIgnored(name) and not self.byName[name] then
					local frame = LibDBIcon:GetMinimapButton(name)
					if frame then
						local ok, err = pcall(self.Adopt, self, name, frame, "libdbicon")
						if not ok then self.failures[name] = tostring(err) end
						pcall(function() ns.Flyout:ApplyLayout() end)
						if ns.Launcher then ns.Launcher:Refresh() end
					end
				end
			end)
		end)
	end

	self:Rescan()

	-- Addons create their buttons at staggered times after login, so sweep
	-- repeatedly for the first ~30 seconds to catch the late arrivals.
	local sweeps = 0
	local function sweep()
		sweeps = sweeps + 1
		self:Rescan()
		if sweeps < 12 then C_Timer.After(2.5, sweep) end
	end
	C_Timer.After(2, sweep)
end
