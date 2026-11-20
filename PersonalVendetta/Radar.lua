--[[-------------------------------------------------------------------------
  Personal Vendetta -- Radar
  Works out which people from the list are near you.

  There is no API that enumerates nearby players, so nameplates are the
  radar: whatever the client is willing to draw a plate for is what we can
  see. Your target and your mouseover are added as free extra sightings,
  since those reach past nameplate range.

  Forever is reported to fire NAME_PLATE_UNIT_ADDED before the unit token is
  populated, so the events only nudge a sweep awake -- the sweep itself is
  what reads units, and it re-reads them every tick.

  Messages fired:
    SIGHTED (entries)          someone from the list just came into view
    RADAR_CHANGED              the nearby set or someone's state changed
    UNIT_SEEN (entry, unit)    every sweep, for each list member in view
    SEEN_DIE (entry, unit)     we watched a list member go from alive to dead
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local SWEEP_INTERVAL = 0.4
local LOSE_AFTER = 2.5   -- seconds out of sight before we call them gone
local REALERT_AFTER = 30 -- per player: gone this long before a return sounds again
local SEEN_LOG_EVERY = 3600 -- one "seen" history line per player per hour
local MAX_PLATES = 40

local Radar = { nearby = {}, lastSweep = 0, goneAt = {} }
ns.Radar = Radar

local ticker

-- ===========================================================================
-- Reading one unit
-- ===========================================================================

local function readBool(fn, ...)
	local ok, v = ns.try(fn, ...)
	if not ok or not ns.usable(v) then return nil end
	return v and true or false
end

local function isDead(unit)
	return readBool(UnitIsDeadOrGhost, unit) or readBool(UnitIsDead, unit) or false
end

-- Is this unit someone who could be on the list?
-- A corpse is not attackable, so "attackable" alone would hide every kill
-- from us. Hostile reaction usually covers the dead, and if the client
-- stops calling a corpse hostile, being on the list is proof enough: the
-- caller still requires a list match.
local function isEnemyPlayer(unit)
	if not readBool(UnitExists, unit) then return false end
	if not readBool(UnitIsPlayer, unit) then return false end
	if readBool(UnitCanAttack, "player", unit) then return true end
	if readBool(UnitIsEnemy, "player", unit) then return true end
	if isDead(unit) then return true end
	return false
end

-- First name and surname of a unit. Forever's UnitName returns them as two
-- values; Blizzard's own Forever code reads them from UnitNameUnmodified.
local function unitNames(unit)
	local fn = UnitNameUnmodified or UnitName
	local ok, first, last = ns.try(fn, unit)
	if not ok then return nil, nil end
	return ns.SplitName(first, last)
end
Radar.UnitNames = unitNames

-- Returns entry, guid, first, surname for a unit on the list, else nil.
local function identify(unit)
	if not isEnemyPlayer(unit) then return nil end

	local _, guidRaw = ns.try(UnitGUID, unit)
	local guid = ns.str(guidRaw)
	local first, last = unitNames(unit)
	if not guid and not first then return nil end

	local key, entry = ns.List:Find(guid, first, last)
	if not entry then return nil end
	return entry, guid, first, last
end

-- Everything we can read off a unit right now, for anyone (on the list or
-- not). Unreadable fields are simply left out.
function Radar:ReadUnitInfo(unit)
	local _, guidRaw = ns.try(UnitGUID, unit)
	local first, last = unitNames(unit)
	local info = { guid = ns.str(guidRaw), name = first, surname = last }

	local ok, level = ns.try(UnitLevel, unit)
	level = ok and ns.num(level) or nil
	if level and level > 0 then
		info.level = level
	elseif level == -1 then
		info.levelSkull = true
	end
	local _, className, classFile = ns.try(UnitClass, unit)
	info.className = ns.str(className)
	info.class = ns.str(classFile)
	local _, raceName = ns.try(UnitRace, unit)
	info.race = ns.str(raceName)
	return info
end

-- The unit token currently showing this GUID, if any is in view.
function Radar:FindUnitByGUID(guid)
	guid = ns.str(guid)
	if not guid then return nil end
	local function check(unit)
		local ok, g = ns.try(UnitGUID, unit)
		return ok and ns.str(g) == guid
	end
	if check("target") then return "target" end
	if check("mouseover") then return "mouseover" end
	for i = 1, MAX_PLATES do
		local unit = "nameplate" .. i
		if check(unit) then return unit end
	end
	return nil
end

-- Top up what we know while we can actually see them.
-- Returns levelFresh: whether the level shown is from this very sighting.
local function enrich(entry, unit, guid, name, surname)
	local info = { guid = guid, name = name, surname = surname }
	local levelFresh = false

	local ok, level = ns.try(UnitLevel, unit)
	level = ok and ns.num(level) or nil
	if level then
		if level > 0 then
			info.level = level
			levelFresh = true
		elseif level == -1 then
			info.levelSkull = true
			levelFresh = true
		end
	end

	local _, className, classFile = ns.try(UnitClass, unit)
	info.className = ns.str(className)
	info.class = ns.str(classFile)

	local _, raceName = ns.try(UnitRace, unit)
	info.race = ns.str(raceName)

	ns.List:Upsert(info)
	entry.lastSeen = time()
	return levelFresh
end

-- ===========================================================================
-- The sweep
-- ===========================================================================

local function sweep()
	if not ns.db then return end

	local tick = GetTime()
	local seenThisSweep = {}
	local newSightings = {}
	local changed = false

	local function consider(unit)
		local entry, guid, name, surname = identify(unit)
		if not entry then return end
		local key = entry.key
		if not key or seenThisSweep[key] then return end
		seenThisSweep[key] = true

		local levelFresh = enrich(entry, unit, guid, name, surname)
		local dead = isDead(unit)

		local record = Radar.nearby[key]
		if not record then
			record = { entry = entry, firstTick = tick, dead = dead }
			Radar.nearby[key] = record
			-- Walking up to a corpse is not a sighting worth a horn. Nor is
			-- someone stepping back into range moments after leaving it: each
			-- player has to be gone a while before their return sounds again.
			local gone = Radar.goneAt[key]
			local quickReturn = gone and (tick - gone) < REALERT_AFTER
			if not dead and not quickReturn then
				newSightings[#newSightings + 1] = entry
			end
			if not dead then
				entry.lastZone = ns.Zone() or entry.lastZone
				if not entry.lastSeenLog or (time() - entry.lastSeenLog) >= SEEN_LOG_EVERY then
					entry.lastSeenLog = time()
					ns.List:Log(entry, "seen")
				end
			end
			changed = true
		else
			if dead and not record.dead then
				ns.Fire("SEEN_DIE", entry, unit)
				changed = true
			elseif record.dead and not dead then
				changed = true -- resurrected
			end
			record.dead = dead
		end

		if record.levelFresh ~= levelFresh then changed = true end
		record.levelFresh = levelFresh
		record.unit = unit
		record.lastTick = tick
		record.entry = entry

		ns.Fire("UNIT_SEEN", entry, unit, record)
	end

	for i = 1, MAX_PLATES do
		consider("nameplate" .. i)
	end
	consider("target")
	consider("mouseover")

	-- Expire anyone we have lost sight of, remembering when they left.
	for key, record in pairs(Radar.nearby) do
		if (tick - (record.lastTick or 0)) > LOSE_AFTER then
			Radar.nearby[key] = nil
			Radar.goneAt[key] = record.lastTick or tick
			changed = true
		end
	end

	Radar.lastSweep = time()

	if #newSightings > 0 then
		ns.Fire("SIGHTED", newSightings)
	end
	if changed then
		ns.Fire("RADAR_CHANGED")
	end
end

-- A nameplate leaving is often the moment someone dies. The token is still
-- valid while this event runs, so check them on the way out.
local function onPlateRemoved(unit)
	if type(unit) ~= "string" then return end
	local entry = identify(unit)
	if not entry or not entry.key then return end
	local record = Radar.nearby[entry.key]
	if record and not record.dead and isDead(unit) then
		record.dead = true
		ns.Fire("SEEN_DIE", entry, unit)
		ns.Fire("RADAR_CHANGED")
	end
end

-- ===========================================================================
-- Queries
-- ===========================================================================

-- Nearby entries: living first, scum first, then worst offender first.
function Radar:GetNearby()
	local t = {}
	for _, record in pairs(self.nearby) do
		if record.entry then t[#t + 1] = record end
	end
	table.sort(t, function(a, b)
		if (a.dead or false) ~= (b.dead or false) then return not a.dead end
		local as, bs = a.entry.scum and true or false, b.entry.scum and true or false
		if as ~= bs then return as end
		local ak, bk = a.entry.theyKilledMe or 0, b.entry.theyKilledMe or 0
		if ak ~= bk then return ak > bk end
		return ns.FullName(a.entry) < ns.FullName(b.entry)
	end)
	return t
end

function Radar:Count()
	local n = 0
	for _, record in pairs(self.nearby) do
		if not record.dead then n = n + 1 end
	end
	return n
end

function Radar:Get(key)
	return self.nearby[key]
end

-- ===========================================================================
-- Nameplate range
-- ===========================================================================

-- Whatever sticks here is the true radius of this addon.
function Radar:GetRange()
	local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
	local ok, v = ns.try(get, "nameplateMaxDistance")
	return ok and ns.str(v) or "?"
end

function Radar:SetRange(n)
	local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
	ns.try(set, "nameplateMaxDistance", tostring(n))
	local now = self:GetRange()
	ns.Print(string.format(ns.L["Nameplate distance asked for %s, the game reports %s."], tostring(n), tostring(now)))
	return now
end

-- ===========================================================================
-- Nameplates: the radar's eyes
--   nameplateShowEnemies  draw plates for enemies at all
--   nameplateShowAll      draw them always, not only once you are in combat;
--                         without it the radar is blind until a fight starts
-- Blizzard's own UI sets both with SetCVar. Changing them mid-fight is not
-- something to try, so a request in combat waits for combat to end.
-- ===========================================================================

local PLATE_CVARS = { "nameplateShowEnemies", "nameplateShowAll" }
local pendingEnable = false

local function cvarOn(name)
	local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
	local ok, v = ns.try(get, name)
	return ok and ns.str(v) == "1"
end

function Radar:NameplatesOn()
	for _, name in ipairs(PLATE_CVARS) do
		if not cvarOn(name) then return false end
	end
	return true
end

-- Which of the two are off, for a precise message.
function Radar:NameplatesMissing()
	local missing = {}
	if not cvarOn("nameplateShowEnemies") then missing[#missing + 1] = ns.L["enemy nameplates"] end
	if not cvarOn("nameplateShowAll") then missing[#missing + 1] = ns.L["\"always show nameplates\""] end
	return missing
end

local function inCombat()
	local ok, v = ns.try(InCombatLockdown)
	return ok and v == true
end

function Radar:EnableNameplates(quiet)
	if self:NameplatesOn() then
		if not quiet then ns.Print(ns.L["Enemy nameplates are already on. The radar can see."]) end
		return true
	end
	if inCombat() then
		pendingEnable = true
		ns.Print(ns.L["In combat -- enemy nameplates will switch on the moment the fight ends."])
		return false
	end
	local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
	for _, name in ipairs(PLATE_CVARS) do
		ns.try(set, name, "1")
	end
	pendingEnable = false
	if self:NameplatesOn() then
		ns.Print("|cff44ff44" .. ns.L["Enemy nameplates on."] .. "|r " .. ns.L["The radar can see. (V toggles them in game.)"])
		ns.Fire("SETTINGS_CHANGED")
		C_Timer.After(0.05, sweep)
		return true
	end
	ns.Print("|cffff4444" .. ns.L["The game would not switch them on."] .. "|r "
		.. ns.L["Open Options > Nameplates and tick \"Show Enemy Nameplates\" and \"Always Show Nameplates\"."])
	return false
end

-- Switch enemy nameplates off (the radar goes blind). The client refuses
-- nameplate changes in combat, so that is said rather than failing quietly.
function Radar:DisableNameplates()
	if not self:NameplatesOn() and not cvarOn("nameplateShowEnemies") then return true end
	if inCombat() then
		ns.Print(ns.L["Nameplates can't be changed in combat. Try again once the fight ends."])
		return false
	end
	pendingEnable = false
	local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
	ns.try(set, "nameplateShowEnemies", "0")
	ns.Print(ns.L["Enemy nameplates off. The radar is blind until you switch them back on."])
	ns.Fire("SETTINGS_CHANGED")
	return true
end

-- Route to Blizzard's own Nameplates settings page. Restricted in combat.
function Radar:OpenNameplateSettings()
	if inCombat() then
		ns.Print(ns.L["Settings can't be opened in combat. Try again once the fight ends."])
		return false
	end
	local id = Settings and Settings.NAMEPLATE_OPTIONS_CATEGORY_ID
	if id and Settings.OpenToCategory then
		local ok = pcall(Settings.OpenToCategory, id)
		if ok then return true end
	end
	ns.Print(ns.L["Couldn't open it directly: Esc > Options > Nameplates."])
	return false
end

function Radar:CheckSetup()
	if self:NameplatesOn() then return end
	ns.Print("|cffff4444" .. ns.L["The radar is blind:"] .. "|r "
		.. string.format(ns.L["%s off. Fix it with /vendetta nameplates or in the settings (minimap skull)."],
			table.concat(self:NameplatesMissing(), ns.L[" and "])))
end

-- ===========================================================================
-- Events
-- ===========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("CVAR_UPDATE")
f:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		onPlateRemoved(unit)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingEnable then Radar:EnableNameplates() end
		return
	end
	if event == "CVAR_UPDATE" then
		-- Pressing V, or ticking it in Blizzard's options: keep our panel honest.
		ns.Fire("SETTINGS_CHANGED")
		return
	end
	-- Do not read the unit here; Forever may not have populated it yet.
	-- Just let the next sweep pick it up promptly.
	C_Timer.After(0.05, sweep)
end)

ns.On("DB_READY", function()
	if ticker then ticker:Cancel() end
	ticker = C_Timer.NewTicker(SWEEP_INTERVAL, sweep)
	C_Timer.After(2, function() Radar:CheckSetup() end)
end)

-- A fresh name on the list should be matched immediately, not next tick.
ns.On("LIST_CHANGED", function()
	C_Timer.After(0.05, sweep)
end)

Radar.Sweep = sweep
Radar.IsDead = isDead
Radar.IsEnemyPlayer = isEnemyPlayer
