local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local eventFrame = { events = {} }
function eventFrame:RegisterEvent(event) self.events[event] = true end
function eventFrame:SetScript(script, callback) self[script] = callback end
CreateFrame = function() return eventFrame end
C_Timer = { After = function(_, callback) callback() end }

Enum = { CooldownViewerCategory = { EquipSlotEssential = 1, EquipSlotTracked = 2 } }
local secretValue = {}
local records = {
    [10] = {
        equipSlot = 13,
        spellID = 100,
        overrideSpellID = 200,
        overrideTooltipSpellID = 300,
        linkedSpellIDs = { 400, 100 },
    },
    [20] = { equipSlot = 14, spellID = 999 },
    [30] = { equipSlot = 13, spellID = secretValue, linkedSpellIDs = { 500 } },
}
C_CooldownViewer = {
    GetCooldownViewerCategorySet = function(category)
        return category == Enum.CooldownViewerCategory.EquipSlotEssential and { 10, 20 } or { 30 }
    end,
    GetCooldownViewerCooldownInfo = function(cooldownID) return records[cooldownID] end,
}

local BCDM = {}
function BCDM:IsSecretValue(value) return value == secretValue end
assert(loadfile(root .. "/CustomViewers/TrinketBar.lua"))("BetterCooldownManager", BCDM)

local spellIDs, hasOnUse, hasCatalog = BCDM._GetTrinketAuraSpellIDs(13, 50)
Check(table.concat(spellIDs, ",") == "50,100,200,300,400,500",
    "trinket aura candidates include every readable 12.1 spell field")
Check(hasOnUse and hasCatalog, "matching equip-slot catalog records preserve their category state")

return failures == 0
