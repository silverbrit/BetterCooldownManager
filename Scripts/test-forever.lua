local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

-- Isolate both clients from the other runtime mocks in test.lua.
local interface = 16001
local env = setmetatable({
    GetBuildInfo = function() return "1.60.1", "69913", "", interface end,
    UnitClass = function() return "Rogue", "ROGUE" end,
    LibStub = function() return { Register = function() end } end,
    C_AddOns = { GetAddOnMetadata = function() return "BCDM" end },
    StaticPopupDialogs = {},
    Enum = { PowerType = {
        Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5,
        RunicPower = 6, SoulShards = 7, LunarPower = 8, HolyPower = 9,
        Maelstrom = 11, Chi = 12, Insanity = 13, ArcaneCharges = 16,
        Fury = 17, Pain = 18, Essence = 19,
    } },
    Constants = { UICharacterClasses = {
        Warrior = 1, Paladin = 2, Hunter = 3, Rogue = 4, Priest = 5, DeathKnight = 6,
        Shaman = 7, Mage = 8, Warlock = 9, Monk = 10, Druid = 11, DemonHunter = 12, Evoker = 13,
    } },
    CLASS_SORT_ORDER = { "WARRIOR", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER" },
    GetSpecialization = false,
    GetSpecializationInfo = false,
    C_SpecializationInfo = {
        GetNumSpecializationsForClassID = function() return 1 end,
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 1488, "Rogue" end,
    },
    GetSpecializationInfoForClassID = function(id, index) return id * 100 + index, "Spec " .. index end,
}, { __index = _G })
local classTokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
env.GetClassInfo = function(id) return classTokens[id], classTokens[id] end
local BCDM = {}
local function Load(path)
    setfenv(assert(loadfile(root .. "/" .. path)), env)("BetterCooldownManager", BCDM)
end
Load("Core/Globals.lua")
Load("Core/Anchors.lua")
local swingAnchors = BCDM:GetAnchorParents("CustomTrackers")
local swingAnchorOrder = {}
for _, key in ipairs(swingAnchors[2]) do swingAnchorOrder[key] = true end
for _, key in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
    assert(swingAnchors[1][key] and swingAnchorOrder[key], "Forever exposes swing timer anchor " .. key)
end
Load("Core/BarBehavior.lua")
Load("Core/ResourceCatalog.lua")
Load("Core/CustomTrackers.lua")
assert(BCDM.IS_WOW_FOREVER, "TOC 16001 must select Forever")
assert(BCDM:GetCurrentSecondaryResource().kind == "COMBO_POINTS", "Forever works without deprecated specialization aliases")

for _, class in ipairs(classTokens) do
    local descriptor = BCDM:ResolveSecondaryResource({ class = class, specID = 267 })
    assert((descriptor ~= nil) == (class == "ROGUE"), "Forever must not select Retail resources for " .. class)
end
local rogue = BCDM:ResolveSecondaryResource({ class = "ROGUE" })
local cat = BCDM:ResolveSecondaryResource({ class = "DRUID", formID = 1 })
assert(rogue.kind == "COMBO_POINTS" and cat.kind == "COMBO_POINTS", "combo points work without a specialization")
assert(not cat.swapToPrimaryEligible and not rogue.swapToPrimaryEligible)
for _, form in ipairs({ 0, 5, 31 }) do
    assert(not BCDM:ResolveSecondaryResource({ class = "DRUID", formID = form }))
end
assert(BCDM:ResolvePrimaryDisplayPowerType(1, "DRUID", 1, 0) == 1, "Forever must use the native power type")

for _, powerType in pairs(env.Enum.PowerType) do
    assert(BCDM:IsPowerColourSupported(powerType, false) == (powerType == 0 or powerType == 1 or powerType == 3))
    assert(BCDM:IsPowerColourSupported(powerType, true) == (powerType == 4))
end
for _, key in ipairs({ "SOUL_FRAGMENTS", "SOUL", "STAGGER", "RUNE_RECHARGE", "ESSENCE_RECHARGE", "CHARGED_COMBO_POINTS" }) do
    assert(not BCDM:IsPowerColourSupported(key, true), "Forever hides " .. key)
end
local catalog = BCDM:GetClassSpecCatalog()
assert(#catalog == 9, "Forever exposes only its nine playable classes")
assert(#BCDM:GetClassSpecCatalog("EVOKER") == 0, "imported filter classes cannot reintroduce unavailable classes")
assert(BCDM:GetClassSpecCatalog("DRUID")[1].classId == 11, "sparse class IDs retain Druid")
local saved = { SpecFilters = { [1467] = true }, FilterClass = "EVOKER" }
BCDM:GetClassSpecCatalog(saved.FilterClass)
assert(saved.SpecFilters[1467] and saved.FilterClass == "EVOKER", "client filtering preserves saved data")

-- Profile controls must expose the two native talent groups, not the single Camelot class spec.
local noop = function() end
local panel = { SetScript = noop }
local controls = { RegisterSection = noop, scrollFrame = { SetScript = noop } }
local widgets = setmetatable({}, { __index = function() return { SetScript = noop } end })
local canvas = {
    Register = noop,
    CreateProfileManagementSection = function() return {}, widgets end,
    CreateProfileSharingSection = function() return {}, widgets end,
    AttachDropdownMenu = noop,
}
local labels = {}
BCDM.SettingsUtils = {
    L = function(text) return text end,
    NewPanel = function() return panel, controls end,
    Section = noop, Text = noop, Checkbox = noop,
    Dropdown = function(_, _, label) labels[label] = true end,
}
env.LibStub = function() return canvas end
env.Settings = { RegisterCanvasLayoutSubcategory = function() return {} end, RegisterAddOnCategory = noop }
env.GetNumSpecializations = function() error("Forever profiles must use talent groups") end
env.DUAL_SPEC_PRIMARY, env.DUAL_SPEC_SECONDARY = "Primary", "Secondary"
Load("Options/Profiles.lua")
BCDM:RegisterProfilesSettings({})
assert(labels.Primary and labels.Secondary, "both Forever talent-group profile slots are configurable")

interface = 120105
Load("Core/Globals.lua")
assert(not BCDM.IS_WOW_FOREVER, "Retail must not select Forever")
assert(not BCDM:GetAnchorParents("CustomTrackers")[1].SwingTimerMainHandFrame,
    "Retail does not expose Forever swing timer anchors")
for _, powerType in pairs(env.Enum.PowerType) do
    assert(BCDM:IsPowerColourSupported(powerType, true) and BCDM:IsPowerColourSupported(powerType, false))
end
assert(BCDM:ResolveSecondaryResource({ class = "EVOKER", specID = 1467 }).kind == "ESSENCE")
assert(BCDM:ResolveSecondaryResource({ class = "WARLOCK", specID = 267 }).fractional)
assert(BCDM:ResolvePrimaryDisplayPowerType(8, "DRUID", 1, 0) == 0, "Retail retains Balance mana override")
env.CLASS_SORT_ORDER = classTokens
assert(#BCDM:GetClassSpecCatalog() == 13, "Retail retains all classes")
interface = 11508
Load("Core/Globals.lua")
assert(not BCDM.IS_WOW_FOREVER, "Classic Era is not Forever")
return true
