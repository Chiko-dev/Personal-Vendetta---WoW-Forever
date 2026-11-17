--[[-------------------------------------------------------------------------
  Personal Vendetta -- Share
  Send your hit list to your party or raid. Anyone there running the addon
  is asked whether to import it, told how many of those players are new to
  them, and only the new ones are added. Nobody gets a duplicate.

  Wire format, over addon messages (prefix "PVendetta"):
    O:<sid>:<chunks>:<entries>:<senderGUID>:<senderName>   offer header
    C:<sid>:<n>:<data>                                     chunk n of the payload
  The payload is "V1" then one record per player, records split by ^ and
  fields by ~, with % ~ ^ | and line breaks percent-encoded.

  Messages are paced to Blizzard's addon-message allowance (a short burst,
  then about one a second) and retried when throttled. Everything received
  is treated as untrusted: escape codes and control bytes are stripped and
  every field is checked before it can reach your list.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local PREFIX = "PVendetta"
local CHUNK = 230             -- payload bytes per message; the cap is 255
local BURST = 8               -- messages sent quickly before slowing down
local BURST_GAP, STEADY_GAP = 0.15, 1.05
local THROTTLE_RETRY = 1.5
local MAX_RETRIES = 20
local MAX_CHUNKS = 400
local MAX_ENTRIES = 1000
local SESSION_TTL = 180       -- seconds a half-received share is kept

local Share = {}
ns.Share = Share

local RESULT = {
	SUCCESS = 0, THROTTLE = 3, NOT_IN_GROUP = 5, CHANNEL_THROTTLE = 8, LOCKDOWN = 11,
}
do
	local E = Enum and Enum.SendAddonMessageResult
	if E then
		RESULT.SUCCESS = E.Success or RESULT.SUCCESS
		RESULT.THROTTLE = E.AddonMessageThrottle or RESULT.THROTTLE
		RESULT.NOT_IN_GROUP = E.NotInGroup or RESULT.NOT_IN_GROUP
		RESULT.CHANNEL_THROTTLE = E.ChannelThrottle or RESULT.CHANNEL_THROTTLE
		RESULT.LOCKDOWN = E.AddOnMessageLockdown or RESULT.LOCKDOWN
	end
end

local sending      -- { sid, channel, queue, i, retries, total }
local sessions = {} -- "<sender>:<sid>" -> incoming share

-- ===========================================================================
-- Encoding
-- ===========================================================================

local function enc(s)
	s = tostring(s or "")
	return (string.gsub(s, "[%%~%^|\r\n:]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function dec(s)
	return (string.gsub(s or "", "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end))
end

local function split(s, sep)
	local out, from = {}, 1
	while true do
		local i = string.find(s, sep, from, true)
		if not i then
			out[#out + 1] = string.sub(s, from)
			return out
		end
		out[#out + 1] = string.sub(s, from, i - 1)
		from = i + #sep
	end
end

local function encodeEntry(e)
	return table.concat({
		enc(e.guid), enc(e.name), enc(e.surname), enc(e.level),
		e.levelSkull and "1" or "", enc(e.class), enc(e.className), enc(e.race),
		e.scum and "1" or "", enc(e.note), enc(e.theyKilledMe or 0),
	}, "~")
end

function Share:Encode(entries)
	local parts = { "V1" }
	for _, e in ipairs(entries) do parts[#parts + 1] = encodeEntry(e) end
	return table.concat(parts, "^")
end

-- Untrusted text in, a checked record (or nil) out.
local function checkRecord(fields)
	local guid = dec(fields[1])
	-- Player-<server>-<id>. Letters and digits only past the prefix: strict
	-- enough that nothing odd gets through, loose enough not to lose a GUID
	-- over formatting.
	if guid == "" or #guid > 40 or not string.find(guid, "^Player%-%d+%-%w+$") then guid = nil end

	local name = ns.CleanText(dec(fields[2]), 24)
	local surname = ns.CleanText(dec(fields[3]), 24)
	if not guid and not name then return nil end

	local level = tonumber(dec(fields[4]))
	if level and (level < 1 or level > 100 or level ~= math.floor(level)) then level = nil end

	local class = dec(fields[6])
	if class == "" or #class > 16 or not string.find(class, "^%u+$") then class = nil end

	return {
		guid = guid,
		name = name,
		surname = surname,
		level = level,
		levelSkull = fields[5] == "1" or nil,
		class = class,
		className = ns.CleanText(dec(fields[7]), 24),
		race = ns.CleanText(dec(fields[8]), 24),
		scum = fields[9] == "1" or nil,
		note = ns.CleanText(dec(fields[10]), ns.NOTE_MAX),
		killedSharer = math.max(0, math.min(9999, math.floor(tonumber(dec(fields[11])) or 0))),
	}
end

function Share:Decode(payload)
	if type(payload) ~= "string" then return nil end
	local records = split(payload, "^")
	if records[1] ~= "V1" then return nil end
	local out = {}
	for i = 2, math.min(#records, MAX_ENTRIES + 1) do
		local rec = checkRecord(split(records[i], "~"))
		if rec then out[#out + 1] = rec end
	end
	return out
end

-- ===========================================================================
-- Group
-- ===========================================================================

local function channel()
	local ok, raid = ns.try(IsInRaid)
	if ok and raid == true then return "RAID" end
	local okG, group = ns.try(IsInGroup)
	if okG and group == true then return "PARTY" end
	return nil
end

function Share:CanShare()
	if sending then return false, "Already sharing -- give it a moment." end
	if not channel() then return false, "You need to be in a party or raid." end
	return true
end

-- ===========================================================================
-- Sending
-- ===========================================================================

local function sendRaw(msg, ch)
	local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage
	if not fn then return RESULT.NOT_IN_GROUP end
	local ok, res = pcall(fn, PREFIX, msg, ch)
	if not ok then return -1 end
	if res == nil or res == true then return RESULT.SUCCESS end -- older clients
	if res == false then return -1 end
	return res
end

local pump

local function finishSending(msg)
	if msg then ns.Print(msg) end
	sending = nil
	ns.Fire("GROUP_CHANGED")
end

pump = function()
	local s = sending
	if not s then return end
	local msg = s.queue[s.i]
	if not msg then
		finishSending(string.format("|cff44ff44Hit list shared|r with your %s (%d players).",
			s.channel == "RAID" and "raid" or "party", s.total))
		return
	end

	local res = sendRaw(msg, s.channel)
	if res == RESULT.SUCCESS then
		s.i = s.i + 1
		s.retries = 0
		C_Timer.After(s.i <= BURST and BURST_GAP or STEADY_GAP, pump)
	elseif res == RESULT.THROTTLE or res == RESULT.CHANNEL_THROTTLE then
		s.retries = s.retries + 1
		if s.retries > MAX_RETRIES then
			finishSending("|cffff4444Sharing stopped:|r the game kept throttling messages. Try again in a minute.")
		else
			C_Timer.After(THROTTLE_RETRY, pump)
		end
	elseif res == RESULT.NOT_IN_GROUP then
		finishSending("|cffff4444Sharing stopped:|r you're no longer in a group.")
	elseif res == RESULT.LOCKDOWN then
		finishSending("|cffff4444Sharing stopped:|r addon messages are blocked here right now. Try again out of combat.")
	else
		finishSending("|cffff4444Sharing stopped:|r the game refused the message (code " .. tostring(res) .. ").")
	end
end

function Share:Send()
	local ok, why = self:CanShare()
	if not ok then
		ns.Print(why)
		return false
	end
	local entries = ns.List:ByDateAdded()
	if #entries == 0 then
		ns.Print("Your list is empty -- nothing to share.")
		return false
	end

	local payload = self:Encode(entries)
	local chunks = {}
	for i = 1, #payload, CHUNK do
		chunks[#chunks + 1] = string.sub(payload, i, i + CHUNK - 1)
	end
	if #chunks > MAX_CHUNKS then
		ns.Print("Your list is too long to share in one go.")
		return false
	end

	local sid = string.format("%06x", math.random(0, 0xFFFFFF))
	local _, myGUID = ns.try(UnitGUID, "player")
	local first, last = ns.Radar and ns.Radar.UnitNames("player")
	local queue = {
		string.format("O:%s:%d:%d:%s:%s", sid, #chunks, #entries,
			enc(ns.str(myGUID) or ""), enc(ns.FullName(first, last))),
	}
	for i, data in ipairs(chunks) do
		queue[#queue + 1] = string.format("C:%s:%d:%s", sid, i, data)
	end

	sending = { sid = sid, channel = channel(), queue = queue, i = 1, retries = 0, total = #entries }
	local seconds = math.max(1, math.floor(math.max(0, #queue - BURST) * STEADY_GAP + 0.5))
	ns.Print(string.format("Sharing %d players with your %s%s...", #entries,
		sending.channel == "RAID" and "raid" or "party",
		#queue > BURST and (" (about " .. seconds .. " s)") or ""))
	ns.Fire("GROUP_CHANGED")
	pump()
	return true
end

-- ===========================================================================
-- Receiving
-- ===========================================================================

local importFrame

local function sortNew(list)
	table.sort(list, function(a, b)
		return ns.FullName(a.name, a.surname) < ns.FullName(b.name, b.surname)
	end)
end

-- Split a shared list into players you don't have and ones you do.
function Share:Compare(records)
	local new, known = {}, 0
	for _, r in ipairs(records) do
		local _, existing = ns.List:Find(r.guid, r.name, r.surname)
		if existing then
			known = known + 1
		else
			new[#new + 1] = r
		end
	end
	sortNew(new)
	return new, known
end

-- Add the new ones. Re-checked at click time: the list may have changed
-- while the prompt was open.
function Share:Import(records, from)
	local added = 0
	for _, r in ipairs(records) do
		local _, existing = ns.List:Find(r.guid, r.name, r.surname)
		if not existing then
			local key, entry = ns.List:Upsert(r)
			if entry then
				entry.scum = r.scum
				entry.note = r.note
				entry.sharedBy = from
				entry.sharedKills = r.killedSharer
				entry.lastSeen = nil
				added = added + 1
			end
		end
	end
	if added > 0 then ns.Fire("LIST_CHANGED") end
	return added
end

local function showImport(session, records)
	local new, known = Share:Compare(records)
	local from = session.from

	if #new == 0 then
		ns.Print(string.format("%s shared their hit list: all %d already on yours.", from, #records))
		return
	end

	if not importFrame then
		importFrame = CreateFrame("Frame", "PersonalVendettaImport", UIParent, "BackdropTemplate")
		importFrame:SetSize(380, 210)
		importFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
		importFrame:SetFrameStrata("DIALOG")
		importFrame:SetMovable(true)
		importFrame:EnableMouse(true)
		importFrame:RegisterForDrag("LeftButton")
		importFrame:SetScript("OnDragStart", importFrame.StartMoving)
		importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
		importFrame:SetClampedToScreen(true)
		if importFrame.SetBackdrop then
			importFrame:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 24,
				insets = { left = 6, right = 6, top = 6, bottom = 6 },
			})
		end
		importFrame.title = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		importFrame.title:SetPoint("TOP", 0, -16)
		importFrame.title:SetText("|cff9933ffShared hit list|r")
		importFrame.body = importFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		importFrame.body:SetPoint("TOPLEFT", 20, -44)
		importFrame.body:SetPoint("TOPRIGHT", -20, -44)
		importFrame.body:SetJustifyH("LEFT")
		importFrame.body:SetWordWrap(true)
		importFrame.names = importFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		importFrame.names:SetPoint("TOPLEFT", importFrame.body, "BOTTOMLEFT", 0, -8)
		importFrame.names:SetPoint("TOPRIGHT", importFrame.body, "BOTTOMRIGHT", 0, -8)
		importFrame.names:SetJustifyH("LEFT")
		importFrame.names:SetWordWrap(true)
		importFrame.yes = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
		importFrame.yes:SetSize(150, 22)
		importFrame.yes:SetPoint("BOTTOMLEFT", 20, 18)
		importFrame.no = CreateFrame("Button", nil, importFrame, "UIPanelButtonTemplate")
		importFrame.no:SetSize(110, 22)
		importFrame.no:SetPoint("BOTTOMRIGHT", -20, 18)
		importFrame.no:SetText("No thanks")
		importFrame.no:SetScript("OnClick", function() importFrame:Hide() end)
	end

	importFrame.body:SetText(string.format(
		"|cffffffff%s|r shared their hit list: %d player%s, |cff44ff44%d new to you|r%s.",
		from, #records, #records == 1 and "" or "s", #new,
		known > 0 and (", " .. known .. " already on your list") or ""))

	local preview = {}
	for i = 1, math.min(#new, 8) do
		local r = new[i]
		preview[#preview + 1] = (r.scum and (ns.SKULL .. " ") or "") .. ns.FullName(r.name, r.surname)
	end
	importFrame.names:SetText(table.concat(preview, ", ") .. (#new > 8 and (" and " .. (#new - 8) .. " more") or ""))

	importFrame.yes:SetText("Import " .. #new .. " new")
	importFrame.yes:SetScript("OnClick", function()
		local added = Share:Import(new, from)
		ns.Print(string.format("Imported %d player%s from %s's hit list.", added, added == 1 and "" or "s", from))
		importFrame:Hide()
	end)
	importFrame.pending = new
	importFrame:Show()
end

local function onMessage(prefix, text, _, sender)
	if prefix ~= PREFIX then return end
	text = ns.str(text)
	sender = ns.str(sender) or "Someone"
	if not text then return end

	local now = time()
	for k, s in pairs(sessions) do
		if now - s.started > SESSION_TTL then sessions[k] = nil end
	end

	local kind = string.sub(text, 1, 2)
	if kind == "O:" then
		local sid, n, count, guid, name = string.match(text, "^O:(%x+):(%d+):(%d+):([^:]*):(.*)$")
		n, count = tonumber(n), tonumber(count)
		if not sid or not n or n < 1 or n > MAX_CHUNKS then return end
		local _, myGUID = ns.try(UnitGUID, "player")
		if dec(guid) ~= "" and dec(guid) == ns.str(myGUID) then return end -- our own share
		local display = ns.CleanText(dec(name), 50) or sender
		sessions[sender .. ":" .. sid] = {
			from = display, sid = sid, n = n, count = count or 0,
			chunks = {}, got = 0, started = now,
		}
		ns.Print(string.format("%s is sharing their hit list (%d players)...", display, count or 0))
	elseif kind == "C:" then
		local sid, i, data = string.match(text, "^C:(%x+):(%d+):(.*)$")
		local s = sid and sessions[sender .. ":" .. sid]
		i = tonumber(i)
		if not s or not i or i < 1 or i > s.n or s.chunks[i] then return end
		s.chunks[i] = data
		s.got = s.got + 1
		if s.got == s.n then
			sessions[sender .. ":" .. sid] = nil
			local records = Share:Decode(table.concat(s.chunks))
			if records and #records > 0 then
				showImport(s, records)
			else
				ns.Print(s.from .. " shared a hit list this version can't read.")
			end
		end
	end
end

-- ===========================================================================
-- Events
-- ===========================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		onMessage(...)
	elseif event == "GROUP_ROSTER_UPDATE" then
		ns.Fire("GROUP_CHANGED")
	end
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

-- Test hooks.
Share._onMessage = onMessage
Share._sessions = sessions
Share._sending = function() return sending end
Share.PREFIX = PREFIX
