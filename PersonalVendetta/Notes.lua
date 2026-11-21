--[[-------------------------------------------------------------------------
  Personal Vendetta -- Notes
  What this person did. A short note per player, written by hand or built
  from preset buttons ("Ganked while leveling", "While low HP", "2v1"...).

  Also home to the player tooltip used by the hit list and the floating
  window, since the note is the heart of it.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local WIDTH = 440
local EDIT_W, EDIT_H = WIDTH - 52, 84

-- The quick-add buttons, in the order they appear.
local PRESETS = {
	"Ganked while leveling",
	"While low HP",
	"While eating/drinking",
	"While fighting a mob",
	"During an escort quest",
	"While AFK",
	"Corpse camped",
	"Max level on a lowbie",
	"2v1",
	"3v1",
	"4v1+",
}

local Notes = { presets = PRESETS }
ns.Notes = Notes

local frame, edit, counter, titleText
local editingKey      -- a hit-list key, or "pending:<id>" for a queued player
local onSave          -- what Save does with the text

-- ===========================================================================
-- The player tooltip (hit list rows, floating window rows)
-- ===========================================================================

function ns.EntryTooltip(owner, entry, anchor)
	if not GameTooltip or not entry then return end
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")

	local r, g, b = ns.ClassColor(entry.class)
	GameTooltip:AddLine((entry.scum and (ns.SKULL .. " ") or "") .. ns.FullName(entry), r, g, b)

	local bits = {}
	if entry.levelSkull then bits[#bits + 1] = L["Level ??"]
	elseif entry.level then bits[#bits + 1] = string.format(L["Level %d"], entry.level) end
	if entry.race then bits[#bits + 1] = entry.race end
	if entry.className then bits[#bits + 1] = entry.className end
	if #bits > 0 then GameTooltip:AddLine(table.concat(bits, " "), 0.8, 0.8, 0.8) end

	GameTooltip:AddLine("|cffff6666" .. string.format(L["Killed you %d"], entry.theyKilledMe or 0) .. "|r   |cff66ff66"
		.. string.format(L["You killed them %d"], entry.iKilledThem or 0) .. "|r")
	GameTooltip:AddLine(string.format(L["Added %s, last seen %s"], ns.Ago(entry.firstAdded), ns.Ago(entry.lastSeen)),
		0.6, 0.6, 0.6)
	if entry.sharedBy then
		local killed = (entry.sharedKills or 0) > 0
			and (" " .. string.format(L["(killed them: %d)"], entry.sharedKills)) or ""
		GameTooltip:AddLine(string.format(L["Shared by %s"], entry.sharedBy) .. killed, 0.6, 0.6, 0.9)
	end
	if entry.scum then
		GameTooltip:AddLine(ns.SCUM_COLOR .. L["Scum: must kill on sight."] .. "|r")
	end
	if entry.note then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(entry.note, 1, 0.82, 0.3, true)
	end
	GameTooltip:Show()
end

-- ===========================================================================
-- Editor
-- ===========================================================================

local function trim(s)
	s = string.gsub(s or "", "^%s+", "")
	return (string.gsub(s, "%s+$", ""))
end

local function updateCounter()
	local n = #(edit:GetText() or "")
	counter:SetText(n .. " / " .. ns.NOTE_MAX)
	if n >= ns.NOTE_MAX then
		counter:SetTextColor(1, 0.3, 0.3)
	else
		counter:SetTextColor(0.6, 0.6, 0.6)
	end
end

-- Add a preset phrase, comma-separated, once.
function Notes:Append(text)
	if not edit then return false end
	local cur = trim(edit:GetText())
	text = L[text]
	if string.find(string.lower(cur), string.lower(text), 1, true) then return false end
	local new = (cur == "") and text or (cur .. ", " .. text)
	if #new > ns.NOTE_MAX then
		counter:SetTextColor(1, 0.3, 0.3)
		return false
	end
	edit:SetText(new)
	if edit.SetCursorPosition then edit:SetCursorPosition(#new) end
	updateCounter()
	return true
end

local function save()
	if onSave then onSave(edit:GetText()) end
	frame:Hide()
end

local function button(parent, label, w, h)
	return ns.Skin.Button(parent, label, w, h or 22, (h or 22) < 22)
end

local function build()
	frame = ns.Skin.Window("PersonalVendettaNotes", WIDTH, 300, L["Note"], ns.ICON)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")

	titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleText:SetPoint("TOPLEFT", 66, -32)
	titleText:SetPoint("TOPRIGHT", -22, -32)
	titleText:SetJustifyH("LEFT")
	titleText:SetWordWrap(false)

	-- Text box with its own border.
	local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	box:SetSize(EDIT_W + 12, EDIT_H + 12)
	box:SetPoint("TOPLEFT", 20, -66)
	ns.Skin.Panel(box, "TooltipDefaultLayout", 0.75)

	edit = CreateFrame("EditBox", nil, box)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject("ChatFontNormal")
	edit:SetMaxLetters(ns.NOTE_MAX)
	edit:SetSize(EDIT_W, EDIT_H)
	edit:SetPoint("TOPLEFT", 6, -6)
	edit:SetTextInsets(0, 0, 0, 0)
	edit:SetScript("OnEscapePressed", function() frame:Hide() end)
	edit:SetScript("OnTextChanged", updateCounter)
	-- Clicking anywhere in the box puts the cursor in it.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() edit:SetFocus() end)

	counter = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	counter:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -3)

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	hint:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -18)
	hint:SetText(L["Quick add"])

	-- Preset buttons, flowed into rows that fit the width.
	local x, y = 0, 0
	local maxW = EDIT_W + 12
	local lastRowBottom
	frame.presetButtons = {}
	for _, text in ipairs(PRESETS) do
		local b = button(frame, L[text], 10, 20)
		local fs = b.GetFontString and b:GetFontString()
		local w = (fs and fs.GetStringWidth and fs:GetStringWidth() or (#text * 6)) + 22
		b:SetWidth(w)
		if x > 0 and x + w > maxW then
			x = 0
			y = y + 24
		end
		b:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", x, -6 - y)
		x = x + w + 4
		b:SetScript("OnClick", function() Notes:Append(text) end)
		frame.presetButtons[#frame.presetButtons + 1] = b
		lastRowBottom = y
	end

	local saveB = button(frame, L["Save"], 90)
	local clearB = button(frame, L["Clear"], 90)
	local cancelB = button(frame, L["Cancel"], 90)
	cancelB:SetPoint("BOTTOMRIGHT", -20, 18)
	saveB:SetPoint("RIGHT", cancelB, "LEFT", -6, 0)
	clearB:SetPoint("BOTTOMLEFT", 20, 18)
	saveB:SetScript("OnClick", save)
	cancelB:SetScript("OnClick", function() frame:Hide() end)
	clearB:SetScript("OnClick", function()
		edit:SetText("")
		updateCounter()
		edit:SetFocus()
	end)
	frame.saveButton, frame.clearButton = saveB, clearB

	-- Height: header + box + label + preset rows + buttons.
	frame:SetHeight(66 + EDIT_H + 12 + 40 + (lastRowBottom or 0) + 20 + 56)
	frame:SetScript("OnHide", function() editingKey, onSave = nil, nil ; edit:ClearFocus() end)
	return frame
end

-- Beside the window it was opened from: over the main window's player
-- pane, or by the floating window (on whichever side has room), else
-- mid-screen.
local function place()
	frame:ClearAllPoints()
	local main = _G.PersonalVendettaMain
	local overlay = _G.PersonalVendettaOverlay
	if main and main:IsShown() then
		frame:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -16, 40)
	elseif overlay and overlay:IsShown() then
		local right = overlay.GetRight and overlay:GetRight()
		local screen = UIParent.GetWidth and UIParent:GetWidth()
		if right and screen and (right + WIDTH + 8) > screen then
			frame:SetPoint("TOPRIGHT", overlay, "TOPLEFT", -4, 0)
		else
			frame:SetPoint("TOPLEFT", overlay, "TOPRIGHT", 4, 0)
		end
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	end
end

local function open(key, name, class, text, saveFn)
	if not frame then build() end
	editingKey, onSave = key, saveFn
	local r, g, b = ns.ClassColor(class)
	local hex = string.format("%02x%02x%02x",
		math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	titleText:SetText("|cff9933ff" .. string.format(L["Note on %s"], "|cff" .. hex .. name .. "|r") .. "|r")
	edit:SetText(text or "")
	updateCounter()
	place()
	frame:Show()
	edit:SetFocus()
end

-- A player on the hit list.
function Notes:Open(key)
	local entry = key and ns.db.list[key]
	if not entry then return end
	open(key, ns.FullName(entry), entry.class, entry.note, function(text)
		ns.List:SetNote(key, text)
		local e = ns.db.list[key]
		if e then
			ns.Print(string.format(e.note and L["Note saved for %s."] or L["Note cleared for %s."], ns.FullName(e)))
		end
	end)
end

-- A player still waiting in the To add tab. The note goes with them when
-- they are added.
function Notes:OpenPending(id)
	local it = ns.Pending and ns.Pending:Get(id)
	if not it then return end
	open("pending:" .. id, ns.FullName(it.name, it.surname), it.class, it.note, function(text)
		ns.Pending:SetNote(id, text)
	end)
end

-- A queued player is being added: keep what was typed (even unsaved) and
-- close the editor, so it doesn't linger for someone who has moved on.
function Notes:CommitPending(id)
	if frame and frame:IsShown() and editingKey == "pending:" .. tostring(id) then
		save()
	end
end

-- A queued player is being skipped: close the editor, keep nothing.
function Notes:ClosePending(id)
	if frame and frame:IsShown() and editingKey == "pending:" .. tostring(id) then
		frame:Hide()
	end
end

function Notes:IsOpen() return frame and frame:IsShown() or false end
function Notes:Save() if frame and frame:IsShown() then save() end end
function Notes:EditingKey() return editingKey end
function Notes:_edit() return edit end
