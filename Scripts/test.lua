local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local BCDM = {}
assert(loadfile(root .. "/Core/Visibility.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Core/BarBehavior.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/Core/CustomTrackers.lua"))("BetterCooldownManager", BCDM)

local visibility = BCDM:NewVisibilityPolicy()
Check(BCDM:EvaluateVisibilityState(visibility, { Combat = false, Instance = "OpenWorld" }), "default visibility allows open world")
visibility.Mode = "IN_COMBAT"
Check(not BCDM:EvaluateVisibilityState(visibility, { Combat = false, Instance = "OpenWorld" }), "combat mode hides out of combat")
Check(BCDM:EvaluateVisibilityState(visibility, { Combat = true, Instance = "OpenWorld" }), "combat mode shows in combat")
visibility.Instances.Raid = false
Check(not BCDM:EvaluateVisibilityState(visibility, { Combat = true, Instance = "Raid" }), "instance filter vetoes visibility")
visibility.HideMounted = true
Check(not BCDM:EvaluateVisibilityState(visibility, { Combat = true, Instance = "OpenWorld", Mounted = true }, true), "state toggles veto macro visibility")
Check(not BCDM:EvaluateVisibilityState(visibility, { Combat = true, Instance = "OpenWorld" }, "hide"), "macro condition can hide")
Check(BCDM:ShouldDisplayCustomTrackerEntry({ Enabled = true, DisplayMode = "ALWAYS" }, nil), "always entries reserve layout without readable state")
Check(not BCDM:ShouldDisplayCustomTrackerEntry({ Enabled = true, DisplayMode = "READY" }, { ready = false }), "ready-only entry collapses while active")
Check(BCDM:ShouldDisplayCustomTrackerEntry({ Enabled = true, DisplayMode = "ACTIVE" }, { active = true }), "active-only entry shows on cooldown")
Check(BCDM:ShouldGlowCustomTrackerEntry({ Glow = "READY" }, { ready = true }), "ready glow uses resolved state")
local auraCandidates = BCDM:BuildCustomTrackerAuraCandidateIDs(
    { Type = "spell", ID = 100, AuraIDs = { 300, 100, "400", -1 } }, 200)
Check(table.concat(auraCandidates, ",") == "100,200,300,400", "aura candidates combine source, override, and explicit IDs")
Check(#BCDM:BuildCustomTrackerAuraCandidateIDs({ Type = "item", ID = 100 }, 200) == 0,
    "non-spell entries do not receive aura candidates")
Check(BCDM:ShouldSmoothBar({ Smoothing = "INHERIT" }, true), "bar smoothing can inherit the shared setting")
Check(not BCDM:ShouldSmoothBar({ Smoothing = "OFF" }, true), "bar smoothing override can disable interpolation")
Check(BCDM:FormatResourceText(25, 100, "CURRENT_MAX") == "25 / 100", "resource text supports current and maximum")
Check(BCDM:FormatResourceText(25, 100, "PERCENT") == "25%", "resource text supports percentages")
local secretValue = {}
BCDM.IsSecretValue = function(_, value) return value == secretValue end
Check(BCDM:FormatResourceText(secretValue, 100, "PERCENT") == "", "resource text does not inspect secret values")
BCDM.IsSecretValue = nil
local directionCalls = {}
BCDM:ApplyStatusBarDirection({ SetReverseFill = function(_, reverse) directionCalls.reverse = reverse end }, "LEFT")
Check(directionCalls.reverse == true, "resource bars support reverse fill")

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
Check(spell.ClassSpecFilters["MAGE:ARCANE"] and spell.ClassSpecFilters["MAGE:FIRE"], "merged spell retains spec filters")
Check(custom.Layout[2] == "BCDM_CustomTrackerBar_2", "legacy inter-viewer anchor is remapped")
Check(profile.CooldownManager.Custom == nil and profile.CooldownManager.Item == nil, "legacy fields are removed after conversion")
local nextBarID = store.NextBarID
Check(not BCDM:MigrateCustomTrackerProfile(profile) and store.NextBarID == nextBarID, "migration is idempotent")
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
Check(BCDM:RenameCustomTrackerBar(newBar, "Utility"), "bar can be renamed")
local duplicate = BCDM:DuplicateCustomTrackerBar(store.BarOrder[1])
Check(duplicate and #store.Bars[duplicate].EntryOrder == #custom.EntryOrder, "duplicate receives copied entries")
Check(store.Bars[duplicate].EntryOrder[1] ~= custom.EntryOrder[1], "entry IDs remain globally unique")
Check(BCDM:MoveCustomTrackerBar(duplicate, -1), "bar can be reordered")
store.Bars[newBar].Layout[2] = "BCDM_CustomTrackerBar_" .. duplicate
store.Bars[duplicate].Layout[2] = "BCDM_CustomTrackerBar_" .. store.BarOrder[1]
Check(BCDM:WouldCustomTrackerAnchorCycle(store.BarOrder[1], newBar), "indirect anchor cycle is rejected")
local timerEntry = BCDM:AddCustomTrackerEntry(newBar, "timer", 123, { Duration = 8 })
Check(store.Bars[newBar].Entries[timerEntry].Source.Duration == 8, "typed entry stores timer duration")
local equipmentEntry = BCDM:AddCustomTrackerEntry(newBar, "equipment", 13)
Check(store.Bars[newBar].Entries[equipmentEntry].Source.ID == 13, "typed entry stores equipment slot")
local auraEntry = BCDM:AddCustomTrackerEntry(newBar, "spell", 456, { AuraIDs = "789, 789, 987" })
Check(table.concat(store.Bars[newBar].Entries[auraEntry].Source.AuraIDs, ",") == "789,987",
    "new spell entries normalize optional aura IDs")
Check(BCDM:DeleteCustomTrackerEntry(newBar, timerEntry), "entry can be deleted")
Check(BCDM:DeleteCustomTrackerBar(newBar), "bar can be deleted")

if failures > 0 then os.exit(1) end
print("Custom tracker model tests passed")
