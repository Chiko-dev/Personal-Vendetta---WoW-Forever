--[[-------------------------------------------------------------------------
  Personal Vendetta -- Prompt
  Offers players for the list, one row each with Scum, Skip and Add.
  Two occasions:
    death  -- after an enemy player kills you. Adding counts their kill.
    fight  -- after you survive a fight with someone who came for you.
              Adding does not count a kill for them; it counts yours if
              you saw them drop.
  Nothing is added without a click. Offers that arrive while one is open
  wait their turn instead of replacing it.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local MAX_ROWS = 8
local ROW_HEIGHT = 26
local WIDTH = 440
local TIMEOUT = 150 -- seconds before the prompt gives up on its own
local QUEUE_TTL = 600 -- a waiting offer older than this is dropped

local frame, rows
local queue = {}
local current        -- { candidates = {...}, mode = "death" | "fight" }

local show -- forward

-- ===========================================================================
-- Rows
-- ===========================================================================

local function lockRow(row)
	row.resolved = true
	row.add:Disable()
	row.skip:Disable()
	row.scum:Disable()
	row.scumText:SetTextColor(0.5, 0.5, 0.5)
end

local function allResolved()
	if not rows or not current then return true end
	for i = 1, math.min(#current.candidates, MAX_ROWS) do
		if not rows[i].resolved then return false end
	end
	return true
end

local function buildFrame()
	frame = CreateFrame("Frame", "PersonalVendettaPrompt", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 120)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	frame:SetFrameStrata("DIALOG")
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

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOP", 0, -16)
	frame.title:SetText("|cff9933ffAdd to your hit list?|r")

	frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)

	rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(WIDTH - 32, ROW_HEIGHT)
		if i == 1 then
			row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -58)
		else
			row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, -2)
		end

		-- [name  detail ........] [x] Scum  [Skip] [Add]
		row.add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.add:SetSize(52, 20)
		row.add:SetPoint("RIGHT", -2, 0)
		row.add:SetText("Add")

		row.skip = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.skip:SetSize(52, 20)
		row.skip:SetPoint("RIGHT", row.add, "LEFT", -4, 0)
		row.skip:SetText("Skip")

		row.scumText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.scumText:SetPoint("RIGHT", row.skip, "LEFT", -8, 0)
		row.scumText:SetText("Scum")
		row.scumText:SetTextColor(1, 0.25, 0.25)

		row.scum = ns.CreateCheckButton(row)
		row.scum:SetSize(22, 22)
		row.scum:SetPoint("RIGHT", row.scumText, "LEFT", 0, 0)
		row.scum:SetScript("OnEnter", function(self) ns.ScumTooltip(self) end)
		row.scum:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.label:SetPoint("LEFT", 2, 0)
		row.label:SetPoint("RIGHT", row.scum, "LEFT", -6, 0)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(false)

		row:Hide()
		rows[i] = row
	end

	frame.addAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.addAll:SetSize(110, 22)
	frame.addAll:SetText("Add everyone")

	frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.close:SetSize(110, 22)
	frame.close:SetText("Close")

	return frame
end

local function layout(count)
	local height = 58 + (count * (ROW_HEIGHT + 2)) + 40
	frame:SetHeight(height)
	frame.addAll:ClearAllPoints()
	frame.close:ClearAllPoints()
	local anchor = (count > 0) and rows[count] or frame.subtitle
	frame.addAll:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -8)
	frame.close:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -2, -8)
end

-- ===========================================================================
-- Closing and the queue
-- ===========================================================================

local function closePrompt()
	if not frame or not frame:IsShown() then return end

	-- In a fight prompt, closing on someone is the same as skipping them.
	if current and current.mode == "fight" and ns.Fights then
		for i = 1, math.min(#current.candidates, MAX_ROWS) do
			if not rows[i].resolved then ns.Fights:Remember(current.candidates[i]) end
		end
	end

	frame:Hide()
	current = nil

	-- Next in line, skipping anything that went stale while it waited.
	local nextOffer = table.remove(queue, 1)
	while nextOffer and (time() - (nextOffer.at or 0)) > QUEUE_TTL do
		nextOffer = table.remove(queue, 1)
	end
	if nextOffer then
		C_Timer.After(0.3, function() show(nextOffer.candidates, nextOffer.mode) end)
	end
end

local function closeWhenDone()
	if allResolved() then
		C_Timer.After(0.8, function()
			if allResolved() then closePrompt() end
		end)
	end
end

-- ===========================================================================
-- Acting on a row
-- ===========================================================================

local function addCandidate(cand, row, mode)
	local entry
	if mode == "fight" then
		entry = ns.List:AddFromFight(cand)
	else
		entry = ns.List:RecordTheirKill(cand)
	end
	if not entry then return end

	local isScum = row and row.scum:GetChecked()
	local name = ns.FullName(entry)
	if isScum then
		ns.List:SetScum(entry.key, true)
		ns.Print(string.format("%s%s|r added to the list as %sscum|r.", ns.SCUM_COLOR, name, ns.SCUM_COLOR))
	else
		ns.Print(string.format("|cffff4444%s|r added to the list.", name))
	end

	if row then
		row.label:SetText((isScum and (ns.SKULL .. " ") or "") .. "|cff44ff44" .. name .. "|r")
		lockRow(row)
	end
end

local function skipCandidate(cand, row, mode)
	if mode == "fight" and ns.Fights then ns.Fights:Remember(cand) end
	row.label:SetText("|cff888888" .. ns.FullName(cand.name, cand.surname) .. "|r")
	lockRow(row)
end

-- "Willia Saqandie  42 Rogue  (you killed them)"
local function rowText(cand, mode)
	local text = cand.name and ns.FullName(cand.name, cand.surname) or "|cff888888unknown name|r"
	if cand.class then
		local r, g, b = ns.ClassColor(cand.class)
		local function byte(v) return math.floor(v * 255 + 0.5) end
		text = string.format("|cff%02x%02x%02x%s|r", byte(r), byte(g), byte(b), text)
	end
	local bits = {}
	if cand.levelSkull then
		bits[#bits + 1] = "|cffff3333??|r"
	elseif cand.level then
		bits[#bits + 1] = tostring(cand.level)
	end
	if cand.className then bits[#bits + 1] = cand.className end
	if #bits > 0 then text = text .. " |cff999999" .. table.concat(bits, " ") .. "|r" end

	if mode == "death" and cand.killingBlow then text = text .. " |cffffd100*|r" end
	if mode == "fight" and cand.killedByMe then text = text .. " |cff66ff66(you killed them)|r" end
	if cand.certain == false then text = text .. " |cff888888?|r" end
	return text
end

-- ===========================================================================
-- Showing
-- ===========================================================================

show = function(candidates, mode)
	if not frame then buildFrame() end
	if not candidates or #candidates == 0 then return end
	mode = (mode == "fight") and "fight" or "death"

	current = { candidates = candidates, mode = mode }
	local count = math.min(#candidates, MAX_ROWS)

	if mode == "fight" then
		frame.subtitle:SetText(count == 1 and "You survived a fight with an enemy player"
			or ("You survived a fight with " .. count .. " enemy players"))
	elseif count == 1 then
		frame.subtitle:SetText("Killed you in the open world")
	else
		frame.subtitle:SetText(count .. " players hit you -- a gank")
	end

	for i = 1, MAX_ROWS do
		local row, cand = rows[i], candidates[i]
		if i <= count and cand then
			row.resolved = nil
			row.label:SetText(rowText(cand, mode))
			row.add:Enable()
			row.skip:Enable()
			row.scum:Enable()
			row.scum:SetChecked(false)
			row.scumText:SetTextColor(1, 0.25, 0.25)
			row.add:SetScript("OnClick", function()
				addCandidate(cand, row, mode)
				closeWhenDone()
			end)
			row.skip:SetScript("OnClick", function()
				skipCandidate(cand, row, mode)
				closeWhenDone()
			end)
			row:Show()
		else
			row.resolved = true
			row:Hide()
		end
	end

	frame.addAll:SetScript("OnClick", function()
		for i = 1, count do
			if not rows[i].resolved then
				addCandidate(candidates[i], rows[i], mode)
			end
		end
		C_Timer.After(0.6, closePrompt)
	end)
	frame.close:SetScript("OnClick", closePrompt)

	frame.addAll:SetShown(count > 1)

	layout(count)
	frame:Show()

	local token = {}
	frame.token = token
	C_Timer.After(TIMEOUT, function()
		if frame:IsShown() and frame.token == token then closePrompt() end
	end)
end

-- Offers queue behind an open prompt rather than replacing it.
local function offer(candidates, mode)
	if not candidates or #candidates == 0 then return end
	if frame and frame:IsShown() then
		queue[#queue + 1] = { candidates = candidates, mode = mode, at = time() }
		return
	end
	show(candidates, mode)
end

ns.Prompt = {
	Show = offer,
	Close = closePrompt,
	_rows = function() return rows end,
	_current = function() return current end,
	_queue = function() return queue end,
}

ns.On("OFFER_CANDIDATES", function(candidates, mode)
	offer(candidates, mode)
end)
