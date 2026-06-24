--[[ Halo — Core/Launcher.lua

	The one button that stays on the minimap. Implemented as a LibDataBroker
	"launcher" registered with LibDBIcon-1.0, so it inherits the standard
	minimap-edge drag/positioning behavior players already expect.

	  • Left-click  → toggle the tray
	  • Right-click → open settings
	  • Hover       → optionally open the tray (config), always show a tooltip
]]

local _, ns = ...
local L = ns.L

local Launcher = {}
ns.Launcher = Launcher

local LDB = LibStub("LibDataBroker-1.1", true)
local LibDBIcon = LibStub("LibDBIcon-1.0", true)

local ICON = "Interface\\AddOns\\Halo\\Media\\halo-logo"

local function buildTooltip(tooltip)
	local count = ns.Collector and ns.Collector:Count() or 0
	tooltip:AddLine("|cff66b3ffHalo|r")
	if count == 0 then
		tooltip:AddLine(L["No buttons collected yet"], 0.7, 0.7, 0.7)
	elseif count == 1 then
		tooltip:AddLine((L["%d button collected"]):format(count), 0.7, 0.7, 0.7)
	else
		tooltip:AddLine((L["%d buttons collected"]):format(count), 0.7, 0.7, 0.7)
	end
	tooltip:AddLine(" ")
	tooltip:AddLine(("|cffffffff%s|r  %s"):format(L["Left-click"], L["toggle the button tray"]), 0.6, 0.8, 1)
	tooltip:AddLine(("|cffffffff%s|r  %s"):format(L["Right-click"], L["open settings"]), 0.6, 0.8, 1)
end

function Launcher:Create()
	if self.dataObject or not LDB then return end

	self.dataObject = LDB:NewDataObject(ns.ADDON, {
		type = "launcher",
		text = "Halo",
		icon = ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				ns.Options:Open()
			else
				ns.Flyout:Toggle()
			end
		end,
		OnEnter = function(anchorFrame)
			if ns.db.profile.openOnHover then
				ns.Flyout:Open()
			end
			local GameTooltip = _G.GameTooltip
			GameTooltip:SetOwner(anchorFrame, "ANCHOR_LEFT")
			buildTooltip(GameTooltip)
			GameTooltip:Show()
		end,
		OnLeave = function()
			_G.GameTooltip:Hide()
		end,
		OnTooltipShow = buildTooltip, -- for broker displays that render the object directly
	})

	if LibDBIcon then
		LibDBIcon:Register(ns.ADDON, self.dataObject, ns.db.profile.minimap)

		-- Optional Masque skinning of the launcher button.
		local Masque = LibStub("Masque", true)
		local button = LibDBIcon:GetMinimapButton(ns.ADDON)
		if Masque and button then
			self.masque = Masque:Group("Halo", "Launcher")
			self.masque:AddButton(button, { Icon = button.icon })
		end
	end
end

--- Re-apply saved show/hide state. Safe to call repeatedly.
function Launcher:Refresh()
	if not LibDBIcon then return end
	if ns.db.profile.minimap.hide then
		LibDBIcon:Hide(ns.ADDON)
	else
		LibDBIcon:Show(ns.ADDON)
	end
end

--- The frame of the launcher button itself (for anchoring the tray).
function Launcher:GetButton()
	if LibDBIcon then return LibDBIcon:GetMinimapButton(ns.ADDON) end
end
