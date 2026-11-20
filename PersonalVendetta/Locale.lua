--[[-------------------------------------------------------------------------
  Personal Vendetta -- Locale
  Every string the player reads goes through ns.L["English text"]. The
  English text is the key, so a missing translation simply shows English.

  Translations live in Locales\<locale>.lua and register themselves with
  ns.AddLocale. Only the one matching your client is kept.

  Keys that are format strings (%s, %d) must keep the same specifiers in
  the same order in every translation; the test suite checks this.
---------------------------------------------------------------------------]]

local ADDON, ns = ...

local function clientLocale()
	local ok, loc = pcall(GetLocale)
	if ok and type(loc) == "string" then return loc end
	return "enUS"
end

ns.LOCALE = clientLocale()

-- Untranslated lines fall back to the English key.
ns.L = setmetatable({}, {
	__index = function(_, key) return key end,
})

-- Every translation table, kept so the tests can check them all.
ns.LocaleTables = {}

-- Locale files call this. aliases lets esES also serve esMX, and so on.
function ns.AddLocale(code, strings, aliases)
	ns.LocaleTables[code] = strings
	local wanted = (code == ns.LOCALE)
	for _, alias in ipairs(aliases or {}) do
		if alias == ns.LOCALE then wanted = true end
	end
	if wanted then
		for k, v in pairs(strings) do
			if type(v) == "string" and v ~= "" then rawset(ns.L, k, v) end
		end
	end
end
