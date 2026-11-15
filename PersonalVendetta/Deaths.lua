--[[-------------------------------------------------------------------------
  Personal Vendetta -- Deaths
  Works out who killed you, using the death recap rather than the combat log.

  The recap holds the last several hits that landed on you, which is exactly
  what we want: a 3-man gank shows up as three separate player sources, so
  the prompt can offer all of them.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local POLL_TRIES = 6     -- the recap fills in a moment after you die
local POLL_DELAY = 1.0

local pollsLeft = 0

-- ===========================================================================
-- Reading the recap
-- ===========================================================================

local function getRecapEvents()
	local fn = C_DeathRecap and C_DeathRecap.GetRecapEvents
	if type(fn) ~= "function" then return nil end
	local ok, events = ns.try(fn)
	if not ok or type(events) ~= "table" or #events == 0 then return nil end
	return events
end

-- Identify this particular death, so the same recap is never counted twice
-- (notably a stale one sitting there at login).
local function signatureOf(events)
	local e = events[1]
	if type(e) ~= "table" then return nil end
	return table.concat({
		ns.S(e.sourceGUID),
		ns.S(e.spellId),
		ns.S(e.amount),
		ns.S(e.timestamp),
	}, "|")
end

-- If the recap carries a readable timestamp that is clearly old, it is not
-- this death. An unreadable timestamp is not held against it.
local function looksStale(events)
	local e = events[1]
	if type(e) ~= "table" then return false end
	local ts = ns.num(e.timestamp)
	if not ts then return false end
	local now = time()
	if ts > 1000000000 and (now - ts) > 120 then return true end
	return false
end

local function isPlayerGUID(guid)
	return guid and string.find(guid, "^Player%-") ~= nil
end

-- Every distinct enemy player who contributed to killing you.
local function extractKillers(events)
	local myGUID = select(2, ns.try(UnitGUID, "player"))
	myGUID = ns.str(myGUID)

	local seen, killers = {}, {}

	for i, e in ipairs(events) do
		if type(e) == "table" then
			local hidden = e.hideCaster
			local isHidden = ns.usable(hidden) and hidden == true
			if not isHidden then
				local guidRaw = e.sourceGUID
				local guid = ns.str(guidRaw)
				local guidIsSecret = ns.isSecret(guidRaw)
				local name = ns.str(e.sourceName)
				local isPlayer = isPlayerGUID(guid)

				-- With no usable GUID we cannot tell a player from a mob,
				-- so a bare name is offered as unconfirmed rather than
				-- dropped. Never compare guidRaw itself: it may be secret.
				if not guid and name and not guidIsSecret then
					isPlayer = nil -- unknown; let the prompt ask
				end

				local isMe = guid and myGUID and guid == myGUID
				if not isMe and (isPlayer or isPlayer == nil) and (guid or name) then
					local dedupe = guid or ("name:" .. string.lower(name))
					if not seen[dedupe] then
						seen[dedupe] = true
						killers[#killers + 1] = {
							guid = guid,
							name = name,
							spell = ns.str(e.spellName),
							killingBlow = (i == 1),
							certain = isPlayer == true,
						}
					end
				end
			end
		end
	end

	return killers
end

-- ===========================================================================
-- Handling a death
-- ===========================================================================

local function handleKillers(killers)
	local db = ns.db
	local fresh, repeats = {}, {}

	for _, k in ipairs(killers) do
		local key, entry = ns.List:Find(k.guid, k.name)
		if entry then
			ns.List:RecordTheirKill(k)
			repeats[#repeats + 1] = entry
		else
			fresh[#fresh + 1] = k
		end
	end

	if #repeats > 0 and db.settings.announceRepeat then
		for _, entry in ipairs(repeats) do
			ns.Print(string.format("|cffff4444%s|r got you again. That is %d to %d.",
				entry.name or "?", entry.theyKilledMe or 0, entry.iKilledThem or 0))
		end
	end

	if #fresh > 0 and db.settings.promptOnDeath then
		ns.Fire("OFFER_CANDIDATES", fresh)
	end
end

local function processRecap(reason)
	local events = getRecapEvents()
	if not events then return false end

	if looksStale(events) then return false end

	local sig = signatureOf(events)
	if sig and ns.db.lastRecapSig == sig
		and ns.db.lastRecapAt and (time() - ns.db.lastRecapAt) < 120 then
		return true -- already dealt with this one
	end

	local killers = extractKillers(events)
	ns.db.lastRecapSig = sig
	ns.db.lastRecapAt = time()

	if #killers == 0 then
		return true -- a mob, a fall, the environment: not our business
	end

	handleKillers(killers)
	return true
end

local function poll()
	if pollsLeft <= 0 then return end
	pollsLeft = pollsLeft - 1
	if processRecap("death") then return end
	if pollsLeft > 0 then
		C_Timer.After(POLL_DELAY, poll)
	end
end

-- ===========================================================================
-- Events
-- ===========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_DEAD")
f:SetScript("OnEvent", function(_, event)
	if event ~= "PLAYER_DEAD" then return end
	if not ns.db then return end
	if not ns.InTrackedZone() then return end
	pollsLeft = POLL_TRIES
	C_Timer.After(0.1, poll)
end)

-- Exposed so /vendetta recap can re-read the last death on demand.
ns.Deaths = {
	ReadNow = function()
		local events = getRecapEvents()
		if not events then
			ns.Print("No death recap available right now.")
			return
		end
		local killers = extractKillers(events)
		if #killers == 0 then
			ns.Print("Last death was not caused by an enemy player.")
			return
		end
		ns.Print("Last death, " .. #killers .. " player source(s):")
		for _, k in ipairs(killers) do
			ns.Print(string.format("  %s%s%s", k.name or "?",
				k.killingBlow and " |cffffd100(killing blow)|r" or "",
				k.spell and (" -- " .. k.spell) or ""))
		end
		ns.Fire("OFFER_CANDIDATES", killers)
	end,
	ForceProcess = function() return processRecap("manual") end,
}
