--[[-------------------------------------------------------------------------
  Personal Vendetta -- Notes
  What this person did. A short note per player, written by hand or built
  from preset buttons ("Ganked while leveling", "While low HP", "2v1"...).

  Also home to the player tooltip used by the hit list and the floating
  window, since the note is the heart of it.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

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
local editingKey

-- ===========================================================================
-- The player tooltip (hit list rows, floating window rows)
-- ===========================================================================

function ns.EntryTooltip(owner, entry, anchor)
	if not GameTooltip or not entry then return end
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")

	local r, g, b = ns.ClassColor(entry.class)
	GameTooltip:AddLine((entry.scum and (ns.SKULL .. " ") or "") .. ns.FullName(entry), r, g, b)

	local bits = {}
	if entry.levelSkull then bits[#bits + 1] = "Level ??"
	elseif entry.level then bits[#bits + 1] = "Level " .. entry.level end
	if entry.race then bits[#bits + 1] = entry.race end
	if entry.className then bits[#bits + 1] = entry.className end
	if #bits > 0 then GameTooltip:AddLine(table.concat(bits, " "), 0.8, 0.8, 0.8) end

	GameTooltip:AddLine(string.format("|cffff6666Killed you %d|r   |cff66ff66You killed them %d|r",
		entry.theyKilledMe or 0, entry.iKilledThem or 0))
	GameTooltip:AddLine("Added " .. ns.Ago(entry.firstAdded) .. ", last seen " .. ns.Ago(entry.lastSeen),
		0.6, 0.6, 0.6)
	if entry.sharedBy then
		local killed = (entry.sharedKills or 0) > 0
			and string.format(" (killed them %d time%s)", entry.sharedKills, entry.sharedKills == 1 and "" or "s") or ""
		GameTooltip:AddLine("Shared by " .. entry.sharedBy .. killed, 0.6, 0.6, 0.9)
	end
	if entry.scum then
		GameTooltip:AddLine(ns.SCUM_COLOR .. "Scum: must kill on sight.|r")
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
	if editingKey then
		ns.List:SetNote(editingKey, edit:GetText())
		local entry = ns.db.list[editingKey]
		if entry then
			ns.Print(entry.note and ("Note saved for " .. ns.FullName(entry) .. ".")
				or ("Note cleared for " .. ns.FullName(entry) .. "."))
		end
	end
	frame:Hide()
end

local function button(parent, label, w, h)
	local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
	if not ok or not b then
		b = CreateFrame("Button", nil, parent)
		b:SetNormalFontObject("GameFontNormalSmall")
		b:SetHighlightFontObject("GameFontHighlightSmall")
	end
	b:SetSize(w, h or 22)
	b:SetText(label)
	return b
end

local function build()
	frame = CreateFrame("Frame", "PersonalVendettaNotes", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 300)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)
	frame:Hide()

	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
	end
	if type(UISpecialFrames) == "table" then
		table.insert(UISpecialFrames, "PersonalVendettaNotes")
	end

	titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	titleText:SetPoint("TOPLEFT", 22, -18)
	titleText:SetPoint("TOPRIGHT", -22, -18)
	titleText:SetJustifyH("LEFT")
	titleText:SetWordWrap(false)

	-- Text box with its own border.
	local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	box:SetSize(EDIT_W + 12, EDIT_H + 12)
	box:SetPoint("TOPLEFT", 20, -46)
	if box.SetBackdrop then
		box:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
		})
		box:SetBackdropColor(0, 0, 0, 0.6)
		box:SetBackdropBorderColor(0.5, 0.35, 0.7, 0.9)
	end

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
	hint:SetText("Quick add")

	-- Preset buttons, flowed into rows that fit the width.
	local x, y = 0, 0
	local maxW = EDIT_W + 12
	local lastRowBottom
	frame.presetButtons = {}
	for _, text in ipairs(PRESETS) do
		local b = button(frame, text, 10, 20)
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

	local saveB = button(frame, "Save", 90)
	local clearB = button(frame, "Clear", 90)
	local cancelB = button(frame, "Cancel", 90)
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
	frame:SetHeight(46 + EDIT_H + 12 + 40 + (lastRowBottom or 0) + 20 + 56)
	frame:SetScript("OnHide", function() editingKey = nil ; edit:ClearFocus() end)
	return frame
end

-- Open the editor for one player.
function Notes:Open(key)
	local entry = key and ns.db.list[key]
	if not entry then return end
	if not frame then build() end

	editingKey = key
	local r, g, b = ns.ClassColor(entry.class)
	local hex = string.format("%02x%02x%02x",
		math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	titleText:SetText("|cff9933ffNote on|r |cff" .. hex .. ns.FullName(entry) .. "|r")
	edit:SetText(entry.note or "")
	updateCounter()

	frame:ClearAllPoints()
	local settings = _G.PersonalVendettaSettings
	if settings and settings:IsShown() then
		frame:SetPoint("TOPLEFT", settings, "TOPRIGHT", 4, 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	end
	frame:Show()
	edit:SetFocus()
end

function Notes:IsOpen() return frame and frame:IsShown() or false end
function Notes:Save() if frame and frame:IsShown() then save() end end
function Notes:EditingKey() return editingKey end
function Notes:_edit() return edit end
