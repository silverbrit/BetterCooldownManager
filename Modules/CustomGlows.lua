local _, BCDM = ...
local LibCustomGlow = LibStub("LibCustomGlow-1.0")

local activeGlows = setmetatable({}, { __mode = "k" })
local glowStates = setmetatable({}, { __mode = "k" })
local activeNativeAlerts = setmetatable({}, { __mode = "k" })
local suppressedNativeAlerts = setmetatable({}, { __mode = "k" })
local hookedCooldownViewers = setmetatable({}, { __mode = "k" })
local hookedAlertManagers = setmetatable({}, { __mode = "k" })
local hookedCooldownViewerPools = setmetatable({}, { __mode = "k" })
local knownPoolFrames = setmetatable({}, { __mode = "k" })
local activePoolFrames = setmetatable({}, { __mode = "k" })
local cooldownViewerTargets = setmetatable({}, { __mode = "k" })
local reportedGlowErrors = {}
local reconcileInProgress = false
local ReconcileCooldownViewerGlows
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

local function IsColor(color, expected)
    return type(color) == "table" and color[1] == expected[1] and color[2] == expected[2]
        and color[3] == expected[3] and color[4] == expected[4]
end

local LEGACY_BUTTON_COLOR = { 1, 1, 1, 1 }
local DEFAULT_BUTTON_COLOR = { 0.95, 0.95, 0, 0.9 }

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

    local legacyType = rawget(glow, "GlowType")
    local normalizedLegacyType = NormalizeGlowType(legacyType)
    if normalizedLegacyType then
        glow.Type = normalizedLegacyType
        glow.GlowType = nil
    end

    glow.Enabled = NormalizeValue(glow.Enabled, true)
    glow.Type = glow.Type or "Button"

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

    local storedButton = rawget(glow, "Button")
    glow.Button = glow.Button or {}
    local storedButtonColor = type(storedButton) == "table" and rawget(storedButton, "Color")
    local storedUseColor = type(storedButton) == "table" and rawget(storedButton, "UseColor")
    local legacyColour = rawget(glow, "Colour")
    local hasLegacyCustomColor = storedButtonColor ~= nil
        and not IsColor(storedButtonColor, LEGACY_BUTTON_COLOR)
        and not IsColor(storedButtonColor, DEFAULT_BUTTON_COLOR)
    if type(legacyColour) == "table"
        and not IsColor(legacyColour, LEGACY_BUTTON_COLOR)
        and not IsColor(legacyColour, DEFAULT_BUTTON_COLOR) then
        hasLegacyCustomColor = true
    end
    local hasLegacyGlowSettings = legacyType ~= nil or rawget(glow, "Colour") ~= nil
    if hasLegacyCustomColor and (storedUseColor == nil or hasLegacyGlowSettings) then
        glow.Button.UseColor = true
    end
    glow.Button.Color = NormalizeColor(glow.Button.Color or legacyColor, DEFAULT_BUTTON_COLOR)
    glow.Button.UseColor = NormalizeValue(glow.Button.UseColor, false)
    glow.Button.Frequency = NormalizeValue(glow.Button.Frequency, 0.3)

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
    if not glowType then return true end
    if not overlay then
        ReportGlowError("stop", glowType, "missing glow overlay")
        return false
    end
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

local function GetGlowState(frame)
    local state = glowStates[frame]
    if state then return state end
    state = {}
    glowStates[frame] = state
    return state
end

local function ReleaseGlowRenderer(frame, state)
    if not state or not state.glowType then
        activeGlows[frame] = nil
        return true
    end

    if not StopGlowOnOverlay(state.overlay, state.glowType) then
        state.cleanupPending = true
        state.rendererActive = false
        activeGlows[frame] = true
        return false
    end

    state.glowType = nil
    state.rendererActive = false
    state.cleanupPending = nil
    state.geometry = nil
    activeGlows[frame] = nil
    return true
end

local GLOW_GEOMETRY_FIELDS = { "width", "height", "frameLevel", "frameStrata" }

local function ReadGlowGeometry(frame)
    local geometry = {}
    local okSize, width, height = pcall(function()
        return frame:GetSize()
    end)
    if okSize and type(width) == "number" and type(height) == "number"
        and not BCDM:IsSecretValue(width) and not BCDM:IsSecretValue(height) then
        geometry.width, geometry.height = width, height
    end

    local okLevel, frameLevel = pcall(function()
        return frame:GetFrameLevel()
    end)
    if okLevel and type(frameLevel) == "number" and not BCDM:IsSecretValue(frameLevel) then
        geometry.frameLevel = frameLevel
    end

    local okStrata, frameStrata = pcall(function()
        return frame:GetFrameStrata()
    end)
    if okStrata and type(frameStrata) == "string" and not BCDM:IsSecretValue(frameStrata) then
        geometry.frameStrata = frameStrata
    end

    return geometry
end

local function MergeGlowGeometry(previous, current)
    local merged = {}
    for _, field in ipairs(GLOW_GEOMETRY_FIELDS) do
        merged[field] = current[field] ~= nil and current[field] or previous and previous[field]
    end
    return merged
end

local function GlowGeometryChanged(previous, current)
    if not previous then return false end
    for _, field in ipairs(GLOW_GEOMETRY_FIELDS) do
        if previous[field] ~= nil and current[field] ~= nil and previous[field] ~= current[field] then
            return true
        end
    end
    return false
end

local function GetGlowCooldown(frame)
    local okCooldown, cooldown = pcall(function()
        return frame and (frame.Cooldown or frame.cooldown)
    end)
    if not okCooldown or not cooldown or BCDM:IsSecretValue(cooldown) then return nil end

    local okMethods, isShown, getDuration = pcall(function()
        return cooldown.IsShown, cooldown.GetCooldownDuration
    end)
    if not okMethods or type(isShown) ~= "function" or type(getDuration) ~= "function" then return nil end

    local okForbiddenMethod, isForbidden = pcall(function() return cooldown.IsForbidden end)
    if okForbiddenMethod and type(isForbidden) == "function" then
        local okForbidden, forbidden = pcall(isForbidden, cooldown)
        if not okForbidden or BCDM:IsSecretValue(forbidden) or forbidden == true then return nil end
    end

    return cooldown
end

local function RefreshOverlayGeometry(frame, overlay)
    local geometry = ReadGlowGeometry(frame)
    local ok = pcall(function() overlay:SetAllPoints(frame) end)
    if not ok then return false, geometry end

    if geometry.frameLevel then
        local okLevel = pcall(function() overlay:SetFrameLevel(geometry.frameLevel + 1) end)
        if not okLevel then geometry.frameLevel = nil end
    end
    if geometry.frameStrata then
        local okStrata = pcall(function() overlay:SetFrameStrata(geometry.frameStrata) end)
        if not okStrata then geometry.frameStrata = nil end
    end
    overlay.cooldown = GetGlowCooldown(frame)
    return true, geometry
end

local function GetGlowOverlay(frame)
    local state = GetGlowState(frame)
    local created = false
    if not state.overlay then
        if GetCooldownViewerChild(frame) and InCombatLockdown and InCombatLockdown() then return nil end
        local ok, overlay = pcall(CreateFrame, "Frame", nil, frame)
        if not ok or not overlay then
            ReportGlowError("overlay", "Frame", overlay)
            return nil
        end
        if overlay.EnableMouse then pcall(overlay.EnableMouse, overlay, false) end
        pcall(overlay.Hide, overlay)
        state.overlay = overlay
        created = true
    end

    local geometryOK, geometry = RefreshOverlayGeometry(frame, state.overlay)
    if not geometryOK and created then
        pcall(state.overlay.Hide, state.overlay)
        return nil
    end
    return state.overlay, geometry, geometryOK
end

local function RestoreNativeAlertAlpha(frame)
    local suppressed = suppressedNativeAlerts[frame]
    if not suppressed then return true end

    local alertFrame = suppressed.frame
    local alpha = suppressed.alpha
    if not alertFrame or type(alertFrame.SetAlpha) ~= "function" then return false end
    local ok = pcall(alertFrame.SetAlpha, alertFrame, alpha)
    if not ok then return false end

    suppressedNativeAlerts[frame] = nil
    return true
end

local function SuppressNativeAlertAlpha(frame)
    local okAlert, alertFrame = pcall(function() return frame and frame.SpellActivationAlert end)
    if not okAlert or not alertFrame or type(alertFrame.SetAlpha) ~= "function" then return false end

    local existing = suppressedNativeAlerts[frame]
    if existing and existing.frame == alertFrame then
        return pcall(alertFrame.SetAlpha, alertFrame, 0)
    elseif existing and not RestoreNativeAlertAlpha(frame) then
        return false
    end

    local alpha = 1
    local okAlpha, currentAlpha = pcall(alertFrame.GetAlpha, alertFrame)
    if okAlpha and type(currentAlpha) == "number" and not BCDM:IsSecretValue(currentAlpha) then
        alpha = currentAlpha
    end

    local ok = pcall(alertFrame.SetAlpha, alertFrame, 0)
    if ok then
        suppressedNativeAlerts[frame] = { frame = alertFrame, alpha = alpha }
    end
    return ok
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
    local overlay, geometry, geometryOK = GetGlowOverlay(frame)
    if not overlay then return false end
    if not geometryOK then return state.rendererActive == true end

    local geometryChanged = GlowGeometryChanged(state.geometry, geometry)
    if state.glowType and state.rendererActive and state.glowType == glowType
        and not forceRefresh and not geometryChanged then
        state.geometry = MergeGlowGeometry(state.geometry, geometry)
        return true
    end

    if state.glowType and not ReleaseGlowRenderer(frame, state) then
        RestoreNativeAlertAlpha(frame)
        return false
    end

    state.glowType = glowType
    state.rendererActive = false
    state.cleanupPending = true
    activeGlows[frame] = true

    local started = RunGlowCall("start", glowType, function()
        overlay:Show()
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
            local color = settings.UseColor and settings.Color or nil
            LibCustomGlow.ButtonGlow_Start(overlay, color, settings.Frequency, 1)
        else
            error("unsupported glow type " .. tostring(glowType))
        end
    end)
    if not started then
        ReleaseGlowRenderer(frame, state)
        RestoreNativeAlertAlpha(frame)
        return false
    end

    state.rendererActive = true
    state.cleanupPending = nil
    state.geometry = MergeGlowGeometry(state.geometry, geometry)
    activeGlows[frame] = true
    return true
end

function BCDM:StopCustomGlow(frame)
    if not frame then return true end
    local state = glowStates[frame]
    if not state then return true end
    local stopped = ReleaseGlowRenderer(frame, state)
    if not stopped then RestoreNativeAlertAlpha(frame) end
    return stopped
end

function BCDM:StopAllCustomGlows()
    local targets = {}
    for frame in pairs(activeGlows) do targets[#targets + 1] = frame end
    for frame, state in pairs(glowStates) do
        if state.glowType and not activeGlows[frame] then targets[#targets + 1] = frame end
    end
    for _, frame in ipairs(targets) do self:StopCustomGlow(frame) end
end

local function HasNativeAlert(frame)
    local manager = ActionButtonSpellAlertManager
    if not manager or not manager.HasAlert then return false end
    local ok, hasAlert = pcall(manager.HasAlert, manager, frame)
    return ok and not BCDM:IsSecretValue(hasAlert) and hasAlert == true
end

local function RestoreNativeAlert(frame)
    local stopped = BCDM:StopCustomGlow(frame)
    local restored = RestoreNativeAlertAlpha(frame)
    activeNativeAlerts[frame] = nil
    return stopped and restored
end

local function StartNativeGlow(frame)
    if not activeNativeAlerts[frame] or not HasNativeAlert(frame) then
        RestoreNativeAlert(frame)
        return
    end

    local glow = BCDM:GetCustomGlowSettings()
    if not glow or not glow.Enabled then
        RestoreNativeAlert(frame)
        return
    end

    if BCDM:StartCustomGlow(frame) then
        SuppressNativeAlertAlpha(frame)
    end
end

local function CleanupReleasedGlow(frame)
    if not frame then return true end
    local tracked = activeNativeAlerts[frame] or activeGlows[frame] or suppressedNativeAlerts[frame]
    local shouldClearNative = activeNativeAlerts[frame] or cooldownViewerTargets[frame]
    if not tracked and not shouldClearNative then return true end

    local nativeCleared = not shouldClearNative
    if not nativeCleared and not HasNativeAlert(frame) then
        nativeCleared = true
    end

    -- Cooldown Viewer pool reset hides the row but does not clear the alert manager.
    local manager = ActionButtonSpellAlertManager
    if not nativeCleared and manager and type(manager.HideAlert) == "function" then
        local ok = pcall(manager.HideAlert, manager, frame)
        nativeCleared = ok and not HasNativeAlert(frame)
    end

    local stopped = BCDM:StopCustomGlow(frame)
    local restored = RestoreNativeAlertAlpha(frame)
    if nativeCleared then activeNativeAlerts[frame] = nil end
    return nativeCleared and stopped and restored
end

local function RememberPoolFrame(pool, frame)
    if not pool or not frame or not BCDM:IsCustomizableCooldownViewerItem(frame) then return end
    cooldownViewerTargets[frame] = true
    local frames = knownPoolFrames[pool]
    if not frames then
        frames = setmetatable({}, { __mode = "k" })
        knownPoolFrames[pool] = frames
    end
    frames[frame] = true
end

local function CleanupPoolFrames(pool)
    local frames = knownPoolFrames[pool]
    if not frames then return end
    for frame in pairs(frames) do
        activePoolFrames[frame] = nil
        CleanupReleasedGlow(frame)
    end
    if ReconcileCooldownViewerGlows then ReconcileCooldownViewerGlows() end
end

local function HookCooldownViewerPool(pool)
    if not pool then return end
    local state = hookedCooldownViewerPools[pool]
    if not state then
        state = {}
        hookedCooldownViewerPools[pool] = state
    end

    if type(pool.Release) == "function" and not state.Release then
        local ok = pcall(hooksecurefunc, pool, "Release", function(_, frame)
            activePoolFrames[frame] = nil
            CleanupReleasedGlow(frame)
        end)
        if ok then state.Release = true end
    end

    if type(pool.ReleaseAll) == "function" and not state.ReleaseAll then
        local ok = pcall(hooksecurefunc, pool, "ReleaseAll", function()
            CleanupPoolFrames(pool)
        end)
        if ok then state.ReleaseAll = true end
    end
end

local function RememberActiveCooldownViewerFrame(frame)
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers or {}) do
        local viewer = _G[viewerName]
        local pool = viewer and viewer.itemFramePool
        if pool and type(pool.IsActive) == "function" then
            local okActive, active = pcall(pool.IsActive, pool, frame)
            if okActive and not BCDM:IsSecretValue(active) and active == true then
                activePoolFrames[frame] = true
                if not (InCombatLockdown and InCombatLockdown()) then
                    HookCooldownViewerPool(pool)
                end
                RememberPoolFrame(pool, frame)
                return
            end
        end
    end
end

local function PrepareCooldownViewerGlowTarget(frame)
    if not frame or (InCombatLockdown and InCombatLockdown()) then return end
    if not BCDM:IsCustomizableCooldownViewerItem(frame) then return end
    GetGlowOverlay(frame)
end

ReconcileCooldownViewerGlows = function()
    if reconcileInProgress then return end
    reconcileInProgress = true

    local ok, message = pcall(function()
        local current = setmetatable({}, { __mode = "k" })
        local glow = BCDM:GetCustomGlowSettings()
        local enabled = glow and glow.Enabled == true

        for _, viewerName in ipairs(BCDM.CooldownManagerViewers or {}) do
            local viewer = _G[viewerName]
            local pool = viewer and viewer.itemFramePool
            if pool then
                HookCooldownViewerPool(pool)
                local okEnum, iterator, invariant, control = pcall(pool.EnumerateActive, pool)
                if okEnum and type(iterator) == "function" then
                    for frame in iterator, invariant, control do
                        if BCDM:IsCustomizableCooldownViewerItem(frame) then
                            current[frame] = true
                            activePoolFrames[frame] = true
                            RememberPoolFrame(pool, frame)
                            PrepareCooldownViewerGlowTarget(frame)

                            local hasNativeAlert = HasNativeAlert(frame)
                            if enabled and hasNativeAlert then
                                activeNativeAlerts[frame] = true
                                StartNativeGlow(frame)
                            elseif activeNativeAlerts[frame] then
                                RestoreNativeAlert(frame)
                            elseif activeGlows[frame] then
                                BCDM:StopCustomGlow(frame)
                                RestoreNativeAlertAlpha(frame)
                            elseif suppressedNativeAlerts[frame] then
                                RestoreNativeAlertAlpha(frame)
                            end
                        end
                    end
                end
            end
        end

        for frame in pairs(activePoolFrames) do
            if not current[frame] then CleanupReleasedGlow(frame) end
        end
        for _, frames in pairs(knownPoolFrames) do
            for frame in pairs(frames) do
                if not current[frame] and not activePoolFrames[frame] then
                    CleanupReleasedGlow(frame)
                end
            end
        end
        activePoolFrames = current
    end)

    reconcileInProgress = false
    if not ok then ReportGlowError("reconcile", "Pool", message) end
end

local function PrepareCooldownViewerGlowTargets()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers or {}) do
        local viewer = _G[viewerName]
        local pool = viewer and viewer.itemFramePool
        if pool then
            HookCooldownViewerPool(pool)
            local okEnum, iterator, invariant, control = pcall(pool.EnumerateActive, pool)
            if okEnum and type(iterator) == "function" then
                for frame in iterator, invariant, control do
                    RememberPoolFrame(pool, frame)
                    PrepareCooldownViewerGlowTarget(frame)
                end
            end
        end

        if viewer then
            local hooks = hookedCooldownViewers[viewer]
            if not hooks then
                hooks = {}
                hookedCooldownViewers[viewer] = hooks
            end
            if type(viewer.RefreshData) == "function" and not hooks.RefreshData then
                local ok = pcall(hooksecurefunc, viewer, "RefreshData", function()
                    PrepareCooldownViewerGlowTargets()
                    ReconcileCooldownViewerGlows()
                end)
                if ok then hooks.RefreshData = true end
            end
            if type(viewer.RefreshLayout) == "function" and not hooks.RefreshLayout then
                local ok = pcall(hooksecurefunc, viewer, "RefreshLayout", function()
                    PrepareCooldownViewerGlowTargets()
                    ReconcileCooldownViewerGlows()
                end)
                if ok then hooks.RefreshLayout = true end
            end
        end
    end
end

local function EnsureGlowPreparationFrame()
    if glowPreparationFrame then return end
    glowPreparationFrame = CreateFrame("Frame")
    glowPreparationFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    glowPreparationFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    glowPreparationFrame:RegisterEvent("ADDON_LOADED")
    glowPreparationFrame:SetScript("OnEvent", function()
        if not customGlowHooksSet and not BCDM:SetupCustomGlows() then return end
        PrepareCooldownViewerGlowTargets()
        ReconcileCooldownViewerGlows()
    end)
end

function BCDM:RefreshCustomGlows()
    self:SetupCustomGlows()
    ReconcileCooldownViewerGlows()

    local glow = self:GetCustomGlowSettings()
    if not glow or not glow.Enabled then
        local targets = {}
        for frame in pairs(activeNativeAlerts) do targets[frame] = true end
        for frame in pairs(activeGlows) do targets[frame] = true end
        for frame in pairs(suppressedNativeAlerts) do targets[frame] = true end
        for frame in pairs(targets) do RestoreNativeAlert(frame) end
        return
    end

    local targets = {}
    for frame in pairs(activeGlows) do
        if not cooldownViewerTargets[frame] or activePoolFrames[frame] then
            targets[#targets + 1] = frame
        end
    end
    for _, frame in ipairs(targets) do self:StartCustomGlow(frame, true) end
    ReconcileCooldownViewerGlows()
end

function BCDM:SetupCustomGlows()
    if customGlowHooksSet then return true end
    EnsureGlowPreparationFrame()

    local manager = ActionButtonSpellAlertManager
    if not manager or type(manager.ShowAlert) ~= "function" or type(manager.HideAlert) ~= "function" then
        return false
    end

    local hooks = hookedAlertManagers[manager]
    if not hooks then
        hooks = {}
        hookedAlertManagers[manager] = hooks
    end

    if not hooks.ShowAlert then
        local ok = pcall(hooksecurefunc, manager, "ShowAlert", function(_, frame)
            local activeGlowTarget = GetGlowTarget(frame)
            if not activeGlowTarget then return end

            local glow = BCDM:GetCustomGlowSettings()
            if not glow or not glow.Enabled then return end
            RememberActiveCooldownViewerFrame(activeGlowTarget)
            activeNativeAlerts[activeGlowTarget] = true
            StartNativeGlow(activeGlowTarget)
        end)
        if ok then hooks.ShowAlert = true end
    end

    if not hooks.HideAlert then
        local ok = pcall(hooksecurefunc, manager, "HideAlert", function(_, frame)
            local activeGlowTarget = GetCooldownViewerChild(frame)
            if not activeGlowTarget then return end
            activeNativeAlerts[activeGlowTarget] = nil
            BCDM:StopCustomGlow(activeGlowTarget)
            RestoreNativeAlertAlpha(activeGlowTarget)
            ReconcileCooldownViewerGlows()
        end)
        if ok then hooks.HideAlert = true end
    end

    if not hooks.ShowAlert or not hooks.HideAlert then return false end
    customGlowHooksSet = true
    PrepareCooldownViewerGlowTargets()
    ReconcileCooldownViewerGlows()
    return true
end
