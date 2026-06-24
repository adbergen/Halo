--[[ Halo — UI/Flyout.lua

	The tray. A flat dark panel that fades/scales in from the launcher and lays
	the collected buttons out as a reflowing grid (or a radial ring). A search
	box appears once enough buttons are collected.

	Movement is animated: every tile eases toward a target position via a small
	per-frame lerp driver, so reordering, column changes, and add/remove all
	glide instead of snapping. Drag-to-reorder lifts a tile to follow the cursor
	while the others shift to open a gap at the drop position.

	The panel sits at MEDIUM strata to match LibDBIcon's locked buttons, and each
	button is hosted independently so one bad frame can't abort the layout.
]]

local _, ns = ...
local Theme = ns.Theme
local Widgets = ns.Widgets

local Flyout = {}
ns.Flyout = Flyout

local PADDING = 10
local GAP = 8
local SEARCH_H = 22
local SEARCH_THRESHOLD = 10
local EASE = 0.30 -- per-frame interpolation toward target (higher = snappier)

Flyout.tilesByName = {} -- name -> tile (one persistent tile per button)
Flyout.isOpen = false

-- ─── Construction ────────────────────────────────────────────────────

function Flyout:Create()
	if self.panel then return end

	local panel = CreateFrame("Frame", "HaloTray", UIParent)
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
		self:ApplyLayout(true)
	end)
	search:Hide()
	self.search = search

	local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	empty:SetPoint("CENTER")
	empty:SetText(ns.L["No buttons collected yet"])
	empty:Hide()
	self.emptyLabel = empty

	-- Floating ghost shown while dragging (the real tile hides and this stands
	-- in for it, following the cursor).
	local ghost = CreateFrame("Frame", "HaloDragGhost", UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:Hide()
	local glow = ghost:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", -3, 3)
	glow:SetPoint("BOTTOMRIGHT", 3, -3)
	glow:SetColorTexture(unpack(Theme.colors.accent))
	glow:SetAlpha(0.5)
	local gicon = ghost:CreateTexture(nil, "ARTWORK")
	gicon:SetAllPoints()
	ghost.icon = gicon
	self.ghost = ghost

	self:SetupAnimations()
	self:SetupDriver()
end

-- Best icon texture (+ texcoords) to represent a button in the drag ghost.
local function buttonIcon(button)
	local icon = button.icon
	if icon and icon.GetTexture and icon:GetTexture() then
		return icon:GetTexture(), { icon:GetTexCoord() }
	end
	if button.GetRegions then
		for _, region in ipairs({ button:GetRegions() }) do
			if region.GetObjectType and region:IsObjectType("Texture")
				and region.GetTexture and region:GetTexture() then
				return region:GetTexture(), { region:GetTexCoord() }
			end
		end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
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

-- The panel's OnUpdate drives both tile easing and auto-hide.
function Flyout:SetupDriver()
	local elapsed = 0
	self.panel:SetScript("OnUpdate", function(_, dt)
		self:Drive()

		if self.dragging then elapsed = 0; return end -- never auto-hide mid-drag
		if not (self.isOpen and ns.db.profile.autoHide) then return end
		local launcher = ns.Launcher and ns.Launcher:GetButton()
		local editBox = self.search and self.search.editBox
		if MouseIsOver(self.panel) or (launcher and MouseIsOver(launcher))
			or (editBox and editBox:HasFocus()) then
			elapsed = 0
			return
		end
		elapsed = elapsed + dt
		if elapsed > 0.6 then elapsed = 0; self:Close() end
	end)
end

--- Ease every grid tile toward its target each frame (skips the dragged tile,
--- which tracks the cursor, and radial mode, which positions directly).
function Flyout:Drive()
	if self.layoutMode ~= "grid" then return end
	local dragTile = self.dragging and self.dragging.frame.haloTile
	for _, tile in pairs(self.tilesByName) do
		if tile ~= dragTile and tile.tx and tile:IsShown() then
			local x = tile.x + (tile.tx - tile.x) * EASE
			local y = tile.y + (tile.ty - tile.y) * EASE
			if math.abs(tile.tx - x) < 0.5 then x = tile.tx end
			if math.abs(tile.ty - y) < 0.5 then y = tile.ty end
			if x ~= tile.x or y ~= tile.y then
				tile.x, tile.y = x, y
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", self.grid, "TOPLEFT", x, y)
			end
		end
	end
end

-- ─── Layout ──────────────────────────────────────────────────────────

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

--- Get/create this button's persistent tile and (re)host the button in it.
function Flyout:EnsureTile(record, size)
	local tile = self.tilesByName[record.name]
	if not tile then
		tile = Widgets:Tile(self.grid, size)
		self.tilesByName[record.name] = tile
	end
	tile:SetSize(size, size)
	tile:Show()
	local ok, err = pcall(Widgets.HostInTile, Widgets, tile, record.frame)
	if not ok then
		ns.Collector.failures[record.name] = tostring(err)
		return nil
	end
	ns.Collector.failures[record.name] = nil
	pcall(record.frame.Show, record.frame)
	return tile
end

--- Set a grid tile's target. Snap (or first placement) jumps; otherwise the
--- driver eases it there.
function Flyout:Place(tile, tx, ty, snap)
	tile.tx, tile.ty = tx, ty
	if snap or not tile.x then
		tile.x, tile.y = tx, ty
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", self.grid, "TOPLEFT", tx, ty)
	end
end

function Flyout:ApplyLayout(snap)
	if not self.grid then return end

	local p = ns.db.profile
	local total = ns.Collector:Count()
	local radial = (p.layout == "radial")
	self.layoutMode = radial and "radial" or "grid"

	self.searchActive = (not radial) and total >= SEARCH_THRESHOLD
	self.search:SetShown(self.searchActive)

	local buttons = self:GetVisibleButtons()
	local count = #buttons
	local size, spacing = p.tileSize, p.spacing

	-- Hide tiles whose buttons aren't currently shown.
	local shown = {}
	for _, rec in ipairs(buttons) do shown[rec.name] = true end
	for name, tile in pairs(self.tilesByName) do
		if not shown[name] then tile:Hide() end
	end

	local hosted = 0
	if radial and count > 1 then
		local step = (2 * math.pi) / count
		local radius = math.max(size, (count * (size + spacing)) / (2 * math.pi))
		for i, record in ipairs(buttons) do
			local tile = self:EnsureTile(record, size)
			if tile then
				hosted = hosted + 1
				local angle = -math.pi / 2 + (i - 1) * step
				tile.tx = nil -- excluded from the grid driver
				tile:ClearAllPoints()
				tile:SetPoint("CENTER", self.grid, "CENTER",
					math.cos(angle) * radius, math.sin(angle) * radius)
			end
		end
		local dim = (radius + size) * 2
		self.grid:ClearAllPoints()
		self.grid:SetPoint("CENTER", self.panel, "CENTER", 0, 0)
		self.grid:SetSize(dim, dim)
		self.panel:SetSize(dim + PADDING, dim + PADDING)
		Theme:SetPanelOpacity(self.panel, 0)
	else
		-- Width keys off the total (not the filtered count) so search doesn't
		-- shrink the tray.
		local widthCount = self.searchActive and total or count
		local cols = math.max(1, math.min(p.columns, math.max(widthCount, 1)))
		local rows = math.max(1, math.ceil(math.max(count, 1) / cols))
		for i, record in ipairs(buttons) do
			local tile = self:EnsureTile(record, size)
			if tile then
				hosted = hosted + 1
				local col = (i - 1) % cols
				local row = math.floor((i - 1) / cols)
				self:Place(tile, col * (size + spacing), -row * (size + spacing), snap)
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
	self:ApplyLayout(true) -- snap tiles into place; the panel itself fades in
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

--- Grid slot index under a cursor position (grid-local UI coords).
function Flyout:HoverIndex(cx, cy)
	local p = ns.db.profile
	local cell = p.tileSize + p.spacing
	local cols = self.dragCols or 1
	local n = #(self.dragVisible or {})
	local gx, gy = self.grid:GetLeft(), self.grid:GetTop()
	if not gx or not gy then return n end
	-- +0.5 so the target flips at each cell's midpoint (less travel, better feel).
	local col = math.max(0, math.min(cols - 1, math.floor((cx - gx) / cell + 0.5)))
	local row = math.max(0, math.floor((gy - cy) / cell + 0.5))
	return math.max(1, math.min(n, row * cols + col + 1))
end

--- Shift the non-dragged tiles to open a gap at hoverIndex (animated).
function Flyout:ReflowDuringDrag(hoverIndex)
	local p = ns.db.profile
	local size, spacing, cols = p.tileSize, p.spacing, self.dragCols

	local seq = {}
	for _, record in ipairs(self.dragVisible) do
		if record ~= self.dragging then seq[#seq + 1] = record end
	end
	hoverIndex = math.max(1, math.min(#seq + 1, hoverIndex))
	table.insert(seq, hoverIndex, self.dragging)
	self.dragSeq = seq

	for i, record in ipairs(seq) do
		if record ~= self.dragging then
			local tile = record.frame.haloTile
			if tile then
				local col = (i - 1) % cols
				local row = math.floor((i - 1) / cols)
				tile.tx = col * (size + spacing)
				tile.ty = -row * (size + spacing)
			end
		end
	end
end

function Flyout:BeginDrag(name)
	if ns.db.profile.layout ~= "grid" then return end
	if self.searchActive and (self.searchText or "") ~= "" then return end
	local record = ns.Collector.byName[name]
	local tile = record and record.frame.haloTile
	if not tile then return end

	self.dragging = record
	self.dragVisible = self:GetVisibleButtons()
	self.dragCols = math.max(1, math.min(ns.db.profile.columns, math.max(#self.dragVisible, 1)))
	self.dragHover = 1
	for i, rec in ipairs(self.dragVisible) do
		if rec == record then self.dragHover = i break end
	end

	local size = ns.db.profile.tileSize
	tile:Hide() -- the ghost stands in for the real tile while dragging

	-- Populate and lift the ghost.
	local ghost = self.ghost
	local tex, coords = buttonIcon(record.frame)
	ghost.icon:SetTexture(tex)
	if coords and #coords >= 4 then
		ghost.icon:SetTexCoord(unpack(coords))
	else
		ghost.icon:SetTexCoord(0, 1, 0, 1)
	end
	ghost:SetSize(size, size)
	ghost:SetAlpha(0)
	ghost:Show()
	ns.Animation.Run("halo_lift", 0, 1, ns.Animation.ANIM.LIFT, function(v)
		local s = size * (1 + 0.12 * v)
		ghost:SetSize(s, s)
		ghost:SetAlpha(0.95 * v)
	end)

	-- Follow the cursor and open the gap under it.
	ghost:SetScript("OnUpdate", function()
		local scale = UIParent:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		cx, cy = cx / scale, cy / scale
		ghost:ClearAllPoints()
		ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
		local idx = self:HoverIndex(cx, cy)
		if idx ~= self.dragHover then
			self.dragHover = idx
			self:ReflowDuringDrag(idx)
		end
	end)
	self:ReflowDuringDrag(self.dragHover)
end

function Flyout:EndDrag()
	local record = self.dragging
	if not record then return end
	local ghost = self.ghost
	ghost:SetScript("OnUpdate", nil)
	ns.Animation.Cancel("halo_lift")

	local seq = self.dragSeq
	local p = ns.db.profile
	local size, spacing, cols = p.tileSize, p.spacing, self.dragCols

	-- Where the dragged button ends up, and commit the new order.
	local idx = self.dragHover or 1
	if seq then
		for i, rec in ipairs(seq) do if rec == record then idx = i break end end
		for i, rec in ipairs(seq) do ns.db.profile.order[rec.name] = i end
	end
	self.dragging, self.dragSeq, self.dragHover, self.dragVisible = nil, nil, nil, nil

	local function finish()
		ghost:Hide()
		ghost:SetSize(size, size)
		ghost:SetAlpha(0.95)
		self:ApplyLayout(true) -- real tile reappears, snapped where the ghost landed
	end

	-- Fly the ghost to its landing slot, then fade it out and reveal the tile.
	local col = (idx - 1) % cols
	local row = math.floor((idx - 1) / cols)
	local gx, gy = self.grid:GetLeft(), self.grid:GetTop()
	local sx, sy = ghost:GetCenter()
	if gx and gy and sx and sy then
		local ex = gx + col * (size + spacing) + size / 2
		local ey = gy - row * (size + spacing) - size / 2
		ns.Animation.Run("halo_drop", 0, 1, ns.Animation.ANIM.DROP_MOVE, function(_, prog)
			ghost:ClearAllPoints()
			ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx + (ex - sx) * prog, sy + (ey - sy) * prog)
		end, function()
			ns.Animation.Run("halo_dropfade", 0.95, 0, ns.Animation.ANIM.DROP_FADE,
				function(a) ghost:SetAlpha(a) end, finish)
		end)
	else
		finish()
	end
end

--- Move a button to targetIndex in the saved tray order and relayout. Used by
--- the drop handler and exposed for tests.
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
