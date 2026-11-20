--[[-------------------------------------------------------------------------
  Personal Vendetta -- Toast
  A small strip near the top of the screen for things worth a glance:
    Undo     -- after Skip, Skip all or Remove, for 10 seconds.
    Settled  -- you drew level with someone who had killed you, or pulled
                ahead. Also kill streaks (3, 5, 10 in a row).
  It never takes the mouse except on its own button, so it can't get in
  the way of a fight.
---------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local UNDO_SECONDS = 10
local CELEBRATE_SECONDS = 6
local FADE = 0.4
local SETTLE_KIT = 73277 -- UI_WORLDQUEST_COMPLETE: a short fanfare

local Toast = {}
ns.Toast = Toast

local frame
local token -- identifies the toast currently showing

local function solid(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	if t.SetColorTexture then
		t:SetColorTexture(r, g, b, a or 1)
	else
		t:SetTexture("Interface\\Buttons\\WHITE8X8")
		t:SetVertexColor(r, g, b, a or 1)
	end
	return t
end

local function build()
	frame = CreateFrame("Frame", "PersonalVendettaToast", UIParent, "BackdropTemplate")
	frame:SetSize(360, 54)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(false) -- clicks go straight through, except on the button
	frame:Hide()

	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 1,
		})
		frame:SetBackdropColor(0.04, 0.02, 0.07, 0.92)
		frame:SetBackdropBorderColor(0.45, 0.25, 0.7, 1)
	end

	frame.accent = solid(frame, "ARTWORK", 0.6, 0.2, 1, 1)
	frame.accent:SetPoint("TOPLEFT", 1, -1)
	frame.accent:SetPoint("BOTTOMLEFT", 1, 1)
	frame.accent:SetWidth(4)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(34, 34)
	frame.icon:SetPoint("LEFT", 12, 0)
	if not frame.icon:SetTexture(ns.ICON) then
		frame.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	end

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, -1)
	frame.title:SetPoint("RIGHT", -86, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
	frame.text:SetPoint("RIGHT", -86, 0)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetWordWrap(false)

	local b = CreateFrame("Button", nil, frame)
	b:SetSize(70, 24)
	b:SetPoint("RIGHT", -10, 0)
	b.bg = solid(b, "BACKGROUND", 0.3, 0.18, 0.45, 1)
	b.bg:SetAllPoints()
	local hl = solid(b, "HIGHLIGHT", 1, 1, 1, 0.18)
	hl:SetAllPoints()
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.text:SetPoint("CENTER")
	frame.button = b

	return frame
end

local function hide(myToken)
	if not frame or token ~= myToken then return end
	frame:Hide()
	frame:SetScript("OnUpdate", nil)
	token = nil
end

-- opts: title, text, duration, accent {r,g,b}, button {label, onClick}, kit
function Toast:Show(opts)
	if not frame then build() end
	local myToken = {}
	token = myToken

	local a = opts.accent or { 0.6, 0.2, 1 }
	frame.accent:SetColorTexture(a[1], a[2], a[3], 1)
	frame.title:SetText(opts.title or "")
	frame.text:SetText(opts.text or "")

	local b = frame.button
	if opts.button then
		b.label = opts.button.label
		b.text:SetText(opts.button.label)
		b:SetScript("OnClick", function()
			hide(myToken)
			opts.button.onClick()
		end)
		b:Show()
	else
		b:Hide()
	end

	local duration = opts.duration or 5
	local started = GetTime()
	frame:SetAlpha(1)
	frame:Show()
	frame:SetScript("OnUpdate", function(self)
		local left = duration - (GetTime() - started)
		if left <= 0 then hide(myToken) return end
		if left < FADE then self:SetAlpha(left / FADE) end
		if opts.countdown and b:IsShown() then
			b.text:SetText(string.format("%s (%d)", b.label, math.ceil(left)))
		end
	end)
	-- A timer as well, in case the frame is not being drawn.
	C_Timer.After(duration, function() hide(myToken) end)

	if opts.kit and ns.Sound and ns.Sound.PlayKit then ns.Sound:PlayKit(opts.kit) end
	return myToken
end

function Toast:IsShown() return frame and frame:IsShown() or false end
function Toast:_frame() return frame end

-- "Skipped Morgath. [Undo]"
function Toast:Undo(text, onUndo)
	return self:Show({
		title = text,
		text = L["Changed your mind?"],
		duration = UNDO_SECONDS,
		accent = { 0.5, 0.5, 0.55 },
		button = { label = L["Undo"], onClick = onUndo },
		countdown = true,
	})
end

-- ===========================================================================
-- Settling the score
-- ===========================================================================

ns.On("SCORE_SETTLED", function(entry, ahead)
	if not ns.db.settings.celebrate then return end
	local mine, theirs = entry.iKilledThem or 0, entry.theyKilledMe or 0
	local text = ahead
		and string.format(L["%s: you lead %d to %d."], ns.FullName(entry), mine, theirs)
		or string.format(L["%s: %d to %d. Even."], ns.FullName(entry), mine, theirs)
	ns.Print((ahead and L["Revenge!"] or L["Vendetta settled."]) .. " " .. text)
	Toast:Show({
		title = "|cff66ff66" .. (ahead and L["Revenge!"] or L["Vendetta settled"]) .. "|r",
		text = text,
		duration = CELEBRATE_SECONDS,
		accent = { 0.3, 0.9, 0.3 },
		kit = SETTLE_KIT,
	})
end)

ns.On("STREAK", function(entry, n)
	if not ns.db.settings.celebrate then return end
	local text = string.format(L["%d kills in a row on %s."], n, ns.FullName(entry))
	ns.Print(text)
	Toast:Show({
		title = "|cffffd100" .. L["Kill streak"] .. "|r",
		text = text,
		duration = CELEBRATE_SECONDS,
		accent = { 1, 0.8, 0.2 },
		kit = SETTLE_KIT,
	})
end)
