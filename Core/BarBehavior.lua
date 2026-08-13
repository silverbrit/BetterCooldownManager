local _, BCDM = ...

local VALID_COLOUR_MODES = {
    CastBar = { CLASS = true, CUSTOM = true, INTERRUPTIBILITY = true },
    PowerBar = { CLASS = true, CUSTOM = true, POWER_TYPE = true },
    SecondaryPowerBar = { CLASS = true, CUSTOM = true, POWER_TYPE = true, SPECIALIZATION = true },
}

local DEFAULT_COLOUR_MODES = {
    CastBar = "CLASS",
    PowerBar = "POWER_TYPE",
    SecondaryPowerBar = "POWER_TYPE",
}

local LEGACY_COLOUR_FIELDS = { "ColourByClass", "ColourByType", "ColourBySpec" }

local function LegacyColourMode(barType, settings)
    if barType == "CastBar" then
        return settings.ColourByClass == false and "INTERRUPTIBILITY" or "CLASS"
    end
    if settings.ColourByType ~= false then return "POWER_TYPE" end
    if settings.ColourByClass == true then return "CLASS" end
    if barType == "SecondaryPowerBar" and settings.ColourBySpec == true then return "SPECIALIZATION" end
    return "CUSTOM"
end

function BCDM:NormalizeBarColourProfile(profile)
    if type(profile) ~= "table" then return false end
    local changed = false
    for barType, validModes in pairs(VALID_COLOUR_MODES) do
        local settings = profile[barType]
        if type(settings) == "table" then
            local mode = settings.ColourMode
            if not validModes[mode] then
                settings.ColourMode = LegacyColourMode(barType, settings)
                changed = true
            end
            for _, field in ipairs(LEGACY_COLOUR_FIELDS) do
                if settings[field] ~= nil then
                    settings[field] = nil
                    changed = true
                end
            end
        end
    end
    return changed
end

function BCDM:NormalizeBarColourProfiles(db)
    local profiles = db and db.sv and db.sv.profiles
    if type(profiles) ~= "table" then return false end
    local changed = false
    for _, profile in pairs(profiles) do
        if self:NormalizeBarColourProfile(profile) then changed = true end
    end
    return changed
end

function BCDM:NormalizeImportedProfile(profile)
    if type(profile) ~= "table" then return false end
    local changed = self:NormalizeBarColourProfile(profile)
    if self:NormalizeEssentialAnchorProfile(profile) then changed = true end
    if self:NormalizeRemovedSettingsProfile(profile) then changed = true end
    if self:MigrateCustomTrackerProfile(profile) then changed = true end
    return changed
end

function BCDM:NormalizeRemovedSettingsProfile(profile)
    if type(profile) ~= "table" then return false end
    local changed = false
    local function RemoveMacroCondition(policy)
        if type(policy) ~= "table" or policy.MacroCondition == nil then return end
        policy.MacroCondition = nil
        changed = true
    end
    RemoveMacroCondition(profile.Visibility)
    if type(profile.General) == "table" and type(profile.General.Animation) == "table" then
        if profile.General.Animation.SmoothBars ~= nil then changed = true end
        profile.General.Animation.SmoothBars = nil
        if next(profile.General.Animation) == nil then profile.General.Animation = nil end
    end
    for _, barType in ipairs({ "PowerBar", "SecondaryPowerBar" }) do
        local settings = profile[barType]
        if type(settings) == "table" then
            if settings.Smoothing ~= nil then settings.Smoothing = nil changed = true end
            if barType == "PowerBar" and settings.FrequentUpdates ~= nil then
                settings.FrequentUpdates = nil
                changed = true
            end
        end
    end
    for _, barType in ipairs({ "PowerBar", "SecondaryPowerBar", "CastBar" }) do
        RemoveMacroCondition(type(profile[barType]) == "table" and profile[barType].Visibility)
    end
    local cooldownManager = profile.CooldownManager
    if type(cooldownManager) == "table" then
        RemoveMacroCondition(type(cooldownManager.Trinket) == "table" and cooldownManager.Trinket.Visibility)
        local store = cooldownManager.CustomTrackers
        for _, bar in pairs(type(store) == "table" and type(store.Bars) == "table" and store.Bars or {}) do
            RemoveMacroCondition(type(bar) == "table" and bar.Visibility)
        end
    end
    return changed
end

function BCDM:NormalizeRemovedSettingsProfiles(db)
    local profiles = db and db.sv and db.sv.profiles
    if type(profiles) ~= "table" then return false end
    local changed = false
    for _, profile in pairs(profiles) do
        if self:NormalizeRemovedSettingsProfile(profile) then changed = true end
    end
    return changed
end

local function ColourComponents(colour)
    if type(colour) ~= "table" then return nil end
    local r, g, b = colour[1] or colour.r, colour[2] or colour.g, colour[3] or colour.b
    if r == nil or g == nil or b == nil then return nil end
    return r, g, b, colour[4] or colour.a or 1
end

function BCDM:ResolveBarFillColour(barType, settings, context)
    settings = settings or {}
    context = context or {}
    local validModes = VALID_COLOUR_MODES[barType] or {}
    local mode = validModes[settings.ColourMode] and settings.ColourMode or DEFAULT_COLOUR_MODES[barType] or "CUSTOM"
    local colour = context.OverrideColour

    if colour then
        -- Contextual resource states intentionally take precedence over the selected base mode.
    elseif mode == "CLASS" then
        colour = context.ClassColour
    elseif mode == "POWER_TYPE" then
        colour = context.PowerTypeColour
    elseif mode == "SPECIALIZATION" then
        colour = context.SpecializationColour or context.PowerTypeColour
    elseif mode == "INTERRUPTIBILITY" then
        if context.Interruptibility == "NON_INTERRUPTIBLE" then
            colour = settings.NonInterruptibleColour
        else
            colour = settings.InterruptibleColour
        end
    else
        colour = settings.ForegroundColour
    end

    local r, g, b, a = ColourComponents(colour)
    if r ~= nil then return r, g, b, a end
    r, g, b, a = ColourComponents(settings.ForegroundColour)
    if r ~= nil then return r, g, b, a end
    return 1, 1, 1, 1
end

function BCDM:FormatResourceText(current, maximum, mode)
    if self.IsSecretValue and (self:IsSecretValue(current) or self:IsSecretValue(maximum)) then
        return ""
    end
    current, maximum = tonumber(current) or 0, tonumber(maximum) or 0
    if mode == "CURRENT_MAX" then return string.format("%s / %s", current, maximum) end
    if mode == "PERCENT" then
        local percent = maximum > 0 and (current / maximum) * 100 or 0
        return string.format("%.0f%%", percent)
    end
    return tostring(current)
end

function BCDM:ApplyStatusBarDirection(statusBar, direction)
    if statusBar and statusBar.SetReverseFill then statusBar:SetReverseFill(direction == "LEFT") end
end

function BCDM:AnchorStatusBarSpark(spark, statusBar, direction)
    if not spark or not statusBar then return end
    local edge = direction == "LEFT" and "LEFT" or "RIGHT"
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", statusBar:GetStatusBarTexture(), edge, 0, 0)
end
