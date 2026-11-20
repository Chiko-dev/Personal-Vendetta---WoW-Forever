--[[-------------------------------------------------------------------------
  Personal Vendetta -- Marks
  A skull above the nameplate of anyone from your list, so you can pick the
  right one out of a crowd. Scum get the Vendetta crosshair instead, with a
  slow red pulse. Only you see these: they are drawn by the addon, not raid
  markers (which addons can no longer set).

  Forever creates some nameplates as "forbidden" frames that addons may not
  touch. Those are checked for and skipped, never anchored to.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local SIZE = 26
local SCUM_SIZE = 32
local PULSE_SPEED = 3.5

local Marks = {}
ns.Marks = Marks

local active = {}  -- entry key -> marker
local pool = {}

local function plateFor(unit)
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	if not get then return nil end
	local ok, plate = pcall(get, unit)
	if not ok or not plate then return nil end
	if plate.IsForbidden then
		local okF, forbidden = pcall(plate.IsForbidden, plate)
		if not okF or forbidden then return nil end
	end
	return plate
end

local function newMarker()
	local m = table.remove(pool)
	if m then return m end
	m = CreateFrame("Frame", nil, UIParent)
	m:SetSize(SIZE, SIZE)
	m.glow = m:CreateTexture(nil, "BACKGROUND")
	m.glow:SetPoint("CENTER")
	m.glow:SetSize(SCUM_SIZE + 14, SCUM_SIZE + 14)
	-- A red-tinted, additive copy of the round icon: a round glow, not a square.
	m.glow:SetTexture(ns.ICON)
	if m.glow.SetVertexColor then m.glow:SetVertexColor(1, 0.1, 0.05, 1) end
	if m.glow.SetBlendMode then m.glow:SetBlendMode("ADD") end
	m.icon = m:CreateTexture(nil, "ARTWORK")
	m.icon:SetAllPoints()
	return m
end

local function release(key)
	local m = active[key]
	if not m then return end
	active[key] = nil
	m:SetScript("OnUpdate", nil)
	m:Hide()
	m:ClearAllPoints()
	pcall(m.SetParent, m, UIParent)
	m.unit, m.plate = nil, nil
	pool[#pool + 1] = m
end

local function pulse(self)
	local wave = 0.5 + 0.5 * math.sin(GetTime() * PULSE_SPEED)
	self.glow:SetAlpha(0.15 + 0.35 * wave)
	local s = SCUM_SIZE * (1 + 0.08 * wave)
	self:SetSize(s, s)
end

local function attach(entry, unit)
	local plate = plateFor(unit)
	if not plate then
		release(entry.key)
		return
	end

	local m = active[entry.key]
	if m and m.plate == plate and m.scum == (entry.scum and true or false) then
		m.unit = unit
		return -- already in place
	end
	if not m then
		m = newMarker()
		active[entry.key] = m
	end

	m.unit, m.plate = unit, plate
	m.scum = entry.scum and true or false
	-- Parented to the plate: it moves, scales and hides with it.
	local ok = pcall(function()
		m:SetParent(plate)
		m:ClearAllPoints()
		m:SetPoint("BOTTOM", plate, "TOP", 0, 2)
		m:SetFrameStrata("HIGH")
	end)
	if not ok then
		release(entry.key)
		return
	end

	if m.scum then
		if not m.icon:SetTexture(ns.ICON) then
			m.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
		end
		m.glow:Show()
		m:SetSize(SCUM_SIZE, SCUM_SIZE)
		m:SetScript("OnUpdate", pulse)
	else
		m.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
		m.glow:Hide()
		m:SetSize(SIZE, SIZE)
		m:SetScript("OnUpdate", nil)
	end
	m:Show()
end

function Marks:Count()
	local n = 0
	for _ in pairs(active) do n = n + 1 end
	return n
end

function Marks:Get(key) return active[key] end

function Marks:Clear()
	for key in pairs(active) do release(key) end
end

-- ===========================================================================
-- Wiring
-- ===========================================================================

-- Every radar sweep, for each list member in view.
ns.On("UNIT_SEEN", function(entry, unit, record)
	if not ns.db.settings.markNameplates then return end
	if not entry or not entry.key then return end
	if record.dead or type(unit) ~= "string" or not string.find(unit, "^nameplate") then
		if record.dead then release(entry.key) end
		return
	end
	attach(entry, unit)
end)

-- Anyone who left the radar, died, or came off the list loses their mark.
local function prune()
	for key, m in pairs(active) do
		local record = ns.Radar and ns.Radar:Get(key)
		if not record or record.dead or not ns.ListData()[key] then
			release(key)
		end
	end
end
ns.On("RADAR_CHANGED", prune)
ns.On("LIST_CHANGED", prune)
ns.On("SETTINGS_CHANGED", function()
	if not ns.db.settings.markNameplates then Marks:Clear() end
end)

local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:SetScript("OnEvent", function(_, _, unit)
	for key, m in pairs(active) do
		if m.unit == unit then release(key) end
	end
end)
