--[[-------------------------------------------------------------------------
  Personal Vendetta -- Overlay
  The floating window. Collapses to a title bar when nobody from the list is
  near you, and expands with a flash and a sound when someone turns up.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local MAX_ROWS = 10
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 22
local WIDTH = 310

local frame, rows
local pendingFlash = {}

-- ===========================================================================
-- Position
-- ===========================================================================

local function savePosition()
	if not frame then return end
	local point, _, relPoint, x, y = frame:GetPoint()
	ns.db.settings.overlayPoint = { point = point, relPoint = relPoint, x = x, y = y }
end

local function restorePosition()
	local p = ns.db.settings.overlayPoint
	frame:ClearAllPoints()
	if p and p.point then
		frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 300, 80)
	end
end

-- ===========================================================================
-- Flashing
-- Hand-rolled on OnUpdate rather than an AnimationGroup: animation groups
-- are created on frames, not on textures, and this needs no template
-- support from the client at all.
-- ===========================================================================

local FLASH_SECONDS = 2.2
local FLASH_RATE = 1.6
local GLOW_SPEED = 3.2   -- radians per second: a slow, steady throb

-- One OnUpdate per row drives both effects: the short flash when someone
-- appears, and the steady glow a scum keeps for as long as he is near.
-- It switches itself off when neither is running.
local function animate(self)
	local now = GetTime()
	local active = false

	if self.flashUntil then
		if now >= self.flashUntil then
			self.flashUntil = nil
			self.flash:SetAlpha(0)
		else
			local phase = (now * FLASH_RATE) % 1
			local a = (phase < 0.5) and (phase * 2) or ((1 - phase) * 2)
			self.flash:SetAlpha(a * 0.5)
			active = true
		end
	end

	if self.glowing then
		local wave = 0.5 + 0.5 * math.sin(now * GLOW_SPEED)
		self.glow:SetAlpha(0.15 + 0.30 * wave)
		self.edge:SetAlpha(0.6 + 0.4 * wave)
		active = true
	end

	if not active then self:SetScript("OnUpdate", nil) end
end

local function wake(row)
	row:SetScript("OnUpdate", animate)
end

local function startFlash(row)
	row.flashUntil = GetTime() + FLASH_SECONDS
	wake(row)
end

local function setGlow(row, on)
	on = on and true or false
	if (row.glowing or false) == on then return end
	row.glowing = on or nil
	row.glow:SetShown(on)
	row.edge:SetShown(on)
	if on then
		wake(row)
	else
		row.glow:SetAlpha(0)
	end
end

local function stopEffects(row)
	row.flashUntil = nil
	row.flash:SetAlpha(0)
	setGlow(row, false)
	row:SetScript("OnUpdate", nil)
end

local function solidTexture(parent, layer, r, g, b)
	local t = parent:CreateTexture(nil, layer)
	if t.SetColorTexture then
		t:SetColorTexture(r, g, b, 1)
	else
		t:SetTexture("Interface\\Buttons\\WHITE8X8")
		t:SetVertexColor(r, g, b, 1)
	end
	return t
end

-- ===========================================================================
-- Construction
-- ===========================================================================

local function buildRow(index, parent, anchor)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 16, ROW_HEIGHT)
	if anchor then
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
	else
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -HEADER_HEIGHT)
	end

	row.flash = solidTexture(row, "BACKGROUND", 1, 0.15, 0.15)
	row.flash:SetAllPoints()
	row.flash:SetAlpha(0)

	-- Scum glow: an additive red wash plus a bright bar on the left edge.
	row.glow = solidTexture(row, "BORDER", 1, 0.08, 0.05)
	row.glow:SetAllPoints()
	if row.glow.SetBlendMode then row.glow:SetBlendMode("ADD") end
	row.glow:SetAlpha(0)
	row.glow:Hide()

	row.edge = solidTexture(row, "ARTWORK", 1, 0.15, 0.1)
	row.edge:SetPoint("TOPLEFT", -6, 0)
	row.edge:SetPoint("BOTTOMLEFT", -6, 0)
	row.edge:SetWidth(3)
	row.edge:Hide()

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("LEFT", 2, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWidth(166)
	row.name:SetWordWrap(false)

	row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.detail:SetPoint("LEFT", row.name, "RIGHT", 2, 0)
	row.detail:SetJustifyH("LEFT")
	row.detail:SetWidth(74)

	row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.score:SetPoint("RIGHT", -2, 0)
	row.score:SetJustifyH("RIGHT")

	-- Hover for the full picture (note included). Motion only: clicks pass
	-- through to the window, so it still drags from anywhere.
	if row.SetMouseMotionEnabled then row:SetMouseMotionEnabled(true) end
	if row.SetMouseClickEnabled then row:SetMouseClickEnabled(false) end
	row:SetScript("OnEnter", function(self)
		if self.entry and ns.EntryTooltip then ns.EntryTooltip(self, self.entry, "ANCHOR_LEFT") end
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

	row:Hide()
	return row
end

local function buildFrame()
	frame = CreateFrame("Frame", "PersonalVendettaOverlay", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEADER_HEIGHT)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePosition()
	end)
	frame:SetClampedToScreen(true)

	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
		})
		frame:SetBackdropColor(0, 0, 0, 0.55)
		frame:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
	end

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.title:SetPoint("LEFT", 8, 0)
	frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
	frame.title:SetJustifyH("LEFT")

	rows = {}
	for i = 1, MAX_ROWS do
		rows[i] = buildRow(i, frame, rows[i - 1])
	end

	restorePosition()
	return frame
end

-- ===========================================================================
-- Rendering
-- ===========================================================================

local function describe(entry)
	local bits = {}
	if entry.race then bits[#bits + 1] = entry.race end
	if entry.className then bits[#bits + 1] = entry.className end
	return table.concat(bits, " ")
end

-- Level as you should read it right now:
--   white 47   read off them this sighting
--   red ??     10+ levels above you; an old number here would lie
--   grey 47?   last known; the client would not give a fresh one just now
local function levelText(entry, record)
	if entry.levelSkull and record and record.levelFresh then
		return "|cffff3333??|r "
	end
	if not entry.level and not entry.levelSkull then return "" end
	if record and record.levelFresh then
		return "|cffffffff" .. entry.level .. "|r "
	end
	if entry.levelSkull then
		return "|cff996666??|r "
	end
	return "|cff888888" .. entry.level .. "?|r "
end
ns.LevelText = levelText

local function refresh()
	if not frame then return end

	local near = ns.Radar and ns.Radar:GetNearby() or {}
	local total = ns.List:Count()
	local count = ns.Radar and ns.Radar:Count() or 0 -- the living ones

	local scumNear = 0
	for _, record in ipairs(near) do
		if record.entry.scum and not record.dead then scumNear = scumNear + 1 end
	end

	if count > 0 then
		frame.title:SetText(string.format("|cff9933ffVendetta|r  |cffff4444%d near|r%s", count,
			scumNear > 0 and string.format("  %s%s %d scum|r", ns.SKULL, ns.SCUM_COLOR, scumNear) or ""))
		frame:SetBackdropBorderColor(0.9, 0.2, 0.2, 0.95)
	else
		frame.title:SetText(string.format("|cff9933ffVendetta|r  |cff888888%d on the list|r", total))
		frame:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
	end

	local shown = 0
	for i = 1, MAX_ROWS do
		local row = rows[i]
		local record = near[i]
		if record then
			local entry = record.entry
			shown = shown + 1
			if record.dead then
				row.name:SetText(ns.FullName(entry))
				row.name:SetTextColor(0.5, 0.5, 0.5)
				row.detail:SetText("|cff888888dead|r")
				setGlow(row, false)
			else
				local r, g, b = ns.ClassColor(entry.class)
				local skull = entry.scum and (ns.SKULL .. " ") or ""
				row.name:SetText(skull .. levelText(entry, record) .. ns.FullName(entry))
				row.name:SetTextColor(r, g, b)
				row.detail:SetText(describe(entry))
				setGlow(row, entry.scum)
			end
			row.score:SetText(string.format("|cffff6666%d|r/|cff66ff66%d|r",
				entry.theyKilledMe or 0, entry.iKilledThem or 0))
			row.entry = entry
			row:Show()

			if entry.key and pendingFlash[entry.key] then
				pendingFlash[entry.key] = nil
				startFlash(row)
			end
		else
			row.entry = nil
			stopEffects(row)
			row:Hide()
		end
	end

	-- Collapsed when quiet, expanded when there is something to show.
	frame:SetHeight(HEADER_HEIGHT + (shown * ROW_HEIGHT) + (shown > 0 and 6 or 0))
end

local function alert(entries)
	if not entries or #entries == 0 then return end

	local anyScum = false
	for _, entry in ipairs(entries) do
		if entry.key then pendingFlash[entry.key] = true end
		local noteBit = ""
		if entry.note then
			local n = entry.note
			if #n > 60 then n = string.sub(n, 1, 57) .. "..." end
			noteBit = " |cffffd100(" .. n .. ")|r"
		end
		if entry.scum then
			anyScum = true
			ns.Print(string.format("%s %sSCUM %s is near.|r Must kill. %d to %d.%s",
				ns.SKULL, ns.SCUM_COLOR, ns.FullName(entry),
				entry.theyKilledMe or 0, entry.iKilledThem or 0, noteBit))
		else
			ns.Print(string.format("|cffff4444%s|r is near. %d to %d.%s",
				ns.FullName(entry), entry.theyKilledMe or 0, entry.iKilledThem or 0, noteBit))
		end
	end

	-- One horn per batch: the scum one wins if any of them is scum.
	if ns.Sound then ns.Sound:Play(anyScum and "scum" or "normal") end

	refresh()
end

-- Build on demand, and never let a UI failure take the commands down with it.
local function ensureFrame()
	if frame then return true end
	local ok, err = pcall(buildFrame)
	if not ok then
		ns.Print("|cffff4444could not build the window:|r " .. tostring(err))
		ns.Print("The list and the tracking still work. |cffffd100/vendetta list|r shows it in chat.")
		return false
	end
	return true
end

local function toggle(show)
	if not ensureFrame() then return end
	if show == nil then show = not frame:IsShown() end
	frame:SetShown(show)
	ns.db.settings.overlayShown = show
	if show then refresh() end
	ns.Fire("SETTINGS_CHANGED")
end

-- ===========================================================================
-- Slash commands
-- ===========================================================================

local function printList()
	local entries = ns.List:ByDateAdded()
	if #entries == 0 then
		ns.Print("The list is empty. Go get killed by someone.")
		return
	end
	ns.Print("Hit list, newest first:")
	for _, e in ipairs(entries) do
		local nearNow = ns.Radar and ns.Radar.nearby[e.key]
		local name = ns.FullName(e)
		if e.scum then name = ns.SKULL .. ns.SCUM_COLOR .. name .. "|r" end
		print(string.format("  |cffff6666%d|r/|cff66ff66%d|r  %s %s%s  |cff888888%s|r",
			e.theyKilledMe or 0, e.iKilledThem or 0,
			name,
			levelText(e, nearNow),
			e.className and (" " .. e.className) or "",
			nearNow and "|cffff4444<< NEAR|r" or ("seen " .. ns.Ago(e.lastSeen))))
	end
end

-- "Not on the list", or -- when a first name fits two people -- ask for the surname.
local function notFound(arg, count)
	if count and count > 1 then
		ns.Print(string.format("%d people on your list are called %s. Use the full name, e.g. "
			.. "|cffffd100%s Surname|r.", count, arg, arg))
	else
		ns.Print("Not on the list: " .. arg)
	end
end

local function handleCommand(msg)
	local cmd, arg = string.match(msg or "", "^(%S*)%s*(.-)$")
	cmd = string.lower(cmd or "")

	if cmd == "" or cmd == "show" or cmd == "toggle" then
		toggle()
	elseif cmd == "list" then
		printList()
	elseif cmd == "add" then
		if arg == "" then
			-- No name: add whoever you have targeted, with everything we can read.
			if not (ns.Radar and ns.Radar.IsEnemyPlayer("target")) then
				ns.Print("Target an enemy player, or use |cffffd100/vendetta add <first> <surname>|r.")
				return
			end
			local info = ns.Radar:ReadUnitInfo("target")
			local _, existing = ns.List:Find(info.guid, info.name, info.surname)
			if existing then
				ns.Print(ns.FullName(existing) .. " is already on the list.")
				return
			end
			local entry = ns.List:AddFromFight(info)
			if entry then ns.Print("Added |cffff4444" .. ns.FullName(entry) .. "|r from your target.") end
			return
		end
		local _, existing = ns.List:Find(nil, arg)
		if existing then
			ns.Print(ns.FullName(existing) .. " is already on the list.")
			return
		end
		local _, entry = ns.List:Upsert({ name = arg })
		if entry then
			ns.Print("Added |cffff4444" .. ns.FullName(entry) .. "|r by hand.")
			ns.Fire("LIST_CHANGED")
		end
	elseif cmd == "remove" or cmd == "forgive" then
		if arg == "" then
			ns.Print("Usage: /vendetta remove <name>")
			return
		end
		local _, entry, count = ns.List:Find(nil, arg)
		if not entry then
			notFound(arg, count)
			return
		end
		local full = ns.FullName(entry)
		ns.List:Remove(entry.guid, full)
		ns.Print("Removed " .. full .. ". Generous of you.")
	elseif cmd == "share" then
		if ns.Share then ns.Share:Send() end
	elseif cmd == "recap" then
		ns.Deaths.ReadNow()
	elseif cmd == "range" then
		if not ns.Radar then
			ns.Print("|cffff4444Radar.lua did not load|r -- check it is in the folder and listed in the .toc.")
			return
		end
		local n = tonumber(arg)
		if not n then
			ns.Print("Radar range is " .. ns.Radar:GetRange() .. " yards. Usage: /vendetta range 41")
		else
			ns.Radar:SetRange(n)
		end
	elseif cmd == "debug" then
		ns.Print("v" .. ns.VERSION .. " status:")
		print("  Core    " .. (ns.db and "|cff44ff44loaded|r" or "|cffff4444no database|r"))
		print("  Deaths  " .. (ns.Deaths and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Prompt  " .. (ns.Prompt and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Radar   " .. (ns.Radar and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Kills   " .. (ns.Kills and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Fights " .. (ns.Fights and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Notes " .. (ns.Notes and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Share " .. (ns.Share and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Sound   " .. (ns.Sound and ("|cff44ff44loaded|r, "
			.. ns.Sound:Current("normal").label .. " " .. math.floor(ns.Sound:Volume("normal") * 100 + 0.5) .. "%, scum "
			.. ns.Sound:Current("scum").label .. " " .. math.floor(ns.Sound:Volume("scum") * 100 + 0.5) .. "%")
			or "|cffff4444MISSING|r"))
		print("  Plates  " .. (ns.Radar and (ns.Radar:NameplatesOn() and "|cff44ff44on|r" or "|cffff4444OFF|r") or "?"))
		print("  Options " .. (ns.Settings and "|cff44ff44loaded|r" or "|cffff4444MISSING|r")
			.. "   Minimap " .. (ns.Minimap and "|cff44ff44loaded|r" or "|cffff4444MISSING|r"))
		print("  Window  " .. (frame and "|cff44ff44built|r" or "|cffffd100not built yet|r"))
		print("  Recap   " .. ((C_DeathRecap and C_DeathRecap.GetRecapEvents)
			and "|cff44ff44available|r" or "|cffff4444MISSING|r"))
		print("  List    " .. ns.List:Count() .. " entries, "
			.. (ns.Radar and ns.Radar:Count() or 0) .. " near")
		print("  Range   " .. (ns.Radar and ns.Radar:GetRange() or "?") .. " yards")
	elseif cmd == "sound" then
		local s = ns.db.settings.sound
		s.enabled = not s.enabled
		ns.Print("Sighting sound " .. (s.enabled and "on" or "off") .. ".")
		ns.Fire("SETTINGS_CHANGED")
	elseif cmd == "options" or cmd == "config" or cmd == "settings" then
		ns.Settings:Toggle()
	elseif cmd == "nameplates" or cmd == "np" then
		ns.Radar:EnableNameplates()
	elseif cmd == "scum" or cmd == "unscum" then
		if arg == "" then
			ns.Print("Usage: /vendetta " .. cmd .. " <name>")
			return
		end
		local key, entry, count = ns.List:Find(nil, arg)
		if not entry then
			notFound(arg, count)
			return
		end
		ns.List:SetScum(key, cmd == "scum")
		ns.Print(string.format("%s is %s.", ns.FullName(entry),
			cmd == "scum" and (ns.SCUM_COLOR .. "scum|r now") or "no longer scum"))
	elseif cmd == "kill" or cmd == "unkill" or cmd == "death" or cmd == "undeath" then
		-- Hand corrections, for when detection misses one or double counts.
		if arg == "" then
			ns.Print("Usage: /vendetta " .. cmd .. " <name>")
			return
		end
		local field = (cmd == "kill" or cmd == "unkill") and "iKilledThem" or "theyKilledMe"
		local delta = (cmd == "kill" or cmd == "death") and 1 or -1
		local entry, count = ns.List:Adjust(arg, field, delta)
		if entry then
			ns.Print(string.format("%s: now %d to %d.", ns.FullName(entry),
				entry.theyKilledMe or 0, entry.iKilledThem or 0))
		else
			notFound(arg, count)
		end
	elseif cmd == "note" then
		local _, entry, count = ns.List:Find(nil, arg)
		if not entry then
			if arg == "" then ns.Print("Usage: /vendetta note <name>") else notFound(arg, count) end
			return
		end
		ns.Notes:Open(entry.key)
	elseif cmd == "wipe" then
		if arg == "confirm" then
			ns.List:Wipe()
			ns.Print("List wiped.")
		else
			ns.Print("This clears everyone. Type |cffffd100/vendetta wipe confirm|r if you mean it.")
		end
	else
		ns.Print("Commands:")
		print("  |cffffd100/vendetta|r  toggle the window")
		print("  |cffffd100/vendetta list|r  print the list, marking who is near")
		print("  |cffffd100/vendetta add|r  add your current target")
		print("  |cffffd100/vendetta add <first> <surname>|r  add someone by name")
		print("  |cffffd100/vendetta remove <name>|r  take someone off")
		print("  |cffffd100/vendetta note <name>|r  write a note on someone")
		print("  |cffffd100/vendetta share|r  share your list with your party")
		print("  |cffffd100/vendetta recap|r  re-read your last death")
		print("  |cffffd100/vendetta options|r  open settings (or click the minimap skull)")
		print("  |cffffd100/vendetta kill <name>|r / |cffffd100unkill|r  fix your kill count by hand")
		print("  |cffffd100/vendetta death <name>|r / |cffffd100undeath|r  fix their kill count by hand")
		print("  |cffffd100/vendetta scum <name>|r / |cffffd100unscum|r  mark or clear scum")
		print("  |cffffd100/vendetta nameplates|r  switch on the enemy nameplates the radar needs")
		print("  |cffffd100/vendetta range [n]|r  show or push nameplate radar range")
		print("  |cffffd100/vendetta sound|r  toggle the sighting sounds")
		print("  |cffffd100/vendetta debug|r  what loaded and what did not")
		print("  |cffffd100/vendetta wipe confirm|r  clear everyone")
	end
end

SLASH_PERSONALVENDETTA1 = "/vendetta"
SLASH_PERSONALVENDETTA2 = "/pv"
SlashCmdList.PERSONALVENDETTA = handleCommand

-- ===========================================================================
-- Wiring
-- ===========================================================================

ns.On("DB_READY", function()
	toggle(ns.db.settings.overlayShown ~= false)
end)

ns.On("LIST_CHANGED", refresh)
ns.On("RADAR_CHANGED", refresh)
ns.On("SIGHTED", alert)

ns.Overlay = { Toggle = toggle, Refresh = refresh }
