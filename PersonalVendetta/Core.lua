--[[-------------------------------------------------------------------------
  Personal Vendetta -- Core
  Shared state, secret-safe helpers, and the hit list itself.

  This addon never registers COMBAT_LOG_EVENT_UNFILTERED. On the Forever /
  Midnight API that registration is forbidden and taints the addon.

  Secret values: a value from the client may be "secret". You may store or
  concatenate it, but arithmetic, comparison, indexing and table keys all
  error on one. So nothing reaches the list unless usable() says it is real.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.VERSION = "3.0"
ns.PREFIX = "|cff9933ffVendetta|r "

-- Art. The icon ships in Media\; WoW finds icon.tga without the extension.
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon"
ns.SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"
ns.SCUM_COLOR = "|cffff2020"

-- ===========================================================================
-- Secret-safe primitives
-- ===========================================================================

local rawIsSecret = _G.issecretvalue

function ns.isSecret(v)
	if not rawIsSecret then return false end
	local ok, res = pcall(rawIsSecret, v)
	return ok and res == true
end

-- A value we are allowed to compare, key on, and trust.
-- The secret test must come first: comparing a secret to nil is itself a
-- comparison, and comparisons on secrets error.
function ns.usable(v)
	if ns.isSecret(v) then return false end
	return v ~= nil
end

-- Printable form of anything, secret or not.
function ns.S(v)
	if ns.isSecret(v) then return "<secret>" end
	if v == nil then return "nil" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unreadable>"
end

-- Call an API that may be missing or restricted. Returns ok, results...
function ns.try(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return false end
	return true, a, b, c, d
end

-- A usable string or nil. Never returns a secret.
function ns.str(v)
	if not ns.usable(v) then return nil end
	local ok, s = pcall(tostring, v)
	if not ok or s == "" then return nil end
	return s
end

-- A usable number or nil.
function ns.num(v)
	if not ns.usable(v) then return nil end
	if type(v) ~= "number" then return nil end
	return v
end

function ns.Print(msg)
	print(ns.PREFIX .. tostring(msg))
end

-- ===========================================================================
-- Database
-- ===========================================================================

local DEFAULTS = {
	version = 1,
	list = {},        -- key -> entry
	settings = {
		promptOnDeath = true,
		promptAfterFight = true,
		announceRepeat = true,
		overlayShown = true,
		overlayPoint = nil,
		sound = {
			enabled = true,
			choice = "warhorn",
			volume = 0.6,       -- 0..1, applied through PlaySound's volumeOverride
			scumChoice = "airhorn",
			scumVolume = 0.6,   -- scum gets its own sound and its own level
			quietCapitals = false, -- no horn or chat alert inside the capital cities
			quietTowns = false,    -- nor in neutral towns (Gadgetzan...) and inns
		},
		minimap = {
			angle = 215,    -- degrees around the minimap rim; always shown
		},
		window = {
			locked = false,
			scale = 1,
			opacity = 0.55,   -- background only; text stays readable
			autoHide = false, -- hide entirely when nobody is near and nothing waits
		},
		markNameplates = true,   -- skull above listed players' nameplates
		celebrate = true,        -- toast and fanfare when you settle a score
		partyAlertSend = true,   -- tell your group when you spot someone
		partyAlertReceive = true,
		scumWarnButton = true,   -- Warn button on scum rows in the floating window
		scumWarnParty = true,    -- post scum sightings in party/raid chat
		listSort = "newest",
	},
	lastRecapSig = nil,
	pending = {},     -- the To add queue
}

local function applyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			applyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
end

function ns.InitDB()
	PersonalVendettaDB = PersonalVendettaDB or {}
	local db = PersonalVendettaDB

	-- 0.4 and earlier kept a single on/off for the sighting sound.
	local oldSound = db.settings and db.settings.soundOnSighting
	applyDefaults(db, DEFAULTS)
	if oldSound ~= nil then
		db.settings.sound.enabled = oldSound and true or false
		db.settings.soundOnSighting = nil
	end

	-- 0.5 let you hide the minimap button. It is always there now.
	db.settings.minimap.hide = nil

	-- 1.0 saved a name index; 1.1 rebuilds it in memory, surname-aware.
	db.nameIndex = nil

	ns.db = db

	-- The account-wide store. Whether it is in use is an account setting:
	-- every character sees the same answer.
	PersonalVendettaAccountDB = PersonalVendettaAccountDB or {}
	local acct = PersonalVendettaAccountDB
	acct.list = acct.list or {}
	ns.account = acct
	if acct.enabled and not db.mergedIntoAccount then
		ns.MergeIntoAccount()
	end

	ns.List:Reindex()
	return ns.db
end

-- The list in use right now: this character's own, or the shared one.
function ns.ListData()
	if ns.account and ns.account.enabled then return ns.account.list end
	return ns.db.list
end

function ns.IsAccountWide()
	return ns.account and ns.account.enabled and true or false
end

local function copyTable(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = copyTable(v) end
	return c
end
ns.CopyTable = copyTable

-- Fold this character's list into the shared one. Someone on both becomes
-- one entry: deaths on different characters are different deaths, so the
-- counts add up; everything else keeps the richest information.
function ns.MergeIntoAccount()
	local acct, db = ns.account, ns.db
	local wasEnabled = acct.enabled
	acct.enabled = true
	ns.List:Reindex()
	local merged, added = 0, 0
	for key, mine in pairs(db.list) do
		local k2, theirs = ns.List:Find(mine.guid, mine.name, mine.surname)
		if theirs then
			theirs.theyKilledMe = (theirs.theyKilledMe or 0) + (mine.theyKilledMe or 0)
			theirs.iKilledThem = (theirs.iKilledThem or 0) + (mine.iKilledThem or 0)
			theirs.scum = theirs.scum or mine.scum
			if mine.note and (not theirs.note or #mine.note > #theirs.note) then theirs.note = mine.note end
			theirs.firstAdded = math.min(theirs.firstAdded or mine.firstAdded or time(), mine.firstAdded or time())
			theirs.lastSeen = math.max(theirs.lastSeen or 0, mine.lastSeen or 0)
			if theirs.lastSeen == 0 then theirs.lastSeen = nil end
			for _, f in ipairs({ "guid", "surname", "level", "class", "className", "race", "lastZone" }) do
				if theirs[f] == nil then theirs[f] = mine[f] end
			end
			theirs.history = theirs.history or {}
			for _, h in ipairs(mine.history or {}) do theirs.history[#theirs.history + 1] = copyTable(h) end
			table.sort(theirs.history, function(a, b) return (a.t or 0) < (b.t or 0) end)
			merged = merged + 1
		else
			acct.list[key] = copyTable(mine)
			added = added + 1
		end
		ns.List:Reindex()
	end
	db.mergedIntoAccount = true
	acct.enabled = wasEnabled
	return added, merged
end

-- Turn the shared list on or off for every character.
function ns.SetAccountWide(on)
	on = on and true or false
	if on == ns.IsAccountWide() then return end
	if on then
		ns.account.enabled = true
		if not ns.db.mergedIntoAccount then
			local added, merged = ns.MergeIntoAccount()
			ns.Print(string.format(ns.L["Shared list on. This character's list was merged in: %d added, %d combined."],
				added, merged))
		else
			ns.Print(ns.L["Shared list on."])
		end
	else
		ns.account.enabled = false
		ns.Print(ns.L["Shared list off. This character is back to its own list."])
	end
	ns.List:Reindex()
	ns.Fire("LIST_CHANGED")
	ns.Fire("SETTINGS_CHANGED")
end

-- ===========================================================================
-- Names
-- Forever characters have a first name and a surname. UnitName returns them
-- as two values (the slot retail uses for the realm holds the surname), and
-- some sources hand over both joined by Blizzard's separator. Everything in
-- the addon goes through SplitName so both shapes end up the same.
-- ===========================================================================

local function separator()
	local c = Constants and Constants.CharacterNameSeparatorConsts
	local s = c and c.CHARACTERNAME_SURNAME_SEPARATOR
	if type(s) == "string" and s ~= "" then return s end
	return " " -- what Blizzard's own slash-command code says it is
end
ns.NameSeparator = separator

-- (first, surname) from "First", ("First", "Last") or "First Last".
function ns.SplitName(name, surname)
	local first, last = ns.str(name), ns.str(surname)
	if not first then return nil, nil end
	if not last then
		local sep = separator()
		local i = string.find(first, sep, 1, true)
		if i and i > 1 then
			local rest = string.sub(first, i + #sep)
			first = string.sub(first, 1, i - 1)
			if rest ~= "" then last = rest end
		end
	end
	return first, last
end

-- "First Last" for display, or just "First" while the surname is unknown.
function ns.FullName(entryOrName, surname)
	local first, last
	if type(entryOrName) == "table" then
		first, last = entryOrName.name, entryOrName.surname
	else
		first, last = entryOrName, surname
	end
	if not first then return "?" end
	if last and last ~= "" then return first .. separator() .. last end
	return first
end

-- ===========================================================================
-- The hit list
-- ===========================================================================

local List = {}
ns.List = List

-- In-memory lookups, rebuilt from the saved list at login:
--   byFull[ "first last" ] = key        (only once the surname is known)
--   byFirst[ "first" ]     = { key = true, ... }
local byFull, byFirst = {}, {}

local function lower(s) return s and string.lower(s) or nil end

local function indexEntry(key, entry)
	local first = entry.name and lower(entry.name)
	if first then
		byFirst[first] = byFirst[first] or {}
		byFirst[first][key] = true
	end
	if entry.name and entry.surname then
		byFull[lower(ns.FullName(entry))] = key
	end
end

local function unindexEntry(key, entry)
	local first = entry.name and lower(entry.name)
	if first and byFirst[first] then
		byFirst[first][key] = nil
		if next(byFirst[first]) == nil then byFirst[first] = nil end
	end
	if entry.name and entry.surname then
		local full = lower(ns.FullName(entry))
		if byFull[full] == key then byFull[full] = nil end
	end
end

function List:Reindex()
	byFull, byFirst = {}, {}
	for key, entry in pairs(ns.ListData()) do
		entry.key = key
		indexEntry(key, entry)
	end
end

-- GUID is the durable identity. A name is the fallback when the GUID is
-- secret or missing, and a manual add has nothing else.
local function keyFor(guid, first, last)
	local g = ns.str(guid)
	if g and string.find(g, "^Player%-") then return g end
	if first then return "name:" .. lower(ns.FullName(first, last)) end
	return nil
end
ns.keyFor = keyFor

-- Find an entry. Returns key, entry -- or nil, nil, count when a bare first
-- name matches more than one person (count says how many).
--
-- Matching rules, in order:
--   1. the GUID, when we have a usable one;
--   2. the full name;
--   3. the first name, only if exactly one entry could be that person.
-- An entry that already has a GUID is never matched to a different GUID by
-- name: two players called Willia are two players.
function List:Find(guid, name, surname)
	local db = { list = ns.ListData() }
	local g = ns.str(guid)
	if g and db.list[g] then return g, db.list[g] end

	local first, last = ns.SplitName(name, surname)
	if not first then return nil, nil end

	local function compatible(e)
		if g and e.guid and e.guid ~= g then return false end
		if last and e.surname and lower(e.surname) ~= lower(last) then return false end
		return true
	end

	if last then
		local k = byFull[lower(ns.FullName(first, last))]
		local e = k and db.list[k]
		if e and compatible(e) then return k, e end
	end

	local set = byFirst[lower(first)]
	if set then
		local found, n = nil, 0
		for k in pairs(set) do
			local e = db.list[k]
			if e and compatible(e) then found, n = k, n + 1 end
		end
		if n == 1 then return found, db.list[found] end
		if n > 1 then return nil, nil, n end
	end
	return nil, nil
end

function List:Count()
	local n = 0
	for _ in pairs(ns.ListData()) do n = n + 1 end
	return n
end

-- ===========================================================================
-- History: what happened, when, where
-- ===========================================================================

local HISTORY_MAX = 40
local LEVELS_MAX = 20

-- Where you are right now: "Darkshire, Duskwood", or just "Duskwood".
function ns.Zone()
	local okZ, zone = ns.try(GetRealZoneText)
	local okS, sub = ns.try(GetSubZoneText)
	zone = okZ and ns.str(zone) or nil
	sub = okS and ns.str(sub) or nil
	if sub and zone and sub ~= zone then return sub .. ", " .. zone end
	return zone or sub
end

-- Map coordinates where you stand, "42, 65", when the game will say.
function ns.Coords()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local okM, map = ns.try(C_Map.GetBestMapForUnit, "player")
	map = okM and ns.num(map)
	if not map then return nil end
	local okP, pos = ns.try(C_Map.GetPlayerMapPosition, map, "player")
	if not okP or type(pos) ~= "table" or not pos.GetXY then return nil end
	local okX, x, y = pcall(pos.GetXY, pos)
	x, y = okX and ns.num(x), okX and ns.num(y)
	if not x or not y or (x == 0 and y == 0) then return nil end
	return string.format("%d, %d", math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
end

-- event: "died" (they killed you), "killed" (you won), "fought" (you both
-- walked away), "seen", "added", "shared". Where it happened is kept too.
function List:Log(entry, event, extra)
	if not entry then return end
	entry.history = entry.history or {}
	local h = { t = time(), e = event, z = ns.Zone(), xy = ns.Coords(), lv = entry.level }
	if extra then for k, v in pairs(extra) do h[k] = v end end
	entry.history[#entry.history + 1] = h
	while #entry.history > HISTORY_MAX do table.remove(entry.history, 1) end
	if h.z then entry.lastZone = h.z end
	return h
end

-- Remember each level we see them at, once per change.
local function noteLevel(entry, level)
	if not level then return end
	entry.levels = entry.levels or {}
	local last = entry.levels[#entry.levels]
	if last and last.lv == level then return end
	entry.levels[#entry.levels + 1] = { t = time(), lv = level }
	while #entry.levels > LEVELS_MAX do table.remove(entry.levels, 1) end
end
ns.NoteLevel = noteLevel

-- Create or update an entry. info may carry guid, name, surname (or a
-- joined "First Last" name), level, levelSkull, class, className, race.
function List:Upsert(info)
	local db = { list = ns.ListData() }
	local guid = ns.str(info.guid)
	local first, last = ns.SplitName(info.name, info.surname)
	if not guid and not first then return nil, nil end

	local key, entry = self:Find(guid, first, last)

	-- Promote a name-keyed entry to its real GUID once we learn it.
	if key and guid and string.find(key, "^name:") then
		unindexEntry(key, entry)
		db.list[guid] = entry
		db.list[key] = nil
		key = guid
	elseif key then
		unindexEntry(key, entry)
	end

	if not key then
		key = keyFor(guid, first, last)
		if not key then return nil, nil end
		entry = {
			key = key,
			theyKilledMe = 0,
			iKilledThem = 0,
			firstAdded = time(),
		}
		db.list[key] = entry
	end

	-- Always refresh this: a name-keyed entry that just learned its GUID
	-- has a new key, and the radar indexes on entry.key.
	entry.key = key

	entry.guid = guid or entry.guid
	entry.name = first or entry.name
	entry.surname = last or entry.surname
	entry.realm = nil -- older versions had a field for this; Forever has surnames
	-- The client reports -1 ("??") for anyone 10+ levels above you. That is
	-- exactly when an old cached number would lie to you, so it is stored
	-- as its own fact rather than ignored.
	local level = ns.num(info.level)
	if info.levelSkull then
		entry.levelSkull = true
		entry.levelAt = time()
	elseif level and level > 0 then
		entry.level = level
		entry.levelSkull = nil
		entry.levelAt = time()
		noteLevel(entry, level)
	end
	entry.class = ns.str(info.class) or entry.class
	entry.className = ns.str(info.className) or entry.className
	entry.race = ns.str(info.race) or entry.race

	indexEntry(key, entry)
	return key, entry
end

-- Returns true plus a snapshot that Restore can put back (for Undo).
function List:Remove(guid, name)
	local key, entry, count = self:Find(guid, name)
	if not key then return false, count end
	local snapshot = { key = key, entry = copyTable(entry) }
	unindexEntry(key, entry)
	ns.ListData()[key] = nil
	ns.Fire("LIST_CHANGED")
	return true, snapshot
end

function List:RemoveKey(key)
	local entry = key and ns.ListData()[key]
	if not entry then return nil end
	local snapshot = { key = key, entry = copyTable(entry) }
	unindexEntry(key, entry)
	ns.ListData()[key] = nil
	ns.Fire("LIST_CHANGED")
	return snapshot
end

function List:Restore(snapshot)
	if not snapshot or not snapshot.key then return nil end
	local data = ns.ListData()
	if data[snapshot.key] then return data[snapshot.key] end
	local entry = copyTable(snapshot.entry)
	entry.key = snapshot.key
	data[snapshot.key] = entry
	indexEntry(snapshot.key, entry)
	ns.Fire("LIST_CHANGED")
	return entry
end

function List:Wipe()
	local data = ns.ListData()
	for k in pairs(data) do data[k] = nil end
	byFull, byFirst = {}, {}
	ns.Fire("LIST_CHANGED")
end

function List:RecordTheirKill(info)
	local key, entry = self:Upsert(info)
	if not entry then return nil end
	entry.theyKilledMe = (entry.theyKilledMe or 0) + 1
	entry.lastKilledMe = time()
	entry.lastSeen = time() -- they were standing over you
	entry.streak = 0
	-- How: the spell that hit you, whether it was the killing blow, and how
	-- many of them there were.
	List:Log(entry, "died", { sp = ns.str(info.spell), kb = info.killingBlow and true or nil, n = info.n })
	ns.Fire("LIST_CHANGED")
	return entry
end

-- Someone you fought and survived. They have not killed you, so their
-- count stays where it is; yours goes up if you saw them drop.
function List:AddFromFight(info)
	local key, entry = self:Upsert(info)
	if not entry then return nil end
	if info.killedByMe then
		entry.iKilledThem = (entry.iKilledThem or 0) + 1
		entry.lastIKilledThem = time()
		List:Log(entry, "killed")
	else
		List:Log(entry, "added")
	end
	entry.lastSeen = time()
	ns.Fire("LIST_CHANGED")
	return entry
end

-- Several signals can report the same kill (seeing them drop, the honor
-- message, the HK counter ticking). Anything inside this window after a
-- counted kill is the same kill. Nobody corpse-runs and dies again in 45s.
local KILL_DEDUPE = 45

-- Returns entry, counted. counted is false when this kill was already in.
-- force skips the dedupe window, for hand corrections.
function List:RecordMyKill(info, force)
	local key, entry = self:Find(ns.str(info.guid), ns.str(info.name), ns.str(info.surname))
	if not entry then return nil, false end

	local now = time()
	if not force and entry.lastIKilledThem and (now - entry.lastIKilledThem) < KILL_DEDUPE then
		return entry, false
	end

	local before = entry.iKilledThem or 0
	entry.iKilledThem = before + 1
	entry.lastIKilledThem = now
	entry.streak = (entry.streak or 0) + 1
	List:Log(entry, "killed")
	ns.Fire("LIST_CHANGED")

	-- The payoff: drawing level, or pulling ahead, after being behind.
	local theirs = entry.theyKilledMe or 0
	if not force and theirs > 0 and before < theirs and entry.iKilledThem >= theirs then
		entry.settledAt = now
		ns.Fire("SCORE_SETTLED", entry, entry.iKilledThem > theirs)
	elseif not force and (entry.streak == 3 or entry.streak == 5 or entry.streak == 10) then
		ns.Fire("STREAK", entry, entry.streak)
	end
	return entry, true
end

-- Scum: killed you dishonourably. A must-kill on sight.
function List:SetScum(key, isScum)
	local entry = key and ns.ListData()[key]
	if not entry then return nil end
	entry.scum = isScum and true or nil
	ns.Fire("LIST_CHANGED")
	return entry
end

-- Notes: what this person did. Plain text, kept short.
ns.NOTE_MAX = 300

function ns.CleanText(s, max)
	s = ns.str(s)
	if not s then return nil end
	-- No escape sequences (colours, textures, links) and no control bytes:
	-- notes can arrive from other players through sharing.
	s = string.gsub(s, "|", "/")
	s = string.gsub(s, "[%z\1-\9\11-\31\127]", "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if max and #s > max then s = string.sub(s, 1, max) end
	if s == "" then return nil end
	return s
end

function List:SetNote(key, text)
	local entry = key and ns.ListData()[key]
	if not entry then return nil end
	entry.note = ns.CleanText(text, ns.NOTE_MAX)
	ns.Fire("LIST_CHANGED")
	return entry
end

function List:Adjust(name, field, delta)
	local key, entry, count = self:Find(nil, name)
	if not entry then return nil, count end
	entry[field] = math.max(0, (entry[field] or 0) + delta)
	ns.Fire("LIST_CHANGED")
	return entry
end

-- Entries sorted worst-offender first.
function List:Sorted()
	local t = {}
	for key, entry in pairs(ns.ListData()) do
		entry.key = key
		t[#t + 1] = entry
	end
	table.sort(t, function(a, b)
		local ak, bk = a.theyKilledMe or 0, b.theyKilledMe or 0
		if ak ~= bk then return ak > bk end
		return ns.FullName(a) < ns.FullName(b)
	end)
	return t
end

-- Entries newest first: the order you added them in, latest on top.
function List:ByDateAdded()
	local t = {}
	for key, entry in pairs(ns.ListData()) do
		entry.key = key
		t[#t + 1] = entry
	end
	table.sort(t, function(a, b)
		local at, bt = a.firstAdded or 0, b.firstAdded or 0
		if at ~= bt then return at > bt end
		return ns.FullName(a) < ns.FullName(b)
	end)
	return t
end

-- "just now", "12 min ago", "3 hours ago", "2 days ago", or "never".
function ns.Ago(t)
	local L = ns.L
	if not t then return L["never"] end
	local d = time() - t
	if d < 60 then return L["just now"] end
	if d < 3600 then
		return string.format(L["%d min ago"], math.floor(d / 60))
	end
	if d < 86400 then
		local h = math.floor(d / 3600)
		return h == 1 and L["1 hour ago"] or string.format(L["%d hours ago"], h)
	end
	local days = math.floor(d / 86400)
	return days == 1 and L["1 day ago"] or string.format(L["%d days ago"], days)
end

-- ===========================================================================
-- A tiny internal message bus, so modules do not reach into each other
-- ===========================================================================

local listeners = {}

function ns.On(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end

function ns.Fire(msg, ...)
	local fns = listeners[msg]
	if not fns then return end
	for _, fn in ipairs(fns) do
		local ok, err = pcall(fn, ...)
		if not ok then
			ns.Print("|cffff4444error in " .. msg .. ":|r " .. tostring(err))
		end
	end
end

-- ===========================================================================
-- Context: are we somewhere that counts?
-- ===========================================================================

-- Open world only. Arenas and battlegrounds are explicitly out of scope,
-- and duels never reach here because a duel does not kill you.
function ns.InTrackedZone()
	local ok, inInstance, instType = ns.try(IsInInstance)
	if not ok then return true end
	if not ns.usable(instType) then return true end
	if instType == "arena" or instType == "pvp" then return false end
	return true
end

-- Cities and towns, where enemies stroll past all day and a horn every
-- minute is just noise. Places are matched by area ID through the client's
-- own (localized) area names, with the English name as a fallback.
local CAPITALS = {
	[1519] = "Stormwind City", [1537] = "Ironforge", [1657] = "Darnassus",
	[1637] = "Orgrimmar", [1638] = "Thunder Bluff", [1497] = "Undercity",
}
local TOWNS = {
	[35] = "Booty Bay", [976] = "Gadgetzan", [392] = "Ratchet", [2255] = "Everlook",
	[2268] = "Light's Hope Chapel", [3425] = "Cenarion Hold", [1446] = "Thorium Point",
}
local placeNames -- lower-case name -> "capital" | "town"
local function buildPlaceNames()
	placeNames = {}
	local getArea = C_Map and C_Map.GetAreaInfo
	local function add(ids, kind)
		for id, english in pairs(ids) do
			placeNames[string.lower(english)] = kind
			if getArea then
				local ok, name = ns.try(getArea, id)
				name = ok and ns.str(name)
				if name and name ~= "" then placeNames[string.lower(name)] = kind end
			end
		end
	end
	add(TOWNS, "town")
	add(CAPITALS, "capital") -- capitals win any clash
end

local function zoneText(fn)
	local ok, v = ns.try(fn)
	v = ok and ns.str(v)
	return v and v ~= "" and string.lower(v) or nil
end

-- "capital", "town" or nil for wherever you are standing.
function ns.PlaceKind()
	if not placeNames then buildPlaceNames() end
	local zone = GetRealZoneText and zoneText(GetRealZoneText)
	if zone and placeNames[zone] == "capital" then return "capital" end
	local sub = GetSubZoneText and zoneText(GetSubZoneText)
	if sub and placeNames[sub] then return placeNames[sub] end
	if zone and placeNames[zone] then return placeNames[zone] end
	-- Any other rest area (an inn, a town) counts as a town.
	local okR, resting = ns.try(IsResting)
	if okR and resting == true then return "town" end
	return nil
end

-- True when the player asked for quiet here.
function ns.InQuietPlace()
	local s = ns.db and ns.db.settings.sound
	if not s or not (s.quietCapitals or s.quietTowns) then return false end
	local kind = ns.PlaceKind()
	if kind == "capital" then return s.quietCapitals and true or false end
	if kind == "town" then return s.quietTowns and true or false end
	return false
end

-- Walking into or out of a quiet place changes what the radar dot shows.
do
	local watcher = CreateFrame("Frame")
	local wasQuiet
	for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
		"PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" }) do
		pcall(watcher.RegisterEvent, watcher, ev)
	end
	watcher:SetScript("OnEvent", function()
		if not ns.db then return end
		local quiet = ns.InQuietPlace()
		if quiet ~= wasQuiet then
			wasQuiet = quiet
			ns.Fire("QUIET_CHANGED", quiet)
		end
	end)
end

-- A checkbox from Blizzard's template, or drawn by hand if it is missing.
-- The template's own label is blanked; callers place their own text.
function ns.CreateCheckButton(parent)
	local ok, cb = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
	if not ok or not cb then
		cb = CreateFrame("CheckButton", nil, parent)
		cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
		cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
		cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
		cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	end
	cb:SetSize(24, 24)
	if cb.Text then cb.Text:SetText("") end
	return cb
end

-- Hover help for the Scum tickbox, wherever it appears.
function ns.ScumTooltip(owner)
	if not GameTooltip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ns.SCUM_COLOR .. ns.L["Scum"] .. "|r")
	GameTooltip:AddLine(ns.L["Killed you dishonourably: ganked you while you were low level, questing, or fighting a mob."], 1, 1, 1, true)
	GameTooltip:AddLine(ns.L["Scum get their own horn and glow red on the radar."], 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

function ns.ClassColor(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c then return c.r, c.g, c.b end
	return 0.9, 0.9, 0.9
end

-- ===========================================================================
-- Load
-- ===========================================================================

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
	if name ~= ADDON then return end
	ns.InitDB()
	ns.Fire("DB_READY")
	ns.Print(string.format(ns.L["v%s loaded. %d on the list. Click the skull on your minimap for settings."],
		ns.VERSION, ns.List:Count()))
	if not ns.db.introShown then
		ns.db.introShown = true
		ns.Print(ns.L["This does not warn you about every enemy around you -- only players who have killed you and that you chose to add to your list."])
	end
end)
