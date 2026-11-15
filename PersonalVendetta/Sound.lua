--[[-------------------------------------------------------------------------
  Personal Vendetta -- Sound
  The sighting alerts. Two of them: the normal one for anyone on the list,
  and a separate one for scum, so you know by ear which is the must-kill.

  The horns are sound kits Blizzard ships with Forever for its own alert
  picker, so they exist on this client. Volume goes through PlaySound's
  volumeOverride rather than touching your sound settings.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local THROTTLE = 3 -- seconds; three people appearing at once is one horn

local SOUNDS = {
	{ id = "warhorn",    label = "Warhorn",      kit = 316723 },
	{ id = "boathorn",   label = "Boat Horn",    kit = 316442 },
	{ id = "brass",      label = "Brass",        kit = 316722 },
	{ id = "airhorn",    label = "Air Horn",     kit = 316436 },
	{ id = "raidwarn",   label = "Raid Warning", soundkit = "RAID_WARNING" },
	{ id = "readycheck", label = "Ready Check",  soundkit = "READY_CHECK" },
}

-- Which settings each kind of alert reads.
local KINDS = {
	normal = { choice = "choice", volume = "volume" },
	scum   = { choice = "scumChoice", volume = "scumVolume" },
}

local Sound = { list = SOUNDS }
ns.Sound = Sound

local lastPlayed = { normal = 0, scum = 0 }

local function kindOf(kind) return KINDS[kind] and kind or "normal" end

local function find(id)
	for i, s in ipairs(SOUNDS) do
		if s.id == id then return s, i end
	end
	return SOUNDS[1], 1
end

local function kitOf(s)
	if s.kit then return s.kit end
	return SOUNDKIT and SOUNDKIT[s.soundkit] or nil
end

function Sound:Current(kind)
	kind = kindOf(kind)
	local cfg = ns.db and ns.db.settings.sound
	local id = cfg and cfg[KINDS[kind].choice] or "warhorn"
	return find(id)
end

-- Step through the list: dir is +1 or -1. Returns the new sound.
function Sound:Cycle(kind, dir)
	kind = kindOf(kind)
	local _, i = self:Current(kind)
	i = ((i - 1 + dir) % #SOUNDS) + 1
	ns.db.settings.sound[KINDS[kind].choice] = SOUNDS[i].id
	return SOUNDS[i]
end

function Sound:Volume(kind)
	kind = kindOf(kind)
	local v = ns.db.settings.sound[KINDS[kind].volume]
	return math.max(0, math.min(1, v or 0.6))
end

function Sound:SetVolume(kind, v)
	kind = kindOf(kind)
	ns.db.settings.sound[KINDS[kind].volume] = math.max(0, math.min(1, v))
end

-- Returns true if something was actually played.
local function playKit(kit, volume)
	if not kit then return false end

	-- Preferred: honours the volume slider. If it answers at all, its answer
	-- is final: a false means this kit is not on the client, and the old
	-- PlaySound below would only replay it at full volume, ignoring the
	-- slider. Let the caller fall back to another sound instead.
	if C_Sound and C_Sound.PlaySoundWithOptions then
		local ok, success = pcall(C_Sound.PlaySoundWithOptions, {
			soundKitID = kit,
			volumeOverride = volume,
		})
		if ok then return success and true or false end
	end

	-- Only if the volume-aware call is missing or broken: plays, but at the
	-- game's own SFX volume.
	if PlaySound then
		local ok, success = pcall(PlaySound, kit, "SFX")
		if ok and success ~= false then return true end
	end
	return false
end

-- Play an alert. kind is "normal" or "scum". force ignores the on/off
-- switch and the throttle, for the Test buttons.
function Sound:Play(kind, force)
	kind = kindOf(kind)
	local cfg = ns.db.settings.sound
	if not force then
		if not cfg.enabled then return false end
		-- Scum is never drowned out by a normal horn a second ago.
		if (GetTime() - lastPlayed[kind]) < THROTTLE then return false end
	end

	local volume = self:Volume(kind)
	if volume <= 0 then return false end

	local s = self:Current(kind)
	local played = playKit(kitOf(s), volume)
	if not played and s.id ~= "readycheck" then
		-- The chosen kit is missing on this build: fall back to something
		-- that always exists rather than staying silent.
		played = playKit(SOUNDKIT and SOUNDKIT.READY_CHECK, volume)
	end

	if played then
		lastPlayed[kind] = GetTime()
		-- A scum horn covers the normal one too: no second horn right after.
		if kind == "scum" then lastPlayed.normal = GetTime() end
	end
	return played
end
