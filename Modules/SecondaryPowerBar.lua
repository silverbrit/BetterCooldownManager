local _, BCDM = ...

local runeBars = {}
local comboPoints = {}
local essenceTicks = {}
local resizeTimer = nil

local function NudgeSecondaryPowerBar(secondaryPowerBar, xOffset, yOffset)
    local powerBarFrame = _G[secondaryPowerBar]
    if not powerBarFrame then return end

    local point, relativeTo, relativePoint, xOfs, yOfs = powerBarFrame:GetPoint(1)
    powerBarFrame:ClearAllPoints()
    powerBarFrame:SetPoint(point, relativeTo, relativePoint, xOfs + xOffset, yOfs + yOffset)
end

local function GetPowerBarColor(descriptor, overrideColour)
    local cooldownManagerDB = BCDM.db.profile
    local generalDB = cooldownManagerDB.General
    local secondaryPowerBarDB = cooldownManagerDB.SecondaryPowerBar

    if not secondaryPowerBarDB then
        return 1, 1, 1, 1
    end

    descriptor = descriptor or BCDM:GetCurrentSecondaryResource()
    local powerColour = descriptor and generalDB.Colours.SecondaryPower[descriptor.key]
    if not powerColour and descriptor and descriptor.powerType == Enum.PowerType.Mana then
        powerColour = generalDB.Colours.PrimaryPower[Enum.PowerType.Mana]
    end

    local specializationColour
    if descriptor and descriptor.runeColourKey then
        local runeColours = generalDB.Colours.SecondaryPower["RUNES"]
        specializationColour = runeColours and runeColours[descriptor.runeColourKey]
    end

    local _, class = UnitClass("player")
    return BCDM:ResolveBarFillColour("SecondaryPowerBar", secondaryPowerBarDB, {
        ClassColour = RAID_CLASS_COLORS[class],
        OverrideColour = overrideColour,
        PowerTypeColour = powerColour,
        SpecializationColour = specializationColour,
    })
end

local function CreateRuneBars()
    local parent = BCDM.SecondaryPowerBar
    if not parent then return end

    for i = 1, #runeBars do
        if runeBars[i] then
            runeBars[i]:SetScript("OnUpdate", nil)
            runeBars[i]:Hide()
            runeBars[i]:SetParent(nil)
            runeBars[i] = nil
        end
    end
    wipe(runeBars)

    for i = 1, 6 do
        local runeBar = CreateFrame("StatusBar", nil, parent)
        runeBar:SetStatusBarTexture(BCDM.Media.Foreground)
        runeBar:SetMinMaxValues(0, 1)
        runeBar:SetValue(0)
        runeBars[i] = runeBar
    end
end

local function CreateComboPoints(maxPower)
    local parent = BCDM.SecondaryPowerBar
    if not parent then return end

    for i = 1, #comboPoints do
        comboPoints[i]:Hide()
        comboPoints[i]:SetParent(nil)
        comboPoints[i] = nil
    end
    wipe(comboPoints)

    for i = 1, maxPower do
        local bar = CreateFrame("StatusBar", nil, parent)
        bar:SetStatusBarTexture(BCDM.Media.Foreground)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        comboPoints[i] = bar
    end
end

local function CreateEssenceTicks(maxEssence)
    local parent = BCDM.SecondaryPowerBar
    if not parent then return end

    for i = 1, #essenceTicks do
        essenceTicks[i].bar:SetScript("OnUpdate", nil)
        essenceTicks[i].bar:Hide()
        essenceTicks[i].bar:SetParent(nil)
        essenceTicks[i] = nil
    end
    wipe(essenceTicks)

    for i = 1, maxEssence do
        local bar = CreateFrame("StatusBar", nil, parent)
        bar:SetStatusBarTexture(BCDM.Media.Foreground)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)

        essenceTicks[i] = {
            bar = bar,
        }
    end
end

local function LayoutRuneBars()
    local secondaryBar = BCDM.SecondaryPowerBar
    if not secondaryBar or #runeBars == 0 then return end

    local powerBarWidth = secondaryBar:GetWidth() - 2
    local powerBarHeight = secondaryBar:GetHeight() - 2
    local runeSpacing = 1
    local runeWidth = (powerBarWidth - (runeSpacing * 5)) / 6

    for i = 1, 6 do
        local runeBar = runeBars[i]
        if not runeBar then return end

        runeBar:ClearAllPoints()
        runeBar:SetSize(runeWidth, powerBarHeight)

        if i == 1 then
            runeBar:SetPoint("LEFT", secondaryBar, "LEFT", 1, 0)
        else
            runeBar:SetPoint("LEFT", runeBars[i-1], "RIGHT", runeSpacing, 0)
        end
    end
end

local function LayoutComboPoints()
    local parent = BCDM.SecondaryPowerBar
    if not parent or #comboPoints == 0 then return end

    local inset = 1
    local width = parent:GetWidth() - inset * 2
    local height = parent:GetHeight() - inset * 2
    local count = #comboPoints
    local barWidth = math.floor(width / count)

    for i = 1, count do
        local bar = comboPoints[i]
        bar:ClearAllPoints()
        bar:SetHeight(height)

        if i == count then
            bar:SetPoint("TOPLEFT", comboPoints[i-1], "TOPRIGHT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
        elseif i == 1 then
            bar:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
            bar:SetWidth(barWidth)
        else
            bar:SetPoint("TOPLEFT", comboPoints[i-1], "TOPRIGHT", 0, 0)
            bar:SetWidth(barWidth)
        end
    end
end

local function LayoutEssenceTicks()
    local parent = BCDM.SecondaryPowerBar
    if not parent or #essenceTicks == 0 then return end

    local powerBarWidth = parent:GetWidth() - 2
    local powerBarHeight = parent:GetHeight() - 2
    local spacing = 1
    local count = #essenceTicks
    local barWidth = (powerBarWidth - (spacing * (count - 1))) / count

    for i = 1, count do
        local tick = essenceTicks[i]
        local bar = tick.bar

        bar:ClearAllPoints()
        bar:SetSize(barWidth, powerBarHeight)

        if i == 1 then
            bar:SetPoint("LEFT", parent, "LEFT", 1, 0)
        else
            bar:SetPoint("LEFT", essenceTicks[i - 1].bar, "RIGHT", spacing, 0)
        end
    end
end

local function StartRuneOnUpdate(runeBar, runeIndex, descriptor)
    local generalDB = BCDM.db.profile.General

    runeBar:SetScript("OnUpdate", function(self)
        local runeStartTime, runeDuration, runeReady = GetRuneCooldown(runeIndex)

        if runeReady then
            self:SetScript("OnUpdate", nil)
            self:SetValue(1)
            local r, g, b, a = GetPowerBarColor(descriptor)
            self:SetStatusBarColor(r, g, b, a)
            return
        end

        if runeDuration and runeDuration > 0 then
            local now = GetTime()
            local elapsed = now - runeStartTime
            local progress = math.min(1, elapsed / runeDuration)
            self:SetValue(progress)

            local rechargeColour = generalDB.Colours.SecondaryPower["RUNE_RECHARGE"]
            self:SetStatusBarColor(GetPowerBarColor(descriptor, rechargeColour))
        end
    end)
end

local function UpdateRuneDisplay(descriptor)
    local parent = BCDM.SecondaryPowerBar
    if not parent or #runeBars == 0 then return end

    local maxPower = 6
    local r, g, b, a = GetPowerBarColor(descriptor)

    local runeReadyList = {}
    local runeOnCDList = {}

    for i = 1, maxPower do
        local runeStartTime, runeDuration, runeReady = GetRuneCooldown(i)

        if runeReady then
            table.insert(runeReadyList, { index = i })
        else
            if runeStartTime and runeDuration and runeDuration > 0 then
                local elapsed = GetTime() - runeStartTime
                local remain = math.max(0, runeDuration - elapsed)
                table.insert(runeOnCDList, { index = i, remaining = remain })
            else
                table.insert(runeOnCDList, { index = i, remaining = 999 })
            end
        end
    end

    table.sort(runeOnCDList, function(a, b) return a.remaining < b.remaining end)

    local order = {}
    for _, v in ipairs(runeReadyList) do table.insert(order, v.index) end
    for _, v in ipairs(runeOnCDList) do table.insert(order, v.index) end

    for runePosition = 1, maxPower do
        local i = order[runePosition]
        local runeBar = runeBars[i]

        runeBar:ClearAllPoints()
        if runePosition == 1 then
            runeBar:SetPoint("LEFT", parent, "LEFT", 1, 0)
        else
            runeBar:SetPoint("LEFT", runeBars[order[runePosition-1]], "RIGHT", 1, 0)
        end

        runeBar:Show()

        local _, _, runeReady = GetRuneCooldown(i)
        if runeReady then
            runeBar:SetValue(1)
            runeBar:SetStatusBarColor(r, g, b, a)
            runeBar:SetScript("OnUpdate", nil)
        else
            StartRuneOnUpdate(runeBar, i, descriptor)
        end
    end
end

local function UpdateComboDisplay(descriptor)
    local powerCurrent = UnitPower("player", Enum.PowerType.ComboPoints) or 0
    local powerMax = UnitPowerMax("player", Enum.PowerType.ComboPoints) or 0
    local charged = GetUnitChargedPowerPoints("player")
    local chargedLookup = {}

    if charged then
        for _, index in ipairs(charged) do
            chargedLookup[index] = true
        end
    end

    if #comboPoints ~= powerMax then
        CreateComboPoints(powerMax)
        LayoutComboPoints()
    end

    local powerBarColourR, powerBarColourG, powerBarColourB, powerBarColourA = GetPowerBarColor(descriptor)
    local chargedComboPointColour = BCDM.db.profile.General.Colours.SecondaryPower["CHARGED_COMBO_POINTS"]

    for i = 1, powerMax do
        local bar = comboPoints[i]

        if i <= powerCurrent then
            bar:SetValue(1)
            if chargedLookup[i] then
                bar:SetStatusBarColor(GetPowerBarColor(descriptor, chargedComboPointColour))
            else
                bar:SetStatusBarColor(powerBarColourR, powerBarColourG, powerBarColourB, powerBarColourA or 1)
            end
            bar:Show()
        else
            bar:SetValue(0)
            bar:Hide()
        end
    end
end

local function GetEssencePartialProgress()
    local displayMod = UnitPowerDisplayMod(Enum.PowerType.Essence) or 0
    if displayMod <= 0 then
        return 0
    end

    local partialPower = UnitPartialPower("player", Enum.PowerType.Essence) or 0
    return math.max(0, math.min(1, partialPower / displayMod))
end

local function UpdateEssenceDisplay(descriptor)
    local parent = BCDM.SecondaryPowerBar
    if not parent or #essenceTicks == 0 then return end

    local powerCurrent = UnitPower("player", Enum.PowerType.Essence) or 0
    local partialProgress = GetEssencePartialProgress()
    local r, g, b, a = GetPowerBarColor(descriptor)
    local rechargeColour = BCDM.db.profile.General.Colours.SecondaryPower["ESSENCE_RECHARGE"]

    for i = 1, #essenceTicks do
        local tick = essenceTicks[i]
        local bar = tick.bar

        bar:Show()
        bar:SetScript("OnUpdate", nil)

        if i <= powerCurrent then
            bar:SetValue(1)
            bar:SetStatusBarColor(r, g, b, a)
        elseif i == powerCurrent + 1 and powerCurrent < #essenceTicks then
            bar:SetValue(partialProgress)
            bar:SetStatusBarColor(GetPowerBarColor(descriptor, rechargeColour))
        else
            bar:SetValue(0)
            bar:SetStatusBarColor(0, 0, 0, 1)
        end
    end
end

local function ReadResourceNumber(value)
    if BCDM:IsSecretValue(value) or type(value) ~= "number" then return nil end
    return value
end

local function GetPlayerAuraBySpellID(spellId)
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil, false end
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
    if not ok or BCDM:IsSecretValue(auraData) then return nil, false end
    return auraData, true
end

local function GetAuraStacks(spellId)
    local auraData, readable = GetPlayerAuraBySpellID(spellId)
    if not readable then return nil, false end
    if auraData == nil then return 0, true end
    if type(auraData) ~= "table" then return nil, false end
    local ok, applications = pcall(function() return auraData.applications end)
    if not ok or BCDM:IsSecretValue(applications) then return nil, false end
    if applications == nil then return 0, true end
    applications = ReadResourceNumber(applications)
    return applications, applications ~= nil
end

local function IsInMetamorphosis(spellId)
    local auraData, readable = GetPlayerAuraBySpellID(spellId)
    if not readable then return nil, false end
    return auraData ~= nil, true
end

local function GetSpellCharges(spellId)
    if not C_Spell or not C_Spell.GetSpellCastCount then return nil, false end
    local ok, charges = pcall(C_Spell.GetSpellCastCount, spellId)
    if not ok then return nil, false end
    charges = ReadResourceNumber(charges)
    return charges, charges ~= nil
end

BCDM._SecondaryResourceReaders = {
    GetAuraStacks = GetAuraStacks,
    IsInMetamorphosis = IsInMetamorphosis,
    GetSpellCharges = GetSpellCharges,
}

local RESOURCE_HANDLERS = {}

local function SetStandardValue(descriptor, bar)
    local current = UnitPower("player", descriptor.powerType) or 0
    local maximum = UnitPowerMax("player", descriptor.powerType) or 0
    bar.Status:SetMinMaxValues(0, maximum)
    bar.Status:SetValue(current)
    bar.Status:Show()
    return current, maximum, tostring(current)
end

RESOURCE_HANDLERS.STANDARD = SetStandardValue
RESOURCE_HANDLERS.AURA_STACKS = function(descriptor, bar)
    local current, readable = GetAuraStacks(descriptor.sourceSpellID)
    if not readable then return nil end
    bar.Status:SetMinMaxValues(0, descriptor.maximum)
    bar.Status:SetValue(current)
    bar.Status:Show()
    return current, descriptor.maximum, tostring(current)
end
RESOURCE_HANDLERS.SPELL_CHARGES = function(descriptor, bar)
    local current, readable = GetSpellCharges(descriptor.sourceSpellID)
    if not readable then return nil end
    bar.Status:SetMinMaxValues(0, descriptor.maximum)
    bar.Status:SetValue(current)
    bar.Status:Show()
    return current, descriptor.maximum, tostring(current)
end
RESOURCE_HANDLERS.DEVOURER_SOUL = function(descriptor, bar)
    local hasSoulGlutton = C_SpellBook.IsSpellKnown(descriptor.soulGluttonSpellID)
    local inMetamorphosis, auraReadable = IsInMetamorphosis(descriptor.metamorphosisAuraID)
    local current, chargesReadable = GetSpellCharges(descriptor.sourceSpellID)
    if not auraReadable or not chargesReadable then return nil end
    local maximum = inMetamorphosis and 40 or (hasSoulGlutton and 35 or 50)
    bar.Status:SetMinMaxValues(0, maximum)
    bar.Status:SetValue(current)
    bar.Status:Show()
    return current, maximum, tostring(current)
end
RESOURCE_HANDLERS.SOUL_SHARDS = function(descriptor, bar)
    local current, maximum, text
    if descriptor.fractional then
        current, maximum = UnitPower("player", descriptor.powerType, true) or 0, 50
        text = string.format("%.1f", current / 10)
    else
        current = UnitPower("player", descriptor.powerType, false) or 0
        maximum = UnitPowerMax("player", descriptor.powerType) or 0
        text = tostring(current)
    end
    bar.Status:SetMinMaxValues(0, maximum)
    bar.Status:SetValue(current)
    bar.Status:Show()
    return current, maximum, text
end
RESOURCE_HANDLERS.COMBO_POINTS = function(descriptor, bar)
    local current = UnitPower("player", descriptor.powerType) or 0
    local maximum = UnitPowerMax("player", descriptor.powerType) or 0
    bar.Status:SetMinMaxValues(0, maximum)
    bar.Status:SetValue(0)
    UpdateComboDisplay(descriptor)
    bar.Status:Show()
    return current, maximum, tostring(current)
end
RESOURCE_HANDLERS.ESSENCE = function(descriptor, bar)
    local current = UnitPower("player", descriptor.powerType) or 0
    local maximum = UnitPowerMax("player", descriptor.powerType) or 0
    UpdateEssenceDisplay(descriptor)
    bar.Status:SetMinMaxValues(0, maximum)
    bar.Status:SetValue(current)
    bar.Status:Show()
    return current, maximum, tostring(current)
end
RESOURCE_HANDLERS.RUNES = function(descriptor, bar)
    bar.Status:Hide()
    UpdateRuneDisplay(descriptor)
    return 0, descriptor.tickCount or 6, ""
end
RESOURCE_HANDLERS.STAGGER = function(descriptor, bar, settings)
    BCDM:ClearTicks()
    local current = UnitStagger("player") or 0
    local maximum = UnitHealthMax("player") or 0
    local percentage = maximum > 0 and (current / maximum) * 100 or 0
    bar.Status:SetMinMaxValues(0, maximum)
    bar.Status:SetValue(current)
    if settings.ColourByState then
        local colours = BCDM.db.profile.General.Colours.SecondaryPower.STAGGER_COLOURS
        local stateColour = percentage < 30 and colours.LIGHT or percentage < 60 and colours.MODERATE or colours.HEAVY
        bar.Status:SetStatusBarColor(GetPowerBarColor(descriptor, stateColour))
    else
        bar.Status:SetStatusBarColor(GetPowerBarColor(descriptor))
    end
    bar.Status:Show()
    local text = AbbreviateLargeNumbers(current)
    if settings.Text.ShowStaggerDPS and current > 0 then
        text = text .. " (" .. AbbreviateLargeNumbers(current / 20) .. " / 0.5s)"
    end
    return current, maximum, text, true
end

local function HideInactiveResourceDisplays(kind)
    if kind ~= "RUNES" then
        for _, runeBar in ipairs(runeBars) do
            runeBar:SetScript("OnUpdate", nil)
            runeBar:Hide()
        end
    end
    if kind ~= "COMBO_POINTS" then
        for _, comboPoint in ipairs(comboPoints) do comboPoint:Hide() end
    end
    if kind ~= "ESSENCE" then
        for _, essenceTick in ipairs(essenceTicks) do
            essenceTick.bar:SetScript("OnUpdate", nil)
            essenceTick.bar:Hide()
        end
    end
end

local function UpdatePowerValues()
    local descriptor = BCDM:GetCurrentSecondaryResource()
    local bar = BCDM.SecondaryPowerBar
    local settings = BCDM.db.profile.SecondaryPowerBar
    if not descriptor then if bar then bar:Hide() end return end
    if not bar then return end
    local handler = RESOURCE_HANDLERS[descriptor.kind]
    if not handler then bar:Hide() return end
    HideInactiveResourceDisplays(descriptor.kind)
    local current, maximum, text, colourApplied = handler(descriptor, bar, settings)
    if current == nil then
        bar.Status:Hide()
        bar.Text:SetText("")
        bar:Hide()
        return
    end
    if not colourApplied then bar.Status:SetStatusBarColor(GetPowerBarColor(descriptor)) end
    if settings.Text.Mode and settings.Text.Mode ~= "AUTO" then
        text = BCDM:FormatResourceText(current, maximum, settings.Text.Mode)
    end
    bar.Text:SetText(text or "")
    bar:Show()
end

local function CreateTicksBasedOnPowerType()
    local settings = BCDM.db.profile.SecondaryPowerBar
    local descriptor = BCDM:GetCurrentSecondaryResource()
    BCDM:ClearTicks()
    if settings.HideTicks or not descriptor then return end
    if descriptor.kind == "RUNES" then
        CreateRuneBars()
        LayoutRuneBars()
        UpdateRuneDisplay(descriptor)
    elseif descriptor.kind == "ESSENCE" then
        local maximum = UnitPowerMax("player", descriptor.powerType) or 0
        CreateEssenceTicks(maximum)
        LayoutEssenceTicks()
        UpdateEssenceDisplay(descriptor)
        BCDM:CreateTicks(maximum)
    elseif descriptor.kind == "DEVOURER_SOUL" then
        BCDM:CreateTicks(C_SpellBook.IsSpellKnown(descriptor.soulGluttonSpellID) and 7 or 10)
    elseif descriptor.tickCount then
        BCDM:CreateTicks(descriptor.tickCount)
    elseif descriptor.kind ~= "STAGGER" and descriptor.powerType ~= Enum.PowerType.Mana then
        local maximum = UnitPowerMax("player", descriptor.powerType) or 0
        if maximum > 0 then BCDM:CreateTicks(maximum) end
    end
end

local function UpdateBarWidth()
    local secondaryPowerBarDB = BCDM.db.profile.SecondaryPowerBar
    local secondaryPowerBar = BCDM.SecondaryPowerBar

    if not secondaryPowerBar or not secondaryPowerBarDB.MatchWidthOfAnchor then return end

    local anchorFrame = BCDM:ResolveAnchorParent(secondaryPowerBarDB.Layout[2])
    if not anchorFrame then return end

    if resizeTimer then
        resizeTimer:Cancel()
    end

    resizeTimer = C_Timer.After(0.5, function()
        local anchorWidth = anchorFrame:GetWidth()
        secondaryPowerBar:SetWidth(anchorWidth)
        local descriptor = BCDM:GetCurrentSecondaryResource()

        if descriptor and descriptor.kind == "RUNES" and #runeBars > 0 then
            LayoutRuneBars()
        elseif descriptor and descriptor.kind == "COMBO_POINTS" and #comboPoints > 0 then
            LayoutComboPoints()
        elseif descriptor and descriptor.kind == "ESSENCE" and #essenceTicks > 0 then
            LayoutEssenceTicks()
            UpdateEssenceDisplay(descriptor)
        end

        resizeTimer = nil
    end)
end

local function SetHooks()
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() if InCombatLockdown() then return end UpdateBarWidth() end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() if InCombatLockdown() then return end UpdateBarWidth() end)
end

local function OnSecondaryPowerBarSizeChanged()
    CreateTicksBasedOnPowerType()
    local descriptor = BCDM:GetCurrentSecondaryResource()
    if descriptor and descriptor.kind == "COMBO_POINTS" and #comboPoints > 0 then
        LayoutComboPoints()
    elseif descriptor and descriptor.kind == "ESSENCE" and #essenceTicks > 0 then
        LayoutEssenceTicks()
        UpdateEssenceDisplay(descriptor)
    end
end

local function OnSecondaryPowerBarEvent(self, event, ...)
    if event == "RUNE_POWER_UPDATE" or event == "RUNE_TYPE_UPDATE" then
        local descriptor = BCDM:GetCurrentSecondaryResource()
        if descriptor and descriptor.kind == "RUNES" then
            UpdateRuneDisplay(descriptor)
        end
        return
    end

    if event == "UNIT_AURA" then
        UpdatePowerValues()
        return
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit and unit ~= "player" then return end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_HEALTH"
        or event == "UNIT_MAXHEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        local unit = ...
        if unit and unit ~= "player" then return end
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM" then
        BCDM:UpdateSecondaryPowerBar()
        return
    elseif event == "UNIT_MAXPOWER" then
        CreateTicksBasedOnPowerType()
    end

    UpdatePowerValues()
end

BCDM._SecondaryPowerBarOnEvent = OnSecondaryPowerBarEvent

local function RegisterSecondaryPowerBarEvents(secondaryPowerBar)
    secondaryPowerBar:RegisterEvent("UNIT_POWER_UPDATE")
    secondaryPowerBar:RegisterEvent("UNIT_MAXPOWER")
    secondaryPowerBar:RegisterEvent("UNIT_HEALTH")
    secondaryPowerBar:RegisterEvent("UNIT_MAXHEALTH")
    secondaryPowerBar:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    secondaryPowerBar:RegisterEvent("PLAYER_ENTERING_WORLD")
    secondaryPowerBar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    secondaryPowerBar:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    secondaryPowerBar:RegisterEvent("RUNE_POWER_UPDATE")
    secondaryPowerBar:RegisterEvent("RUNE_TYPE_UPDATE")
    secondaryPowerBar:RegisterUnitEvent("UNIT_AURA", "player")
    secondaryPowerBar:SetScript("OnEvent", OnSecondaryPowerBarEvent)
    secondaryPowerBar.Status:SetScript("OnSizeChanged", OnSecondaryPowerBarSizeChanged)
end

local function UnregisterSecondaryPowerBarEvents(secondaryPowerBar)
    secondaryPowerBar:SetScript("OnEvent", nil)
    secondaryPowerBar.Status:SetScript("OnSizeChanged", nil)
    secondaryPowerBar:UnregisterAllEvents()
end

function BCDM:CreateSecondaryPowerBar()
    local generalDB = BCDM.db.profile.General
    local powerBarDB = BCDM.db.profile.PowerBar
    local secondaryPowerBarDB = BCDM.db.profile.SecondaryPowerBar

    SetHooks()

    local secondaryPowerBar = _G.BCDM_SecondaryPowerBar
        or CreateFrame("Frame", "BCDM_SecondaryPowerBar", UIParent, "BackdropTemplate")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize

    secondaryPowerBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        secondaryPowerBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        secondaryPowerBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    secondaryPowerBar:SetBackdropColor(secondaryPowerBarDB.BackgroundColour[1], secondaryPowerBarDB.BackgroundColour[2], secondaryPowerBarDB.BackgroundColour[3], secondaryPowerBarDB.BackgroundColour[4])
    secondaryPowerBar:SetSize(secondaryPowerBarDB.Width, secondaryPowerBarDB.Height)

    if BCDM:CanSwapSecondaryResourceToPrimary() and secondaryPowerBarDB.SwapToPowerBarPosition then
        if BCDM.PowerBar then BCDM.PowerBar:Hide() end
        secondaryPowerBar:ClearAllPoints()
        secondaryPowerBar:SetPoint(powerBarDB.Layout[1], BCDM:ResolveAnchorParent(powerBarDB.Layout[2]), powerBarDB.Layout[3], powerBarDB.Layout[4], powerBarDB.Layout[5])
        secondaryPowerBar:SetHeight(secondaryPowerBarDB.HeightWithoutPrimary)
    else
        secondaryPowerBar:ClearAllPoints()
        secondaryPowerBar:SetPoint(secondaryPowerBarDB.Layout[1], BCDM:ResolveAnchorParent(secondaryPowerBarDB.Layout[2]), secondaryPowerBarDB.Layout[3], secondaryPowerBarDB.Layout[4], secondaryPowerBarDB.Layout[5])
        secondaryPowerBar:SetHeight(secondaryPowerBarDB.Height)
        if powerBarDB.Enabled then BCDM.PowerBar:Show() end
    end

    secondaryPowerBar:SetFrameStrata(secondaryPowerBarDB.FrameStrata)
    secondaryPowerBar.Status = CreateFrame("StatusBar", nil, secondaryPowerBar)
    secondaryPowerBar.Status:SetPoint("TOPLEFT", secondaryPowerBar, "TOPLEFT", borderSize, -borderSize)
    secondaryPowerBar.Status:SetPoint("BOTTOMRIGHT", secondaryPowerBar, "BOTTOMRIGHT", -borderSize, borderSize)
    secondaryPowerBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    BCDM:ApplyStatusBarDirection(secondaryPowerBar.Status, secondaryPowerBarDB.FillDirection)
    secondaryPowerBar.Spark = secondaryPowerBar.Status:CreateTexture(nil, "OVERLAY")
    secondaryPowerBar.Spark:SetColorTexture(1, 1, 1, 0.9)
    secondaryPowerBar.Spark:SetSize(2, secondaryPowerBarDB.Height)
    BCDM:AnchorStatusBarSpark(secondaryPowerBar.Spark, secondaryPowerBar.Status, secondaryPowerBarDB.FillDirection)
    secondaryPowerBar.Spark:SetShown(secondaryPowerBarDB.ShowSpark == true)

    secondaryPowerBar.TickFrame = CreateFrame("Frame", nil, secondaryPowerBar)
    secondaryPowerBar.TickFrame:SetAllPoints(secondaryPowerBar)
    secondaryPowerBar.TickFrame:SetFrameLevel(secondaryPowerBar.Status:GetFrameLevel() + 10)
    secondaryPowerBar.Ticks = {}

    secondaryPowerBar.Status:SetScript("OnSizeChanged", OnSecondaryPowerBarSizeChanged)

    secondaryPowerBar.Text = secondaryPowerBar.Status:CreateFontString(nil, "OVERLAY")
    secondaryPowerBar.Text:SetFont(BCDM.Media.Font, secondaryPowerBarDB.Text.FontSize, generalDB.Fonts.FontFlag)
    secondaryPowerBar.Text:SetTextColor(secondaryPowerBarDB.Text.Colour[1], secondaryPowerBarDB.Text.Colour[2], secondaryPowerBarDB.Text.Colour[3], 1)
    secondaryPowerBar.Text:SetPoint(secondaryPowerBarDB.Text.Layout[1], secondaryPowerBar, secondaryPowerBarDB.Text.Layout[2], secondaryPowerBarDB.Text.Layout[3], secondaryPowerBarDB.Text.Layout[4])

    if generalDB.Fonts.Shadow.Enabled then
        secondaryPowerBar.Text:SetShadowColor(generalDB.Fonts.Shadow.Colour[1], generalDB.Fonts.Shadow.Colour[2], generalDB.Fonts.Shadow.Colour[3], generalDB.Fonts.Shadow.Colour[4])
        secondaryPowerBar.Text:SetShadowOffset(generalDB.Fonts.Shadow.OffsetX, generalDB.Fonts.Shadow.OffsetY)
    else
        secondaryPowerBar.Text:SetShadowColor(0, 0, 0, 0)
        secondaryPowerBar.Text:SetShadowOffset(0, 0)
    end

    secondaryPowerBar.Text:SetText("")
    if secondaryPowerBarDB.Text.Enabled then
        secondaryPowerBar.Text:Show()
    else
        secondaryPowerBar.Text:Hide()
    end

    BCDM.SecondaryPowerBar = secondaryPowerBar
    BCDM:RegisterOwnedFrameVisibility(secondaryPowerBar, function() return BCDM.db.profile.SecondaryPowerBar end,
        function() BCDM:UpdateSecondaryPowerBar() end)

    if secondaryPowerBarDB.Enabled then
        RegisterSecondaryPowerBarEvents(secondaryPowerBar)
        UpdatePowerValues()
        CreateTicksBasedOnPowerType()
        NudgeSecondaryPowerBar("BCDM_SecondaryPowerBar", -0.1, 0)
        if BCDM:GetCurrentSecondaryResource() then
            secondaryPowerBar:Show()
        else
            secondaryPowerBar:Hide()
        end
    else
        secondaryPowerBar:Hide()
        UnregisterSecondaryPowerBarEvents(secondaryPowerBar)
    end

    UpdateBarWidth()
end

function BCDM:UpdateSecondaryPowerBar()
    local cooldownManagerDB = BCDM.db.profile
    local generalDB = cooldownManagerDB.General
    local powerBarDB = cooldownManagerDB.PowerBar
    local secondaryPowerBarDB = BCDM.db.profile.SecondaryPowerBar
    local descriptor = BCDM:GetCurrentSecondaryResource()
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize

    if not descriptor then
        if BCDM.SecondaryPowerBar then BCDM.SecondaryPowerBar:Hide() end
        if powerBarDB.Enabled and BCDM.PowerBar and BCDM:ShouldShowOwnedFrame(powerBarDB) then BCDM.PowerBar:Show() end
        return
    end

    local secondaryPowerBar = BCDM.SecondaryPowerBar
    if not secondaryPowerBar then return end
    secondaryPowerBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        secondaryPowerBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        secondaryPowerBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    secondaryPowerBar:SetBackdropColor(secondaryPowerBarDB.BackgroundColour[1], secondaryPowerBarDB.BackgroundColour[2], secondaryPowerBarDB.BackgroundColour[3], secondaryPowerBarDB.BackgroundColour[4])
    secondaryPowerBar:SetSize(secondaryPowerBarDB.Width, secondaryPowerBarDB.Height)

    if descriptor.swapToPrimaryEligible and secondaryPowerBarDB.SwapToPowerBarPosition then
        if BCDM.PowerBar then BCDM.PowerBar:Hide() end
        secondaryPowerBar:ClearAllPoints()
        secondaryPowerBar:SetPoint(powerBarDB.Layout[1], BCDM:ResolveAnchorParent(powerBarDB.Layout[2]), powerBarDB.Layout[3], powerBarDB.Layout[4], powerBarDB.Layout[5])
        secondaryPowerBar:SetHeight(secondaryPowerBarDB.HeightWithoutPrimary)
    else
        secondaryPowerBar:ClearAllPoints()
        secondaryPowerBar:SetPoint(secondaryPowerBarDB.Layout[1], BCDM:ResolveAnchorParent(secondaryPowerBarDB.Layout[2]), secondaryPowerBarDB.Layout[3], secondaryPowerBarDB.Layout[4], secondaryPowerBarDB.Layout[5])
        secondaryPowerBar:SetHeight(secondaryPowerBarDB.Height)
        if powerBarDB.Enabled then BCDM.PowerBar:Show() end
    end
    secondaryPowerBar:SetFrameStrata(secondaryPowerBarDB.FrameStrata)
    secondaryPowerBar.Status:SetPoint("TOPLEFT", secondaryPowerBar, "TOPLEFT", borderSize, -borderSize)
    secondaryPowerBar.Status:SetPoint("BOTTOMRIGHT", secondaryPowerBar, "BOTTOMRIGHT", -borderSize, borderSize)
    secondaryPowerBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    BCDM:ApplyStatusBarDirection(secondaryPowerBar.Status, secondaryPowerBarDB.FillDirection)
    BCDM:AnchorStatusBarSpark(secondaryPowerBar.Spark, secondaryPowerBar.Status, secondaryPowerBarDB.FillDirection)
    secondaryPowerBar.Spark:SetHeight(secondaryPowerBar:GetHeight())
    secondaryPowerBar.Spark:SetShown(secondaryPowerBarDB.ShowSpark == true)
    secondaryPowerBar.Status:SetStatusBarColor(GetPowerBarColor(descriptor))
    secondaryPowerBar.Status:SetMinMaxValues(0, UnitPowerMax("player"))
    secondaryPowerBar.Status:SetValue(UnitPower("player"))
    secondaryPowerBar.Text:SetFont(BCDM.Media.Font, secondaryPowerBarDB.Text.FontSize, generalDB.Fonts.FontFlag)
    secondaryPowerBar.Text:SetTextColor(secondaryPowerBarDB.Text.Colour[1], secondaryPowerBarDB.Text.Colour[2], secondaryPowerBarDB.Text.Colour[3], 1)
    secondaryPowerBar.Text:ClearAllPoints()
    secondaryPowerBar.Text:SetPoint(secondaryPowerBarDB.Text.Layout[1], secondaryPowerBar, secondaryPowerBarDB.Text.Layout[2], secondaryPowerBarDB.Text.Layout[3], secondaryPowerBarDB.Text.Layout[4])
    if generalDB.Fonts.Shadow.Enabled then
        secondaryPowerBar.Text:SetShadowColor(generalDB.Fonts.Shadow.Colour[1], generalDB.Fonts.Shadow.Colour[2], generalDB.Fonts.Shadow.Colour[3], generalDB.Fonts.Shadow.Colour[4])
        secondaryPowerBar.Text:SetShadowOffset(generalDB.Fonts.Shadow.OffsetX, generalDB.Fonts.Shadow.OffsetY)
    else
        secondaryPowerBar.Text:SetShadowColor(0, 0, 0, 0)
        secondaryPowerBar.Text:SetShadowOffset(0, 0)
    end
    secondaryPowerBar.Text:SetText("")
    if secondaryPowerBarDB.Text.Enabled then secondaryPowerBar.Text:Show() else secondaryPowerBar.Text:Hide() end
    if secondaryPowerBarDB.Enabled then
        RegisterSecondaryPowerBarEvents(secondaryPowerBar)
        UpdatePowerValues()
        CreateTicksBasedOnPowerType()
        NudgeSecondaryPowerBar("BCDM_SecondaryPowerBar", -0.1, 0)
        secondaryPowerBar:Show()
    else
        secondaryPowerBar:Hide()
        UnregisterSecondaryPowerBarEvents(secondaryPowerBar)
    end
    UpdateBarWidth()
end

function BCDM:UpdateSecondaryPowerBarWidth()
    UpdateBarWidth()
end
