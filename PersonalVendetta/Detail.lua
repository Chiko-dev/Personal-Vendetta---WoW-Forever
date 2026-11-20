--[[-------------------------------------------------------------------------
  Personal Vendetta -- Detail
  Everything known about one player, opened by clicking a name on the hit
  list: who they are, the score and where it stands, how their level has
  moved since you first met, every death, kill and sighting with the zone
  it happened in, and the note. Scum and Remove (with Undo) live here too.

  The level progression is the addon's own record, built from every time
  you have seen them. WoW addons cannot reach the internet, so there is no
  armory lookup; this is the in-game equivalent.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local WIDTH, HEIGHT = 400, 520
local HISTORY_LINES = 11

local Detail = {}
ns.Detail = Detail

local frame, showingKey
local lines = {}

local EVENT_LABEL = {
	died = "|cffff6666" .. "%s" .. "|r",
	killed = "|cff66ff66" .. "%s" .. "|r",
	fought = "|cffffd100" .. "%s" .. "|r",
	seen = "|cffaaaaaa" .. "%s" .. "|r",
	added = "|cffaaaaff" .. "%s" .. "|r",
	shared = "|cffaaaaff" .. "%s" .. "|r",
}
local EVENT_TEXT = {
	died = "Killed you",
	killed = "You killed them",
	fought = "Fought you",
	seen = "Seen",
	added = "Added to your list",
	shared = "Imported from a share",
}

local function day(t) return t and date("%Y-%m-%d", t) or "?" end
local function stamp(t) return t and date("%Y-%m-%d %H:%M", t) or "?" end

local function fs(parent, font, width)
	local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	if width then
		f:SetWidth(width)
		f:SetJustifyH("LEFT")
		f:SetWordWrap(true)
	end
	return f
end

local function button(parent, label, w)
	local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", nil, parent)
		b:SetNormalFontObject("GameFontNormalSmall")
	end
	b:SetSize(w, 22)
	b:SetText(label)
	return b
end

-- ===========================================================================
-- What to say
-- ===========================================================================

function Detail:Standing(entry)
	local mine, theirs = entry.iKilledThem or 0, entry.theyKilledMe or 0
	if theirs == 0 and mine == 0 then return "|cffaaaaaa" .. L["No kills either way yet."] .. "|r" end
	if mine > theirs then return "|cff66ff66" .. string.format(L["You lead by %d."], mine - theirs) .. "|r" end
	if mine == theirs then return "|cff66ff66" .. L["Even. Vendetta settled."] .. "|r" end
	return "|cffff6666" .. string.format(L["You're %d behind."], theirs - mine) .. "|r"
end

function Detail:Progression(entry)
	local levels = entry.levels or {}
	if #levels == 0 then
		return entry.level and string.format(L["Level %d when last seen. No changes recorded yet."], entry.level)
			or L["No level seen yet."]
	end
	local parts = {}
	for i = math.max(1, #levels - 5), #levels do
		local p = levels[i]
		parts[#parts + 1] = string.format("|cffffffff%d|r |cff888888(%s)|r", p.lv, day(p.t))
	end
	local text = table.concat(parts, "  >  ")
	local first, last = levels[1], levels[#levels]
	if #levels > 1 and last.lv > first.lv then
		text = text .. "\n" .. string.format(L["+%d levels since %s."], last.lv - first.lv, day(first.t))
	end
	return text
end

function Detail:HistoryLines(entry)
	local out = {}
	local h = entry.history or {}
	for i = #h, math.max(1, #h - HISTORY_LINES + 1), -1 do
		local ev = h[i]
		local label = string.format(EVENT_LABEL[ev.e] or "%s", L[EVENT_TEXT[ev.e] or ev.e or "?"])
		local where = ev.z and ("  |cffcccccc" .. ev.z .. "|r") or ""
		local lvl = ev.lv and ("  |cff888888" .. string.format(L["Lv %d"], ev.lv) .. "|r") or ""
		out[#out + 1] = "|cff888888" .. stamp(ev.t) .. "|r  " .. label .. where .. lvl
	end
	return out, math.max(0, #h - HISTORY_LINES)
end

-- ===========================================================================
-- Building
-- ===========================================================================

local function build()
	frame = CreateFrame("Frame", "PersonalVendettaDetail", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
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
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "PersonalVendettaDetail") end

	local inner = WIDTH - 44
	frame.name = fs(frame, "GameFontNormalLarge", inner - 30)
	frame.name:SetPoint("TOPLEFT", 22, -20)
	frame.name:SetWordWrap(false)

	local okC, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
	if okC and close then
		close:SetPoint("TOPRIGHT", -4, -4)
		close:SetScript("OnClick", function() frame:Hide() end)
	end

	frame.who = fs(frame, "GameFontHighlightSmall", inner)
	frame.who:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -4)

	frame.score = fs(frame, "GameFontHighlight", inner)
	frame.score:SetPoint("TOPLEFT", frame.who, "BOTTOMLEFT", 0, -12)
	frame.standing = fs(frame, "GameFontHighlightSmall", inner)
	frame.standing:SetPoint("TOPLEFT", frame.score, "BOTTOMLEFT", 0, -3)

	frame.facts = fs(frame, "GameFontHighlightSmall", inner)
	frame.facts:SetPoint("TOPLEFT", frame.standing, "BOTTOMLEFT", 0, -10)
	frame.facts:SetSpacing(2)

	frame.hLevels = fs(frame, "GameFontNormalSmall")
	frame.hLevels:SetPoint("TOPLEFT", frame.facts, "BOTTOMLEFT", 0, -12)
	frame.hLevels:SetText(L["Level progression"])
	frame.levels = fs(frame, "GameFontHighlightSmall", inner)
	frame.levels:SetPoint("TOPLEFT", frame.hLevels, "BOTTOMLEFT", 0, -4)

	frame.hHistory = fs(frame, "GameFontNormalSmall")
	frame.hHistory:SetPoint("TOPLEFT", frame.levels, "BOTTOMLEFT", 0, -12)
	frame.hHistory:SetText(L["History"])
	local prev = frame.hHistory
	for i = 1, HISTORY_LINES do
		local line = fs(frame, "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -4 or -2)
		line:SetWidth(inner)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(false)
		lines[i] = line
		prev = line
	end
	frame.older = fs(frame, "GameFontDisableSmall")
	frame.older:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)

	-- Bottom: note, scum, remove
	frame.note = fs(frame, "GameFontHighlightSmall", inner - 100)
	frame.note:SetPoint("BOTTOMLEFT", 22, 50)
	frame.note:SetMaxLines(3)
	frame.editNote = button(frame, L["Edit note"], 90)
	frame.editNote:SetPoint("BOTTOMRIGHT", -20, 52)
	frame.editNote:SetScript("OnClick", function()
		if showingKey and ns.Notes then ns.Notes:Open(showingKey) end
	end)

	frame.scum = ns.CreateCheckButton(frame)
	frame.scum:SetPoint("BOTTOMLEFT", 18, 16)
	frame.scumText = fs(frame, "GameFontNormalSmall")
	frame.scumText:SetPoint("LEFT", frame.scum, "RIGHT", 0, 0)
	frame.scumText:SetText(ns.SCUM_COLOR .. L["Scum"] .. "|r")
	frame.scum:SetScript("OnClick", function(self)
		if showingKey then ns.List:SetScum(showingKey, self:GetChecked() and true or false) end
	end)
	frame.scum:SetScript("OnEnter", function(self) ns.ScumTooltip(self) end)
	frame.scum:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	frame.remove = button(frame, L["Remove from list"], 130)
	frame.remove:SetPoint("BOTTOMRIGHT", -20, 16)
	frame.remove:SetScript("OnClick", function()
		if not showingKey then return end
		local entry = ns.ListData()[showingKey]
		local name = entry and ns.FullName(entry) or "?"
		local snapshot = ns.List:RemoveKey(showingKey)
		frame:Hide()
		if snapshot and ns.Toast then
			ns.Toast:Undo(string.format(L["Removed %s."], name), function()
				ns.List:Restore(snapshot)
			end)
		end
	end)

	frame:SetScript("OnHide", function() showingKey = nil end)
	return frame
end

-- ===========================================================================
-- Filling
-- ===========================================================================

local function fill()
	local entry = showingKey and ns.ListData()[showingKey]
	if not entry then frame:Hide() return end

	local r, g, b = ns.ClassColor(entry.class)
	frame.name:SetText((entry.scum and (ns.SKULL .. " ") or "") .. ns.FullName(entry))
	frame.name:SetTextColor(r, g, b)

	local bits = {}
	if entry.levelSkull then bits[#bits + 1] = L["Level ?? (10+ above you)"]
	elseif entry.level then bits[#bits + 1] = string.format(L["Level %d"], entry.level) end
	if entry.race then bits[#bits + 1] = entry.race end
	if entry.className then bits[#bits + 1] = entry.className end
	frame.who:SetText(table.concat(bits, " "))

	frame.score:SetText(string.format("|cffff6666" .. L["Killed you %d"] .. "|r     |cff66ff66" .. L["You killed them %d"] .. "|r",
		entry.theyKilledMe or 0, entry.iKilledThem or 0))
	local standing = Detail:Standing(entry)
	if (entry.streak or 0) >= 2 then
		standing = standing .. "  |cffffd100" .. string.format(L["%d kills in a row."], entry.streak) .. "|r"
	end
	frame.standing:SetText(standing)

	local facts = {}
	facts[#facts + 1] = string.format(L["Added %s (%s)"], day(entry.firstAdded), ns.Ago(entry.firstAdded))
	if entry.lastSeen then
		local where = entry.lastZone and string.format(L[" in %s"], entry.lastZone) or ""
		facts[#facts + 1] = string.format(L["Last seen %s%s"], ns.Ago(entry.lastSeen), where)
	else
		facts[#facts + 1] = L["Not seen since you added them."]
	end
	if entry.sharedBy then
		facts[#facts + 1] = string.format(L["Shared by %s"], entry.sharedBy)
	end
	frame.facts:SetText(table.concat(facts, "\n"))

	frame.levels:SetText(Detail:Progression(entry))

	local hist, older = Detail:HistoryLines(entry)
	for i = 1, HISTORY_LINES do
		lines[i]:SetText(hist[i] or (i == 1 and ("|cff888888" .. L["Nothing recorded yet."] .. "|r") or ""))
	end
	frame.older:SetText(older > 0 and string.format(L["+%d older"], older) or "")

	frame.note:SetText(entry.note and ("|cffffd100\"" .. entry.note .. "\"|r")
		or ("|cff888888" .. L["No note."] .. "|r"))
	frame.editNote:SetText(entry.note and L["Edit note"] or L["Add note"])
	frame.scum:SetChecked(entry.scum and true or false)
end

function Detail:Open(key)
	if not key or not ns.ListData()[key] then return end
	if not frame then build() end
	showingKey = key
	frame:ClearAllPoints()
	local settings = _G.PersonalVendettaSettings
	if settings and settings:IsShown() then
		local right = settings.GetRight and settings:GetRight()
		local screen = UIParent.GetWidth and UIParent:GetWidth()
		if right and screen and (right + WIDTH + 8) > screen then
			frame:SetPoint("TOPRIGHT", settings, "TOPLEFT", -4, 0)
		else
			frame:SetPoint("TOPLEFT", settings, "TOPRIGHT", 4, 0)
		end
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	fill()
	frame:Show()
end

function Detail:IsOpen() return frame and frame:IsShown() or false end
function Detail:Key() return showingKey end
function Detail:_frame() return frame end

ns.On("LIST_CHANGED", function()
	if frame and frame:IsShown() then fill() end
end)
