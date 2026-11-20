-- Drives Personal Vendetta's logic through the stub client.
-- Usage: cd tests && lua run.lua   (the addon is at ../PersonalVendetta)

-- Lua 5.1 (what WoW runs) only loads strings through loadstring.
local load = loadstring or load

local ADDON_DIR = "../PersonalVendetta/"
-- Same order as the .toc.
local FILES = {}
do
	local f = assert(io.open(ADDON_DIR .. "PersonalVendetta.toc", "r"))
	for line in f:lines() do
		local file = string.match(line, "^%s*([%w_\\]+%.lua)%s*$")
		if file then FILES[#FILES + 1] = (string.gsub(file, "\\", "/")) end
	end
	f:close()
end

-- Grab the real print before the harness replaces it with the in-game stub.
local say = function(s) io.write(tostring(s), "\n") end

dofile("harness.lua")
local H = _G.H

local ns = {}
local function loadAddon()
	for _, file in ipairs(FILES) do
		local f = assert(io.open(ADDON_DIR .. file, "r"))
		local src = f:read("*a")
		f:close()
		local chunk = assert(load(src, file))
		chunk("PersonalVendetta", ns)
	end
end

-- ---------------------------------------------------------------- test kit
local passed, failed = 0, 0
local function check(label, cond, detail)
	if cond then
		passed = passed + 1
		say(string.format("  ok    %s", label))
	else
		failed = failed + 1
		say(string.format("  FAIL  %s%s", label, detail and ("  -- " .. tostring(detail)) or ""))
	end
end
local function section(name) say("\n" .. name) end

-- Candidates handed to the prompt, captured instead of drawn.
local offered = {}

-- ---------------------------------------------------------------- go
loadAddon()
ns.On("OFFER_CANDIDATES", function(c)
	offered = c
end)

section("Load")
H.fire("ADDON_LOADED", "PersonalVendetta")
check("db initialised", ns.db ~= nil)
check("list starts empty", ns.List:Count() == 0, ns.List:Count())
check("startup message printed", H.outputContains("loaded"))

-- ---------------------------------------------------------------------------
section("Death to a single enemy player")
H.recap = {
	{ sourceName = "Pumpdaddy", sourceGUID = "Player-4710-0001AAAA",
	  spellName = "Mortal Strike", spellId = 12294, amount = 900, overkill = 120,
	  event = "SPELL_DAMAGE", timestamp = H.now },
	{ sourceName = "Pumpdaddy", sourceGUID = "Player-4710-0001AAAA",
	  spellName = "Melee", spellId = 0, amount = 300, overkill = -1,
	  event = "SWING_DAMAGE", timestamp = H.now },
}
offered = {}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("one candidate offered", #offered == 1, #offered)
check("name read from recap", offered[1] and offered[1].name == "Pumpdaddy", offered[1] and offered[1].name)
check("killing blow flagged", offered[1] and offered[1].killingBlow == true)
check("confirmed as a player", offered[1] and offered[1].certain == true)
check("nothing added without a click", ns.List:Count() == 0)

-- The player clicks Add.
local entry = ns.List:RecordTheirKill(offered[1])
check("added on click", ns.List:Count() == 1)
check("death counted", entry.theyKilledMe == 1, entry.theyKilledMe)
check("keyed on guid", entry.key == "Player-4710-0001AAAA", entry.key)

-- ---------------------------------------------------------------------------
section("Same recap must not be counted twice")
offered = {}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("no second prompt", #offered == 0, #offered)
check("counter unchanged", entry.theyKilledMe == 1, entry.theyKilledMe)

-- ---------------------------------------------------------------------------
section("Killed again by someone already on the list")
H.now = H.now + 300
H.clearOutput()
H.recap = {
	{ sourceName = "Pumpdaddy", sourceGUID = "Player-4710-0001AAAA",
	  spellName = "Execute", spellId = 5308, amount = 1200, overkill = 400,
	  event = "SPELL_DAMAGE", timestamp = H.now },
}
offered = {}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("no prompt for a known name", #offered == 0, #offered)
check("counter incremented silently", entry.theyKilledMe == 2, entry.theyKilledMe)
check("repeat announced in chat", H.outputContains("got you again"))

-- ---------------------------------------------------------------------------
section("Gank: three attackers, one of them a pet and one a mob")
H.now = H.now + 300
H.recap = {
	{ sourceName = "Sneakyboi", sourceGUID = "Player-4710-0002BBBB",
	  spellName = "Ambush", spellId = 8676, amount = 1100, overkill = 200,
	  event = "SPELL_DAMAGE", timestamp = H.now },
	{ sourceName = "Hexxer", sourceGUID = "Player-4710-0003CCCC",
	  spellName = "Shadow Bolt", spellId = 686, amount = 400, overkill = -1,
	  event = "SPELL_DAMAGE", timestamp = H.now },
	{ sourceName = "Voidwalker", sourceGUID = "Pet-0-4710-0-0-416-0000AAAA",
	  spellName = "Torment", spellId = 3716, amount = 80, overkill = -1,
	  event = "SPELL_DAMAGE", timestamp = H.now },
	{ sourceName = "Mangy Wolf", sourceGUID = "Creature-0-4710-0-0-299-0000BBBB",
	  spellName = "Bite", spellId = 0, amount = 40, overkill = -1,
	  event = "SPELL_DAMAGE", timestamp = H.now },
}
offered = {}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("two player candidates", #offered == 2, #offered)
local names = {}
for _, c in ipairs(offered) do names[c.name] = true end
check("rogue offered", names["Sneakyboi"] == true)
check("warlock offered", names["Hexxer"] == true)
check("pet not offered", names["Voidwalker"] == nil)
check("mob not offered", names["Mangy Wolf"] == nil)

-- Add only the rogue; the warlock gets a pass.
ns.List:RecordTheirKill(offered[1].name == "Sneakyboi" and offered[1] or offered[2])
check("only the chosen one added", ns.List:Count() == 2, ns.List:Count())

-- ---------------------------------------------------------------------------
section("Death with no player involved")
H.now = H.now + 300
H.recap = {
	{ sourceName = "Mangy Wolf", sourceGUID = "Creature-0-4710-0-0-299-0000BBBB",
	  spellName = "Bite", spellId = 0, amount = 400, overkill = 50,
	  event = "SPELL_DAMAGE", timestamp = H.now },
}
offered = {}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("no prompt for a mob death", #offered == 0, #offered)

-- ---------------------------------------------------------------------------
section("Arenas and battlegrounds are out of scope")
H.now = H.now + 300
H.instanceType = "arena"
H.recap = {
	{ sourceName = "Arenagod", sourceGUID = "Player-4710-0009ZZZZ",
	  spellName = "Kidney Shot", spellId = 408, amount = 999, overkill = 99,
	  event = "SPELL_DAMAGE", timestamp = H.now },
}
offered = {}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("no prompt in an arena", #offered == 0, #offered)
H.instanceType = "pvp"
offered = {}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("no prompt in a battleground", #offered == 0, #offered)
H.instanceType = "none"

-- ---------------------------------------------------------------------------
section("Radar: spotting someone from the list")
H.units["nameplate1"] = {
	name = "Pumpdaddy", guid = "Player-4710-0001AAAA", level = 47,
	class = "WARRIOR", className = "Warrior", race = "Orc",
	isPlayer = true, canAttack = true,
}
H.units["nameplate2"] = {
	name = "Randomguy", guid = "Player-4710-00FFFFFF", level = 31,
	class = "MAGE", className = "Mage", race = "Troll",
	isPlayer = true, canAttack = true,
}
H.soundsPlayed = 0
H.clearOutput()
ns.Radar.Sweep()
check("one target nearby", ns.Radar:Count() == 1, ns.Radar:Count())
check("stranger ignored", ns.Radar.nearby["Player-4710-00FFFFFF"] == nil)
check("level cached", entry.level == 47, entry.level)
check("class cached", entry.class == "WARRIOR", entry.class)
check("race cached", entry.race == "Orc", entry.race)
check("sighting announced", H.outputContains("is near"))
check("sound played", (H.soundsPlayed or 0) > 0, H.soundsPlayed)

-- A second sweep must not re-alert for the same person.
H.clearOutput()
H.soundsPlayed = 0
ns.Radar.Sweep()
check("no repeat alert while still in range", not H.outputContains("is near"))
check("still tracked", ns.Radar:Count() == 1)

-- Walk away.
H.units["nameplate1"] = nil
H.clock = H.clock + 5
ns.Radar.Sweep()
check("dropped after leaving range", ns.Radar:Count() == 0, ns.Radar:Count())

-- ---------------------------------------------------------------------------
section("Radar: secret name, readable guid")
H.units["nameplate1"] = {
	name = H.secret(), guid = "Player-4710-0001AAAA", level = H.secret(),
	class = "WARRIOR", className = "Warrior", race = "Orc",
	isPlayer = true, canAttack = true,
}
H.clock = H.clock + 5
ns.Radar.Sweep()
check("matched by guid despite secret name", ns.Radar:Count() == 1, ns.Radar:Count())
check("secret name did not overwrite stored name", entry.name == "Pumpdaddy", entry.name)
check("secret level did not overwrite stored level", entry.level == 47, entry.level)

-- ---------------------------------------------------------------------------
section("Radar: secret guid, readable name")
H.units["nameplate1"] = {
	name = "Pumpdaddy", guid = H.secret(), level = 48,
	class = "WARRIOR", className = "Warrior", race = "Orc",
	isPlayer = true, canAttack = true,
}
H.clock = H.clock + 5
ns.Radar.Sweep()
check("matched by name despite secret guid", ns.Radar:Count() == 1, ns.Radar:Count())
check("level updated from a readable value", entry.level == 48, entry.level)

-- ---------------------------------------------------------------------------
section("Manual add gets upgraded to a guid on sight")
ns.List:Upsert({ name = "Latecomer" })
local _, late = ns.List:Find(nil, "Latecomer")
check("name-keyed on manual add", late.key == "name:latecomer", late.key)
H.units["nameplate3"] = {
	name = "Latecomer", guid = "Player-4710-000ABCDE", level = 60,
	class = "ROGUE", className = "Rogue", race = "Undead",
	isPlayer = true, canAttack = true,
}
H.clock = H.clock + 5
ns.Radar.Sweep()
local _, lateAfter = ns.List:Find("Player-4710-000ABCDE", nil)
check("promoted to guid key", lateAfter ~= nil and lateAfter.key == "Player-4710-000ABCDE",
	lateAfter and lateAfter.key)
check("history survived the promotion", lateAfter == late)
check("no duplicate entry created", ns.db.list["name:latecomer"] == nil)

-- ---------------------------------------------------------------------------
section("Kill counter and removal")
ns.List:RecordMyKill({ guid = "Player-4710-0001AAAA" })
check("my kill counted", entry.iKilledThem == 1, entry.iKilledThem)
local before = ns.List:Count()
check("removal by name works", ns.List:Remove(nil, "Latecomer") == true)
check("count dropped", ns.List:Count() == before - 1)
check("removed player no longer found by name", select(2, ns.List:Find(nil, "Latecomer")) == nil)

-- ---------------------------------------------------------------------------
section("Nameplate range")
local got = ns.Radar:SetRange(41)
check("range set to 41", got == "41", got)
got = ns.Radar:SetRange(100)
check("client clamp respected", got == "41", got)

-- ===========================================================================
-- v0.5
-- ===========================================================================

-- A clean slate for the kill tests.
local function resetWorld()
	for k in pairs(H.units) do
		if k ~= "player" then H.units[k] = nil end
	end
	for k in pairs(ns.Radar.nearby) do ns.Radar.nearby[k] = nil end
	for k in pairs(ns.Kills._engaged) do ns.Kills._engaged[k] = nil end
	for k in pairs(ns.Kills._recentDeaths) do ns.Kills._recentDeaths[k] = nil end
	H.inCombat = false
	H.groupSize = 0
	H.clock = H.clock + 10
	H.now = H.now + 100 -- clear of the kill dedupe window
	ns.Radar.Sweep()
end

local function warrior(extra)
	local t = {
		name = "Pumpdaddy", guid = "Player-4710-0001AAAA", level = 47,
		class = "WARRIOR", className = "Warrior", race = "Orc",
		isPlayer = true, canAttack = true,
	}
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

local function step(seconds)
	H.clock = H.clock + (seconds or 0.4)
	H.now = H.now + 1
	ns.Radar.Sweep()
	H.runTimers(0)
end

-- ---------------------------------------------------------------------------
section("Kill: you were hitting your target and it died")
resetWorld()
local kills0 = entry.iKilledThem
H.units["nameplate1"] = warrior()
H.units["target"] = H.units["nameplate1"]
H.inCombat = true
step()
check("engaged while targeting them in combat", ns.Kills:IsEngaged(entry.key))
H.units["nameplate1"].dead = true
H.clearOutput()
step()
check("kill counted", entry.iKilledThem == kills0 + 1, entry.iKilledThem)
check("says how it was detected", H.outputContains("saw them drop"))
check("shown as dead in the radar", ns.Radar:Get(entry.key) and ns.Radar:Get(entry.key).dead == true)
check("dead do not count as near", ns.Radar:Count() == 0, ns.Radar:Count())

-- ---------------------------------------------------------------------------
section("Kill: someone else got the killing blow, he had you targeted")
resetWorld()
kills0 = entry.iKilledThem
H.units["nameplate1"] = warrior({ targets = "player" })
H.inCombat = true
step()
check("engaged because he was on you", ns.Kills:IsEngaged(entry.key))
H.units["nameplate1"].dead = true
step()
check("kill counted without a killing blow", entry.iKilledThem == kills0 + 1, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Kill: he was on your party member, you were fighting too")
resetWorld()
kills0 = entry.iKilledThem
H.groupSize = 2
H.units["party1"] = { name = "Buddy", guid = "Player-4710-00BUDDY1", isPlayer = true, canAttack = false }
H.units["nameplate1"] = warrior({ targets = "party1" })
H.inCombat = true
step()
check("engaged through the group", ns.Kills:IsEngaged(entry.key))
H.units["nameplate1"].dead = true
step()
check("group kill counted", entry.iKilledThem == kills0 + 1, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Kill: no contact seen, but the honor system credits you")
resetWorld()
kills0 = entry.iKilledThem
H.units["nameplate1"] = warrior()
H.inCombat = true
step()
check("not engaged on sight alone", not ns.Kills:IsEngaged(entry.key))
H.units["nameplate1"].dead = true
step()
check("no credit for merely watching", entry.iKilledThem == kills0, entry.iKilledThem)
H.fire("PLAYER_PVP_KILLS_CHANGED", "player")
check("HK tick credits the death we watched", entry.iKilledThem == kills0 + 1, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Kill: readable honor message, nobody seen")
resetWorld()
kills0 = entry.iKilledThem
H.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Pumpdaddy dies, honorable kill Rank: Scout (Estimated Honor Points: 14)")
check("honor message alone counts", entry.iKilledThem == kills0 + 1, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Kill: three signals for one kill count once")
resetWorld()
kills0 = entry.iKilledThem
H.units["nameplate1"] = warrior()
H.units["target"] = H.units["nameplate1"]
H.inCombat = true
step()
H.units["nameplate1"].dead = true
step()
H.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Pumpdaddy dies, honorable kill Rank: Scout (Estimated Honor Points: 14)")
H.fire("PLAYER_PVP_KILLS_CHANGED", "player")
check("counted exactly once", entry.iKilledThem == kills0 + 1, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Kill: secret honor message is ignored safely")
resetWorld()
kills0 = entry.iKilledThem
local okSecret = pcall(H.fire, "CHAT_MSG_COMBAT_HONOR_GAIN", H.secret())
check("no error on a secret message", okSecret)
check("no phantom kill", entry.iKilledThem == kills0, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Kill: two deaths, ambiguous HK tick credits nobody")
resetWorld()
local _, rogue = ns.List:Find(nil, "Sneakyboi")
local rogueKills0 = rogue.iKilledThem or 0
kills0 = entry.iKilledThem
H.units["nameplate1"] = warrior()
H.units["nameplate2"] = { name = "Sneakyboi", guid = "Player-4710-0002BBBB", level = 50,
	class = "ROGUE", className = "Rogue", race = "Undead", isPlayer = true, canAttack = true }
step()
H.units["nameplate1"].dead = true
H.units["nameplate2"].dead = true
step()
H.fire("PLAYER_PVP_KILLS_CHANGED", "player")
check("warrior not guessed", entry.iKilledThem == kills0, entry.iKilledThem)
check("rogue not guessed", (rogue.iKilledThem or 0) == rogueKills0, rogue.iKilledThem)

-- ---------------------------------------------------------------------------
section("Kill: corpse no longer reads as hostile")
resetWorld()
kills0 = entry.iKilledThem
H.units["nameplate1"] = warrior()
H.units["target"] = H.units["nameplate1"]
H.inCombat = true
step()
H.units["nameplate1"].dead = true
H.units["nameplate1"].enemy = false -- the client stops calling the corpse an enemy
step()
check("death still seen, kill counted", entry.iKilledThem == kills0 + 1, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Corpse walk-up")
resetWorld()
kills0 = entry.iKilledThem
H.soundsPlayed = 0
H.clearOutput()
H.units["nameplate1"] = warrior({ dead = true })
H.inCombat = true
H.units["target"] = H.units["nameplate1"]
step()
check("a corpse is still recognised", ns.Radar:Get(entry.key) ~= nil)
check("no horn for a corpse", H.soundsPlayed == 0, H.soundsPlayed)
check("no kill for a corpse", entry.iKilledThem == kills0, entry.iKilledThem)

-- ---------------------------------------------------------------------------
section("Levels stay honest")
resetWorld()
H.units["nameplate1"] = warrior({ level = 52 })
step()
local rec = ns.Radar:Get(entry.key)
check("level updates on sight", entry.level == 52, entry.level)
check("fresh level shown in white", ns.LevelText(entry, rec) == "|cffffffff52|r ", ns.LevelText(entry, rec))

H.units["nameplate1"].level = -1
step()
rec = ns.Radar:Get(entry.key)
check("?? stored when they out-level you", entry.levelSkull == true)
check("?? shown in red, not the old 52", ns.LevelText(entry, rec) == "|cffff3333??|r ", ns.LevelText(entry, rec))

H.units["nameplate1"].level = 53
step()
rec = ns.Radar:Get(entry.key)
check("skull cleared once readable again", entry.levelSkull == nil and entry.level == 53)

H.units["nameplate1"].level = H.secret()
step()
rec = ns.Radar:Get(entry.key)
check("secret level keeps the old number", entry.level == 53, entry.level)
check("but flags it as not fresh", ns.LevelText(entry, rec) == "|cff88888853?|r ", ns.LevelText(entry, rec))

-- ---------------------------------------------------------------------------
section("Horn")
local snd = ns.db.settings.sound
snd.enabled, snd.choice, snd.volume = true, "warhorn", 0.6
H.soundsPlayed = 0
H.clock = H.clock + 10
check("plays", ns.Sound:Play("normal") == true)
check("uses the warhorn kit", H.lastSound and H.lastSound.soundKitID == 316723, H.lastSound and H.lastSound.soundKitID)
check("passes the volume", H.lastSound and H.lastSound.volumeOverride == 0.6, H.lastSound and H.lastSound.volumeOverride)
check("throttled straight after", ns.Sound:Play("normal") == false)
check("Test button ignores the throttle", ns.Sound:Play("normal", true) == true)
snd.volume = 0
H.clock = H.clock + 10
check("volume 0 is silent", ns.Sound:Play("normal") == false)
snd.volume = 0.3
snd.enabled = false
H.clock = H.clock + 10
check("off means off", ns.Sound:Play("normal") == false)
check("Test still works when off", ns.Sound:Play("normal", true) == true)
snd.enabled = true
ns.Sound:Cycle("normal", 1)
check("cycle moves to the next horn", snd.choice == "boathorn", snd.choice)
ns.Sound:Cycle("normal", -1)
ns.Sound:Cycle("normal", -1)
check("cycle wraps around", snd.choice == "readycheck", snd.choice)
snd.choice = "warhorn"
H.missingKits[316723] = true
H.clock = H.clock + 10
check("falls back if the horn is missing", ns.Sound:Play("normal") == true and H.lastSound.soundKitID == 8960,
	H.lastSound and H.lastSound.soundKitID)
H.missingKits[316723] = nil

-- ---------------------------------------------------------------------------
section("Settings panel and minimap button")
local okSettings, errSettings = pcall(function() ns.Settings:Toggle(true) end)
check("settings panel builds", okSettings, errSettings)
check("settings panel shown", _G.PersonalVendettaSettings and _G.PersonalVendettaSettings:IsShown())
check("escape closes it", (function()
	for _, n in ipairs(UISpecialFrames) do if n == "PersonalVendettaSettings" then return true end end
	return false
end)())
check("minimap button built on load", _G.PersonalVendettaMinimapButton ~= nil)
check("minimap button always shown", _G.PersonalVendettaMinimapButton:IsShown())
check("no hide option exposed", ns.Minimap.SetShown == nil)

local wasShown = ns.db.settings.overlayShown
_G.PersonalVendettaMinimapButton:Click("RightButton")
check("right-click toggles the window", ns.db.settings.overlayShown == not wasShown)
_G.PersonalVendettaMinimapButton:Click("RightButton")
check("and back", ns.db.settings.overlayShown == wasShown)
_G.PersonalVendettaSettings:Hide()
_G.PersonalVendettaMinimapButton:Click("LeftButton")
check("left-click opens settings", _G.PersonalVendettaSettings:IsShown())

check("compartment handler is global", type(PersonalVendetta_OnAddonCompartmentClick) == "function")

-- Panel survives every template being missing.
H.missingTemplates = { UICheckButtonTemplate = true, UISliderTemplate = true,
	UIPanelButtonTemplate = true, UIPanelCloseButton = true }
do
	local fresh = setmetatable({}, { __index = ns })
	local fh = assert(io.open(ADDON_DIR .. "Settings.lua"))
	local src = fh:read("*a")
	fh:close()
	local chunk = assert(load(src, "Settings.lua"))
	chunk("PersonalVendetta", fresh)
	local ok, err = pcall(function() fresh.Settings:Toggle(true) end)
	check("panel builds with no templates at all", ok, err)
end
H.missingTemplates = nil

-- ---------------------------------------------------------------------------
section("Old settings migrate")
PersonalVendettaDB.settings.sound = nil
PersonalVendettaDB.settings.soundOnSighting = false
ns.InitDB()
check("old sound-off carried over", ns.db.settings.sound.enabled == false)
check("old key removed", ns.db.settings.soundOnSighting == nil)
ns.db.settings.sound.enabled = true

-- ---------------------------------------------------------------------------
section("Commands")
check("there is no popup window any more", _G.PersonalVendettaPrompt == nil)
local before = entry.iKilledThem
SlashCmdList.PERSONALVENDETTA("kill Pumpdaddy")
check("/vendetta kill adds one", entry.iKilledThem == before + 1)
SlashCmdList.PERSONALVENDETTA("unkill Pumpdaddy")
check("/vendetta unkill takes it back", entry.iKilledThem == before)
check("/vendetta debug runs", (pcall(SlashCmdList.PERSONALVENDETTA, "debug")))
check("/vendetta help runs", (pcall(SlashCmdList.PERSONALVENDETTA, "help")))
check("/vendetta list runs", (pcall(SlashCmdList.PERSONALVENDETTA, "list")))
check("/vendetta options runs", (pcall(SlashCmdList.PERSONALVENDETTA, "options")))

-- ===========================================================================
-- v1.0
-- ===========================================================================

-- The To add queue replaced the popup (1.2). Helpers for the tests below.
local function clearQueue()
	local q = ns.db.pending or {}
	for i = #q, 1, -1 do q[i] = nil end
	ns.Fire("PENDING_CHANGED")
end
local function queueText()
	local out = {}
	for _, it in ipairs(ns.Pending:List()) do
		out[#out + 1] = table.concat({ ns.FullName(it.name, it.surname), tostring(it.level or ""),
			it.className or "", ns.Pending:Describe(it) }, " ")
	end
	return table.concat(out, " | ")
end
-- The floating window's To add row showing this player.
local function addRowFor(name)
	ns.Overlay.Toggle(true)
	ns.Overlay.SelectTab("add")
	for _, row in ipairs(ns.Overlay._addRows()) do
		if row:IsShown() and row.item and ns.FullName(row.item.name, row.item.surname):find(name, 1, true) then
			return row
		end
	end
end

-- ---------------------------------------------------------------------------
section("Scum: ticked in the To add tab")
clearQueue()
H.now = H.now + 600
H.recap = {
	{ sourceName = "Gankmaster", sourceGUID = "Player-4710-000GANK1",
	  spellName = "Backstab", spellId = 53, amount = 700, overkill = 100,
	  event = "SPELL_DAMAGE", timestamp = H.now },
	{ sourceName = "Fairfighter", sourceGUID = "Player-4710-000FAIR1",
	  spellName = "Frostbolt", spellId = 116, amount = 300, overkill = -1,
	  event = "SPELL_DAMAGE", timestamp = H.now },
}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("no popup appears", _G.PersonalVendettaPrompt == nil)
check("both wait in the queue", ns.Pending:Count() == 2, ns.Pending:Count())
local gRow, fRow = addRowFor("Gankmaster"), addRowFor("Fairfighter")
check("each To add row has a Scum box", gRow and fRow and gRow.scum ~= nil and fRow.scum ~= nil)
check("Scum starts unticked", gRow and fRow and not gRow.scum:GetChecked() and not fRow.scum:GetChecked())
check("marked as a gank", queueText():find("gank", 1, true) ~= nil, queueText())
gRow.scum:SetChecked(true)
gRow.scum:Click()
addRowFor("Gankmaster").add:Click()
addRowFor("Fairfighter").add:Click()
local _, gank = ns.List:Find(nil, "Gankmaster")
local _, fair = ns.List:Find(nil, "Fairfighter")
check("ticked one added as scum", gank and gank.scum == true)
check("unticked one added as normal", fair and not fair.scum)
check("their kill counted on Add", gank and gank.theyKilledMe == 1)
check("added players leave the queue", ns.Pending:Count() == 0)

-- A new arrival must not inherit the old tick.
H.now = H.now + 600
H.recap = {
	{ sourceName = "Newbie", sourceGUID = "Player-4710-000NEW01",
	  spellName = "Wrath", spellId = 5176, amount = 200, overkill = 10,
	  event = "SPELL_DAMAGE", timestamp = H.now },
}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
local nRow = addRowFor("Newbie")
check("new row's Scum unticked", nRow and not nRow.scum:GetChecked())
clearQueue()

-- ---------------------------------------------------------------------------
section("Scum: own horn, first in line, glowing")
resetWorld()
H.units["nameplate1"] = warrior()
H.units["nameplate2"] = { name = "Gankmaster", guid = "Player-4710-000GANK1", level = 58,
	class = "ROGUE", className = "Rogue", race = "Undead", isPlayer = true, canAttack = true }
local snd2 = ns.db.settings.sound
snd2.enabled, snd2.choice, snd2.volume, snd2.scumChoice, snd2.scumVolume = true, "warhorn", 0.6, "airhorn", 0.8
H.clock = H.clock + 10
H.lastSound = nil
H.clearOutput()
step()
check("scum horn played, not the normal one", H.lastSound and H.lastSound.soundKitID == 316436,
	H.lastSound and H.lastSound.soundKitID)
check("at the scum volume", H.lastSound and H.lastSound.volumeOverride == 0.8, H.lastSound and H.lastSound.volumeOverride)
check("chat calls him scum", H.outputContains("SCUM|r ") and H.outputContains("Gankmaster|r is near. Must kill."))
local near = ns.Radar:GetNearby()
check("scum sorted to the top", near[1] and near[1].entry.name == "Gankmaster", near[1] and near[1].entry.name)
local orow = _G.PersonalVendettaOverlay and nil
-- Find the overlay row showing him and check it glows.
local function overlayRowFor(name)
	for _, f in ipairs(H.frames) do
		if f.name and f.glow and f.name.GetText and (f.name:GetText() or ""):find(name, 1, true) then
			return f
		end
	end
end
ns.Overlay.Refresh()
orow = overlayRowFor("Gankmaster")
check("scum row found in the window", orow ~= nil)
check("scum row glows", orow and orow.glowing == true)
check("scum row shows a skull", orow and (orow.name:GetText() or ""):find("RaidTargetingIcon_8", 1, true) ~= nil)
local nrow = overlayRowFor("Pumpdaddy")
check("normal row does not glow", nrow and not nrow.glowing)

-- Normal sighting right after a scum horn does not double up.
H.lastSound = nil
H.units["nameplate3"] = { name = "Sneakyboi", guid = "Player-4710-0002BBBB", level = 50,
	class = "ROGUE", className = "Rogue", race = "Undead", isPlayer = true, canAttack = true }
step()
check("no normal horn straight after the scum horn", H.lastSound == nil)

-- Scum dies: glow stops.
H.units["nameplate2"].dead = true
step()
ns.Overlay.Refresh()
orow = overlayRowFor("Gankmaster")
check("dead scum stops glowing", orow and not orow.glowing)

-- Unmark.
ns.List:SetScum(gank.key, false)
check("scum can be cleared", not gank.scum)
SlashCmdList.PERSONALVENDETTA("scum Gankmaster")
check("/vendetta scum marks", gank.scum == true)
SlashCmdList.PERSONALVENDETTA("unscum Gankmaster")
check("/vendetta unscum clears", not gank.scum)

-- ---------------------------------------------------------------------------
section("Scum: separate sound settings")
H.clock = H.clock + 10
ns.Sound:Cycle("scum", 1)
check("cycling scum leaves the normal choice alone", snd2.choice == "warhorn" and snd2.scumChoice ~= "airhorn",
	snd2.choice .. "/" .. snd2.scumChoice)
ns.Sound:SetVolume("scum", 0.25)
check("scum volume separate", ns.Sound:Volume("scum") == 0.25 and ns.Sound:Volume("normal") == 0.6)
ns.Sound:SetVolume("scum", 1.7)
check("volume clamped to 100%", ns.Sound:Volume("scum") == 1)
snd2.scumChoice, snd2.scumVolume = "airhorn", 0.6

-- ---------------------------------------------------------------------------
section("Nameplates")
H.cvars.nameplateShowEnemies, H.cvars.nameplateShowAll = "0", "0"
check("off detected", not ns.Radar:NameplatesOn())
local missing = table.concat(ns.Radar:NameplatesMissing(), ",")
check("reports both missing", missing:find("enemy nameplates", 1, true) and missing:find("always show", 1, true), missing)
H.lockdown = true
H.clearOutput()
ns.Radar:EnableNameplates()
check("not touched in combat", H.cvars.nameplateShowEnemies == "0")
check("says it will wait", H.outputContains("fight ends"))
H.lockdown = false
H.fire("PLAYER_REGEN_ENABLED")
check("switched on when combat ends", H.cvars.nameplateShowEnemies == "1" and H.cvars.nameplateShowAll == "1")
check("now reads as on", ns.Radar:NameplatesOn())
H.clearOutput()
SlashCmdList.PERSONALVENDETTA("nameplates")
check("/vendetta nameplates when already on is harmless", H.outputContains("already on"))
H.cvars.nameplateShowEnemies = "0"
SlashCmdList.PERSONALVENDETTA("nameplates")
check("/vendetta nameplates switches them on", H.cvars.nameplateShowEnemies == "1")

H.openedCategory = nil
ns.Radar:OpenNameplateSettings()
check("routes to Blizzard's Nameplates page", H.openedCategory == 42, H.openedCategory)
H.lockdown = true
H.openedCategory = nil
ns.Radar:OpenNameplateSettings()
check("does not try in combat", H.openedCategory == nil)
H.lockdown = false

H.cvars.nameplateShowEnemies, H.cvars.nameplateShowAll = "1", "0"
H.clearOutput()
ns.Radar:CheckSetup()
check("login warning names the exact missing setting", H.outputContains("always show nameplates"))
H.cvars.nameplateShowAll = "1"

-- ---------------------------------------------------------------------------
section("Settings panel v1.0")
ns.Settings:Open("general")
check("opens on General", ns.Settings.current == "general")
ns.Settings:Open("list")
check("Hit list tab opens", ns.Settings.current == "list")
-- The list tab's rows: find one showing Gankmaster and tick it.
local function listRowFor(name)
	for _, f in ipairs(H.frames) do
		if f.scum and f.tint and f.name and (f.name:GetText() or ""):find(name, 1, true) then return f end
	end
end
local lr = listRowFor("Gankmaster")
check("Gankmaster listed", lr ~= nil)
if lr then
	lr.scum:SetChecked(true)
	lr.scum:Click()
end
check("ticking Scum in the list marks him", gank.scum == true)
if lr then
	lr.scum:SetChecked(false)
	lr.scum:Click()
end
check("unticking clears it", not gank.scum)

-- Nameplate checkbox in the panel drives the CVars.
local function checkboxLabelled(needle)
	for _, f in ipairs(H.frames) do
		if f.label and f.label.GetText and (f.label:GetText() or ""):find(needle, 1, true) and f.refresh then
			return f
		end
	end
end
local npBox = checkboxLabelled("Enemy nameplates")
check("nameplate checkbox present", npBox ~= nil)
H.cvars.nameplateShowEnemies = "0"
ns.Settings:Refresh()
check("checkbox shows them off", npBox and not npBox:GetChecked())
if npBox then npBox:SetChecked(true) ; npBox:Click() end
check("ticking it turns them on", H.cvars.nameplateShowEnemies == "1")
H.fire("CVAR_UPDATE", "nameplateShowEnemies", "0")
H.cvars.nameplateShowEnemies = "0"
H.fire("CVAR_UPDATE", "nameplateShowEnemies", "0")
check("pressing V elsewhere unticks it", npBox and not npBox:GetChecked())
H.cvars.nameplateShowEnemies = "1"
H.fire("CVAR_UPDATE", "nameplateShowEnemies", "1")

check("no minimap checkbox anymore", checkboxLabelled("minimap") == nil)
check("old sound checkbox wording gone", checkboxLabelled("Play a sound when") == nil)

-- ---------------------------------------------------------------------------
section("Icon and release metadata")
local toc = assert(io.open(ADDON_DIR .. "PersonalVendetta.toc")):read("*a")
check("toc version 2.0", toc:find("## Version: 2.0", 1, true) ~= nil)
check("toc icon points at our file", toc:find("Media\\icon", 1, true) ~= nil)
local ih = io.open(ADDON_DIR .. "Media/icon.tga", "rb")
check("icon.tga shipped", ih ~= nil)
if ih then
	local head = ih:read(18)
	ih:close()
	check("icon is 32-bit uncompressed TGA", head:byte(3) == 2 and head:byte(17) == 32)
end
check("code points at the same file", ns.ICON == "Interface\\AddOns\\PersonalVendetta\\Media\\icon", ns.ICON)

-- ---------------------------------------------------------------------------
section("0.5 settings migrate to 1.0")
PersonalVendettaDB.settings.minimap.hide = true
ns.InitDB()
check("old minimap hide dropped", ns.db.settings.minimap.hide == nil)
check("scum sound defaults filled in", ns.db.settings.sound.scumChoice ~= nil and ns.db.settings.sound.scumVolume ~= nil)

-- ===========================================================================
-- v1.1
-- ===========================================================================

-- ---------------------------------------------------------------------------
section("Surnames: names")
local a, b = ns.SplitName("Willia Saqandie")
check("joined name splits", a == "Willia" and b == "Saqandie", tostring(a) .. "/" .. tostring(b))
a, b = ns.SplitName("Willia", "Saqandie")
check("two-part name kept", a == "Willia" and b == "Saqandie")
a, b = ns.SplitName("Willia")
check("first name alone", a == "Willia" and b == nil)
a, b = ns.SplitName(H.secret(), "Saqandie")
check("secret first name gives nothing", a == nil and b == nil)
check("full name for display", ns.FullName({ name = "Willia", surname = "Saqandie" }) == "Willia Saqandie")
check("first name only until surname known", ns.FullName({ name = "Willia" }) == "Willia")

-- ---------------------------------------------------------------------------
section("Surnames: two players, same first name")
local _, w1 = ns.List:Upsert({ guid = "Player-4710-0000W111", name = "Willia", surname = "Saqandie", class = "ROGUE" })
local _, w2 = ns.List:Upsert({ guid = "Player-4710-0000W222", name = "Willia", surname = "Ravenholt", class = "MAGE" })
check("kept as two entries", w1 ~= w2 and w1.key ~= w2.key)
local k1 = ns.List:Find(nil, "Willia Saqandie")
local k2 = ns.List:Find(nil, "Willia", "Ravenholt")
check("full name finds the right one", k1 == w1.key and k2 == w2.key)
local kAmb, eAmb, nAmb = ns.List:Find(nil, "Willia")
check("bare first name is ambiguous", kAmb == nil and eAmb == nil and nAmb == 2, tostring(nAmb))
check("guid wins regardless of name", ns.List:Find("Player-4710-0000W222", "Willia", "Saqandie") == w2.key)
-- A third Willia (new GUID) seen on a nameplate is a stranger, not either of them.
local strangerKey = ns.List:Find("Player-4710-0000W333", "Willia", "Stranger")
check("a third Willia is a stranger", strangerKey == nil)
local strangerKey2 = ns.List:Find("Player-4710-0000W333", "Willia")
check("a third Willia with no surname is still a stranger", strangerKey2 == nil)

-- ---------------------------------------------------------------------------
section("Surnames: the radar")
resetWorld()
H.units["nameplate5"] = { name = "Willia", surname = "Stranger", guid = "Player-4710-0000W333",
	level = 30, class = "WARRIOR", className = "Warrior", race = "Orc", isPlayer = true, canAttack = true }
step()
check("stranger with a shared first name is not flagged", ns.Radar:Get(w1.key) == nil and ns.Radar:Get(w2.key) == nil)
-- An old entry with no surname learns it on sight.
check("Pumpdaddy had no surname yet", entry.surname == nil)
H.units["nameplate1"] = warrior({ surname = "Grimtusk" })
step()
check("surname learned on sight", entry.surname == "Grimtusk", entry.surname)
check("shown as the full name", ns.FullName(entry) == "Pumpdaddy Grimtusk")
-- GUID unreadable, full name readable: still recognised.
resetWorld()
H.units["nameplate1"] = { name = "Willia", surname = "Saqandie", guid = H.secret(), level = 40,
	class = "ROGUE", isPlayer = true, canAttack = true }
step()
check("secret guid, full name still matches", ns.Radar:Get(w1.key) ~= nil)
-- GUID unreadable and only a first name shared by two: not guessed.
resetWorld()
H.units["nameplate1"] = { name = "Willia", guid = H.secret(), level = 40, isPlayer = true, canAttack = true }
step()
check("secret guid, ambiguous first name: no guess", ns.Radar:Get(w1.key) == nil and ns.Radar:Get(w2.key) == nil)

-- ---------------------------------------------------------------------------
section("Surnames: death recap")
clearQueue()
resetWorld()
H.now = H.now + 600
H.units["nameplate4"] = { name = "Morgath", surname = "Bloodfang", guid = "Player-4710-0000MRG1", level = 44,
	class = "WARLOCK", className = "Warlock", race = "Undead", isPlayer = true, canAttack = true }
H.recap = {
	{ sourceName = "Morgath", sourceGUID = "Player-4710-0000MRG1", spellName = "Shadow Bolt", spellId = 686,
	  amount = 900, overkill = 50, event = "SPELL_DAMAGE", timestamp = H.now },
	{ sourceName = "Kelra Dawnmere", sourceGUID = "Player-4710-0000KLR1", spellName = "Frostbolt", spellId = 116,
	  amount = 300, overkill = -1, event = "SPELL_DAMAGE", timestamp = H.now },
}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
local labels = queueText()
check("killer's surname read from his nameplate", labels:find("Morgath Bloodfang", 1, true) ~= nil, labels)
check("his level and class shown", labels:find("44 Warlock", 1, true) ~= nil, labels)
check("joined recap name split and shown", labels:find("Kelra Dawnmere", 1, true) ~= nil, labels)
addRowFor("Morgath").add:Click()
local _, morg = ns.List:Find("Player-4710-0000MRG1")
check("added with surname, level and race", morg and morg.surname == "Bloodfang" and morg.level == 44 and morg.race == "Undead")
check("added killer counts their kill", morg and morg.theyKilledMe == 1)
clearQueue()

-- ---------------------------------------------------------------------------
section("Surnames: commands and honor messages")
H.clearOutput()
SlashCmdList.PERSONALVENDETTA("scum Willia")
check("ambiguous first name asks for the surname", H.outputContains("2 people on your list are called Willia"))
check("nobody marked by the ambiguous command", not w1.scum and not w2.scum)
SlashCmdList.PERSONALVENDETTA("scum Willia Ravenholt")
check("full name marks the right one", w2.scum == true and not w1.scum)
SlashCmdList.PERSONALVENDETTA("unscum Willia Ravenholt")
local w1k0, w2k0 = w1.iKilledThem, w2.iKilledThem
H.now = H.now + 600
H.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Willia dies, honorable kill Rank: Scout (Estimated Honor Points: 14)")
check("honor message with a shared first name credits nobody", w1.iKilledThem == w1k0 and w2.iKilledThem == w2k0)
H.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Willia Saqandie dies, honorable kill Rank: Scout (Estimated Honor Points: 14)")
check("honor message with the full name credits the right one", w1.iKilledThem == w1k0 + 1 and w2.iKilledThem == w2k0)

-- ---------------------------------------------------------------------------
section("Post-fight prompt")
clearQueue()
resetWorld()
ns.db.settings.promptAfterFight = true
H.now = H.now + 4000 -- clear of any earlier skip memory
local function fight(units, opts)
	opts = opts or {}
	for k, v in pairs(units) do H.units[k] = v end
	H.inCombat = true
	H.fire("PLAYER_REGEN_DISABLED")
	ns.Fights._scan()
	if opts.before then opts.before() end
	ns.Fights._scan()
	H.inCombat = false
	H.fire("PLAYER_REGEN_ENABLED")
	H.runTimers(1)
end
local brute = { name = "Drogbar", surname = "Skullsplit", guid = "Player-4710-0000DRG1", level = 39,
	class = "WARRIOR", className = "Warrior", race = "Orc", isPlayer = true, canAttack = true, targets = "player" }
fight({ nameplate6 = brute }, { before = function() brute.dead = true end })
check("queued after surviving, no popup", ns.Pending:Count() == 1 and _G.PersonalVendettaPrompt == nil)
labels = queueText()
check("he is queued by full name", labels:find("Drogbar Skullsplit", 1, true) ~= nil, labels)
check("marked as killed by you", labels:find("you killed them", 1, true) ~= nil, labels)
check("fight wording, not death wording", labels:find("Fought you", 1, true) ~= nil
	and labels:find("Killed you", 1, true) == nil, labels)
addRowFor("Drogbar").add:Click()
local _, drog = ns.List:Find("Player-4710-0000DRG1")
check("added", drog ~= nil)
check("his kills on you stay 0", drog and drog.theyKilledMe == 0)
check("your kill counted", drog and drog.iKilledThem == 1)
check("last seen set", drog and drog.lastSeen == time())
clearQueue()

resetWorld()
fight({ nameplate6 = { name = "Survivor", surname = "Quickfeet", guid = "Player-4710-0000SRV1", level = 30,
	isPlayer = true, canAttack = true, targets = "player" } })
labels = queueText()
check("one who got away is offered too", labels:find("Survivor Quickfeet", 1, true) ~= nil, labels)
check("but not marked as killed", labels:find("you killed", 1, true) == nil, labels)
addRowFor("Survivor").skip:Click()
resetWorld()
fight({ nameplate6 = { name = "Survivor", surname = "Quickfeet", guid = "Player-4710-0000SRV1",
	isPlayer = true, canAttack = true, targets = "player" } })
check("skipped player not offered again soon", ns.Pending:Count() == 0)
H.now = H.now + 31 * 60
resetWorld()
fight({ nameplate6 = { name = "Survivor", surname = "Quickfeet", guid = "Player-4710-0000SRV1",
	isPlayer = true, canAttack = true, targets = "player" } })
check("offered again after half an hour", ns.Pending:Count() == 1)
clearQueue()

resetWorld()
fight({ nameplate6 = { name = "Duelist", surname = "Fairplay", guid = "Player-4710-0000DUE1", faction = "Alliance",
	isPlayer = true, canAttack = true, targets = "player" } })
check("same-faction duel opponent not offered", ns.Pending:Count() == 0)

resetWorld()
fight({ nameplate6 = { name = "Bystander", surname = "Idle", guid = "Player-4710-0000BYS1",
	isPlayer = true, canAttack = true } })
check("enemy who never targeted you not offered", ns.Pending:Count() == 0)

resetWorld()
fight({ nameplate1 = warrior({ targets = "player" }) })
check("someone already on the list not offered", ns.Pending:Count() == 0)

resetWorld()
H.units.player.dead = true
fight({ nameplate6 = { name = "Victor", surname = "Grim", guid = "Player-4710-0000VIC1",
	isPlayer = true, canAttack = true, targets = "player" } })
H.units.player.dead = nil
check("nothing queued from a fight that killed you", ns.Pending:Count() == 0)
clearQueue()

resetWorld()
H.instanceType = "pvp"
fight({ nameplate6 = { name = "Bgguy", surname = "Flag", guid = "Player-4710-0000BG01",
	isPlayer = true, canAttack = true, targets = "player" } })
H.instanceType = "none"
check("no fight prompt in a battleground", ns.Pending:Count() == 0)

resetWorld()
ns.db.settings.promptAfterFight = false
fight({ nameplate6 = { name = "Ignored", surname = "Setting", guid = "Player-4710-0000IGN1",
	isPlayer = true, canAttack = true, targets = "player" } })
check("setting off means no prompt", ns.Pending:Count() == 0)
ns.db.settings.promptAfterFight = true

-- A fight and a death land side by side in the queue; nothing waits behind a popup.
resetWorld()
fight({ nameplate6 = { name = "First", surname = "Inline", guid = "Player-4710-0000FIR1",
	isPlayer = true, canAttack = true, targets = "player" } })
H.now = H.now + 600
H.recap = { { sourceName = "Second", sourceGUID = "Player-4710-0000SEC1", spellName = "Ambush", spellId = 8676,
	amount = 999, overkill = 99, event = "SPELL_DAMAGE", timestamp = H.now } }
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("fight and death both queued", ns.Pending:Count() == 2, ns.Pending:Count())
check("both shown in the To add tab", addRowFor("First") ~= nil and addRowFor("Second") ~= nil)
clearQueue()

-- /vendetta add with no name adds your target.
resetWorld()
H.units["target"] = { name = "Targetted", surname = "Person", guid = "Player-4710-0000TGT1", level = 33,
	class = "HUNTER", className = "Hunter", race = "Troll", isPlayer = true, canAttack = true }
SlashCmdList.PERSONALVENDETTA("add")
local _, tgt = ns.List:Find("Player-4710-0000TGT1")
check("/vendetta add adds your target", tgt and ns.FullName(tgt) == "Targetted Person" and tgt.className == "Hunter")
H.clearOutput()
SlashCmdList.PERSONALVENDETTA("add")
check("and won't add them twice", H.outputContains("already on the list"))

-- ---------------------------------------------------------------------------
section("Hit list: newest first, last seen")
check("ago: never", ns.Ago(nil) == "never")
check("ago: just now", ns.Ago(time() - 20) == "just now")
check("ago: minutes", ns.Ago(time() - 5 * 60) == "5 min ago")
check("ago: one hour", ns.Ago(time() - 3600) == "1 hour ago")
check("ago: hours", ns.Ago(time() - 3 * 3600 - 100) == "3 hours ago")
check("ago: one day", ns.Ago(time() - 86400 - 5) == "1 day ago")
check("ago: days", ns.Ago(time() - 4 * 86400) == "4 days ago")
local byDate = ns.List:ByDateAdded()
local sorted = true
for i = 2, #byDate do
	if (byDate[i - 1].firstAdded or 0) < (byDate[i].firstAdded or 0) then sorted = false end
end
check("sorted newest first", sorted)
check("newest on top is the last one added", byDate[1] == tgt, byDate[1] and ns.FullName(byDate[1]))
ns.Settings:Open("list")
local function listRowAt(n)
	local rowsFound = {}
	for _, f in ipairs(H.frames) do
		if f.scum and f.tint and f.seen and f:IsShown() then rowsFound[#rowsFound + 1] = f end
	end
	return rowsFound[n]
end
local top = listRowAt(1)
check("top row of the tab is the newest", top and top.entry == tgt)
tgt.lastSeen = time() - 3 * 3600 - 60
ns.Settings:Refresh()
check("last seen shown as hours", top and (top.seen:GetText() or "") == "3 hours ago", top and top.seen:GetText())
tgt.lastSeen = time() - 2 * 86400 - 60
ns.Settings:Refresh()
check("then as days", top and (top.seen:GetText() or "") == "2 days ago", top and top.seen:GetText())

-- ---------------------------------------------------------------------------
section("Notes")
check("note button on the row", top and top.note ~= nil)
check("empty note reads + Note", top and (top.note:GetText() or ""):find("+ Note", 1, true) ~= nil)
top.note:Click()
check("editor opens for that player", ns.Notes:IsOpen() and ns.Notes:EditingKey() == tgt.key)
ns.Notes:Append("Ganked while leveling")
ns.Notes:Append("Ganked while leveling")
ns.Notes:Append("2v1")
check("presets append once, comma separated", ns.Notes:_edit():GetText() == "Ganked while leveling, 2v1",
	ns.Notes:_edit():GetText())
ns.Notes:Save()
check("saved to the player", tgt.note == "Ganked while leveling, 2v1", tgt.note)
check("editor closed on save", not ns.Notes:IsOpen())
check("button shows a note exists", (top.note:GetText() or ""):find("Note", 1, true) ~= nil and
	(top.note:GetText() or ""):find("+", 1, true) == nil)
ns.Notes:Open(tgt.key)
ns.Notes:_edit():SetText("something else")
_G.PersonalVendettaNotes:Hide()
check("closing without Save keeps the old note", tgt.note == "Ganked while leveling, 2v1")
ns.List:SetNote(tgt.key, "|cffff0000red|r |Hitem:19019|h[Thunderfury]|h \7 bell")
check("escape codes and control bytes stripped", tgt.note and not tgt.note:find("|", 1, true) and not tgt.note:find("\7", 1, true), tgt.note)
ns.List:SetNote(tgt.key, string.rep("x", 400))
check("notes capped at 300 characters", #tgt.note == 300, #tgt.note)
ns.List:SetNote(tgt.key, "   ")
check("blank note clears it", tgt.note == nil)
check("there are presets for 2v1 and 3v1", (function()
	local has = {}
	for _, p in ipairs(ns.Notes.presets) do has[p] = true end
	return has["2v1"] and has["3v1"] and has["Ganked while leveling"] and has["While low HP"]
		and has["While eating/drinking"] and has["During an escort quest"]
end)())
check("removed presets are gone", (function()
	for _, p in ipairs(ns.Notes.presets) do
		if p == "At a flight master" or p == "At a quest giver" or p == "Stealth opener" then return false end
	end
	return #ns.Notes.presets == 11
end)())
-- Notes ride along in the sighting message.
ns.List:SetNote(entry.key, "Camped me at the flight master")
resetWorld()
H.clearOutput()
H.units["nameplate1"] = warrior({ surname = "Grimtusk" })
step()
check("sighting message carries the note", H.outputContains("Camped me at the flight master"))

-- ---------------------------------------------------------------------------
section("Sharing: encoding")
local tricky = { guid = "Player-4710-0000TRK1", name = "Tricky", surname = "Name", level = 41, class = "ROGUE",
	className = "Rogue", race = "Gnome", scum = true, note = "a~b^c%d:e\nnew line", theyKilledMe = 3 }
local round = ns.Share:Decode(ns.Share:Encode({ tricky }))
check("round trip keeps fields", round and round[1] and round[1].name == "Tricky" and round[1].surname == "Name"
	and round[1].level == 41 and round[1].class == "ROGUE" and round[1].scum == true and round[1].killedSharer == 3)
check("round trip keeps awkward characters", round and round[1].note == "a~b^c%d:e\nnew line", round and round[1].note)
local evil = "V1^" .. table.concat({ "NotAGuid", "Bad%7Cname", "", "999", "", "rogue", "", "", "", "%7Ccff0000x", "-5" }, "~")
local ev = ns.Share:Decode(evil)
check("bad guid dropped", ev and ev[1] and ev[1].guid == nil)
check("pipes stripped from names", ev and ev[1] and not ev[1].name:find("|", 1, true))
check("impossible level dropped", ev and ev[1] and ev[1].level == nil)
check("lowercase class rejected", ev and ev[1] and ev[1].class == nil)
check("negative counts clamped", ev and ev[1] and ev[1].killedSharer == 0)
check("unknown version refused", ns.Share:Decode("V9^whatever") == nil)

-- ---------------------------------------------------------------------------
section("Sharing: sending")
clearQueue()
H.inGroup = false
H.clearOutput()
check("can't share outside a group", ns.Share:Send() == false and H.outputContains("party or raid"))
H.inGroup = true
H.sent = {}
local listSize = ns.List:Count()
check("sharing starts in a party", ns.Share:Send() == true)
for _ = 1, 200 do H.runTimers(1.1) ; if not ns.Share._sending() then break end end
check("all messages sent", #H.sent >= 2, #H.sent)
check("over the party channel", H.sent[1] and H.sent[1].channel == "PARTY")
check("offer header first", H.sent[1] and H.sent[1].msg:sub(1, 2) == "O:")
local tooLong = false
for _, m in ipairs(H.sent) do if #m.msg > 255 then tooLong = true end end
check("every message within the 255-byte cap", not tooLong)
check("finish reported", H.outputContains("Hit list shared"))

-- Throttling: the game says "slow down" once; nothing is lost.
H.sent = {}
H.sendResults = { 0, 3 }
ns.Share:Send()
for _ = 1, 200 do H.runTimers(1.6) ; if not ns.Share._sending() then break end end
local chunkCount = tonumber(H.sent[1].msg:match("^O:%x+:(%d+):"))
check("throttled message retried, none lost", #H.sent == chunkCount + 1, #H.sent .. " vs " .. tostring(chunkCount and chunkCount + 1))
H.sendResults = { 11 }
H.clearOutput()
ns.Share:Send()
check("lockdown stops sharing cleanly", not ns.Share._sending() and H.outputContains("blocked"))
H.sendResults = {}

-- ---------------------------------------------------------------------------
section("Sharing: receiving")
-- Capture one share, then play it back as if from a party member.
H.sent = {}
ns.Share:Send()
for _ = 1, 200 do H.runTimers(1.1) ; if not ns.Share._sending() then break end end
local msgs = {}
for _, m in ipairs(H.sent) do msgs[#msgs + 1] = m.msg end

-- Your own share coming back is ignored.
ns.Share._onMessage(ns.Share.PREFIX, msgs[1], "PARTY", "Me")
check("own share ignored", next(ns.Share._sessions) == nil)

local function asFriend(msg)
	if msg:sub(1, 2) == "O:" then
		return (msg:gsub("^(O:%x+:%d+:%d+:)[^:]*:(.*)$", "%1Player-4710-0000FRND:Kaz%%20Ironvein"))
	end
	return msg
end
-- The receiver is missing three of the players the friend shares.
local missing = { "Player-4710-0000DRG1", "Player-4710-0000TGT1", "Player-4710-0000MRG1" }
local savedEntries = {}
for _, g in ipairs(missing) do
	savedEntries[g] = ns.db.list[g]
	ns.List:Remove(g)
end
local before = ns.List:Count()
-- Deliver chunks out of order, with a duplicate thrown in.
local order = { 1 }
for i = #msgs, 2, -1 do order[#order + 1] = i end
order[#order + 1] = 2
H.clearOutput()
for _, i in ipairs(order) do ns.Share._onMessage(ns.Share.PREFIX, asFriend(msgs[i]), "PARTY", "Kaz") end
check("announced who is sharing", H.outputContains("Kaz Ironvein is sharing their hit list"))
local imp = _G.PersonalVendettaImport
check("import prompt shown", imp and imp:IsShown())
check("says how many are new", imp and (imp.body:GetText() or ""):find("new to you: 3", 1, true) ~= nil, imp and imp.body:GetText())
check("says how many you already have", imp and (imp.body:GetText() or ""):find("Already on your list: " .. (listSize - 3), 1, true) ~= nil)
imp.yes:Click()
check("only the new ones imported", ns.List:Count() == before + 3, ns.List:Count() .. " vs " .. (before + 3))
local _, back = ns.List:Find("Player-4710-0000DRG1")
check("imported with full name", back and ns.FullName(back) == "Drogbar Skullsplit")
check("marked as shared by them", back and back.sharedBy == "Kaz Ironvein")
check("their score with you starts clean", back and back.theyKilledMe == 0 and back.iKilledThem == 0)
check("no duplicates anywhere", (function()
	local seen = {}
	for _, e in pairs(ns.db.list) do
		local id = e.guid or ns.FullName(e)
		if seen[id] then return false end
		seen[id] = true
	end
	return true
end)())
-- Sharing the same list again: nothing new.
H.clearOutput()
for i = 1, #msgs do ns.Share._onMessage(ns.Share.PREFIX, asFriend(msgs[i]), "PARTY", "Kaz") end
check("second share: all already on yours", H.outputContains("all " .. ns.List:Count() .. " already on yours")
	or H.outputContains("already on yours"))
-- Chunks for a share nobody announced are ignored.
ns.Share._onMessage(ns.Share.PREFIX, "C:abcdef:1:junk", "PARTY", "Rando")
check("stray chunk ignored", next(ns.Share._sessions) == nil)

-- ---------------------------------------------------------------------------
section("1.0 saves load in 1.1")
PersonalVendettaDB.nameIndex = { pumpdaddy = entry.key }
ns.InitDB()
check("old saved name index dropped", PersonalVendettaDB.nameIndex == nil)
check("lookups rebuilt from the list", ns.List:Find(nil, "Pumpdaddy Grimtusk") == entry.key)
check("post-fight setting defaults on", ns.db.settings.promptAfterFight == true)

-- ===========================================================================
-- v1.2: no popups, the To add tab
-- ===========================================================================

local function die(...)
	H.now = H.now + 600
	local recap = {}
	for i, k in ipairs({ ... }) do
		recap[i] = { sourceName = k[1], sourceGUID = k[2], spellName = "Hit", spellId = 1,
			amount = 500, overkill = (i == 1) and 50 or -1, event = "SPELL_DAMAGE", timestamp = H.now }
	end
	H.recap = recap
	H.fire("PLAYER_DEAD")
	H.runTimers(0.2)
end

-- ---------------------------------------------------------------------------
section("Queue: nothing interrupts you")
clearQueue()
resetWorld()
ns.Overlay.Toggle(true)
ns.Overlay.SelectTab("near")
H.clearOutput()
die({ "Vanishblade", "Player-4710-0000VAN1" })
check("no popup frame, ever", _G.PersonalVendettaPrompt == nil)
check("the window did not switch tabs on its own", ns.Overlay.CurrentTab() == "near")
check("one chat line says where to look", H.outputContains("waiting to be added") and H.outputContains("To add"))
check("queued", ns.Pending:Count() == 1)

-- ---------------------------------------------------------------------------
section("Queue: the To add tab glows until you look")
local tabs = ns.Overlay._tabs()
check("tab shows the count", (tabs.add.text:GetText() or ""):find("1", 1, true) ~= nil, tabs.add.text:GetText())
check("unseen while on Nearby", ns.Pending:UnseenCount() == 1)
check("glow animation running", _G.PersonalVendettaOverlay:GetScript("OnUpdate") ~= nil)
ns.Overlay.SelectTab("add")
check("opening the tab marks it seen", ns.Pending:UnseenCount() == 0)
check("glow stops once seen", _G.PersonalVendettaOverlay:GetScript("OnUpdate") == nil)
ns.Overlay.SelectTab("near")
die({ "Vanishblade", "Player-4710-0000VAN1" })
check("a repeat from the same player glows again", ns.Pending:UnseenCount() == 1)
check("still one row for him", ns.Pending:Count() == 1)

-- ---------------------------------------------------------------------------
section("Queue: repeats merge into one row")
local it = ns.Pending:List()[1]
check("killed you x2", it.deaths == 2, it.deaths)
check("described as x2", ns.Pending:Describe(it):find("Killed you x2", 1, true) ~= nil, ns.Pending:Describe(it))
check("killing blow noted", it.killingBlows == 2)
SlashCmdList.PERSONALVENDETTA("recap")
check("re-reading the recap counts nothing extra", ns.Pending:List()[1].deaths == 2)
addRowFor("Vanishblade").add:Click()
local _, van = ns.List:Find("Player-4710-0000VAN1")
check("Add carries both deaths over", van and van.theyKilledMe == 2, van and van.theyKilledMe)
check("queue empty after Add", ns.Pending:Count() == 0)

-- ---------------------------------------------------------------------------
section("Queue: note from the window, before adding")
clearQueue()
die({ "Notetaker", "Player-4710-0000NOT1" })
ns.Overlay.SelectTab("add")
local row = addRowFor("Notetaker")
check("To add row has a Note button", row and row.note ~= nil)
row.note:Click()
check("editor opens for the queued player", ns.Notes:IsOpen() and ns.Notes:EditingKey() == "pending:" .. row.id)
ns.Notes:Append("While eating/drinking")
ns.Notes:Append("2v1")
ns.Notes:Save()
check("note kept on the queued player", ns.Pending:List()[1].note == "While eating/drinking, 2v1",
	ns.Pending:List()[1].note)
check("button shows a note exists", (addRowFor("Notetaker").note:GetLabel() or ""):find("+", 1, true) == nil)
local ntRow = addRowFor("Notetaker")
ntRow.scum:SetChecked(true)
ntRow.scum:Click()
addRowFor("Notetaker").add:Click()
local _, nt = ns.List:Find("Player-4710-0000NOT1")
check("note goes with them onto the list", nt and nt.note == "While eating/drinking, 2v1")
check("scum goes with them too", nt and nt.scum == true)

-- ---------------------------------------------------------------------------
section("Nearby rows have a Note button")
resetWorld()
ns.Overlay.SelectTab("near")
H.units["nameplate1"] = warrior({ surname = "Grimtusk" })
step()
local nearRow
for _, r in ipairs(ns.Overlay._rows()) do if r:IsShown() and r.entry == entry then nearRow = r end end
check("he is on the Nearby tab", nearRow ~= nil)
check("with a Note button", nearRow and nearRow.note ~= nil)
nearRow.note:Click()
check("Note opens his note straight from the window", ns.Notes:IsOpen() and ns.Notes:EditingKey() == entry.key)
_G.PersonalVendettaNotes:Hide()

-- ---------------------------------------------------------------------------
section("Queue: a sighting brings you back to Nearby")
resetWorld()
ns.Overlay.SelectTab("add")
H.units["nameplate1"] = warrior({ surname = "Grimtusk" })
H.clock = H.clock + 10
step()
check("switched to Nearby when a listed player appeared", ns.Overlay.CurrentTab() == "near")

-- ---------------------------------------------------------------------------
section("Queue: Add all, Skip all")
clearQueue()
die({ "Alpha", "Player-4710-0000ALP1" }, { "Bravo", "Player-4710-0000BRV1" }, { "Charlie", "Player-4710-0000CHR1" })
check("three queued from one gank", ns.Pending:Count() == 3)
ns.Overlay.SelectTab("add")
local page = ns.Overlay._addPage()
check("Add all button shown", page.addAll:IsShown())
page.addAll:Click()
check("Add all adds everyone", ns.Pending:Count() == 0 and select(2, ns.List:Find("Player-4710-0000BRV1")) ~= nil)
die({ "Delta", "Player-4710-0000DLT1" }, { "Echo", "Player-4710-0000ECH1" })
ns.Overlay.SelectTab("add")
page.skipAll:Click()
check("Skip all clears the queue", ns.Pending:Count() == 0)
check("skipped players not added", select(2, ns.List:Find("Player-4710-0000DLT1")) == nil)
check("empty message shown", page.empty:IsShown())

-- ---------------------------------------------------------------------------
section("Queue: saved, bounded, and kept tidy")
clearQueue()
die({ "Survives", "Player-4710-0000SVR1" })
local savedId = ns.Pending:List()[1].id
ns.InitDB()
H.fire("ADDON_LOADED", "PersonalVendetta")
check("queue survives a reload", ns.Pending:Count() == 1 and ns.Pending:List()[1].id == savedId)
die({ "Afterload", "Player-4710-0000AFT1" })
local ids = {}
for _, q in ipairs(ns.Pending:List()) do ids[q.id] = (ids[q.id] or 0) + 1 end
check("ids stay unique after a reload", (function() for _, n in pairs(ids) do if n > 1 then return false end end return true end)())
SlashCmdList.PERSONALVENDETTA("add Survives")
check("adding by command takes them out of the queue", (function()
	for _, q in ipairs(ns.Pending:List()) do if q.name == "Survives" then return false end end
	return true
end)())
clearQueue()
for i = 1, 45 do
	ns.Pending:OfferBatch({ { name = "Mass" .. i, guid = string.format("Player-4710-%08X", 0xA000 + i), certain = true } }, "death")
end
check("queue capped at 40", ns.Pending:Count() == 40, ns.Pending:Count())
check("the newest are the ones kept", ns.Pending:List()[1].name == "Mass45")
clearQueue()

-- ---------------------------------------------------------------------------
section("Queue: window hidden, commands, settings wording")
ns.Overlay.Toggle(false)
H.clearOutput()
die({ "Hiddenview", "Player-4710-0000HID1" })
check("with the window hidden, chat says how to open it", H.outputContains("/vendetta review"))
SlashCmdList.PERSONALVENDETTA("review")
check("/vendetta review opens the window on To add",
	_G.PersonalVendettaOverlay:IsShown() and ns.Overlay.CurrentTab() == "add")
clearQueue()
local function labelled(needle)
	for _, f in ipairs(H.frames) do
		if f.label and f.label.GetText and (f.label:GetText() or ""):find(needle, 1, true) then return f end
	end
end
check("setting now talks about the To add tab", labelled("Queue players who kill me") ~= nil)
check("no setting still says Ask me", labelled("Ask me") == nil)

-- ---------------------------------------------------------------------------
section("Note window closes when its player is added")
-- The reported steps: fight, player queued, Note, type, Add.
clearQueue()
resetWorld()
fight({ nameplate6 = { name = "Noteclose", surname = "Steps", guid = "Player-4710-0000NCS1",
	isPlayer = true, canAttack = true, targets = "player" } })
local ncRow = addRowFor("Noteclose")
ncRow.note:Click()
check("note window open", ns.Notes:IsOpen())
ns.Notes:_edit():SetText("Typed but never pressed Save")
addRowFor("Noteclose").add:Click()
check("note window closes on Add", not ns.Notes:IsOpen())
local _, ncs = ns.List:Find("Player-4710-0000NCS1")
check("what was typed is kept", ncs and ncs.note == "Typed but never pressed Save", ncs and ncs.note)

-- Same, without typing anything.
clearQueue()
resetWorld()
fight({ nameplate6 = { name = "Blanknote", surname = "Steps", guid = "Player-4710-0000BNS1",
	isPlayer = true, canAttack = true, targets = "player" } })
addRowFor("Blanknote").note:Click()
addRowFor("Blanknote").add:Click()
check("closes with an empty note too", not ns.Notes:IsOpen())
local _, bns = ns.List:Find("Player-4710-0000BNS1")
check("added with no note", bns and bns.note == nil)

-- Skip closes it and keeps nothing.
clearQueue()
resetWorld()
fight({ nameplate6 = { name = "Skipnote", surname = "Steps", guid = "Player-4710-0000SNS1",
	isPlayer = true, canAttack = true, targets = "player" } })
addRowFor("Skipnote").note:Click()
ns.Notes:_edit():SetText("never mind")
addRowFor("Skipnote").skip:Click()
check("closes on Skip", not ns.Notes:IsOpen())
check("skipped player not added", select(2, ns.List:Find("Player-4710-0000SNS1")) == nil)

-- Adding someone else leaves an open note alone.
clearQueue()
die({ "Keepopen", "Player-4710-0000KOP1" }, { "Otherone", "Player-4710-0000OTH1" })
addRowFor("Keepopen").note:Click()
addRowFor("Otherone").add:Click()
check("adding a different player keeps the note open", ns.Notes:IsOpen()
	and ns.Notes:EditingKey() == "pending:" .. addRowFor("Keepopen").id)
-- Add all closes it (and keeps the text).
ns.Notes:_edit():SetText("via add all")
ns.Overlay._addPage().addAll:Click()
check("Add all closes it", not ns.Notes:IsOpen())
local _, kop = ns.List:Find("Player-4710-0000KOP1")
check("and keeps the text", kop and kop.note == "via add all", kop and kop.note)
clearQueue()


-- ===========================================================================
-- v2.0
-- ===========================================================================

local function enemy(name, surname, guid, extra)
	local t = { name = name, surname = surname, guid = guid, level = 30, class = "ROGUE",
		className = "Rogue", race = "Undead", isPlayer = true, canAttack = true }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
local function seen(text) for _, l in ipairs(H.output) do if string.find(l, text, 1, true) then return true end end return false end

-- ---------------------------------------------------------------------------
section("Per-player 30 second re-alert")
resetWorld()
ns.db.settings.sound.enabled = true
local rv = ns.List:RecordTheirKill({ guid = "Player-4710-00RV0001", name = "Revolver", surname = "Door" })
local sightings = 0
ns.On("SIGHTED", function(list) for _, e in ipairs(list) do if e == rv then sightings = sightings + 1 end end end)
H.units.nameplate3 = enemy("Revolver", "Door", "Player-4710-00RV0001")
step()
check("first sighting sounds", sightings == 1, sightings)
H.units.nameplate3 = nil
step(3) ; step(0.4)
check("gone from the radar", ns.Radar:Get(rv.key) == nil)
H.units.nameplate3 = enemy("Revolver", "Door", "Player-4710-00RV0001")
step(5)
check("back after a few seconds: silent", sightings == 1, sightings)
H.units.nameplate3 = nil
step(3) ; step(0.4)
step(31)
H.units.nameplate3 = enemy("Revolver", "Door", "Player-4710-00RV0001")
step()
check("back after 30+ seconds: sounds again", sightings == 2, sightings)
-- Someone else is not held back by Revolver's timer.
local ot = ns.List:RecordTheirKill({ guid = "Player-4710-00RV0002", name = "Otherguy", surname = "Door" })
local otherSighted = false
ns.On("SIGHTED", function(list) for _, e in ipairs(list) do if e == ot then otherSighted = true end end end)
H.units.nameplate4 = enemy("Otherguy", "Door", "Player-4710-00RV0002")
step()
check("the delay is per player", otherSighted)
check("zone remembered on sighting", rv.lastZone == "Goldshire, Elwynn Forest", rv.lastZone)
check("sighting logged in history", (function()
	for _, h in ipairs(rv.history or {}) do if h.e == "seen" or h.event == "seen" then return true end end
	return false end)())

-- ---------------------------------------------------------------------------
section("Skull on their nameplate")
ns.db.settings.markNameplates = true
step()
check("listed player in view is marked", ns.Marks:Get(rv.key) ~= nil)
check("marker sits on their plate", ns.Marks:Get(rv.key) and ns.Marks:Get(rv.key).plate == H.plates.nameplate3)
ns.List:SetScum(rv.key, true)
step()
check("scum marker glows", ns.Marks:Get(rv.key) and ns.Marks:Get(rv.key).scum == true)
ns.List:SetScum(rv.key, false)
H.plates.nameplate4.__forbidden = true
ns.Marks:Clear()
step()
check("forbidden plate is left alone", ns.Marks:Get(ot.key) == nil)
H.plates.nameplate4.__forbidden = false
H.units.nameplate3 = nil
step(3) ; step(0.4)
check("mark released when they leave", ns.Marks:Get(rv.key) == nil)
ns.db.settings.markNameplates = false
ns.Fire("SETTINGS_CHANGED")
check("setting off clears every mark", ns.Marks:Count() == 0)
ns.db.settings.markNameplates = true
resetWorld()

-- ---------------------------------------------------------------------------
section("Settle the score")
local st = ns.List:RecordTheirKill({ guid = "Player-4710-00ST0001", name = "Settler", surname = "Score" })
ns.List:RecordTheirKill({ guid = "Player-4710-00ST0001", name = "Settler", surname = "Score" })
local settled, streak
ns.On("SCORE_SETTLED", function(e, ahead) settled = { e, ahead } end)
ns.On("STREAK", function(e, n) streak = n end)
ns.List:RecordMyKill({ guid = "Player-4710-00ST0001" })
check("1 of 2: not settled yet", settled == nil)
H.now = H.now + 60
ns.List:RecordMyKill({ guid = "Player-4710-00ST0001" })
check("drawing level settles it", settled and settled[1] == st and settled[2] == false)
check("revenge toast shown", ns.Toast:IsShown() and seen ~= nil)
check("toast says settled", (_G.PersonalVendettaToast.title:GetText() or ""):find("settled", 1, true) ~= nil,
	_G.PersonalVendettaToast.title:GetText())
H.now = H.now + 60
ns.List:RecordMyKill({ guid = "Player-4710-00ST0001" })
check("third kill in a row is a streak", streak == 3, streak)
check("their kill resets the streak", ns.List:RecordTheirKill({ guid = "Player-4710-00ST0001" }).streak == 0)

-- ---------------------------------------------------------------------------
section("Player detail")
ns.List:Upsert({ guid = "Player-4710-00ST0001", name = "Settler", surname = "Score", level = 31 })
ns.List:Upsert({ guid = "Player-4710-00ST0001", name = "Settler", surname = "Score", level = 34 })
ns.Detail:Open(st.key)
check("detail opens", ns.Detail:IsOpen() and ns.Detail:Key() == st.key)
check("levels recorded", st.levels and #st.levels >= 2, st.levels and #st.levels)
check("progression line mentions levels", (function()
	local p = ns.Detail:Progression(st)
	local s = type(p) == "table" and table.concat(p, "\n") or tostring(p)
	return s:find("34", 1, true) ~= nil end)())
check("history has kills and deaths", (function()
	local lines = ns.Detail:HistoryLines(st)
	return type(lines) == "table" and #lines >= 4 end)())
local dframe = ns.Detail:_frame()
dframe.remove:Click()
check("remove takes them off", select(2, ns.List:Find("Player-4710-00ST0001")) == nil)
check("undo offered", ns.Toast:IsShown() and _G.PersonalVendettaToast.button:IsShown())
_G.PersonalVendettaToast.button:Click()
local _, back = ns.List:Find("Player-4710-00ST0001")
check("undo brings them back with their score", back and back.theyKilledMe == 3 and back.iKilledThem == 3,
	back and (back.theyKilledMe .. "/" .. back.iKilledThem))
check("detail not open for an unknown key", (function() ns.Detail:_frame():Hide(); ns.Detail:Open("nope") ; return not ns.Detail:IsOpen() end)())

-- ---------------------------------------------------------------------------
section("Undo for skips")
clearQueue()
die({ "Undoskip", "Player-4710-00US0001" })
addRowFor("Undoskip").skip:Click()
check("skipped", addRowFor("Undoskip") == nil)
check("undo toast for the skip", ns.Toast:IsShown() and (_G.PersonalVendettaToast.title:GetText() or ""):find("Undoskip", 1, true))
_G.PersonalVendettaToast.button:Click()
check("undo puts them back in the queue", addRowFor("Undoskip") ~= nil)
die({ "Skipa", "Player-4710-00US0002" }, { "Skipb", "Player-4710-00US0003" })
ns.Overlay._addPage().skipAll:Click()
check("skip all empties the queue", ns.Pending:Count() == 0, ns.Pending:Count())
_G.PersonalVendettaToast.button:Click()
check("one undo brings everyone back", ns.Pending:Count() >= 3, ns.Pending:Count())
clearQueue()

-- ---------------------------------------------------------------------------
section("Party alerts")
H.inGroup = true
H.sent = {}
resetWorld()
H.units.nameplate5 = enemy("Partyspot", "Ted", "Player-4710-00PA0001")
local pa = ns.List:RecordTheirKill({ guid = "Player-4710-00PA0001", name = "Partyspot", surname = "Ted" })
H.clock = H.clock + 40
step()
local sMsg
for _, m in ipairs(H.sent) do if m.msg:sub(1, 2) == "S:" then sMsg = m.msg end end
check("sighting sent to the group", sMsg ~= nil)
ns.db.settings.partyAlertSend = false
H.sent = {}
H.units.nameplate5 = nil ; step(3) ; step(40)
H.units.nameplate5 = enemy("Partyspot", "Ted", "Player-4710-00PA0001")
step()
check("not sent when switched off", #H.sent == 0)
ns.db.settings.partyAlertSend = true
-- Receiving one from a friend.
local friendMsg = sMsg and sMsg:gsub(":[^:]*:[^:]*$", ":Player-4710-0000FRND:Kaz%%20Ironvein")
H.clearOutput()
H.lastSound = nil
H.clock = H.clock + 10
ns.Share:OnPartySighting(friendMsg, "Kaz")
check("friend's sighting printed", H.outputContains("Kaz Ironvein spotted") and H.outputContains("from your list"))
check("and the horn plays", H.lastSound ~= nil)
H.clearOutput()
ns.Share:OnPartySighting(friendMsg, "Kaz")
check("repeat within 30s ignored", not H.outputContains("spotted"))
H.clock = H.clock + 31
H.clearOutput()
ns.Share:OnPartySighting(sMsg, "Me")
check("our own message ignored", not H.outputContains("spotted"))
H.inGroup = false
resetWorld()

-- ---------------------------------------------------------------------------
section("Window options and the radar dot")
ns.Overlay.Toggle(true)
local ov = _G.PersonalVendettaOverlay
H.cvars.nameplateShowEnemies = "0"
ns.Fire("SETTINGS_CHANGED")
check("dot goes red when blind", ov.dot.blind == true)
H.cvars.nameplateShowEnemies = "1"
ns.Fire("SETTINGS_CHANGED")
check("dot green when it can see", ov.dot.blind == false)
ns.db.settings.window.autoHide = true
clearQueue()
ns.Overlay.SelectTab("near")
ns.Fire("SETTINGS_CHANGED")
check("auto-hide hides a quiet window", not ov:IsShown() and ov.autoHidden)
H.units.nameplate5 = enemy("Partyspot", "Ted", "Player-4710-00PA0001")
H.clock = H.clock + 40
step()
check("comes back when someone appears", ov:IsShown())
ns.db.settings.window.autoHide = false
resetWorld()
ns.Fire("SETTINGS_CHANGED")

-- ---------------------------------------------------------------------------
section("Hit list search and sort")
ns.Settings:Open("list")
ns.Settings:SetSearch("partyspot")
local vis = ns.Settings:VisibleEntries()
check("search narrows to the match", #vis == 1 and vis[1].name == "Partyspot", #vis)
ns.Settings:SetSearch("goldshire")
check("search reaches the zone", #ns.Settings:VisibleEntries() >= 1)
ns.Settings:SetSearch("")
local all = ns.Settings:VisibleEntries()
check("empty search shows everyone", #all == ns.List:Count(), #all .. " vs " .. ns.List:Count())
ns.db.settings.listSort = "deaths"
local byDeaths = ns.Settings:VisibleEntries()
check("most deaths first", (byDeaths[1].theyKilledMe or 0) >= (byDeaths[#byDeaths].theyKilledMe or 0))
local before = ns.db.settings.listSort
ns.Settings:CycleSort()
check("sort button cycles", ns.db.settings.listSort ~= before)
ns.db.settings.listSort = "newest"
ns.Settings:Toggle(false)

-- ---------------------------------------------------------------------------
section("Feedback")
local fb = ns.Settings:Feedback()
check("feedback window opens", fb:IsShown())
check("links to the CurseForge comments", fb.url:GetText() == "https://www.curseforge.com/wow/addons/personal-vendetta-pvp/comments")
check("version line for bug reports", (fb.info:GetText() or ""):find("Personal Vendetta 2.0", 1, true) ~= nil, fb.info:GetText())
fb.url:SetText("typed over")
fb.url:GetScript("OnTextChanged")(fb.url)
check("link box is read-only", fb.url:GetText() == ns.FEEDBACK_URL)
fb:Hide()

-- ---------------------------------------------------------------------------
section("Account-wide list")
local charCount = ns.List:Count()
PersonalVendettaAccountDB.list["Player-4710-00AC0001"] = { key = "Player-4710-00AC0001", guid = "Player-4710-00AC0001",
	name = "Altkiller", surname = "Shared", theyKilledMe = 2, iKilledThem = 0, firstAdded = H.now }
PersonalVendettaAccountDB.list["Player-4710-00PA0001"] = { key = "Player-4710-00PA0001", guid = "Player-4710-00PA0001",
	name = "Partyspot", surname = "Ted", theyKilledMe = 4, iKilledThem = 1, firstAdded = H.now }
local paDeaths = pa.theyKilledMe
ns.SetAccountWide(true)
check("shared list is in use", ns.IsAccountWide() and ns.ListData() == PersonalVendettaAccountDB.list)
check("this character's list merged in", ns.List:Count() == charCount + 1, ns.List:Count() .. " vs " .. (charCount + 1))
local _, merged = ns.List:Find("Player-4710-00PA0001")
check("someone on both: scores added", merged and merged.theyKilledMe == paDeaths + 4, merged and merged.theyKilledMe)
check("alt's kills findable", select(2, ns.List:Find(nil, "Altkiller Shared")) ~= nil)
ns.SetAccountWide(false)
check("off: back to the character list", ns.ListData() == ns.db.list and ns.List:Count() == charCount)
ns.SetAccountWide(true)
check("on again: no double merge", select(2, ns.List:Find("Player-4710-00PA0001")).theyKilledMe == paDeaths + 4)
ns.SetAccountWide(false)

-- ---------------------------------------------------------------------------
section("Translations")
local function specs(s) local t = {} for x in s:gmatch("%%[sd]") do t[#t + 1] = x end return table.concat(t) end
for _, code in ipairs({ "deDE", "frFR", "esES", "ruRU" }) do
	local tbl = ns.LocaleTables[code]
	check(code .. " loaded", type(tbl) == "table")
	local n, bad, empty = 0, {}, 0
	for k, v in pairs(tbl or {}) do
		n = n + 1
		if specs(k) ~= specs(v) then bad[#bad + 1] = k end
		if v == "" then empty = empty + 1 end
	end
	check(code .. " has every string", n >= 289, n)
	check(code .. " keeps %s/%d in order", #bad == 0, bad[1])
	check(code .. " has no blanks", empty == 0)
end
-- Every key used in the code exists in each translation.
check("English client shows English", ns.L["Revenge!"] == "Revenge!")
-- A German client gets German.
H.locale = "deDE"
local ns2 = {}
for _, file in ipairs(FILES) do
	if file == "Locale.lua" or file:find("^Locales/") then
		local f = assert(io.open(ADDON_DIR .. file, "r")); local src = f:read("*a"); f:close()
		assert(load(src, file))("PersonalVendetta", ns2)
	end
end
check("German client gets German", ns2.L["Revenge!"] == "Rache!", ns2.L["Revenge!"])
check("missing key falls back to English", ns2.L["Not a real key"] == "Not a real key")
H.locale = "esMX"
local ns3 = {}
for _, file in ipairs(FILES) do
	if file == "Locale.lua" or file:find("^Locales/") then
		local f = assert(io.open(ADDON_DIR .. file, "r")); local src = f:read("*a"); f:close()
		assert(load(src, file))("PersonalVendetta", ns3)
	end
end
check("Mexican Spanish uses the Spanish file", ns3.L["Revenge!"] == "¡Venganza!")
H.locale = "enUS"


-- ---------------------------------------------------------------------------
section("Radar dot switches nameplates both ways")
ns.Overlay.Toggle(true)
local ov2 = _G.PersonalVendettaOverlay
H.cvars.nameplateShowEnemies, H.cvars.nameplateShowAll = "1", "1"
ns.Fire("SETTINGS_CHANGED")
ov2.dot:Click()
check("click while seeing: nameplates off", H.cvars.nameplateShowEnemies == "0")
check("dot turns red", ov2.dot.blind == true)
ov2.dot:Click()
check("click again: back on", H.cvars.nameplateShowEnemies == "1" and ov2.dot.blind == false)
H.inCombat = true
H.lockdown = true
H.clearOutput()
ns.Radar:DisableNameplates()
check("can't switch off in combat", H.cvars.nameplateShowEnemies == "1" and H.outputContains("in combat"))
H.inCombat, H.lockdown = false, false

-- ---------------------------------------------------------------------------
section("Sort dropdown")
ns.Settings:Open("list")
ns.Settings:SetSort("scum")
check("picking an order sets it", ns.db.settings.listSort == "scum")
check("unknown order ignored", ns.Settings:SetSort("bogus") == nil and ns.db.settings.listSort == "scum")
ns.Settings:SetSort("newest")
ns.Settings:Toggle(false)

-- ---------------------------------------------------------------------------
section("Quiet in cities and towns")
local function sightQuiet(zone, sub, resting)
	resetWorld()
	H.zone, H.subzone, H.resting = zone, sub, resting or false
	H.units.nameplate7 = enemy("Partyspot", "Ted", "Player-4710-00PA0001")
	H.clock = H.clock + 60
	H.lastSound = nil
	H.clearOutput()
	step()
	local shown = ns.Radar:Get("Player-4710-00PA0001") ~= nil
	local horn = H.lastSound ~= nil
	local chat = H.outputContains("is near")
	H.units.nameplate7 = nil
	return horn, chat, shown
end
local snd = ns.db.settings.sound
snd.enabled = true
snd.quietCapitals, snd.quietTowns = false, false
local horn, chat = sightQuiet("Stormwind City", "Trade District")
check("options off: horn in Stormwind as before", horn and chat)
snd.quietCapitals = true
check("capital recognised", ns.PlaceKind() == "capital")
local horn2, chat2, shown2 = sightQuiet("Stormwind City", "Trade District")
check("quiet in Stormwind: no horn", not horn2)
check("quiet in Stormwind: no chat line", not chat2)
check("but the window still lists them", shown2)
local horn3 = sightQuiet("Tanaris", "Gadgetzan")
check("towns not muted by the capital option", horn3)
snd.quietTowns = true
check("Gadgetzan is a town", (function() H.zone, H.subzone = "Tanaris", "Gadgetzan" ; return ns.PlaceKind() == "town" end)())
local horn4 = sightQuiet("Tanaris", "Gadgetzan")
check("quiet in Gadgetzan", not horn4)
local horn5 = sightQuiet("Elwynn Forest", "Lion's Pride Inn", true)
check("quiet in an inn (rest area)", not horn5)
local horn6 = sightQuiet("Tanaris", "Lost Rigger Cove")
check("out in the wild: horn again", horn6)
check("English fallback name works", (function() H.zone, H.subzone = "Tanaris", "Booty Bay" ; return ns.PlaceKind() == "town" end)())
H.inGroup = true
H.sent = {}
H.zone, H.subzone = "Tanaris", "Gadgetzan"
check("no party alert sent from a quiet town", ns.Share:SendSighting(pa) == false and #H.sent == 0)
H.inGroup = false
snd.quietCapitals, snd.quietTowns = false, false
H.zone, H.subzone, H.resting = "Elwynn Forest", "Goldshire", false
resetWorld()

-- ---------------------------------------------------------------------------
say(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
