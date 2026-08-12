local _, BCDM = ...
local LibCustomGlow = LibStub("LibCustomGlow-1.0")

local activeGlows = setmetatable({}, { __mode = "k" })
local glowStates = setmetatable({}, { __mode = "k" })
local pendingNativeStarts = setmetatable({}, { __mode = "k" })
local activeNativeAlerts = setmetatable({}, { __mode = "k" })
local suppressedNativeAlerts = setmetatable({}, { __mode = "k" })
local hookedCooldownViewers = setmetatable({}, { __mode = "k" })
local reportedGlowErrors = {}
local customGlowHooksSet = false
local glowPreparationFrame

local function NormalizeValue(value, defaultValue)
    if value == nil then
        return defaultValue
    end
    return value
end

local function NormalizeColor(color, fallback)
    if type(color) ~= "table" then
        color = fallback or { 1, 1, 1, 1 }
    end
    local fallbackColor = fallback or { 1, 1, 1, 1 }
    return {
        NormalizeValue(color[1], fallbackColor[1]),
        NormalizeValue(color[2], fallbackColor[2]),
        NormalizeValue(color[3], fallbackColor[3]),
        NormalizeValue(color[4], fallbackColor[4]),
    }
end

local function NormalizeGlowType(glowType)
    if not glowType then
        return nil
    end
    local normalized = tostring(glowType):lower()
    if normalized == "pixel" or normalized == "pixelglow" or normalized == "pix" or normalized == "pixel_glow" then
        return "Pixel"
    end
    if normalized == "autocast" or normalized == "autocastglow" or normalized == "autocast_glow" then
        return "Autocast"
    end
    if normalized == "proc" or normalized == "procglow" or normalized == "proc_glow" then
        return "Proc"
    end
    if normalized == "button" or normalized == "buttonglow" or normalized == "actionbuttonglow" or normalized == "action_button_glow" then
        return "Button"
    end
    return nil
end

function BCDM:NormalizeGlowSettings()
    if not BCDM.db or not BCDM.db.profile or not BCDM.db.profile.CooldownManager then
        return nil
    end

    local general = BCDM.db.profile.CooldownManager.General
    general.Glow = general.Glow or {}

    local glow = general.Glow

    local legacyType = glow.GlowType
    if glow.Type == nil and legacyType ~= nil then
        glow.Type = NormalizeGlowType(legacyType)
    end

    glow.Enabled = NormalizeValue(glow.Enabled, true)
    glow.Type = glow.Type or "Pixel"

    local legacyColor = glow.Colour
    glow.Pixel = glow.Pixel or {}
    glow.Pixel.Color = NormalizeColor(glow.Pixel.Color or legacyColor, { 1, 1, 1, 1 })
    glow.Pixel.Lines = NormalizeValue(glow.Pixel.Lines or glow.Lines, 5)
    glow.Pixel.Frequency = NormalizeValue(glow.Pixel.Frequency or glow.Frequency, 0.25)
    glow.Pixel.Length = NormalizeValue(glow.Pixel.Length, 2)
    glow.Pixel.Thickness = NormalizeValue(glow.Pixel.Thickness or glow.Thickness, 1)
    glow.Pixel.XOffset = NormalizeValue(glow.Pixel.XOffset or glow.XOffset, -1)
    glow.Pixel.YOffset = NormalizeValue(glow.Pixel.YOffset or glow.YOffset, -1)
    glow.Pixel.Border = NormalizeValue(glow.Pixel.Border, false)

    glow.Autocast = glow.Autocast or {}
    glow.Autocast.Color = NormalizeColor(glow.Autocast.Color or legacyColor, { 1, 1, 1, 1 })
    glow.Autocast.Particles = NormalizeValue(glow.Autocast.Particles or glow.Particles, 10)
    glow.Autocast.Frequency = NormalizeValue(glow.Autocast.Frequency or glow.Frequency, 0.25)
    glow.Autocast.Scale = NormalizeValue(glow.Autocast.Scale or glow.Scale, 1)
    glow.Autocast.XOffset = NormalizeValue(glow.Autocast.XOffset or glow.XOffset, -1)
    glow.Autocast.YOffset = NormalizeValue(glow.Autocast.YOffset or glow.YOffset, -1)

    glow.Proc = glow.Proc or {}
    glow.Proc.Color = NormalizeColor(glow.Proc.Color or legacyColor, { 1, 1, 1, 1 })
    glow.Proc.StartAnim = NormalizeValue(glow.Proc.StartAnim, true)
    glow.Proc.Duration = NormalizeValue(glow.Proc.Duration, 1)
    glow.Proc.XOffset = NormalizeValue(glow.Proc.XOffset, 0)
    glow.Proc.YOffset = NormalizeValue(glow.Proc.YOffset, 0)

    glow.Button = glow.Button or {}
    glow.Button.Color = NormalizeColor(glow.Button.Color or legacyColor, { 1, 1, 1, 1 })
    glow.Button.Frequency = NormalizeValue(glow.Button.Frequency, 0.125)

    return glow
end

function BCDM:GetCustomGlowSettings()
    return self:NormalizeGlowSettings()
end

local function GetCooldownViewerChild(frame)
    if not frame then return nil end
    local current = frame
    while current do
        local okMethod, getParent = pcall(function() return current.GetParent end)
        if not okMethod or type(getParent) ~= "function" then return nil end
        local okParent, parent = pcall(getParent, current)
        if not okParent then return nil end
        if not parent then return nil end

        for _, viewerName in ipairs(BCDM.CooldownManagerViewers or {}) do
            if parent == _G[viewerName] then return current end
        end

        current = parent
    end

    return nil
end

local function GetGlowTarget(frame)
    if not frame then return nil end
    local target = GetCooldownViewerChild(frame)
    if not target or not BCDM:IsCustomizableCooldownViewerItem(target) then return nil end
    return target
end

local function ReportGlowError(action, glowType, message)
    local key = action .. ":" .. tostring(glowType)
    if reportedGlowErrors[key] then return end
    reportedGlowErrors[key] = true
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        pcall(handler, "BetterCooldownManager custom glow " .. action .. " failed: " .. tostring(message))
    end
end

local function RunGlowCall(action, glowType, callback)
    local ok, message = pcall(callback)
    if not ok then ReportGlowError(action, glowType, message) end
    return ok
end

local function StopGlowOnOverlay(overlay, glowType)
    if not overlay or not glowType then return true end
    return RunGlowCall("stop", glowType, function()
        overlay:Hide()
        if glowType == "Pixel" then
            LibCustomGlow.PixelGlow_Stop(overlay, "BCDM")
        elseif glowType == "Autocast" then
            LibCustomGlow.AutoCastGlow_Stop(overlay, "BCDM")
        elseif glowType == "Proc" then
            LibCustomGlow.ProcGlow_Stop(overlay, "BCDM")
        elseif glowType == "Button" then
            LibCustomGlow.ButtonGlow_Stop(overlay)
        end
    end)
end

local function CancelNativeStart(frame)
    local timer = pendingNativeStarts[frame]
    if timer and timer.Cancel then timer:Cancel() end
    pendingNativeStarts[frame] = nil
end

local function GetGlowState(frame)
    local state = glowStates[frame]
    if state then return state end
    state = {}
    glowStates[frame] = state
    return state
end

local function RefreshOverlayGeometry(frame, overlay)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(frame)
    if frame.GetFrameLevel and overlay.SetFrameLevel then
        local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
        if ok and type(frameLevel) == "number" then overlay:SetFrameLevel(frameLevel + 1) end
    end
end

local function GetGlowOverlay(frame)
    local state = GetGlowState(frame)
    if not state.overlay then
        if GetCooldownViewerChild(frame) and InCombatLockdown and InCombatLockdown() then return nil end
        local ok, overlay = pcall(CreateFrame, "Frame", nil, frame)
        if not ok or not overlay then
            ReportGlowError("overlay", "Frame", overlay)
            return nil
        end
        if overlay.EnableMouse then overlay:EnableMouse(false) end
        overlay:Hide()
        state.overlay = overlay
    end
    RefreshOverlayGeometry(frame, state.overlay)
    return state.overlay
end

local function RestoreNativeAlertAlpha(frame)
    local alertFrame = suppressedNativeAlerts[frame]
    suppressedNativeAlerts[frame] = nil
    if alertFrame and alertFrame.SetAlpha then pcall(alertFrame.SetAlpha, alertFrame, 1) end
end

local function SuppressNativeAlertAlpha(frame)
    local okAlert, alertFrame = pcall(function() return frame and frame.SpellActivationAlert end)
    if not okAlert then return end
    if not alertFrame or not alertFrame.SetAlpha then return end
    local ok = pcall(alertFrame.SetAlpha, alertFrame, 0)
    if ok then suppressedNativeAlerts[frame] = alertFrame end
end

function BCDM:StartCustomGlow(frame, forceRefresh)
    if not frame then return false end
    local viewerItem = GetCooldownViewerChild(frame)
    if viewerItem and not self:IsCustomizableCooldownViewerItem(viewerItem) then
        self:StopCustomGlow(frame)
        RestoreNativeAlertAlpha(frame)
        return false
    end

    local glow = self:GetCustomGlowSettings()
    if not glow or not glow.Enabled then
        self:StopCustomGlow(frame)
        RestoreNativeAlertAlpha(frame)
        return false
    end

    local glowType = glow.Type or "Pixel"
    local state = GetGlowState(frame)
    if state.glowType == glowType and not forceRefresh then return true end
    if state.glowType then StopGlowOnOverlay(state.overlay, state.glowType) end

    local overlay = GetGlowOverlay(frame)
    if not overlay then return false end
    overlay:Show()
    local started = RunGlowCall("start", glowType, function()
        if glowType == "Pixel" then
            local settings = glow.Pixel
            LibCustomGlow.PixelGlow_Start(overlay, settings.Color, settings.Lines, settings.Frequency, settings.Length, settings.Thickness, settings.XOffset, settings.YOffset, settings.Border, "BCDM", 1)
        elseif glowType == "Autocast" then
            local settings = glow.Autocast
            LibCustomGlow.AutoCastGlow_Start(overlay, settings.Color, settings.Particles, settings.Frequency, settings.Scale, settings.XOffset, settings.YOffset, "BCDM", 1)
        elseif glowType == "Proc" then
            local settings = glow.Proc
            LibCustomGlow.ProcGlow_Start(overlay, {
                key = "BCDM",
                frameLevel = 1,
                color = settings.Color,
                startAnim = settings.StartAnim,
                duration = settings.Duration,
                xOffset = settings.XOffset,
                yOffset = settings.YOffset,
            })
        elseif glowType == "Button" then
            local settings = glow.Button
            LibCustomGlow.ButtonGlow_Start(overlay, settings.Color, settings.Frequency, 1)
        else
            error("unsupported glow type " .. tostring(glowType))
        end
    end)
    if not started then
        overlay:Hide()
        state.glowType = nil
        activeGlows[frame] = nil
        RestoreNativeAlertAlpha(frame)
        return false
    end

    state.glowType = glowType
    activeGlows[frame] = true
    return true
end

function BCDM:StopCustomGlow(frame)
    if not frame then return end
    local state = glowStates[frame]
    if state and state.glowType then
        StopGlowOnOverlay(state.overlay, state.glowType)
        state.glowType = nil
    end
    activeGlows[frame] = nil
end

function BCDM:StopAllCustomGlows()
    local targets = {}
    for frame in pairs(activeGlows) do targets[#targets + 1] = frame end
    for _, frame in ipairs(targets) do self:StopCustomGlow(frame) end
end

local function HasNativeAlert(frame)
    local manager = ActionButtonSpellAlertManager
    if not manager or not manager.HasAlert then return false end
    local ok, hasAlert = pcall(manager.HasAlert, manager, frame)
    return ok and not BCDM:IsSecretValue(hasAlert) and hasAlert == true
end

local function RestoreNativeAlert(frame)
    CancelNativeStart(frame)
    BCDM:StopCustomGlow(frame)
    activeNativeAlerts[frame] = nil
    RestoreNativeAlertAlpha(frame)
end

local function QueueNativeGlow(frame)
    CancelNativeStart(frame)
    local timer
    timer = C_Timer.NewTimer(0, function()
        if pendingNativeStarts[frame] ~= timer then return end
        pendingNativeStarts[frame] = nil
        if not activeNativeAlerts[frame] or not HasNativeAlert(frame) then
            activeNativeAlerts[frame] = nil
            BCDM:StopCustomGlow(frame)
            return
        end
        local glow = BCDM:GetCustomGlowSettings()
        if not glow or not glow.Enabled then
            RestoreNativeAlert(frame)
            return
        end
        if BCDM:StartCustomGlow(frame) then SuppressNativeAlertAlpha(frame) end
    end)
    pendingNativeStarts[frame] = timer
end

local function AdoptActiveNativeAlerts()
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers or {}) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if BCDM:IsCustomizableCooldownViewerItem(frame) and HasNativeAlert(frame) then
                    activeNativeAlerts[frame] = true
                    QueueNativeGlow(frame)
                end
            end
        end
    end
end

local function PrepareCooldownViewerGlowTarget(frame)
    if not frame or (InCombatLockdown and InCombatLockdown()) then return end
    if not BCDM:IsCustomizableCooldownViewerItem(frame) then return end
    GetGlowOverlay(frame)
end

local function PrepareCooldownViewerGlowTargets()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers or {}) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for frame in viewer.itemFramePool:EnumerateActive() do
                PrepareCooldownViewerGlowTarget(frame)
            end
        end
        if viewer and viewer.RefreshData and not hookedCooldownViewers[viewer] then
            hookedCooldownViewers[viewer] = true
            hooksecurefunc(viewer, "RefreshData", function()
                if InCombatLockdown and InCombatLockdown() then return end
                for frame in viewer.itemFramePool:EnumerateActive() do
                    PrepareCooldownViewerGlowTarget(frame)
                end
            end)
        end
    end
end

local function EnsureGlowPreparationFrame()
    if glowPreparationFrame then return end
    glowPreparationFrame = CreateFrame("Frame")
    glowPreparationFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    glowPreparationFrame:SetScript("OnEvent", function()
        PrepareCooldownViewerGlowTargets()
        AdoptActiveNativeAlerts()
    end)
end

function BCDM:RefreshCustomGlows()
    self:SetupCustomGlows()
    local glow = self:GetCustomGlowSettings()
    if not glow or not glow.Enabled then
        local nativeTargets = {}
        for frame in pairs(activeNativeAlerts) do nativeTargets[#nativeTargets + 1] = frame end
        self:StopAllCustomGlows()
        for _, frame in ipairs(nativeTargets) do RestoreNativeAlert(frame) end
        return
    end

    local targets = {}
    for frame in pairs(activeGlows) do targets[#targets + 1] = frame end
    for _, frame in ipairs(targets) do self:StartCustomGlow(frame, true) end
    AdoptActiveNativeAlerts()
end

function BCDM:SetupCustomGlows()
    if customGlowHooksSet then return true end
    if not ActionButtonSpellAlertManager then return false end
    customGlowHooksSet = true
    EnsureGlowPreparationFrame()
    PrepareCooldownViewerGlowTargets()

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, frame)
        local activeGlowTarget = GetGlowTarget(frame)
        if not activeGlowTarget then return end

        local glow = BCDM:GetCustomGlowSettings()
        if not glow or not glow.Enabled then return end
        activeNativeAlerts[activeGlowTarget] = true
        QueueNativeGlow(activeGlowTarget)
    end)

    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, frame)
        local activeGlowTarget = GetCooldownViewerChild(frame)
        if not activeGlowTarget then return end
        CancelNativeStart(activeGlowTarget)
        activeNativeAlerts[activeGlowTarget] = nil
        BCDM:StopCustomGlow(activeGlowTarget)
        RestoreNativeAlertAlpha(activeGlowTarget)
    end)

    return true
end
