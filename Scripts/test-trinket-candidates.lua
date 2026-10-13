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

for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "LEFT", "RIGHT", "CENTER" }) do
    for _, growth in ipairs({ "RIGHT", "LEFT", "UP", "DOWN" }) do
        for _, order in ipairs({ { 13, 14 }, { 14, 13 } }) do
            local settings = { Layout = { point }, GrowthDirection = growth, SlotOrder = { order[1], order[2] } }
            local reversed = growth == "UP" or (growth == "LEFT" and point ~= "TOP" and point ~= "BOTTOM")
            local firstIndex = BCDM:GetTrinketDisplaySlotIndex(settings, 1)
            local secondIndex = BCDM:GetTrinketDisplaySlotIndex(settings, 2)
            Check(firstIndex == (reversed and 2 or 1) and secondIndex == (reversed and 1 or 2),
                "trinket selector follows the live layout for " .. point .. "/" .. growth)
            local firstSlot = settings.SlotOrder[firstIndex]
            Check(BCDM:ReorderTrinketSlot(settings, firstSlot, secondIndex)
                and settings.SlotOrder[BCDM:GetTrinketDisplaySlotIndex(settings, 2)] == firstSlot,
                "dragging the first displayed trinket to second updates saved order")
            Check(not BCDM:ReorderTrinketSlot(settings, firstSlot, secondIndex),
                "dropping a trinket at its displayed position preserves saved order")
        end
    end
end

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
} }, CooldownManager = { General = { BorderSize = 1, CooldownText = {
    FontSize = 18, ScaleByIconSize = true, Layout = { "CENTER", "CENTER", 0, 0 },
} } } } }
function BCDM:GetIconDimensions() return 40, 40 end
function BCDM:ApplyIconTexCoord() end

local boundCount, boundCooldown, boundIcon
local accessDenied = false
local count = {}
function count:ClearAllPoints()
    if accessDenied then error("forbidden count region was restyled") end
    self.anchored = false
end
function count:SetPoint() self.anchored = true end
function count:SetFont(_, size) self.fontSize = size end
function count:SetTextColor(...) self.colour = { ... } end
function count:SetAlpha() end
function count:SetShadowColor() end
function count:SetShadowOffset() end

local durationText = setmetatable({}, { __index = count })
local auraTexture = setmetatable({}, { __index = count })
function auraTexture:SetDesaturation(value) self.desaturation = value end
local auraCooldown = setmetatable({}, { __index = count })
function auraCooldown:SetDrawEdge() end
function auraCooldown:SetDrawBling() end
function auraCooldown:SetDrawSwipe() end
function auraCooldown:SetSwipeColor() end
function auraCooldown:SetHideCountdownNumbers(hidden) self.hideNumbers = hidden end
function auraCooldown:GetCountdownFontString() return durationText end

local auraButton = {}
function auraButton:CreateFontString() return count end
function auraButton:CreateTexture() return auraTexture end
function auraButton:SetIcon(region)
    assert(region.anchored, "aura icon must be anchored before binding")
    boundIcon = region
end
function auraButton:SetDurationCooldown(region)
    assert(region.anchored, "aura cooldown must be anchored before binding")
    boundCooldown = region
end
function auraButton:IsShown() error("must not inspect secret aura visibility") end
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
    if frameType == "Cooldown" then return auraCooldown end
    return frameType == "AuraContainer" and container or NewLayer()
end

local icon = { GetFrameLevel = function() return 1 end }
local prepared = BCDM:EnsureTrinketAuraCountDisplay(icon, { 100 }, {
    Text = { Layout = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }, FontSize = 15, Colour = { 1, 1, 1 } },
}, { TextEnabled = true })
Check(prepared and boundCount == count and count.anchored,
    "trinket aura counts are anchored before Blizzard validates their binding")
Check(boundIcon == auraTexture and boundCooldown == auraCooldown and auraCooldown.hideNumbers == false,
    "trinket buffs bind a native duration overlay above the unchanged item cooldown")
Check(table.concat(durationText.colour, ",") == "1,1,0,1" and durationText.fontSize == 20,
    "trinket buff duration is yellow and follows the shared cooldown font scaling")
accessDenied = true
Check(BCDM:EnsureTrinketAuraCountDisplay(icon, { 100 }, {
    Text = { Layout = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }, FontSize = 15, Colour = { 1, 1, 1 } },
}, { TextEnabled = true }),
    "inaccessible trinket aura buttons retain their prepared style without errors")

return failures == 0
