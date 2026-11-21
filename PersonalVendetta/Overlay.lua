--[[-------------------------------------------------------------------------
  Personal Vendetta -- Overlay
  The floating window, with two tabs:

    Nearby  -- live tracking. Collapses to its header when nobody from the
               list is around; expands with a flash and a horn when someone
               turns up. Each row has a Note button.
    To add  -- the review queue. Players who killed you, and players you
               survived a fight with, wait here instead of in a popup, so
               nothing ever jumps in front of you mid-fight. The tab glows
               while there is someone you haven't looked at. Each row has
               Scum, Note, Skip and Add.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local WIDTH = 340
local HEADER_HEIGHT = 24
local MAX_ROWS = 10          -- Nearby rows
local ROW_HEIGHT = 20
local ADD_ROWS = 6           -- To add rows visible at once (mouse wheel for more)
local ADD_ROW_HEIGHT = 34
local FOOTER_HEIGHT = 28

local frame, rows, addRows
local lastRemoved -- for /vendetta undo
local tabs = {}
local addPage
local currentTab = "near"
local addOffset = 0
local pendingFlash = {}      -- list keys to flash on the Nearby tab
local newPending = {}        -- queue ids to flash on the To add tab

-- ===========================================================================
-- Position
-- ===========================================================================

local function savePosition()
	if not frame then return end
	local point, _, relPoint, x, y = frame:GetPoint()
	ns.db.settings.overlayPoint = { point = point, relPoint = relPoint, x = x, y = y }
end

local function restorePosition()
	local p = ns.db.settings.overlayPoint
	frame:ClearAllPoints()
	if p and p.point then
		frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, 80)
	end
end

-- ===========================================================================
-- Flashing and glowing
-- Hand-rolled on OnUpdate rather than an AnimationGroup: animation groups
-- are created on frames, not on textures, and this needs no template
-- support from the client at all.
-- ===========================================================================

local FLASH_SECONDS = 2.2
local FLASH_RATE = 1.6
local GLOW_SPEED = 3.2   -- radians per second: a slow, steady throb

-- One OnUpdate per row drives both effects: the short flash when someone
-- appears, and the steady glow a scum keeps for as long as he is near.
-- It switches itself off when neither is running.
local function animate(self)
	local now = GetTime()
	local active = false

	if self.flashUntil then
		if now >= self.flashUntil then
			self.flashUntil = nil
			self.flash:SetAlpha(0)
		else
			local phase = (now * FLASH_RATE) % 1
			local a = (phase < 0.5) and (phase * 2) or ((1 - phase) * 2)
			self.flash:SetAlpha(a * 0.5)
			active = true
		end
	end

	if self.glowing then
		local wave = 0.5 + 0.5 * math.sin(now * GLOW_SPEED)
		self.glow:SetAlpha(0.15 + 0.30 * wave)
		self.edge:SetAlpha(0.6 + 0.4 * wave)
		active = true
	end

	if not active then self:SetScript("OnUpdate", nil) end
end

local function wake(row)
	row:SetScript("OnUpdate", animate)
end

local function startFlash(row)
	row.flashUntil = GetTime() + FLASH_SECONDS
	wake(row)
end

local function setGlow(row, on)
	if not row.glow then return end
	on = on and true or false
	if (row.glowing or false) == on then return end
	row.glowing = on or nil
	row.glow:SetShown(on)
	row.edge:SetShown(on)
	if on then
		wake(row)
	else
		row.glow:SetAlpha(0)
	end
end

local function stopEffects(row)
	row.flashUntil = nil
	row.flash:SetAlpha(0)
	setGlow(row, false)
	row:SetScript("OnUpdate", nil)
end

local function solidTexture(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	if t.SetColorTexture then
		t:SetColorTexture(r, g, b, a or 1)
	else
		t:SetTexture("Interface\\Buttons\\WHITE8X8")
		t:SetVertexColor(r, g, b, a or 1)
	end
	return t
end

-- A compact button in the Forever list art, sized for this window. A tint
-- tells Add (green) and Skip (grey) apart at a glance.
local function flatButton(parent, label, w, h, r, g, b)
	return ns.Skin.FlatButton(parent, label, w, h or 18, r and { r * 1.6 + 0.3, g * 1.6 + 0.3, b * 1.6 + 0.3 } or nil)
end

-- ===========================================================================
-- Shared formatting
-- ===========================================================================

local function describe(entry)
	local bits = {}
	if entry.race then bits[#bits + 1] = entry.race end
	if entry.className then bits[#bits + 1] = entry.className end
	return table.concat(bits, " ")
end

-- Level as you should read it right now:
--   white 47   read off them this sighting
--   red ??     10+ levels above you; an old number here would lie
--   grey 47?   last known; the client would not give a fresh one just now
local function levelText(entry, record)
	if entry.levelSkull and record and record.levelFresh then
		return "|cffff3333??|r "
	end
	if not entry.level and not entry.levelSkull then return "" end
	if record and record.levelFresh then
		return "|cffffffff" .. entry.level .. "|r "
	end
	if entry.levelSkull then
		return "|cff996666??|r "
	end
	return "|cff888888" .. entry.level .. "?|r "
end
ns.LevelText = levelText

-- ===========================================================================
-- Nearby rows
-- ===========================================================================

local function buildRow(index, parent, anchor)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 16, ROW_HEIGHT)
	if anchor then
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
	else
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -HEADER_HEIGHT)
	end

	row.flash = solidTexture(row, "BACKGROUND", 1, 0.15, 0.15)
	row.flash:SetAllPoints()
	row.flash:SetAlpha(0)

	-- Scum glow: an additive red wash plus a bright bar on the left edge.
	row.glow = solidTexture(row, "BORDER", 1, 0.08, 0.05)
	row.glow:SetAllPoints()
	if row.glow.SetBlendMode then row.glow:SetBlendMode("ADD") end
	row.glow:SetAlpha(0)
	row.glow:Hide()

	row.edge = solidTexture(row, "ARTWORK", 1, 0.15, 0.1)
	row.edge:SetPoint("TOPLEFT", -6, 0)
	row.edge:SetPoint("BOTTOMLEFT", -6, 0)
	row.edge:SetWidth(3)
	row.edge:Hide()

	-- Note, right on the row: write down what they did without leaving the
	-- window.
	row.note = flatButton(row, "+" .. L["Note"], 38, 16)
	row.note:SetPoint("RIGHT", -1, 0)
	row.note:SetScript("OnClick", function()
		if row.entry and ns.Notes then ns.Notes:Open(row.entry.key) end
	end)
	row.note:SetScript("OnEnter", function(self)
		if not GameTooltip or not row.entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if row.entry.note then
			GameTooltip:AddLine(L["Note"], 1, 0.82, 0.3)
			GameTooltip:AddLine(row.entry.note, 1, 1, 1, true)
			GameTooltip:AddLine(L["Click to edit."], 0.6, 0.6, 0.6)
		else
			GameTooltip:AddLine(L["Add a note: what did they do?"], 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	row.note:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	-- Scum only: one click yells a warning to everyone around you.
	row.warn = flatButton(row, "|cffff5555" .. L["Warn"] .. "|r", 40, 16, 0.5, 0.1, 0.1)
	row.warn:SetPoint("RIGHT", row.note, "LEFT", -3, 0)
	row.warn:SetScript("OnClick", function()
		if row.entry and ns.Share then ns.Share:WarnAround(row.entry) end
	end)
	row.warn:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Warn everyone around you"])
		if row.entry and ns.Share then GameTooltip:AddLine(ns.Share:ScumWarning(row.entry), 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	row.warn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	row.warn:Hide()

	row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.score:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
	row.score:SetJustifyH("RIGHT")

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("LEFT", 2, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWidth(158)
	row.name:SetWordWrap(false)

	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.detail:SetPoint("LEFT", row.name, "RIGHT", 2, 0)
	row.detail:SetPoint("RIGHT", row.score, "LEFT", -4, 0)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetWordWrap(false)

	-- Hover for the full picture (note included). Motion only: clicks pass
	-- through to the window, so it still drags from anywhere but the button.
	if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(true) end
	if row.SetMouseClickEnabled then row:SetMouseClickEnabled(false) end
	row:SetScript("OnEnter", function(self)
		if self.entry and ns.EntryTooltip then ns.EntryTooltip(self, self.entry, "ANCHOR_LEFT") end
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	row:Hide()
	return row
end

-- ===========================================================================
-- To add rows
-- ===========================================================================

local refresh -- forward

local function buildAddRow(index, parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 16, ADD_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ADD_ROW_HEIGHT)

	local stripe = solidTexture(row, "BACKGROUND", 1, 1, 1, (index % 2 == 0) and 0.05 or 0)
	stripe:SetAllPoints()
	row.flash = solidTexture(row, "BORDER", 1, 0.82, 0.2)
	row.flash:SetAllPoints()
	row.flash:SetAlpha(0)

	-- [name            ] [x]Scum [Note] [Skip] [Add]
	-- [killed you x2 ...]
	row.add = flatButton(row, L["Add"], 34, 18, 0.15, 0.45, 0.15)
	row.add:SetPoint("RIGHT", -1, 0)
	row.skip = flatButton(row, L["Skip"], 32, 18, 0.3, 0.3, 0.3)
	row.skip:SetPoint("RIGHT", row.add, "LEFT", -3, 0)
	row.note = flatButton(row, "+" .. L["Note"], 38, 18)
	row.note:SetPoint("RIGHT", row.skip, "LEFT", -3, 0)

	row.scumText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.scumText:SetPoint("RIGHT", row.note, "LEFT", -4, 0)
	row.scumText:SetText(L["Scum"])
	row.scumText:SetTextColor(1, 0.25, 0.25)
	row.scum = ns.CreateCheckButton(row)
	row.scum:SetSize(20, 20)
	row.scum:SetPoint("RIGHT", row.scumText, "LEFT", 1, 0)
	row.scum:SetScript("OnEnter", function(self) ns.ScumTooltip(self) end)
	row.scum:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("TOPLEFT", 2, -4)
	row.name:SetPoint("RIGHT", row.scum, "LEFT", -4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.detail:SetPoint("BOTTOMLEFT", 2, 4)
	row.detail:SetPoint("RIGHT", row.scum, "LEFT", -4, 0)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetWordWrap(false)

	row.scum:SetScript("OnClick", function(self)
		if row.id then ns.Pending:SetScum(row.id, self:GetChecked() and true or false) end
	end)
	row.note:SetScript("OnClick", function()
		if row.id and ns.Notes then ns.Notes:OpenPending(row.id) end
	end)
	row.skip:SetScript("OnClick", function()
		if row.id then ns.Pending:Skip(row.id) end
	end)
	row.add:SetScript("OnClick", function()
		if row.rid then ns.Pending:Undo(row.rid)
		elseif row.id then ns.Pending:Add(row.id) end
	end)

	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if self.item and ns.PendingTooltip then ns.PendingTooltip(self, self.item) end
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	row:EnableMouseWheel(true)
	row:SetScript("OnMouseWheel", function(_, delta)
		addOffset = addOffset - delta
		refresh()
	end)

	row:Hide()
	return row
end

-- ===========================================================================
-- Tabs
-- ===========================================================================

local function animateTabs(self)
	local unseen = ns.Pending and ns.Pending:UnseenCount() or 0
	local glowOn = unseen > 0 and currentTab ~= "add"
	if not glowOn then
		tabs.add.glow:SetAlpha(0)
		self:SetScript("OnUpdate", nil)
		return
	end
	local wave = 0.5 + 0.5 * math.sin(GetTime() * 4)
	tabs.add.glow:SetAlpha(0.25 + 0.55 * wave)
end

local function selectTab(which)
	currentTab = (which == "add") and "add" or "near"
	if ns.db then ns.db.settings.overlayTab = currentTab end
	refresh()
end

local function buildTab(key, label)
	local tab = CreateFrame("Button", nil, frame)
	tab:SetSize(key == "add" and 86 or 74, HEADER_HEIGHT - 6)
	tab.bg = tab:CreateTexture(nil, "BACKGROUND")
	tab.bg:SetAllPoints()
	ns.Skin.Atlas(tab.bg, "Legacy-Challenge-Left-Sub-Tab", false, { 0.2, 0.14, 0.09, 0.9 })
	tab.glow = solidTexture(tab, "BORDER", 1, 0.75, 0.15, 1)
	tab.glow:SetAllPoints()
	if tab.glow.SetBlendMode then tab.glow:SetBlendMode("ADD") end
	tab.glow:SetAlpha(0)
	tab.line = tab:CreateTexture(nil, "ARTWORK")
	if ns.Skin.Atlas(tab.line, "Legacy-Challenge-Left-Sub-Tab-selected", false) then
		tab.line:SetAllPoints()
	else
		ns.Skin.Color(tab.line, { 1, 0.82, 0, 1 })
		tab.line:SetPoint("BOTTOMLEFT", 0, 0)
		tab.line:SetPoint("BOTTOMRIGHT", 0, 0)
		tab.line:SetHeight(2)
	end
	local hl = solidTexture(tab, "HIGHLIGHT", 1, 1, 1, 0.12)
	hl:SetAllPoints()
	tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tab.text:SetPoint("CENTER", 0, 0)
	tab.text:SetText(label)
	tab:SetScript("OnClick", function() selectTab(key) end)
	tabs[key] = tab
	return tab
end

-- ===========================================================================
-- Construction
-- ===========================================================================

local function buildFrame()
	frame = CreateFrame("Frame", "PersonalVendettaOverlay", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEADER_HEIGHT)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if ns.db.settings.window.locked then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:SetClampedToScreen(true)

	-- Forever's thin tooltip border: it scales down to a single title bar.
	ns.Skin.Panel(frame, "TooltipDefaultLayout", 0.55)

	-- Radar status: green when enemy nameplates are on and the radar can see,
	-- red when it is blind. Click to switch them on or off.
	local dot = CreateFrame("Button", nil, frame)
	dot:SetSize(12, 12)
	dot:SetPoint("TOPLEFT", 7, -6)
	dot.tex = solidTexture(dot, "ARTWORK", 0.2, 0.9, 0.2, 1)
	dot.tex:SetPoint("CENTER")
	dot.tex:SetSize(8, 8)
	dot:SetScript("OnClick", function(self)
		if not ns.Radar then return end
		if ns.Radar:NameplatesOn() then ns.Radar:DisableNameplates() else ns.Radar:EnableNameplates() end
		if self:IsMouseOver() and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
	end)
	dot:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		if self.muted then
			GameTooltip:AddLine("|cffff4444" .. L["Alerts muted here"] .. "|r")
			GameTooltip:AddLine(L["You're somewhere you chose to keep quiet (Settings > Alerts). The radar turns back on when you leave."], 1, 1, 1, true)
		elseif ns.Radar and ns.Radar:NameplatesOn() then
			GameTooltip:AddLine("|cff44ff44" .. L["Radar on"] .. "|r")
			GameTooltip:AddLine(string.format(L["Watching up to %s yards around you."], ns.Radar:GetRange()), 1, 1, 1, true)
			GameTooltip:AddLine(L["Click to switch enemy nameplates off."], 0.7, 0.7, 0.7, true)
		else
			GameTooltip:AddLine("|cffff4444" .. L["Radar blind"] .. "|r")
			GameTooltip:AddLine(L["Enemy nameplates are off, so nobody can be spotted. Click to switch them on."], 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	dot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	frame.dot = dot

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.title:SetPoint("TOPLEFT", 22, -6)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWidth(WIDTH - 86 - 74 - 38)
	frame.title:SetWordWrap(false)

	local addTab = buildTab("add", L["To add"])
	addTab:SetPoint("TOPRIGHT", -4, -3)
	local nearTab = buildTab("near", L["Nearby"])
	nearTab:SetPoint("RIGHT", addTab, "LEFT", -3, 0)

	rows = {}
	for i = 1, MAX_ROWS do
		rows[i] = buildRow(i, frame, rows[i - 1])
	end

	addPage = CreateFrame("Frame", nil, frame)
	addPage:SetPoint("TOPLEFT", 8, -HEADER_HEIGHT)
	addPage:SetSize(WIDTH - 16, ADD_ROWS * ADD_ROW_HEIGHT + FOOTER_HEIGHT)
	addPage:EnableMouseWheel(true)
	addPage:SetScript("OnMouseWheel", function(_, delta)
		addOffset = addOffset - delta
		refresh()
	end)
	addRows = {}
	for i = 1, ADD_ROWS do
		addRows[i] = buildAddRow(i, addPage)
	end

	addPage.empty = addPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	addPage.empty:SetPoint("TOPLEFT", 2, -6)
	addPage.empty:SetPoint("TOPRIGHT", -2, -6)
	addPage.empty:SetJustifyH("LEFT")
	addPage.empty:SetWordWrap(true)
	addPage.empty:SetText(L["Nobody to review. Players who kill you, or who you fight off, wait here so you can add them when it suits you."])

	addPage.addAll = flatButton(addPage, L["Add all"], 70, 20, 0.15, 0.45, 0.15)
	addPage.skipAll = flatButton(addPage, L["Skip all"], 64, 20, 0.3, 0.3, 0.3)
	addPage.info = addPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	addPage.addAll:SetScript("OnClick", function() ns.Pending:AddAll() end)
	addPage.skipAll:SetScript("OnClick", function() ns.Pending:SkipAll() end)

	currentTab = (ns.db and ns.db.settings.overlayTab == "add") and "add" or "near"
	restorePosition()
	return frame
end

-- ===========================================================================
-- Rendering
-- ===========================================================================

local function renderNear()
	local near = ns.Radar and ns.Radar:GetNearby() or {}
	local shown = 0
	for i = 1, MAX_ROWS do
		local row = rows[i]
		local record = near[i]
		if record then
			local entry = record.entry
			shown = shown + 1
			if record.dead then
				row.name:SetText(ns.FullName(entry))
				row.name:SetTextColor(0.5, 0.5, 0.5)
				row.detail:SetText("|cff888888dead|r")
				setGlow(row, false)
			else
				local r, g, b = ns.ClassColor(entry.class)
				local skull = entry.scum and (ns.SKULL .. " ") or ""
				row.name:SetText(skull .. levelText(entry, record) .. ns.FullName(entry))
				row.name:SetTextColor(r, g, b)
				row.detail:SetText(describe(entry))
				setGlow(row, entry.scum)
			end
			row.score:SetText(string.format("|cffff6666%d|r/|cff66ff66%d|r",
				entry.theyKilledMe or 0, entry.iKilledThem or 0))
			row.note:SetLabel(entry.note and ("|cffffd100" .. L["Note"] .. "|r") or ("|cffaaaaaa+" .. L["Note"] .. "|r"))
			local warn = entry.scum and not record.dead and ns.db.settings.scumWarnButton ~= false
			row.warn:SetShown(warn and true or false)
			row.score:ClearAllPoints()
			row.score:SetPoint("RIGHT", warn and row.warn or row.note, "LEFT", -6, 0)
			row.entry = entry
			row:Show()

			if entry.key and pendingFlash[entry.key] then
				pendingFlash[entry.key] = nil
				startFlash(row)
			end
		else
			row.entry = nil
			stopEffects(row)
			row:Hide()
		end
	end
	return shown
end

local function hideNear()
	for i = 1, MAX_ROWS do
		rows[i].entry = nil
		stopEffects(rows[i])
		rows[i]:Hide()
	end
end

local function renderAdd()
	local pending = ns.Pending and ns.Pending:List() or {}
	-- Just added or skipped: their row stays a moment, with Undo where Add was.
	local list = {}
	for _, r in ipairs(ns.Pending and ns.Pending:Recent() or {}) do list[#list + 1] = { recent = r } end
	for _, it in ipairs(pending) do list[#list + 1] = it end
	local total = #pending
	local maxOffset = math.max(0, #list - ADD_ROWS)
	if addOffset > maxOffset then addOffset = maxOffset end
	if addOffset < 0 then addOffset = 0 end

	local shown = 0
	for i = 1, ADD_ROWS do
		local row = addRows[i]
		local it = list[addOffset + i]
		if it and it.recent then
			shown = shown + 1
			local r = it.recent
			row.name:SetText(r.label)
			if r.kind == "added" then row.name:SetTextColor(0.5, 0.9, 0.5) else row.name:SetTextColor(0.6, 0.6, 0.6) end
			row.detail:SetText("|cff888888" .. L["Changed your mind?"] .. "|r")
			row.scum:Hide()
			row.scumText:Hide()
			row.note:Hide()
			row.skip:Hide()
			row.add:SetLabel(L["Undo"])
			row.add:SetWidth(math.max(34, (row.add.text:GetStringWidth() or 0) + 14))
			row.id, row.item, row.rid = nil, nil, r.rid
			stopEffects(row)
			row:Show()
		elseif it then
			shown = shown + 1
			row.scum:Show()
			row.scumText:Show()
			row.note:Show()
			row.skip:Show()
			row.add:SetLabel(L["Add"])
			row.add:SetWidth(34)
			row.rid = nil
			local r, g, b = ns.ClassColor(it.class)
			local lvl = it.levelSkull and "|cffff3333??|r " or (it.level and ("|cffffffff" .. it.level .. "|r ") or "")
			row.name:SetText((it.scum and (ns.SKULL .. " ") or "") .. lvl .. ns.FullName(it.name, it.surname))
			row.name:SetTextColor(r, g, b)
			local detail = ns.Pending:Describe(it)
			if it.className then detail = "|cff999999" .. it.className .. "|r  " .. detail end
			if it.note then detail = detail .. "  |cffffd100\"" .. it.note .. "\"|r" end
			row.detail:SetText(detail)
			row.scum:SetChecked(it.scum and true or false)
			row.note:SetLabel(it.note and ("|cffffd100" .. L["Note"] .. "|r") or ("|cffaaaaaa+" .. L["Note"] .. "|r"))
			row.id, row.item = it.id, it
			row:Show()
			if newPending[it.id] then
				newPending[it.id] = nil
				startFlash(row)
			end
		else
			row.id, row.item, row.rid = nil, nil, nil
			stopEffects(row)
			row:Hide()
		end
	end

	addPage.empty:SetShown(#list == 0)
	addPage.addAll:SetShown(total > 0)
	addPage.skipAll:SetShown(total > 0)
	addPage.info:SetShown(total > 0)

	local bodyHeight = (#list == 0) and 34 or (shown * ADD_ROW_HEIGHT)
	addPage.addAll:ClearAllPoints()
	addPage.skipAll:ClearAllPoints()
	addPage.info:ClearAllPoints()
	addPage.addAll:SetPoint("TOPRIGHT", addPage, "TOPRIGHT", -1, -(bodyHeight + 4))
	addPage.skipAll:SetPoint("RIGHT", addPage.addAll, "LEFT", -4, 0)
	addPage.info:SetPoint("LEFT", addPage, "TOPLEFT", 2, -(bodyHeight + 14))
	if #list > ADD_ROWS then
		addPage.info:SetText(string.format(L["%d-%d of %d, scroll for more"],
			addOffset + 1, math.min(#list, addOffset + ADD_ROWS), #list))
	else
		addPage.info:SetText(string.format(L["%d waiting"], total))
	end

	return bodyHeight + ((total > 0) and FOOTER_HEIGHT or 0)
end

-- Scale, background opacity. Position lock is checked at drag time.
local function applyWindowOptions()
	if not frame then return end
	local w = ns.db.settings.window
	frame:SetScale(math.max(0.6, math.min(1.6, w.scale or 1)))
	frame.bgAlpha = math.max(0, math.min(1, w.opacity or 0.55))
end

refresh = function()
	if not frame then return end
	applyWindowOptions()

	local total = ns.List:Count()
	local count = ns.Radar and ns.Radar:Count() or 0 -- the living ones
	local pendingCount = ns.Pending and ns.Pending:Count() or 0

	-- Looking at the To add tab counts as having seen everything in it.
	if currentTab == "add" and frame:IsShown() and ns.Pending then
		ns.Pending:MarkAllSeen(true)
	end
	local unseen = ns.Pending and ns.Pending:UnseenCount() or 0

	local scumNear = 0
	for _, record in ipairs(ns.Radar and ns.Radar:GetNearby() or {}) do
		if record.entry.scum and not record.dead then scumNear = scumNear + 1 end
	end

	-- Header
	if count > 0 then
		frame.title:SetText("|cff9933ffVendetta|r  |cffff4444" .. string.format(L["%d near"], count) .. "|r"
			.. (scumNear > 0 and ("  " .. ns.SKULL .. ns.SCUM_COLOR .. string.format(L["%d scum"], scumNear) .. "|r") or ""))
		frame:SetBorderTint(1, 0.25, 0.2, 1)
	else
		frame.title:SetText("|cff9933ffVendetta|r  |cff888888" .. string.format(L["%d on list"], total) .. "|r")
		frame:SetBorderTint(1, 1, 1, 1)
	end
	frame:SetCenterTint(0.06, 0.045, 0.03, frame.bgAlpha or 0.55)

	-- Red when the radar is blind, and also in a city or town you chose to
	-- keep quiet: it is not alerting you there. Green again once you leave.
	local seeing = ns.Radar and ns.Radar:NameplatesOn()
	local muted = seeing and ns.InQuietPlace() or false
	if seeing and not muted then
		frame.dot.tex:SetColorTexture(0.2, 0.9, 0.2, 1)
	else
		frame.dot.tex:SetColorTexture(1, 0.15, 0.15, 1)
	end
	frame.dot.blind = not seeing
	frame.dot.muted = muted

	tabs.near.text:SetText(count > 0 and (L["Nearby"] .. " |cffff4444" .. count .. "|r") or L["Nearby"])
	tabs.add.text:SetText(pendingCount > 0 and (L["To add"] .. " |cffffd100" .. pendingCount .. "|r") or L["To add"])
	for key, tab in pairs(tabs) do
		local on = (key == currentTab)
		tab.bg:SetAlpha(on and 1 or 0.35)
		tab.line:SetShown(on)
	end

	-- The To add tab glows while there is someone you haven't looked at.
	if unseen > 0 and currentTab ~= "add" then
		frame:SetScript("OnUpdate", animateTabs)
	else
		tabs.add.glow:SetAlpha(0)
		frame:SetScript("OnUpdate", nil)
	end

	-- Body
	local height
	if currentTab == "add" then
		hideNear()
		addPage:Show()
		height = HEADER_HEIGHT + renderAdd() + 4
	else
		addPage:Hide()
		for i = 1, ADD_ROWS do stopEffects(addRows[i]) end
		local shown = renderNear()
		-- Collapsed when quiet, expanded when there is something to show.
		height = HEADER_HEIGHT + (shown * ROW_HEIGHT) + (shown > 0 and 6 or 0)
	end
	frame:SetHeight(height)

	-- Auto-hide: out of the way entirely while there is nothing to show.
	-- The window comes back on its own when someone appears or is queued.
	if ns.db.settings.overlayShown ~= false then
		local quiet = count == 0 and pendingCount == 0 and currentTab == "near"
		local hide = ns.db.settings.window.autoHide and quiet
		if hide and frame:IsShown() then
			frame:Hide()
			frame.autoHidden = true
		elseif not hide and frame.autoHidden then
			frame.autoHidden = nil
			frame:Show()
		end
	end
end

local function alert(entries)
	if not entries or #entries == 0 then return end

	local anyScum = false
	-- In a city or town you asked to be quiet in: the window still shows
	-- them, but no chat line and no horn.
	local quiet = ns.InQuietPlace and ns.InQuietPlace()
	for _, entry in ipairs(entries) do
		if entry.key then pendingFlash[entry.key] = true end
		if quiet then
			-- nothing in chat
		else
		local noteBit = ""
		if entry.note then
			local n = entry.note
			if #n > 60 then n = string.sub(n, 1, 57) .. "..." end
			noteBit = " |cffffd100(" .. n .. ")|r"
		end
		if entry.scum then
			anyScum = true
			ns.Print(ns.SKULL .. " " .. ns.SCUM_COLOR .. L["SCUM"] .. "|r " .. string.format(L["%s is near. Must kill. %d to %d."],
				ns.SCUM_COLOR .. ns.FullName(entry) .. "|r", entry.theyKilledMe or 0, entry.iKilledThem or 0) .. noteBit)
		else
			ns.Print(string.format(L["%s is near. %d to %d."],
				"|cffff4444" .. ns.FullName(entry) .. "|r", entry.theyKilledMe or 0, entry.iKilledThem or 0) .. noteBit)
		end
		end
	end

	-- One horn per batch: the scum one wins if any of them is scum.
	if ns.Sound then ns.Sound:Play(anyScum and "scum" or "normal") end

	-- Someone on the list is here: that matters more than the review queue.
	if currentTab ~= "near" then
		currentTab = "near"
		if ns.db then ns.db.settings.overlayTab = "near" end
	end
	refresh()
end

-- Build on demand, and never let a UI failure take the commands down with it.
local function ensureFrame()
	if frame then return true end
	local ok, err = pcall(buildFrame)
	if not ok then
		ns.Print("|cffff4444" .. L["Could not build the window:"] .. "|r " .. tostring(err))
		ns.Print(L["The list and the tracking still work. /vendetta list shows it in chat."])
		return false
	end
	return true
end

local function toggle(show)
	if not ensureFrame() then return end
	if show == nil then show = not (frame:IsShown() or frame.autoHidden) end
	frame.autoHidden = nil
	frame:SetShown(show)
	ns.db.settings.overlayShown = show
	if show then refresh() end
	ns.Fire("SETTINGS_CHANGED")
end

-- Open the window on a given tab.
local function showTab(which)
	if not ensureFrame() then return end
	toggle(true)
	selectTab(which)
end

-- ===========================================================================
-- Slash commands
-- ===========================================================================

local function printList()
	local entries = ns.List:ByDateAdded()
	if #entries == 0 then
		ns.Print(L["The list is empty. Go get killed by someone."])
		return
	end
	ns.Print(L["Hit list, newest first:"])
	for _, e in ipairs(entries) do
		local nearNow = ns.Radar and ns.Radar.nearby[e.key]
		local name = ns.FullName(e)
		if e.scum then name = ns.SKULL .. ns.SCUM_COLOR .. name .. "|r" end
		print(string.format("  |cffff6666%d|r/|cff66ff66%d|r  %s %s%s  |cff888888%s|r",
			e.theyKilledMe or 0, e.iKilledThem or 0,
			name,
			levelText(e, nearNow),
			e.className and (" " .. e.className) or "",
			nearNow and ("|cffff4444<< " .. L["NEAR"] .. "|r") or string.format(L["seen %s"], ns.Ago(e.lastSeen))))
	end
end

-- "Not on the list", or -- when a first name fits two people -- ask for the surname.
local function notFound(arg, count)
	if count and count > 1 then
		ns.Print(string.format(L["%d people on your list are called %s. Use the full name, e.g. %s Surname."], count, arg, arg))
	else
		ns.Print(string.format(L["Not on the list: %s"], arg))
	end
end

local function handleCommand(msg)
	local cmd, arg = string.match(msg or "", "^(%S*)%s*(.-)$")
	cmd = string.lower(cmd or "")

	if cmd == "" or cmd == "show" or cmd == "toggle" then
		toggle()
	elseif cmd == "list" then
		printList()
	elseif cmd == "review" or cmd == "toadd" then
		showTab("add")
	elseif cmd == "add" then
		if arg == "" then
			-- No name: add whoever you have targeted, with everything we can read.
			if not (ns.Radar and ns.Radar.IsEnemyPlayer("target")) then
				ns.Print(L["Target an enemy player, or use /vendetta add <first> <surname>."])
				return
			end
			local info = ns.Radar:ReadUnitInfo("target")
			local _, existing = ns.List:Find(info.guid, info.name, info.surname)
			if existing then
				ns.Print(string.format(L["%s is already on the list."], ns.FullName(existing)))
				return
			end
			local entry = ns.List:AddFromFight(info)
			if entry then ns.Print(string.format(L["Added %s from your target."], "|cffff4444" .. ns.FullName(entry) .. "|r")) end
			return
		end
		local _, existing = ns.List:Find(nil, arg)
		if existing then
			ns.Print(string.format(L["%s is already on the list."], ns.FullName(existing)))
			return
		end
		local _, entry = ns.List:Upsert({ name = arg })
		if entry then
			ns.Print(string.format(L["Added %s by hand."], "|cffff4444" .. ns.FullName(entry) .. "|r"))
			ns.Fire("LIST_CHANGED")
		end
	elseif cmd == "remove" or cmd == "forgive" then
		if arg == "" then
			ns.Print(L["Usage: /vendetta remove <name>"])
			return
		end
		local _, entry, count = ns.List:Find(nil, arg)
		if not entry then
			notFound(arg, count)
			return
		end
		local full = ns.FullName(entry)
		local snapshot = ns.List:RemoveKey(entry.key)
		ns.Print(string.format(L["Removed %s. Generous of you."], full) .. " " .. L["Changed your mind? /vendetta undo"])
		lastRemoved = snapshot
	elseif cmd == "undo" then
		local snap = lastRemoved
		lastRemoved = nil
		local back = snap and ns.List:Restore(snap)
		if back then
			ns.Print(string.format(L["%s is back on the list."], ns.FullName(back)))
		else
			ns.Print(L["Nothing to undo."])
		end
	elseif cmd == "detail" or cmd == "details" or cmd == "info" then
		local _, entry, count = ns.List:Find(nil, arg)
		if not entry then
			if arg == "" then ns.Print(L["Usage: /vendetta detail <name>"]) else notFound(arg, count) end
			return
		end
		ns.Detail:Open(entry.key)
	elseif cmd == "feedback" or cmd == "bug" or cmd == "about" then
		ns.Print(string.format(L["Personal Vendetta %s. Feedback and bug reports: %s"], ns.VERSION, ns.FEEDBACK_URL))
		ns.Settings:Feedback()
	elseif cmd == "share" then
		if ns.Share then ns.Share:Send() end
	elseif cmd == "recap" then
		ns.Deaths.ReadNow()
	elseif cmd == "range" then
		if not ns.Radar then
			ns.Print("|cffff4444Radar.lua did not load|r -- check it is in the folder and listed in the .toc.")
			return
		end
		local n = tonumber(arg)
		if not n then
			ns.Print(string.format(L["Radar range is %s yards. Usage: /vendetta range 41"], ns.Radar:GetRange()))
		else
			ns.Radar:SetRange(n)
		end
	elseif cmd == "debug" then
		ns.Print("v" .. ns.VERSION .. " status:")
		print("  Core    " .. (ns.db and "|cff44ff44loaded|r" or "|cffff4444no database|r"))
		print("  Deaths  " .. (ns.Deaths and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Queue   " .. (ns.Pending and ("|cff44ff44loaded|r, " .. ns.Pending:Count() .. " waiting")
			or "|cffff4444MISSING|r"))
		print("  Radar   " .. (ns.Radar and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Kills   " .. (ns.Kills and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Fights " .. (ns.Fights and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Notes " .. (ns.Notes and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Share " .. (ns.Share and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Sound   " .. (ns.Sound and ("|cff44ff44loaded|r, "
			.. ns.Sound:Current("normal").label .. " " .. math.floor(ns.Sound:Volume("normal") * 100 + 0.5) .. "%, scum "
			.. ns.Sound:Current("scum").label .. " " .. math.floor(ns.Sound:Volume("scum") * 100 + 0.5) .. "%")
			or "|cffff4444MISSING|r"))
		print("  Plates  " .. (ns.Radar and (ns.Radar:NameplatesOn() and "|cff44ff44on|r" or "|cffff4444OFF|r") or "?"))
		print("  Extras  " .. "Toast " .. (ns.Toast and "|cff44ff44ok|r" or "|cffff4444MISSING|r")
			.. "  Detail " .. (ns.Detail and "|cff44ff44ok|r" or "|cffff4444MISSING|r")
			.. "  Marks " .. (ns.Marks and ("|cff44ff44ok|r (" .. ns.Marks:Count() .. ")") or "|cffff4444MISSING|r")
			.. "  Locale " .. tostring(ns.LOCALE)
			.. "  Shared list " .. (ns.IsAccountWide() and "on" or "off"))
		print("  Options " .. (ns.Settings and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Minimap " .. (ns.Minimap and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Window  " .. (frame and "|cff44ff44built|r" or "|cffffd100not built yet|r"))
		print("  Recap   " .. ((C_DeathRecap and C_DeathRecap.GetRecapEvents)
			and "|cff44ff44available|r" or "|cffff4444MISSING|r"))
		print("  List    " .. ns.List:Count() .. " entries, "
			.. (ns.Radar and ns.Radar:Count() or 0) .. " near")
		print("  Range   " .. (ns.Radar and ns.Radar:GetRange() or "?") .. " yards")
	elseif cmd == "sound" then
		local s = ns.db.settings.sound
		s.enabled = not s.enabled
		ns.Print(s.enabled and L["Sighting sounds on."] or L["Sighting sounds off."])
		ns.Fire("SETTINGS_CHANGED")
	elseif cmd == "options" or cmd == "config" or cmd == "settings" then
		ns.Settings:Open("general")
	elseif cmd == "nameplates" or cmd == "np" then
		ns.Radar:EnableNameplates()
	elseif cmd == "scum" or cmd == "unscum" then
		if arg == "" then
			ns.Print(string.format(L["Usage: /vendetta %s <name>"], cmd))
			return
		end
		local key, entry, count = ns.List:Find(nil, arg)
		if not entry then
			notFound(arg, count)
			return
		end
		ns.List:SetScum(key, cmd == "scum")
		ns.Print(string.format(cmd == "scum" and L["%s is scum now."] or L["%s is no longer scum."], ns.FullName(entry)))
	elseif cmd == "kill" or cmd == "unkill" or cmd == "death" or cmd == "undeath" then
		-- Hand corrections, for when detection misses one or double counts.
		if arg == "" then
			ns.Print(string.format(L["Usage: /vendetta %s <name>"], cmd))
			return
		end
		local field = (cmd == "kill" or cmd == "unkill") and "iKilledThem" or "theyKilledMe"
		local delta = (cmd == "kill" or cmd == "death") and 1 or -1
		local entry, count = ns.List:Adjust(arg, field, delta)
		if entry then
			ns.Print(string.format(L["%s: now %d to %d."], ns.FullName(entry),
				entry.theyKilledMe or 0, entry.iKilledThem or 0))
		else
			notFound(arg, count)
		end
	elseif cmd == "note" then
		local _, entry, count = ns.List:Find(nil, arg)
		if not entry then
			if arg == "" then ns.Print(L["Usage: /vendetta note <name>"]) else notFound(arg, count) end
			return
		end
		ns.Notes:Open(entry.key)
	elseif cmd == "wipe" then
		if arg == "confirm" then
			ns.List:Wipe()
			ns.Print(L["List wiped."])
		else
			ns.Print(L["This clears everyone. Type /vendetta wipe confirm if you mean it."])
		end
	else
		ns.Print(L["Commands:"])
		print("  |cffffd100/vendetta|r  " .. L["toggle the window"])
		print("  |cffffd100/vendetta review|r  " .. L["open the To add tab"])
		print("  |cffffd100/vendetta list|r  " .. L["print the list, marking who is near"])
		print("  |cffffd100/vendetta add|r  " .. L["add your current target"])
		print("  |cffffd100/vendetta add <first> <surname>|r  " .. L["add someone by name"])
		print("  |cffffd100/vendetta remove <name>|r  " .. L["take someone off"])
		print("  |cffffd100/vendetta undo|r  " .. L["bring back the last one you removed"])
		print("  |cffffd100/vendetta note <name>|r  " .. L["write a note on someone"])
		print("  |cffffd100/vendetta share|r  " .. L["share your list with your party"])
		print("  |cffffd100/vendetta recap|r  " .. L["re-read your last death"])
		print("  |cffffd100/vendetta options|r  " .. L["open settings (or click the minimap skull)"])
		print("  |cffffd100/vendetta kill <name>|r / |cffffd100unkill|r  " .. L["fix your kill count by hand"])
		print("  |cffffd100/vendetta death <name>|r / |cffffd100undeath|r  " .. L["fix their kill count by hand"])
		print("  |cffffd100/vendetta scum <name>|r / |cffffd100unscum|r  " .. L["mark or clear scum"])
		print("  |cffffd100/vendetta nameplates|r  " .. L["switch on the enemy nameplates the radar needs"])
		print("  |cffffd100/vendetta range [n]|r  " .. L["show or push nameplate radar range"])
		print("  |cffffd100/vendetta sound|r  " .. L["toggle the sighting sounds"])
		print("  |cffffd100/vendetta detail <name>|r  " .. L["everything known about someone"])
		print("  |cffffd100/vendetta feedback|r  " .. L["link to leave feedback or report a bug"])
		print("  |cffffd100/vendetta debug|r  " .. L["what loaded and what did not"])
		print("  |cffffd100/vendetta wipe confirm|r  " .. L["clear everyone"])
	end
end

SLASH_PERSONALVENDETTA1 = "/vendetta"
SLASH_PERSONALVENDETTA2 = "/pv"
SlashCmdList.PERSONALVENDETTA = handleCommand

-- ===========================================================================
-- Wiring
-- ===========================================================================

ns.On("DB_READY", function()
	toggle(ns.db.settings.overlayShown ~= false)
end)

ns.On("LIST_CHANGED", function() refresh() end)
ns.On("RADAR_CHANGED", function() refresh() end)
ns.On("SIGHTED", alert)
ns.On("SETTINGS_CHANGED", function() refresh() end)
ns.On("QUIET_CHANGED", function() refresh() end)
ns.On("PENDING_CHANGED", function(added)
	if type(added) == "table" then
		for _, it in ipairs(added) do newPending[it.id] = true end
	end
	refresh()
end)

ns.Overlay = {
	Toggle = toggle,
	Refresh = function() refresh() end,
	ShowTab = showTab,
	SelectTab = function(which) selectTab(which) end,
	CurrentTab = function() return currentTab end,
	_addRows = function() return addRows end,
	_rows = function() return rows end,
	_tabs = function() return tabs end,
	_addPage = function() return addPage end,
}
