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
		local file = string.match(line, "^%s*([%w_]+%.lua)%s*$")
		if file then FILES[#FILES + 1] = file end
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
check("name index cleaned", ns.db.nameIndex["latecomer"] == nil)

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
section("Prompt and commands")
ns.Prompt.Show({ { name = "Testguy", guid = "Player-1-TEST", certain = true } })
check("button reads Close", _G.PersonalVendettaPrompt.close:GetText() == "Close",
	_G.PersonalVendettaPrompt.close:GetText())
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

-- ---------------------------------------------------------------------------
section("Scum: ticked in the death prompt")
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
local prows = ns.Prompt._rows()
check("prompt has a Scum box on each row", prows[1].scum ~= nil and prows[2].scum ~= nil)
check("Scum starts unticked", not prows[1].scum:GetChecked() and not prows[2].scum:GetChecked())
local first = (prows[1].label:GetText() or ""):find("Gankmaster") and 1 or 2
local second = 3 - first
prows[first].scum:SetChecked(true)
prows[first].add:Click()
prows[second].add:Click()
local _, gank = ns.List:Find(nil, "Gankmaster")
local _, fair = ns.List:Find(nil, "Fairfighter")
check("ticked one added as scum", gank and gank.scum == true)
check("unticked one added as normal", fair and not fair.scum)
check("rows lock after Add", not prows[first].scum:IsEnabled() and not prows[first].add:IsEnabled())

-- A second prompt must not inherit the old tick.
H.now = H.now + 600
H.recap = {
	{ sourceName = "Newbie", sourceGUID = "Player-4710-000NEW01",
	  spellName = "Wrath", spellId = 5176, amount = 200, overkill = 10,
	  event = "SPELL_DAMAGE", timestamp = H.now },
}
H.fire("PLAYER_DEAD")
H.runTimers(0.2)
check("fresh prompt resets Scum", not ns.Prompt._rows()[1].scum:GetChecked())
check("fresh prompt re-enables Scum", ns.Prompt._rows()[1].scum:IsEnabled())
ns.Prompt.Close()

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
check("chat calls him scum", H.outputContains("SCUM Gankmaster"))
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
check("toc version 1.0", toc:find("## Version: 1.0", 1, true) ~= nil)
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

-- ---------------------------------------------------------------------------
say(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
