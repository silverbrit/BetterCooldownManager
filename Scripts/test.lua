local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local BCDM = {}
assert(loadfile(root .. "/Core/CustomTrackers.lua"))("BetterCooldownManager", BCDM)

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

BCDM.db = { profile = profile }
local newBar = BCDM:AddCustomTrackerBar("Timers")
Check(BCDM:RenameCustomTrackerBar(newBar, "Utility"), "bar can be renamed")
local duplicate = BCDM:DuplicateCustomTrackerBar(store.BarOrder[1])
Check(duplicate and #store.Bars[duplicate].EntryOrder == #custom.EntryOrder, "duplicate receives copied entries")
Check(BCDM:MoveCustomTrackerBar(duplicate, -1), "bar can be reordered")
store.Bars[newBar].Layout[2] = "BCDM_CustomTrackerBar_" .. duplicate
store.Bars[duplicate].Layout[2] = "BCDM_CustomTrackerBar_" .. store.BarOrder[1]
Check(BCDM:WouldCustomTrackerAnchorCycle(store.BarOrder[1], newBar), "indirect anchor cycle is rejected")
local timerEntry = BCDM:AddCustomTrackerEntry(newBar, "timer", 123, { Duration = 8 })
Check(store.Bars[newBar].Entries[timerEntry].Source.Duration == 8, "typed entry stores timer duration")
Check(BCDM:DeleteCustomTrackerEntry(newBar, timerEntry), "entry can be deleted")
Check(BCDM:DeleteCustomTrackerBar(newBar), "bar can be deleted")

if failures > 0 then os.exit(1) end
print("Custom tracker model tests passed")
