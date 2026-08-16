local _, BCDM = ...

local function IsSecretValue(value)
    return BCDM.IsSecretValue and BCDM:IsSecretValue(value) or false
end

local function IsReadableBoolean(value)
    return not IsSecretValue(value) and type(value) == "boolean"
end

local function IsReadableCastBarID(value)
    return not IsSecretValue(value) and type(value) == "number"
end

local function GetDisplayCastText(text, maxChars)
    if IsSecretValue(text) then return text end
    if type(text) ~= "string" then return "" end

    text = text:gsub("\226\128\152", "'"):gsub("\226\128\153", "'"):gsub("`", "'")
    if type(maxChars) ~= "number" then return text end
    maxChars = math.floor(maxChars)
    if maxChars < 1 then return "" end

    local position, characters = 1, 0
    while position <= #text and characters < maxChars do
        local byte = string.byte(text, position)
        local width = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
        position = position + width
        characters = characters + 1
    end
    return string.sub(text, 1, position - 1)
end

local function FetchCastBarColour(notInterruptible)
    local CastBarDB = BCDM.db.profile.CastBar
    local _, class = UnitClass("player")
    local interruptibility = "UNKNOWN"
    if IsReadableBoolean(notInterruptible) then
        interruptibility = notInterruptible and "NON_INTERRUPTIBLE" or "INTERRUPTIBLE"
    elseif BCDM.CastBar and IsReadableBoolean(BCDM.CastBar.LastNotInterruptible) then
        interruptibility = BCDM.CastBar.LastNotInterruptible and "NON_INTERRUPTIBLE" or "INTERRUPTIBLE"
    end
    return BCDM:ResolveBarFillColour("CastBar", CastBarDB, {
        ClassColour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class],
        Interruptibility = interruptibility,
    })
end

local function UpdateCastBarColour(notInterruptible)
    local CastBar = BCDM.CastBar
    if not CastBar or not CastBar.Status then return end
    if IsReadableBoolean(notInterruptible) then
        CastBar.LastNotInterruptible = notInterruptible
    end
    CastBar.Status:SetStatusBarColor(FetchCastBarColour(CastBar.LastNotInterruptible))
end

local function ClearPips()
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    for _, pip in ipairs(CastBar.Pips or {}) do
        pip:Hide()
        if pip.SetParent then pip:SetParent(nil) end
    end
    CastBar.Pips = {}
end

local function CreatePips(empoweredStages)
    ClearPips()
    local CastBar = BCDM.CastBar
    if not CastBar or IsSecretValue(empoweredStages) or type(empoweredStages) ~= "table" then return end

    local stageCount = #empoweredStages
    for i = 1, stageCount do
        if IsSecretValue(empoweredStages[i]) or type(empoweredStages[i]) ~= "number" then return end
    end

    local totalWidth = CastBar.Status:GetWidth()
    local cumulativePercentage = 0
    local pipSettings = BCDM.db.profile.CastBar.EmpowerPips
    for i = 1, stageCount - 1 do
        cumulativePercentage = cumulativePercentage + empoweredStages[i]
        local empoweredPip = CastBar.Status:CreateTexture(nil, "OVERLAY")
        empoweredPip:SetColorTexture(pipSettings.Colour[1], pipSettings.Colour[2], pipSettings.Colour[3], pipSettings.Colour[4])
        local xPos = totalWidth * cumulativePercentage
        empoweredPip:SetSize(pipSettings.Width, CastBar.Status:GetHeight() - 2)
        if BCDM.db.profile.CastBar.FillDirection == "LEFT" then
            empoweredPip:SetPoint("RIGHT", CastBar.Status, "RIGHT", -xPos, 0)
        else
            empoweredPip:SetPoint("LEFT", CastBar.Status, "LEFT", xPos, 0)
        end
        CastBar.Pips[#CastBar.Pips + 1] = empoweredPip
        empoweredPip:Show()
    end
end

local function ReadCastingInfo()
    if type(UnitCastingInfo) ~= "function" then return end
    local ok, name, _, texture, _, _, _, _, notInterruptible, _, castBarID = pcall(UnitCastingInfo, "player")
    if not ok then return end
    return name, texture, notInterruptible, castBarID
end

local function ReadChannelInfo()
    if type(UnitChannelInfo) ~= "function" then return end
    local ok, name, _, texture, _, _, _, notInterruptible, _, isEmpowered, _, castBarID = pcall(UnitChannelInfo, "player")
    if not ok then return end
    return name, texture, notInterruptible, isEmpowered, castBarID
end

local function ReadCastDuration(kind)
    local getter
    if kind == "cast" then
        getter = UnitCastingDuration
    elseif kind == "channel" then
        getter = UnitChannelDuration
    elseif kind == "empower" then
        getter = UnitEmpoweredChannelDuration
    end
    if type(getter) ~= "function" then return end
    local ok, duration
    if kind == "empower" then
        ok, duration = pcall(getter, "player", true)
    else
        ok, duration = pcall(getter, "player")
    end
    if ok then return duration end
end

local function IsMissingValue(value)
    return not IsSecretValue(value) and value == nil
end

local function HasValue(value)
    return IsSecretValue(value) or value ~= nil
end

local function GetCastTimerDirection(kind)
    local directions = Enum and Enum.StatusBarTimerDirection
    if not directions then return end
    if kind == "channel" then return directions.RemainingTime end
    return directions.ElapsedTime
end

local function TryMethod(object, method, ...)
    if object and type(object[method]) == "function" then
        pcall(object[method], object, ...)
    end
end

local function CreateCastTimeBinding(fontString)
    if not (C_DurationUtil and type(C_DurationUtil.CreateDurationTextBinding) == "function") then return end
    if not (C_StringUtil and type(C_StringUtil.CreateSecondsFormatter) == "function") then return end

    local ok, binding = pcall(C_DurationUtil.CreateDurationTextBinding)
    if not ok or not binding then return end
    local formatterOK, formatter = pcall(C_StringUtil.CreateSecondsFormatter)
    if not formatterOK or not formatter then return end

    TryMethod(formatter, "SetDesiredUnitCount", 1)
    local secondsInterval = Enum and Enum.SecondsFormatterInterval and Enum.SecondsFormatterInterval.Seconds
    if secondsInterval ~= nil then TryMethod(formatter, "SetMinInterval", secondsInterval) end
    local noAbbreviation = Enum and Enum.SecondsFormatterAbbreviation and Enum.SecondsFormatterAbbreviation.None
    if noAbbreviation ~= nil then TryMethod(formatter, "SetDefaultAbbreviation", noAbbreviation) end
    local truncate = Enum and Enum.SecondsFormatterRounding and Enum.SecondsFormatterRounding.Truncate
    if truncate ~= nil then TryMethod(formatter, "SetRounding", truncate) end
    TryMethod(formatter, "SetMillisecondsThreshold", 5)

    local formatterSet = pcall(binding.SetFormatter, binding, formatter)
    local fontStringSet = pcall(binding.SetFontString, binding, fontString)
    if not formatterSet or not fontStringSet then return end
    TryMethod(binding, "SetUpdateInterval", 0.1)
    TryMethod(binding, "SetExpiredText", "")
    TryMethod(binding, "SetZeroDurationText", "")
    TryMethod(binding, "SetEnabled", false)
    return binding
end

local function DisableCastTimeText()
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    if CastBar.CastTimeBinding then
        TryMethod(CastBar.CastTimeBinding, "SetEnabled", false)
    end
    if CastBar.CastTimeText then CastBar.CastTimeText:SetText("") end
end

local function BindCastTimeText(duration)
    local CastBar = BCDM.CastBar
    if not CastBar or not CastBar.CastTimeBinding then
        if CastBar and CastBar.CastTimeText then CastBar.CastTimeText:SetText("") end
        return false
    end
    local ok = pcall(CastBar.CastTimeBinding.SetDuration, CastBar.CastTimeBinding, duration)
    if not ok then return false end
    ok = pcall(CastBar.CastTimeBinding.SetEnabled, CastBar.CastTimeBinding, true)
    if not ok then return false end
    TryMethod(CastBar.CastTimeBinding, "UpdateFontString")
    return true
end

local function BindCastDuration(kind)
    local CastBar = BCDM.CastBar
    if not CastBar or not CastBar.Status then return false end
    local duration = ReadCastDuration(kind)
    if IsMissingValue(duration) then return false end
    local direction = GetCastTimerDirection(kind)
    if direction == nil then return false end

    local ok = pcall(CastBar.Status.SetTimerDuration, CastBar.Status, duration, nil, direction)
    if not ok then return false end
    TryMethod(CastBar.Status, "SetToTargetValue")
    BindCastTimeText(duration)
    CastBar.HasDuration = true
    CastBar.DurationKind = kind
    return true
end

local function ClearCastVisual()
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    DisableCastTimeText()
    if CastBar.Status and CastBar.Status.SetValue then
        pcall(CastBar.Status.SetValue, CastBar.Status, 0)
    end
    if CastBar.SetScript then CastBar:SetScript("OnUpdate", nil) end
    ClearPips()
    if CastBar.SpellNameText then CastBar.SpellNameText:SetText("") end
    if CastBar.Icon then CastBar.Icon:SetTexture(nil) end
    CastBar.HasDuration = false
    CastBar.DurationKind = nil
    CastBar:Hide()
end

local function StopCastBar()
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    CastBar.CastActive = false
    CastBar.ActiveKind = nil
    CastBar.ActiveCastID = nil
    CastBar.EmpoweredStages = nil
    ClearCastVisual()
end

local function SetCastIcon(texture)
    local CastBar = BCDM.CastBar
    if not CastBar or not CastBar.Icon then return end
    if IsSecretValue(texture) then
        CastBar.Icon:SetTexture(texture)
    elseif type(texture) == "number" or type(texture) == "string" then
        CastBar.Icon:SetTexture(texture)
    else
        CastBar.Icon:SetTexture(nil)
    end
end

local function StartCast(kind, eventCastBarID)
    local CastBar = BCDM.CastBar
    if not CastBar then return false end

    StopCastBar()
    local name, texture, notInterruptible, infoCastBarID
    local isEmpowered
    if kind == "cast" then
        name, texture, notInterruptible, infoCastBarID = ReadCastingInfo()
    else
        name, texture, notInterruptible, isEmpowered, infoCastBarID = ReadChannelInfo()
        if kind == "empower" and isEmpowered ~= true then return false end
        if kind == "channel" and isEmpowered == true then return false end
    end
    if not HasValue(name) then return false end

    CastBar.CastActive = true
    CastBar.ActiveKind = kind
    if IsReadableCastBarID(infoCastBarID) then
        CastBar.ActiveCastID = infoCastBarID
    elseif IsReadableCastBarID(eventCastBarID) then
        CastBar.ActiveCastID = eventCastBarID
    else
        CastBar.ActiveCastID = nil
    end
    CastBar.EmpoweredStages = nil
    CastBar.SpellNameText:SetText(GetDisplayCastText(name, BCDM.db.profile.CastBar.Text.SpellName.MaxCharacters))
    SetCastIcon(texture)
    UpdateCastBarColour(notInterruptible)

    if kind == "empower" then
        local ok, stages = pcall(UnitEmpoweredStagePercentages, "player")
        if ok and not IsSecretValue(stages) and type(stages) == "table" then
            CastBar.EmpoweredStages = stages
        end
        CreatePips(CastBar.EmpoweredStages)
    end

    if not BindCastDuration(kind) then
        return false
    end
    CastBar:Show()
    return true
end

local function RebindActiveDuration(kind)
    local CastBar = BCDM.CastBar
    if not CastBar or not CastBar.CastActive or CastBar.ActiveKind ~= kind then return false end
    local bound = BindCastDuration(kind)
    if CastBar.HasDuration then CastBar:Show() end
    return bound
end

local function GetCurrentCastKind()
    local name = ReadCastingInfo()
    if HasValue(name) then return "cast" end
    local channelName, _, _, isEmpowered = ReadChannelInfo()
    if HasValue(channelName) then return isEmpowered == true and "empower" or "channel" end
end

local function EventCastBarID(event, payload4, payload5, payload6)
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        return payload5
    end
    if event == "UNIT_SPELLCAST_EMPOWER_STOP" then return payload6 end
    return payload4
end

local function MatchesActiveCast(CastBar, eventCastBarID)
    return IsReadableCastBarID(eventCastBarID)
        and IsReadableCastBarID(CastBar.ActiveCastID)
        and eventCastBarID == CastBar.ActiveCastID
end

local function UpdateCastBarValues(self, event, unit, payload2, payload3, payload4, payload5, payload6)
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    if unit and unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        UpdateCastBarColour(event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
        return
    end

    if event == "UNIT_SPELLCAST_START" then
        StartCast("cast", EventCastBarID(event, payload4, payload5, payload6))
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        StartCast("channel", EventCastBarID(event, payload4, payload5, payload6))
    elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
        StartCast("empower", EventCastBarID(event, payload4, payload5, payload6))
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        RebindActiveDuration("cast")
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        RebindActiveDuration("channel")
    elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        RebindActiveDuration("empower")
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if CastBar.ActiveKind == "cast" and MatchesActiveCast(CastBar, EventCastBarID(event, payload4, payload5, payload6)) then
            StopCastBar()
        end
    elseif (event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP")
        and (CastBar.ActiveKind == "channel" or CastBar.ActiveKind == "empower") then
        StopCastBar()
    end
end

local function SetNativePlayerCastBarShown(shown)
    local nativeCastBar = _G.PlayerCastingBarFrame
    if nativeCastBar and type(nativeCastBar.SetAndUpdateShowCastbar) == "function" then
        nativeCastBar:SetAndUpdateShowCastbar(shown)
    end
end

local function CancelCastBarWidthTimer(CastBar)
    CastBar.WidthGeneration = (CastBar.WidthGeneration or 0) + 1
    if CastBar.WidthTimer and type(CastBar.WidthTimer.Cancel) == "function" then
        pcall(CastBar.WidthTimer.Cancel, CastBar.WidthTimer)
    end
    CastBar.WidthTimer = nil
end

local function ScheduleCastBarWidth(delay)
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    CancelCastBarWidthTimer(CastBar)

    local CastBarDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.CastBar
    if not CastBarDB or CastBarDB.Enabled ~= true or not CastBarDB.MatchWidthOfAnchor then return end

    local generation = CastBar.WidthGeneration
    local function ApplyWidth()
        if CastBar.WidthGeneration ~= generation then return end
        CastBar.WidthTimer = nil
        local currentDB = BCDM.db and BCDM.db.profile and BCDM.db.profile.CastBar
        if not currentDB or currentDB.Enabled ~= true or not currentDB.MatchWidthOfAnchor then return end
        local anchorFrame = BCDM:ResolveAnchorParent(currentDB.Layout[2])
        if not anchorFrame or type(anchorFrame.GetWidth) ~= "function" then return end
        local ok, anchorWidth = pcall(anchorFrame.GetWidth, anchorFrame)
        if ok and type(anchorWidth) == "number" then CastBar:SetWidth(anchorWidth) end
    end

    if C_Timer and type(C_Timer.NewTimer) == "function" then
        local ok, timer = pcall(C_Timer.NewTimer, delay, ApplyWidth)
        if ok then CastBar.WidthTimer = timer end
    end
end

local function SetHooks()
    if BCDM.CastBarHooksSet then return end
    if not (EditModeManagerFrame and type(EditModeManagerFrame.EnterEditMode) == "function"
        and type(EditModeManagerFrame.ExitEditMode) == "function" and type(hooksecurefunc) == "function") then return end
    BCDM.CastBarHooksSet = true
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if InCombatLockdown and InCombatLockdown() then return end
        BCDM:UpdateCastBarWidth()
    end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        if InCombatLockdown and InCombatLockdown() then return end
        BCDM:UpdateCastBarWidth()
    end)
end

local function SetFontStyle(fontString, settings, generalDB)
    fontString:SetFont(BCDM.Media.Font, settings.FontSize, generalDB.Fonts.FontFlag)
    fontString:SetTextColor(settings.Colour[1], settings.Colour[2], settings.Colour[3], 1)
    fontString:ClearAllPoints()
    fontString:SetPoint(settings.Layout[1], BCDM.CastBar.Status, settings.Layout[2], settings.Layout[3], settings.Layout[4])
    if generalDB.Fonts.Shadow.Enabled then
        fontString:SetShadowColor(generalDB.Fonts.Shadow.Colour[1], generalDB.Fonts.Shadow.Colour[2], generalDB.Fonts.Shadow.Colour[3], generalDB.Fonts.Shadow.Colour[4])
        fontString:SetShadowOffset(generalDB.Fonts.Shadow.OffsetX, generalDB.Fonts.Shadow.OffsetY)
    else
        fontString:SetShadowColor(0, 0, 0, 0)
        fontString:SetShadowOffset(0, 0)
    end
end

local function ApplyCastBarAppearance()
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    local GeneralDB = BCDM.db.profile.General
    local CastBarDB = BCDM.db.profile.CastBar
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize

    CastBar:SetBackdrop(BCDM.BACKDROP)
    if borderSize > 0 then
        CastBar:SetBackdropBorderColor(0, 0, 0, 1)
    else
        CastBar:SetBackdropBorderColor(0, 0, 0, 0)
    end
    CastBar:SetBackdropColor(CastBarDB.BackgroundColour[1], CastBarDB.BackgroundColour[2], CastBarDB.BackgroundColour[3], CastBarDB.BackgroundColour[4])
    CastBar:SetSize(CastBarDB.Width, CastBarDB.Height)
    CastBar:ClearAllPoints()
    CastBar:SetPoint(CastBarDB.Layout[1], BCDM:ResolveAnchorParent(CastBarDB.Layout[2]), CastBarDB.Layout[3], CastBarDB.Layout[4], CastBarDB.Layout[5])
    CastBar:SetFrameStrata(CastBarDB.FrameStrata or "LOW")

    CastBar.Status:SetStatusBarColor(FetchCastBarColour(CastBar.LastNotInterruptible))
    CastBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    BCDM:ApplyStatusBarDirection(CastBar.Status, CastBarDB.FillDirection)

    CastBar.Icon:SetSize(CastBarDB.Height, CastBarDB.Height)
    local iconZoom = BCDM.db.profile.CooldownManager.General.IconZoom * 0.5
    CastBar.Icon:SetTexCoord(iconZoom, 1 - iconZoom, iconZoom, 1 - iconZoom)
    CastBar.Icon:ClearAllPoints()
    CastBar.Status:ClearAllPoints()
    if CastBarDB.Icon.Enabled == false then
        CastBar.Status:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
    elseif CastBarDB.Icon.Layout == "LEFT" then
        CastBar.Icon:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Icon:SetPoint("BOTTOMLEFT", CastBar, "BOTTOMLEFT", borderSize, borderSize)
        CastBar.Status:SetPoint("TOPLEFT", CastBar.Icon, "TOPRIGHT", 0, 0)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
    elseif CastBarDB.Icon.Layout == "RIGHT" then
        CastBar.Icon:SetPoint("TOPRIGHT", CastBar, "TOPRIGHT", -borderSize, -borderSize)
        CastBar.Icon:SetPoint("BOTTOMRIGHT", CastBar, "BOTTOMRIGHT", -borderSize, borderSize)
        CastBar.Status:SetPoint("TOPLEFT", CastBar, "TOPLEFT", borderSize, -borderSize)
        CastBar.Status:SetPoint("BOTTOMRIGHT", CastBar.Icon, "BOTTOMLEFT", 0, 0)
    end

    SetFontStyle(CastBar.SpellNameText, CastBarDB.Text.SpellName, GeneralDB)
    SetFontStyle(CastBar.CastTimeText, CastBarDB.Text.CastTime, GeneralDB)
    if CastBarDB.Icon.Enabled then CastBar.Icon:Show() else CastBar.Icon:Hide() end

    if CastBar.CastActive and CastBar.ActiveKind == "empower" then
        CreatePips(CastBar.EmpoweredStages)
    elseif not CastBar.CastActive then
        ClearPips()
    end
end

local function RegisterCastBarEvents(CastBar)
    CastBar:UnregisterAllEvents()
    for _, event in ipairs({
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    }) do
        CastBar:RegisterUnitEvent(event, "player")
    end
    CastBar:SetScript("OnEvent", UpdateCastBarValues)
end

local function EnableCastBar(CastBar, syncCurrentCast)
    RegisterCastBarEvents(CastBar)
    CastBar.EventsEnabled = true
    SetNativePlayerCastBarShown(false)
    if syncCurrentCast then
        local kind = GetCurrentCastKind()
        if kind then StartCast(kind) else StopCastBar() end
    elseif CastBar.CastActive then
        RebindActiveDuration(CastBar.ActiveKind)
    end
end

local function DisableCastBar(CastBar)
    CancelCastBarWidthTimer(CastBar)
    CastBar.EventsEnabled = false
    CastBar:UnregisterAllEvents()
    CastBar:SetScript("OnEvent", nil)
    StopCastBar()
    SetNativePlayerCastBarShown(true)
end

function BCDM:CreateCastBar()
    local CastBarDB = BCDM.db.profile.CastBar
    SetHooks()

    local CastBar = _G.BCDM_CastBar or CreateFrame("Frame", "BCDM_CastBar", UIParent, "BackdropTemplate")
    CastBar.Pips = CastBar.Pips or {}
    CastBar.CastActive = false
    CastBar.HasDuration = false
    CastBar.EnabledState = false
    CastBar:Hide()

    CastBar.Icon = CastBar.Icon or CastBar:CreateTexture(nil, "OVERLAY")
    CastBar.Status = CastBar.Status or CreateFrame("StatusBar", nil, CastBar)
    CastBar.Status:SetStatusBarTexture(BCDM.Media.Foreground)
    CastBar.Status:SetMinMaxValues(0, 1)
    CastBar.Status:SetValue(0)

    CastBar.SpellNameText = CastBar.SpellNameText or CastBar.Status:CreateFontString(nil, "OVERLAY")
    CastBar.CastTimeText = CastBar.CastTimeText or CastBar.Status:CreateFontString(nil, "OVERLAY")
    CastBar.CastTimeBinding = CastBar.CastTimeBinding or CreateCastTimeBinding(CastBar.CastTimeText)
    CastBar.SpellNameText:SetText("")
    CastBar.CastTimeText:SetText("")

    BCDM.CastBar = CastBar
    ApplyCastBarAppearance()
    BCDM:RegisterOwnedFrameVisibility(CastBar, function() return BCDM.db.profile.CastBar end, function(frame)
        if frame.CastActive and frame.HasDuration then frame:Show() end
    end)

    if CastBarDB.Enabled then
        CastBar.EnabledState = true
        EnableCastBar(CastBar, true)
    else
        DisableCastBar(CastBar)
    end
    ScheduleCastBarWidth(0.1)
end

function BCDM:UpdateCastBar()
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    local CastBarDB = BCDM.db.profile.CastBar
    local wasEnabled = CastBar.EnabledState == true

    ApplyCastBarAppearance()
    ScheduleCastBarWidth(0.1)

    if CastBarDB.Enabled then
        CastBar.EnabledState = true
        EnableCastBar(CastBar, not wasEnabled)
        if CastBar.CastActive and CastBar.ActiveKind == "empower" then
            CreatePips(CastBar.EmpoweredStages)
        end
    else
        CastBar.EnabledState = false
        DisableCastBar(CastBar)
    end
    if BCDM.CAST_BAR_TEST_MODE then BCDM:CreateTestCastBar() end
end

function BCDM:CreateTestCastBar()
    local CastBar = BCDM.CastBar
    if not CastBar then return end
    if not BCDM.CAST_BAR_TEST_MODE then
        CastBar:Hide()
        return
    end

    DisableCastTimeText()
    ApplyCastBarAppearance()
    local CastBarDB = BCDM.db.profile.CastBar
    local testState = BCDM.CAST_BAR_TEST_STATE or "NORMAL"
    CastBar.SpellNameText:SetText(string.sub("Ethereal Portal", 1, CastBarDB.Text.SpellName.MaxCharacters))
    CastBar.Icon:SetTexture("Interface\\Icons\\ability_mage_netherwindpresence")
    CastBar.Status:SetMinMaxValues(0, 10)
    CastBar.Status:SetValue(5)
    UpdateCastBarColour(testState == "NON_INTERRUPTIBLE")
    CreatePips(testState == "EMPOWERED" and { 0.25, 0.35, 0.4 } or {})
    CastBar.CastTimeText:SetText("5.0")
    if CastBarDB.Enabled then CastBar:Show() else CastBar:Hide() end
end

function BCDM:UpdateCastBarWidth()
    if self.CastBar then ScheduleCastBarWidth(0.5) end
end

BCDM._CastBarTest = {
    GetDisplayCastText = GetDisplayCastText,
    CreatePips = CreatePips,
    BindCastDuration = BindCastDuration,
    HandleEvent = UpdateCastBarValues,
    StopCastBar = StopCastBar,
    DisableCastBar = DisableCastBar,
    ScheduleCastBarWidth = ScheduleCastBarWidth,
}
