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
    local okMethod, getPoint = pcall(function() return powerBarFrame and powerBarFrame.GetPoint end)
    if not okMethod or type(getPoint) ~= "function" then return end
    local ok, point, relativeTo, relativePoint, xOfs, yOfs = pcall(getPoint, powerBarFrame, 1)
    if not ok or BCDM:IsSecretValue(point) or type(point) ~= "string" then return end
    xOfs = type(xOfs) == "number" and not BCDM:IsSecretValue(xOfs) and xOfs or 0
    yOfs = type(yOfs) == "number" and not BCDM:IsSecretValue(yOfs) and yOfs or 0
    pcall(function() powerBarFrame:ClearAllPoints() end)
    BCDM:SetSafeAnchorPoint(powerBarFrame, point, relativeTo, relativePoint,
        xOfs + xOffset, yOfs + yOffset)
end

local function UpdatePowerValues()
    local PowerBar = BCDM.PowerBar
    local _, class = UnitClass("player")
    local powerType = BCDM:ResolvePrimaryDisplayPowerType(
        UnitPowerType("player"), class, GetSpecialization(), GetShapeshiftFormID and GetShapeshiftFormID() or 0)
    local powerCurrent = UnitPower("player", powerType)
    local powerMax = UnitPowerMax("player", powerType)
    if PowerBar and PowerBar.Status and powerType then
        local textMode = BCDM.db.profile.PowerBar.Text.Mode or "AUTO"
        if BCDM:IsSecretValue(powerCurrent) or BCDM:IsSecretValue(powerMax) then
            PowerBar.Text:SetText("")
        elseif textMode ~= "AUTO" then
            PowerBar.Text:SetText(BCDM:FormatResourceText(powerCurrent, powerMax, textMode))
        elseif powerType == 0 then
            local percent = UnitPowerPercent("player", 0, false, CurveConstants.ScaleTo100)
            if BCDM:IsSecretValue(percent) then
                PowerBar.Text:SetText("")
            else
                PowerBar.Text:SetText(string.format("%.0f%%", percent))
            end
        else
            PowerBar.Text:SetText(tostring(powerCurrent))
        end
        PowerBar.Status:SetStatusBarColor(FetchPowerBarColour(powerType))
        PowerBar.Status:SetMinMaxValues(0, powerMax)
        PowerBar.Status:SetValue(powerCurrent)
    end
    return powerType
end

local function OnPowerBarEvent(self, event)
    UpdatePowerValues()
    if not BCDM._UpdatingPowerBars and BCDM.ApplyPowerBarOwnership then
        BCDM:ApplyPowerBarOwnership(BCDM._SecondaryResourceState)
    end
end

BCDM._PowerBarOnEvent = OnPowerBarEvent

local function RegisterPowerBarEvents(powerBar)
    powerBar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    powerBar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    powerBar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    powerBar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
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
    if BCDM.UpdatePowerBars then
        BCDM:UpdatePowerBars()
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
    local powerLayout, powerAnchor = BCDM:GetPowerBarLayout("PowerBar", false)
    BCDM:SetSafeAnchorPoint(PowerBar, powerLayout[1], powerAnchor,
        powerLayout[3], powerLayout[4], powerLayout[5])
    PowerBar:SetFrameStrata(PowerBarDB.FrameStrata or "LOW")

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
    PowerBar.Text:ClearAllPoints()
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
        function() BCDM:UpdatePowerBars() end)

    if PowerBarDB.Enabled then
        RegisterPowerBarEvents(PowerBar)
        PowerBar:SetScript("OnEvent", OnPowerBarEvent)
        NudgePowerBar("BCDM_PowerBar", -0.1, 0)
    else
        PowerBar:Hide()
        PowerBar:SetScript("OnEvent", nil)
        PowerBar:UnregisterAllEvents()
    end
    if BCDM.ApplyPowerBarOwnership then
        BCDM:ApplyPowerBarOwnership(BCDM._SecondaryResourceState or BCDM.RENDER_UNAVAILABLE)
    end
end

function BCDM:UpdatePowerBarAppearance()
    local profile = BCDM.db.profile
    local generalDB = profile.General
    local powerBarDB = profile.PowerBar
    local powerBar = BCDM.PowerBar
    local borderSize = profile.CooldownManager.General.BorderSize
    if not powerBar then return end
    if not powerBarDB.Enabled then
        powerBar:Hide()
        powerBar:SetScript("OnEvent", nil)
        powerBar:UnregisterAllEvents()
        return
    end

    powerBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        powerBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        powerBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    powerBar.Status:ClearAllPoints()
    powerBar.Status:SetPoint("TOPLEFT", powerBar, "TOPLEFT", borderSize, -borderSize)
    powerBar.Status:SetPoint("BOTTOMRIGHT", powerBar, "BOTTOMRIGHT", -borderSize, borderSize)
    powerBar:ClearAllPoints()
    local powerLayout, powerAnchor = BCDM:GetPowerBarLayout("PowerBar", false)
    BCDM:SetSafeAnchorPoint(powerBar, powerLayout[1], powerAnchor,
        powerLayout[3], powerLayout[4], powerLayout[5])
    if powerBarDB.MatchWidthOfAnchor ~= true then
        powerBar:SetWidth(powerBarDB.Width)
    end
    powerBar:SetHeight(BCDM._SecondaryDisplayVisible == true
        and powerBarDB.Height or powerBarDB.HeightWithoutSecondary)
    powerBar:SetFrameStrata(powerBarDB.FrameStrata or "LOW")
    powerBar:SetBackdropColor(powerBarDB.BackgroundColour[1], powerBarDB.BackgroundColour[2], powerBarDB.BackgroundColour[3], powerBarDB.BackgroundColour[4])
    powerBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    BCDM:ApplyStatusBarDirection(powerBar.Status, powerBarDB.FillDirection)
    BCDM:AnchorStatusBarSpark(powerBar.Spark, powerBar.Status, powerBarDB.FillDirection)
    powerBar.Spark:SetHeight(powerBar:GetHeight())
    powerBar.Spark:SetShown(powerBarDB.ShowSpark == true)
    powerBar.Text:SetFont(BCDM.Media.Font, powerBarDB.Text.FontSize, generalDB.Fonts.FontFlag)
    powerBar.Text:SetTextColor(powerBarDB.Text.Colour[1], powerBarDB.Text.Colour[2], powerBarDB.Text.Colour[3], 1)
    powerBar.Text:ClearAllPoints()
    powerBar.Text:SetPoint(powerBarDB.Text.Layout[1], powerBar, powerBarDB.Text.Layout[2], powerBarDB.Text.Layout[3], powerBarDB.Text.Layout[4])
    if generalDB.Fonts.Shadow.Enabled then
        powerBar.Text:SetShadowColor(generalDB.Fonts.Shadow.Colour[1], generalDB.Fonts.Shadow.Colour[2], generalDB.Fonts.Shadow.Colour[3], generalDB.Fonts.Shadow.Colour[4])
        powerBar.Text:SetShadowOffset(generalDB.Fonts.Shadow.OffsetX, generalDB.Fonts.Shadow.OffsetY)
    else
        powerBar.Text:SetShadowColor(0, 0, 0, 0)
        powerBar.Text:SetShadowOffset(0, 0)
    end
    powerBar.Status:SetStatusBarColor(FetchPowerBarColour())
    RegisterPowerBarEvents(powerBar)
    powerBar:SetScript("OnEvent", OnPowerBarEvent)
    UpdatePowerValues()
    if powerBarDB.Text.Enabled then powerBar.Text:Show() else powerBar.Text:Hide() end
end

function BCDM:UpdatePowerBar()
    if self.UpdatePowerBars and not self._UpdatingPowerBars then
        return self:UpdatePowerBars()
    end
    return self:UpdatePowerBarAppearance()
end

function BCDM:UpdatePowerBarWidth()
    if self.QueuePowerBarWidthUpdates then self:QueuePowerBarWidthUpdates() end
end
