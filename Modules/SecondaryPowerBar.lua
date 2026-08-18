local _, BCDM = ...

local runeBars = {}
local comboPoints = {}
local essenceTicks = {}
local resizeTimer = nil
local tickLayoutKey
local tickLayoutResource
local lastReadableMaximum = {}

local RENDER_UNAVAILABLE = 0
local RENDER_READABLE = 1
local RENDER_WIDGET = 2

local function ReadValue(value)
    if BCDM:IsSecretValue(value) then return value, RENDER_WIDGET end
    if type(value) ~= "number" then return nil, RENDER_UNAVAILABLE end
    return value, RENDER_READABLE
end

local function ReadAPI(api, ...)
    if type(api) ~= "function" then return nil, RENDER_UNAVAILABLE end
    local ok, value = pcall(api, ...)
    if not ok then return nil, RENDER_UNAVAILABLE end
    return ReadValue(value)
end

local function MergeRenderStates(...)
    local widget = false
    for i = 1, select("#", ...) do
        local state = select(i, ...)
        if state == RENDER_UNAVAILABLE then return RENDER_UNAVAILABLE end
        if state == RENDER_WIDGET then widget = true end
    end
    return widget and RENDER_WIDGET or RENDER_READABLE
end

local function ApplyChildBarDirection(bar, direction)
    if BCDM.ApplyStatusBarDirection then
        BCDM:ApplyStatusBarDirection(bar, direction)
    elseif bar and bar.SetReverseFill then
        bar:SetReverseFill(direction == "LEFT")
    end
end

local function HideBars(bars, getBar)
    for _, value in ipairs(bars) do
        local bar = getBar and getBar(value) or value
        if bar then
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
        end
    end
end

local function SetBarText(bar, text)
    if bar.Text and bar.Text.SetText then bar.Text:SetText(text or "") end
end

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
        ApplyChildBarDirection(runeBar, BCDM.db.profile.SecondaryPowerBar.FillDirection)
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
        ApplyChildBarDirection(bar, BCDM.db.profile.SecondaryPowerBar.FillDirection)
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
        ApplyChildBarDirection(bar, BCDM.db.profile.SecondaryPowerBar.FillDirection)

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
        ApplyChildBarDirection(runeBar, BCDM.db.profile.SecondaryPowerBar.FillDirection)

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
        ApplyChildBarDirection(bar, BCDM.db.profile.SecondaryPowerBar.FillDirection)

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
        ApplyChildBarDirection(bar, BCDM.db.profile.SecondaryPowerBar.FillDirection)

        if i == 1 then
            bar:SetPoint("LEFT", parent, "LEFT", 1, 0)
        else
            bar:SetPoint("LEFT", essenceTicks[i - 1].bar, "RIGHT", spacing, 0)
        end
    end
end

local function ReadRuneCooldown(runeIndex)
    if type(GetRuneCooldown) ~= "function" then return nil, nil, nil end
    local ok, startTime, duration, runeReady = pcall(GetRuneCooldown, runeIndex)
    if not ok then return nil, nil, nil end
    return startTime, duration, runeReady
end

local function ReadRuneStates()
    local states, readyCount = {}, 0
    for i = 1, 6 do
        local startTime, duration, runeReady = ReadRuneCooldown(i)
        if BCDM:IsSecretValue(startTime) or BCDM:IsSecretValue(duration) or BCDM:IsSecretValue(runeReady)
            or (runeReady ~= true and runeReady ~= false) then
            return nil, nil, RENDER_UNAVAILABLE
        end
        states[i] = { startTime = startTime, duration = duration, ready = runeReady }
        if runeReady then readyCount = readyCount + 1 end
    end
    return states, readyCount, RENDER_READABLE
end

local function StartRuneOnUpdate(runeBar, runeIndex, descriptor)
    local generalDB = BCDM.db.profile.General

    runeBar:SetScript("OnUpdate", function(self)
        local runeStartTime, runeDuration, runeReady = ReadRuneCooldown(runeIndex)

        if runeStartTime == nil and runeDuration == nil and runeReady == nil then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end

        if runeReady then
            self:SetScript("OnUpdate", nil)
            self:SetValue(1)
            local r, g, b, a = GetPowerBarColor(descriptor)
            self:SetStatusBarColor(r, g, b, a)
            return
        end

        if type(runeDuration) == "number" and runeDuration > 0 then
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
    local runeStates, _, state = ReadRuneStates()
    if state == RENDER_UNAVAILABLE then
        HideBars(runeBars)
        if BCDM.ClearTicks then BCDM:ClearTicks() end
        tickLayoutKey = false
        tickLayoutResource = nil
        return state
    end

    local runeReadyList = {}
    local runeOnCDList = {}
    for i = 1, maxPower do
        local runeState = runeStates[i]
        if runeState.ready then
            table.insert(runeReadyList, { index = i })
        elseif type(runeState.startTime) == "number" and type(runeState.duration) == "number"
            and runeState.duration > 0 then
            local remain = math.max(0, runeState.duration - (GetTime() - runeState.startTime))
            table.insert(runeOnCDList, { index = i, remaining = remain })
        else
            table.insert(runeOnCDList, { index = i, remaining = 999 })
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

        local runeState = runeStates[i]
        if runeState.ready then
            runeBar:SetValue(1)
            runeBar:SetStatusBarColor(r, g, b, a)
            runeBar:SetScript("OnUpdate", nil)
        else
            StartRuneOnUpdate(runeBar, i, descriptor)
        end
    end
    return RENDER_READABLE
end

local function GetChargedPowerPointLookup()
    local chargedLookup = {}
    if type(GetUnitChargedPowerPoints) ~= "function" then return chargedLookup end
    local ok, charged = pcall(GetUnitChargedPowerPoints, "player")
    if not ok or BCDM:IsSecretValue(charged) or type(charged) ~= "table" then return chargedLookup end
    local iterationOK = pcall(function()
        for _, index in ipairs(charged) do
            local point, state = ReadValue(index)
            if state == RENDER_READABLE then chargedLookup[point] = true end
        end
    end)
    return iterationOK and chargedLookup or {}
end

local function UpdateComboDisplay(descriptor, powerCurrent, currentState, powerMax, maxState)
    local state = MergeRenderStates(currentState, maxState)
    if state == RENDER_UNAVAILABLE then return state end

    local maxPoints = powerMax
    if maxState == RENDER_WIDGET then
        maxPoints = lastReadableMaximum.COMBO_POINTS or #comboPoints
    else
        lastReadableMaximum.COMBO_POINTS = powerMax
    end
    if not maxPoints or maxPoints <= 0 then return state end

    if #comboPoints ~= maxPoints then
        CreateComboPoints(maxPoints)
        LayoutComboPoints()
    end
    for _, bar in ipairs(comboPoints) do
        ApplyChildBarDirection(bar, BCDM.db.profile.SecondaryPowerBar.FillDirection)
    end

    local powerBarColourR, powerBarColourG, powerBarColourB, powerBarColourA = GetPowerBarColor(descriptor)
    local chargedComboPointColour = BCDM.db.profile.General.Colours.SecondaryPower["CHARGED_COMBO_POINTS"]
    local chargedLookup = GetChargedPowerPointLookup()

    for i = 1, maxPoints do
        local bar = comboPoints[i]
        bar:SetMinMaxValues(i - 1, i)
        bar:SetValue(powerCurrent)
        if chargedLookup[i] then
            bar:SetStatusBarColor(GetPowerBarColor(descriptor, chargedComboPointColour))
        else
            bar:SetStatusBarColor(powerBarColourR, powerBarColourG, powerBarColourB, powerBarColourA or 1)
        end
        bar:Show()
    end
    return state
end

local function HideEssenceBars()
    for _, tick in ipairs(essenceTicks) do
        tick.bar:SetScript("OnUpdate", nil)
        tick.bar:Hide()
    end
end

local function GetEssencePartialProgress()
    local displayMod, displayState = ReadAPI(UnitPowerDisplayMod, Enum.PowerType.Essence)
    if displayState ~= RENDER_READABLE or displayMod <= 0 then
        return nil, displayState
    end

    local partialPower, partialState = ReadAPI(UnitPartialPower, "player", Enum.PowerType.Essence)
    if partialState ~= RENDER_READABLE then return nil, partialState end
    return math.max(0, math.min(1, partialPower / displayMod)), RENDER_READABLE
end

local function UpdateEssenceDisplay(descriptor, powerCurrent, currentState, powerMax, maxState)
    local parent = BCDM.SecondaryPowerBar
    if not parent or #essenceTicks == 0 then return end

    if currentState ~= RENDER_READABLE or maxState ~= RENDER_READABLE then
        HideEssenceBars()
        return
    end

    local maxPoints = powerMax
    local partialProgress
    if powerCurrent < maxPoints then
        local partialState
        partialProgress, partialState = GetEssencePartialProgress()
        if partialState ~= RENDER_READABLE then
            HideEssenceBars()
            return
        end
    end

    local r, g, b, a = GetPowerBarColor(descriptor)
    local rechargeColour = BCDM.db.profile.General.Colours.SecondaryPower["ESSENCE_RECHARGE"]
    lastReadableMaximum.ESSENCE = maxPoints

    for i = 1, #essenceTicks do
        local tick = essenceTicks[i]
        local bar = tick.bar
        ApplyChildBarDirection(bar, BCDM.db.profile.SecondaryPowerBar.FillDirection)
        bar:Show()
        bar:SetScript("OnUpdate", nil)
        bar:SetMinMaxValues(i - 1, i)
        bar:SetValue(powerCurrent)

        if i <= powerCurrent then
            bar:SetStatusBarColor(r, g, b, a)
        elseif i == powerCurrent + 1 and powerCurrent < maxPoints then
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(partialProgress)
            bar:SetStatusBarColor(GetPowerBarColor(descriptor, rechargeColour))
        else
            bar:SetStatusBarColor(0, 0, 0, 1)
        end
    end
end

local function GetPlayerAuraBySpellID(spellId)
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil, RENDER_UNAVAILABLE end
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
    if not ok or BCDM:IsSecretValue(auraData) then return nil, RENDER_UNAVAILABLE end
    return auraData, RENDER_READABLE
end

local function GetAuraStacks(spellId)
    local auraData, auraState = GetPlayerAuraBySpellID(spellId)
    if auraState == RENDER_UNAVAILABLE then return nil, false, false end
    if auraData == nil then return 0, true, false end
    if type(auraData) ~= "table" then return nil, false, false end
    local ok, applications = pcall(function() return auraData.applications end)
    if not ok then return nil, false, false end
    local value, state = ReadValue(applications)
    return value, state == RENDER_READABLE, state == RENDER_WIDGET
end

local function IsInMetamorphosis(spellId)
    local auraData, auraState = GetPlayerAuraBySpellID(spellId)
    if auraState == RENDER_UNAVAILABLE then return nil, false, false end
    return auraData ~= nil, true, false
end

local function GetSpellCharges(spellId)
    if not C_Spell or not C_Spell.GetSpellCastCount then return nil, false, false end
    local ok, charges = pcall(C_Spell.GetSpellCastCount, spellId)
    if not ok then return nil, false, false end
    local value, state = ReadValue(charges)
    return value, state == RENDER_READABLE, state == RENDER_WIDGET
end

local function GetSpellMaximum(spellId, fallback)
    if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
        return ReadAPI(C_Spell.GetSpellMaxCumulativeAuraApplications, spellId)
    end
    return ReadValue(fallback)
end

local function GetPowerValue(powerType, unmodified)
    return ReadAPI(UnitPower, "player", powerType, unmodified == true)
end

local function GetPowerMaximum(powerType)
    return ReadAPI(UnitPowerMax, "player", powerType)
end

local function GetHealthMaximum()
    return ReadAPI(UnitHealthMax, "player")
end

local function ReaderState(readable, widget)
    if widget then return RENDER_WIDGET end
    if readable then return RENDER_READABLE end
    return RENDER_UNAVAILABLE
end

local function GetDevourerValues(descriptor)
    local inMetamorphosis, auraReadable, auraWidget = IsInMetamorphosis(descriptor.metamorphosisAuraID)
    local auraState = ReaderState(auraReadable, auraWidget)
    if auraState ~= RENDER_READABLE then return nil, nil, auraState end

    local sourceSpellID = inMetamorphosis and descriptor.transformedSourceSpellID or descriptor.sourceSpellID
    local current, currentReadable, currentWidget = GetAuraStacks(sourceSpellID)
    local currentState = ReaderState(currentReadable, currentWidget)
    local maximum, maximumState
    if inMetamorphosis then
        maximum, maximumState = ReadAPI(GetCollapsingStarCost)
    else
        maximum, maximumState = GetSpellMaximum(descriptor.maximumSpellID, descriptor.maximum)
    end
    return current, maximum, MergeRenderStates(currentState, maximumState), sourceSpellID
end

BCDM._SecondaryResourceReaders = {
    GetAuraStacks = GetAuraStacks,
    IsInMetamorphosis = IsInMetamorphosis,
    GetSpellCharges = GetSpellCharges,
    GetSpellMaximum = function(spellId, fallback)
        local value, state = GetSpellMaximum(spellId, fallback)
        return value, state == RENDER_READABLE, state == RENDER_WIDGET
    end,
    GetDevourerValues = GetDevourerValues,
    GetChargedPowerPointLookup = GetChargedPowerPointLookup,
}

local RESOURCE_HANDLERS = {}

local function SetResourceStatus(bar, current, maximum)
    bar.Status:SetMinMaxValues(0, maximum)
    bar.Status:SetValue(current)
    bar.Status:Show()
end

local function ReadableText(current, maximum, fractional)
    if fractional then return string.format("%.1f", current / 10) end
    return tostring(current)
end

local function SetStandardValue(descriptor, bar)
    local current, currentState = GetPowerValue(descriptor.powerType)
    local maximum, maximumState = GetPowerMaximum(descriptor.powerType)
    local state = MergeRenderStates(currentState, maximumState)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    SetResourceStatus(bar, current, maximum)
    return current, maximum, state, state == RENDER_READABLE and ReadableText(current, maximum) or nil
end

RESOURCE_HANDLERS.STANDARD = SetStandardValue
RESOURCE_HANDLERS.AURA_STACKS = function(descriptor, bar)
    local current, readable, widget = GetAuraStacks(descriptor.sourceSpellID)
    local maximum, maximumState = GetSpellMaximum(descriptor.maximumSpellID, descriptor.maximum)
    local state = MergeRenderStates(ReaderState(readable, widget), maximumState)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    SetResourceStatus(bar, current, maximum)
    return current, maximum, state, state == RENDER_READABLE and ReadableText(current, maximum) or nil
end
RESOURCE_HANDLERS.SPELL_CHARGES = function(descriptor, bar)
    local current, readable, widget = GetSpellCharges(descriptor.sourceSpellID)
    local state = ReaderState(readable, widget)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    SetResourceStatus(bar, current, descriptor.maximum)
    return current, descriptor.maximum, state, state == RENDER_READABLE and ReadableText(current, descriptor.maximum) or nil
end
RESOURCE_HANDLERS.DEVOURER_SOUL = function(descriptor, bar)
    local current, maximum, state = GetDevourerValues(descriptor)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    SetResourceStatus(bar, current, maximum)
    return current, maximum, state, state == RENDER_READABLE and ReadableText(current, maximum) or nil
end
RESOURCE_HANDLERS.SOUL_SHARDS = function(descriptor, bar)
    local current, currentState = GetPowerValue(descriptor.powerType, descriptor.fractional)
    local maximum, maximumState
    if descriptor.fractional then
        maximum, maximumState = 50, RENDER_READABLE
    else
        maximum, maximumState = GetPowerMaximum(descriptor.powerType)
    end
    local state = MergeRenderStates(currentState, maximumState)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    SetResourceStatus(bar, current, maximum)
    return current, maximum, state, state == RENDER_READABLE and ReadableText(current, maximum, descriptor.fractional) or nil
end
RESOURCE_HANDLERS.COMBO_POINTS = function(descriptor, bar)
    local current, currentState = GetPowerValue(descriptor.powerType)
    local maximum, maximumState = GetPowerMaximum(descriptor.powerType)
    local state = MergeRenderStates(currentState, maximumState)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    SetResourceStatus(bar, current, maximum)
    UpdateComboDisplay(descriptor, current, currentState, maximum, maximumState)
    return current, maximum, state, state == RENDER_READABLE and ReadableText(current, maximum) or nil
end
RESOURCE_HANDLERS.ESSENCE = function(descriptor, bar, settings)
    local current, currentState = GetPowerValue(descriptor.powerType)
    local maximum, maximumState = GetPowerMaximum(descriptor.powerType)
    local state = MergeRenderStates(currentState, maximumState)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    if settings.HideTicks then
        HideEssenceBars()
    else
        UpdateEssenceDisplay(descriptor, current, currentState, maximum, maximumState)
    end
    SetResourceStatus(bar, current, maximum)
    return current, maximum, state, state == RENDER_READABLE and ReadableText(current, maximum) or nil
end
RESOURCE_HANDLERS.RUNES = function(descriptor, bar, settings)
    if settings.HideTicks then
        HideBars(runeBars)
        local _, current, state = ReadRuneStates()
        if state == RENDER_UNAVAILABLE then return nil, nil, state end
        SetResourceStatus(bar, current, 6)
        return current, 6, state, ReadableText(current, 6)
    end
    bar.Status:Hide()
    local state = UpdateRuneDisplay(descriptor)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    return 0, 6, state, ""
end
RESOURCE_HANDLERS.STAGGER = function(descriptor, bar, settings)
    if BCDM.ClearTicks then BCDM:ClearTicks() end
    tickLayoutKey = nil
    tickLayoutResource = nil
    local current, currentState = ReadAPI(UnitStagger, "player")
    local maximum, maximumState = GetHealthMaximum()
    local state = MergeRenderStates(currentState, maximumState)
    if state == RENDER_UNAVAILABLE then return nil, nil, state end
    SetResourceStatus(bar, current, maximum)
    if state == RENDER_WIDGET then
        bar.Status:SetStatusBarColor(GetPowerBarColor(descriptor))
        return current, maximum, state
    end

    if settings.ColourByState then
        local colours = BCDM.db.profile.General.Colours.SecondaryPower.STAGGER_COLOURS
        local percentage = maximum > 0 and (current / maximum) * 100 or 0
        local stateColour = percentage < 30 and colours.LIGHT or percentage < 60 and colours.MODERATE or colours.HEAVY
        bar.Status:SetStatusBarColor(GetPowerBarColor(descriptor, stateColour))
    else
        bar.Status:SetStatusBarColor(GetPowerBarColor(descriptor))
    end
    local text = AbbreviateLargeNumbers(current)
    if settings.Text.ShowStaggerDPS and current > 0 then
        text = text .. " (" .. AbbreviateLargeNumbers(current / 20) .. " / 0.5s)"
    end
    return current, maximum, state, text, true
end

local function HideInactiveResourceDisplays(kind)
    if kind ~= "RUNES" then HideBars(runeBars) end
    if kind ~= "COMBO_POINTS" then HideBars(comboPoints) end
    if kind ~= "ESSENCE" then HideBars(essenceTicks, function(value) return value.bar end) end
end

local function HideAllResourceDisplays()
    HideInactiveResourceDisplays(nil)
    tickLayoutKey = nil
    tickLayoutResource = nil
    if BCDM.ClearTicks and BCDM.SecondaryPowerBar then BCDM:ClearTicks() end
end

local function UpdatePowerValues()
    local descriptor = BCDM:GetCurrentSecondaryResource()
    local bar = BCDM.SecondaryPowerBar
    local settings = BCDM.db.profile.SecondaryPowerBar
    if not descriptor then
        HideAllResourceDisplays()
        if bar then
            bar.Status:Hide()
            SetBarText(bar, "")
            bar:Hide()
        end
        return RENDER_UNAVAILABLE
    end
    if not bar then return RENDER_UNAVAILABLE end
    local handler = RESOURCE_HANDLERS[descriptor.kind]
    if not handler then
        HideAllResourceDisplays()
        bar.Status:Hide()
        SetBarText(bar, "")
        bar:Hide()
        return RENDER_UNAVAILABLE
    end

    HideInactiveResourceDisplays(descriptor.kind)
    local current, maximum, state, text, colourApplied = handler(descriptor, bar, settings)
    if state == RENDER_UNAVAILABLE then
        bar.Status:Hide()
        SetBarText(bar, "")
        bar:Hide()
        return state
    end
    if not colourApplied then bar.Status:SetStatusBarColor(GetPowerBarColor(descriptor)) end
    if state == RENDER_READABLE and settings.Text and settings.Text.Mode and settings.Text.Mode ~= "AUTO" then
        text = BCDM:FormatResourceText(current, maximum, settings.Text.Mode)
    elseif state == RENDER_WIDGET then
        text = nil
    end
    SetBarText(bar, text)
    bar:Show()
    return state
end

local function ClearTickLayout()
    if tickLayoutKey ~= false and BCDM.ClearTicks then BCDM:ClearTicks() end
    tickLayoutKey = false
    tickLayoutResource = nil
end

local function SetTickLayout(key, count, resource)
    if not count or count <= 1 or not BCDM.CreateTicks then
        ClearTickLayout()
        return
    end
    if tickLayoutKey == key then return end
    BCDM:CreateTicks(count)
    tickLayoutKey = key
    tickLayoutResource = resource or key
end

local function GetTickMaximum(descriptor)
    if descriptor.kind == "DEVOURER_SOUL" then
        local _, maximum, state = GetDevourerValues(descriptor)
        return maximum, state
    elseif descriptor.maximumSpellID then
        return GetSpellMaximum(descriptor.maximumSpellID, descriptor.maximum)
    elseif descriptor.kind == "ESSENCE" or descriptor.kind == "STANDARD"
        or descriptor.kind == "COMBO_POINTS" then
        return GetPowerMaximum(descriptor.powerType)
    end
    return descriptor.tickCount, descriptor.tickCount and RENDER_READABLE or RENDER_UNAVAILABLE
end

local function CreateTicksBasedOnPowerType()
    local settings = BCDM.db.profile.SecondaryPowerBar
    local descriptor = BCDM:GetCurrentSecondaryResource()
    if settings.HideTicks or not descriptor then
        ClearTickLayout()
        return UpdatePowerValues()
    end
    if tickLayoutResource and tickLayoutResource ~= descriptor.kind then ClearTickLayout() end
    if descriptor.kind == "RUNES" then
        if #runeBars == 0 then CreateRuneBars() end
        LayoutRuneBars()
        SetTickLayout("RUNES", descriptor.tickCount or 6, descriptor.kind)
    elseif descriptor.kind == "ESSENCE" then
        local maximum, state = GetPowerMaximum(descriptor.powerType)
        if state == RENDER_READABLE and maximum > 0 then
            if #essenceTicks ~= maximum then CreateEssenceTicks(maximum) end
            LayoutEssenceTicks()
            SetTickLayout("ESSENCE:" .. maximum, maximum, descriptor.kind)
        end
    elseif descriptor.powerType == Enum.PowerType.Mana then
        ClearTickLayout()
    else
        local maximum, state = GetTickMaximum(descriptor)
        if state == RENDER_READABLE and maximum > 0 then
            local count = descriptor.kind == "DEVOURER_SOUL" and math.ceil(maximum / 5) or maximum
            SetTickLayout(descriptor.kind .. ":" .. count, count, descriptor.kind)
        end
    end
    return UpdatePowerValues()
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
            UpdatePowerValues()
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
        UpdatePowerValues()
    end
end

local RESOURCE_EVENTS = {
    "UNIT_POWER_UPDATE",
    "UNIT_POWER_FREQUENT",
    "UNIT_POWER_POINT_CHARGE",
    "UNIT_MAXPOWER",
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "RUNE_POWER_UPDATE",
    "RUNE_TYPE_UPDATE",
    "UNIT_AURA",
}

local function SetResourceEventRegistration(secondaryPowerBar, enabled)
    if enabled then
        secondaryPowerBar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        secondaryPowerBar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        secondaryPowerBar:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
        secondaryPowerBar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        secondaryPowerBar:RegisterUnitEvent("UNIT_HEALTH", "player")
        secondaryPowerBar:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
        secondaryPowerBar:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
        secondaryPowerBar:RegisterEvent("RUNE_POWER_UPDATE")
        secondaryPowerBar:RegisterEvent("RUNE_TYPE_UPDATE")
        secondaryPowerBar:RegisterUnitEvent("UNIT_AURA", "player")
    else
        for _, event in ipairs(RESOURCE_EVENTS) do secondaryPowerBar:UnregisterEvent(event) end
    end
end

local function IsResourceEvent(event)
    for _, resourceEvent in ipairs(RESOURCE_EVENTS) do
        if event == resourceEvent then return true end
    end
    return false
end

local function OnSecondaryPowerBarEvent(self, event, ...)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit and unit ~= "player" then return end
        BCDM:UpdateSecondaryPowerBar()
        return
    elseif event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "PLAYER_TALENT_UPDATE" then
        BCDM:UpdateSecondaryPowerBar()
        return
    end

    if event == "RUNE_POWER_UPDATE" or event == "RUNE_TYPE_UPDATE" then
        local descriptor = BCDM:GetCurrentSecondaryResource()
        if not descriptor then
            if self then SetResourceEventRegistration(self, false) end
            UpdatePowerValues()
        elseif descriptor.kind == "RUNES" then
            if BCDM.db.profile.SecondaryPowerBar.HideTicks then
                UpdatePowerValues()
            else
                local state = UpdateRuneDisplay(descriptor)
                if state == RENDER_UNAVAILABLE then
                    UpdatePowerValues()
                elseif tickLayoutKey ~= "RUNES" then
                    CreateTicksBasedOnPowerType()
                end
            end
        end
        return
    end

    if IsResourceEvent(event) and not BCDM:GetCurrentSecondaryResource() then
        if self then SetResourceEventRegistration(self, false) end
        UpdatePowerValues()
        return
    end

    if event == "UNIT_AURA" then
        if BCDM.db.profile.SecondaryPowerBar.HideTicks then
            UpdatePowerValues()
        else
            CreateTicksBasedOnPowerType()
        end
        return
    elseif event == "UNIT_MAXPOWER" then
        CreateTicksBasedOnPowerType()
        return
    end

    UpdatePowerValues()
end

BCDM._SecondaryPowerBarOnEvent = OnSecondaryPowerBarEvent

local function RegisterSecondaryPowerBarEvents(secondaryPowerBar)
    secondaryPowerBar:RegisterEvent("PLAYER_ENTERING_WORLD")
    secondaryPowerBar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    secondaryPowerBar:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    secondaryPowerBar:RegisterEvent("PLAYER_TALENT_UPDATE")
    SetResourceEventRegistration(secondaryPowerBar, BCDM:GetCurrentSecondaryResource() ~= nil)
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
        local renderState = UpdatePowerValues()
        renderState = CreateTicksBasedOnPowerType() or renderState
        NudgeSecondaryPowerBar("BCDM_SecondaryPowerBar", -0.1, 0)
        if renderState ~= RENDER_UNAVAILABLE and BCDM:GetCurrentSecondaryResource() then
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
        if BCDM.SecondaryPowerBar then
            SetResourceEventRegistration(BCDM.SecondaryPowerBar, false)
            HideAllResourceDisplays()
            BCDM.SecondaryPowerBar:Hide()
        end
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
        local renderState = UpdatePowerValues()
        renderState = CreateTicksBasedOnPowerType() or renderState
        NudgeSecondaryPowerBar("BCDM_SecondaryPowerBar", -0.1, 0)
        local shouldShow = renderState ~= RENDER_UNAVAILABLE
        if BCDM.ShouldShowOwnedFrame then shouldShow = shouldShow and BCDM:ShouldShowOwnedFrame(secondaryPowerBarDB) end
        if shouldShow then secondaryPowerBar:Show() else secondaryPowerBar:Hide() end
    else
        secondaryPowerBar:Hide()
        UnregisterSecondaryPowerBarEvents(secondaryPowerBar)
    end
    UpdateBarWidth()
end

function BCDM:UpdateSecondaryPowerBarWidth()
    UpdateBarWidth()
end
