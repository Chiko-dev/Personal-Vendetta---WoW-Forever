--[[-------------------------------------------------------------------------
  Personal Vendetta -- Pending
  The review queue behind the floating window's "To add" tab. Nothing pops
  up: players who kill you, and players you survive a fight with, wait here
  until you have a quiet moment to Add or Skip them.

  One item per player. If the same person kills you twice before you get
  round to it, that is one item that says "killed you x2", and Add counts
  both. Scum and a note can be set while they wait and carry over on Add.
  The queue is saved, so a /reload or a logout does not lose anyone.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local MAX_ITEMS = 40   -- oldest are dropped beyond this

local Pending = {}
ns.Pending = Pending

local nextId = 1

local function items()
	ns.db.pending = ns.db.pending or {}
	return ns.db.pending
end

local function keyOf(c)
	if c.guid then return c.guid end
	if c.name then return "name:" .. string.lower(ns.FullName(c.name, c.surname)) end
	return nil
end

local function findItem(c)
	local key = keyOf(c)
	for i, it in ipairs(items()) do
		if key and it.key == key then return it, i end
		-- A name-only item learns its GUID later, or vice versa.
		if c.guid and it.guid == c.guid then return it, i end
		if not c.guid and not it.guid and c.name and it.name
			and string.lower(ns.FullName(c.name, c.surname)) == string.lower(ns.FullName(it.name, it.surname)) then
			return it, i
		end
	end
	return nil
end

function Pending:Get(id)
	for i, it in ipairs(items()) do
		if it.id == id then return it, i end
	end
	return nil
end

-- Newest activity first.
function Pending:List()
	local t = {}
	for _, it in ipairs(items()) do t[#t + 1] = it end
	table.sort(t, function(a, b)
		if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
		return a.id > b.id
	end)
	return t
end

function Pending:Count() return #items() end

-- ===========================================================================
-- Undo, in place: a player you just added or skipped keeps their row for a
-- few seconds, with Undo where Add was. No pop-up in the middle of the screen.
-- ===========================================================================

Pending.UNDO_SECONDS = 10
local recent = {}   -- newest first: { rid, label, kind, undo, expires }
local nextRid = 1

local function pruneRecent()
	local now = GetTime()
	for i = #recent, 1, -1 do
		if recent[i].expires <= now then table.remove(recent, i) end
	end
end

local function pushRecent(label, kind, undo)
	local r = { rid = nextRid, label = label, kind = kind, undo = undo,
		expires = GetTime() + Pending.UNDO_SECONDS }
	nextRid = nextRid + 1
	table.insert(recent, 1, r)
	while #recent > 6 do table.remove(recent) end
	if C_Timer and C_Timer.After then
		C_Timer.After(Pending.UNDO_SECONDS + 0.1, function()
			pruneRecent()
			ns.Fire("PENDING_CHANGED")
		end)
	end
	return r
end

-- Rows that can still be undone, newest first.
function Pending:Recent()
	pruneRecent()
	return recent
end

function Pending:ClearRecent()
	for i = #recent, 1, -1 do recent[i] = nil end
end

function Pending:Undo(rid)
	pruneRecent()
	for i, r in ipairs(recent) do
		if r.rid == rid then
			table.remove(recent, i)
			r.undo()
			ns.Fire("PENDING_CHANGED")
			return true
		end
	end
	return false
end

function Pending:UnseenCount()
	local n = 0
	for _, it in ipairs(items()) do if not it.seen then n = n + 1 end end
	return n
end

-- quiet: called from inside a redraw, so don't announce a change that
-- would trigger another redraw.
function Pending:MarkAllSeen(quiet)
	local changed = false
	for _, it in ipairs(items()) do
		if not it.seen then it.seen = true ; changed = true end
	end
	if changed and not quiet then ns.Fire("PENDING_CHANGED") end
end

-- ===========================================================================
-- Arriving
-- ===========================================================================

local INFO_FIELDS = { "guid", "name", "surname", "level", "levelSkull", "class", "className", "race" }

-- mode: "death" (they killed you), "fight" (you survived), "recap" (re-read
-- of a death already counted: adds the player if missing, counts nothing).
-- Returns the item, and whether it is new.
function Pending:Offer(c, mode)
	if not c or not (c.guid or c.name) then return nil end
	local _, onList = ns.List:Find(c.guid, c.name, c.surname)
	if onList then return nil end

	local it = findItem(c)
	local isNew = not it
	if isNew then
		it = {
			id = nextId, deaths = 0, killingBlows = 0, fights = 0, kills = 0,
			at = time(),
		}
		nextId = nextId + 1
		items()[#items() + 1] = it
	end

	for _, f in ipairs(INFO_FIELDS) do
		if c[f] ~= nil then it[f] = c[f] end
	end
	if c.level then it.levelSkull = nil end
	it.key = keyOf(it)

	if mode == "death" or (mode == "recap" and isNew) then
		it.deaths = it.deaths + 1
		if c.killingBlow then it.killingBlows = it.killingBlows + 1 end
		if c.gank then it.gank = true end
		if c.certain == false then it.uncertain = true end
	elseif mode == "fight" then
		it.fights = it.fights + 1
		if c.killedByMe then it.kills = it.kills + 1 end
	end

	-- Their own little history, handed to the list entry on Add.
	local event = (mode == "death" or (mode == "recap" and isNew)) and "died"
		or (mode == "fight" and (c.killedByMe and "killed" or "fought")) or nil
	if event then
		it.events = it.events or {}
		local ev = { t = time(), e = event, z = ns.Zone(), xy = ns.Coords(), lv = c.level }
		if event == "died" then
			ev.sp = ns.str(c.spell)
			ev.kb = c.killingBlow and true or nil
			ev.n = c.n
		end
		it.events[#it.events + 1] = ev
		while #it.events > 20 do table.remove(it.events, 1) end
	end

	it.last = time()
	it.seen = false
	return it, isNew
end

-- A batch from one death or one fight.
function Pending:OfferBatch(candidates, mode)
	local added = {}
	local gank = mode == "death" and #candidates > 1
	for _, c in ipairs(candidates) do
		if gank then c.gank = true end
		local it = self:Offer(c, mode)
		if it then added[#added + 1] = it end
	end

	-- Keep the queue bounded: drop the oldest activity.
	local all = items()
	if #all > MAX_ITEMS then
		-- Newest first; ids break ties, since time() only counts whole seconds.
		table.sort(all, function(a, b)
			if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
			return a.id > b.id
		end)
		for i = #all, MAX_ITEMS + 1, -1 do all[i] = nil end
	end

	if #added > 0 then
		ns.Fire("PENDING_CHANGED", added)
	end
	return added
end

-- ===========================================================================
-- Acting
-- ===========================================================================

local function remove(id)
	local it, i = Pending:Get(id)
	if i then table.remove(items(), i) end
	return it
end

-- Put them on the list. Counts carry over: their kills on you, yours on
-- them, the scum mark and the note.
function Pending:Add(id, quiet)
	if not self:Get(id) then return nil end
	-- An open note for this player is saved and closed first, so the text
	-- goes onto the list with them.
	if ns.Notes and ns.Notes.CommitPending then ns.Notes:CommitPending(id) end
	local it = self:Get(id)
	if not it then return nil end

	local snap = ns.CopyTable(it)
	local info = {}
	for _, f in ipairs(INFO_FIELDS) do info[f] = it[f] end
	local beforeKey, before = ns.List:Find(info.guid, info.name, info.surname)
	before = before and ns.CopyTable(before)
	local key, entry = ns.List:Upsert(info)
	remove(id)
	if not entry then
		ns.Fire("PENDING_CHANGED")
		return nil
	end

	entry.theyKilledMe = (entry.theyKilledMe or 0) + (it.deaths or 0)
	entry.iKilledThem = (entry.iKilledThem or 0) + (it.kills or 0)
	if (it.deaths or 0) > 0 then entry.lastKilledMe = it.last end
	if (it.kills or 0) > 0 then entry.lastIKilledThem = it.last end
	entry.lastSeen = math.max(entry.lastSeen or 0, it.last or 0)
	if it.scum then entry.scum = true end
	if it.note then entry.note = ns.CleanText(it.note, ns.NOTE_MAX) end
	if (it.kills or 0) > 0 and (it.deaths or 0) == 0 then entry.streak = it.kills end
	if (it.deaths or 0) > 0 then entry.streak = 0 end
	if it.events then
		entry.history = entry.history or {}
		for _, h in ipairs(it.events) do entry.history[#entry.history + 1] = ns.CopyTable(h) end
		table.sort(entry.history, function(a, b) return (a.t or 0) < (b.t or 0) end)
		if it.events[#it.events].z then entry.lastZone = it.events[#it.events].z end
	end

	entry._undoAdd = function()
		if before then
			ns.ListData()[beforeKey] = before
			ns.List:Reindex()
			ns.Fire("LIST_CHANGED")
		else
			ns.List:RemoveKey(key)
		end
		Pending:Restore({ snap })
	end

	if not quiet then
		local undoFn = entry._undoAdd
		pushRecent(string.format(L["Added %s."], ns.FullName(entry)), "added", undoFn)
		local name = ns.FullName(entry)
		if entry.scum then
			ns.Print(string.format(L["%s added to the list as scum."], ns.SCUM_COLOR .. name .. "|r"))
		else
			ns.Print(string.format(L["%s added to the list."], "|cffff4444" .. name .. "|r"))
		end
	end
	local undoAdd = entry._undoAdd
	entry._undoAdd = nil
	ns.Fire("LIST_CHANGED")
	ns.Fire("PENDING_CHANGED")
	return entry, undoAdd
end

-- Put skipped players back, for Undo.
function Pending:Restore(snapshots)
	for _, snap in ipairs(snapshots or {}) do
		if not self:Get(snap.id) then
			local _, onList = ns.List:Find(snap.guid, snap.name, snap.surname)
			if not onList then
				items()[#items() + 1] = ns.CopyTable(snap)
				if ns.Fights and ns.Fights.Forget then ns.Fights:Forget(snap.key) end
			end
		end
	end
	ns.Fire("PENDING_CHANGED")
end

-- Let them go. Someone you only fought is not offered again for a while.
-- quiet: no Undo row of its own (Skip all keeps one for the lot).
function Pending:Skip(id, quiet)
	if ns.Notes and ns.Notes.ClosePending then ns.Notes:ClosePending(id) end
	local it = remove(id)
	if not it then return end
	if (it.fights or 0) > 0 and ns.Fights then ns.Fights:Remember({ key = it.key }) end
	ns.Fire("PENDING_CHANGED")
	if not quiet then
		local snap = ns.CopyTable(it)
		pushRecent(string.format(L["Skipped %s."], ns.FullName(it.name, it.surname)), "skipped", function()
			Pending:Restore({ snap })
		end)
		ns.Fire("PENDING_CHANGED")
	end
	return it
end

function Pending:AddAll()
	local n, undos = 0, {}
	for _, it in ipairs(self:List()) do
		local entry, undo = self:Add(it.id, true)
		if entry then
			n = n + 1
			undos[#undos + 1] = undo
		end
	end
	if n > 0 then
		ns.Print(string.format(L["Players added to the list: %d"], n))
		pushRecent(string.format(L["Added %d players."], n), "added", function()
			for i = #undos, 1, -1 do undos[i]() end
		end)
		ns.Fire("PENDING_CHANGED")
	end
	return n
end

function Pending:SkipAll()
	local snaps = {}
	for _, it in ipairs(self:List()) do
		local gone = self:Skip(it.id, true)
		if gone then snaps[#snaps + 1] = ns.CopyTable(gone) end
	end
	if #snaps > 0 then
		pushRecent(string.format(L["Skipped %d players."], #snaps), "skipped", function()
			Pending:Restore(snaps)
		end)
		ns.Fire("PENDING_CHANGED")
	end
end

function Pending:SetScum(id, on)
	local it = self:Get(id)
	if not it then return end
	it.scum = on and true or nil
	ns.Fire("PENDING_CHANGED")
end

function Pending:SetNote(id, text)
	local it = self:Get(id)
	if not it then return end
	it.note = ns.CleanText(text, ns.NOTE_MAX)
	ns.Fire("PENDING_CHANGED")
end

-- "Killed you x2 (killing blow) - gank - you killed them"
function Pending:Describe(it)
	local bits = {}
	if (it.deaths or 0) > 0 then
		local s = "|cffff6666" .. L["Killed you"] .. (it.deaths > 1 and (" x" .. it.deaths) or "") .. "|r"
		if (it.killingBlows or 0) > 0 then s = s .. " |cffffd100(" .. L["killing blow"] .. ")|r" end
		bits[#bits + 1] = s
		if it.gank then bits[#bits + 1] = L["gank"] end
	end
	if (it.fights or 0) > 0 and (it.deaths or 0) == 0 then
		bits[#bits + 1] = L["Fought you"] .. (it.fights > 1 and (" x" .. it.fights) or "")
	end
	if (it.kills or 0) > 0 then
		bits[#bits + 1] = "|cff66ff66" .. L["you killed them"] .. (it.kills > 1 and (" x" .. it.kills) or "") .. "|r"
	end
	if it.uncertain then bits[#bits + 1] = "|cff888888" .. L["unconfirmed"] .. "|r" end
	return table.concat(bits, " |cff666666-|r ")
end

function ns.PendingTooltip(owner, it, anchor)
	if not GameTooltip or not it then return end
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
	local r, g, b = ns.ClassColor(it.class)
	GameTooltip:AddLine((it.scum and (ns.SKULL .. " ") or "") .. ns.FullName(it.name, it.surname), r, g, b)
	local bits = {}
	if it.levelSkull then bits[#bits + 1] = L["Level ??"]
	elseif it.level then bits[#bits + 1] = string.format(L["Level %d"], it.level) end
	if it.race then bits[#bits + 1] = it.race end
	if it.className then bits[#bits + 1] = it.className end
	if #bits > 0 then GameTooltip:AddLine(table.concat(bits, " "), 0.8, 0.8, 0.8) end
	GameTooltip:AddLine(Pending:Describe(it), 1, 1, 1, true)
	GameTooltip:AddLine(string.format(L["Waiting since %s"], ns.Ago(it.at)), 0.6, 0.6, 0.6)
	if it.note then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(it.note, 1, 0.82, 0.3, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Not on your list yet. Add or Skip them here."], 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

-- ===========================================================================
-- Wiring
-- ===========================================================================

-- Deaths and fights hand their candidates here instead of to a popup.
ns.On("OFFER_CANDIDATES", function(candidates, mode)
	if not candidates or #candidates == 0 then return end
	local added = Pending:OfferBatch(candidates, mode)
	if #added == 0 or mode == "recap" then return end

	local names = {}
	for i = 1, math.min(#added, 3) do names[i] = ns.FullName(added[i].name, added[i].surname) end
	local more = #added > 3 and (" " .. string.format(L["and %d more"], #added - 3)) or ""
	local where = (ns.db.settings.overlayShown ~= false)
		and L["Review them in the To add tab of the Vendetta window."]
		or L["Type /vendetta review to open them."]
	ns.Print(string.format(L["%s waiting to be added."], table.concat(names, ", ") .. more) .. " " .. where)
end)

-- Someone added another way (a command, sharing) leaves the queue.
ns.On("LIST_CHANGED", function()
	if not ns.db or not ns.db.pending then return end
	local changed = false
	for i = #ns.db.pending, 1, -1 do
		local it = ns.db.pending[i]
		local _, onList = ns.List:Find(it.guid, it.name, it.surname)
		if onList then
			table.remove(ns.db.pending, i)
			changed = true
		end
	end
	if changed then ns.Fire("PENDING_CHANGED") end
end)

ns.On("DB_READY", function()
	-- Continue ids after whatever was saved.
	for _, it in ipairs(items()) do
		if (it.id or 0) >= nextId then nextId = it.id + 1 end
	end
end)
