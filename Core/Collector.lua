--[[ Halo — Core/Collector.lua

	Owns the lifecycle of every collected button: adopting it off the minimap,
	keeping it pinned inside the tray, and releasing it back when the user opts
	a button out (or disables Halo).

	The tricky part is that LibDBIcon actively re-anchors its buttons to the
	minimap edge (its updatePosition calls button:SetPoint). To win that fight
	for good, Halo takes over each adopted button's SetPoint — replacing it with
	a no-op so nothing but Halo can move it — and positions buttons through the
	saved original. Release restores the original SetPoint.

	Safety: only ever touch non-secure, non-forbidden frames (minimap buttons
	are), and remember each button's original parent + anchors so release is
	lossless.
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
Collector.placing = false -- reserved for layout coordination
Collector.failures = {}   -- name -> error string from hosting (shown by /halo scan)

local function blockedSetPoint() end -- installed on adopted buttons

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

	frame:SetParent(ns.Flyout.grid) -- off the minimap immediately
	frame:SetScale(1)

	-- Take sole authority over this button's position. LibDBIcon (and others)
	-- can call SetPoint all they like; it will do nothing until release.
	if not frame.haloSetPoint then
		frame.haloSetPoint = frame.SetPoint
		frame.SetPoint = blockedSetPoint
	end

	-- Drag-to-reorder. The button's own minimap-drag is neutralized by the
	-- SetPoint block, so we repurpose its drag to reorder the tray. WoW still
	-- distinguishes a click from a drag, so left-clicking the button works.
	if not frame.haloDragHooked then
		frame.haloDragHooked = true
		if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end
		frame:HookScript("OnDragStart", function() ns.Flyout:BeginDrag(name) end)
		frame:HookScript("OnDragStop", function() ns.Flyout:EndDrag() end)
		-- Fallback: EndDrag is idempotent, so also end on mouse-up in case a
		-- particular button doesn't fire OnDragStop reliably.
		frame:HookScript("OnMouseUp", function() ns.Flyout:EndDrag() end)
	end

	self.byName[name] = record
	self.byFrame[frame] = record
	self.order[#self.order + 1] = name
end

function Collector:Release(name)
	local record = self.byName[name]
	if not record then return end

	-- Hand positioning back before restoring the original anchors.
	if record.frame.haloSetPoint then
		record.frame.SetPoint = record.frame.haloSetPoint
		record.frame.haloSetPoint = nil
	end
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

--- Every button name we know about (collected or detected) — for the options list.
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

--- Diagnostic: report each collected button's actual render state.
function Collector:Dump()
	local hosted = (ns.Flyout and ns.Flyout.lastHosted) or -1
	local lines = { ("|cff66b3ffHalo|r [v4] collected %d, last layout hosted %d:")
		:format(self:Count(), hosted) }
	for _, record in ipairs(self:GetButtons()) do
		local b = record.frame
		local parent = b:GetParent()
		local pname = (parent and parent.GetName and parent:GetName()) or "?"
		local icon = b.icon
		local tex = icon and icon.GetTexture and icon:GetTexture()
		lines[#lines + 1] = ("  %s shown=%s a=%.1f parent=%s strata=%s lvl=%d w=%d icon=%s")
			:format(
				record.name,
				tostring(b:IsShown()),
				b:GetAlpha() or 0,
				pname,
				b:GetFrameStrata() or "?",
				b:GetFrameLevel() or 0,
				math.floor((b:GetWidth() or 0) + 0.5),
				tex and "yes" or "NO")
	end
	for name, err in pairs(self.failures) do
		lines[#lines + 1] = ("|cffff5555host failed|r [%s]: %s"):format(name, err)
	end
	return lines
end

--- Adopt anything new, release anything now ignored, then relayout.
function Collector:Rescan()
	if not self.started then return end

	-- Release collected buttons the user now wants back on the minimap: ones they
	-- opted out of, and Blizzard frames whose opt-in toggle was turned back off.
	local toRelease = {}
	for name, record in pairs(self.byName) do
		if self:IsIgnored(name) then
			toRelease[#toRelease + 1] = name
		elseif record.source == "blizzard" and not Detector:IsOptedIn(name) then
			toRelease[#toRelease + 1] = name
		end
	end
	for _, name in ipairs(toRelease) do self:Release(name) end

	-- Adopt anything newly detected and not opted out.
	for name, info in pairs(Detector:Scan()) do
		if not self:IsIgnored(name) and not self.byName[name] then
			self:Adopt(name, info.frame, info.source)
		end
	end

	ns.Flyout:ApplyLayout()
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
						self:Adopt(name, frame, "libdbicon")
						ns.Flyout:ApplyLayout()
						if ns.Launcher then ns.Launcher:Refresh() end
					end
				end
			end)
		end)
	end

	self:Rescan()
end
