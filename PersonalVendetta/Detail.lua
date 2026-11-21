--[[-------------------------------------------------------------------------
  Personal Vendetta -- Detail
  Everything known about one player: the right half of the Hit list page in
  the main window. Who they are, the score and where it stands, how their
  level has moved since you first met, every death, kill and sighting with
  the zone it happened in, and the note. Scum and Remove (with Undo) too.

  The level progression is the addon's own record, built from every time
  you have seen them. WoW addons cannot reach the internet, so there is no
  armory lookup; this is the in-game equivalent.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local HISTORY_LINES = 8

local Detail = {}
ns.Detail = Detail

local frame, showingKey
-- Just removed: the card stays for a few seconds with Undo where Remove was.
local removed -- { snap, expires }
local UNDO_SECONDS = 10
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
	killed = "You won the fight",
	fought = "You both walked away. Not settled.",
	seen = "Seen",
	added = "Added to your list",
	shared = "Imported from a share",
}

local function day(t) return t and date("%Y-%m-%d", t) or "?" end
local function stamp(t) return t and date("%m-%d %H:%M", t) or "?" end

local function fs(parent, font, width)
	local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	if width then
		f:SetWidth(width)
		f:SetJustifyH("LEFT")
		f:SetWordWrap(true)
	end
	return f
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
		local text = L[EVENT_TEXT[ev.e] or ev.e or "?"]
		if ev.e == "died" then
			-- How they did it: 1v1 or a gank, the spell, the killing blow.
			local how = {}
			if ev.n then
				how[#how + 1] = ev.n <= 1 and "1v1" or (ev.n == 2 and L["2v1"] or (ev.n == 3 and L["3v1"] or L["4v1+"]))
			end
			if ev.sp then how[#how + 1] = ev.sp end
			if ev.kb then how[#how + 1] = L["killing blow"] end
			if #how > 0 then text = text .. " (" .. table.concat(how, ", ") .. ")" end
		end
		local label = string.format(EVENT_LABEL[ev.e] or "%s", text)
		local where = ev.z and ("  |cffcccccc" .. ev.z .. (ev.xy and (" (" .. ev.xy .. ")") or "") .. "|r") or ""
		local lvl = ev.lv and ("  |cff888888" .. string.format(L["Lv %d"], ev.lv) .. "|r") or ""
		out[#out + 1] = "|cff888888" .. stamp(ev.t) .. "|r  " .. label .. where .. lvl
	end
	return out, math.max(0, #h - HISTORY_LINES)
end

-- ===========================================================================
-- Building: four cards stacked in the pane
-- ===========================================================================

local Skin

local function card(parent, top, height)
	local c = Skin.Card(parent)
	c:SetPoint("TOPLEFT", 0, top)
	c:SetPoint("TOPRIGHT", 0, top)
	c:SetHeight(height)
	return c
end

local function cardTitle(c, str)
	local t = Skin.Text(c, "GameFontNormal", str)
	t:SetPoint("TOPLEFT", 16, -12)
	return t
end

function Detail:Build(parent)
	Skin = ns.Skin
	frame = CreateFrame("Frame", "PersonalVendettaDetail", parent)
	frame:SetAllPoints()
	local W = (parent.GetWidth and parent:GetWidth()) or 540
	if not W or W < 100 then W = 540 end
	local inner = W - 32

	-- Who: icon, name, race and class, the score
	local top = card(frame, 0, 112)
	frame.icon = Skin.IconFrame(top, 64)
	frame.icon:SetPoint("LEFT", 14, 0)
	frame.name = fs(top, "GameFontNormalLarge", inner - 250)
	frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -6)
	frame.name:SetWordWrap(false)
	frame.who = fs(top, "GameFontHighlight", inner - 250)
	frame.who:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -4)
	frame.added = fs(top, "GameFontDisableSmall", inner - 250)
	frame.added:SetPoint("TOPLEFT", frame.who, "BOTTOMLEFT", 0, -6)

	frame.bigScore = fs(top, "GameFontNormalHuge")
	frame.bigScore:SetPoint("TOPRIGHT", -24, -22)
	frame.scoreLabel = fs(top, "GameFontDisableSmall")
	frame.scoreLabel:SetPoint("TOP", frame.bigScore, "BOTTOM", 0, -2)
	frame.scoreLabel:SetText("|cffff6666" .. L["They"] .. "|r  :  |cff66ff66" .. L["You"] .. "|r")
	frame.standing = fs(top, "GameFontHighlightSmall")
	frame.standing:SetPoint("TOPRIGHT", frame.scoreLabel, "BOTTOMRIGHT", 0, -6)
	frame.standing:SetJustifyH("RIGHT")
	-- kept for older callers: the score in words
	frame.score = frame.standing

	-- Where and how strong
	local seen = card(frame, -118, 92)
	cardTitle(seen, L["Last seen"])
	frame.facts = fs(seen, "GameFontHighlightSmall", inner)
	frame.facts:SetPoint("TOPLEFT", 16, -32)
	frame.hLevels = fs(seen, "GameFontNormalSmall")
	frame.hLevels:SetPoint("TOPLEFT", frame.facts, "BOTTOMLEFT", 0, -8)
	frame.hLevels:SetText(L["Level progression"])
	frame.levels = fs(seen, "GameFontHighlightSmall", inner - 120)
	frame.levels:SetPoint("TOPLEFT", frame.hLevels, "TOPRIGHT", 8, 0)

	-- Everything that happened
	local hist = card(frame, -216, 172)
	frame.hHistory = cardTitle(hist, L["History"])
	local prev = frame.hHistory
	for i = 1, HISTORY_LINES do
		local line = fs(hist, "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -6 or -3)
		line:SetWidth(inner)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(false)
		lines[i] = line
		prev = line
	end
	frame.older = fs(hist, "GameFontDisableSmall")
	frame.older:SetPoint("TOPRIGHT", -16, -12)

	-- The note
	local noteCard = card(frame, -394, 62)
	frame.note = fs(noteCard, "GameFontHighlightSmall", inner - 120)
	frame.note:SetPoint("LEFT", 16, 0)
	frame.note:SetMaxLines(3)
	frame.editNote = Skin.Button(noteCard, L["Edit note"], 100, 22)
	frame.editNote:SetPoint("RIGHT", -14, 0)
	frame.editNote:SetScript("OnClick", function()
		if showingKey and ns.Notes then ns.Notes:Open(showingKey) end
	end)

	-- Scum and Remove along the bottom
	frame.scum = ns.CreateCheckButton(frame)
	frame.scum:SetPoint("BOTTOMLEFT", 2, 0)
	frame.scumText = fs(frame, "GameFontNormal")
	frame.scumText:SetPoint("LEFT", frame.scum, "RIGHT", 2, 0)
	frame.scumText:SetText(ns.SKULL .. " " .. ns.SCUM_COLOR .. L["Scum"] .. "|r")
	frame.scum:SetScript("OnClick", function(self)
		if showingKey then ns.List:SetScum(showingKey, self:GetChecked() and true or false) end
	end)
	frame.scum:SetScript("OnEnter", function(self) ns.ScumTooltip(self) end)
	frame.scum:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	frame.remove = Skin.Button(frame, L["Remove from list"], 150, 22)
	frame.remove:SetPoint("BOTTOMRIGHT", 0, 2)
	frame.remove:SetScript("OnClick", function()
		if removed then
			-- Undo
			local snap = removed.snap
			removed = nil
			local back = ns.List:Restore(snap)
			if back and ns.Main then ns.Main:Select(back.key) end
			return
		end
		if not showingKey then return end
		local snapshot = ns.List:RemoveKey(showingKey)
		if not snapshot then return end
		removed = { snap = snapshot, expires = GetTime() + UNDO_SECONDS }
		local mine = removed
		if C_Timer and C_Timer.After then
			C_Timer.After(UNDO_SECONDS, function()
				if removed == mine then
					removed = nil
					if ns.Main then ns.Main:Refresh() end
				end
			end)
		end
		if ns.Main then ns.Main:Refresh() end
	end)

	frame:Hide()
	return frame
end

-- ===========================================================================
-- Filling
-- ===========================================================================

local function fill()
	local entry = showingKey and ns.ListData()[showingKey]
	if removed then entry = removed.snap.entry end
	if not entry then showingKey = nil ; frame:Hide() return end
	frame:SetAlpha(removed and 0.6 or 1)
	frame.remove:SetText(removed and L["Undo"] or L["Remove from list"])
	frame.editNote:SetEnabled(not removed)
	frame.scum:SetEnabled(not removed)

	local r, g, b = ns.ClassColor(entry.class)
	frame.name:SetText((entry.scum and (ns.SKULL .. " ") or "") .. ns.FullName(entry))
	frame.name:SetTextColor(r, g, b)

	local bits = {}
	if entry.levelSkull then bits[#bits + 1] = L["Level ?? (10+ above you)"]
	elseif entry.level then bits[#bits + 1] = string.format(L["Level %d"], entry.level) end
	if entry.race then bits[#bits + 1] = entry.race end
	if entry.className then bits[#bits + 1] = entry.className end
	frame.who:SetText(table.concat(bits, " "))

	frame.bigScore:SetText(string.format("|cffff6666%d|r : |cff66ff66%d|r", entry.theyKilledMe or 0, entry.iKilledThem or 0))
	Skin.SetClassIcon(frame.icon.icon, entry.class)
	local standing = Detail:Standing(entry)
	if (entry.streak or 0) >= 2 then
		standing = standing .. "  |cffffd100" .. string.format(L["%d kills in a row."], entry.streak) .. "|r"
	end
	frame.standing:SetText(standing)

	local added = string.format(L["Added %s (%s)"], day(entry.firstAdded), ns.Ago(entry.firstAdded))
	if entry.sharedBy then added = added .. "  " .. string.format(L["Shared by %s"], entry.sharedBy) end
	frame.added:SetText(added)

	local facts = {}
	if entry.lastSeen then
		local where = entry.lastZone and string.format(L[" in %s"], entry.lastZone) or ""
		facts[#facts + 1] = string.format(L["Last seen %s%s"], ns.Ago(entry.lastSeen), where)
	else
		facts[#facts + 1] = L["Not seen since you added them."]
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

-- Show one player in the pane (the main window decides when).
function Detail:Show(key)
	if not frame then return false end
	if removed then
		-- Still offering Undo on the one just removed.
		showingKey = nil
		fill()
		frame:Show()
		return true
	end
	if not key or not ns.ListData()[key] then
		showingKey = nil
		frame:Hide()
		return false
	end
	showingKey = key
	fill()
	frame:Show()
	return true
end

-- Open the main window on the Hit list with this player picked.
function Detail:Open(key)
	if not key or not ns.ListData()[key] then return end
	if ns.Main then ns.Main:ShowList(key) end
end

function Detail:IsOpen()
	local main = _G.PersonalVendettaMain
	return frame and frame:IsShown() and main and main:IsShown() and showingKey ~= nil or false
end
function Detail:Key() return showingKey end
function Detail:Undoing() return removed ~= nil end
function Detail:ClearUndo() removed = nil end
function Detail:_frame() return frame end

ns.On("LIST_CHANGED", function()
	if frame and frame:IsShown() then fill() end
end)
