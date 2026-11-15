--[[-------------------------------------------------------------------------
  Personal Vendetta -- Prompt
  After a death, offers each enemy player who hit you. Nothing is added
  without a click: an honourable 1v1 should be able to walk away clean.
  Tick Scum before Add for the ones who did it dishonourably.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local MAX_ROWS = 8
local ROW_HEIGHT = 26
local WIDTH = 380
local TIMEOUT = 150 -- seconds before the prompt gives up on its own

local frame, rows

local function lockRow(row)
	row.add:Disable()
	row.skip:Disable()
	row.scum:Disable()
	row.scumText:SetTextColor(0.5, 0.5, 0.5)
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

		-- [name ........] [x] Scum  [Skip] [Add]
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

local function closePrompt()
	if frame then frame:Hide() end
end

local function addCandidate(cand, row)
	local entry = ns.List:RecordTheirKill(cand)
	if not entry then return end

	local isScum = row and row.scum:GetChecked()
	if isScum then
		ns.List:SetScum(entry.key, true)
		ns.Print(string.format("%s%s|r added to the list as %sscum|r.",
			ns.SCUM_COLOR, entry.name or "?", ns.SCUM_COLOR))
	else
		ns.Print(string.format("|cffff4444%s|r added to the list.", entry.name or "?"))
	end

	if row then
		row.label:SetText((isScum and (ns.SKULL .. " ") or "")
			.. "|cff44ff44" .. (cand.name or "?") .. "|r")
		lockRow(row)
	end
end

local function show(candidates)
	if not frame then buildFrame() end
	if not candidates or #candidates == 0 then return end

	local count = math.min(#candidates, MAX_ROWS)

	if count == 1 then
		frame.subtitle:SetText("Killed you in the open world")
	else
		frame.subtitle:SetText(count .. " players hit you -- a gank")
	end

	for i = 1, MAX_ROWS do
		local row, cand = rows[i], candidates[i]
		if i <= count and cand then
			local text = cand.name or "|cff888888unknown name|r"
			if cand.killingBlow then
				text = text .. " |cffffd100*|r"
			end
			if cand.certain == false then
				text = text .. " |cff888888?|r"
			end
			row.label:SetText(text)
			row.add:Enable()
			row.skip:Enable()
			row.scum:Enable()
			row.scum:SetChecked(false)
			row.scumText:SetTextColor(1, 0.25, 0.25)
			row.add:SetScript("OnClick", function()
				addCandidate(cand, row)
			end)
			row.skip:SetScript("OnClick", function()
				row.label:SetText("|cff888888" .. (cand.name or "?") .. "|r")
				lockRow(row)
			end)
			row:Show()
		else
			row:Hide()
		end
	end

	frame.addAll:SetScript("OnClick", function()
		for i = 1, count do
			if rows[i].add:IsEnabled() then
				addCandidate(candidates[i], rows[i])
			end
		end
		C_Timer.After(0.6, closePrompt)
	end)
	frame.close:SetScript("OnClick", closePrompt)

	frame.addAll:SetShown(count > 1)

	layout(count)
	frame:Show()

	frame.expiry = time() + TIMEOUT
	C_Timer.After(TIMEOUT, function()
		if frame:IsShown() and frame.expiry and time() >= frame.expiry then
			closePrompt()
		end
	end)
end

ns.Prompt = { Show = show, Close = closePrompt, _rows = function() return rows end }

ns.On("OFFER_CANDIDATES", function(candidates)
	show(candidates)
end)
