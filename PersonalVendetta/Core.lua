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

ns.VERSION = "1.0"
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
	nameIndex = {},   -- lowercased name -> key
	settings = {
		promptOnDeath = true,
		announceRepeat = true,
		overlayShown = true,
		overlayPoint = nil,
		sound = {
			enabled = true,
			choice = "warhorn",
			volume = 0.6,       -- 0..1, applied through PlaySound's volumeOverride
			scumChoice = "airhorn",
			scumVolume = 0.6,   -- scum gets its own sound and its own level
		},
		minimap = {
			angle = 215,    -- degrees around the minimap rim; always shown
		},
	},
	lastRecapSig = nil,
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

	ns.db = db
	return ns.db
end

-- ===========================================================================
-- The hit list
-- ===========================================================================

local List = {}
ns.List = List

-- GUID is the durable identity; a name is the fallback when the GUID is
-- secret or missing, and the bridge for /target, which only speaks names.
local function keyFor(guid, name)
	local g = ns.str(guid)
	if g and string.find(g, "^Player%-") then return g end
	local n = ns.str(name)
	if n then return "name:" .. string.lower(n) end
	return nil
end
ns.keyFor = keyFor

-- Find an existing entry by either identity, so a name-keyed entry gets
-- upgraded to its GUID the first time we see one.
function List:Find(guid, name)
	local db = ns.db
	local g = ns.str(guid)
	if g and db.list[g] then return g, db.list[g] end

	local n = ns.str(name)
	if n then
		local mapped = db.nameIndex[string.lower(n)]
		if mapped and db.list[mapped] then return mapped, db.list[mapped] end
		local nameKey = "name:" .. string.lower(n)
		if db.list[nameKey] then return nameKey, db.list[nameKey] end
	end
	return nil, nil
end

function List:Count()
	local n = 0
	for _ in pairs(ns.db.list) do n = n + 1 end
	return n
end

-- Create or update an entry. info may carry name, realm, guid, level,
-- class, className, race.
function List:Upsert(info)
	local db = ns.db
	local guid = ns.str(info.guid)
	local name = ns.str(info.name)
	if not guid and not name then return nil, nil end

	local key, entry = self:Find(guid, name)

	-- Promote a name-keyed entry to its real GUID once we learn it.
	if key and guid and string.find(key, "^name:") then
		db.list[guid] = entry
		db.list[key] = nil
		key = guid
	end

	if not key then
		key = keyFor(guid, name)
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
	entry.name = name or entry.name
	entry.realm = ns.str(info.realm) or entry.realm
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
	end
	entry.class = ns.str(info.class) or entry.class
	entry.className = ns.str(info.className) or entry.className
	entry.race = ns.str(info.race) or entry.race

	if entry.name then
		db.nameIndex[string.lower(entry.name)] = key
	end

	return key, entry
end

function List:Remove(guid, name)
	local key, entry = self:Find(guid, name)
	if not key then return false end
	if entry and entry.name then
		ns.db.nameIndex[string.lower(entry.name)] = nil
	end
	ns.db.list[key] = nil
	ns.Fire("LIST_CHANGED")
	return true
end

function List:Wipe()
	ns.db.list = {}
	ns.db.nameIndex = {}
	ns.Fire("LIST_CHANGED")
end

function List:RecordTheirKill(info)
	local key, entry = self:Upsert(info)
	if not entry then return nil end
	entry.theyKilledMe = (entry.theyKilledMe or 0) + 1
	entry.lastKilledMe = time()
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
	local key, entry = self:Find(ns.str(info.guid), ns.str(info.name))
	if not entry then return nil, false end

	local now = time()
	if not force and entry.lastIKilledThem and (now - entry.lastIKilledThem) < KILL_DEDUPE then
		return entry, false
	end

	entry.iKilledThem = (entry.iKilledThem or 0) + 1
	entry.lastIKilledThem = now
	ns.Fire("LIST_CHANGED")
	return entry, true
end

-- Scum: killed you dishonourably. A must-kill on sight.
function List:SetScum(key, isScum)
	local entry = key and ns.db.list[key]
	if not entry then return nil end
	entry.scum = isScum and true or nil
	ns.Fire("LIST_CHANGED")
	return entry
end

function List:Adjust(name, field, delta)
	local key, entry = self:Find(nil, name)
	if not entry then return nil end
	entry[field] = math.max(0, (entry[field] or 0) + delta)
	ns.Fire("LIST_CHANGED")
	return entry
end

-- Entries sorted worst-offender first, for display.
function List:Sorted()
	local t = {}
	for key, entry in pairs(ns.db.list) do
		entry.key = key
		t[#t + 1] = entry
	end
	table.sort(t, function(a, b)
		local ak, bk = a.theyKilledMe or 0, b.theyKilledMe or 0
		if ak ~= bk then return ak > bk end
		return (a.name or "") < (b.name or "")
	end)
	return t
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
	GameTooltip:AddLine(ns.SCUM_COLOR .. "Scum|r")
	GameTooltip:AddLine("Killed you dishonourably: ganked you while you were\nlow level, questing, or fighting a mob.", 1, 1, 1, true)
	GameTooltip:AddLine("Scum get their own horn and glow red on the radar.", 0.8, 0.8, 0.8, true)
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
	ns.Print("v" .. ns.VERSION .. " loaded. " .. ns.List:Count()
		.. " on the list. Click the skull on your minimap for settings.")
	if not ns.db.introShown then
		ns.db.introShown = true
		ns.Print("This does not warn you about every enemy around you -- only players "
			.. "who have killed you and that you chose to add to your list.")
	end
end)
