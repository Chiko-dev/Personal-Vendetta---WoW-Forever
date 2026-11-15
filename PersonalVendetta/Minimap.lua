--[[-------------------------------------------------------------------------
  Personal Vendetta -- Minimap button
  Left-click: settings.  Right-click: show/hide the window.  Drag: move it
  around the rim.

  Always shown. Also registered in the addon compartment (the drawer button
  on Forever's minimap) through the .toc, as a second way in.
---------------------------------------------------------------------------]]

local ADDON, ns = ...


local btn

local Minimap_ = {}
ns.Minimap = Minimap_

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- ===========================================================================
-- Placement
-- ===========================================================================

local function place(angle)
	if not btn or not Minimap then return end
	local rad = math.rad(angle or 215)
	local radius = (Minimap:GetWidth() / 2) + 10
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function cursorAngle()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	return math.deg(atan2(py - my, px - mx)) % 360
end

-- ===========================================================================
-- Tooltip
-- ===========================================================================

local function showTooltip(self)
	if not GameTooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("|cff9933ffPersonal Vendetta|r")
	local near = ns.Radar and ns.Radar:Count() or 0
	GameTooltip:AddLine(string.format("%d on the list%s", ns.List:Count(),
		near > 0 and (", |cffff4444" .. near .. " near|r") or ""), 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("|cffffd100Left-click|r  settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffd100Right-click|r  show/hide window", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffd100Drag|r  move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

-- ===========================================================================
-- Construction
-- ===========================================================================

local function build()
	if not Minimap then return end

	btn = CreateFrame("Button", "PersonalVendettaMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	-- The icon carries its own dark disc, so it sits where Blizzard's grey
	-- background circle would. If the file ever fails to load, the raid
	-- skull stands in rather than an empty green square.
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(21, 21)
	icon:SetPoint("TOPLEFT", 6, -5)
	if not icon:SetTexture(ns.ICON) then
		icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	end
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	btn:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			ns.Overlay.Toggle()
			ns.Fire("SETTINGS_CHANGED")
		else
			ns.Settings:Toggle()
		end
	end)

	-- Press-in nudge on the icon, like Blizzard's own minimap buttons.
	btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 7, -6) end)
	btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 6, -5) end)

	btn:SetScript("OnDragStart", function(self)
		self.dragging = true
		if GameTooltip then GameTooltip:Hide() end
		self:SetScript("OnUpdate", function()
			local a = cursorAngle()
			ns.db.settings.minimap.angle = a
			place(a)
		end)
	end)
	btn:SetScript("OnDragStop", function(self)
		self.dragging = nil
		self:SetScript("OnUpdate", nil)
		icon:SetPoint("TOPLEFT", 6, -5)
	end)

	btn:SetScript("OnEnter", function(self)
		if not self.dragging then showTooltip(self) end
	end)
	btn:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)

	place(ns.db.settings.minimap.angle)
end

-- ===========================================================================
-- Public
-- ===========================================================================

-- Always there: no hide option, by design.
ns.On("DB_READY", function()
	build()
	if btn then btn:Show() end
end)

-- The addon compartment calls this by name; see the .toc.
function PersonalVendetta_OnAddonCompartmentClick(_, mouse)
	if mouse == "RightButton" then
		ns.Overlay.Toggle()
		ns.Fire("SETTINGS_CHANGED")
	else
		ns.Settings:Toggle()
	end
end
