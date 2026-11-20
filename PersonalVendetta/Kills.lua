--[[-------------------------------------------------------------------------
  Personal Vendetta -- Kills
  Counts the times you killed someone on the list.

  A kill is a kill: the killing blow does not matter, taking part does.
  With the combat log closed there is no "who damaged whom", so taking part
  is read from what the client will still show us:

    Engaged  -- while you were in combat, they were your target, or they had
                you or someone in your group targeted. Remembered for a while.
    Died     -- we watched them go from alive to dead (radar), or the honor
                system credited you with an honorable kill on them.

  Engaged + died = a kill. The honor message, when the client lets us read
  it, is credit on its own: it is the game itself saying you took part.

  Every counted kill says in chat how it was detected, which is what to
  look at if one is ever missed or double counted. /vendetta kill <name>
  adds one by hand.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local ENGAGED_FOR = 30       -- seconds a fight stays "yours" after contact
local HK_MATCH_WINDOW = 12   -- seconds an HK tick looks back for a death

local engaged = {}      -- key -> time() of last contact
local recentDeaths = {} -- key -> { at = time(), entry = entry }

local Kills = {}
ns.Kills = Kills

-- ===========================================================================
-- Helpers
-- ===========================================================================

local function readBool(fn, ...)
	local ok, v = ns.try(fn, ...)
	if not ok or not ns.usable(v) then return nil end
	return v and true or false
end

local function inCombat()
	return readBool(UnitAffectingCombat, "player") or false
end

local function same(a, b)
	return readBool(UnitIsUnit, a, b) or false
end

-- Group tokens, so "they were hitting my party" counts as your fight too.
local function groupUnits()
	local units = {}
	local inRaid = readBool(IsInRaid)
	local ok, n = ns.try(GetNumGroupMembers)
	n = ok and ns.num(n) or 0
	if inRaid then
		for i = 1, n do units[#units + 1] = "raid" .. i end
	else
		for i = 1, math.max(0, n - 1) do units[#units + 1] = "party" .. i end
	end
	return units
end

local function isEngaged(key)
	local at = key and engaged[key]
	return at ~= nil and (time() - at) <= ENGAGED_FOR
end

function Kills:IsEngaged(key) return isEngaged(key) end

local function credit(entry, how)
	if not entry then return end
	local _, counted = ns.List:RecordMyKill({ guid = entry.guid, name = entry.name, surname = entry.surname })
	if counted then
		ns.Print(string.format(ns.L["Kill on %s counted (%s). Now %d to %d."],
			"|cff66ff66" .. ns.FullName(entry) .. "|r", ns.L[how], entry.theyKilledMe or 0, entry.iKilledThem or 0))
	end
	engaged[entry.key] = nil
end

-- ===========================================================================
-- Engagement: called by the radar for every list member it can see
-- ===========================================================================

ns.On("UNIT_SEEN", function(entry, unit, record)
	if not entry or not entry.key or record.dead then return end
	if not inCombat() then return end

	local contact = same(unit, "target")
		or same(unit .. "target", "player")

	if not contact then
		for _, g in ipairs(groupUnits()) do
			if same(unit .. "target", g) or same(g .. "target", unit) then
				contact = true
				break
			end
		end
	end

	if contact then
		engaged[entry.key] = time()
	end
end)

-- ===========================================================================
-- Deaths we watched happen
-- ===========================================================================

ns.On("SEEN_DIE", function(entry, unit)
	if not entry or not entry.key then return end
	recentDeaths[entry.key] = { at = time(), entry = entry }
	if isEngaged(entry.key) then
		credit(entry, "saw them drop")
	end
end)

-- ===========================================================================
-- The honor system: the game's own verdict on whether you took part
-- ===========================================================================

-- Find which list member an honor message is about. The format varies by
-- language, so look for any known name in it and prefer the longest match:
-- a full "Willia Saqandie" beats a bare "Willia", and "Bobby" must not be
-- read as "Bob". Two different people tied for the best match is a guess,
-- and a guess is not a kill.
local function nameInMessage(text)
	local best, bestLen, tied
	for key, entry in pairs(ns.db.list) do
		local candidates = { ns.FullName(entry) }
		if entry.surname then candidates[2] = entry.name end
		for _, n in ipairs(candidates) do
			if n and #n >= 2 and string.find(text, n, 1, true) then
				if not bestLen or #n > bestLen then
					best, bestLen, tied = entry, #n, false
				elseif #n == bestLen and best ~= entry then
					tied = true
				end
				break -- the full name was checked first; no need for the short one
			end
		end
	end
	if tied then return nil end
	return best
end

local function onHonorGain(text)
	local msg = ns.str(text)
	if not msg then return end -- secret or empty on this client: rely on the radar
	local entry = nameInMessage(msg)
	if entry then
		credit(entry, "honorable kill")
	end
end

-- The HK counter ticked but we may not know for whom. If exactly one list
-- member we were fighting died moments ago, it was them.
local function onPvpKillsChanged(unit)
	-- usable() before comparing: a secret token must not be compared at all.
	if ns.usable(unit) and unit ~= "player" then return end
	local now = time()
	local candidates = {}
	for key, d in pairs(recentDeaths) do
		if (now - d.at) <= HK_MATCH_WINDOW then
			candidates[#candidates + 1] = d.entry
		end
	end
	if #candidates == 1 then
		credit(candidates[1], "honorable kill")
	end
end

-- ===========================================================================
-- Events
-- ===========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
f:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")
f:SetScript("OnEvent", function(_, event, arg1)
	if not ns.db then return end
	if event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
		onHonorGain(arg1)
	elseif event == "PLAYER_PVP_KILLS_CHANGED" then
		onPvpKillsChanged(arg1)
	end
end)

-- Old deaths are no use to the HK matcher; keep the table small.
C_Timer.NewTicker(30, function()
	local now = time()
	for key, d in pairs(recentDeaths) do
		if (now - d.at) > 60 then recentDeaths[key] = nil end
	end
	for key, at in pairs(engaged) do
		if (now - at) > ENGAGED_FOR * 2 then engaged[key] = nil end
	end
end)

-- Test hooks.
Kills._engaged = engaged
Kills._recentDeaths = recentDeaths
Kills._onHonorGain = onHonorGain
Kills._onPvpKillsChanged = onPvpKillsChanged
