local _, BCDM = ...

local TRINKET_SLOTS = { 13, 14 }
local slotIcons = {}
local pendingItemData = {}
local DEFAULT_ENTRY_SETTINGS = {
    DisplayMode = "ALWAYS", VisualMode = "FULL", Alpha = 0.45,
    Glow = "NONE", TextEnabled = true, Tooltip = true,
}
BCDM.TrinketBarIcons = slotIcons

function BCDM:GetTrinketSlotOrder(settings)
    if type(settings) ~= "table" then return TRINKET_SLOTS end
    local order, seen = {}, {}
    for _, slotID in ipairs(type(settings.SlotOrder) == "table" and settings.SlotOrder or {}) do
        if (slotID == 13 or slotID == 14) and not seen[slotID] then
            order[#order + 1], seen[slotID] = slotID, true
        end
    end
    for _, slotID in ipairs(TRINKET_SLOTS) do
        if not seen[slotID] then order[#order + 1] = slotID end
    end
    settings.SlotOrder = order
    return order
end

function BCDM:ReorderTrinketSlot(settings, slotID, targetIndex)
    local order = self:GetTrinketSlotOrder(settings)
    targetIndex = tonumber(targetIndex)
    if not targetIndex then return false end
    targetIndex = math.max(1, math.min(#order, math.floor(targetIndex)))
    for index, candidate in ipairs(order) do
        if candidate == slotID then
            if index == targetIndex then return false end
            table.remove(order, index)
            table.insert(order, targetIndex, slotID)
            return true
        end
    end
    return false
end

function BCDM:GetTrinketSlotRecord(settings, slotID)
    if type(settings) ~= "table" then return end
    settings.Slots = type(settings.Slots) == "table" and settings.Slots or {}
    local slot = settings.Slots[slotID]
    if type(slot) ~= "table" then
        slot = { Enabled = true, OverrideBarSettings = false }
        settings.Slots[slotID] = slot
    end
    return slot
end

function BCDM:GetTrinketSlotSettings(settings, slotID)
    local slot = self:GetTrinketSlotRecord(settings, slotID)
    if slot and slot.OverrideBarSettings == true then return slot end
    return type(settings) == "table" and type(settings.EntrySettings) == "table"
        and settings.EntrySettings or DEFAULT_ENTRY_SETTINGS
end

local function ReadNumber(value)
    if BCDM:IsSecretValue(value) or type(value) ~= "number" then return end
    return value
end

local function FetchCooldownTextRegion(cooldown)
    if not cooldown then return end
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            return region
        end
    end
end

local function ApplyCooldownText()
    local CooldownManagerDB = BCDM.db.profile
    local GeneralDB = CooldownManagerDB.General
    local CooldownTextDB = CooldownManagerDB.CooldownManager.General.CooldownText
    local Viewer = _G["BCDM_TrinketBar"]
    if not Viewer then return end
    for _, icon in ipairs({ Viewer:GetChildren() }) do
        if icon and icon.Cooldown then
            local textRegion = FetchCooldownTextRegion(icon.Cooldown)
            if textRegion then
                if CooldownTextDB.ScaleByIconSize then
                    local iconWidth = icon:GetWidth()
                    local scaleFactor = iconWidth / 36
                    textRegion:SetFont(BCDM.Media.Font, CooldownTextDB.FontSize * scaleFactor, GeneralDB.Fonts.FontFlag)
                else
                    textRegion:SetFont(BCDM.Media.Font, CooldownTextDB.FontSize, GeneralDB.Fonts.FontFlag)
                end
                textRegion:SetTextColor(CooldownTextDB.Colour[1], CooldownTextDB.Colour[2], CooldownTextDB.Colour[3], 1)
                textRegion:ClearAllPoints()
                textRegion:SetPoint(CooldownTextDB.Layout[1], icon, CooldownTextDB.Layout[2], CooldownTextDB.Layout[3], CooldownTextDB.Layout[4])
                if GeneralDB.Fonts.Shadow.Enabled then
                    textRegion:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
                    textRegion:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
                else
                    textRegion:SetShadowColor(0, 0, 0, 0)
                    textRegion:SetShadowOffset(0, 0)
                end
            end
        end
    end
end

local function SetIconDesaturation(icon, value)
    if not icon then return end
    if icon.SetDesaturation then
        icon:SetDesaturation(value)
        return
    end
    if icon.SetDesaturated then
        icon:SetDesaturated(value > 0)
    end
end

local function ClearCooldown(cooldown)
    if C_DurationUtil and C_DurationUtil.CreateDuration and cooldown.SetCooldownFromDurationObject then
        cooldown:SetCooldownFromDurationObject(C_DurationUtil.CreateDuration(), true)
    elseif cooldown.Clear then
        cooldown:Clear()
    end
end

local function GetItemSpellData(itemId)
    if not itemId then return nil, false end
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemId) then
        if not pendingItemData[itemId] then
            pendingItemData[itemId] = true
            C_Item.RequestLoadItemDataByID(itemId)
        end
        return nil, false
    end
    local spellName, spellID = C_Item.GetItemSpell(itemId)
    spellID = ReadNumber(spellID)
    local hasSpellName = type(spellName) == "string" and not BCDM:IsSecretValue(spellName) and spellName ~= ""
    return spellID, (spellID and spellID > 0) or hasSpellName
end

local function GetInventoryTooltipOnUseState(slotID)
    local lineTypes = Enum and Enum.TooltipDataLineType
    local onUseType = lineTypes and lineTypes.ItemSpellTriggerOnUse
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem and onUseType) then return end

    local okTooltip, tooltipData = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
    if not okTooltip or type(tooltipData) ~= "table" then return end

    local okLines, lines = pcall(function() return tooltipData.lines end)
    if not okLines or type(lines) ~= "table" then return end
    for _, line in ipairs(lines) do
        local okType, lineType = pcall(function() return line.type end)
        if okType and not BCDM:IsSecretValue(lineType) and lineType == onUseType then
            return true
        end
    end

    -- Structured tooltip data is authoritative: passive equip/proc effects can
    -- still expose an item spell or a cooldown-viewer catalog entry.
    return false
end

local function GetTrinketAuraSpellIDs(slotID, itemSpellID)
    local spellIDs, seen = {}, {}
    local hasCatalogEntry, hasOnUseEntry = false, false
    local function AddSpellID(spellID)
        spellID = ReadNumber(spellID)
        if spellID and spellID > 0 and not seen[spellID] then
            seen[spellID] = true
            spellIDs[#spellIDs + 1] = spellID
        end
    end
    local function ReadInfoNumber(info, key)
        local ok, value = pcall(function() return info[key] end)
        if not ok then return end
        return ReadNumber(value)
    end
    AddSpellID(itemSpellID)

    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        and C_CooldownViewer.GetCooldownViewerCooldownInfo and Enum.CooldownViewerCategory) then
        return spellIDs, false, false
    end
    for _, category in ipairs({
        Enum.CooldownViewerCategory.EquipSlotEssential,
        Enum.CooldownViewerCategory.EquipSlotTracked,
    }) do
        local okSet, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        if okSet and type(cooldownIDs) == "table" then
            for _, cooldownID in ipairs(cooldownIDs) do
                local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                if okInfo and type(info) == "table" and ReadInfoNumber(info, "equipSlot") == slotID then
                    hasCatalogEntry = true
                    if category == Enum.CooldownViewerCategory.EquipSlotEssential then hasOnUseEntry = true end
                    AddSpellID(ReadInfoNumber(info, "spellID"))
                    AddSpellID(ReadInfoNumber(info, "overrideSpellID"))
                    AddSpellID(ReadInfoNumber(info, "overrideTooltipSpellID"))
                    local okLinked, linkedSpellIDs = pcall(function() return info.linkedSpellIDs end)
                    if okLinked and type(linkedSpellIDs) == "table" then
                        for _, linkedSpellID in ipairs(linkedSpellIDs) do AddSpellID(linkedSpellID) end
                    end
                end
            end
        end
    end
    return spellIDs, hasOnUseEntry, hasCatalogEntry
end

BCDM._GetTrinketAuraSpellIDs = GetTrinketAuraSpellIDs

local function PlayerMatchesFilters(entrySettings)
    local classToken = select(2, UnitClass("player"))
    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then specID, specName = GetSpecializationInfo(specIndex) end
    return BCDM:EntryMatchesSpecialization(entrySettings, specID, classToken, specName)
end

local function GetTrinketCooldownState(slotID)
    local startTime, durationTime, enabled = GetInventoryItemCooldown("player", slotID)
    startTime, durationTime = ReadNumber(startTime), ReadNumber(durationTime)
    local state = { active = nil, ready = nil }
    if startTime and durationTime and not BCDM:IsSecretValue(enabled) then
        state.active = enabled ~= false and startTime > 0 and durationTime > 0
        state.ready = not state.active
        if state.active and C_DurationUtil and C_DurationUtil.CreateDuration then
            state.durationObject = C_DurationUtil.CreateDuration()
            state.durationObject:SetTimeFromStart(startTime, durationTime)
        end
    end
    return state
end

local function FetchEquippedTrinkets(settings)
    local equipped = {}
    local previewing = BCDM.TrinketSettingsPreview == true
    for _, slotID in ipairs(BCDM:GetTrinketSlotOrder(settings)) do
        local itemId = GetInventoryItemID("player", slotID)
        itemId = ReadNumber(itemId)
        if itemId then
            local spellID, itemHasSpell = GetItemSpellData(itemId)
            local auraSpellIDs, catalogOnUse, hasCatalogEntry = GetTrinketAuraSpellIDs(slotID, spellID)
            local isOnUse = GetInventoryTooltipOnUseState(slotID)
            if isOnUse == nil then
                isOnUse = hasCatalogEntry and catalogOnUse or itemHasSpell
            end
            local slot = BCDM:GetTrinketSlotRecord(settings, slotID)
            local entrySettings = BCDM:GetTrinketSlotSettings(settings, slotID)
            local state = GetTrinketCooldownState(slotID)
            if slot.Enabled ~= false and (settings.DisplayOnUseOnly ~= true or isOnUse)
                and (previewing or (PlayerMatchesFilters(entrySettings)
                    and BCDM:ShouldDisplayCustomTrackerEntry(entrySettings, state))) then
                equipped[#equipped + 1] = {
                    itemId = itemId,
                    slotID = slotID,
                    auraSpellIDs = auraSpellIDs,
                    entrySettings = entrySettings,
                    state = state,
                }
            end
        end
    end

    return equipped
end

local function RefreshIconCooldown(customIcon, state, entrySettings)
    if not customIcon or not customIcon.Cooldown or not customIcon.SlotID then return end
    state = state or GetTrinketCooldownState(customIcon.SlotID)
    entrySettings = entrySettings or customIcon.EntrySettings or DEFAULT_ENTRY_SETTINGS
    customIcon.EntrySettings = entrySettings
    if state.durationObject then
        customIcon.Cooldown:SetCooldownFromDurationObject(state.durationObject, true)
    elseif state.active == false then
        ClearCooldown(customIcon.Cooldown)
    end
    local visualMode = entrySettings.VisualMode or "FULL"
    customIcon:SetAlpha(visualMode == "LOW_ALPHA" and (tonumber(entrySettings.Alpha) or 0.45) or 1)
    SetIconDesaturation(customIcon.Icon, visualMode == "DESATURATE" and 1 or 0)
    if BCDM:ShouldGlowCustomTrackerEntry(entrySettings, state) then
        BCDM:StartCustomGlow(customIcon)
    else
        BCDM:StopCustomGlow(customIcon)
    end
end

local function AcquireCustomIcon(itemId, slotID, auraSpellIDs, entrySettings, state)
    local CooldownManagerDB = BCDM.db.profile
    local CustomDB = CooldownManagerDB.CooldownManager.Trinket
    if not itemId then return end
    local customIcon = slotIcons[slotID]
    if not customIcon then
        customIcon = CreateFrame("Button", "BCDM_Custom_Trinket_" .. slotID, BCDM.TrinketBarContainer, "BackdropTemplate")
        customIcon:EnableMouse(true)
        customIcon.Cooldown = CreateFrame("Cooldown", nil, customIcon, "CooldownFrameTemplate")
        customIcon.Cooldown:SetAllPoints(customIcon)
        customIcon.Cooldown:SetDrawEdge(false)
        customIcon.Cooldown:SetDrawBling(false)
        customIcon.Cooldown:SetDrawSwipe(true)
        customIcon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
        customIcon.Cooldown:SetHideCountdownNumbers(false)
        customIcon.Cooldown:SetReverse(false)
        customIcon.Icon = customIcon:CreateTexture(nil, "BACKGROUND")
        customIcon:SetScript("OnEnter", function(self)
            if not self.EntrySettings or self.EntrySettings.Tooltip == false or not self.SlotID then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetInventoryItem("player", self.SlotID)
            GameTooltip:Show()
        end)
        customIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        slotIcons[slotID] = customIcon
    end
    if customIcon.ItemID ~= itemId then
        ClearCooldown(customIcon.Cooldown)
        SetIconDesaturation(customIcon.Icon, 0)
        BCDM:StopCustomGlow(customIcon)
        BCDM:HideTrinketAuraCountDisplay(customIcon)
    end
    customIcon.ItemID = itemId
    customIcon.SlotID = slotID
    customIcon:EnableMouse(not entrySettings or entrySettings.Tooltip ~= false)
    customIcon:SetParent(BCDM.TrinketBarContainer)
    customIcon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = BCDM.db.profile.CooldownManager.General.BorderSize, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    customIcon:SetBackdropColor(0, 0, 0, 0)
    if BCDM.db.profile.CooldownManager.General.BorderSize <= 0 then
        customIcon:SetBackdropBorderColor(0, 0, 0, 0)
    else
        customIcon:SetBackdropBorderColor(0, 0, 0, 1)
    end
    local iconWidth, iconHeight = BCDM:GetIconDimensions(CustomDB)
    customIcon:SetSize(iconWidth, iconHeight)
    customIcon:SetFrameStrata(CustomDB.FrameStrata or "LOW")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    customIcon.Icon:ClearAllPoints()
    customIcon.Icon:SetPoint("TOPLEFT", customIcon, "TOPLEFT", borderSize, -borderSize)
    customIcon.Icon:SetPoint("BOTTOMRIGHT", customIcon, "BOTTOMRIGHT", -borderSize, borderSize)
    local iconZoom = BCDM.db.profile.CooldownManager.General.IconZoom * 0.5
    BCDM:ApplyIconTexCoord(customIcon.Icon, iconWidth, iconHeight, iconZoom)
    customIcon.Icon:SetTexture(GetInventoryItemTexture("player", slotID))
    RefreshIconCooldown(customIcon, state, entrySettings)
    BCDM:EnsureTrinketAuraCountDisplay(customIcon, auraSpellIDs, CustomDB, entrySettings)

    return customIcon
end

local function CreateCustomIcons(iconTable)
    wipe(iconTable)

    local settings = BCDM.db.profile.CooldownManager.Trinket
    local trinkets = FetchEquippedTrinkets(settings)
    for _, trinketEntry in ipairs(trinkets) do
        local customTrinket = AcquireCustomIcon(trinketEntry.itemId, trinketEntry.slotID,
            trinketEntry.auraSpellIDs, trinketEntry.entrySettings, trinketEntry.state)
        if customTrinket then
            table.insert(iconTable, customTrinket)
        end
    end
end

local function LayoutTrinketBar()
    local CooldownManagerDB = BCDM.db.profile
    local CustomDB = CooldownManagerDB.CooldownManager.Trinket
    local customTrinketIcons = {}

    local growthDirection = CustomDB.GrowthDirection or "RIGHT"

    local containerAnchorFrom = CustomDB.Layout[1]
    if growthDirection == "UP" then
        local verticalFlipMap = {
            ["TOPLEFT"] = "BOTTOMLEFT",
            ["TOP"] = "BOTTOM",
            ["TOPRIGHT"] = "BOTTOMRIGHT",
            ["BOTTOMLEFT"] = "TOPLEFT",
            ["BOTTOM"] = "TOP",
            ["BOTTOMRIGHT"] = "TOPRIGHT",
        }
        containerAnchorFrom = verticalFlipMap[CustomDB.Layout[1]] or CustomDB.Layout[1]
    end

    if not BCDM.TrinketBarContainer then
        BCDM.TrinketBarContainer = CreateFrame("Frame", "BCDM_TrinketBar", UIParent, "BackdropTemplate")
        BCDM.TrinketBarContainer:SetSize(1, 1)
        BCDM:RegisterOwnedFrameVisibility(BCDM.TrinketBarContainer, function()
            return BCDM.db.profile.CooldownManager.Trinket
        end, function() BCDM:UpdateTrinketBar() end)
    end

    BCDM.TrinketBarContainer:ClearAllPoints()
    BCDM.TrinketBarContainer:SetFrameStrata(CustomDB.FrameStrata or "LOW")
    local anchorParent = BCDM:ResolveAnchorParent(CustomDB.Layout[2])
    BCDM.TrinketBarContainer:SetPoint(containerAnchorFrom, anchorParent, CustomDB.Layout[3], CustomDB.Layout[4], CustomDB.Layout[5])

    for _, icon in pairs(slotIcons) do
        BCDM:StopCustomGlow(icon)
        icon:Hide()
        BCDM:HideTrinketAuraCountDisplay(icon)
    end

    CreateCustomIcons(customTrinketIcons)

    local iconWidth, iconHeight = BCDM:GetIconDimensions(CustomDB)
    local iconSpacing = CustomDB.Spacing

    if #customTrinketIcons == 0 then
        BCDM.TrinketBarContainer:SetSize(1, 1)
    else
        local point = select(1, BCDM.TrinketBarContainer:GetPoint(1))
        local useCenteredLayout = (point == "TOP" or point == "BOTTOM") and (growthDirection == "LEFT" or growthDirection == "RIGHT")

        local totalWidth, totalHeight = 0, 0
        if useCenteredLayout or growthDirection == "RIGHT" or growthDirection == "LEFT" then
            totalWidth = (#customTrinketIcons * iconWidth) + ((#customTrinketIcons - 1) * iconSpacing)
            totalHeight = iconHeight
        elseif growthDirection == "UP" or growthDirection == "DOWN" then
            totalWidth = iconWidth
            totalHeight = (#customTrinketIcons * iconHeight) + ((#customTrinketIcons - 1) * iconSpacing)
        end
        BCDM.TrinketBarContainer:SetWidth(totalWidth)
        BCDM.TrinketBarContainer:SetHeight(totalHeight)
    end

    local LayoutConfig = {
        TOPLEFT     = { anchor="TOPLEFT",     xMult=1,  yMult=1  },
        TOP         = { anchor="TOP",         xMult=0,  yMult=1  },
        TOPRIGHT    = { anchor="TOPRIGHT",    xMult=-1, yMult=1  },
        BOTTOMLEFT  = { anchor="BOTTOMLEFT",  xMult=1,  yMult=-1 },
        BOTTOM      = { anchor="BOTTOM",      xMult=0,  yMult=-1 },
        BOTTOMRIGHT = { anchor="BOTTOMRIGHT", xMult=-1, yMult=-1 },
        LEFT        = { anchor="LEFT",        xMult=1,  yMult=0  },
        RIGHT       = { anchor="RIGHT",       xMult=-1, yMult=0  },
        CENTER      = { anchor="CENTER",      xMult=0,  yMult=0  },
    }

    local point = select(1, BCDM.TrinketBarContainer:GetPoint(1))
    local useCenteredLayout = (point == "TOP" or point == "BOTTOM") and (growthDirection == "LEFT" or growthDirection == "RIGHT")

    if useCenteredLayout and #customTrinketIcons > 0 then
        local totalWidth = (#customTrinketIcons * iconWidth) + ((#customTrinketIcons - 1) * iconSpacing)
        local startOffset = -(totalWidth / 2) + (iconWidth / 2)

        for i, spellIcon in ipairs(customTrinketIcons) do
            spellIcon:SetParent(BCDM.TrinketBarContainer)
            spellIcon:SetSize(iconWidth, iconHeight)
            spellIcon:ClearAllPoints()

            local xOffset = startOffset + ((i - 1) * (iconWidth + iconSpacing))
            spellIcon:SetPoint("CENTER", BCDM.TrinketBarContainer, "CENTER", xOffset, 0)
            ApplyCooldownText()
            spellIcon:Show()
        end
    else
        for i, spellIcon in ipairs(customTrinketIcons) do
            spellIcon:SetParent(BCDM.TrinketBarContainer)
            spellIcon:SetSize(iconWidth, iconHeight)
            spellIcon:ClearAllPoints()

            if i == 1 then
                local config = LayoutConfig[point] or LayoutConfig.TOPLEFT
                spellIcon:SetPoint(config.anchor, BCDM.TrinketBarContainer, config.anchor, 0, 0)
            else
                if growthDirection == "RIGHT" then
                    spellIcon:SetPoint("LEFT", customTrinketIcons[i - 1], "RIGHT", iconSpacing, 0)
                elseif growthDirection == "LEFT" then
                    spellIcon:SetPoint("RIGHT", customTrinketIcons[i - 1], "LEFT", -iconSpacing, 0)
                elseif growthDirection == "UP" then
                    spellIcon:SetPoint("BOTTOM", customTrinketIcons[i - 1], "TOP", 0, iconSpacing)
                elseif growthDirection == "DOWN" then
                    spellIcon:SetPoint("TOP", customTrinketIcons[i - 1], "BOTTOM", 0, -iconSpacing)
                end
            end
            ApplyCooldownText()
            spellIcon:Show()
        end
    end

    if CustomDB.Enabled and #customTrinketIcons > 0 then
        if BCDM.TrinketSettingsPreview or BCDM:ShouldShowOwnedFrame(CustomDB) then BCDM.TrinketBarContainer:Show()
        else BCDM.TrinketBarContainer:Hide() end
    else
        BCDM.TrinketBarContainer:Hide()
    end
end

function BCDM:SetupTrinketBar()
    LayoutTrinketBar()
end

function BCDM:UpdateTrinketBar()
    LayoutTrinketBar()
end

function BCDM:RefreshTrinketCooldowns()
    BCDM:UpdateTrinketBar()
end

function BCDM:FetchEquippedTrinkets()
    if InCombatLockdown() then return end
    if not BCDM.db.profile.CooldownManager.Trinket.Enabled then
        if BCDM.TrinketBarContainer then BCDM.TrinketBarContainer:Hide() end
        return
    end
    BCDM:UpdateTrinketBar()
end

local trinketEquipmentEvents = CreateFrame("Frame")
trinketEquipmentEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
trinketEquipmentEvents:RegisterEvent("PLAYER_LOGIN")
trinketEquipmentEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
trinketEquipmentEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
trinketEquipmentEvents:RegisterEvent("ITEM_DATA_LOAD_RESULT")
trinketEquipmentEvents:RegisterEvent("BAG_UPDATE_COOLDOWN")
trinketEquipmentEvents:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
trinketEquipmentEvents:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
local refreshAfterCombat = false
local refreshQueued = false
local function RefreshEquippedTrinkets()
    if InCombatLockdown() then
        refreshAfterCombat = true
        return
    end
    refreshAfterCombat = false
    BCDM:FetchEquippedTrinkets()
end
local function QueueEquippedTrinketRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        RefreshEquippedTrinkets()
    end)
end
trinketEquipmentEvents:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "BAG_UPDATE_COOLDOWN" then
        BCDM:RefreshTrinketCooldowns()
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, RefreshEquippedTrinkets)
    elseif event == "PLAYER_EQUIPMENT_CHANGED" and (arg1 == 13 or arg1 == 14) then
        QueueEquippedTrinketRefresh()
    elseif event == "ITEM_DATA_LOAD_RESULT" and pendingItemData[arg1] then
        pendingItemData[arg1] = nil
        if arg2 == true then QueueEquippedTrinketRefresh() end
    elseif event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        QueueEquippedTrinketRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        BCDM:PreparePendingCustomTrackerAuraDisplays()
        if refreshAfterCombat then RefreshEquippedTrinkets() end
    end
end)
