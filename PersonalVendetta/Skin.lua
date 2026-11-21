--[[-------------------------------------------------------------------------
  Personal Vendetta -- Skin
  The Forever look, built from what the client itself uses for its own
  windows (Legacy Challenges, Professions): the portrait frame, side tabs,
  gold collapsible headers, card art, the Legacy progress bar, the search
  box and the Filter dropdown.

  Every helper checks that the template or atlas exists on this client and
  falls back to plain textures when it does not, so a missing piece of art
  never takes a window down with it.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Skin = {}
ns.Skin = Skin

-- Forever's palette, for the places drawn by hand.
Skin.GOLD = { 1, 0.82, 0 }
Skin.TEXT = { 0.95, 0.9, 0.8 }
Skin.DIM = { 0.62, 0.58, 0.5 }

-- A template's child region, only if it really is one.
local function child(f, key)
	local v = f and f[key]
	return type(v) == "table" and v or nil
end
Skin.Child = child

local function try(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

-- A frame from a template when the client has it, else a bare one.
function Skin.Make(kind, parent, template, name)
	if template then
		local ok, f = pcall(CreateFrame, kind, name, parent, template)
		if ok and f then return f, true end
	end
	return CreateFrame(kind, name, parent), false
end

function Skin.HasAtlas(atlas)
	if not atlas or not C_Texture or not C_Texture.GetAtlasInfo then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
	return ok and info ~= nil
end

local function color(tex, c)
	if not c then return end
	if tex.SetColorTexture then
		tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	else
		tex:SetTexture("Interface\\Buttons\\WHITE8X8")
		tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end
end
Skin.Color = color

-- Put an atlas on a texture; a flat colour when the atlas is missing.
function Skin.Atlas(tex, atlas, useSize, fallback)
	if Skin.HasAtlas(atlas) and tex.SetAtlas then
		local ok = pcall(tex.SetAtlas, tex, atlas, useSize and true or false)
		if ok then return true end
	end
	color(tex, fallback)
	return false
end

function Skin.Texture(parent, layer, atlas, fallback, sub)
	local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
	Skin.Atlas(t, atlas, false, fallback)
	return t
end

function Skin.Text(parent, font, str, width, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	if width then
		fs:SetWidth(width)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
	end
	if str then fs:SetText(str) end
	if r then fs:SetTextColor(r, g, b) end
	return fs
end

-- ===========================================================================
-- Panels: a thin Forever border around any frame
-- ===========================================================================

-- The tooltip nine-slice: thin, scales to any size, and looks like the rest
-- of the client. Pieces are drawn on the frame itself, under its children.
function Skin.Panel(frame, layout, alpha)
	local applied = false
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
		applied = pcall(NineSliceUtil.ApplyLayoutByName, frame, layout or "TooltipDefaultLayout")
	end
	if applied and NineSlicePanelMixin then
		frame.SetBorderTint = function(self, r, g, b, a)
			if NineSlicePanelMixin.SetBorderColor then pcall(NineSlicePanelMixin.SetBorderColor, self, r, g, b, a) end
		end
		frame.SetCenterTint = function(self, r, g, b, a)
			if NineSlicePanelMixin.SetCenterColor then pcall(NineSlicePanelMixin.SetCenterColor, self, r, g, b, a) end
		end
	elseif frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame.SetBorderTint = function(self, r, g, b, a) self:SetBackdropBorderColor(r, g, b, a) end
		frame.SetCenterTint = function(self, r, g, b, a) self:SetBackdropColor(r, g, b, a) end
	else
		local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		bg:SetAllPoints()
		color(bg, { 0.05, 0.04, 0.03, 0.9 })
		frame.SetBorderTint = function() end
		frame.SetCenterTint = function(_, r, g, b, a) color(bg, { r, g, b, a }) end
	end
	frame:SetBorderTint(1, 1, 1, 1)
	frame:SetCenterTint(0.06, 0.045, 0.03, alpha or 0.9)
	return frame
end

-- ===========================================================================
-- Windows
-- ===========================================================================

-- A Forever window: round portrait top left, title, close button, the
-- stone background. Movable, closes with Escape.
function Skin.Window(name, width, height, title, icon, background)
	local f, framed = Skin.Make("Frame", UIParent, "PortraitFrameTemplate", name)
	if not framed then
		f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
		Skin.Panel(f, "TooltipDefaultLayout", 0.95)
		local t = Skin.Text(f, "GameFontNormal", title)
		t:SetPoint("TOP", 0, -8)
		f.fallbackTitle = t
		local close = Skin.Make("Button", f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		close:SetScript("OnClick", function() f:Hide() end)
		f.CloseButton = close
	end
	f.framed = framed
	f:SetSize(width, height)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()

	if framed then
		local tc = child(f, "TitleContainer")
		if f.SetTitle then try(f.SetTitle, f, title)
		elseif tc and child(tc, "TitleText") then tc.TitleText:SetText(title) end
		local portrait = child(child(f, "PortraitContainer"), "portrait")
		if icon and f.SetPortraitToAsset then
			try(f.SetPortraitToAsset, f, icon)
		elseif icon and portrait then
			portrait:SetTexture(icon)
		end
	end

	-- The parchment-and-stone page behind the content.
	if background ~= false then
		local bg = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		bg:SetPoint("TOPLEFT", 2, -21)
		bg:SetPoint("BOTTOMRIGHT", -2, 2)
		if not Skin.Atlas(bg, background or "Legacy-Challenge-BG", false) then
			bg:Hide()
		end
		f.pageBg = bg
	end

	if type(UISpecialFrames) == "table" and name then
		table.insert(UISpecialFrames, name)
	end
	return f
end

-- ===========================================================================
-- Side tabs: the big square tabs down the right edge
-- ===========================================================================

function Skin.SideTab(parent, icon, tooltip, onClick)
	local t, templated = Skin.Make("Frame", parent, "LargeSideTabButtonTemplate")
	if templated and child(t, "Icon") then
		t.Icon:SetTexture(icon)
	else
		t = CreateFrame("Button", nil, parent)
		t:SetSize(44, 44)
		local bg = t:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		color(bg, { 0.12, 0.09, 0.06, 0.95 })
		t.Icon = t:CreateTexture(nil, "ARTWORK")
		t.Icon:SetPoint("TOPLEFT", 4, -4)
		t.Icon:SetPoint("BOTTOMRIGHT", -4, 4)
		t.Icon:SetTexture(icon)
		t.SelectedTexture = t:CreateTexture(nil, "OVERLAY")
		t.SelectedTexture:SetAllPoints()
		color(t.SelectedTexture, { 1, 0.82, 0, 0.25 })
		if t.SelectedTexture.SetBlendMode then t.SelectedTexture:SetBlendMode("ADD") end
		local hl = t:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		color(hl, { 1, 1, 1, 0.15 })
	end
	t.tooltip = tooltip
	t:EnableMouse(true)
	t:SetScript("OnMouseUp", function(self, button)
		if self.OnMouseUp and SidePanelTabButtonMixin and SidePanelTabButtonMixin.OnMouseUp then
			pcall(SidePanelTabButtonMixin.OnMouseUp, self, button, true)
		end
		if button == "LeftButton" and onClick then onClick(self) end
	end)
	if t:HasScript("OnClick") then t:SetScript("OnClick", function(self) if onClick then onClick(self) end end) end
	t:SetScript("OnEnter", function(self)
		if not GameTooltip or not self.tooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.tooltip, 1, 1, 1)
		if self.tooltipLine then GameTooltip:AddLine(self.tooltipLine, 0.8, 0.8, 0.8, true) end
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	t.SetSelected = function(self, on)
		if self.SetChecked and SidePanelTabButtonMixin then pcall(self.SetChecked, self, on) end
		if self.SelectedTexture then self.SelectedTexture:SetShown(on and true or false) end
		self.selected = on and true or false
	end
	-- Mouse-up is the template's click; tests and the keyboard use Click().
	t.Click = function(self) if onClick then onClick(self) end end
	return t
end

-- ===========================================================================
-- Buttons
-- ===========================================================================

-- The red Forever panel button.
function Skin.Button(parent, label, w, h, small)
	local b, templated = Skin.Make("Button", parent, "UIPanelButtonTemplate")
	if not templated then
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		color(bg, { 0.45, 0.08, 0.06, 0.95 })
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		color(hl, { 1, 1, 1, 0.15 })
		b:SetNormalFontObject(small and "GameFontNormalSmall" or "GameFontNormal")
		b:SetHighlightFontObject(small and "GameFontHighlightSmall" or "GameFontHighlight")
		b:SetDisabledFontObject(small and "GameFontDisableSmall" or "GameFontDisable")
	elseif small then
		b:SetNormalFontObject("GameFontNormalSmall")
		b:SetHighlightFontObject("GameFontHighlightSmall")
		b:SetDisabledFontObject("GameFontDisableSmall")
	end
	b:SetSize(w, h or 22)
	b:SetText(label)
	return b
end

-- A compact button drawn with the Legacy sub-tab art: for the HUD window,
-- where the panel button is too tall.
function Skin.FlatButton(parent, label, w, h, tint)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h or 18)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	Skin.Atlas(b.bg, "Legacy-Challenge-Left-Sub-Tab", false, { 0.2, 0.14, 0.09, 0.95 })
	if tint then b.bg:SetVertexColor(tint[1], tint[2], tint[3]) end
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	if not Skin.Atlas(hl, "Legacy-Challenge-Left-Sub-Tab-selected", false) then
		color(hl, { 1, 1, 1, 0.15 })
	end
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(label)
	b.SetLabel = function(self, t) self.text:SetText(t) end
	b.GetLabel = function(self) return self.text:GetText() end
	return b
end

-- ===========================================================================
-- Lists: gold collapsible headers and the sub-tab rows under them
-- ===========================================================================

function Skin.Header(parent, width, onClick)
	local h = CreateFrame("Button", nil, parent)
	h:SetSize(width, 25)
	local n = h:CreateTexture(nil, "BACKGROUND")
	n:SetAllPoints()
	Skin.Atlas(n, "common-button-list-collapseExpand", false, { 0.32, 0.22, 0.1, 0.95 })
	local hl = h:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	if Skin.Atlas(hl, "common-button-list-collapseExpand", false) then
		hl:SetAlpha(0.4)
		if hl.SetBlendMode then hl:SetBlendMode("ADD") end
	else
		color(hl, { 1, 1, 1, 0.08 })
	end
	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetSize(14, 14)
	h.icon:SetPoint("RIGHT", -8, 0)
	h.sign = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.sign:SetPoint("CENTER", h.icon, "CENTER")
	h.text = h:CreateFontString(nil, "OVERLAY", _G.Game15Font_Shadow and "Game15Font_Shadow" or "GameFontNormal")
	h.text:SetPoint("LEFT", 8, 0)
	h.text:SetPoint("RIGHT", h.icon, "LEFT", -4, 0)
	h.text:SetJustifyH("LEFT")
	h.text:SetWordWrap(false)
	h.text:SetTextColor(Skin.GOLD[1], Skin.GOLD[2], Skin.GOLD[3])
	h.SetCollapsed = function(self, collapsed)
		self.collapsed = collapsed and true or false
		local atlas = collapsed and "common-button-list-plus" or "common-button-list-minus"
		if Skin.Atlas(self.icon, atlas, false) then
			self.icon:Show()
			self.sign:SetText("")
		else
			self.icon:Hide()
			self.sign:SetText(collapsed and "+" or "-")
		end
	end
	h.SetLabel = function(self, t) self.text:SetText(t) end
	h:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
	h:SetCollapsed(false)
	return h
end

function Skin.ListItem(parent, width, height)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, height or 24)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.sel = b:CreateTexture(nil, "BORDER")
	b.sel:SetAllPoints()
	b.hasArt = Skin.Atlas(b.bg, "Legacy-Challenge-Left-Sub-Tab", false, { 0.14, 0.1, 0.07, 0.85 })
	if not Skin.Atlas(b.sel, "Legacy-Challenge-Left-Sub-Tab-selected", false) then
		color(b.sel, { 1, 0.82, 0, 0.22 })
	end
	b.sel:Hide()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	if Skin.Atlas(hl, "Legacy-Challenge-Left-Sub-Tab-selected", false) then
		hl:SetAlpha(0.5)
	else
		color(hl, { 1, 1, 1, 0.07 })
	end
	b.SetSelected = function(self, on)
		self.selected = on and true or false
		self.sel:SetShown(self.selected)
	end
	return b
end

-- ===========================================================================
-- Cards, bars, dividers
-- ===========================================================================

-- The Legacy Challenge card: a framed slab of stone for a block of content.
function Skin.Card(parent)
	local c = CreateFrame("Frame", nil, parent)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints()
	if not Skin.Atlas(c.bg, "Legacy-Challenge-Cards", false) then
		color(c.bg, { 0.1, 0.075, 0.05, 0.92 })
		Skin.Panel(c, "TooltipDefaultLayout", 0)
	end
	return c
end

-- Legacy progress bar: gold fill in a framed track.
function Skin.ProgressBar(parent, width)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(width, 14)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOPLEFT", -4, 3)
	track:SetPoint("BOTTOMRIGHT", 4, -3)
	Skin.Atlas(track, "Legacy-Progressbar-BG", false, { 0, 0, 0, 0.7 })
	local fill = bar:CreateTexture(nil, "ARTWORK")
	if not Skin.Atlas(fill, "Legacy-Progressbar-Fill", false) then
		color(fill, { 0.2, 0.75, 0.2, 1 })
	end
	bar:SetStatusBarTexture(fill)
	local frameArt = bar:CreateTexture(nil, "OVERLAY")
	frameArt:SetPoint("TOPLEFT", -6, 5)
	frameArt:SetPoint("BOTTOMRIGHT", 6, -5)
	if not Skin.Atlas(frameArt, "Legacy-Progressbar-Frame", false) then frameArt:Hide() end
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bar.text:SetPoint("CENTER", 0, 0)
	return bar
end

function Skin.VerticalDivider(parent, height)
	local d = parent:CreateTexture(nil, "ARTWORK")
	d:SetSize(12, height)
	if not Skin.Atlas(d, "Legacy-Tree-Frame-divider-Vertical", false) then
		d:SetWidth(1)
		color(d, { 0.55, 0.45, 0.3, 0.6 })
	end
	return d
end

-- The round icon frame from the Legacy cards, around any icon.
function Skin.IconFrame(parent, size, icon)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("CENTER")
	f.icon:SetSize(size * 0.82, size * 0.82)
	if icon then f.icon:SetTexture(icon) end
	if f.CreateMaskTexture and Skin.HasAtlas("UI-Frame-IconMask") then
		local ok, mask = pcall(f.CreateMaskTexture, f)
		if ok and mask then
			pcall(mask.SetAtlas, mask, "UI-Frame-IconMask")
			mask:SetAllPoints(f.icon)
			pcall(f.icon.AddMaskTexture, f.icon, mask)
		end
	end
	f.border = f:CreateTexture(nil, "OVERLAY")
	f.border:SetAllPoints()
	if not Skin.Atlas(f.border, "Legacy-Tree-Frame-icon-frame", false) then f.border:Hide() end
	return f
end

-- Class icon for a player: the atlas when the client has one.
function Skin.SetClassIcon(tex, class)
	local atlas = class and ("classicon-" .. string.lower(class))
	if atlas and Skin.Atlas(tex, atlas, false) then return end
	if not tex:SetTexture(ns.ICON) then
		tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	end
end

-- ===========================================================================
-- Search box and Filter dropdown
-- ===========================================================================

function Skin.SearchBox(parent, width, onChange, hintText)
	local box, templated = Skin.Make("EditBox", parent, "SearchBoxTemplate")
	if not templated then
		box = Skin.Make("EditBox", parent, "InputBoxTemplate")
	end
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	if not templated then
		box:SetFontObject("ChatFontNormal")
		local hint = Skin.Text(parent, "GameFontDisableSmall", hintText)
		hint:SetPoint("LEFT", box, "LEFT", 2, 0)
		hint:SetPoint("RIGHT", box, "RIGHT", -6, 0)
		hint:SetJustifyH("LEFT")
		hint:SetWordWrap(false)
		box:SetScript("OnEditFocusGained", function() hint:Hide() end)
		box:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)
		box.hint = hint
	elseif child(box, "Instructions") and hintText then
		box.Instructions:SetText(hintText)
	end
	local inherited = box:GetScript("OnTextChanged")
	box:SetScript("OnTextChanged", function(self, userInput)
		if inherited then pcall(inherited, self, userInput) end
		if onChange then onChange(self:GetText() or "") end
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText("") ; self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return box
end

-- Forever's Filter button. setup(rootDescription) builds the menu.
-- Returns nil when the client has no menu system; the caller falls back.
function Skin.FilterDropdown(parent, width, setup)
	local dd, ok = Skin.Make("DropdownButton", parent, "WowStyle1FilterDropdownTemplate")
	if not ok or not dd.SetupMenu then
		if dd and dd.Hide then dd:Hide() end
		return nil
	end
	dd:SetWidth(width)
	dd.resizeToText = false
	dd:SetupMenu(function(_, root) setup(root) end)
	return dd
end
