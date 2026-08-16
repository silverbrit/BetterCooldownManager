local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local BCDM = {}
BCDM.IsSecretValue = function(_, value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end
Enum = { PowerType = {
    Mana = 0, ComboPoints = 4, Runes = 5, SoulShards = 7, HolyPower = 9,
    Maelstrom = 11, Chi = 12, ArcaneCharges = 16, Essence = 19,
} }
assert(loadfile(root .. "/Core/Visibility.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Core/Anchors.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Core/BarBehavior.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Core/ResourceCatalog.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Core/Defaults.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Core/CustomTrackers.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Modules/CooldownManager.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Scripts/test-cooldown-manager.lua"))(BCDM, Check)

local defaults = BCDM:GetDefaultDB()
Check(defaults.global.SettingsWindow.ShowSelectedElementHighlight == true,
    "selected element highlights default to enabled")
Check(defaults.profile.CooldownManager.Trinket.DisplayOnUseOnly == true,
    "trinket viewer shows on-use equipment by default")
Check(defaults.profile.CooldownManager.Trinket.Text.FontSize == 15,
    "trinket aura stacks have configurable text defaults")
Check(defaults.profile.CooldownManager.General.CooldownText.Layout[4] == 0
    and defaults.profile.CooldownManager.Essential.Text.Layout[4] == 0
    and defaults.profile.CooldownManager.Utility.Text.Layout[4] == 0
    and defaults.profile.CooldownManager.Buffs.Text.Layout[4] == 0
    and defaults.profile.CooldownManager.Trinket.Text.Layout[4] == 0
    and defaults.profile.PowerBar.Text.Layout[4] == 0
    and defaults.profile.SecondaryPowerBar.Text.Layout[4] == 0
    and defaults.profile.CastBar.Text.SpellName.Layout[4] == 0
    and defaults.profile.CastBar.Text.CastTime.Layout[4] == 0,
    "all built-in text defaults use zero Y offset")
Check(defaults.profile.General.Fonts.Font == "Friz Quadrata TT",
    "missing Expressway media falls back to Friz Quadrata TT")
Check(defaults.profile.General.Textures.Foreground == "Solid"
    and defaults.profile.General.Textures.Background == "Solid",
    "default bar textures use Solid")
Check(defaults.profile.CooldownManager.Buffs.CenterBuffs == true
    and defaults.profile.CooldownManager.Buffs.Layout[2] == "BCDM_PowerBar"
    and defaults.profile.CooldownManager.Trinket.Enabled == true,
    "tracked buffs center on the power bar and trinkets are enabled by default")
Check(defaults.profile.CooldownManager.Essential.Layout[2] == "NONE"
    and defaults.profile.CooldownManager.Essential.Layout[3] == "CENTER",
    "Essential Cooldowns use the shared anchor-parent layout schema")
local legacyEssentialProfile = {
    CooldownManager = { Essential = { Layout = { "CENTER", "CENTER", 12, -34 } } },
}
Check(BCDM:NormalizeEssentialAnchorProfile(legacyEssentialProfile)
    and legacyEssentialProfile.CooldownManager.Essential.Layout[2] == "NONE"
    and legacyEssentialProfile.CooldownManager.Essential.Layout[3] == "CENTER"
    and legacyEssentialProfile.CooldownManager.Essential.Layout[4] == 12
    and legacyEssentialProfile.CooldownManager.Essential.Layout[5] == -34,
    "legacy Essential Cooldown positions migrate without moving the viewer")
Check(not BCDM:NormalizeEssentialAnchorProfile(legacyEssentialProfile),
    "Essential Cooldown anchor migration is idempotent")
Check(defaults.profile.CooldownManager.Trinket.IconSize == 32
    and defaults.profile.CooldownManager.Trinket.IconWidth == 32
    and defaults.profile.CooldownManager.Trinket.IconHeight == 32
    and defaults.profile.CooldownManager.Trinket.Layout[1] == "TOPRIGHT"
    and defaults.profile.CooldownManager.Trinket.Layout[2] == "ElvUF_Player"
    and defaults.profile.CooldownManager.Trinket.Layout[3] == "BOTTOMRIGHT",
    "trinkets default to 32px icons anchored to the ElvUI player frame")
Check(defaults.profile.CastBar.Layout[2] == "BCDM_PowerBar",
    "cast bar defaults to the BCM power bar anchor")
Check(defaults.profile.PowerBar.BackgroundColour[1] == 62 / 255
    and defaults.profile.SecondaryPowerBar.BackgroundColour[1] == 62 / 255
    and defaults.profile.CastBar.BackgroundColour[1] == 62 / 255,
    "bar backgrounds default to #3e3e3e")
Check(defaults.profile.CooldownManager.Trinket.EntrySettings.DisplayMode == "ALWAYS",
    "trinket slots share entry behavior by default")
Check(defaults.profile.CooldownManager.Trinket.Slots[13].OverrideBarSettings == false
    and defaults.profile.CooldownManager.Trinket.Slots[14].OverrideBarSettings == false,
    "both trinket slots use shared settings by default")
Check(table.concat(defaults.profile.CooldownManager.Trinket.SlotOrder, ",") == "13,14",
    "trinket slots have a stable default order")

local visibility = BCDM:NewVisibilityPolicy()
Check(BCDM:EvaluateVisibilityState(visibility, { Combat = false, Instance = "OpenWorld" }), "default visibility allows open world")
Check(visibility.MacroCondition == nil, "visibility policies do not expose macro conditions")
visibility.Mode = "IN_COMBAT"
Check(not BCDM:EvaluateVisibilityState(visibility, { Combat = false, Instance = "OpenWorld" }), "combat mode hides out of combat")
Check(BCDM:EvaluateVisibilityState(visibility, { Combat = true, Instance = "OpenWorld" }), "combat mode shows in combat")
visibility.Instances.Raid = false
Check(not BCDM:EvaluateVisibilityState(visibility, { Combat = true, Instance = "Raid" }), "instance filter vetoes visibility")
visibility.HideMounted = true
Check(not BCDM:EvaluateVisibilityState(visibility, { Combat = true, Instance = "OpenWorld", Mounted = true }), "state toggles veto visibility")
Check(BCDM:ShouldDisplayCustomTrackerEntry({ Enabled = true, DisplayMode = "ALWAYS" }, nil), "always entries reserve layout without readable state")
Check(not BCDM:ShouldDisplayCustomTrackerEntry({ Enabled = true, DisplayMode = "READY" }, { ready = false }), "ready-only entry collapses while active")
Check(BCDM:ShouldDisplayCustomTrackerEntry({ Enabled = true, DisplayMode = "ACTIVE" }, { active = true }), "active-only entry shows on cooldown")
Check(BCDM:ShouldGlowCustomTrackerEntry({ Glow = "READY" }, { ready = true }), "ready glow uses resolved state")
local auraCandidates = BCDM:BuildCustomTrackerAuraCandidateIDs(
    { Type = "spell", ID = 100, AuraIDs = { 300, 100, "400", -1 } }, 200)
Check(table.concat(auraCandidates, ",") == "100,200,300,400", "aura candidates combine source, override, and explicit IDs")
Check(#BCDM:BuildCustomTrackerAuraCandidateIDs({ Type = "item", ID = 100 }, 200) == 0,
    "non-spell entries do not receive aura candidates")
Check(BCDM:FormatResourceText(25, 100, "CURRENT_MAX") == "25 / 100", "resource text supports current and maximum")
Check(BCDM:FormatResourceText(25, 100, "PERCENT") == "25%", "resource text supports percentages")
local secretValue = {}
local defaultIsSecretValue = BCDM.IsSecretValue
BCDM.IsSecretValue = function(_, value) return value == secretValue end
Check(BCDM:FormatResourceText(secretValue, 100, "PERCENT") == "", "resource text does not inspect secret values")
BCDM.IsSecretValue = defaultIsSecretValue
local directionCalls = {}
BCDM:ApplyStatusBarDirection({ SetReverseFill = function(_, reverse) directionCalls.reverse = reverse end }, "LEFT")
Check(directionCalls.reverse == true, "resource bars support reverse fill")

local legacyColours = {
    CastBar = { ColourByClass = true },
    PowerBar = { ColourByType = false, ColourByClass = true },
    SecondaryPowerBar = { ColourByType = false, ColourByClass = false, ColourBySpec = true },
}
Check(BCDM:NormalizeBarColourProfile(legacyColours), "legacy bar colours report migration")
Check(legacyColours.CastBar.ColourMode == "CLASS", "cast migration honors the class setting")
Check(legacyColours.PowerBar.ColourMode == "CLASS", "primary power migration honors legacy precedence")
Check(legacyColours.SecondaryPowerBar.ColourMode == "SPECIALIZATION", "secondary power migration preserves specialization")
Check(legacyColours.CastBar.ColourByClass == nil and legacyColours.PowerBar.ColourByType == nil
    and legacyColours.SecondaryPowerBar.ColourBySpec == nil, "legacy colour fields are removed after migration")
Check(not BCDM:NormalizeBarColourProfile(legacyColours), "bar colour migration is idempotent")

local removedSettings = {
    Visibility = { MacroCondition = "[combat] show" },
    General = { Animation = { SmoothBars = true } },
    PowerBar = { Smoothing = "ON", FrequentUpdates = false, Visibility = { MacroCondition = "[combat] show" } },
    SecondaryPowerBar = { Smoothing = "OFF", Visibility = { MacroCondition = "[combat] show" } },
    CastBar = { Visibility = { MacroCondition = "[combat] show" } },
    CooldownManager = {
        Trinket = { Visibility = { MacroCondition = "[combat] show" } },
        CustomTrackers = { Bars = { [1] = { Visibility = { MacroCondition = "[combat] show" } } } },
    },
}
Check(BCDM:NormalizeRemovedSettingsProfile(removedSettings), "removed settings report migration")
Check(removedSettings.Visibility.MacroCondition == nil, "shared macro condition is removed")
Check(removedSettings.General.Animation == nil, "empty legacy animation settings are removed")
Check(removedSettings.PowerBar.Smoothing == nil and removedSettings.PowerBar.FrequentUpdates == nil
    and removedSettings.SecondaryPowerBar.Smoothing == nil, "legacy bar update controls are removed")
Check(removedSettings.PowerBar.Visibility.MacroCondition == nil
    and removedSettings.SecondaryPowerBar.Visibility.MacroCondition == nil
    and removedSettings.CastBar.Visibility.MacroCondition == nil
    and removedSettings.CooldownManager.Trinket.Visibility.MacroCondition == nil
    and removedSettings.CooldownManager.CustomTrackers.Bars[1].Visibility.MacroCondition == nil,
    "macro conditions are removed from all owned bars")
Check(not BCDM:NormalizeRemovedSettingsProfile(removedSettings), "removed settings migration is idempotent")

local anchorSource = {
    { PlayerFrame = "Player", TargetFrame = "Target", NONE = "UIParent" },
    { "PlayerFrame", "TargetFrame", "NONE" },
}
local elvAnchors = BCDM:BuildAnchorParents(anchorSource, true, {
    ElvUF_Player = "ElvUI Player", ElvUF_Target = "ElvUI Target",
})
Check(elvAnchors[1].PlayerFrame == nil and elvAnchors[1].TargetFrame == nil,
    "ElvUI anchor lists omit Blizzard unit frames")
Check(elvAnchors[1].ElvUF_Player == "ElvUI Player" and elvAnchors[1].ElvUF_Target == "ElvUI Target",
    "ElvUI unit-frame anchors are added dynamically")
local blizzardAnchors = BCDM:BuildAnchorParents(anchorSource, false, {})
Check(blizzardAnchors[1].PlayerFrame == "Player" and blizzardAnchors[1].ElvUF_Player == nil,
    "Blizzard unit-frame anchors remain without ElvUI")

local implicitLegacyDefaults = { CastBar = {}, PowerBar = {}, SecondaryPowerBar = {} }
BCDM:NormalizeBarColourProfile(implicitLegacyDefaults)
Check(implicitLegacyDefaults.CastBar.ColourMode == "CLASS", "missing cast toggle uses its legacy default")
Check(implicitLegacyDefaults.PowerBar.ColourMode == "POWER_TYPE", "missing primary toggle uses its legacy default")
Check(implicitLegacyDefaults.SecondaryPowerBar.ColourMode == "POWER_TYPE", "missing secondary toggle uses its legacy default")

local colourSettings = {
    ColourMode = "CUSTOM",
    ForegroundColour = { 0.1, 0.2, 0.3, 0.4 },
    InterruptibleColour = { 0.2, 0.8, 0.2, 1 },
    NonInterruptibleColour = { 0.8, 0.2, 0.2, 1 },
}
local r, g, b, a = BCDM:ResolveBarFillColour("CastBar", colourSettings)
Check(r == 0.1 and g == 0.2 and b == 0.3 and a == 0.4, "custom mode uses the foreground colour")
colourSettings.ColourMode = "CLASS"
r, g, b, a = BCDM:ResolveBarFillColour("CastBar", colourSettings, { ClassColour = { r = 0.4, g = 0.5, b = 0.6 } })
Check(r == 0.4 and g == 0.5 and b == 0.6 and a == 1, "class mode accepts Blizzard class colour tables")
colourSettings.ColourMode = "INTERRUPTIBILITY"
r, g, b = BCDM:ResolveBarFillColour("CastBar", colourSettings, { Interruptibility = "NON_INTERRUPTIBLE" })
Check(r == 0.8 and g == 0.2 and b == 0.2, "protected casts use the non-interruptible colour")
r, g, b = BCDM:ResolveBarFillColour("CastBar", colourSettings, { Interruptibility = "UNKNOWN" })
Check(r == 0.2 and g == 0.8 and b == 0.2, "unknown cast state safely uses the interruptible colour")

colourSettings.ColourMode = "POWER_TYPE"
r, g, b = BCDM:ResolveBarFillColour("PowerBar", colourSettings, { PowerTypeColour = { 0.7, 0.6, 0.5 } })
Check(r == 0.7 and g == 0.6 and b == 0.5, "power-type mode uses the resource palette")
colourSettings.ColourMode = "SPECIALIZATION"
r, g, b = BCDM:ResolveBarFillColour("SecondaryPowerBar", colourSettings, {
    PowerTypeColour = { 0.3, 0.2, 0.1 }, SpecializationColour = { 0.9, 0.8, 0.7 },
})
Check(r == 0.9 and g == 0.8 and b == 0.7, "specialization mode uses the specialization palette")
r, g, b = BCDM:ResolveBarFillColour("SecondaryPowerBar", colourSettings, { PowerTypeColour = { 0.3, 0.2, 0.1 } })
Check(r == 0.3 and g == 0.2 and b == 0.1, "missing specialization falls back to power type")
r, g, b = BCDM:ResolveBarFillColour("SecondaryPowerBar", colourSettings, {
    PowerTypeColour = { 0.3, 0.2, 0.1 }, OverrideColour = { 1, 0.5, 0 },
})
Check(r == 1 and g == 0.5 and b == 0, "resource state colours override the selected base mode")
colourSettings.ColourMode = "CLASS"
r, g, b, a = BCDM:ResolveBarFillColour("PowerBar", colourSettings)
Check(r == 0.1 and g == 0.2 and b == 0.3 and a == 0.4, "missing selected colours fall back to foreground")

local descriptor = BCDM:ResolveSecondaryResource({ class = "WARLOCK", specID = 267, powerTypes = Enum.PowerType })
Check(descriptor and descriptor.kind == "SOUL_SHARDS" and descriptor.fractional,
    "destruction resolves fractional soul shards")
Check(descriptor.swapToPrimaryEligible, "warlock resources can use the primary position")
descriptor = BCDM:ResolveSecondaryResource({ class = "DEATHKNIGHT", specID = 250, powerTypes = Enum.PowerType })
Check(descriptor and descriptor.kind == "RUNES" and descriptor.runeColourKey == "BLOOD",
    "death knight descriptors own specialization rune colours")
descriptor = BCDM:ResolveSecondaryResource({ class = "SHAMAN", specID = 262, showMana = false, powerTypes = Enum.PowerType })
Check(descriptor == nil, "elemental mana remains opt-in")
descriptor = BCDM:ResolveSecondaryResource({ class = "SHAMAN", specID = 262, showMana = true, powerTypes = Enum.PowerType })
Check(descriptor and descriptor.powerType == Enum.PowerType.Mana, "elemental mana resolves when enabled")
descriptor = BCDM:ResolveSecondaryResource({ class = "DRUID", specID = 103, formID = 1, powerTypes = Enum.PowerType })
Check(descriptor and descriptor.powerType == Enum.PowerType.ComboPoints, "cat form resolves combo points")
Check(BCDM:ResolveSecondaryResource({ class = "DRUID", specID = 103, formID = 0, powerTypes = Enum.PowerType }) == nil,
    "druid combo points require cat form")
for _, expected in ipairs({
    { "MONK", 268, "STAGGER" }, { "MONK", 269, "STANDARD" }, { "ROGUE", 259, "COMBO_POINTS" },
    { "PALADIN", 70, "STANDARD" }, { "MAGE", 62, "STANDARD" }, { "EVOKER", 1467, "ESSENCE" },
    { "DEMONHUNTER", 581, "SPELL_CHARGES" }, { "DEMONHUNTER", 1480, "DEVOURER_SOUL" },
    { "SHAMAN", 263, "AURA_STACKS" },
}) do
    descriptor = BCDM:ResolveSecondaryResource({ class = expected[1], specID = expected[2], powerTypes = Enum.PowerType })
    Check(descriptor and descriptor.kind == expected[3], expected[1] .. " resource resolves through the shared catalog")
end
Check(not BCDM:ResolveSecondaryResource({ class = "PALADIN", specID = 65, powerTypes = Enum.PowerType }).swapToPrimaryEligible,
    "holy paladin retains the separate secondary position")

local profile = {
    CooldownManager = {
        Custom = {
            Layout = { "CENTER", "BCDM_CustomItemBar", "CENTER", 2, 3 },
            Spells = {
                MAGE = {
                    ARCANE = { [100] = { isActive = true, layoutIndex = 2 } },
                    FIRE = { [100] = { isActive = true, layoutIndex = 1 }, [200] = { isActive = false, layoutIndex = 3 } },
                },
            },
        },
        Item = {
            Layout = { "CENTER", "NONE", "CENTER", 0, 0 },
            Items = { [300] = { isActive = true, layoutIndex = 1 } },
        },
        ItemSpell = {
            ItemsSpells = {
                [400] = { isActive = true, layoutIndex = 1, entryType = "item" },
                [500] = { isActive = true, layoutIndex = 2, entryType = "spell" },
            },
        },
    },
}

Check(BCDM:MigrateCustomTrackerProfile(profile), "legacy profile reports migration")
local store = profile.CooldownManager.CustomTrackers
Check(#store.BarOrder == 3, "one bar is created for each non-empty legacy viewer")
local custom = store.Bars[store.BarOrder[1]]
Check(custom.Name == "Custom Cooldowns", "legacy bar name is retained")
Check(#custom.EntryOrder == 2, "duplicate spells across specs merge")
local spell = custom.Entries[custom.EntryOrder[1]]
Check(spell.Source.ID == 100, "spell order uses earliest legacy layout index")
Check(spell.OverrideBarSettings == true, "legacy entries preserve their per-entry behavior as overrides")
Check(spell.SpecFilters[62] and spell.SpecFilters[63] and spell.ClassSpecFilters == nil,
    "merged spell migrates spec filters to specialization IDs")
Check(custom.Layout[2] == "BCDM_CustomTrackerBar_2", "legacy inter-viewer anchor is remapped")
Check(profile.CooldownManager.Custom == nil and profile.CooldownManager.Item == nil, "legacy fields are removed after conversion")
local nextBarID = store.NextBarID
Check(not BCDM:MigrateCustomTrackerProfile(profile) and store.NextBarID == nextBarID, "migration is idempotent")
spell.ClassSpecFilters = { ["mage:future spec"] = true }
Check(not BCDM:MigrateCustomTrackerProfile(profile), "unresolved current-schema filters do not retrigger migration")
Check(spell.ClassSpecFilters["mage:future spec"], "unresolved legacy filters are preserved losslessly")
Check(BCDM:EntryMatchesSpecialization(spell, 9999, "MAGE", "Future Spec"),
    "unresolved filters retain their English-name compatibility fallback")
spell.ClassSpecFilters = nil
spell.Source.AuraIDs = { 700, "800", 700, 0 }
store.SchemaVersion = 1
Check(BCDM:MigrateCustomTrackerProfile(profile), "schema-v2 aura IDs migrate")
Check(table.concat(spell.Source.AuraIDs, ",") == "700,800", "schema-v2 migration normalizes aura IDs")
Check(not BCDM:MigrateCustomTrackerProfile(profile), "schema-v2 migration is idempotent")
spell.Source.AuraIDs = "900, 900, 901"
Check(BCDM:MigrateCustomTrackerProfile(profile), "current-schema imports still normalize aura IDs")
Check(table.concat(spell.Source.AuraIDs, ",") == "900,901", "current-schema aura IDs use the canonical shape")

BCDM.db = { profile = profile }
local newBar = BCDM:AddCustomTrackerBar("Timers")
Check(store.Bars[newBar].Text.Layout[4] == 0, "new tracker text defaults to zero Y offset")
Check(store.Bars[newBar].EntrySettings.TextEnabled == true, "new bars enable shared entry text by default")
Check(store.Bars[newBar].EntrySettings.Tooltip == true, "new bars enable shared entry tooltips by default")
Check(store.Bars[newBar].EntrySettings.DisplayMode == "ALWAYS", "new bars share display mode by default")
Check(type(store.Bars[newBar].EntrySettings.SpecFilters) == "table", "new bars share specialization filters")
Check(BCDM:RenameCustomTrackerBar(newBar, "Utility"), "bar can be renamed")
local duplicate = BCDM:DuplicateCustomTrackerBar(store.BarOrder[1])
Check(duplicate and #store.Bars[duplicate].EntryOrder == #custom.EntryOrder, "duplicate receives copied entries")
Check(store.Bars[duplicate].EntryOrder[1] ~= custom.EntryOrder[1], "entry IDs remain globally unique")
Check(store.BarOrder[#store.BarOrder] == duplicate, "duplicate is appended to stable bar order")
store.Bars[newBar].Layout[2] = "BCDM_CustomTrackerBar_" .. duplicate
store.Bars[duplicate].Layout[2] = "BCDM_CustomTrackerBar_" .. store.BarOrder[1]
Check(BCDM:WouldCustomTrackerAnchorCycle(store.BarOrder[1], newBar), "indirect anchor cycle is rejected")
local timerEntry = BCDM:AddCustomTrackerEntry(newBar, "timer", 123, { Duration = 8 })
Check(store.Bars[newBar].Entries[timerEntry].Source.Duration == 8, "typed entry stores timer duration")
Check(store.Bars[newBar].Entries[timerEntry].TextEnabled == true, "new entries enable text by default")
Check(store.Bars[newBar].Entries[timerEntry].OverrideBarSettings == false,
    "new entries use shared bar settings by default")
local sharedStyle = BCDM:GetCustomTrackerEntrySettings(store.Bars[newBar], store.Bars[newBar].Entries[timerEntry])
Check(sharedStyle == store.Bars[newBar].EntrySettings, "entries resolve shared bar styling by default")
store.Bars[newBar].Entries[timerEntry].OverrideBarSettings = true
Check(BCDM:GetCustomTrackerEntrySettings(store.Bars[newBar], store.Bars[newBar].Entries[timerEntry])
    == store.Bars[newBar].Entries[timerEntry], "entry override resolves its own styling")
local equipmentEntry = BCDM:AddCustomTrackerEntry(newBar, "equipment", 13)
Check(store.Bars[newBar].Entries[equipmentEntry].Source.ID == 13, "typed entry stores equipment slot")
Check(BCDM:EntryMatchesSpecialization(store.Bars[newBar].Entries[equipmentEntry], 62, "MAGE", "Arcane"),
    "entries without specialization filters remain unrestricted")
local auraEntry = BCDM:AddCustomTrackerEntry(newBar, "spell", 456, { AuraIDs = "789, 789, 987" })
Check(table.concat(store.Bars[newBar].Entries[auraEntry].Source.AuraIDs, ",") == "789,987",
    "new spell entries normalize optional aura IDs")
local filteredEntry = BCDM:AddCustomTrackerEntry(newBar, "spell", 654, { SpecFilters = { [62] = true } })
Check(BCDM:EntryMatchesSpecialization(store.Bars[newBar].Entries[filteredEntry], 62, "MAGE", "Arcane"),
    "numeric specialization filters match directly")
Check(not BCDM:EntryMatchesSpecialization(store.Bars[newBar].Entries[filteredEntry], 63, "MAGE", "Fire"),
    "numeric specialization filters reject other specs")
local order = store.Bars[newBar].EntryOrder
Check(BCDM:ReorderCustomTrackerEntry(newBar, filteredEntry, 1) and order[1] == filteredEntry,
    "entry can be dragged to the first position")
Check(BCDM:ReorderCustomTrackerEntry(newBar, filteredEntry, #order) and order[#order] == filteredEntry,
    "entry can be dragged to the last position")
local middle = math.max(1, math.floor((#order + 1) / 2))
Check(BCDM:ReorderCustomTrackerEntry(newBar, filteredEntry, middle) and order[middle] == filteredEntry,
    "entry can be dragged to a middle position")
Check(not BCDM:ReorderCustomTrackerEntry(newBar, filteredEntry, middle), "same-position drops are ignored")
Check(not BCDM:ReorderCustomTrackerEntry(newBar, 999999, 1), "unknown entry reorder is rejected")
Check(not BCDM:ReorderCustomTrackerEntry(newBar, filteredEntry, nil), "invalid reorder index is rejected")
Check(BCDM:DeleteCustomTrackerEntry(newBar, timerEntry), "entry can be deleted")
local expectedOrder = {}
for _, barID in ipairs(store.BarOrder) do
    if barID ~= newBar then expectedOrder[#expectedOrder + 1] = barID end
end
Check(BCDM:DeleteCustomTrackerBar(newBar), "bar can be deleted")
Check(table.concat(store.BarOrder, ",") == table.concat(expectedOrder, ","),
    "deleting a bar preserves the relative stable bar order")
local recycledID = BCDM:AddCustomTrackerBar()
Check(recycledID > newBar, "recycled tracker names retain monotonic internal IDs")
Check(store.Bars[recycledID].Name == "Tracker Bar 1", "default tracker names reuse the lowest available number")
Check(store.BarOrder[#store.BarOrder] == recycledID, "new bars append without reordering existing bars")

Check(assert(loadfile(root .. "/Scripts/test-glows.lua"))(root), "custom glow lifecycle tests pass")
Check(assert(loadfile(root .. "/Scripts/test-cooldown-runtime.lua"))(root),
    "Cooldown Manager runtime safety tests pass")
Check(assert(loadfile(root .. "/Scripts/test-secondary-power.lua"))(root),
    "secondary-resource secret-value tests pass")
Check(assert(loadfile(root .. "/Scripts/test-trinket-candidates.lua"))(root),
    "trinket candidate tests pass")

if failures > 0 then os.exit(1) end
print("Custom tracker model tests passed")
