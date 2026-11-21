--[[-------------------------------------------------------------------------
  Personal Vendetta -- Settings
  The Settings tab of the main window (Main.lua), in three sections:
    General   what the addon is for, the radar, what gets queued, shared list
    Window    the floating window: show, lock, auto-hide, scale, opacity
    Alerts    sounds, quiet places, celebrating a settled score, party alerts

  Also the search and sort behind the Hit list page, and the feedback box.
  Built from templates the Forever client ships, each with a plain fallback.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local INNER = 500                 -- usable text width of a settings section
local FEEDBACK_URL = "https://www.curseforge.com/wow/addons/personal-vendetta-pvp/comments"
ns.FEEDBACK_URL = FEEDBACK_URL

local built = false
local controls = {}               -- anything with a .refresh
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
		function(v) ns.db.settings.sound.quietCapitals = v ; ns.Fire("QUIET_CHANGED") end, -28)
	local quietTown = under(checkbox(page, L["Stay quiet in towns and inns (Gadgetzan, Booty Bay...)"], quietCap, 0,
		function() return ns.db.settings.sound.quietTowns end,
		function(v) ns.db.settings.sound.quietTowns = v ; ns.Fire("QUIET_CHANGED") end), quietCap)
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
	local recv = under(checkbox(page, L["Show me when my group spots someone"], send, 0,
		function() return ns.db.settings.partyAlertReceive end,
		function(v) ns.db.settings.partyAlertReceive = v end), send)

	-- Warning everyone else, addon or not.
	local warnBtn = under(checkbox(page, L["Warn button on scum: one click yells it to everyone around you"], recv, 0,
		function() return ns.db.settings.scumWarnButton end,
		function(v) ns.db.settings.scumWarnButton = v ; ns.Fire("SETTINGS_CHANGED") end), recv)
	under(checkbox(page, L["Post a warning in party or raid chat when scum is spotted"], warnBtn, 0,
		function() return ns.db.settings.scumWarnParty end,
		function(v) ns.db.settings.scumWarnParty = v end), warnBtn)
end

-- ===========================================================================
-- Hit list tab
-- ===========================================================================

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
	if ns.Main then ns.Main:SyncSearch(searchText) end
	Settings:Refresh()
end
function Settings:GetSearch() return searchText end

Settings.SORTS = SORTS
function Settings:SortLabel() return L[SORTS[sortIndex()].label] end

function Settings:SetSort(id)
	for _, s in ipairs(SORTS) do
		if s.id == id then
			ns.db.settings.listSort = id
			Settings:Refresh()
			return id
		end
	end
end

function Settings:CycleSort()
	local i = sortIndex() % #SORTS + 1
	ns.db.settings.listSort = SORTS[i].id
	Settings:Refresh()
	return SORTS[i].id
end

-- ===========================================================================
-- Feedback
-- ===========================================================================

local feedbackFrame

function Settings:Feedback()
	if not feedbackFrame then
		local f = ns.Skin.Window("PersonalVendettaFeedback", 480, 210, L["Feedback and bug reports"], ns.ICON)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		f:SetFrameStrata("FULLSCREEN_DIALOG")

		local body = text(f, "GameFontHighlightSmall",
			L["Ideas, bugs, or something that annoys you? Leave a comment on the CurseForge page. Press Ctrl+C to copy the link, then paste it into your browser."], 390)
		body:SetPoint("TOPLEFT", 66, -34)

		local function copyBox(value, anchor, y)
			local b, templated = make("EditBox", f, "InputBoxTemplate")
			b:SetSize(390, 22)
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
		close:SetPoint("BOTTOMRIGHT", -16, 12)
		close:SetScript("OnClick", function() f:Hide() end)
		f:SetScript("OnShow", function() f.url:SetFocus() ; f.url:HighlightText() end)
		feedbackFrame = f
	end
	feedbackFrame:Show()
	return feedbackFrame
end

-- ===========================================================================
-- Sections, built into the main window on demand
-- ===========================================================================

Settings.SECTIONS = { "general", "window", "alerts" }
Settings.SECTION_LABELS = { general = "General", window = "Window", alerts = "Alerts" }
local builders = { general = function(p) buildGeneral(p) end, window = function(p) buildWindow(p) end,
	alerts = function(p) buildAlerts(p) end }

function Settings:BuildSection(name, parent)
	local fn = builders[name]
	if not fn then return end
	fn(parent)
	built = true
end

-- ===========================================================================
-- Public
-- ===========================================================================

function Settings:Refresh()
	for _, c in ipairs(controls) do
		if c.refresh then c.refresh() end
	end
	if ns.Main then ns.Main:Refresh() end
end

function Settings:Toggle(show)
	if ns.Main then ns.Main:Toggle(show) end
end

-- "general", "window", "alerts" open that settings section; "list" and
-- "add" open those pages of the main window.
function Settings:Open(tab)
	if not ns.Main then return end
	if tab == "list" or tab == "add" then
		ns.Main:Open(tab)
	else
		ns.Main:Open("settings", tab)
	end
end

-- Keep the boxes honest when something changes from a slash command,
-- the V key, or the list itself.
ns.On("SETTINGS_CHANGED", function() Settings:Refresh() end)
ns.On("LIST_CHANGED", function() Settings:Refresh() end)
ns.On("GROUP_CHANGED", function() Settings:Refresh() end)
