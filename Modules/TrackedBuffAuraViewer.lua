local _, BCDM = ...

local FILTER = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local MAX_REFRESH_ATTEMPTS = 3
local NATIVE_BUFF_ICON_SIZE = 40
local Unpack = unpack or table.unpack
local requestedItemData = {}
local CATEGORY_FALLBACK_TEXTURES = {
    [4] = "Interface/ICONS/INV_POTION_114",
    [30] = "Interface/ICONS/INV_POTION_54",
    [1711] = "Interface/ICONS/Warlock_ Healthstone",
}

local Runtime = {
    pending = false,
    scheduled = false,
    attempts = 0,
    ready = false,
    editorVisible = false,
    capacity = 0,
    groups = {},
    itemCapacity = 0,
    itemFrames = {},
    itemCatalog = {},
    itemRefreshScheduled = false,
    signature = nil,
    pendingVisibilityRestore = nil,
}
BCDM.TrackedBuffAuraRuntime = Runtime

local function IsInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function Call(object, methodName, ...)
    if not object then return false end
    local okMethod, method = pcall(function() return object[methodName] end)
    if not okMethod or type(method) ~= "function" then return false end
    return pcall(method, object, ...)
end

local function ReadField(object, key)
    if type(object) ~= "table" then return nil, false end
    local ok, value = pcall(function() return object[key] end)
    if not ok or BCDM:IsSecretValue(value) then return nil, false end
    return value, true
end

local function AddReadableSpellID(spellIDs, seen, value)
    if BCDM:IsSecretValue(value) or type(value) ~= "number" or value <= 0 or seen[value] then return end
    seen[value] = true
    spellIDs[#spellIDs + 1] = value
end

function BCDM.BuildTrackedBuffAuraCandidates(info)
    local spellIDs, seen = {}, {}
    local spellID, spellReadable = ReadField(info, "spellID")
    if not spellReadable then return {}, false end
    AddReadableSpellID(spellIDs, seen, spellID)
    local overrideSpellID, overrideReadable = ReadField(info, "overrideSpellID")
    if not overrideReadable then return {}, false end
    AddReadableSpellID(spellIDs, seen, overrideSpellID)
    local overrideTooltipSpellID, overrideTooltipReadable = ReadField(info, "overrideTooltipSpellID")
    if not overrideTooltipReadable then return {}, false end
    AddReadableSpellID(spellIDs, seen, overrideTooltipSpellID)

    local linkedSpellIDs, linkedReadable = ReadField(info, "linkedSpellIDs")
    if not linkedReadable or type(linkedSpellIDs) ~= "table" then return {}, false end
    if type(linkedSpellIDs) == "table" then
        local okCount, count = pcall(function() return #linkedSpellIDs end)
        if not okCount or BCDM:IsSecretValue(count) or type(count) ~= "number" then return {}, false end
        for index = 1, count do
            local okValue, linkedSpellID = pcall(function() return linkedSpellIDs[index] end)
            if not okValue or BCDM:IsSecretValue(linkedSpellID) then return {}, false end
            AddReadableSpellID(spellIDs, seen, linkedSpellID)
        end
    end
    table.sort(spellIDs)
    return spellIDs, true
end

function BCDM.BuildTrackedBuffAuraCatalog(cooldownIDs, getCooldownInfo)
    if type(cooldownIDs) ~= "table" or type(getCooldownInfo) ~= "function" then return nil, false end
    local catalog = { auras = {}, items = {} }
    local claimedSpellIDs, signatureParts = {}, {}
    for _, cooldownID in ipairs(cooldownIDs) do
        if BCDM:IsSecretValue(cooldownID) or type(cooldownID) ~= "number" then return nil, false end
        local okInfo, info = pcall(getCooldownInfo, cooldownID)
        if not okInfo or BCDM:IsSecretValue(info) then return nil, false end
        if not info then return nil, false end
        if info then
            local candidates, candidatesReadable = BCDM.BuildTrackedBuffAuraCandidates(info)
            if not candidatesReadable then return nil, false end
            local equipSlot, equipSlotReadable = ReadField(info, "equipSlot")
            local spellCategoryID, categoryReadable = ReadField(info, "spellCategoryID")
            if not equipSlotReadable or not categoryReadable then return nil, false end
            if equipSlot ~= nil and type(equipSlot) ~= "number" then return nil, false end
            if spellCategoryID ~= nil and type(spellCategoryID) ~= "number" then return nil, false end

            local uniqueCandidates = {}
            for _, spellID in ipairs(candidates) do
                if not claimedSpellIDs[spellID] then
                    claimedSpellIDs[spellID] = true
                    uniqueCandidates[#uniqueCandidates + 1] = spellID
                end
            end

            local isEquipment = type(equipSlot) == "number" and equipSlot > 0
            local isCategoryItem = type(spellCategoryID) == "number" and spellCategoryID > 0
            if isEquipment or isCategoryItem then
                local baseSpellID = select(1, ReadField(info, "spellID"))
                catalog.items[#catalog.items + 1] = {
                    cooldownID = cooldownID,
                    spellIDs = uniqueCandidates,
                    fallbackSpellID = type(baseSpellID) == "number" and baseSpellID > 0
                        and baseSpellID or candidates[1],
                    kind = isEquipment and "equipment" or "category",
                    equipSlot = isEquipment and equipSlot or nil,
                    spellCategoryID = isCategoryItem and spellCategoryID or nil,
                }
                signatureParts[#signatureParts + 1] = table.concat({
                    isEquipment and "E" or "I",
                    tostring(cooldownID),
                    tostring(isEquipment and equipSlot or spellCategoryID),
                    table.concat(uniqueCandidates, ","),
                }, ":")
            elseif #uniqueCandidates > 0 then
                catalog.auras[#catalog.auras + 1] = {
                    cooldownID = cooldownID,
                    spellIDs = uniqueCandidates,
                }
                signatureParts[#signatureParts + 1] = "A:" .. tostring(cooldownID)
                    .. ":" .. table.concat(uniqueCandidates, ",")
            end
        end
    end
    return catalog, true, table.concat(signatureParts, ";")
end

function BCDM.GetTrackedBuffFixedLayout(auraCount, itemCount, width, height, spacing, isHorizontal)
    auraCount = math.max(0, auraCount or 0)
    itemCount = math.max(0, itemCount or 0)
    spacing = spacing or 0
    local totalCount = auraCount + itemCount
    local auraExtent = 0
    if auraCount > 0 then
        auraExtent = auraCount * (isHorizontal and width or height) + (auraCount - 1) * spacing
    end
    local itemExtent = 0
    if itemCount > 0 then
        itemExtent = itemCount * (isHorizontal and width or height) + (itemCount - 1) * spacing
    end
    local sectionGap = auraCount > 0 and itemCount > 0 and spacing or 0
    local primaryExtent = auraExtent + sectionGap + itemExtent
    if totalCount == 0 then primaryExtent = 1 end
    return {
        auraExtent = auraExtent,
        itemExtent = itemExtent,
        sectionGap = sectionGap,
        width = isHorizontal and primaryExtent or width,
        height = isHorizontal and height or primaryExtent,
    }
end

local function ReplacementRequested()
    local profile = BCDM.db and BCDM.db.profile
    local settings = profile and profile.CooldownManager
    return settings and settings.Enable == true and settings.Buffs and settings.Buffs.CenterBuffs == true
end

function BCDM:IsTrackedBuffAuraReplacementEnabled()
    return ReplacementRequested()
end

function BCDM:ShouldStyleNativeTrackedBuffViewer()
    return not ReplacementRequested() or Runtime.editorVisible
end

local function EnsureAuraContainerLoaded()
    if type(CustomAuraContainerGroupDefaultOptions) == "table" then return true end
    if IsInCombat() then return false end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return type(CustomAuraContainerGroupDefaultOptions) == "table"
end

local function PositionOwner(width, height)
    local owner = Runtime.owner
    local profile = BCDM.db and BCDM.db.profile
    local settings = profile and profile.CooldownManager and profile.CooldownManager.Buffs
    local layout = settings and settings.Layout
    if not owner or type(layout) ~= "table" then return false end

    local anchorParent = BCDM:ResolveAnchorParent(layout[2])
    owner:ClearAllPoints()
    owner:SetSize(width or 1, height or 1)
    local okOwner = pcall(owner.SetPoint, owner,
        layout[1], anchorParent, layout[3], layout[4] or 0, layout[5] or 0)
    if not okOwner then
        owner:SetPoint(layout[1] or "CENTER", UIParent, layout[3] or "CENTER", layout[4] or 0, layout[5] or 0)
    end
    return okOwner
end

local function GetLayoutSettings()
    local viewer = BuffIconCooldownViewer
    local isHorizontal = true
    local goingForward = true
    local spacing = 0
    if viewer then
        local okHorizontal, horizontal = pcall(function() return viewer.isHorizontal end)
        if okHorizontal and not BCDM:IsSecretValue(horizontal) and type(horizontal) == "boolean" then
            isHorizontal = horizontal
        end
        local directionField = isHorizontal and "layoutFramesGoingRight" or "layoutFramesGoingUp"
        local okDirection, direction = pcall(function() return viewer[directionField] end)
        if okDirection and not BCDM:IsSecretValue(direction) and type(direction) == "boolean" then
            goingForward = direction
        end
        local spacingField = isHorizontal and "childXPadding" or "childYPadding"
        local okSpacing, nativeSpacing = pcall(function() return viewer[spacingField] end)
        if okSpacing and not BCDM:IsSecretValue(nativeSpacing) and type(nativeSpacing) == "number" then
            spacing = nativeSpacing
        end
    end
    return isHorizontal, goingForward, spacing
end

local function StyleDurationText(cooldown, button, settings)
    if not cooldown or not cooldown.GetRegions then return end
    local textSettings = BCDM.db.profile.CooldownManager.General.CooldownText
    local general = BCDM.db.profile.General
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            local fontSize = textSettings.FontSize or 12
            if textSettings.ScaleByIconSize then
                local width = BCDM:GetIconDimensions(settings)
                fontSize = fontSize * width / 36
            end
            region:SetFont(BCDM.Media.Font, fontSize, general.Fonts.FontFlag)
            region:SetTextColor(textSettings.Colour[1], textSettings.Colour[2], textSettings.Colour[3], 1)
            region:ClearAllPoints()
            local layout = textSettings.Layout
            region:SetPoint(layout[1], button, layout[2], layout[3], layout[4])
            break
        end
    end
end

local function InitializeAuraButton(auraButton)
    local settings = BCDM.db.profile.CooldownManager.Buffs
    local general = BCDM.db.profile.General
    local cooldownGeneral = BCDM.db.profile.CooldownManager.General
    local width, height = BCDM:GetIconDimensions(settings)
    local border = cooldownGeneral.BorderSize or 0
    local text = settings.Text

    auraButton:SetSize(width, height)
    local icon = auraButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", auraButton, "TOPLEFT", border, -border)
    icon:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", -border, border)
    BCDM:ApplyIconTexCoord(icon, width, height, (cooldownGeneral.IconZoom or 0) * 0.5)

    local cooldown = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", auraButton, "TOPLEFT", border, -border)
    cooldown:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", -border, border)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)
    if cooldown.SetSwipeTexture then cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8") end

    local count = auraButton:CreateFontString(nil, "OVERLAY")
    count:SetPoint(text.Layout[1], auraButton, text.Layout[2], text.Layout[3], text.Layout[4])
    count:SetFont(BCDM.Media.Font, text.FontSize or 12, general.Fonts.FontFlag)
    count:SetTextColor(text.Colour[1], text.Colour[2], text.Colour[3], 1)

    auraButton:SetDurationCooldown(cooldown)
    auraButton:SetIcon(icon)
    auraButton:SetApplicationCount(count, {})
    if auraButton.SetMouseMotionEnabled then auraButton:SetMouseMotionEnabled(true)
    else auraButton:EnableMouse(true) end
    BCDM:AddBorder(auraButton)
    StyleDurationText(cooldown, auraButton, settings)
end

local function ReadNumber(value)
    if type(value) ~= "number" or BCDM:IsSecretValue(value) then return end
    return value
end

local function ReadTexture(value)
    if BCDM:IsSecretValue(value) then return end
    if type(value) == "number" or type(value) == "string" then return value end
end

local function SetReadableItemCount(itemFrame, count)
    count = ReadNumber(count)
    if not count then return end
    itemFrame.Count:SetText(count > 1 and tostring(count) or "")
end

local function RequestItemData(itemID)
    if not itemID or requestedItemData[itemID] or not C_Item
        or type(C_Item.RequestLoadItemDataByID) ~= "function" then return end
    requestedItemData[itemID] = true
    pcall(C_Item.RequestLoadItemDataByID, itemID)
end

local function ResolveItemTexture(itemID)
    if not itemID or not C_Item then return end
    if type(C_Item.GetItemIconByID) == "function" then
        local ok, texture = pcall(C_Item.GetItemIconByID, itemID)
        texture = ok and ReadTexture(texture) or nil
        if texture then return texture end
    end
    if type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, texture = pcall(C_Item.GetItemInfoInstant, itemID)
        texture = ok and ReadTexture(texture) or nil
        if texture then return texture end
    end
end

local function ResolveSpellTexture(spellID)
    if not spellID or not C_Spell or type(C_Spell.GetSpellTexture) ~= "function" then return end
    local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
    return ok and ReadTexture(texture) or nil
end

local function ForwardCooldown(cooldown, getter, ...)
    if not cooldown or type(getter) ~= "function" then return false end
    local arguments = { ... }
    -- Timing can become secret in combat. Pass it straight to the BCM widget;
    -- if the client rejects that aspect, retain the last safe visual.
    return pcall(function()
        local startTime, duration = getter(Unpack(arguments))
        cooldown:SetCooldown(startTime, duration)
    end)
end

BCDM.ForwardTrackedBuffItemCooldown = ForwardCooldown

local function ApplyItemStyle(itemFrame)
    local settings = BCDM.db.profile.CooldownManager.Buffs
    local general = BCDM.db.profile.General
    local cooldownGeneral = BCDM.db.profile.CooldownManager.General
    local width, height = BCDM:GetIconDimensions(settings)
    local border = cooldownGeneral.BorderSize or 0
    local text = settings.Text

    itemFrame:SetSize(width, height)
    itemFrame.Icon:ClearAllPoints()
    itemFrame.Icon:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", border, -border)
    itemFrame.Icon:SetPoint("BOTTOMRIGHT", itemFrame, "BOTTOMRIGHT", -border, border)
    BCDM:ApplyIconTexCoord(itemFrame.Icon, width, height, (cooldownGeneral.IconZoom or 0) * 0.5)

    itemFrame.Cooldown:ClearAllPoints()
    itemFrame.Cooldown:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", border, -border)
    itemFrame.Cooldown:SetPoint("BOTTOMRIGHT", itemFrame, "BOTTOMRIGHT", -border, border)
    itemFrame.Cooldown:SetDrawEdge(false)
    itemFrame.Cooldown:SetDrawBling(false)
    itemFrame.Cooldown:SetDrawSwipe(true)
    itemFrame.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    if itemFrame.Cooldown.SetSwipeTexture then
        itemFrame.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
    end

    itemFrame.Count:ClearAllPoints()
    itemFrame.Count:SetPoint(text.Layout[1], itemFrame, text.Layout[2], text.Layout[3], text.Layout[4])
    itemFrame.Count:SetFont(BCDM.Media.Font, text.FontSize or 12, general.Fonts.FontFlag)
    itemFrame.Count:SetTextColor(text.Colour[1], text.Colour[2], text.Colour[3], 1)
    BCDM:AddBorder(itemFrame)
    StyleDurationText(itemFrame.Cooldown, itemFrame, settings)
end

local function SetItemTooltip(itemFrame)
    local entry = itemFrame.Entry
    if not entry then return end
    GameTooltip:SetOwner(itemFrame, "ANCHOR_CURSOR")
    if entry.kind == "equipment" and entry.equipSlot then
        pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", entry.equipSlot)
    elseif itemFrame.ItemID then
        pcall(GameTooltip.SetItemByID, GameTooltip, itemFrame.ItemID)
    elseif itemFrame.SpellID then
        pcall(GameTooltip.SetSpellByID, GameTooltip, itemFrame.SpellID)
    end
    GameTooltip:Show()
end

local function CreateItemFrame(parent)
    local itemFrame = CreateFrame("Button", nil, parent)
    itemFrame.Icon = itemFrame:CreateTexture(nil, "BACKGROUND")
    itemFrame.Cooldown = CreateFrame("Cooldown", nil, itemFrame, "CooldownFrameTemplate")
    itemFrame.Count = itemFrame:CreateFontString(nil, "OVERLAY")
    itemFrame:SetScript("OnEnter", SetItemTooltip)
    itemFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    itemFrame:EnableMouse(true)

    local auraLayer = CreateFrame("Frame", nil, itemFrame)
    auraLayer:SetAllPoints(itemFrame)
    auraLayer:SetFrameLevel((itemFrame:GetFrameLevel() or 1) + 10)
    local auraContainer = CreateFrame("AuraContainer", nil, auraLayer, "CustomAuraContainerTemplate")
    auraContainer:SetAllPoints(auraLayer)
    auraContainer:SetUnit("player")
    local initialized = false
    local ok, auraButton = Call(auraContainer, "AddAuraSlot", "active", FILTER, {
        candidateFilters = { includeSpellIDs = {} },
        initializeFrame = function(button)
            button:ClearAllPoints()
            button:SetAllPoints(auraContainer)
            button:SetFrameLevel(auraLayer:GetFrameLevel() + 1)
            InitializeAuraButton(button)
            initialized = true
        end,
    })
    if not ok or not auraButton or not initialized or not Call(auraContainer, "SetEnabled", true) then
        auraLayer:Hide()
        itemFrame.AuraContainer = nil
    else
        itemFrame.AuraContainer = auraContainer
    end
    ApplyItemStyle(itemFrame)
    return itemFrame
end

local function EnsureItemCapacity(required)
    if not Runtime.itemStrip then
        Runtime.itemStrip = CreateFrame("Frame", nil, Runtime.owner)
        Runtime.itemStrip:SetSize(1, 1)
    end
    if IsInCombat() and Runtime.itemCapacity < required then return false end
    while Runtime.itemCapacity < required do
        local itemFrame = CreateItemFrame(Runtime.itemStrip)
        Runtime.itemCapacity = Runtime.itemCapacity + 1
        Runtime.itemFrames[Runtime.itemCapacity] = itemFrame
    end
    return true
end

local function UpdateItemFrame(itemFrame)
    local entry = itemFrame and itemFrame.Entry
    if not entry then return end

    local texture
    if entry.kind == "equipment" then
        if type(GetInventoryItemID) == "function" then
            local ok, itemID = pcall(GetInventoryItemID, "player", entry.equipSlot)
            if ok and not BCDM:IsSecretValue(itemID) then
                if type(itemID) == "number" then
                    if itemFrame.ItemID ~= itemID then itemFrame.Count:SetText("") end
                    itemFrame.ItemID = itemID
                    RequestItemData(itemID)
                elseif itemID == nil then
                    itemFrame.ItemID = nil
                    itemFrame.Count:SetText("")
                end
            end
        end
        if type(GetInventoryItemTexture) == "function" then
            local ok, inventoryTexture = pcall(GetInventoryItemTexture, "player", entry.equipSlot)
            if ok then texture = ReadTexture(inventoryTexture) end
        end
        texture = texture or ResolveItemTexture(itemFrame.ItemID)
        if type(GetInventoryItemCooldown) == "function" then
            ForwardCooldown(itemFrame.Cooldown, GetInventoryItemCooldown, "player", entry.equipSlot)
        end
    else
        if C_Spell and type(C_Spell.GetLastCategoryCooldownSource) == "function" then
            local ok, spellID, itemID = pcall(C_Spell.GetLastCategoryCooldownSource, entry.spellCategoryID)
            if ok and not BCDM:IsSecretValue(spellID) and not BCDM:IsSecretValue(itemID) then
                if type(spellID) == "number" and spellID > 0 then itemFrame.SpellID = spellID end
                if type(itemID) == "number" and itemID > 0 then
                    if itemFrame.ItemID ~= itemID then itemFrame.Count:SetText("") end
                    itemFrame.ItemID = itemID
                    RequestItemData(itemID)
                end
            end
        end
        itemFrame.SpellID = itemFrame.SpellID or entry.fallbackSpellID
        texture = ResolveItemTexture(itemFrame.ItemID) or ResolveSpellTexture(itemFrame.SpellID)
            or CATEGORY_FALLBACK_TEXTURES[entry.spellCategoryID]
        if itemFrame.ItemID and C_Item and type(C_Item.GetItemCount) == "function" then
            local ok, count = pcall(C_Item.GetItemCount, itemFrame.ItemID)
            if ok and not BCDM:IsSecretValue(count) then SetReadableItemCount(itemFrame, count) end
        end

        local cooldownApplied = false
        if itemFrame.SpellID and C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function"
            and itemFrame.Cooldown.SetCooldownFromDurationObject then
            local okDuration, duration = pcall(C_Spell.GetSpellCooldownDuration, itemFrame.SpellID)
            if okDuration and not BCDM:IsSecretValue(duration) and duration then
                cooldownApplied = pcall(itemFrame.Cooldown.SetCooldownFromDurationObject,
                    itemFrame.Cooldown, duration, true)
            end
        end
        if not cooldownApplied and itemFrame.ItemID and C_Item
            and type(C_Item.GetItemCooldown) == "function" then
            ForwardCooldown(itemFrame.Cooldown, C_Item.GetItemCooldown, itemFrame.ItemID)
        end
    end

    if texture then itemFrame.Icon:SetTexture(texture)
    elseif not itemFrame.Icon:GetTexture() then itemFrame.Icon:SetTexture(134400) end
end

local function QueueItemRefresh()
    if Runtime.itemRefreshScheduled then return end
    Runtime.itemRefreshScheduled = true
    C_Timer.After(0, function()
        Runtime.itemRefreshScheduled = false
        if not Runtime.ready or Runtime.editorVisible or not ReplacementRequested() then return end
        for index = 1, #Runtime.itemCatalog do UpdateItemFrame(Runtime.itemFrames[index]) end
    end)
end

local function ApplyItemCatalog(items)
    if not EnsureItemCapacity(#items) then return false end
    Runtime.itemCatalog = items
    for index = 1, Runtime.itemCapacity do
        local itemFrame = Runtime.itemFrames[index]
        local entry = items[index]
        if entry and itemFrame.CooldownID ~= entry.cooldownID then
            itemFrame.CooldownID = entry.cooldownID
            itemFrame.ItemID = nil
            itemFrame.SpellID = nil
            itemFrame.Count:SetText("")
            itemFrame.Icon:SetTexture(nil)
            Call(itemFrame.Cooldown, "Clear")
        end
        itemFrame.Entry = entry
        if entry then
            ApplyItemStyle(itemFrame)
            if itemFrame.AuraContainer then
                local includeSpellIDs = {}
                for _, spellID in ipairs(entry.spellIDs) do includeSpellIDs[spellID] = true end
                if not Call(itemFrame.AuraContainer, "SetAuraSlotCandidateFilters", "active",
                    { includeSpellIDs = includeSpellIDs })
                    or not Call(itemFrame.AuraContainer, "SetEnabled", #entry.spellIDs > 0) then
                    return false
                end
            end
            UpdateItemFrame(itemFrame)
            itemFrame:Show()
        else
            itemFrame.CooldownID = nil
            itemFrame.ItemID = nil
            itemFrame.SpellID = nil
            if itemFrame.AuraContainer then Call(itemFrame.AuraContainer, "SetEnabled", false) end
            itemFrame:Hide()
        end
    end
    return true
end

local function LayoutItemFrames(isHorizontal, goingForward, spacing)
    local previous
    for index = 1, #Runtime.itemCatalog do
        local itemFrame = Runtime.itemFrames[index]
        itemFrame:ClearAllPoints()
        if not previous then
            if isHorizontal then
                itemFrame:SetPoint(goingForward and "LEFT" or "RIGHT", Runtime.itemStrip,
                    goingForward and "LEFT" or "RIGHT", 0, 0)
            else
                itemFrame:SetPoint(goingForward and "BOTTOM" or "TOP", Runtime.itemStrip,
                    goingForward and "BOTTOM" or "TOP", 0, 0)
            end
        elseif isHorizontal then
            itemFrame:SetPoint(goingForward and "LEFT" or "RIGHT", previous,
                goingForward and "RIGHT" or "LEFT", goingForward and spacing or -spacing, 0)
        else
            itemFrame:SetPoint(goingForward and "BOTTOM" or "TOP", previous,
                goingForward and "TOP" or "BOTTOM", 0, goingForward and spacing or -spacing)
        end
        previous = itemFrame
    end
end

local function ConfigureFixedLayout(auraCount, itemCount)
    local settings = BCDM.db.profile.CooldownManager.Buffs
    local width, height = BCDM:GetIconDimensions(settings)
    local isHorizontal, goingForward, spacing = GetLayoutSettings()
    local layout = BCDM.GetTrackedBuffFixedLayout(
        auraCount, itemCount, width, height, spacing, isHorizontal)
    if not PositionOwner(layout.width, layout.height) then return false end

    -- The AuraContainer's live size is secret-wrapped. Both sections therefore
    -- anchor to the fixed owner instead of propagating that layout aspect into item frames.
    Runtime.container:ClearAllPoints()
    Runtime.itemStrip:ClearAllPoints()
    if isHorizontal then
        local startPoint = goingForward and "LEFT" or "RIGHT"
        Runtime.container:SetPoint(startPoint, Runtime.owner, startPoint, 0, 0)
        Runtime.itemStrip:SetSize(math.max(1, layout.itemExtent), height)
        Runtime.itemStrip:SetPoint(startPoint, Runtime.owner, startPoint,
            goingForward and (layout.auraExtent + layout.sectionGap)
                or -(layout.auraExtent + layout.sectionGap), 0)
    else
        local startPoint = goingForward and "BOTTOM" or "TOP"
        Runtime.container:SetPoint(startPoint, Runtime.owner, startPoint, 0, 0)
        Runtime.itemStrip:SetSize(width, math.max(1, layout.itemExtent))
        Runtime.itemStrip:SetPoint(startPoint, Runtime.owner, startPoint, 0,
            goingForward and (layout.auraExtent + layout.sectionGap)
                or -(layout.auraExtent + layout.sectionGap))
    end
    LayoutItemFrames(isHorizontal, goingForward, spacing)
    return true
end

local function ConfigureContainerLayout(container, groupCount)
    local settings = BCDM.db.profile.CooldownManager.Buffs
    local width, height = BCDM:GetIconDimensions(settings)
    local isHorizontal, goingForward, spacing = GetLayoutSettings()
    local horizontalDirection = goingForward and AnchorUtil.FlowDirection.Right or AnchorUtil.FlowDirection.Left
    local verticalDirection = goingForward and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down
    if isHorizontal then verticalDirection = AnchorUtil.FlowDirection.Down
    else horizontalDirection = AnchorUtil.FlowDirection.Right end

    local anchorPoint
    if horizontalDirection == AnchorUtil.FlowDirection.Left then
        anchorPoint = verticalDirection == AnchorUtil.FlowDirection.Up and "BOTTOMRIGHT" or "TOPRIGHT"
    else
        anchorPoint = verticalDirection == AnchorUtil.FlowDirection.Up and "BOTTOMLEFT" or "TOPLEFT"
    end
    container:SetFlowLayoutAnchorPoint(anchorPoint)
    container:SetFlowLayoutGrowthDirection(horizontalDirection, verticalDirection)
    container:SetFlowLayoutMaximumLineSize(math.huge)

    for index = 1, groupCount do
        container:SetAuraGroupLayout(Runtime.groups[index].key, {
            elementWidth = width,
            elementHeight = height,
            gapX = isHorizontal and (index > 1 and spacing or 0) or 0,
            gapY = not isHorizontal and (index > 1 and spacing or 0) or 0,
        })
    end
end

local function CreateContainer(capacity)
    if not Runtime.owner then
        Runtime.owner = CreateFrame("Frame", "BCDM_TrackedBuffAuraViewer", UIParent)
        Runtime.owner:SetSize(1, 1)
        Runtime.owner:SetFrameStrata("LOW")
        Runtime.owner:Hide()
    end

    local container = CreateFrame("AuraContainer", nil, Runtime.owner, "CustomAuraContainerTemplate")
    container:SetPoint("CENTER", Runtime.owner, "CENTER")
    container:SetUnit("player")
    local groups = {}
    for index = 1, capacity do
        local key = "trackedBuff" .. index
        local ok = pcall(container.AddAuraGroup, container, key, FILTER, {
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = InitializeAuraButton,
            layout = {},
        })
        if not ok then
            container:SetEnabled(false)
            container:Hide()
            return nil
        end
        groups[index] = { key = key }
    end
    return container, groups
end

local function EnsureContainerCapacity(required)
    required = math.max(1, required)
    if Runtime.container and Runtime.capacity >= required then return true end
    local container, groups = CreateContainer(required)
    if not container then return false end
    if Runtime.container then
        Runtime.container:SetEnabled(false)
        Runtime.container:Hide()
    end
    Runtime.container = container
    Runtime.groups = groups
    Runtime.capacity = required
    return true
end

local function SetReplacementShown(shown)
    shown = shown == true and Runtime.ready and ReplacementRequested() and not Runtime.editorVisible
    if Runtime.owner then Runtime.owner:SetShown(shown) end
end

local function ReadNativeCooldownIDs()
    local viewer = BuffIconCooldownViewer
    if not viewer or type(viewer.GetCooldownIDs) ~= "function" then return nil, false end
    local okIDs, cooldownIDs = pcall(viewer.GetCooldownIDs, viewer)
    if not okIDs or BCDM:IsSecretValue(cooldownIDs) or type(cooldownIDs) ~= "table" then
        return nil, false
    end

    local okCount, count = pcall(function() return #cooldownIDs end)
    if not okCount or BCDM:IsSecretValue(count) or type(count) ~= "number" then return nil, false end
    local readableIDs = {}
    for index = 1, count do
        local okID, cooldownID = pcall(function() return cooldownIDs[index] end)
        if not okID or BCDM:IsSecretValue(cooldownID) or type(cooldownID) ~= "number" then
            return nil, false
        end
        readableIDs[index] = cooldownID
    end
    return readableIDs, true
end

local function ApplyCatalog(catalog, signature)
    local auras = catalog.auras or {}
    local items = catalog.items or {}
    if #auras == 0 and #items == 0 then return false end
    if not EnsureContainerCapacity(#auras) or not ApplyItemCatalog(items) then return false end
    local container = Runtime.container
    for index = 1, Runtime.capacity do
        local includeSpellIDs = {}
        local entry = auras[index]
        if entry then
            for _, spellID in ipairs(entry.spellIDs) do includeSpellIDs[spellID] = true end
        end
        if not Call(container, "SetAuraGroupCandidateFilters", Runtime.groups[index].key,
            { includeSpellIDs = includeSpellIDs }) then
            return false
        end
    end
    ConfigureContainerLayout(container, #auras)
    if not ConfigureFixedLayout(#auras, #items) then return false end
    Runtime.signature = signature
    Runtime.ready = true
    Runtime.attempts = 0
    SetReplacementShown(true)
    return true
end

local function FailReplacement()
    Runtime.ready = false
    SetReplacementShown(false)
    if BCDM.QueueCooldownViewerLayoutApply then BCDM:QueueCooldownViewerLayoutApply() end
end

local TryRefresh

local function ScheduleRefresh()
    if Runtime.scheduled then return end
    Runtime.scheduled = true
    C_Timer.After(0, function()
        Runtime.scheduled = false
        TryRefresh()
    end)
end

TryRefresh = function()
    if not Runtime.pending then return end
    if IsInCombat() or (BCDM.IsCooldownViewerInteractionActive and BCDM:IsCooldownViewerInteractionActive()) then return end
    Runtime.pending = false

    if not ReplacementRequested() then
        Runtime.ready = false
        SetReplacementShown(false)
        if BCDM.QueueCooldownViewerLayoutApply then BCDM:QueueCooldownViewerLayoutApply() end
        return
    end
    if not EnsureAuraContainerLoaded() then
        FailReplacement()
        return
    end

    local cooldownIDs, cooldownIDsReadable = ReadNativeCooldownIDs()
    local catalog, readable, signature
    if cooldownIDsReadable and C_CooldownViewer
        and type(C_CooldownViewer.GetCooldownViewerCooldownInfo) == "function" then
        catalog, readable, signature = BCDM.BuildTrackedBuffAuraCatalog(
            cooldownIDs, C_CooldownViewer.GetCooldownViewerCooldownInfo)
    end
    if not readable then
        Runtime.attempts = Runtime.attempts + 1
        if Runtime.attempts < MAX_REFRESH_ATTEMPTS then
            Runtime.pending = true
            C_Timer.After(0, ScheduleRefresh)
        else
            Runtime.attempts = 0
            FailReplacement()
        end
        return
    end

    if #catalog.auras == 0 and #catalog.items == 0 then
        FailReplacement()
        return
    end

    if not ApplyCatalog(catalog, signature) then
        FailReplacement()
        return
    end
    if BCDM.QueueCooldownViewerLayoutApply then BCDM:QueueCooldownViewerLayoutApply() end
end

function BCDM:QueueTrackedBuffAuraRefresh()
    Runtime.pending = true
    ScheduleRefresh()
end

function BCDM:SetTrackedBuffAuraEditorVisible(visible, suppressRefresh)
    Runtime.editorVisible = visible == true
    SetReplacementShown(not Runtime.editorVisible)
    if not Runtime.editorVisible and not suppressRefresh then self:QueueTrackedBuffAuraRefresh("editor-closed") end
end

local function VisibilityStore()
    if not BCDM.db or not BCDM.db.global then return end
    BCDM.db.global.CooldownViewer = BCDM.db.global.CooldownViewer or {}
    local settings = BCDM.db.global.CooldownViewer
    settings.NativeTrackedBuffVisibility = settings.NativeTrackedBuffVisibility or {}
    return settings.NativeTrackedBuffVisibility
end

local function GetActiveLayoutKey(LEMO)
    local ok, layoutName = pcall(LEMO.GetActiveLayout, LEMO)
    if not ok or type(layoutName) ~= "string" or layoutName == "" then return end
    return layoutName
end

function BCDM:PrepareTrackedBuffVisibilityOverride(LEMO)
    local viewer = BuffIconCooldownViewer
    local visibilitySetting = Enum and Enum.EditModeCooldownViewerSetting
        and Enum.EditModeCooldownViewerSetting.VisibleSetting
    local iconSizeSetting = Enum and Enum.EditModeCooldownViewerSetting
        and Enum.EditModeCooldownViewerSetting.IconSize
    local hidden = Enum and Enum.CooldownViewerVisibleSetting and Enum.CooldownViewerVisibleSetting.Hidden
    local store = VisibilityStore()
    local layoutKey = LEMO and store and GetActiveLayoutKey(LEMO)
    if not viewer or not visibilitySetting or not iconSizeSetting or hidden == nil or not layoutKey then return false end

    local record = store[layoutKey]
    if Runtime.ready and ReplacementRequested() then
        if not record then
            local okVisibility, originalVisibility = pcall(
                LEMO.GetFrameSetting, LEMO, viewer, visibilitySetting)
            local okIconSize, originalIconSize = pcall(
                LEMO.GetFrameSetting, LEMO, viewer, iconSizeSetting)
            if not okVisibility or type(originalVisibility) ~= "number"
                or not okIconSize or type(originalIconSize) ~= "number" then
                FailReplacement()
                return false
            end
            record = { value = originalVisibility, iconSize = originalIconSize }
            store[layoutKey] = record
        elseif type(record.iconSize) ~= "number" then
            local okIconSize, originalIconSize = pcall(
                LEMO.GetFrameSetting, LEMO, viewer, iconSizeSetting)
            if not okIconSize or type(originalIconSize) ~= "number" then
                FailReplacement()
                return false
            end
            record.iconSize = originalIconSize
        end
        local buffSettings = BCDM.db.profile.CooldownManager.Buffs
        local iconWidth = BCDM:GetIconDimensions(buffSettings)
        local nativeIconScale = math.max(50, math.min(200,
            math.floor((iconWidth / NATIVE_BUFF_ICON_SIZE * 100) + 0.5)))
        local okHidden = pcall(LEMO.SetFrameSetting, LEMO, viewer, visibilitySetting, hidden)
        local okScaled = pcall(LEMO.SetFrameSetting, LEMO, viewer, iconSizeSetting, nativeIconScale)
        if not okHidden or not okScaled then
            FailReplacement()
            return false
        end
        Runtime.pendingVisibilityRestore = nil
        return true
    end

    if record and type(record.value) == "number" then
        local okVisibility = pcall(
            LEMO.SetFrameSetting, LEMO, viewer, visibilitySetting, record.value)
        local okIconSize = type(record.iconSize) ~= "number"
            or pcall(LEMO.SetFrameSetting, LEMO, viewer, iconSizeSetting, record.iconSize)
        if okVisibility and okIconSize then Runtime.pendingVisibilityRestore = layoutKey end
        return okVisibility and okIconSize
    end
    return true
end

function BCDM:CommitTrackedBuffVisibilityOverride()
    local layoutKey = Runtime.pendingVisibilityRestore
    if not layoutKey then return end
    local store = VisibilityStore()
    if store then store[layoutKey] = nil end
    Runtime.pendingVisibilityRestore = nil
end

function BCDM:RestoreTrackedBuffVisibilityForLogout()
    local LEMO = self.LEMO
    local viewer = BuffIconCooldownViewer
    if not LEMO or not viewer or not LEMO.IsReady or not LEMO:IsReady() then return end
    local ok = pcall(function()
        LEMO:LoadLayouts()
        local layoutKey = GetActiveLayoutKey(LEMO)
        local store = VisibilityStore()
        local record = layoutKey and store and store[layoutKey]
        local visibilitySetting = Enum.EditModeCooldownViewerSetting.VisibleSetting
        local iconSizeSetting = Enum.EditModeCooldownViewerSetting.IconSize
        if record and type(record.value) == "number" then
            LEMO:SetFrameSetting(viewer, visibilitySetting, record.value)
            if type(record.iconSize) == "number" then
                LEMO:SetFrameSetting(viewer, iconSizeSetting, record.iconSize)
            end
            LEMO:SaveOnly()
            store[layoutKey] = nil
        end
    end)
    return ok
end

function BCDM:SetupTrackedBuffAuraViewer()
    if Runtime.eventFrame then return end
    Runtime.eventFrame = CreateFrame("Frame")
    Runtime.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    Runtime.eventFrame:RegisterEvent("PLAYER_LOGOUT")
    Runtime.eventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    Runtime.eventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    Runtime.eventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
    Runtime.eventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
    Runtime.eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    Runtime.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    Runtime.eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    Runtime.eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    Runtime.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    Runtime.eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGOUT" then
            BCDM:RestoreTrackedBuffVisibilityForLogout()
        elseif event == "BAG_UPDATE_COOLDOWN" or event == "BAG_UPDATE_DELAYED"
            or event == "ITEM_DATA_LOAD_RESULT" or event == "PLAYER_EQUIPMENT_CHANGED"
            or event == "SPELL_UPDATE_COOLDOWN" then
            QueueItemRefresh()
        else
            BCDM:QueueTrackedBuffAuraRefresh("combat-ended")
        end
    end)
    self:QueueTrackedBuffAuraRefresh("setup")
end
