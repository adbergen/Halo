--[[ Halo — UI/Flyout.lua

	The tray: a flat dark panel that fades/scales in from the launcher and lays
	the collected buttons out in a reflowing grid. It anchors itself to whatever
	side of the screen the launcher lives on so it always opens inward, and can
	auto-hide when the cursor leaves.

	`ApplyLayout` is the single place that anchors collected buttons. It raises
	`Collector.placing` while it works so the per-button SetPoint guard doesn't
	mistake our own anchoring for an addon fighting back.
]]

local _, ns = ...
local Theme = ns.Theme
local Widgets = ns.Widgets

local Flyout = {}
ns.Flyout = Flyout

local PADDING = 10
local GAP = 8 -- gap between launcher and panel

Flyout.tiles = {}
Flyout.isOpen = false

-- ─── Construction ────────────────────────────────────────────────────

function Flyout:Create()
	if self.panel then return end

	local panel = CreateFrame("Frame", "HaloTray", UIParent)
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:Hide()
	panel:SetAlpha(0)
	Theme:StylePanel(panel)
	self.panel = panel

	local grid = CreateFrame("Frame", nil, panel)
	grid:SetPoint("TOPLEFT", PADDING, -PADDING)
	self.grid = grid

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
		if s.SetScaleFrom then -- modern API
			s:SetScaleFrom(from, from); s:SetScaleTo(to, to)
		elseif s.SetFromScale then -- legacy API
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
	self.animOut:SetScript("OnFinished", function()
		panel:Hide(); panel:SetAlpha(1)
	end)
end

function Flyout:SetupAutoHide()
	local elapsed, panel = 0, self.panel
	panel:SetScript("OnUpdate", function(_, dt)
		if not (self.isOpen and ns.db.profile.autoHide) then return end
		local launcher = ns.Launcher and ns.Launcher:GetButton()
		if MouseIsOver(panel) or (launcher and MouseIsOver(launcher)) then
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

function Flyout:ApplyLayout()
	if not self.grid then return end

	local p = ns.db.profile
	local buttons = ns.Collector:GetButtons()
	local count = #buttons
	local size, spacing = p.tileSize, p.spacing
	local cols = math.max(1, math.min(p.columns, math.max(count, 1)))
	local rows = math.max(1, math.ceil(math.max(count, 1) / cols))

	ns.Collector.placing = true

	-- Hide unused pooled tiles up front.
	for i = count + 1, #self.tiles do self.tiles[i]:Hide() end

	for index, record in ipairs(buttons) do
		local tile = self.tiles[index]
		if not tile then
			tile = Widgets:Tile(self.grid, size)
			self.tiles[index] = tile
		end
		tile:SetSize(size, size)
		tile:Show()

		local col = (index - 1) % cols
		local row = math.floor((index - 1) / cols)
		tile:ClearAllPoints()
		tile:SetPoint("TOPLEFT", self.grid, "TOPLEFT",
			col * (size + spacing), -row * (size + spacing))

		-- Hosting touches a foreign button; never let one bad frame break layout.
		if pcall(Widgets.HostInTile, Widgets, tile, record.frame) then
			pcall(record.frame.Show, record.frame)
		end
	end

	local gridW = cols * size + (cols - 1) * spacing
	local gridH = rows * size + (rows - 1) * spacing
	self.grid:SetSize(math.max(gridW, 1), math.max(gridH, 1))
	self.panel:SetSize(gridW + PADDING * 2, gridH + PADDING * 2)
	self.panel:SetScale(p.trayScale)
	Theme:SetPanelOpacity(self.panel, p.trayOpacity)

	self.emptyLabel:SetShown(count == 0)
	ns.Collector.placing = false

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
	local yOff = top and -GAP or GAP

	panel:ClearAllPoints()
	panel:SetPoint(point, anchorTo, relPoint, 0, yOff)
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
	self.animIn:Stop()
	self.animOut:Play()
end

function Flyout:Toggle()
	if self.isOpen then self:Close() else self:Open() end
end
