--[[-------------------------------------------------------------------------
  Personal Vendetta -- Main window
  One window in the Forever style, like Legacy Challenges: round portrait,
  stone page, and three tabs down the right edge.

    Hit list   gold category headers on the left (Near you now, Scum, Seen
               this week, Everyone else), the player's cards on the right
    To add     everyone waiting to be added, as cards
    Settings   General, Window and Alerts

  Opened from the minimap skull, /vendetta options, or a name anywhere.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Main = {}
ns.Main = Main

local WIDTH, HEIGHT = 880, 620
-- The stone background has a band across the top for the summary bar; the
-- pages start under its gold line.
local TOP = 108
local PAGE_H = HEIGHT - TOP - 8
local LEFT_W = 300              -- category list column on the Hit list page
local ROW_H, HEADER_H = 24, 25
local CARD_H = 68               -- To add cards
local RECENT = 7 * 24 * 3600    -- "Seen this week"

local Skin
local frame, pages, tabs = nil, {}, {}
local listScroll, listContent, emptyText, searchBox, sortDropdown, shareButton, countText
local headers, rowPool = {}, {}
local addScroll, addContent, addEmpty, addCards = nil, nil, nil, {}
local sectionButtons, sectionPages = {}, {}
local summary
local selectedKey
local syncingSearch = false

Main.current = "list"
Main.section = "general"

-- ===========================================================================
-- Helpers
-- ===========================================================================

-- A scroll frame with Forever's scroll bar, and a content child to fill.
local function scroller(parent)
	local sf, templated = Skin.Make("ScrollFrame", parent, "ScrollFrameTemplate")
	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(1, 1)
	sf:SetScrollChild(content)
	if not templated then
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(self, delta)
			local maxV = math.max(0, content:GetHeight() - self:GetHeight())
			local v = math.min(maxV, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40))
			self:SetVerticalScroll(v)
		end)
	elseif Skin.Child(sf, "ScrollBar") and sf.ScrollBar.SetHideIfUnscrollable then
		pcall(sf.ScrollBar.SetHideIfUnscrollable, sf.ScrollBar, true)
	end
	return sf, content
end

local function category(entry)
	local record = ns.Radar and ns.Radar:Get(entry.key)
	if record and not record.dead then return "near" end
	if entry.scum then return "scum" end
	if entry.lastSeen and (time() - entry.lastSeen) < RECENT then return "recent" end
	return "rest"
end

local CATEGORIES = {
	{ id = "near", label = "Near you now" },
	{ id = "scum", label = "Scum" },
	{ id = "recent", label = "Seen this week" },
	{ id = "rest", label = "Everyone else" },
}

local function collapsed()
	ns.db.settings.listCollapsed = ns.db.settings.listCollapsed or {}
	return ns.db.settings.listCollapsed
end

-- ===========================================================================
-- Hit list page: the categories
-- ===========================================================================

local function newRow()
	local row = Skin.ListItem(listContent, LEFT_W - 30, ROW_H)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("LEFT", 12, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.score:SetPoint("RIGHT", -10, 0)
	row.score:SetJustifyH("RIGHT")
	row.name:SetPoint("RIGHT", row.score, "LEFT", -6, 0)
	row:SetScript("OnClick", function(self) if self.key then Main:Select(self.key) end end)
	row:SetScript("OnEnter", function(self)
		if self.entry and ns.EntryTooltip then ns.EntryTooltip(self, self.entry, "ANCHOR_RIGHT") end
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	return row
end

local function header(id)
	if headers[id] then return headers[id] end
	local h = Skin.Header(listContent, LEFT_W - 30, function(self)
		local c = collapsed()
		c[id] = not c[id] or nil
		Main:RenderList()
	end)
	h.id = id
	headers[id] = h
	return h
end

function Main:RenderList()
	if not frame or not listContent then return end
	local entries, total = ns.Settings:VisibleEntries()
	local buckets = { near = {}, scum = {}, recent = {}, rest = {} }
	for _, e in ipairs(entries) do
		local b = buckets[category(e)]
		b[#b + 1] = e
	end

	for _, h in pairs(headers) do h:Hide() end
	for _, r in ipairs(rowPool) do r:Hide() ; r.key, r.entry = nil, nil end

	local y, used = 0, 0
	local firstKey = nil
	local c = collapsed()
	for _, cat in ipairs(CATEGORIES) do
		local list = buckets[cat.id]
		if #list > 0 then
			local h = header(cat.id)
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", 0, -y)
			h:SetLabel(string.format("%s |cffaaaaaa(%d)|r", L[cat.label], #list))
			h:SetCollapsed(c[cat.id])
			h:Show()
			y = y + HEADER_H + 3
			if not c[cat.id] then
				for _, e in ipairs(list) do
					used = used + 1
					local row = rowPool[used] or newRow()
					rowPool[used] = row
					row:ClearAllPoints()
					row:SetPoint("TOPLEFT", 8, -y)
					local r, g, b = ns.ClassColor(e.class)
					local prefix = e.scum and (ns.SKULL .. " ") or ""
					if cat.id == "near" then prefix = "|cffff4444>|r " .. prefix end
					row.name:SetText(prefix .. ns.FullName(e))
					row.name:SetTextColor(r, g, b)
					row.score:SetText(string.format("|cffff6666%d|r : |cff66ff66%d|r", e.theyKilledMe or 0, e.iKilledThem or 0))
					row.key, row.entry = e.key, e
					row:SetSelected(e.key == selectedKey)
					row:Show()
					y = y + ROW_H + 2
					firstKey = firstKey or e.key
				end
				y = y + 4
			end
		end
	end
	listContent:SetSize(LEFT_W - 26, math.max(1, y))

	emptyText:SetShown(#entries == 0)
	emptyText:SetText(total == 0
		and L["Nobody yet. When an enemy player kills you in the open world, or you survive a fight with one, they wait in the To add tab of the floating window."]
		or string.format(L["Nobody matches \"%s\"."], ns.Settings:GetSearch()))
	countText:SetText(string.format(L["%s. %d of %d players. Click a name for details."],
		ns.Settings:SortLabel(), #entries, total))

	if sortDropdown then
		sortDropdown:SetText(ns.Settings:SortLabel())
		if sortDropdown.ValidateResetState then pcall(sortDropdown.ValidateResetState, sortDropdown) end
	end
	if shareButton and ns.Share then
		local canShare, why = ns.Share:CanShare()
		if canShare and total > 0 then shareButton:Enable() else shareButton:Disable() end
		shareButton.why = (total == 0) and L["Your list is empty."] or why
	end

	-- Keep someone in the pane: the one you picked (even if a search hides
	-- their row), else the first on the list.
	if not (selectedKey and ns.ListData()[selectedKey]) then
		selectedKey = firstKey
		for _, r in ipairs(rowPool) do if r.key then r:SetSelected(r.key == selectedKey) end end
	end
	ns.Detail:Show(selectedKey)
	pages.list.pick:SetShown(selectedKey == nil and total > 0)
end

function Main:Select(key)
	ns.Detail:ClearUndo()
	selectedKey = key
	self:RenderList()
end

function Main:Selected() return selectedKey end

-- ===========================================================================
-- Hit list page: building
-- ===========================================================================

local function buildListPage(page)
	searchBox = Skin.SearchBox(page, LEFT_W - 158, function(text)
		if syncingSearch then return end
		ns.Settings:SetSearch(text)
	end, L["Search"])
	searchBox:SetPoint("TOPLEFT", 18, -6)
	-- The long hint lives in a tooltip; the box only has room for one word.
	searchBox:HookScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Search name, class, race, zone or note"], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	searchBox:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	sortDropdown = Skin.FilterDropdown(page, 124, function(root)
		if root.CreateTitle then root:CreateTitle(L["Sort by"]) end
		for _, s in ipairs(ns.Settings.SORTS) do
			root:CreateRadio(L[s.label],
				function() return (ns.db.settings.listSort or "newest") == s.id end,
				function() ns.Settings:SetSort(s.id) end)
		end
	end)
	if sortDropdown then
		sortDropdown:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
		if sortDropdown.SetIsDefaultCallback then
			sortDropdown:SetIsDefaultCallback(function() return (ns.db.settings.listSort or "newest") == "newest" end)
			sortDropdown:SetDefaultCallback(function() ns.Settings:SetSort("newest") end)
		end
	else
		local b = Skin.Button(page, L["Sort"], 124, 22, true)
		b:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
		b:SetScript("OnClick", function() ns.Settings:CycleSort() end)
	end

	listScroll, listContent = scroller(page)
	listScroll:SetPoint("TOPLEFT", 8, -36)
	listScroll:SetSize(LEFT_W - 22, PAGE_H - 36 - 64)

	emptyText = Skin.Text(page, "GameFontDisable", nil, LEFT_W - 50)
	emptyText:SetPoint("TOP", listScroll, "TOP", 0, -40)
	emptyText:SetJustifyH("CENTER")

	countText = Skin.Text(page, "GameFontDisableSmall", nil, LEFT_W - 20)
	countText:SetPoint("TOPLEFT", listScroll, "BOTTOMLEFT", 6, -6)

	shareButton = Skin.Button(page, L["Share with party"], 160, 22)
	shareButton:SetPoint("BOTTOMLEFT", 14, 4)
	shareButton:SetScript("OnClick", function()
		if ns.Share then ns.Share:Send() end
		Main:RenderList()
	end)
	shareButton:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Share your hit list"])
		GameTooltip:AddLine(L["Sends everyone on your list to the people in your party or raid who also run Personal Vendetta. They choose whether to import, and only players they don't already have are added."], 1, 1, 1, true)
		if self.why and not self:IsEnabled() then GameTooltip:AddLine(self.why, 1, 0.3, 0.3, true) end
		GameTooltip:Show()
	end)
	shareButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	local div = Skin.VerticalDivider(page, PAGE_H - 6)
	div:SetPoint("TOPLEFT", LEFT_W + 2, -4)

	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", LEFT_W + 16, -4)
	right:SetSize(WIDTH - 16 - LEFT_W - 16 - 8, PAGE_H - 8)
	page.right = right
	ns.Detail:Build(right)

	page.pick = Skin.Text(right, "GameFontDisable", L["Pick a name on the left to see everything known about them."], 300)
	page.pick:SetPoint("CENTER")
	page.pick:SetJustifyH("CENTER")
	page.pick:Hide()
end

function Main:SyncSearch(text)
	if not searchBox then return end
	if (searchBox:GetText() or "") ~= text then
		syncingSearch = true
		searchBox:SetText(text)
		syncingSearch = false
	end
end

-- ===========================================================================
-- To add page
-- ===========================================================================

local function newCard()
	local c = Skin.Card(addContent)
	c:SetSize(WIDTH - 60, CARD_H)
	c.icon = Skin.IconFrame(c, 48)
	c.icon:SetPoint("LEFT", 12, 0)
	c.name = Skin.Text(c, "GameFontNormalLarge")
	c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -4)
	c.name:SetJustifyH("LEFT")
	c.name:SetWordWrap(false)
	c.detail = Skin.Text(c, "GameFontHighlightSmall")
	c.detail:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -4)
	c.detail:SetJustifyH("LEFT")
	c.detail:SetWordWrap(false)

	c.add = Skin.Button(c, L["Add"], 80, 24)
	c.add:SetPoint("RIGHT", -14, 0)
	c.skip = Skin.Button(c, L["Skip"], 80, 24)
	c.skip:SetPoint("RIGHT", c.add, "LEFT", -6, 0)
	c.note = Skin.Button(c, L["Note"], 80, 24)
	c.note:SetPoint("RIGHT", c.skip, "LEFT", -6, 0)
	c.scumText = Skin.Text(c, "GameFontNormal", ns.SCUM_COLOR .. L["Scum"] .. "|r")
	c.scumText:SetPoint("RIGHT", c.note, "LEFT", -12, 0)
	c.scum = ns.CreateCheckButton(c)
	c.scum:SetPoint("RIGHT", c.scumText, "LEFT", 0, 0)
	c.name:SetPoint("RIGHT", c.scum, "LEFT", -8, 0)
	c.detail:SetPoint("RIGHT", c.scum, "LEFT", -8, 0)

	c.scum:SetScript("OnClick", function(self)
		if c.id then ns.Pending:SetScum(c.id, self:GetChecked() and true or false) end
	end)
	c.scum:SetScript("OnEnter", function(self) ns.ScumTooltip(self) end)
	c.scum:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	c.note:SetScript("OnClick", function() if c.id and ns.Notes then ns.Notes:OpenPending(c.id) end end)
	c.skip:SetScript("OnClick", function() if c.id then ns.Pending:Skip(c.id) end end)
	c.add:SetScript("OnClick", function()
		if c.rid then ns.Pending:Undo(c.rid) elseif c.id then ns.Pending:Add(c.id) end
	end)
	c:EnableMouse(true)
	c:SetScript("OnEnter", function(self) if self.item and ns.PendingTooltip then ns.PendingTooltip(self, self.item, "ANCHOR_RIGHT") end end)
	c:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	return c
end

function Main:RenderAdd()
	if not frame or not addContent then return end
	local items = ns.Pending:List()
	-- Just added or skipped: the card stays a moment, with Undo where Add was.
	local list = {}
	for _, r in ipairs(ns.Pending:Recent()) do list[#list + 1] = { recent = r } end
	for _, it in ipairs(items) do list[#list + 1] = it end
	for _, c in ipairs(addCards) do c:Hide() ; c.id, c.item, c.rid = nil, nil, nil end
	for i, it in ipairs(list) do
		local c = addCards[i] or newCard()
		addCards[i] = c
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", 0, -(i - 1) * (CARD_H + 6))
		local undo = it.recent ~= nil
		c.skip:SetShown(not undo)
		c.note:SetShown(not undo)
		c.scum:SetShown(not undo)
		c.scumText:SetShown(not undo)
		c.add:SetText(undo and L["Undo"] or L["Add"])
		c:SetAlpha(undo and 0.75 or 1)
		if undo then
			local r = it.recent
			c.name:SetText(r.label)
			if r.kind == "added" then c.name:SetTextColor(0.5, 0.9, 0.5) else c.name:SetTextColor(0.7, 0.7, 0.7) end
			c.detail:SetText(L["Changed your mind?"])
			c.icon.icon:SetTexture(ns.ICON)
			c.rid = r.rid
		else
			local r, g, b = ns.ClassColor(it.class)
			c.name:SetText((it.scum and (ns.SKULL .. " ") or "") .. ns.FullName(it.name, it.surname))
			c.name:SetTextColor(r, g, b)
			local bits = {}
			if it.levelSkull then bits[#bits + 1] = L["Level ??"]
			elseif it.level then bits[#bits + 1] = string.format(L["Level %d"], it.level) end
			if it.race then bits[#bits + 1] = it.race end
			if it.className then bits[#bits + 1] = it.className end
			local who = table.concat(bits, " ")
			c.detail:SetText((who ~= "" and (who .. "  |cff666666-|r  ") or "") .. ns.Pending:Describe(it))
			Skin.SetClassIcon(c.icon.icon, it.class)
			c.scum:SetChecked(it.scum and true or false)
			c.note:SetText(it.note and L["Edit note"] or L["Note"])
			c.id, c.item = it.id, it
		end
		c:Show()
	end
	addContent:SetSize(WIDTH - 56, math.max(1, #list * (CARD_H + 6)))
	addEmpty:SetShown(#list == 0)
	pages.add.addAll:SetEnabled(#items > 0)
	pages.add.skipAll:SetEnabled(#items > 0)
	pages.add.info:SetText(#items > 0 and string.format(L["%d waiting"], #items) or "")
	if #items > 0 and frame:IsShown() and Main.current == "add" then ns.Pending:MarkAllSeen(true) end
end

local function buildAddPage(page)
	addScroll, addContent = scroller(page)
	addScroll:SetPoint("TOPLEFT", 14, -8)
	addScroll:SetSize(WIDTH - 60, PAGE_H - 8 - 44)

	addEmpty = Skin.Text(page, "GameFontDisable",
		L["Nobody to review. Players who kill you, or who you fight off, wait here so you can add them when it suits you."], 420)
	addEmpty:SetPoint("TOP", addScroll, "TOP", 0, -80)
	addEmpty:SetJustifyH("CENTER")

	page.addAll = Skin.Button(page, L["Add all"], 120, 24)
	page.addAll:SetPoint("BOTTOMRIGHT", -16, 6)
	page.addAll:SetScript("OnClick", function() ns.Pending:AddAll() end)
	page.skipAll = Skin.Button(page, L["Skip all"], 120, 24)
	page.skipAll:SetPoint("RIGHT", page.addAll, "LEFT", -8, 0)
	page.skipAll:SetScript("OnClick", function() ns.Pending:SkipAll() end)
	page.info = Skin.Text(page, "GameFontNormal")
	page.info:SetPoint("BOTTOMLEFT", 18, 12)
end

-- ===========================================================================
-- Settings page
-- ===========================================================================

local function selectSection(name)
	Main.section = name
	for n, p in pairs(sectionPages) do p:SetShown(n == name) end
	for n, b in pairs(sectionButtons) do b:SetSelected(n == name) end
	if Main.current == "settings" then ns.Settings.current = name end
end

local function buildSettingsPage(page)
	local SIDE_W = 200
	local prev
	for _, name in ipairs(ns.Settings.SECTIONS) do
		local b = Skin.ListItem(page, SIDE_W, 30)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.text:SetPoint("LEFT", 14, 0)
		b.text:SetText(L[ns.Settings.SECTION_LABELS[name]])
		if prev then b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4) else b:SetPoint("TOPLEFT", 12, -8) end
		b:SetScript("OnClick", function() selectSection(name) end)
		sectionButtons[name] = b
		prev = b

		local p = CreateFrame("Frame", nil, page)
		p:SetPoint("TOPLEFT", SIDE_W + 40, -10)
		p:SetPoint("BOTTOMRIGHT", -16, 8)
		p:Hide()
		ns.Settings:BuildSection(name, p)
		sectionPages[name] = p
	end

	local div = Skin.VerticalDivider(page, PAGE_H - 6)
	div:SetPoint("TOPLEFT", SIDE_W + 18, -4)

	local feedback = Skin.Button(page, L["Feedback / report a bug"], SIDE_W, 24)
	feedback:SetPoint("BOTTOMLEFT", 12, 34)
	feedback:SetScript("OnClick", function() ns.Settings:Feedback() end)
	local help = Skin.Text(page, "GameFontDisableSmall", L["/vendetta help lists every command."], SIDE_W)
	help:SetPoint("TOPLEFT", feedback, "BOTTOMLEFT", 2, -8)
	local version = Skin.Text(page, "GameFontDisableSmall", "Personal Vendetta v" .. ns.VERSION)
	version:SetPoint("BOTTOMLEFT", feedback, "TOPLEFT", 2, 8)
end

-- ===========================================================================
-- The window
-- ===========================================================================

local PAGE_ORDER = { "list", "add", "settings" }

local function updateSummary()
	if not summary then return end
	local fought, settled, total, scum = 0, 0, 0, 0
	for _, e in pairs(ns.ListData()) do
		total = total + 1
		if e.scum then scum = scum + 1 end
		if (e.theyKilledMe or 0) > 0 then
			fought = fought + 1
			if (e.iKilledThem or 0) >= e.theyKilledMe then settled = settled + 1 end
		end
	end
	summary:SetMinMaxValues(0, math.max(1, fought))
	summary:SetValue(settled)
	summary.text:SetText(string.format(L["Vendettas settled %d / %d"], settled, fought))
	summary.side:SetText(string.format(L["%d on list"], total)
		.. (scum > 0 and ("   " .. ns.SKULL .. ns.SCUM_COLOR .. string.format(L["%d scum"], scum) .. "|r") or ""))

	if tabs.add then
		local n = ns.Pending:Count()
		tabs.add.badge:SetText(n > 0 and tostring(n) or "")
		tabs.add.tooltipLine = n > 0 and string.format(L["%d waiting to be added (To add tab)"], n) or nil
	end
	if tabs.list then
		tabs.list.tooltip = total > 0 and string.format(L["Hit list (%d)"], total) or L["Hit list"]
	end
end

local function build()
	Skin = ns.Skin
	frame = Skin.Window("PersonalVendettaMain", WIDTH, HEIGHT, "Personal Vendetta", ns.ICON)
	frame:SetFrameStrata("DIALOG")

	-- Score across the whole list, like the Legacy points bar.
	summary = Skin.ProgressBar(frame, 420)
	summary:SetPoint("TOP", 20, -38)
	summary.side = Skin.Text(frame, "GameFontNormal")
	summary.side:SetPoint("LEFT", summary, "RIGHT", 18, 0)

	for _, name in ipairs(PAGE_ORDER) do
		local p = CreateFrame("Frame", nil, frame)
		p:SetPoint("TOPLEFT", 8, -TOP)
		p:SetPoint("BOTTOMRIGHT", -8, 8)
		p:SetSize(WIDTH - 16, PAGE_H)
		p:Hide()
		pages[name] = p
	end

	-- Side tabs down the right edge
	local defs = {
		{ "list", ns.ICON, L["Hit list"] },
		{ "add", "Interface\\Icons\\INV_Scroll_03", L["To add"] },
		{ "settings", "Interface\\Icons\\INV_Misc_Gear_01", L["Settings"] },
	}
	local prev
	for _, d in ipairs(defs) do
		local key = d[1]
		local t = Skin.SideTab(frame, d[2], d[3], function() Main:Open(key) end)
		if prev then
			t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
		else
			t:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
		end
		t.badge = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		t.badge:SetPoint("BOTTOMRIGHT", -8, 6)
		t.badge:SetTextColor(1, 0.82, 0)
		tabs[key] = t
		prev = t
	end

	buildListPage(pages.list)
	buildAddPage(pages.add)
	buildSettingsPage(pages.settings)

	frame:SetScript("OnShow", function() Main:Refresh() end)
	return frame
end

function Main:Frame() return frame end

function Main:Refresh()
	if not frame or not frame:IsShown() then return end
	updateSummary()
	if Main.current == "list" then
		Main:RenderList()
	elseif Main.current == "add" then
		Main:RenderAdd()
	end
end

-- page: "list", "add" or "settings"; section: a settings section.
function Main:Open(page, section)
	if not frame then build() end
	if not pages[page] then page = "list" end
	Main.current = page
	for name, p in pairs(pages) do p:SetShown(name == page) end
	for name, t in pairs(tabs) do t:SetSelected(name == page) end
	if page == "settings" then
		selectSection(section or Main.section or "general")
		ns.Settings.current = Main.section
	else
		ns.Settings.current = page
	end
	frame:Show()
	ns.Settings:Refresh()
end

function Main:ShowList(key)
	if key then ns.Detail:ClearUndo() end
	selectedKey = key or selectedKey
	self:Open("list")
end

function Main:Toggle(show)
	if not frame then build() end
	if show == nil then show = not frame:IsShown() end
	if show then
		self:Open(Main.current or "list", Main.section)
	else
		frame:Hide()
	end
end

function Main:IsShown() return frame and frame:IsShown() or false end

ns.On("LIST_CHANGED", function() Main:Refresh() end)
ns.On("RADAR_CHANGED", function()
	if frame and frame:IsShown() and Main.current == "list" then Main:RenderList() end
end)
ns.On("PENDING_CHANGED", function() Main:Refresh() end)
ns.On("GROUP_CHANGED", function() Main:Refresh() end)
