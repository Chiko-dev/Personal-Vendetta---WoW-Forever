-- Minimal stand-in for the WoW client, enough to drive the addon's logic.
-- Lives outside the addon folder; the addon never sees it in game.

local H = {}
_G.H = H

-- ---------------------------------------------------------------- secrets
local flagged = setmetatable({}, { __mode = "k" })
function _G.issecretvalue(v) return flagged[v] == true end
function H.secret()
	local t = setmetatable({}, { __tostring = function() return "SECRET" end })
	flagged[t] = true
	return t
end

-- ---------------------------------------------------------------- clock
H.now = 1763000000
H.clock = 100.0
function _G.time() return H.now end
function _G.GetTime() return H.clock end

-- ---------------------------------------------------------------- timers
H.timers = {}
_G.C_Timer = {
	After = function(delay, fn)
		table.insert(H.timers, { at = H.clock + (delay or 0), fn = fn })
	end,
	NewTicker = function(interval, fn)
		H.ticker = fn
		return { Cancel = function() H.ticker = nil end }
	end,
}

-- Run every timer due now, repeatedly, so chained callbacks resolve.
function H.runTimers(advance)
	H.clock = H.clock + (advance or 0.1)
	for _ = 1, 30 do
		local due, rest = {}, {}
		for _, t in ipairs(H.timers) do
			if t.at <= H.clock then due[#due + 1] = t else rest[#rest + 1] = t end
		end
		H.timers = rest
		if #due == 0 then break end
		for _, t in ipairs(due) do t.fn() end
	end
end

-- ---------------------------------------------------------------- frames
H.frames = {}

local function newWidget()
	local w = {}
	w.__events = {}
	w.__scripts = {}
	w.__shown = false

	function w:SetScript(name, fn) self.__scripts[name] = fn end
	function w:GetScript(name) return self.__scripts[name] end
	function w:RegisterEvent(e) self.__events[e] = true end
	function w:UnregisterEvent(e) self.__events[e] = nil end
	function w:IsEventRegistered(e) return self.__events[e] == true end
	function w:Show() self.__shown = true end
	function w:Hide() self.__shown = false end
	function w:SetShown(v) self.__shown = not not v end
	function w:IsShown() return self.__shown end
	function w:IsEnabled() return self.__enabled ~= false end
	function w:Enable() self.__enabled = true end
	function w:Disable() self.__enabled = false end
	function w:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
	function w:SetText(t) self.__text = t end
	function w:GetText() return self.__text end
	function w:SetChecked(v) self.__checked = not not v end
	function w:GetChecked() return self.__checked == true end
	function w:SetValue(v)
		self.__value = v
		if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end
	end
	function w:GetValue() return self.__value end
	function w:Click(button)
		if self.__scripts.OnClick then self.__scripts.OnClick(self, button or "LeftButton") end
	end
	function w:CreateFontString() return newWidget() end
	function w:CreateTexture() return newWidget() end
	function w:CreateAnimationGroup() return newWidget() end
	function w:CreateAnimation() return newWidget() end

	-- Template children a real frame might or might not have.
	local DATA_KEYS = { Text = true, NineSlice = true, Thumb = true, Icon = true }

	return setmetatable(w, {
		__index = function(t, k)
			-- Lowercase keys and known child keys are data: absent means nil.
			if type(k) ~= "string" or DATA_KEYS[k] or not string.find(k, "^%u") then
				return nil
			end
			-- Anything else that looks like a method is a no-op method.
			local f = function() end
			t[k] = f
			return f
		end,
	})
end
H.newWidget = newWidget

function _G.CreateFrame(kind, name, parent, template)
	if template and H.missingTemplates and H.missingTemplates[template] then
		error("unknown template " .. template)
	end
	local f = newWidget()
	f.__kind, f.__name, f.__template = kind, name, template
	if template == "UICheckButtonTemplate" or template == "UISliderTemplateWithLabels" then
		f.Text = newWidget()
	end
	table.insert(H.frames, f)
	if name then _G[name] = f end
	return f
end

_G.UIParent = newWidget()

-- Send an event to every frame listening for it.
function H.fire(event, ...)
	for _, f in ipairs(H.frames) do
		if f.__events[event] and f.__scripts.OnEvent then
			f.__scripts.OnEvent(f, event, ...)
		end
	end
end

-- ---------------------------------------------------------------- units
-- H.units["nameplate1"] = { name=, guid=, level=, class=, className=,
--                           race=, isPlayer=, canAttack= }
H.units = {}

local function u(unit) return H.units[unit] end

-- Resolve "nameplate1target", "party2target" etc. to a unit record.
local function resolve(token)
	if H.units[token] then return H.units[token] end
	local base = string.match(token, "^(.+)target$")
	if base then
		local b = resolve(base)
		if b and b.targets then return resolve(b.targets) end
	end
	return nil
end
H.resolve = resolve

function _G.UnitIsUnit(a, b)
	local x, y = resolve(a), resolve(b)
	if not x or not y then return false end
	if H.unitIsUnitSecret then return H.secret() end
	return (x.guid or x.name) == (y.guid or y.name)
end
H.inCombat = false
function _G.UnitAffectingCombat(unit)
	if unit == "player" then return H.inCombat end
	return false
end
function _G.UnitIsEnemy(_, unit) local x = u(unit) ; return x and x.isPlayer ~= false and x.enemy ~= false or false end
function _G.UnitIsDeadOrGhost(unit) local x = u(unit) ; return x and x.dead or false end
H.groupSize = 0
function _G.GetNumGroupMembers() return H.groupSize end

function _G.UnitExists(unit) return u(unit) ~= nil end
function _G.UnitIsPlayer(unit) local x = u(unit) ; return x and x.isPlayer ~= false or false end
-- Like the real client: a corpse cannot be attacked.
function _G.UnitCanAttack(_, unit) local x = u(unit) ; return x and x.canAttack ~= false and not x.dead or false end
function _G.UnitGUID(unit) local x = u(unit) ; return x and x.guid or nil end
-- Forever returns (first name, surname); the realm slot holds the surname.
function _G.UnitName(unit) local x = u(unit) ; if not x then return nil end return x.name, x.surname end
function _G.UnitNameUnmodified(unit) return _G.UnitName(unit) end
_G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
function _G.UnitLevel(unit) local x = u(unit) ; return x and x.level or nil end
function _G.UnitClass(unit) local x = u(unit) ; if not x then return nil end return x.className, x.class end
function _G.UnitRace(unit) local x = u(unit) ; if not x then return nil end return x.race, x.race end
function _G.UnitFactionGroup(unit)
	if unit == "player" then return "Alliance" end
	local x = u(unit) ; return x and (x.faction or "Horde") or nil
end
function _G.UnitIsDead(unit) local x = u(unit) ; return x and x.dead or false end

H.units.player = { name = "Me", guid = "Player-9999-MEMEME", isPlayer = true, canAttack = false }

-- ---------------------------------------------------------------- context
H.instanceType = "none"
function _G.IsInInstance()
	return H.instanceType ~= "none", H.instanceType
end

-- ---------------------------------------------------------------- recap
H.recap = nil
_G.C_DeathRecap = {
	HasRecapEvents = function() return H.recap ~= nil end,
	GetRecapEvents = function() return H.recap end,
	GetRecapMaxHealth = function() return 4200 end,
	GetRecapLink = function() return nil end,
}

-- ---------------------------------------------------------------- misc
_G.RAID_CLASS_COLORS = {
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	ROGUE = { r = 1, g = 0.96, b = 0.41 },
	MAGE = { r = 0.41, g = 0.8, b = 0.94 },
}
_G.SOUNDKIT = { READY_CHECK = 8960, RAID_WARNING = 8959 }
function _G.PlaySound() H.soundsPlayed = (H.soundsPlayed or 0) + 1 ; return true end
H.missingKits = {}
_G.C_Sound = {
	PlaySoundWithOptions = function(p)
		if H.missingKits[p.soundKitID] then return false end
		H.soundsPlayed = (H.soundsPlayed or 0) + 1
		H.lastSound = p
		return true, 1
	end,
}

-- Minimap, cursor, tooltip, escape-to-close list.
_G.Minimap = newWidget()
function Minimap:GetWidth() return 140 end
function Minimap:GetCenter() return 1000, 600 end
function Minimap:GetEffectiveScale() return 1 end
H.cursor = { 1000, 700 }
function _G.GetCursorPosition() return H.cursor[1], H.cursor[2] end
_G.GameTooltip = newWidget()
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
H.cvars = { nameplateMaxDistance = "20", nameplateShowEnemies = "1" }
_G.C_CVar = {
	GetCVar = function(k) return H.cvars[k] end,
	SetCVar = function(k, v)
		-- Pretend the client clamps like TBC-era clients did.
		local n = tonumber(v)
		if k == "nameplateMaxDistance" and n then
			if n > 41 then n = 41 end
			H.cvars[k] = tostring(n)
		else
			H.cvars[k] = tostring(v)
		end
		return true
	end,
}

-- ---------------------------------------------------------------- v1.0
H.lockdown = false
function _G.InCombatLockdown() return H.lockdown end
_G.Settings = {
	NAMEPLATE_OPTIONS_CATEGORY_ID = 42,
	OpenToCategory = function(id) H.openedCategory = id end,
}
H.cvars.nameplateShowAll = "1"

-- ---------------------------------------------------------------- v1.1
H.inGroup, H.inRaidGroup = false, false
function _G.IsInGroup() return H.inGroup end
function _G.IsInRaid() return H.inRaidGroup end
H.sent = {}
H.sendResults = {}   -- queue of results to return; empty means success
_G.C_ChatInfo = {
	RegisterAddonMessagePrefix = function(p) H.prefix = p ; return 0 end,
	SendAddonMessage = function(prefix, msg, channel)
		local res = table.remove(H.sendResults, 1) or 0
		if res == 0 then
			H.sent[#H.sent + 1] = { prefix = prefix, msg = msg, channel = channel }
		end
		return res
	end,
}
function _G.GetBuildInfo() return "1.60.1", "70009", "Nov 2026", 16001 end
_G.date = function(fmt) return "2026-11-15 00:00:00" end

H.output = {}
local realPrint = print
function _G.print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	local line = table.concat(parts, " ")
	table.insert(H.output, line)
	if H.verbose then realPrint(line) end
end

function H.outputContains(needle)
	for _, line in ipairs(H.output) do
		if string.find(line, needle, 1, true) then return true end
	end
	return false
end

function H.clearOutput() H.output = {} end

-- ---------------------------------------------------------------- v1.3 stubs
H.locale = H.locale or "enUS"
_G.GetLocale = function() return H.locale end
H.zone, H.subzone = "Elwynn Forest", "Goldshire"
_G.GetRealZoneText = function() return H.zone end
_G.GetSubZoneText = function() return H.subzone end
H.resting = false
_G.IsResting = function() return H.resting end
_G.C_Map = _G.C_Map or {}
H.areaNames = { [1519] = "Stormwind City", [976] = "Gadgetzan" }
C_Map.GetAreaInfo = function(id) return H.areaNames[id] end
H.mapPos = { 0.4237, 0.6512 }
C_Map.GetBestMapForUnit = function() return 1429 end
C_Map.GetPlayerMapPosition = function()
	if not H.mapPos then return nil end
	return { GetXY = function() return H.mapPos[1], H.mapPos[2] end }
end
H.chat = {}
C_ChatInfo.SendChatMessage = function(msg, chatType) H.chat[#H.chat + 1] = { msg = msg, type = chatType } end
H.plates = {}
_G.C_NamePlate = _G.C_NamePlate or {}
C_NamePlate.GetNamePlateForUnit = function(unit)
	if not H.units[unit] then return nil end
	local p = H.plates[unit]
	if not p then
		p = newWidget()
		p.__forbidden = false
		function p:IsForbidden() return self.__forbidden end
		H.plates[unit] = p
	end
	return p
end

return H
