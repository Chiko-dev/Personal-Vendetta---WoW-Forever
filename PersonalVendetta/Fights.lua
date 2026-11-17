--[[-------------------------------------------------------------------------
  Personal Vendetta -- Fights
  For the ones who came for you and lost. While you are in combat, any enemy
  player of the other faction who has you targeted is remembered. When the
  fight ends and you are still standing, in the open world, the ones not on
  your list yet are offered in the same prompt as after a death.

  The client cannot say who started a fight, so anyone who had you
  targeted counts. Skip them and they will not be offered again for a while.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local SCAN_INTERVAL = 0.5
local SKIP_MEMORY = 30 * 60   -- a skipped player is not offered again for 30 min
local MAX_PLATES = 40

local Fights = {}
ns.Fights = Fights

local foes = {}     -- foeKey -> { info, dead, firstAt, lastAt }
local skipped = {}  -- foeKey -> time skipped
local ticker

local function readBool(fn, ...)
	local ok, v = ns.try(fn, ...)
	if not ok or not ns.usable(v) then return nil end
	return v and true or false
end

local function foeKey(info)
	if info.guid then return info.guid end
	if info.name then return "name:" .. string.lower(ns.FullName(info.name, info.surname)) end
	return nil
end
Fights.KeyOf = foeKey

-- Only the other faction. A same-faction duel opponent is attackable too,
-- and a duel is not a vendetta.
local function otherFaction(unit)
	local okA, mine = ns.try(UnitFactionGroup, "player")
	local okB, theirs = ns.try(UnitFactionGroup, unit)
	mine, theirs = okA and ns.str(mine), okB and ns.str(theirs)
	if not mine or not theirs then return true end -- unreadable: do not block
	return mine ~= theirs
end

-- ===========================================================================
-- During the fight
-- ===========================================================================

local function consider(unit)
	if not ns.Radar.IsEnemyPlayer(unit) then return end
	if not otherFaction(unit) then return end

	local info = ns.Radar:ReadUnitInfo(unit)
	local k = foeKey(info)
	if not k then return end

	local dead = ns.Radar.IsDead(unit)
	local rec = foes[k]
	if not rec then
		-- They join the fight by having you targeted while alive.
		if dead then return end
		if not readBool(UnitIsUnit, unit .. "target", "player") then return end
		rec = { info = {}, firstAt = time() }
		foes[k] = rec
	end

	-- Keep the freshest readable details.
	for field, v in pairs(info) do rec.info[field] = v end
	if dead then rec.dead = true end
	rec.lastAt = time()
end

local function scan()
	if not ns.db or not ns.Radar then return end
	if not ns.InTrackedZone() then return end
	for i = 1, MAX_PLATES do consider("nameplate" .. i) end
	consider("target")
	consider("mouseover")
end

-- ===========================================================================
-- After the fight
-- ===========================================================================

local function offer()
	local found = foes
	foes = {}

	if not ns.db or not ns.db.settings.promptAfterFight then return end
	if ns.Radar.IsDead("player") then return end -- the death prompt has this one
	if not ns.InTrackedZone() then return end

	local now = time()
	local candidates = {}
	for k, rec in pairs(found) do
		local info = rec.info
		local _, onList = ns.List:Find(info.guid, info.name, info.surname)
		local skippedAt = skipped[k]
		local recentlySkipped = skippedAt and (now - skippedAt) < SKIP_MEMORY
		if not onList and not recentlySkipped and (info.guid or info.name) then
			candidates[#candidates + 1] = {
				key = k,
				guid = info.guid,
				name = info.name,
				surname = info.surname,
				level = info.level,
				levelSkull = info.levelSkull,
				class = info.class,
				className = info.className,
				race = info.race,
				killedByMe = rec.dead and true or false,
				certain = true,
			}
		end
	end

	if #candidates > 0 then
		-- The ones you dropped first, then by name.
		table.sort(candidates, function(a, b)
			if a.killedByMe ~= b.killedByMe then return a.killedByMe end
			return ns.FullName(a.name, a.surname) < ns.FullName(b.name, b.surname)
		end)
		ns.Fire("OFFER_CANDIDATES", candidates, "fight")
	end
end

-- The prompt calls this for each fight candidate you skip or close on.
function Fights:Remember(candidate)
	local k = candidate and (candidate.key or foeKey(candidate))
	if k then skipped[k] = time() end
end

-- ===========================================================================
-- Events
-- ===========================================================================

local function startTracking()
	foes = {}
	if ticker then ticker:Cancel() end
	ticker = C_Timer.NewTicker(SCAN_INTERVAL, scan)
	scan()
end

local function stopTracking()
	if ticker then ticker:Cancel() ; ticker = nil end
	scan() -- one last look: someone may have just dropped
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("PLAYER_DEAD")
f:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_REGEN_DISABLED" then
		startTracking()
	elseif event == "PLAYER_REGEN_ENABLED" then
		stopTracking()
		-- A moment's grace so a death that ended the fight is seen as one.
		C_Timer.After(0.5, offer)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		-- Someone dropping takes their nameplate with them: check on the way out.
		if ticker and type(unit) == "string" then consider(unit) end
	elseif event == "PLAYER_DEAD" then
		foes = {}
	end
end)

-- Test hooks.
Fights._foes = function() return foes end
Fights._scan = scan
Fights._offer = offer
