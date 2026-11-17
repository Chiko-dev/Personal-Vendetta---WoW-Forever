--[[-------------------------------------------------------------------------
  Personal Vendetta -- Settings
  The panel the minimap button opens. Two tabs:
    General   what the addon is for, nameplates, window, alert sounds
    Hit list  everyone who has killed you, with a Scum tickbox each

  Built from templates the Forever client ships (UICheckButtonTemplate,
  UISliderTemplate, UIPanelButtonTemplate, UIPanelCloseButton), each with a
  plain fallback.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local WIDTH = 540
local HEIGHT = 580
local INNER = WIDTH - 48          -- usable text width inside the border
local LIST_ROWS = 14
local LIST_ROW_H = 22

local frame
local controls = {}               -- anything with a .refresh
local tabs, pages = {}, {}
local listOffset = 0

local Settings = {}
ns.Settings = Settings

-- ===========================================================================
-- Widget helpers
-- ===========================================================================

local function make(kind, parent, template)
	if template then
		local ok, w = pcall(CreateFrame, kind, nil, parent, template)
		if ok and w then return w, true end
	end
	return CreateFrame(kind, nil, parent), false
end

local function text(parent, font, str, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	if width then
		fs:SetWidth(width)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(true)
	end
	if str then fs:SetText(str) end
	return fs
end

local function heading(parent, str, anchor, y)
	local fs = text(parent, "GameFontNormal", str)
	fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -16)
	return fs
end

-- A checkbox whose label wraps inside the panel instead of running out of it.
local function checkbox(parent, label, anchor, y, get, set)
	local cb = ns.CreateCheckButton(parent)
	cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, y or -4)

	local fs = text(parent, "GameFontHighlight", label, INNER - 30)
	fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.label = fs
	cb:SetHitRectInsets(0, -(INNER - 30), 0, 0)

	cb:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	cb.refresh = function() cb:SetChecked(get() and true or false) end
	controls[#controls + 1] = cb
	return cb
end

local function button(parent, label, w, h)
	local b, templated = make("Button", parent, "UIPanelButtonTemplate")
	b:SetSize(w, h or 22)
	if not templated then
		-- A bare Button has no font until it is given one.
		b:SetNormalFontObject("GameFontNormal")
		b:SetHighlightFontObject("GameFontHighlight")
	end
	b:SetText(label)
	return b
end

local function slider(parent)
	local s, templated = make("Slider", parent, "UISliderTemplate")
	if not templated then
		s:SetOrientation("HORIZONTAL")
		s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local track = s:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("LEFT", 4, 0)
		track:SetPoint("RIGHT", -4, 0)
		track:SetHeight(6)
		if track.SetColorTexture then track:SetColorTexture(0.25, 0.25, 0.25, 0.9) end
	end
	s:SetSize(150, 17)
	s:SetMinMaxValues(0, 100)
	s:SetValueStep(5)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	return s
end

-- One alert line:  Label  [<] Warhorn [>] [Test]
--                         Volume [======o====] 60%
-- kind is "normal" or "scum". Returns the lowest widget, for anchoring.
local function alertControls(parent, anchor, kind, labelText, labelColor)
	local label = text(parent, "GameFontHighlight", labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -12)
	if labelColor then label:SetTextColor(labelColor[1], labelColor[2], labelColor[3]) end

	local prev = button(parent, "<", 26)
	prev:SetPoint("LEFT", label, "LEFT", 74, 0)

	local name = text(parent, "GameFontHighlight")
	name:SetWidth(96)
	name:SetJustifyH("CENTER")
	name:SetPoint("LEFT", prev, "RIGHT", 4, 0)

	local nextB = button(parent, ">", 26)
	nextB:SetPoint("LEFT", name, "RIGHT", 4, 0)

	local test = button(parent, "Test", 56)
	test:SetPoint("LEFT", nextB, "RIGHT", 8, 0)

	local function showName() name:SetText(ns.Sound:Current(kind).label) end
	prev:SetScript("OnClick", function() ns.Sound:Cycle(kind, -1) ; showName() ; ns.Sound:Play(kind, true) end)
	nextB:SetScript("OnClick", function() ns.Sound:Cycle(kind, 1) ; showName() ; ns.Sound:Play(kind, true) end)
	test:SetScript("OnClick", function() ns.Sound:Play(kind, true) end)

	local volLabel = text(parent, "GameFontDisable", "Volume")
	volLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -16)

	local s = slider(parent)
	s:SetPoint("LEFT", volLabel, "LEFT", 74, 0)

	local value = text(parent, "GameFontHighlight")
	value:SetPoint("LEFT", s, "RIGHT", 10, 0)

	local syncing = false
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor((v or 0) + 0.5)
		value:SetText(v .. "%")
		if not syncing then ns.Sound:SetVolume(kind, v / 100) end
	end)
	-- Hear the new level when you let go, so you set it by ear.
	s:SetScript("OnMouseUp", function() ns.Sound:Play(kind, true) end)

	s.refresh = function()
		local pct = math.floor(ns.Sound:Volume(kind) * 100 + 0.5)
		syncing = true
		s:SetValue(pct)
		syncing = false
		value:SetText(pct .. "%")
		showName()
	end
	controls[#controls + 1] = s

	return volLabel
end

-- ===========================================================================
-- General tab
-- ===========================================================================

local function buildGeneral(page)
	local top = CreateFrame("Frame", nil, page)
	top:SetSize(1, 1)
	top:SetPoint("TOPLEFT", 0, 0)

	-- What this is, and what it is not.
	local notice = text(page, "GameFontNormalSmall",
		"This addon does not warn you about every enemy around you. It only "
		.. "tracks players who have killed you in the open world -- and only "
		.. "the ones you chose to add to your list.", INNER)
	notice:SetPoint("TOPLEFT", top, "TOPLEFT", 0, 0)
	notice:SetTextColor(1, 0.82, 0.3)

	-- Radar ------------------------------------------------------------------
	local hRadar = heading(page, "Radar", notice, -16)

	local status = text(page, "GameFontHighlightSmall", nil, INNER)
	status:SetPoint("TOPLEFT", hRadar, "BOTTOMLEFT", 0, -6)
	status.refresh = function()
		local on = ns.Radar:NameplatesOn()
		local range = ns.Radar:GetRange()
		if on then
			status:SetText("|cff44ff44Enemy nameplates are on.|r The radar sees up to "
				.. range .. " yards around you.")
		else
			status:SetText("|cffff4444Enemy nameplates are off -- the radar can't see anyone.|r "
				.. "Tick the box below to switch them on.")
		end
	end
	controls[#controls + 1] = status

	local plates = checkbox(page, "Enemy nameplates (the radar needs these)", status, -6,
		function() return ns.Radar:NameplatesOn() end,
		function(v)
			if v then
				ns.Radar:EnableNameplates()
			else
				local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
				ns.try(set, "nameplateShowEnemies", "0")
				ns.Print("Enemy nameplates off. The radar is blind until you switch them back on.")
			end
			Settings:Refresh()
		end)

	local openNp = button(page, "Open nameplate settings", 180)
	openNp:SetPoint("TOPLEFT", plates, "BOTTOMLEFT", 4, -4)
	openNp:SetScript("OnClick", function() ns.Radar:OpenNameplateSettings() end)

	-- Window -----------------------------------------------------------------
	local hWin = heading(page, "Window", openNp, -16)
	hWin:ClearAllPoints()
	hWin:SetPoint("TOPLEFT", openNp, "BOTTOMLEFT", -2, -16)

	local showWindow = checkbox(page, "Show the Vendetta window", hWin, -4,
		function() return ns.db.settings.overlayShown ~= false end,
		function(v) ns.Overlay.Toggle(v) end)

	local ask = checkbox(page, "Ask me after an enemy player kills me", showWindow, 0,
		function() return ns.db.settings.promptOnDeath end,
		function(v) ns.db.settings.promptOnDeath = v end)
	ask:ClearAllPoints()
	ask:SetPoint("TOPLEFT", showWindow, "BOTTOMLEFT", 0, 2)

	local askFight = checkbox(page, "Ask me after I survive a fight with an enemy player who came for me", ask, 0,
		function() return ns.db.settings.promptAfterFight end,
		function(v) ns.db.settings.promptAfterFight = v end)
	askFight:ClearAllPoints()
	askFight:SetPoint("TOPLEFT", ask, "BOTTOMLEFT", 0, 2)

	-- Alerts -----------------------------------------------------------------
	local hAlert = heading(page, "Alerts", askFight, -14)
	hAlert:ClearAllPoints()
	hAlert:SetPoint("TOPLEFT", askFight, "BOTTOMLEFT", 2, -14)

	local soundOn = checkbox(page, "Sound when someone from the list is near", hAlert, -4,
		function() return ns.db.settings.sound.enabled end,
		function(v) ns.db.settings.sound.enabled = v end)

	local afterNormal = alertControls(page, soundOn, "normal", "Normal")
	alertControls(page, afterNormal, "scum", ns.SKULL .. " Scum", { 1, 0.3, 0.3 })
end

-- ===========================================================================
-- Hit list tab
-- ===========================================================================

local listRows = {}
local listEmpty, listFooter, shareButton

-- Column x positions inside a row:
--   [scum] Name ......... race class ...... seen ...... They/You  [Note]
local COL_NAME, NAME_W = 34, 150
local DETAIL_W = 90
local SEEN_W = 92
local NOTE_W = 46

local function renderList()
	local entries = ns.List:ByDateAdded()
	local total = #entries
	local maxOffset = math.max(0, total - LIST_ROWS)
	if listOffset > maxOffset then listOffset = maxOffset end
	if listOffset < 0 then listOffset = 0 end

	for i = 1, LIST_ROWS do
		local row = listRows[i]
		local entry = entries[listOffset + i]
		if entry then
			local r, g, b = ns.ClassColor(entry.class)
			row.name:SetText(ns.LevelText(entry, ns.Radar and ns.Radar:Get(entry.key)) .. ns.FullName(entry))
			row.name:SetTextColor(r, g, b)
			local bits = {}
			if entry.race then bits[#bits + 1] = entry.race end
			if entry.className then bits[#bits + 1] = entry.className end
			row.detail:SetText(table.concat(bits, " "))

			local near = ns.Radar and ns.Radar:Get(entry.key)
			if near and not near.dead then
				row.seen:SetText("|cffff4444near you now|r")
			else
				row.seen:SetText(entry.lastSeen and ns.Ago(entry.lastSeen) or "|cff666666never|r")
			end

			row.score:SetText(string.format("|cffff6666%d|r / |cff66ff66%d|r",
				entry.theyKilledMe or 0, entry.iKilledThem or 0))
			row.scum:SetChecked(entry.scum and true or false)
			row.note:SetText(entry.note and "|cffffd100Note|r" or "|cff888888+ Note|r")
			row.key = entry.key
			row.entry = entry
			row.tint:SetShown(entry.scum and true or false)
			row:Show()
		else
			row.key, row.entry = nil, nil
			row:Hide()
		end
	end

	listEmpty:SetShown(total == 0)
	if total > LIST_ROWS then
		listFooter:SetText(string.format("Newest first. Showing %d-%d of %d, scroll for more.",
			listOffset + 1, math.min(total, listOffset + LIST_ROWS), total))
	elseif total > 0 then
		listFooter:SetText("Newest first. " .. (total == 1 and "1 player on your list." or (total .. " players on your list.")))
	else
		listFooter:SetText("")
	end

	if tabs.list then
		tabs.list:SetText(total > 0 and ("Hit list (" .. total .. ")") or "Hit list")
	end
	if shareButton and ns.Share then
		local canShare, why = ns.Share:CanShare()
		if canShare and total > 0 then
			shareButton:Enable()
		else
			shareButton:Disable()
		end
		shareButton.why = (total == 0) and "Your list is empty." or why
	end
end

local function buildList(page)
	local intro = text(page, "GameFontNormalSmall",
		"Everyone you added, newest first. Tick " .. ns.SCUM_COLOR .. "Scum|r for anyone who "
		.. "killed you dishonourably. Hover a name for details; click Note to write "
		.. "down what they did.", INNER)
	intro:SetPoint("TOPLEFT", 0, 0)
	intro:SetTextColor(1, 0.82, 0.3)

	-- Column headings
	local head = CreateFrame("Frame", nil, page)
	head:SetSize(INNER, 16)
	head:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
	local hScum = text(head, "GameFontNormalSmall", "Scum")
	hScum:SetPoint("LEFT", 0, 0)
	local hName = text(head, "GameFontNormalSmall", "Player")
	hName:SetPoint("LEFT", COL_NAME, 0)
	local hNote = text(head, "GameFontNormalSmall", "Note")
	hNote:SetPoint("RIGHT", -10, 0)
	local hScore = text(head, "GameFontNormalSmall", "|cffff6666They|r / |cff66ff66You|r")
	hScore:SetPoint("RIGHT", -(NOTE_W + 8), 0)
	local hSeen = text(head, "GameFontNormalSmall", "Last seen")
	hSeen:SetPoint("LEFT", COL_NAME + NAME_W + 4 + DETAIL_W + 4, 0)

	local holder = CreateFrame("Frame", nil, page)
	holder:SetSize(INNER, LIST_ROWS * LIST_ROW_H)
	holder:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
	holder:EnableMouseWheel(true)
	holder:SetScript("OnMouseWheel", function(_, delta)
		listOffset = listOffset - delta * 3
		renderList()
	end)

	for i = 1, LIST_ROWS do
		local row = CreateFrame("Frame", nil, holder)
		row:SetSize(INNER, LIST_ROW_H)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_H)

		-- zebra stripes, and a red tint on scum rows
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		if stripe.SetColorTexture then stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0) end
		row.tint = row:CreateTexture(nil, "BORDER")
		row.tint:SetAllPoints()
		if row.tint.SetColorTexture then row.tint:SetColorTexture(0.8, 0.05, 0.05, 0.22) end
		row.tint:Hide()

		row.scum = ns.CreateCheckButton(row)
		row.scum:SetSize(22, 22)
		row.scum:SetPoint("LEFT", 4, 0)
		row.scum:SetScript("OnClick", function(self)
			if row.key then ns.List:SetScum(row.key, self:GetChecked() and true or false) end
		end)
		row.scum:SetScript("OnEnter", function(self) ns.ScumTooltip(self) end)
		row.scum:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

		row.note = button(row, "+ Note", NOTE_W, 18)
		row.note:SetPoint("RIGHT", -2, 0)
		row.note:SetScript("OnClick", function()
			if row.key and ns.Notes then ns.Notes:Open(row.key) end
		end)
		row.note:SetScript("OnEnter", function(self)
			if not GameTooltip or not row.entry then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if row.entry.note then
				GameTooltip:AddLine("Note", 1, 0.82, 0.3)
				GameTooltip:AddLine(row.entry.note, 1, 1, 1, true)
				GameTooltip:AddLine("Click to edit.", 0.6, 0.6, 0.6)
			else
				GameTooltip:AddLine("Add a note: what did they do?", 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		row.note:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

		row.score = text(row, "GameFontHighlightSmall")
		row.score:SetPoint("RIGHT", row.note, "LEFT", -8, 0)

		row.name = text(row, "GameFontNormalSmall")
		row.name:SetPoint("LEFT", COL_NAME, 0)
		row.name:SetWidth(NAME_W)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)

		row.detail = text(row, "GameFontDisableSmall")
		row.detail:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
		row.detail:SetWidth(DETAIL_W)
		row.detail:SetJustifyH("LEFT")
		row.detail:SetWordWrap(false)

		row.seen = text(row, "GameFontDisableSmall")
		row.seen:SetPoint("LEFT", row.detail, "RIGHT", 4, 0)
		row.seen:SetPoint("RIGHT", row.score, "LEFT", -6, 0)
		row.seen:SetJustifyH("LEFT")
		row.seen:SetWordWrap(false)

		-- Hover anywhere on the row for the full picture.
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			if self.entry then ns.EntryTooltip(self, self.entry) end
		end)
		row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function(_, delta)
			listOffset = listOffset - delta * 3
			renderList()
		end)

		row:Hide()
		listRows[i] = row
	end

	listEmpty = text(page, "GameFontDisable",
		"Nobody yet. When an enemy player kills you in the open world, or you survive "
		.. "a fight with one, you'll be asked whether to add them.", INNER - 20)
	listEmpty:SetPoint("TOP", holder, "TOP", 0, -40)
	listEmpty:SetJustifyH("CENTER")

	listFooter = text(page, "GameFontDisableSmall")
	listFooter:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)

	-- Share with the group
	shareButton = button(page, "Share with party", 140)
	shareButton:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -4)
	shareButton:SetScript("OnClick", function()
		if ns.Share then ns.Share:Send() end
		renderList()
	end)
	shareButton:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Share your hit list")
		GameTooltip:AddLine("Sends everyone on your list to the people in your party or raid "
			.. "who also run Personal Vendetta. They choose whether to import, and only "
			.. "players they don't already have are added.", 1, 1, 1, true)
		if self.why and not self:IsEnabled() then
			GameTooltip:AddLine(self.why, 1, 0.3, 0.3, true)
		end
		GameTooltip:Show()
	end)
	shareButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- ===========================================================================
-- Frame and tabs
-- ===========================================================================

local function selectTab(which)
	for name, page in pairs(pages) do page:SetShown(name == which) end
	for name, tab in pairs(tabs) do
		if name == which then
			tab:LockHighlight()
		else
			tab:UnlockHighlight()
		end
	end
	if which == "list" then renderList() end
	Settings.current = which
end

local function build()
	frame = CreateFrame("Frame", "PersonalVendettaSettings", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)
	frame:Hide()

	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
	end

	-- Escape closes it, like any Blizzard panel.
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "PersonalVendettaSettings")
	end

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(28, 28)
	logo:SetPoint("TOPLEFT", 18, -14)
	if not logo:SetTexture(ns.ICON) then
		logo:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	end

	local title = text(frame, "GameFontNormalLarge", "|cff9933ffPersonal Vendetta|r")
	title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

	local version = text(frame, "GameFontDisableSmall", "v" .. ns.VERSION)
	version:SetPoint("LEFT", title, "RIGHT", 6, -1)

	local close, closeTemplated = make("Button", frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	if not closeTemplated then
		close:SetSize(24, 24)
		close:SetNormalFontObject("GameFontNormal")
		close:SetText("x")
	end
	close:SetScript("OnClick", function() frame:Hide() end)

	-- Tabs
	tabs.general = button(frame, "General", 110, 24)
	tabs.general:SetPoint("TOPLEFT", 20, -50)
	tabs.list = button(frame, "Hit list", 130, 24)
	tabs.list:SetPoint("LEFT", tabs.general, "RIGHT", 6, 0)
	tabs.general:SetScript("OnClick", function() selectTab("general") end)
	tabs.list:SetScript("OnClick", function() selectTab("list") end)

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 18, -80)
	rule:SetPoint("TOPRIGHT", -18, -80)
	if rule.SetColorTexture then rule:SetColorTexture(0.6, 0.3, 0.9, 0.5) end

	for _, name in ipairs({ "general", "list" }) do
		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", 24, -92)
		page:SetPoint("BOTTOMRIGHT", -24, 34)
		pages[name] = page
	end
	buildGeneral(pages.general)
	buildList(pages.list)

	local foot = text(frame, "GameFontDisableSmall",
		"/vendetta help lists every command.")
	foot:SetPoint("BOTTOMLEFT", 24, 16)

	frame:SetScript("OnShow", function()
		Settings:Refresh()
		selectTab(Settings.current or "general")
	end)
	return frame
end

-- ===========================================================================
-- Public
-- ===========================================================================

function Settings:Refresh()
	if not frame then return end
	for _, c in ipairs(controls) do
		if c.refresh then c.refresh() end
	end
	if pages.list and pages.list:IsShown() then renderList() end
	if tabs.list then
		local total = ns.List:Count()
		tabs.list:SetText(total > 0 and ("Hit list (" .. total .. ")") or "Hit list")
	end
end

function Settings:Toggle(show)
	if not frame then build() end
	if show == nil then show = not frame:IsShown() end
	frame:SetShown(show)
end

function Settings:Open(tab)
	if not frame then build() end
	Settings.current = tab or Settings.current or "general"
	frame:Show()
	selectTab(Settings.current)
end

-- Keep the boxes honest when something changes from a slash command,
-- the V key, or the list itself.
ns.On("SETTINGS_CHANGED", function() Settings:Refresh() end)
ns.On("LIST_CHANGED", function() Settings:Refresh() end)
ns.On("GROUP_CHANGED", function() Settings:Refresh() end)
