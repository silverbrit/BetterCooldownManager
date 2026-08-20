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

local passiveIDs = BCDM._GetTrinketAuraSpellIDs(13, nil)
Check(table.concat(passiveIDs, ",") == "100,200,300,400,500",
    "passive trinket catalog entries can be cached without an item spell")
records[10].spellID = 600
local oldPassiveIDs = BCDM._GetTrinketAuraSpellIDs(13, nil)
Check(table.concat(oldPassiveIDs, ",") == "100,200,300,400,500",
    "passive trinket cache remains stable until catalog invalidation")
BCDM:InvalidateTrinketCatalogCache()
local refreshedPassiveIDs = BCDM._GetTrinketAuraSpellIDs(13, nil)
Check(table.concat(refreshedPassiveIDs, ",") == "600,200,300,400,100,500",
    "trinket catalog invalidation refreshes passive replacements")
Check(eventFrame.events["PLAYER_SPECIALIZATION_CHANGED"]
    and eventFrame.events["COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"],
    "trinket catalog listens for specialization and override changes")
records[10].spellID = 700
eventFrame.OnEvent(nil, "PLAYER_SPECIALIZATION_CHANGED", "player")
local specializationIDs = BCDM._GetTrinketAuraSpellIDs(13, nil)
Check(table.concat(specializationIDs, ",") == "700,200,300,400,100,500",
    "specialization changes invalidate trinket catalog entries")
local oldFetchEquippedTrinkets = BCDM.FetchEquippedTrinkets
local oldInCombatLockdown = InCombatLockdown
BCDM.FetchEquippedTrinkets = function() end
InCombatLockdown = function() return false end
records[10].spellID = 800
eventFrame.OnEvent(nil, "PLAYER_EQUIPMENT_CHANGED", 13)
local equipmentIDs = BCDM._GetTrinketAuraSpellIDs(13, nil)
Check(table.concat(equipmentIDs, ",") == "800,200,300,400,100,500",
    "equipment changes invalidate trinket catalog entries")
BCDM.FetchEquippedTrinkets = oldFetchEquippedTrinkets
InCombatLockdown = oldInCombatLockdown

assert(loadfile(root .. "/CustomViewers/AuraSourceDisplay.lua"))("BetterCooldownManager", BCDM)
CustomAuraContainerSlotDefaultOptions = {}
InCombatLockdown = function() return false end
BCDM.Media = { Font = "font" }
BCDM.db = { profile = { General = { Fonts = {
    FontFlag = "", Shadow = { Enabled = false },
} } } }

local boundCount
local accessDenied = false
local count = {}
function count:ClearAllPoints()
    if accessDenied then error("forbidden count region was restyled") end
    self.anchored = false
end
function count:SetPoint() self.anchored = true end
function count:SetFont() end
function count:SetTextColor() end
function count:SetAlpha() end
function count:SetShadowColor() end
function count:SetShadowOffset() end

local auraButton = {}
function auraButton:CreateFontString() return count end
function auraButton:SetAllPoints() end
function auraButton:SetFrameLevel() end
function auraButton:SetMouseMotionEnabled() end
function auraButton:CanBeAccessedInContext() return not accessDenied end
function auraButton:SetApplicationCount(region)
    if not region.anchored then error("application count must be anchored before binding") end
    boundCount = region
end

local container = {}
function container:SetAllPoints() end
function container:SetUnit() end
function container:SetEnabled() end
function container:AddAuraSlot(_, _, options)
    options.initializeFrame(auraButton)
    return auraButton
end

local function NewLayer()
    local layer = {}
    function layer:SetAllPoints() end
    function layer:SetFrameLevel() end
    function layer:GetFrameLevel() return 11 end
    function layer:Show() end
    return layer
end
CreateFrame = function(frameType)
    return frameType == "AuraContainer" and container or NewLayer()
end

local icon = { GetFrameLevel = function() return 1 end }
local prepared = BCDM:EnsureTrinketAuraCountDisplay(icon, { 100 }, {
    Text = { Layout = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }, FontSize = 15, Colour = { 1, 1, 1 } },
}, { TextEnabled = true })
Check(prepared and boundCount == count and count.anchored,
    "trinket aura counts are anchored before Blizzard validates their binding")
accessDenied = true
Check(BCDM:EnsureTrinketAuraCountDisplay(icon, { 100 }, {
    Text = { Layout = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }, FontSize = 15, Colour = { 1, 1, 1 } },
}, { TextEnabled = true }),
    "inaccessible trinket aura buttons retain their prepared style without errors")

return failures == 0
