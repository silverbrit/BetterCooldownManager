local _, BCDM = ...

local function FetchPowerBarColour(customPowerType)
    local CooldownManagerDB = BCDM.db.profile
    local GeneralDB = CooldownManagerDB.General
    local PowerBarDB = CooldownManagerDB.PowerBar
    if not PowerBarDB then return 1, 1, 1, 1 end
    local powerType = customPowerType or UnitPowerType("player")
    local _, class = UnitClass("player")
    return BCDM:ResolveBarFillColour("PowerBar", PowerBarDB, {
        ClassColour = RAID_CLASS_COLORS[class],
        PowerTypeColour = GeneralDB.Colours.PrimaryPower[powerType],
    })
end

local function NudgePowerBar(powerBar, xOffset, yOffset)
    local powerBarFrame = _G[powerBar]
    if not powerBarFrame then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = powerBarFrame:GetPoint(1)
    powerBarFrame:ClearAllPoints()
    powerBarFrame:SetPoint(point, relativeTo, relativePoint, xOfs + xOffset, yOfs + yOffset)
end

local function UpdatePowerValues()
    local PowerBar = BCDM.PowerBar
    local _, class = UnitClass("player")
    local powerType = UnitPowerType("player")
    if class == "DRUID" then
        local spec = GetSpecialization()
        local form = GetShapeshiftFormID() or 0 
        local isHybridMoonkin = (spec == 2 or spec == 3 or spec == 4) and form == 31 or form == 32 or form == 33 or form == 34 or form == 35
        local isBalanceHumanoid = (spec == 1 and form == 0)
        if isHybridMoonkin or isBalanceHumanoid then
            powerType = 0 
        end
    end
    local powerCurrent = UnitPower("player", powerType)
    local powerMax = UnitPowerMax("player", powerType)
    if PowerBar and PowerBar.Status and powerType then
        local textMode = BCDM.db.profile.PowerBar.Text.Mode or "AUTO"
        if textMode ~= "AUTO" then
            PowerBar.Text:SetText(BCDM:FormatResourceText(powerCurrent, powerMax, textMode))
        elseif powerType == 0 then
           PowerBar.Text:SetText(string.format("%.0f%%", UnitPowerPercent("player", 0, false, CurveConstants.ScaleTo100)))
        else
            PowerBar.Text:SetText(tostring(powerCurrent))
        end
        PowerBar.Status:SetStatusBarColor(FetchPowerBarColour(powerType))
        PowerBar.Status:SetMinMaxValues(0, powerMax)
        PowerBar.Status:SetValue(powerCurrent)
    end
end

local function RegisterPowerBarEvents(powerBar)
    powerBar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    powerBar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    powerBar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    powerBar:RegisterEvent("PLAYER_ENTERING_WORLD")
    powerBar:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
end

local function SetHooks()
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() if InCombatLockdown() then return end  BCDM:UpdatePowerBarWidth() end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() if InCombatLockdown() then return end  BCDM:UpdatePowerBarWidth() end)
end

local updatePowerBarHeightEventFrame = CreateFrame("Frame")
updatePowerBarHeightEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
updatePowerBarHeightEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
updatePowerBarHeightEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit and unit ~= "player" then return end
    end
    local PowerBarDB = BCDM.db.profile.PowerBar
    local PowerBar = BCDM.PowerBar
    if PowerBarDB.Enabled and PowerBar then
        local hasSecondary = BCDM:GetCurrentSecondaryResource() ~= nil
        PowerBar:SetHeight(hasSecondary and PowerBarDB.Height or PowerBarDB.HeightWithoutSecondary)
    end
end)

function BCDM:CreatePowerBar()
    local GeneralDB = BCDM.db.profile.General
    local PowerBarDB = BCDM.db.profile.PowerBar

    SetHooks()

    local PowerBar = _G.BCDM_PowerBar or CreateFrame("Frame", "BCDM_PowerBar", UIParent, "BackdropTemplate")
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize

    PowerBar:ClearAllPoints()
    PowerBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        PowerBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        PowerBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    PowerBar:SetBackdropColor(PowerBarDB.BackgroundColour[1], PowerBarDB.BackgroundColour[2], PowerBarDB.BackgroundColour[3], PowerBarDB.BackgroundColour[4])
    local hasSecondary = BCDM:GetCurrentSecondaryResource() ~= nil
    PowerBar:SetSize(PowerBarDB.Width, hasSecondary and PowerBarDB.Height or PowerBarDB.HeightWithoutSecondary)
    PowerBar:SetPoint(PowerBarDB.Layout[1], BCDM:ResolveAnchorParent(PowerBarDB.Layout[2]), PowerBarDB.Layout[3], PowerBarDB.Layout[4], PowerBarDB.Layout[5])
    PowerBar:SetFrameStrata(PowerBarDB.FrameStrata or "LOW")

    if PowerBarDB.MatchWidthOfAnchor then
        local anchorFrame = BCDM:ResolveAnchorParent(PowerBarDB.Layout[2])
        if anchorFrame then
            C_Timer.After(0.1, function() local anchorWidth = anchorFrame:GetWidth() PowerBar:SetWidth(anchorWidth) end)
        end
    end

    PowerBar.Status = CreateFrame("StatusBar", nil, PowerBar)
    PowerBar.Status:SetPoint("TOPLEFT", PowerBar, "TOPLEFT", borderSize, -borderSize)
    PowerBar.Status:SetPoint("BOTTOMRIGHT", PowerBar, "BOTTOMRIGHT", -borderSize, borderSize)
    PowerBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    PowerBar.Status:SetStatusBarColor(FetchPowerBarColour())
    PowerBar.Status:SetMinMaxValues(0, UnitPowerMax("player"))
    PowerBar.Status:SetValue(UnitPower("player"))
    BCDM:ApplyStatusBarDirection(PowerBar.Status, PowerBarDB.FillDirection)
    PowerBar.Spark = PowerBar.Status:CreateTexture(nil, "OVERLAY")
    PowerBar.Spark:SetColorTexture(1, 1, 1, 0.9)
    PowerBar.Spark:SetSize(2, PowerBarDB.Height)
    BCDM:AnchorStatusBarSpark(PowerBar.Spark, PowerBar.Status, PowerBarDB.FillDirection)
    PowerBar.Spark:SetShown(PowerBarDB.ShowSpark == true)

    PowerBar.Text = PowerBar.Status:CreateFontString(nil, "OVERLAY")
    PowerBar.Text:SetFont(BCDM.Media.Font, PowerBarDB.Text.FontSize, GeneralDB.Fonts.FontFlag)
    PowerBar.Text:SetTextColor(PowerBarDB.Text.Colour[1], PowerBarDB.Text.Colour[2], PowerBarDB.Text.Colour[3], 1)
    PowerBar.Text:SetPoint(PowerBarDB.Text.Layout[1], PowerBar, PowerBarDB.Text.Layout[2], PowerBarDB.Text.Layout[3], PowerBarDB.Text.Layout[4])
    if GeneralDB.Fonts.Shadow.Enabled then
        PowerBar.Text:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
        PowerBar.Text:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
    else
        PowerBar.Text:SetShadowColor(0, 0, 0, 0)
        PowerBar.Text:SetShadowOffset(0, 0)
    end
    PowerBar.Text:SetText("")
    if PowerBarDB.Text.Enabled then PowerBar.Text:Show() else PowerBar.Text:Hide() end

    BCDM.PowerBar = PowerBar
    BCDM:RegisterOwnedFrameVisibility(PowerBar, function() return BCDM.db.profile.PowerBar end,
        function() BCDM:UpdatePowerBar() end)

    if PowerBarDB.Enabled then
        RegisterPowerBarEvents(PowerBar)
        PowerBar:SetScript("OnEvent", UpdatePowerValues)
        NudgePowerBar("BCDM_PowerBar", -0.1, 0)
    else
        PowerBar:Hide()
        PowerBar:SetScript("OnEvent", nil)
        PowerBar:UnregisterAllEvents()
    end
end

function BCDM:UpdatePowerBar()
    local GeneralDB = BCDM.db.profile.General
    local PowerBarDB = BCDM.db.profile.PowerBar
    local PowerBar = BCDM.PowerBar
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize
    if PowerBar then
        if PowerBarDB.Enabled then
            PowerBar:SetBackdrop(BCDM.BACKDROP)
            if borderSize > 0 then
                PowerBar:SetBackdropBorderColor(0, 0, 0, 1)
            else
                PowerBar:SetBackdropBorderColor(0, 0, 0, 0)
            end
            PowerBar.Status:SetPoint("TOPLEFT", PowerBar, "TOPLEFT", borderSize, -borderSize)
            PowerBar.Status:SetPoint("BOTTOMRIGHT", PowerBar, "BOTTOMRIGHT", -borderSize, borderSize)
            PowerBar:ClearAllPoints()
            PowerBar:SetPoint(PowerBarDB.Layout[1], BCDM:ResolveAnchorParent(PowerBarDB.Layout[2]), PowerBarDB.Layout[3], PowerBarDB.Layout[4], PowerBarDB.Layout[5])
            PowerBar:SetFrameStrata(PowerBarDB.FrameStrata or "LOW")
            if PowerBarDB.MatchWidthOfAnchor then
                local anchorFrame = BCDM:ResolveAnchorParent(PowerBarDB.Layout[2])
                if anchorFrame then
                    C_Timer.After(0.1, function() local anchorWidth = anchorFrame:GetWidth() PowerBar:SetWidth(anchorWidth) end)
                end
            else
                PowerBar:SetWidth(PowerBarDB.Width)
            end
            local hasSecondary = BCDM:GetCurrentSecondaryResource() ~= nil
            PowerBar:SetHeight(hasSecondary and PowerBarDB.Height or PowerBarDB.HeightWithoutSecondary)
            PowerBar:SetBackdropColor(PowerBarDB.BackgroundColour[1], PowerBarDB.BackgroundColour[2], PowerBarDB.BackgroundColour[3], PowerBarDB.BackgroundColour[4])
            PowerBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
            BCDM:ApplyStatusBarDirection(PowerBar.Status, PowerBarDB.FillDirection)
            BCDM:AnchorStatusBarSpark(PowerBar.Spark, PowerBar.Status, PowerBarDB.FillDirection)
            PowerBar.Spark:SetHeight(PowerBar:GetHeight())
            PowerBar.Spark:SetShown(PowerBarDB.ShowSpark == true)
            PowerBar.Text:SetFont(BCDM.Media.Font, PowerBarDB.Text.FontSize, BCDM.db.profile.General.Fonts.FontFlag)
            PowerBar.Text:SetTextColor(PowerBarDB.Text.Colour[1], PowerBarDB.Text.Colour[2], PowerBarDB.Text.Colour[3], 1)
            PowerBar.Text:SetPoint(PowerBarDB.Text.Layout[1], PowerBar, PowerBarDB.Text.Layout[2], PowerBarDB.Text.Layout[3], PowerBarDB.Text.Layout[4])
            if GeneralDB.Fonts.Shadow.Enabled then
                PowerBar.Text:SetShadowColor(GeneralDB.Fonts.Shadow.Colour[1], GeneralDB.Fonts.Shadow.Colour[2], GeneralDB.Fonts.Shadow.Colour[3], GeneralDB.Fonts.Shadow.Colour[4])
                PowerBar.Text:SetShadowOffset(GeneralDB.Fonts.Shadow.OffsetX, GeneralDB.Fonts.Shadow.OffsetY)
            else
                PowerBar.Text:SetShadowColor(0, 0, 0, 0)
                PowerBar.Text:SetShadowOffset(0, 0)
            end
            PowerBar.Status:SetMinMaxValues(0, UnitPowerMax("player"))
            PowerBar.Status:SetStatusBarColor(FetchPowerBarColour())
            RegisterPowerBarEvents(PowerBar)
            PowerBar:SetScript("OnEvent", UpdatePowerValues)
            UpdatePowerValues()
            if PowerBarDB.Text.Enabled then PowerBar.Text:Show() else PowerBar.Text:Hide() end
            NudgePowerBar("BCDM_PowerBar", -0.1, 0)
            if PowerBarDB.Enabled and not BCDM.db.profile.SecondaryPowerBar.SwapToPowerBarPosition
                and BCDM:ShouldShowOwnedFrame(PowerBarDB) then PowerBar:Show() end
        else
            PowerBar:Hide()
            PowerBar:SetScript("OnEvent", nil)
            PowerBar:UnregisterAllEvents()
        end
    end
end

function BCDM:UpdatePowerBarWidth()
    local PowerBarDB = BCDM.db.profile.PowerBar
    local PowerBar = BCDM.PowerBar
    if PowerBarDB.Enabled and PowerBarDB.MatchWidthOfAnchor then
        local anchorFrame = BCDM:ResolveAnchorParent(PowerBarDB.Layout[2])
        if anchorFrame then
            C_Timer.After(0.5, function() local anchorWidth = anchorFrame:GetWidth() PowerBar:SetWidth(anchorWidth) end)
        end
    end
end
