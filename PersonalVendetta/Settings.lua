--[[-------------------------------------------------------------------------
  Personal Vendetta -- Settings
  The panel the minimap button opens. Four tabs:
    General   what the addon is for, the radar, what gets queued, shared list
    Window    the floating window: show, lock, auto-hide, scale, opacity
    Alerts    sounds, celebrating a settled score, party alerts
    Hit list  everyone on your list: search, sort, scum, notes, details, share

  Built from templates the Forever client ships (UICheckButtonTemplate,
  UISliderTemplate, UIPanelButtonTemplate, UIPanelCloseButton,
  InputBoxTemplate), each with a plain fallback.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local WIDTH = 540
local HEIGHT = 580
local INNER = WIDTH - 48          -- usable text width inside the border
local LIST_ROWS = 13
local LIST_ROW_H = 22
local FEEDBACK_URL = "https://www.curseforge.com/wow/addons/personal-vendetta-pvp/comments"
ns.FEEDBACK_URL = FEEDBACK_URL

local frame
local controls = {}               -- anything with a .refresh
local tabs, pages = {}, {}
local listOffset = 0
local searchText = ""

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

local function heading(parent, str, anchor, y, x)
	local fs = text(parent, "GameFontNormal", str)
	if anchor then
		fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -16)
	else
		fs:SetPoint("TOPLEFT", 0, 0)
	end
	return fs
end

-- A checkbox whose label wraps inside the panel instead of running out of it.
local function checkbox(parent, label, anchor, y, get, set, x)
	local cb = ns.CreateCheckButton(parent)
	cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or -2, y or -4)

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

-- Stack a checkbox right under another one.
local function under(cb, prev)
	cb:ClearAllPoints()
	cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 2)
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

-- Label, slider and value on one line. get/set work in slider units.
local function slider(parent, label, anchor, y, minV, maxV, step, get, set, fmt, onRelease)
	local lab = text(parent, "GameFontHighlight", label)
	lab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, y or -16)

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
	s:SetSize(180, 17)
	s:SetPoint("LEFT", lab, "LEFT", 150, 0)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

	local value = text(parent, "GameFontHighlight")
	value:SetPoint("LEFT", s, "RIGHT", 10, 0)

	local syncing = false
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor((v or 0) / step + 0.5) * step
		value:SetText(string.format(fmt or "%d", v))
		if not syncing then set(v) end
	end)
	if onRelease then s:SetScript("OnMouseUp", onRelease) end
	s.refresh = function()
		syncing = true
		s:SetValue(get())
		syncing = false
		value:SetText(string.format(fmt or "%d", get()))
	end
	controls[#controls + 1] = s
	s.label = lab
	return s, lab
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
	name:SetWidth(110)
	name:SetJustifyH("CENTER")
	name:SetPoint("LEFT", prev, "RIGHT", 4, 0)

	local nextB = button(parent, ">", 26)
	nextB:SetPoint("LEFT", name, "RIGHT", 4, 0)

	local test = button(parent, L["Test"], 60)
	test:SetPoint("LEFT", nextB, "RIGHT", 8, 0)

	local function showName() name:SetText(L[ns.Sound:Current(kind).label]) end
	prev:SetScript("OnClick", function() ns.Sound:Cycle(kind, -1) ; showName() ; ns.Sound:Play(kind, true) end)
	nextB:SetScript("OnClick", function() ns.Sound:Cycle(kind, 1) ; showName() ; ns.Sound:Play(kind, true) end)
	test:SetScript("OnClick", function() ns.Sound:Play(kind, true) end)

	local s = slider(parent, L["Volume"], label, -16, 0, 100, 5,
		function() return math.floor(ns.Sound:Volume(kind) * 100 + 0.5) end,
		function(v) ns.Sound:SetVolume(kind, v / 100) end,
		"%d%%",
		function() ns.Sound:Play(kind, true) end) -- hear it when you let go
	s.label:ClearAllPoints()
	s.label:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -16)
	s:ClearAllPoints()
	s:SetPoint("LEFT", s.label, "LEFT", 74, 0)
	local oldRefresh = s.refresh
	s.refresh = function() oldRefresh() ; showName() end

	return s.label
end

-- ===========================================================================
-- General tab
-- ===========================================================================

local function buildGeneral(page)
	local notice = text(page, "GameFontNormalSmall",
		L["This addon does not warn you about every enemy around you. It only tracks players who have killed you in the open world -- and only the ones you chose to add to your list."], INNER)
	notice:SetPoint("TOPLEFT", 0, 0)
	notice:SetTextColor(1, 0.82, 0.3)

	-- Radar ------------------------------------------------------------------
	local hRadar = heading(page, L["Radar"], notice, -16)

	local status = text(page, "GameFontHighlightSmall", nil, INNER)
	status:SetPoint("TOPLEFT", hRadar, "BOTTOMLEFT", 0, -6)
	status.refresh = function()
		if ns.Radar:NameplatesOn() then
			status:SetText("|cff44ff44" .. L["Enemy nameplates are on."] .. "|r "
				.. string.format(L["The radar sees up to %s yards around you."], ns.Radar:GetRange()))
		else
			status:SetText("|cffff4444" .. L["Enemy nameplates are off -- the radar can't see anyone."] .. "|r "
				.. L["Tick the box below to switch them on."])
		end
	end
	controls[#controls + 1] = status

	local plates = checkbox(page, L["Enemy nameplates (the radar needs these)"], status, -6,
		function() return ns.Radar:NameplatesOn() end,
		function(v)
			if v then
				ns.Radar:EnableNameplates()
			else
				ns.Radar:DisableNameplates()
			end
			Settings:Refresh()
		end)

	local marks = under(checkbox(page, L["Mark listed players' nameplates with a skull"], plates, 0,
		function() return ns.db.settings.markNameplates end,
		function(v) ns.db.settings.markNameplates = v ; ns.Fire("SETTINGS_CHANGED") end), plates)

	local openNp = button(page, L["Open nameplate settings"], 190)
	openNp:SetPoint("TOPLEFT", marks, "BOTTOMLEFT", 4, -4)
	openNp:SetScript("OnClick", function() ns.Radar:OpenNameplateSettings() end)

	-- What gets collected ----------------------------------------------------
	local hCollect = heading(page, L["Your list"], openNp, -16, -2)

	local ask = checkbox(page, L["Queue players who kill me in the To add tab"], hCollect, -4,
		function() return ns.db.settings.promptOnDeath end,
		function(v) ns.db.settings.promptOnDeath = v end)
	local askFight = under(checkbox(page, L["Also queue enemy players I survive a fight with"], ask, 0,
		function() return ns.db.settings.promptAfterFight end,
		function(v) ns.db.settings.promptAfterFight = v end), ask)
	local shared = under(checkbox(page, L["Share one hit list across all my characters"], askFight, 0,
		function() return ns.IsAccountWide() end,
		function(v) ns.SetAccountWide(v) end), askFight)

	local sharedHelp = text(page, "GameFontDisableSmall",
		L["Turning it on merges this character's list in; anyone on both keeps both scores, added together. Turning it off takes each character back to its own list."], INNER - 30)
	sharedHelp:SetPoint("TOPLEFT", shared, "BOTTOMLEFT", 28, 0)
end

-- ===========================================================================
-- Window tab
-- ===========================================================================

local function buildWindow(page)
	local h = heading(page, L["Floating window"])

	local show = checkbox(page, L["Show the Vendetta window"], h, -4,
		function() return ns.db.settings.overlayShown ~= false end,
		function(v) ns.Overlay.Toggle(v) end)
	local lock = under(checkbox(page, L["Lock its position"], show, 0,
		function() return ns.db.settings.window.locked end,
		function(v) ns.db.settings.window.locked = v end), show)
	local auto = under(checkbox(page, L["Hide it completely when nobody is near and nothing is waiting"], lock, 0,
		function() return ns.db.settings.window.autoHide end,
		function(v) ns.db.settings.window.autoHide = v ; ns.Fire("SETTINGS_CHANGED") end), lock)

	local scale = slider(page, L["Size"], auto, -20, 60, 160, 5,
		function() return math.floor((ns.db.settings.window.scale or 1) * 100 + 0.5) end,
		function(v) ns.db.settings.window.scale = v / 100 ; ns.Fire("SETTINGS_CHANGED") end, "%d%%")
	local opacity = slider(page, L["Background opacity"], scale.label, -26, 0, 100, 5,
		function() return math.floor((ns.db.settings.window.opacity or 0.55) * 100 + 0.5) end,
		function(v) ns.db.settings.window.opacity = v / 100 ; ns.Fire("SETTINGS_CHANGED") end, "%d%%")
	opacity.label:ClearAllPoints()
	opacity.label:SetPoint("TOPLEFT", scale.label, "BOTTOMLEFT", 0, -26)

	local reset = button(page, L["Reset position"], 140)
	reset:SetPoint("TOPLEFT", opacity.label, "BOTTOMLEFT", -2, -24)
	reset:SetScript("OnClick", function()
		ns.db.settings.overlayPoint = nil
		local o = _G.PersonalVendettaOverlay
		if o then
			o:ClearAllPoints()
			o:SetPoint("CENTER", UIParent, "CENTER", 300, 80)
		end
	end)

	local tip = text(page, "GameFontDisableSmall",
		L["Tip: the dot in the window's corner is the radar. Green means it can see; red means enemy nameplates are off."], INNER)
	tip:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 2, -16)
end

-- ===========================================================================
-- Alerts tab
-- ===========================================================================

local function buildAlerts(page)
	local h = heading(page, L["Sounds"])

	local soundOn = checkbox(page, L["Sound when someone from the list comes near"], h, -4,
		function() return ns.db.settings.sound.enabled end,
		function(v) ns.db.settings.sound.enabled = v end)
	local once = text(page, "GameFontDisableSmall",
		L["Each player sounds once. If they step out of range and back, they have to be gone 30 seconds before it sounds again."], INNER - 30)
	once:SetPoint("TOPLEFT", soundOn, "BOTTOMLEFT", 28, 0)

	local quietCap = checkbox(page, L["Stay quiet in capital cities (Stormwind, Orgrimmar...)"], once, -2,
		function() return ns.db.settings.sound.quietCapitals end,
		function(v) ns.db.settings.sound.quietCapitals = v end, -28)
	local quietTown = under(checkbox(page, L["Stay quiet in towns and inns (Gadgetzan, Booty Bay...)"], quietCap, 0,
		function() return ns.db.settings.sound.quietTowns end,
		function(v) ns.db.settings.sound.quietTowns = v end), quietCap)
	local quietNote = text(page, "GameFontDisableSmall",
		L["No horn, chat line or party alert there. The window still shows who is near."], INNER - 30)
	quietNote:SetPoint("TOPLEFT", quietTown, "BOTTOMLEFT", 28, 0)

	local afterNormal = alertControls(page, quietNote, "normal", L["Normal"])
	local afterScum = alertControls(page, afterNormal, "scum", ns.SKULL .. " " .. L["Scum"], { 1, 0.3, 0.3 })

	local hScore = heading(page, L["Score"], afterScum, -22, -4)
	local celebrate = checkbox(page, L["Celebrate when I settle a score or get a kill streak"], hScore, -4,
		function() return ns.db.settings.celebrate end,
		function(v) ns.db.settings.celebrate = v end)

	local hParty = heading(page, L["Party"], celebrate, -14, 2)
	local send = checkbox(page, L["Tell my group when I spot someone from my list"], hParty, -4,
		function() return ns.db.settings.partyAlertSend end,
		function(v) ns.db.settings.partyAlertSend = v end)
	under(checkbox(page, L["Show me when my group spots someone"], send, 0,
		function() return ns.db.settings.partyAlertReceive end,
		function(v) ns.db.settings.partyAlertReceive = v end), send)
end

-- ===========================================================================
-- Hit list tab
-- ===========================================================================

local listRows = {}
local listEmpty, listFooter, shareButton, sortButton, searchBox

-- Column x positions inside a row:
--   [scum] Name ......... race class ...... seen ...... They/You  [Note]
local COL_NAME, NAME_W = 34, 150
local DETAIL_W = 90
local NOTE_W = 46

local SORTS = {
	{ id = "newest", label = "Newest" },
	{ id = "deaths", label = "Most deaths" },
	{ id = "kills", label = "Most kills" },
	{ id = "scum", label = "Scum first" },
	{ id = "seen", label = "Last seen" },
	{ id = "name", label = "Name" },
}

local function sortIndex()
	local id = ns.db.settings.listSort or "newest"
	for i, s in ipairs(SORTS) do if s.id == id then return i end end
	return 1
end

-- The list as shown: filtered by the search box, ordered by the sort.
function Settings:VisibleEntries()
	local all = ns.List:ByDateAdded()
	local q = string.lower(searchText or "")
	local out = {}
	for _, e in ipairs(all) do
		local hit = (q == "")
		if not hit then
			for _, field in ipairs({ ns.FullName(e), e.className, e.race, e.note, e.lastZone, e.sharedBy }) do
				if field and string.find(string.lower(field), q, 1, true) then hit = true break end
			end
		end
		if hit then out[#out + 1] = e end
	end

	local mode = SORTS[sortIndex()].id
	local function newest(a, b) return (a.firstAdded or 0) > (b.firstAdded or 0) end
	local cmp = newest
	if mode == "deaths" then
		cmp = function(a, b)
			if (a.theyKilledMe or 0) ~= (b.theyKilledMe or 0) then return (a.theyKilledMe or 0) > (b.theyKilledMe or 0) end
			return newest(a, b)
		end
	elseif mode == "kills" then
		cmp = function(a, b)
			if (a.iKilledThem or 0) ~= (b.iKilledThem or 0) then return (a.iKilledThem or 0) > (b.iKilledThem or 0) end
			return newest(a, b)
		end
	elseif mode == "scum" then
		cmp = function(a, b)
			if (a.scum and true or false) ~= (b.scum and true or false) then return a.scum and true or false end
			return newest(a, b)
		end
	elseif mode == "seen" then
		cmp = function(a, b)
			if (a.lastSeen or 0) ~= (b.lastSeen or 0) then return (a.lastSeen or 0) > (b.lastSeen or 0) end
			return newest(a, b)
		end
	elseif mode == "name" then
		cmp = function(a, b) return string.lower(ns.FullName(a)) < string.lower(ns.FullName(b)) end
	end
	table.sort(out, cmp)
	return out, #all
end

function Settings:SetSearch(q)
	searchText = q or ""
	listOffset = 0
	if searchBox and searchBox:GetText() ~= searchText then searchBox:SetText(searchText) end
	Settings:Refresh()
end

function Settings:SetSort(id)
	for _, s in ipairs(SORTS) do
		if s.id == id then
			ns.db.settings.listSort = id
			listOffset = 0
			Settings:Refresh()
			return id
		end
	end
end

function Settings:CycleSort()
	local i = sortIndex() % #SORTS + 1
	ns.db.settings.listSort = SORTS[i].id
	listOffset = 0
	Settings:Refresh()
	return SORTS[i].id
end

local function renderList()
	local entries, total = Settings:VisibleEntries()
	local shownTotal = #entries
	local maxOffset = math.max(0, shownTotal - LIST_ROWS)
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
				row.seen:SetText("|cffff4444" .. L["near you now"] .. "|r")
			else
				row.seen:SetText(entry.lastSeen and ns.Ago(entry.lastSeen) or ("|cff666666" .. L["never"] .. "|r"))
			end

			row.score:SetText(string.format("|cffff6666%d|r / |cff66ff66%d|r",
				entry.theyKilledMe or 0, entry.iKilledThem or 0))
			row.scum:SetChecked(entry.scum and true or false)
			row.note:SetText(entry.note and ("|cffffd100" .. L["Note"] .. "|r") or ("|cff888888+ " .. L["Note"] .. "|r"))
			row.key = entry.key
			row.entry = entry
			row.tint:SetShown(entry.scum and true or false)
			row:Show()
		else
			row.key, row.entry = nil, nil
			row:Hide()
		end
	end

	listEmpty:SetShown(shownTotal == 0)
	listEmpty:SetText(total == 0
		and L["Nobody yet. When an enemy player kills you in the open world, or you survive a fight with one, they wait in the To add tab of the floating window."]
		or string.format(L["Nobody matches \"%s\"."], searchText))

	local sortLabel = L[SORTS[sortIndex()].label]
	if shownTotal > LIST_ROWS then
		listFooter:SetText(string.format(L["%s. Showing %d-%d of %d, scroll for more. Click a name for details."],
			sortLabel, listOffset + 1, math.min(shownTotal, listOffset + LIST_ROWS), shownTotal))
	elseif shownTotal > 0 then
		listFooter:SetText(string.format(L["%s. %d of %d players. Click a name for details."], sortLabel, shownTotal, total))
	else
		listFooter:SetText("")
	end

	if sortButton then
		sortButton:SetText(string.format(L["Sort: %s"], sortLabel))
		if sortButton.ValidateResetState then pcall(sortButton.ValidateResetState, sortButton) end
	end
	if tabs.list then
		tabs.list:SetText(total > 0 and string.format(L["Hit list (%d)"], total) or L["Hit list"])
	end
	if shareButton and ns.Share then
		local canShare, why = ns.Share:CanShare()
		if canShare and total > 0 then shareButton:Enable() else shareButton:Disable() end
		shareButton.why = (total == 0) and L["Your list is empty."] or why
	end
end

local function buildList(page)
	-- Toolbar: search on the left, the sort filter on the right.
	local SORT_W = 170
	local box, templated = make("EditBox", page, "InputBoxTemplate")
	box:SetSize(INNER - SORT_W - 24, 22)
	box:SetPoint("TOPLEFT", 6, 0)
	box:SetAutoFocus(false)
	if not templated then box:SetFontObject("ChatFontNormal") end
	box:SetScript("OnTextChanged", function(self)
		searchText = self:GetText() or ""
		listOffset = 0
		renderList()
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText("") ; self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	searchBox = box

	-- The hint sits inside the box as a placeholder, so it can never run
	-- into the sort button however long the translation is.
	local hint = text(page, "GameFontDisableSmall", L["Search name, class, race, zone or note"])
	hint:SetPoint("LEFT", box, "LEFT", 2, 0)
	hint:SetPoint("RIGHT", box, "RIGHT", -6, 0)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)
	box:SetScript("OnEditFocusGained", function() hint:Hide() end)
	box:SetScript("OnEditFocusLost", function(self) hint:SetShown((self:GetText() or "") == "") end)

	-- Sort: Blizzard's filter dropdown when this client has it, else a
	-- button that steps through the orders.
	local dd, ddOk = make("DropdownButton", page, "WowStyle1FilterDropdownTemplate")
	if ddOk and dd.SetupMenu then
		dd:SetWidth(SORT_W)
		dd:SetPoint("TOPRIGHT", -2, -1)
		dd.resizeToText = false
		dd:SetupMenu(function(_, root)
			if root.CreateTitle then root:CreateTitle(L["Sort by"]) end
			for _, s in ipairs(SORTS) do
				root:CreateRadio(L[s.label],
					function() return (ns.db.settings.listSort or "newest") == s.id end,
					function() Settings:SetSort(s.id) end)
			end
		end)
		if dd.SetIsDefaultCallback then
			dd:SetIsDefaultCallback(function() return (ns.db.settings.listSort or "newest") == "newest" end)
			dd:SetDefaultCallback(function() Settings:SetSort("newest") end)
		end
		dd.isDropdown = true
		sortButton = dd
	else
		sortButton = button(page, L["Sort: Newest"], SORT_W)
		sortButton:SetPoint("TOPRIGHT", 0, 0)
		sortButton:SetScript("OnClick", function() Settings:CycleSort() end)
	end

	-- Column headings
	local head = CreateFrame("Frame", nil, page)
	head:SetSize(INNER, 16)
	head:SetPoint("TOPLEFT", 0, -32)
	local hScum = text(head, "GameFontNormalSmall", L["Scum"])
	hScum:SetPoint("LEFT", 0, 0)
	local hName = text(head, "GameFontNormalSmall", L["Player"])
	hName:SetPoint("LEFT", COL_NAME, 0)
	local hNote = text(head, "GameFontNormalSmall", L["Note"])
	hNote:SetPoint("RIGHT", -10, 0)
	local hScore = text(head, "GameFontNormalSmall", "|cffff6666" .. L["They"] .. "|r / |cff66ff66" .. L["You"] .. "|r")
	hScore:SetPoint("RIGHT", -(NOTE_W + 8), 0)
	local hSeen = text(head, "GameFontNormalSmall", L["Last seen"])
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
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		if hl.SetColorTexture then hl:SetColorTexture(1, 1, 1, 0.06) end

		row.scum = ns.CreateCheckButton(row)
		row.scum:SetSize(22, 22)
		row.scum:SetPoint("LEFT", 4, 0)
		row.scum:SetScript("OnClick", function(self)
			if row.key then ns.List:SetScum(row.key, self:GetChecked() and true or false) end
		end)
		row.scum:SetScript("OnEnter", function(self) ns.ScumTooltip(self) end)
		row.scum:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

		row.note = button(row, "+ " .. L["Note"], NOTE_W, 18)
		row.note:SetPoint("RIGHT", -2, 0)
		row.note:SetScript("OnClick", function()
			if row.key and ns.Notes then ns.Notes:Open(row.key) end
		end)
		row.note:SetScript("OnEnter", function(self)
			if not GameTooltip or not row.entry then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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

		-- Hover for the summary; click for the full story.
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			if self.entry then ns.EntryTooltip(self, self.entry) end
		end)
		row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		row:SetScript("OnMouseUp", function(self, mouse)
			if mouse == "LeftButton" and self.key and ns.Detail then ns.Detail:Open(self.key) end
		end)

		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function(_, delta)
			listOffset = listOffset - delta * 3
			renderList()
		end)

		row:Hide()
		listRows[i] = row
	end

	listEmpty = text(page, "GameFontDisable", nil, INNER - 20)
	listEmpty:SetPoint("TOP", holder, "TOP", 0, -40)
	listEmpty:SetJustifyH("CENTER")

	listFooter = text(page, "GameFontDisableSmall", nil, INNER - 160)
	listFooter:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -8)

	-- Share with the group
	shareButton = button(page, L["Share with party"], 140)
	shareButton:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -4)
	shareButton:SetScript("OnClick", function()
		if ns.Share then ns.Share:Send() end
		renderList()
	end)
	shareButton:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Share your hit list"])
		GameTooltip:AddLine(L["Sends everyone on your list to the people in your party or raid who also run Personal Vendetta. They choose whether to import, and only players they don't already have are added."], 1, 1, 1, true)
		if self.why and not self:IsEnabled() then
			GameTooltip:AddLine(self.why, 1, 0.3, 0.3, true)
		end
		GameTooltip:Show()
	end)
	shareButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- ===========================================================================
-- Feedback
-- ===========================================================================

local feedbackFrame

function Settings:Feedback()
	if not feedbackFrame then
		local f = CreateFrame("Frame", "PersonalVendettaFeedback", UIParent, "BackdropTemplate")
		f:SetSize(460, 200)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		if f.SetBackdrop then
			f:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 24,
				insets = { left = 6, right = 6, top = 6, bottom = 6 },
			})
		end
		if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "PersonalVendettaFeedback") end

		local t = text(f, "GameFontNormalLarge", "|cff9933ff" .. L["Feedback and bug reports"] .. "|r")
		t:SetPoint("TOPLEFT", 22, -20)
		local body = text(f, "GameFontHighlightSmall",
			L["Ideas, bugs, or something that annoys you? Leave a comment on the CurseForge page. Press Ctrl+C to copy the link, then paste it into your browser."], 416)
		body:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)

		local function copyBox(value, anchor, y)
			local b, templated = make("EditBox", f, "InputBoxTemplate")
			b:SetSize(410, 22)
			b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, y)
			b:SetAutoFocus(false)
			if not templated then b:SetFontObject("ChatFontNormal") end
			b.value = value
			b:SetText(value)
			-- Read-only: anything typed snaps back to the value.
			b:SetScript("OnTextChanged", function(self) if self:GetText() ~= self.value then self:SetText(self.value) end end)
			b:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
			b:SetScript("OnMouseUp", function(self) self:SetFocus() ; self:HighlightText() end)
			b:SetScript("OnEscapePressed", function() f:Hide() end)
			return b
		end
		f.url = copyBox(FEEDBACK_URL, body, -10)

		local vlab = text(f, "GameFontHighlightSmall", L["Reporting a bug? Include this line:"])
		vlab:SetPoint("TOPLEFT", f.url, "BOTTOMLEFT", -6, -12)
		local okB, version, build = ns.try(GetBuildInfo)
		local info = string.format("Personal Vendetta %s | WoW %s (%s) | %s", ns.VERSION,
			okB and ns.S(version) or "?", okB and ns.S(build) or "?", ns.LOCALE or "?")
		f.info = copyBox(info, vlab, -6)

		local close = button(f, L["Close"], 90)
		close:SetPoint("BOTTOMRIGHT", -20, 16)
		close:SetScript("OnClick", function() f:Hide() end)
		f:SetScript("OnShow", function() f.url:SetFocus() ; f.url:HighlightText() end)
		feedbackFrame = f
	end
	feedbackFrame:Show()
	return feedbackFrame
end

-- ===========================================================================
-- Frame and tabs
-- ===========================================================================

local TAB_ORDER = { "general", "window", "alerts", "list" }

local function selectTab(which)
	for name, page in pairs(pages) do page:SetShown(name == which) end
	for name, tab in pairs(tabs) do
		if name == which then tab:LockHighlight() else tab:UnlockHighlight() end
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
	local tabLabels = { general = L["General"], window = L["Window"], alerts = L["Alerts"], list = L["Hit list"] }
	local prevTab
	for _, key in ipairs(TAB_ORDER) do
		local t = button(frame, tabLabels[key], key == "list" and 130 or 100, 24)
		if prevTab then
			t:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
		else
			t:SetPoint("TOPLEFT", 20, -50)
		end
		t:SetScript("OnClick", function() selectTab(key) end)
		tabs[key] = t
		prevTab = t
	end

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 18, -80)
	rule:SetPoint("TOPRIGHT", -18, -80)
	if rule.SetColorTexture then rule:SetColorTexture(0.6, 0.3, 0.9, 0.5) end

	for _, name in ipairs(TAB_ORDER) do
		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", 24, -92)
		page:SetPoint("BOTTOMRIGHT", -24, 40)
		pages[name] = page
	end
	buildGeneral(pages.general)
	buildWindow(pages.window)
	buildAlerts(pages.alerts)
	buildList(pages.list)

	local feedback = button(frame, L["Feedback / report a bug"], 190)
	feedback:SetPoint("BOTTOMLEFT", 20, 14)
	feedback:SetScript("OnClick", function() Settings:Feedback() end)

	local foot = text(frame, "GameFontDisableSmall", L["/vendetta help lists every command."])
	foot:SetPoint("LEFT", feedback, "RIGHT", 12, 0)

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
		tabs.list:SetText(total > 0 and string.format(L["Hit list (%d)"], total) or L["Hit list"])
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
