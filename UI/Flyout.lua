--[[ Halo — UI/Flyout.lua

	The tray: a flat dark panel that fades/scales in from the launcher. It lays
	the collected buttons out either as a reflowing grid or as a ring (radial
	mode, where the panel background hides so buttons appear to orbit the
	launcher). A search box appears once enough buttons are collected.

	The panel sits at MEDIUM strata to match LibDBIcon's buttons, and each button
	is hosted independently so one bad frame can't abort the whole layout.
]]

local _, ns = ...
local Theme = ns.Theme
local Widgets = ns.Widgets

local Flyout = {}
ns.Flyout = Flyout

local PADDING = 10
local GAP = 8           -- gap between launcher and panel
local SEARCH_H = 22     -- search box height
local SEARCH_THRESHOLD = 10 -- show search once this many buttons are collected

Flyout.tiles = {}
Flyout.isOpen = false

-- ─── Construction ────────────────────────────────────────────────────

function Flyout:Create()
	if self.panel then return end

	local panel = CreateFrame("Frame", "HaloTray", UIParent)
	-- MEDIUM matches LibDBIcon's locked button strata so buttons render above
	-- the panel background (as its children).
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	panel:SetAlpha(0)
	Theme:StylePanel(panel)
	self.panel = panel

	local grid = CreateFrame("Frame", nil, panel)
	self.grid = grid

	local search = Widgets:EditBox(panel, 120, ns.L["Search"], function(text)
		self.searchText = text
		self:ApplyLayout()
	end)
	search:Hide()
	self.search = search

	local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	empty:SetPoint("CENTER")
	empty:SetText(ns.L["No buttons collected yet"])
	empty:Hide()
	self.emptyLabel = empty

	self:SetupAnimations()
	self:SetupAutoHide()
end

function Flyout:SetupAnimations()
	local panel = self.panel

	local function scaleAnim(group, from, to)
		local s = group:CreateAnimation("Scale")
		s:SetDuration(0.16)
		s:SetSmoothing("OUT")
		if s.SetScaleFrom then
			s:SetScaleFrom(from, from); s:SetScaleTo(to, to)
		elseif s.SetFromScale then
			s:SetFromScale(from, from); s:SetToScale(to, to)
		end
		if s.SetOrigin then s:SetOrigin("CENTER", 0, 0) end
	end

	self.animIn = panel:CreateAnimationGroup()
	local fadeIn = self.animIn:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.16); fadeIn:SetSmoothing("OUT")
	scaleAnim(self.animIn, 0.94, 1)
	self.animIn:SetScript("OnFinished", function() panel:SetAlpha(1) end)

	self.animOut = panel:CreateAnimationGroup()
	local fadeOut = self.animOut:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.12); fadeOut:SetSmoothing("IN")
	self.animOut:SetScript("OnFinished", function() panel:Hide(); panel:SetAlpha(1) end)
end

function Flyout:SetupAutoHide()
	local elapsed, panel = 0, self.panel
	panel:SetScript("OnUpdate", function(_, dt)
		if self.dragging then elapsed = 0; return end -- never auto-hide mid-drag
		if not (self.isOpen and ns.db.profile.autoHide) then return end
		local launcher = ns.Launcher and ns.Launcher:GetButton()
		local editBox = self.search and self.search.editBox
		if MouseIsOver(panel) or (launcher and MouseIsOver(launcher))
			or (editBox and editBox:HasFocus()) then
			elapsed = 0
			return
		end
		elapsed = elapsed + dt
		if elapsed > 0.6 then
			elapsed = 0
			self:Close()
		end
	end)
end

-- ─── Layout ──────────────────────────────────────────────────────────

--- Collected buttons honoring the search filter (when the search box is shown).
function Flyout:GetVisibleButtons()
	local all = ns.Collector:GetButtons()
	local q = self.searchActive and self.searchText
	if not q or q == "" then return all end
	q = q:lower()
	local out = {}
	for _, record in ipairs(all) do
		local label = record.name:gsub("^LibDBIcon10_", ""):lower()
		if label:find(q, 1, true) then out[#out + 1] = record end
	end
	return out
end

--- Create/reuse tile #index, position it, and host the button. Returns success.
function Flyout:HostAt(index, record, size, point, x, y)
	local ok, err = pcall(function()
		local tile = self.tiles[index]
		if not tile then
			tile = Widgets:Tile(self.grid, size)
			self.tiles[index] = tile
		end
		tile:SetSize(size, size)
		tile:Show()
		tile:ClearAllPoints()
		tile:SetPoint(point, self.grid, point, x, y)
		Widgets:HostInTile(tile, record.frame)
		record.frame:Show()
	end)
	if ok then
		ns.Collector.failures[record.name] = nil
		return true
	end
	ns.Collector.failures[record.name] = tostring(err)
	return false
end

function Flyout:ApplyLayout()
	if not self.grid then return end

	local p = ns.db.profile
	local total = ns.Collector:Count()
	local radial = (p.layout == "radial")

	-- Search box only in grid mode, and only when there are enough buttons.
	self.searchActive = (not radial) and total >= SEARCH_THRESHOLD
	self.search:SetShown(self.searchActive)

	local buttons = self:GetVisibleButtons()
	local count = #buttons
	local size, spacing = p.tileSize, p.spacing

	for i = count + 1, #self.tiles do self.tiles[i]:Hide() end

	local hosted = 0
	if radial and count > 1 then
		-- Ring of buttons around the panel centre; background hidden.
		local step = (2 * math.pi) / count
		local radius = math.max(size, (count * (size + spacing)) / (2 * math.pi))
		for index, record in ipairs(buttons) do
			local angle = -math.pi / 2 + (index - 1) * step
			if self:HostAt(index, record, size, "CENTER",
				math.cos(angle) * radius, math.sin(angle) * radius) then
				hosted = hosted + 1
			end
		end
		local dim = (radius + size) * 2
		self.grid:ClearAllPoints()
		self.grid:SetPoint("CENTER", self.panel, "CENTER", 0, 0)
		self.grid:SetSize(dim, dim)
		self.panel:SetSize(dim + PADDING, dim + PADDING)
		Theme:SetPanelOpacity(self.panel, 0)
	else
		local cols = math.max(1, math.min(p.columns, math.max(count, 1)))
		local rows = math.max(1, math.ceil(math.max(count, 1) / cols))
		for index, record in ipairs(buttons) do
			local col = (index - 1) % cols
			local row = math.floor((index - 1) / cols)
			if self:HostAt(index, record, size, "TOPLEFT",
				col * (size + spacing), -row * (size + spacing)) then
				hosted = hosted + 1
			end
		end
		local searchOff = self.searchActive and (SEARCH_H + 6) or 0
		local gridW = cols * size + (cols - 1) * spacing
		local gridH = rows * size + (rows - 1) * spacing
		self.grid:ClearAllPoints()
		self.grid:SetPoint("TOPLEFT", self.panel, "TOPLEFT", PADDING, -PADDING - searchOff)
		self.grid:SetSize(math.max(gridW, 1), math.max(gridH, 1))
		self.panel:SetSize(gridW + PADDING * 2, gridH + PADDING * 2 + searchOff)
		Theme:SetPanelOpacity(self.panel, p.trayOpacity)

		if self.searchActive then
			self.search:ClearAllPoints()
			self.search:SetPoint("TOPLEFT", self.panel, "TOPLEFT", PADDING, -PADDING)
			self.search:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", -PADDING, -PADDING)
		end
	end
	self.lastHosted = hosted

	self.panel:SetScale(p.trayScale)
	self.emptyLabel:SetShown(count == 0)
	self:Anchor()
end

--- Anchor the panel to the launcher so it opens toward screen center.
function Flyout:Anchor()
	local panel = self.panel
	local anchorTo = (ns.Launcher and ns.Launcher:GetButton()) or Minimap
	if not anchorTo then return end

	local cx, cy = anchorTo:GetCenter()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	cx, cy = cx or sw / 2, cy or sh / 2

	local right = cx > sw / 2
	local top = cy > sh / 2
	local horiz = right and "RIGHT" or "LEFT"
	local point = (top and "TOP" or "BOTTOM") .. horiz
	local relPoint = (top and "BOTTOM" or "TOP") .. horiz

	panel:ClearAllPoints()
	panel:SetPoint(point, anchorTo, relPoint, 0, top and -GAP or GAP)
end

-- ─── Open / close ────────────────────────────────────────────────────

function Flyout:Open()
	if self.isOpen then return end
	self.isOpen = true
	self:ApplyLayout()
	self.animOut:Stop()
	self.panel:SetAlpha(0)
	self.panel:Show()
	self.animIn:Play()
end

function Flyout:Close()
	if not self.isOpen then return end
	self.isOpen = false
	if self.search and self.search.editBox then self.search.editBox:ClearFocus() end
	self.animIn:Stop()
	self.animOut:Play()
end

function Flyout:Toggle()
	if self.isOpen then self:Close() else self:Open() end
end

-- ─── Drag-to-reorder (grid mode) ─────────────────────────────────────

--- Start dragging a collected button; its tile follows the cursor.
function Flyout:BeginDrag(name)
	if ns.db.profile.layout ~= "grid" then return end
	if self.searchActive and (self.searchText or "") ~= "" then return end
	local record = ns.Collector.byName[name]
	local tile = record and record.frame.haloTile
	if not tile then return end

	self.dragging = record
	tile:SetFrameLevel(tile:GetFrameLevel() + 20)
	tile:SetScript("OnUpdate", function()
		local scale = tile:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		tile:ClearAllPoints()
		tile:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
	end)
end

--- Drop the dragged button into the slot under the cursor and persist order.
function Flyout:EndDrag()
	local record = self.dragging
	if not record then return end
	self.dragging = nil

	local tile = record.frame.haloTile
	if tile then tile:SetScript("OnUpdate", nil) end

	local p = ns.db.profile
	local count = #self:GetVisibleButtons()
	local cols = math.max(1, math.min(p.columns, math.max(count, 1)))
	local cell = p.tileSize + p.spacing

	local target = count
	local gx, gy = self.grid:GetLeft(), self.grid:GetTop()
	if gx and gy then
		local scale = self.grid:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		cx, cy = cx / scale, cy / scale
		local col = math.max(0, math.min(cols - 1, math.floor((cx - gx) / cell)))
		local row = math.max(0, math.floor((gy - cy) / cell))
		target = row * cols + col + 1
	end
	self:MoveButton(record.name, target)
end

--- Move a button to targetIndex in the saved tray order and relayout.
function Flyout:MoveButton(name, targetIndex)
	local names = {}
	for _, record in ipairs(self:GetVisibleButtons()) do names[#names + 1] = record.name end

	local from
	for i, n in ipairs(names) do
		if n == name then from = i; table.remove(names, i) break end
	end
	if not from then return end

	targetIndex = math.max(1, math.min(#names + 1, targetIndex))
	table.insert(names, targetIndex, name)
	for i, n in ipairs(names) do ns.db.profile.order[n] = i end

	self:ApplyLayout()
end
