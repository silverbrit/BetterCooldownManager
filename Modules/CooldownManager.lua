local _, BCDM = ...

local EARLY_VIEWER_ANCHOR_NAMES = {
    "BCDM_PowerBar",
    "BCDM_SecondaryPowerBar",
    "BCDM_CastBar",
}

function BCDM:EnsureCooldownViewerAnchorFrames()
    if not CreateFrame or not UIParent then return end
    for _, frameName in ipairs(EARLY_VIEWER_ANCHOR_NAMES) do
        local frame = _G[frameName] or CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        if frame and frame.HookScript then
            pcall(frame.HookScript, frame, "OnSizeChanged", function()
                if BCDM.QueueCooldownViewerLayoutApply then
                    BCDM:QueueCooldownViewerLayoutApply()
                end
            end)
        end
    end
end

-- Edit Mode can replay saved Cooldown Viewer anchors before AceAddon OnEnable.
-- Register the BCM-owned anchor names while addon files are loading so that
-- Blizzard can resolve legacy layouts before the queued UIParent migration.
BCDM:EnsureCooldownViewerAnchorFrames()

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function IsReadableNumber(value)
    return type(value) == "number" and not BCDM:IsSecretValue(value)
end

local function GetViewerItemFrames(viewer)
    if not viewer or not viewer.GetItemFrames then return {}, false end
    local ok, frames = pcall(viewer.GetItemFrames, viewer)
    if not ok or BCDM:IsSecretValue(frames) or type(frames) ~= "table" then return {}, false end
    return frames, true
end

function BCDM:IsCustomizableCooldownViewerItem(itemFrame)
    if not itemFrame or not itemFrame.IsItem then return false end
    if itemFrame.IsForbidden then
        local okForbidden, forbidden = pcall(itemFrame.IsForbidden, itemFrame)
        if not okForbidden or self:IsSecretValue(forbidden) or forbidden == true then return false end
    end
    local ok, isItem = pcall(itemFrame.IsItem, itemFrame)
    return ok and not self:IsSecretValue(isItem) and isItem == false
end

local function ShouldSkin()
    if not BCDM.db.profile.CooldownManager.Enable then return false end
    if C_AddOns.IsAddOnLoaded("ElvUI") and ElvUI[1].private.skins.blizzard.cooldownManager then return false end
    if C_AddOns.IsAddOnLoaded("MasqueBlizzBars") then return false end
    return true
end

local viewerLayoutPending = false
local viewerLayoutScheduled = false
local viewerLayoutApplying = false
local viewerLayoutErrorReported = false
local viewerLayoutSettleGeneration = 0
local TryApplyViewerLayouts
local TryApplyViewerStyles
local CenterWrappedIcons
local viewerLayoutEventFrame
local nativeSettingsOpen = false
local editModeOpen = false
local nativeSettingsOpenPending = false
local QueueCenteredTrackedBuffs
local QueueSettingsHighlightRefresh

local function EnsureViewerLayoutEventFrame()
    if viewerLayoutEventFrame then return end
    viewerLayoutEventFrame = CreateFrame("Frame")
    viewerLayoutEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    viewerLayoutEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    viewerLayoutEventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    viewerLayoutEventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    viewerLayoutEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
    viewerLayoutEventFrame:RegisterEvent("ADDON_LOADED")
    viewerLayoutEventFrame:RegisterEvent("UI_SCALE_CHANGED")
    viewerLayoutEventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    viewerLayoutEventFrame:SetScript("OnEvent", function(_, event, ...)
        local addonName = ...
        if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            BCDM:QueueCooldownViewerLayoutApply()
        elseif event == "ADDON_LOADED" and addonName == "ElvUI" then
            -- ElvUI creates the supported ElvUF_* anchors after BCM may have
            -- already queued a layout with an unavailable relative frame.
            BCDM:RetryPendingCooldownViewerLayoutApply()
        end
        if viewerLayoutPending and TryApplyViewerLayouts then TryApplyViewerLayouts() end
        if (event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED")
            and BCDM.QueueCooldownViewerStyleRefresh then
            BCDM:QueueCooldownViewerStyleRefresh()
        end
        if TryApplyViewerStyles then TryApplyViewerStyles() end
        if event == "PLAYER_ENTERING_WORLD" and QueueCenteredTrackedBuffs then
            QueueCenteredTrackedBuffs()
        end
    end)
end

local POINT_FACTORS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

function BCDM.GetUIParentAnchorPosition(frame, point)
    local factors = POINT_FACTORS[point]
    if not frame or not factors or not frame.GetRect or not frame.GetEffectiveScale
        or not UIParent or not UIParent.GetEffectiveScale then
        return nil
    end

    local okRect, left, bottom, width, height = pcall(frame.GetRect, frame)
    local okFrameScale, frameScale = pcall(frame.GetEffectiveScale, frame)
    local okParentScale, parentScale = pcall(UIParent.GetEffectiveScale, UIParent)
    if not okRect or not okFrameScale or not okParentScale then return nil end
    if not IsReadableNumber(left) or not IsReadableNumber(bottom)
        or not IsReadableNumber(width) or not IsReadableNumber(height)
        or not IsReadableNumber(frameScale) or not IsReadableNumber(parentScale) then
        return nil
    end
    if parentScale <= 0 then return nil end

    local scale = frameScale / parentScale
    return (left + width * factors[1]) * scale, (bottom + height * factors[2]) * scale
end

local function GetPersistentViewerAnchor(layout)
    if type(layout) ~= "table" or BCDM:IsSecretValue(layout) then return nil end
    local ok, point, anchorName, relativePoint, xOffset, yOffset = pcall(function()
        return layout[1], layout[2], layout[3], layout[4], layout[5]
    end)
    if not ok or type(point) ~= "string" or type(relativePoint) ~= "string"
        or BCDM:IsSecretValue(point) or BCDM:IsSecretValue(anchorName)
        or BCDM:IsSecretValue(relativePoint) then
        return nil
    end
    if xOffset == nil then xOffset = 0 end
    if yOffset == nil then yOffset = 0 end
    if not IsReadableNumber(xOffset) or not IsReadableNumber(yOffset) then return nil end

    local anchorParent = BCDM:ResolveAnchorParent(anchorName)
    local requiresStableAnchor = type(anchorName) == "string"
        and (anchorName:match("^BCDM_") or anchorName:match("^ElvUF_"))
    if not requiresStableAnchor then
        return anchorParent, relativePoint, xOffset, yOffset
    end

    if not _G[anchorName] then return nil end
    local anchorX, anchorY = BCDM.GetUIParentAnchorPosition(anchorParent, relativePoint)
    if not anchorX then return nil end
    return UIParent, "BOTTOMLEFT", anchorX + xOffset, anchorY + yOffset
end

local function ReadUnsecretField(object, field)
    local ok, value = pcall(function() return object and object[field] end)
    if not ok or BCDM:IsSecretValue(value) then return nil, false end
    return value, true
end

local function GetSavedActiveLayout(layouts)
    local layoutList, layoutsOK = ReadUnsecretField(layouts, "layouts")
    local activeLayout, activeOK = ReadUnsecretField(layouts, "activeLayout")
    if type(layouts) ~= "table" or BCDM:IsSecretValue(layouts)
        or not layoutsOK or type(layoutList) ~= "table"
        or not activeOK or type(activeLayout) ~= "number" then return nil end
    local presetManager = EditModePresetLayoutManager
    if not presetManager or type(presetManager.GetCopyOfPresetLayouts) ~= "function"
        or type(securecallfunction) ~= "function" then return nil end
    local ok, presets = pcall(securecallfunction,
        presetManager.GetCopyOfPresetLayouts, presetManager)
    if not ok or type(presets) ~= "table" or BCDM:IsSecretValue(presets) then return nil end
    local okActive, active = pcall(function() return layoutList[activeLayout - #presets] end)
    return okActive and type(active) == "table" and not BCDM:IsSecretValue(active) and active or nil
end

local function GetLayoutSystem(layout, viewer)
    local systems, systemsOK = ReadUnsecretField(layout, "systems")
    local viewerSystem, systemOK = ReadUnsecretField(viewer, "system")
    local viewerSystemIndex, systemIndexOK = ReadUnsecretField(viewer, "systemIndex")
    if type(layout) ~= "table" or BCDM:IsSecretValue(layout)
        or not systemsOK or type(systems) ~= "table"
        or not systemOK or viewerSystem == nil
        or not systemIndexOK or viewerSystemIndex == nil then return nil end
    for _, systemInfo in ipairs(systems) do
        if type(systemInfo) == "table" and not BCDM:IsSecretValue(systemInfo) then
            local system, systemValueOK = ReadUnsecretField(systemInfo, "system")
            local systemIndex, indexValueOK = ReadUnsecretField(systemInfo, "systemIndex")
            if systemValueOK and indexValueOK and system ~= nil and systemIndex ~= nil
                and system == viewerSystem and systemIndex == viewerSystemIndex then
                return systemInfo
            end
        end
    end
end

local function RefreshCooldownViewerLayouts(editMode, layouts)
    local overrideLayoutInfo, overrideOK = ReadUnsecretField(editMode, "overrideLayoutInfo")
    if not editMode or not overrideOK or overrideLayoutInfo ~= nil
        or type(editMode.GetActiveLayoutSystemInfo) ~= "function"
        or type(editMode.UpdateSystemAnchorInfo) ~= "function"
        or type(securecallfunction) ~= "function" then
        return overrideOK and overrideLayoutInfo ~= nil
    end

    local activeLayout = GetSavedActiveLayout(layouts)
    if not activeLayout then return false end
    local updated = false
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        local savedSystemInfo = viewer and GetLayoutSystem(activeLayout, viewer)
        if type(savedSystemInfo) == "table" and not BCDM:IsSecretValue(savedSystemInfo)
            and type(viewer.UpdateSystem) == "function" then
            local gotManagerInfo, managerSystemInfo = pcall(securecallfunction,
                editMode.GetActiveLayoutSystemInfo, editMode, viewer.system, viewer.systemIndex)
            if not gotManagerInfo or type(managerSystemInfo) ~= "table"
                or BCDM:IsSecretValue(managerSystemInfo) then return false end

            -- Apply only this native Cooldown Viewer, copy its clean resulting
            -- anchor into Blizzard's existing layout, then restore the shared
            -- system-info reference. Never assign Edit Mode manager fields.
            local savedOK = pcall(securecallfunction, viewer.UpdateSystem, viewer, savedSystemInfo)
            local anchorOK = savedOK and pcall(securecallfunction,
                editMode.UpdateSystemAnchorInfo, editMode, viewer)
            local restoredOK = pcall(securecallfunction, viewer.UpdateSystem, viewer, managerSystemInfo)
            if not savedOK or not anchorOK or not restoredOK then return false end
            updated = true
        end
    end
    return updated
end

local function ApplyViewerLayouts()
    local LEMO = BCDM.LEMO
    if not LEMO or not LEMO.IsReady or not LEMO:IsReady() then return false, "not-ready" end
    if IsInCombat() then return false, "combat" end

    local ok, result = pcall(function()
        LEMO:LoadLayouts()
        if LEMO.CanEditActiveLayout and not LEMO:CanEditActiveLayout() then
            return "not-editable"
        end

        local settings = BCDM.db.profile.CooldownManager
        for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
            local viewer = _G[viewerName]
            local viewerSettings = settings[BCDM.CooldownManagerViewerToDBViewer[viewerName]]
            local layout = viewerSettings and viewerSettings.Layout
            if viewer and layout then
                local anchorParent, relativePoint, xOffset, yOffset = GetPersistentViewerAnchor(layout)
                if not anchorParent then return "anchor-not-ready" end
                LEMO:ReanchorFrame(viewer, layout[1], anchorParent, relativePoint, xOffset, yOffset)
            end
        end
        -- Save, then securely update only native Cooldown Viewer systems. Never
        -- call LibEditModeOverride:ApplyChanges: it opens Edit Mode from addon
        -- code and taints protected target/focus and party-frame refreshes.
        local saved = pcall(LEMO.SaveOnly, LEMO)
        if not saved then return "settings-open" end
        local editMode = EditModeManagerFrame
        local editModeAPI = C_EditMode
        if not editMode or not editModeAPI or type(editModeAPI.GetLayouts) ~= "function"
            or type(securecallfunction) ~= "function" then return "settings-open" end
        local gotLayouts, layouts = pcall(securecallfunction, editModeAPI.GetLayouts)
        if not gotLayouts or type(layouts) ~= "table" then return "settings-open" end
        local refreshed, updated = pcall(RefreshCooldownViewerLayouts, editMode, layouts)
        return refreshed and updated and "applied" or "settings-open"
    end)
    if not ok then return false, result end
    if result == "not-editable" or result == "anchor-not-ready" or result == "settings-open" then
        return false, result
    end
    return true, result
end

local function IsSettingsFrameShown(frame)
    if not frame or not frame.IsShown then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and not BCDM:IsSecretValue(shown) and shown == true
end

local function AreCooldownSettingsShown()
    return nativeSettingsOpenPending or nativeSettingsOpen or editModeOpen
        or IsSettingsFrameShown(CooldownViewerSettings)
        or IsSettingsFrameShown(_G.BetterCooldownManagerSettingsWindow)
end

function BCDM:SetCooldownViewerOpenPending(pending)
    nativeSettingsOpenPending = pending == true
end

function BCDM:IsCooldownViewerInteractionActive()
    return AreCooldownSettingsShown()
end

TryApplyViewerLayouts = function()
    if not viewerLayoutPending or viewerLayoutApplying or IsInCombat()
        or nativeSettingsOpenPending or nativeSettingsOpen or editModeOpen
        or IsSettingsFrameShown(CooldownViewerSettings)
        or IsSettingsFrameShown(EditModeManagerFrame) then return end
    local LEMO = BCDM.LEMO
    if not LEMO or not LEMO.IsReady or not LEMO:IsReady() then return end

    viewerLayoutApplying = true
    local ok, result = ApplyViewerLayouts()
    viewerLayoutApplying = false
    if ok then
        viewerLayoutPending = false
        viewerLayoutErrorReported = false
        if QueueSettingsHighlightRefresh then QueueSettingsHighlightRefresh() end
    elseif result ~= "combat" and result ~= "not-ready" and result ~= "not-editable"
        and result ~= "anchor-not-ready" and result ~= "settings-open"
        and not viewerLayoutErrorReported then
        viewerLayoutErrorReported = true
        if BCDM.PrettyPrint then
            BCDM:PrettyPrint("Unable to apply Cooldown Manager positions through Edit Mode.")
        end
    end
end

function BCDM:QueueCooldownViewerLayoutApply()
    viewerLayoutPending = true
    EnsureViewerLayoutEventFrame()
    if viewerLayoutScheduled then return end
    viewerLayoutScheduled = true
    C_Timer.After(0, function()
        viewerLayoutScheduled = false
        TryApplyViewerLayouts()
    end)
end

function BCDM:QueueCooldownViewerLayoutSettle()
    self:QueueCooldownViewerLayoutApply()
    viewerLayoutSettleGeneration = viewerLayoutSettleGeneration + 1
    local generation = viewerLayoutSettleGeneration
    C_Timer.After(0.05, function()
        if generation == viewerLayoutSettleGeneration then
            BCDM:QueueCooldownViewerLayoutApply()
            BCDM:QueueCooldownViewerStyleRefresh()
        end
    end)
end

function BCDM:RetryPendingCooldownViewerLayoutApply()
    if viewerLayoutPending then self:QueueCooldownViewerLayoutApply() end
end

local function FetchCooldownTextRegion(cooldown)
    if not cooldown then return end
    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            return region
        end
    end
end

local function ApplyCooldownText(cooldownViewer)
    if IsInCombat() then return end
    local CooldownManagerDB = BCDM.db.profile
    local GeneralDB = CooldownManagerDB.General
    local CooldownTextDB = CooldownManagerDB.CooldownManager.General.CooldownText
    local Viewer = _G[cooldownViewer]
    if not Viewer then return end
    for _, icon in ipairs(GetViewerItemFrames(Viewer)) do
        if BCDM:IsCustomizableCooldownViewerItem(icon) and icon.Cooldown then
            local textRegion = FetchCooldownTextRegion(icon.Cooldown)
            if textRegion then
                local fontSize = CooldownTextDB.FontSize
                if CooldownTextDB.ScaleByIconSize then
                    local okWidth, iconWidth = pcall(icon.GetWidth, icon)
                    if okWidth and IsReadableNumber(iconWidth) and iconWidth > 0 then
                        fontSize = fontSize * iconWidth / 36
                    end
                end
                textRegion:SetFont(BCDM.Media.Font, fontSize, GeneralDB.Fonts.FontFlag)
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

local PANDEMIC_RETRY_LIMIT = 2
local pandemicRefreshStates = setmetatable({}, { __mode = "k" })
local RefreshPandemicStateFrame

local function PandemicStateFrameHasNativeAnchors(pandemicFrame, itemFrame)
    if type(pandemicFrame.GetNumPoints) ~= "function"
        or type(pandemicFrame.GetPoint) ~= "function" then return true end
    local okCount, count = pcall(pandemicFrame.GetNumPoints, pandemicFrame)
    if not okCount or BCDM:IsSecretValue(count) or type(count) ~= "number" then return true end
    if count < 2 then return false end
    for index = 1, 2 do
        local ok, point, relativeTo, relativePoint, x, y = pcall(
            pandemicFrame.GetPoint, pandemicFrame, index)
        if not ok then return false end
        if BCDM:IsSecretValue(point) or BCDM:IsSecretValue(relativeTo)
            or BCDM:IsSecretValue(relativePoint) or BCDM:IsSecretValue(x)
            or BCDM:IsSecretValue(y) then
            return true
        end
        if type(point) ~= "string" or relativeTo ~= itemFrame
            or type(relativePoint) ~= "string" or not IsReadableNumber(x)
            or not IsReadableNumber(y) then
            return false
        end
    end
    return true
end

local function SchedulePandemicStateFrameRetry(viewer, itemFrame, state)
    if state.pending or state.retries >= PANDEMIC_RETRY_LIMIT
        or state.exhausted or not C_Timer or type(C_Timer.After) ~= "function" then
        if state.retries >= PANDEMIC_RETRY_LIMIT then state.exhausted = true end
        return
    end
    state.retries = state.retries + 1
    state.pending = true
    C_Timer.After(0, function()
        state.pending = nil
        RefreshPandemicStateFrame(viewer, itemFrame, true)
    end)
end

RefreshPandemicStateFrame = function(viewer, itemFrame, isRetry)
    if not viewer or not itemFrame or type(viewer.AnchorPandemicStateFrame) ~= "function" then return end
    local state = pandemicRefreshStates[itemFrame]
    if not state then
        state = { retries = 0 }
        pandemicRefreshStates[itemFrame] = state
    end
    if not isRetry and not state.pending and not state.exhausted then state.retries = 0 end

    local ok, pandemicFrame = pcall(function() return itemFrame.PandemicIcon end)
    if not ok or not pandemicFrame or BCDM:IsSecretValue(pandemicFrame) then
        state.retries = 0
        state.exhausted = nil
        return
    end
    local anchored = pcall(viewer.AnchorPandemicStateFrame, viewer, pandemicFrame, itemFrame)
    if anchored and PandemicStateFrameHasNativeAnchors(pandemicFrame, itemFrame) then
        state.retries = 0
        state.exhausted = nil
        return
    end
    SchedulePandemicStateFrameRetry(viewer, itemFrame, state)
end

local function StyleIcons(onlyViewerName)
    if IsInCombat() then return end
    if not ShouldSkin() then return end
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        if not onlyViewerName or viewerName == onlyViewerName then
        local viewer = _G[viewerName]
        local viewerSettings = cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]]
        local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
        local preserveNativeSize = onlyViewerName == "BuffIconCooldownViewer"
        for _, childFrame in ipairs(GetViewerItemFrames(viewer)) do
            if BCDM:IsCustomizableCooldownViewerItem(childFrame) then
                if childFrame.Icon then
                    BCDM:StripTextures(childFrame.Icon)
                    local iconZoomAmount = cooldownManagerSettings.General.IconZoom * 0.5
                    local textureWidth, textureHeight = iconWidth, iconHeight
                    if preserveNativeSize then
                        local okWidth, nativeWidth = pcall(childFrame.GetWidth, childFrame)
                        local okHeight, nativeHeight = pcall(childFrame.GetHeight, childFrame)
                        if okWidth and not BCDM:IsSecretValue(nativeWidth) and type(nativeWidth) == "number" then
                            textureWidth = nativeWidth
                        end
                        if okHeight and not BCDM:IsSecretValue(nativeHeight) and type(nativeHeight) == "number" then
                            textureHeight = nativeHeight
                        end
                    end
                    BCDM:ApplyIconTexCoord(childFrame.Icon, textureWidth, textureHeight, iconZoomAmount)
                end
                if childFrame.Cooldown then
                    local borderSize = cooldownManagerSettings.General.BorderSize
                    childFrame.Cooldown:ClearAllPoints()
                    childFrame.Cooldown:SetPoint("TOPLEFT", childFrame, "TOPLEFT", borderSize, -borderSize)
                    childFrame.Cooldown:SetPoint("BOTTOMRIGHT", childFrame, "BOTTOMRIGHT", -borderSize, borderSize)
                    childFrame.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
                    childFrame.Cooldown:SetDrawEdge(false)
                    childFrame.Cooldown:SetDrawSwipe(true)
                    childFrame.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                end
                if childFrame.CooldownFlash then childFrame.CooldownFlash:SetAlpha(0) end
                if childFrame.DebuffBorder then childFrame.DebuffBorder:SetAlpha(0) end
                if not preserveNativeSize then childFrame:SetSize(iconWidth, iconHeight) end
                RefreshPandemicStateFrame(viewer, childFrame)
                BCDM:AddBorder(childFrame)
            end
        end
        local container = _G[viewerName]
        if container and not editModeOpen then
            if type(container.GetItemContainerFrame) == "function" then
                local ok, itemContainer = pcall(container.GetItemContainerFrame, container)
                if ok and itemContainer then container = itemContainer end
            end
            if type(container.Layout) == "function" then
                -- Icon sizes are changed after Blizzard initially lays out the viewer.
                pcall(container.Layout, container)
            end
        end
        end
    end
end

-- BCM's glow overlay is item +1 and LibCustomGlow's renderer is one level above it.
local COUNT_FRAME_LEVEL_OFFSET = 3

local function RaiseCountFrame(itemFrame, countFrame)
    if not itemFrame or not countFrame or type(itemFrame.GetFrameLevel) ~= "function"
        or type(countFrame.GetFrameLevel) ~= "function" or type(countFrame.SetFrameLevel) ~= "function" then
        return
    end
    local ok, itemLevel, countLevel = pcall(function()
        return itemFrame:GetFrameLevel(), countFrame:GetFrameLevel()
    end)
    if not ok or type(itemLevel) ~= "number" or type(countLevel) ~= "number"
        or BCDM:IsSecretValue(itemLevel) or BCDM:IsSecretValue(countLevel) then
        return
    end
    local desiredLevel = itemLevel + COUNT_FRAME_LEVEL_OFFSET
    if countLevel < desiredLevel then
        pcall(countFrame.SetFrameLevel, countFrame, desiredLevel)
    end
end

local function StyleChargeCount(onlyViewerName)
    if IsInCombat() then return end
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local generalSettings = BCDM.db.profile.General
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        if not onlyViewerName or viewerName == onlyViewerName then
        for _, childFrame in ipairs(GetViewerItemFrames(_G[viewerName])) do
            if BCDM:IsCustomizableCooldownViewerItem(childFrame)
                and childFrame.ChargeCount and childFrame.ChargeCount.Current then
                RaiseCountFrame(childFrame, childFrame.ChargeCount)
                local currentChargeText = childFrame.ChargeCount.Current
                currentChargeText:SetFont(BCDM.Media.Font, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.FontSize, generalSettings.Fonts.FontFlag)
                currentChargeText:ClearAllPoints()
                currentChargeText:SetPoint(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[1], childFrame, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[3], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[4])
                currentChargeText:SetTextColor(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[1], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[3], 1)
                if generalSettings.Fonts.Shadow.Enabled then
                    currentChargeText:SetShadowColor(generalSettings.Fonts.Shadow.Colour[1], generalSettings.Fonts.Shadow.Colour[2], generalSettings.Fonts.Shadow.Colour[3], generalSettings.Fonts.Shadow.Colour[4])
                    currentChargeText:SetShadowOffset(generalSettings.Fonts.Shadow.OffsetX, generalSettings.Fonts.Shadow.OffsetY)
                else
                    currentChargeText:SetShadowColor(0, 0, 0, 0)
                    currentChargeText:SetShadowOffset(0, 0)
                end
                currentChargeText:SetDrawLayer("OVERLAY")
            end
        end
        for _, childFrame in ipairs(GetViewerItemFrames(_G[viewerName])) do
            if BCDM:IsCustomizableCooldownViewerItem(childFrame) and childFrame.Applications then
                RaiseCountFrame(childFrame, childFrame.Applications)
                local applicationsText = childFrame.Applications.Applications
                applicationsText:SetFont(BCDM.Media.Font, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.FontSize, generalSettings.Fonts.FontFlag)
                applicationsText:ClearAllPoints()
                applicationsText:SetPoint(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[1], childFrame, cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[3], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Layout[4])
                applicationsText:SetTextColor(cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[1], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[2], cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]].Text.Colour[3], 1)
                if generalSettings.Fonts.Shadow.Enabled then
                    applicationsText:SetShadowColor(generalSettings.Fonts.Shadow.Colour[1], generalSettings.Fonts.Shadow.Colour[2], generalSettings.Fonts.Shadow.Colour[3], generalSettings.Fonts.Shadow.Colour[4])
                    applicationsText:SetShadowOffset(generalSettings.Fonts.Shadow.OffsetX, generalSettings.Fonts.Shadow.OffsetY)
                else
                    applicationsText:SetShadowColor(0, 0, 0, 0)
                    applicationsText:SetShadowOffset(0, 0)
                end
                applicationsText:SetDrawLayer("OVERLAY")
            end
        end
        end
    end
end

-- Native tracked-buff centering follows EUIStandaloneCooldownManager's path:
-- enumerate Blizzard's active pool, sort by layoutIndex, and reapply addon-owned
-- anchors after Blizzard changes active state or lays the viewer out again.
function BCDM.ComputeCenteredTrackedBuffLayout(sizes, spacing, isHorizontal, growsForward)
    if type(sizes) ~= "table" or type(isHorizontal) ~= "boolean"
        or type(growsForward) ~= "boolean" or BCDM:IsSecretValue(isHorizontal)
        or BCDM:IsSecretValue(growsForward) then
        return nil
    end
    if not IsReadableNumber(spacing) then return nil end

    local total, width, height = 0, 0, 0
    for index, size in ipairs(sizes) do
        if type(size) ~= "table" or BCDM:IsSecretValue(size)
            or not IsReadableNumber(size.width) or not IsReadableNumber(size.height)
            or size.width < 0 or size.height < 0 then
            return nil
        end
        width, height = math.max(width, size.width), math.max(height, size.height)
        total = total + (isHorizontal and size.width or size.height) + (index > 1 and spacing or 0)
    end

    local positions = {}
    local cursor = growsForward and -total / 2 or total / 2
    for index, size in ipairs(sizes) do
        local extent = isHorizontal and size.width or size.height
        local center
        if growsForward then
            center = cursor + extent / 2
            cursor = cursor + extent + spacing
        else
            center = cursor - extent / 2
            cursor = cursor - extent - spacing
        end
        positions[index] = isHorizontal and { center, 0 } or { 0, center }
    end
    return math.max(1, isHorizontal and total or width), math.max(1, isHorizontal and height or total), positions
end

function BCDM.SortTrackedBuffFrames(frames)
    local function Index(entry)
        local value = entry and entry.layoutIndex
        return type(value) == "number" and not BCDM:IsSecretValue(value) and value or 99999
    end
    table.sort(frames, function(left, right)
        local leftIndex, rightIndex = Index(left), Index(right)
        if leftIndex == rightIndex then return (left.order or 0) < (right.order or 0) end
        return leftIndex < rightIndex
    end)
    return frames
end

local centeredTrackedBuffOwner
local centeredTrackedBuffDriver
local centeredTrackedBuffActive = false
local centeredTrackedBuffPending = false
local centeredTrackedBuffTicks = 0
local centeredTrackedBuffHooksInstalled = false
local centeredTrackedBuffHookState = setmetatable({}, { __mode = "k" })
local centeredTrackedBuffNativeLayout = false
local centeredTrackedBuffRetryCount = 0
local QueueCenteredTrackedBuffRetry
local centeredTrackedBuffFrameHooks = setmetatable({}, { __mode = "k" })
local centeredTrackedBuffAnchors = setmetatable({}, { __mode = "k" })
local centeredTrackedBuffOriginalPoints = setmetatable({}, { __mode = "k" })
local settingsHighlightRefreshPending = false

QueueSettingsHighlightRefresh = function()
    if not IsSettingsFrameShown(_G.BetterCooldownManagerSettingsWindow)
        or settingsHighlightRefreshPending or not BCDM.RefreshSettings then return end
    settingsHighlightRefreshPending = true
    C_Timer.After(0, function()
        settingsHighlightRefreshPending = false
        if IsSettingsFrameShown(_G.BetterCooldownManagerSettingsWindow)
            and BCDM.RefreshSettings then
            BCDM:RefreshSettings()
        end
    end)
end

function BCDM:GetTrackedBuffSettingsHighlightTarget()
    if centeredTrackedBuffActive and centeredTrackedBuffOwner then
        return centeredTrackedBuffOwner
    end
    return BuffIconCooldownViewer
end

local function IsTrackedBuffCenteringEnabled()
    local profile = BCDM.db and BCDM.db.profile
    local cooldownManager = profile and profile.CooldownManager
    local settings = cooldownManager and cooldownManager.Buffs
    return cooldownManager and cooldownManager.Enable == true and settings and settings.CenterBuffs == true
end

local function ReadTrackedBuffNumber(frame, methodName)
    local okMethod, method = pcall(function() return frame and frame[methodName] end)
    if not okMethod or type(method) ~= "function" then return nil end
    local ok, value = pcall(method, frame)
    return ok and IsReadableNumber(value) and value > 0 and value or nil
end

local function ReadTrackedBuffDimension(frame, methodName, fallback)
    local okMethod, method = pcall(function() return frame and frame[methodName] end)
    if not okMethod or BCDM:IsSecretValue(method) then return nil, false end
    if type(method) ~= "function" then return fallback, fallback ~= nil end
    local ok, value = pcall(method, frame)
    if not ok or not IsReadableNumber(value) or value <= 0 then return nil, false end
    return value, true
end

local function ReadTrackedBuffScale(frame)
    local scale = ReadTrackedBuffNumber(frame, "GetScale")
    return scale and scale >= 0.01 and scale or nil
end

local function ReadTrackedBuffPoint(frame, index)
    local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, index)
    if not ok or type(point) ~= "string" or BCDM:IsSecretValue(point)
        or (relativeTo ~= nil and BCDM:IsSecretValue(relativeTo))
        or (relativePoint ~= nil and (type(relativePoint) ~= "string"
            or BCDM:IsSecretValue(relativePoint)))
        or not IsReadableNumber(x) or not IsReadableNumber(y) then
        return nil
    end
    return { point, relativeTo, relativePoint, x, y }
end

local function CaptureTrackedBuffPoints(frame)
    if centeredTrackedBuffOriginalPoints[frame] then
        return centeredTrackedBuffOriginalPoints[frame]
    end
    local okCount, count = pcall(frame.GetNumPoints, frame)
    if not okCount or not IsReadableNumber(count) or count < 1 or count ~= math.floor(count) then
        return nil
    end

    local points = {}
    for index = 1, count do
        local point = ReadTrackedBuffPoint(frame, index)
        if not point then return nil end
        points[#points + 1] = point
    end
    return points
end

local function RestoreTrackedBuffPointList(frame, points)
    if not points then return false end
    local ok = pcall(frame.ClearAllPoints, frame)
    if not ok then return false end
    for _, point in ipairs(points) do
        local pointOK = pcall(frame.SetPoint, frame,
            point[1], point[2], point[3], point[4], point[5])
        ok = pointOK and ok
    end
    return ok
end

local function SetTrackedBuffAnchor(frame, anchor)
    if not pcall(frame.ClearAllPoints, frame) then return false end
    return pcall(frame.SetPoint, frame,
        anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
end

local function RestoreTrackedBuffPoints(frame)
    if frame then
        local points = centeredTrackedBuffOriginalPoints[frame]
        centeredTrackedBuffAnchors[frame] = nil
        if not points then return true end
        local restored = RestoreTrackedBuffPointList(frame, points)
        if restored then centeredTrackedBuffOriginalPoints[frame] = nil end
        return restored
    end

    local frames = {}
    for savedFrame in pairs(centeredTrackedBuffOriginalPoints) do
        frames[#frames + 1] = savedFrame
    end
    local restored = true
    for _, savedFrame in ipairs(frames) do
        if not RestoreTrackedBuffPoints(savedFrame) then restored = false end
    end
    for anchoredFrame in pairs(centeredTrackedBuffAnchors) do
        centeredTrackedBuffAnchors[anchoredFrame] = nil
    end
    return restored
end

local function FailCenteredTrackedBuffBatch()
    RestoreTrackedBuffPoints()
    if centeredTrackedBuffOwner then centeredTrackedBuffOwner:Hide() end
    if QueueCenteredTrackedBuffRetry then QueueCenteredTrackedBuffRetry() end
end

local function ForgetTrackedBuffPoints()
    -- ReleaseAll has already returned these rows to Blizzard's pool. Clear any
    -- stale addon point that survived a pool reset before dropping the weak state.
    for frame in pairs(centeredTrackedBuffAnchors) do
        pcall(frame.ClearAllPoints, frame)
        centeredTrackedBuffAnchors[frame] = nil
        centeredTrackedBuffOriginalPoints[frame] = nil
    end
    for frame in pairs(centeredTrackedBuffOriginalPoints) do
        centeredTrackedBuffOriginalPoints[frame] = nil
    end
end

local function ReapplyCenteredTrackedBuffPositions()
    local failed = false
    for frame, anchor in pairs(centeredTrackedBuffAnchors) do
        if not SetTrackedBuffAnchor(frame, anchor) then
            RestoreTrackedBuffPoints(frame)
            failed = true
        end
    end
    if failed then FailCenteredTrackedBuffBatch() end
end

local function ReadTrackedBuffBoolean(frame, methodName, fieldName)
    if methodName then
        local okMethod, method = pcall(function() return frame and frame[methodName] end)
        if okMethod and type(method) == "function" then
            local ok, value = pcall(method, frame)
            if ok and type(value) == "boolean" and not BCDM:IsSecretValue(value) then
                return value
            end
            return nil
        end
    end
    local okField, value = pcall(function() return frame and frame[fieldName] end)
    if okField and type(value) == "boolean" and not BCDM:IsSecretValue(value) then
        return value
    end
end

local function GetTrackedBuffViewerSettings(viewer)
    local isHorizontal = ReadTrackedBuffBoolean(viewer, "IsHorizontal", "isHorizontal")
    if isHorizontal == nil then return nil end

    local directionField = isHorizontal and "layoutFramesGoingRight" or "layoutFramesGoingUp"
    local growsForward = ReadTrackedBuffBoolean(viewer, nil, directionField)
    if growsForward == nil then return nil end

    local spacingField = isHorizontal and "childXPadding" or "childYPadding"
    local okSpacing, spacing = pcall(function() return viewer[spacingField] end)
    if not okSpacing or not IsReadableNumber(spacing) then return nil end
    return isHorizontal, growsForward, spacing
end

local function ForEachActivePoolFrame(pool, callback)
    if not pool or type(pool.EnumerateActive) ~= "function" then return false end
    local okEnum, iterator, state, control = pcall(pool.EnumerateActive, pool)
    if not okEnum or type(iterator) ~= "function" then return false end
    local callbackOK = true
    local ok = pcall(function()
        for frame in iterator, state, control do
            if callback(frame) == false then
                callbackOK = false
                break
            end
        end
    end)
    return ok and callbackOK
end

local function GetCenteredTrackedBuffEntries()
    local viewer = BuffIconCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return {}, false end

    local settings = BCDM.db and BCDM.db.profile and BCDM.db.profile.CooldownManager
        and BCDM.db.profile.CooldownManager.Buffs
    local fallbackWidth, fallbackHeight
    if settings and BCDM.GetIconDimensions then
        local ok, width, height = pcall(BCDM.GetIconDimensions, BCDM, settings)
        if ok and IsReadableNumber(width) and IsReadableNumber(height)
            and width > 0 and height > 0 then
            fallbackWidth, fallbackHeight = width, height
        end
    end

    local entries = {}
    local enumerationOK = ForEachActivePoolFrame(pool, function(frame)
        if not frame or BCDM:IsSecretValue(frame) then return false end
        local okIcon, icon = pcall(function() return frame.Icon end)
        if not okIcon or BCDM:IsSecretValue(icon) then return false end

        local active = true
        local okActiveMethod, isActive = pcall(function() return frame.IsActive end)
        if not okActiveMethod then return false end
        if type(isActive) == "function" then
            local okActive, value = pcall(isActive, frame)
            if not okActive or BCDM:IsSecretValue(value) or type(value) ~= "boolean" then
                return false
            end
            active = value
        end

        local okShownMethod, isShown = pcall(function() return frame.IsShown end)
        if not okShownMethod or type(isShown) ~= "function" then return false end
        local okShown, shown = pcall(isShown, frame)
        if not okShown or BCDM:IsSecretValue(shown) or type(shown) ~= "boolean" then
            return false
        end
        if not active or not shown then return true end
        if not icon or not BCDM:IsCustomizableCooldownViewerItem(frame) then return false end

        local okIndex, layoutIndex = pcall(function() return frame.layoutIndex end)
        if not okIndex or not IsReadableNumber(layoutIndex) then return false end
        local scale = ReadTrackedBuffScale(frame)
        local nativeWidth, widthReady = ReadTrackedBuffDimension(frame, "GetWidth", fallbackWidth)
        local nativeHeight, heightReady = ReadTrackedBuffDimension(frame, "GetHeight", fallbackHeight)
        if not scale or not widthReady or not heightReady then return false end
        entries[#entries + 1] = {
            frame = frame,
            layoutIndex = layoutIndex,
            order = #entries + 1,
            width = nativeWidth * scale,
            height = nativeHeight * scale,
            scale = scale,
        }
        return true
    end)
    if not enumerationOK then return {}, false end
    local okSort, sorted = pcall(BCDM.SortTrackedBuffFrames, entries)
    if not okSort or type(sorted) ~= "table" or BCDM:IsSecretValue(sorted) then return {}, false end
    return sorted, true
end

function BCDM:GetTrackedBuffSettingsHighlightFrames()
    local entries = GetCenteredTrackedBuffEntries()
    local frames = {}
    for _, entry in ipairs(entries) do frames[#frames + 1] = entry.frame end
    return frames
end

local function PositionCenteredTrackedBuffOwner(width, height)
    if not centeredTrackedBuffOwner then return false end
    local settings = BCDM.db and BCDM.db.profile and BCDM.db.profile.CooldownManager
        and BCDM.db.profile.CooldownManager.Buffs
    local layout = settings and settings.Layout or { "CENTER", "NONE", "CENTER", 0, 0 }
    local point, anchorName, relativePoint = layout[1], layout[2], layout[3]
    local xOffset, yOffset = layout[4] or 0, layout[5] or 0
    if type(point) ~= "string" or type(relativePoint) ~= "string"
        or not IsReadableNumber(xOffset) or not IsReadableNumber(yOffset) then
        return false
    end
    -- The BCM-owned centering frame must stay live-relative to its selected
    -- parent. Persistent UIParent translation is only for Blizzard's saved
    -- Edit Mode layout, not this addon-owned runtime anchor.
    local anchorParent = BCDM.ResolveAnchorParent
        and BCDM:ResolveAnchorParent(anchorName) or UIParent
    anchorParent = anchorParent or UIParent
    centeredTrackedBuffOwner:ClearAllPoints()
    local ok = pcall(centeredTrackedBuffOwner.SetPoint, centeredTrackedBuffOwner,
        point, anchorParent, relativePoint, xOffset, yOffset)
    if not ok then
        ok = pcall(centeredTrackedBuffOwner.SetPoint, centeredTrackedBuffOwner,
            point, UIParent, relativePoint, xOffset, yOffset)
    end
    if not ok then return false end
    centeredTrackedBuffOwner:SetSize(width, height)
    return true
end

local function LayoutCenteredTrackedBuffs()
    if not centeredTrackedBuffActive or not centeredTrackedBuffOwner
        or nativeSettingsOpen or editModeOpen then return end

    local viewer = BuffIconCooldownViewer
    if not viewer then return end
    local entries, geometryReady = GetCenteredTrackedBuffEntries()
    if not geometryReady then
        RestoreTrackedBuffPoints()
        centeredTrackedBuffOwner:Hide()
        return
    end
    if #entries == 0 then
        RestoreTrackedBuffPoints()
        centeredTrackedBuffOwner:Hide()
        return
    end
    local currentFrames = {}
    for _, entry in ipairs(entries) do currentFrames[entry.frame] = true end
    local staleRestoreFailed = false
    for frame in pairs(centeredTrackedBuffAnchors) do
        if not currentFrames[frame] and not RestoreTrackedBuffPoints(frame) then
            staleRestoreFailed = true
        end
    end
    if staleRestoreFailed then
        FailCenteredTrackedBuffBatch()
        return
    end

    local isHorizontal, growsForward, spacing = GetTrackedBuffViewerSettings(viewer)
    if isHorizontal == nil then return end
    local width, height, positions = BCDM.ComputeCenteredTrackedBuffLayout(
        entries, spacing, isHorizontal, growsForward)
    if not width or not height or not positions then return end

    for _, entry in ipairs(entries) do
        local points = CaptureTrackedBuffPoints(entry.frame)
        if not points then
            RestoreTrackedBuffPoints()
            centeredTrackedBuffOwner:Hide()
            return
        end
        centeredTrackedBuffOriginalPoints[entry.frame] = points
    end

    centeredTrackedBuffOwner:SetSize(width, height)
    if not PositionCenteredTrackedBuffOwner(width, height) then
        FailCenteredTrackedBuffBatch()
        return
    end
    centeredTrackedBuffOwner:Show()

    for index, entry in ipairs(entries) do
        local position = positions[index]
        local scale = entry.scale
        local x = (position[1] + width / 2 - entry.width / 2) / scale
        local y = (position[2] - height / 2 + entry.height / 2) / scale
        local anchor = { "TOPLEFT", centeredTrackedBuffOwner, "TOPLEFT", x, y }
        if not SetTrackedBuffAnchor(entry.frame, anchor) then
            FailCenteredTrackedBuffBatch()
            return
        end
        centeredTrackedBuffAnchors[entry.frame] = anchor
    end
    centeredTrackedBuffRetryCount = 0
    QueueSettingsHighlightRefresh()
end

local function HookCenteredTrackedBuffFrame(frame)
    if not frame or centeredTrackedBuffFrameHooks[frame] then return end
    local hooksOK = true
    local okSetPoint, setPoint = pcall(function() return frame.SetPoint end)
    if not okSetPoint then hooksOK = false end
    if okSetPoint and type(setPoint) == "function" then
        local ok = pcall(hooksecurefunc, frame, "SetPoint", function(_, point, relativeTo, relativePoint, x, y)
            local anchor = centeredTrackedBuffAnchors[frame]
            if not centeredTrackedBuffActive or centeredTrackedBuffNativeLayout
                or nativeSettingsOpen or editModeOpen or not anchor then return end
            local sameAnchor = false
            pcall(function() sameAnchor = relativeTo == anchor[2] end)
            if sameAnchor then return end

            local nativePoint
            if type(point) == "string" and not BCDM:IsSecretValue(point)
                and (relativeTo == nil or not BCDM:IsSecretValue(relativeTo))
                and (relativePoint == nil or (type(relativePoint) == "string"
                    and not BCDM:IsSecretValue(relativePoint)))
                and IsReadableNumber(x) and IsReadableNumber(y) then
                nativePoint = { point, relativeTo, relativePoint, x, y }
            end
            centeredTrackedBuffAnchors[frame] = nil
            centeredTrackedBuffOriginalPoints[frame] = nativePoint and { nativePoint } or nil
            if not nativePoint then
                FailCenteredTrackedBuffBatch()
                return
            end

            if SetTrackedBuffAnchor(frame, anchor) then
                centeredTrackedBuffAnchors[frame] = anchor
            else
                FailCenteredTrackedBuffBatch()
            end
        end)
        hooksOK = ok
    end
    local okActiveState, activeStateChanged = pcall(function() return frame.OnActiveStateChanged end)
    if not okActiveState then hooksOK = false end
    if okActiveState and type(activeStateChanged) == "function" then
        local ok = pcall(hooksecurefunc, frame, "OnActiveStateChanged", function()
            if centeredTrackedBuffActive and not centeredTrackedBuffNativeLayout
                and not nativeSettingsOpen and not editModeOpen then
                ReapplyCenteredTrackedBuffPositions()
                QueueCenteredTrackedBuffs()
            end
        end)
        hooksOK = hooksOK and ok
    end
    if hooksOK then centeredTrackedBuffFrameHooks[frame] = true end
end

local function HookCenteredTrackedBuffFrames()
    local viewer = BuffIconCooldownViewer
    local pool = viewer and viewer.itemFramePool
    ForEachActivePoolFrame(pool, function(frame)
        HookCenteredTrackedBuffFrame(frame)
        return true
    end)
end

QueueCenteredTrackedBuffs = function()
    if not centeredTrackedBuffActive or nativeSettingsOpen or editModeOpen
        or centeredTrackedBuffPending or not centeredTrackedBuffDriver then return end
    centeredTrackedBuffPending = true
    centeredTrackedBuffTicks = 0
    centeredTrackedBuffDriver:Show()
end

QueueCenteredTrackedBuffRetry = function()
    if centeredTrackedBuffRetryCount >= 2 then return false end
    centeredTrackedBuffRetryCount = centeredTrackedBuffRetryCount + 1
    QueueCenteredTrackedBuffs()
    return true
end

local function SetCenteredTrackedBuffsActive(enabled)
    enabled = enabled == true and not nativeSettingsOpen and not editModeOpen
    if enabled == centeredTrackedBuffActive then
        if enabled then HookCenteredTrackedBuffFrames(); QueueCenteredTrackedBuffs() end
        return
    end
    if enabled and not centeredTrackedBuffOwner then return end
    centeredTrackedBuffActive = enabled
    centeredTrackedBuffPending = false
    centeredTrackedBuffRetryCount = 0
    if centeredTrackedBuffDriver then centeredTrackedBuffDriver:Hide() end
    if enabled then
        centeredTrackedBuffOwner:Show()
        HookCenteredTrackedBuffFrames()
        QueueCenteredTrackedBuffs()
    else
        RestoreTrackedBuffPoints()
        if centeredTrackedBuffOwner then centeredTrackedBuffOwner:Hide() end
    end
    QueueSettingsHighlightRefresh()
end

local function InstallTrackedBuffHook(object, method, callback)
    if not object then return false end
    local state = centeredTrackedBuffHookState[object]
    if not state then
        state = {}
        centeredTrackedBuffHookState[object] = state
    end
    if state[method] then return true end
    local okMethod, methodFunction = pcall(function() return object[method] end)
    if not okMethod or type(methodFunction) ~= "function" then return false end
    local ok = pcall(hooksecurefunc, object, method, callback)
    if ok then state[method] = true end
    return ok
end

local function EnsureCenteredTrackedBuffs()
    local viewer = BuffIconCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not viewer or not pool or type(pool.EnumerateActive) ~= "function" then return false end
    if not centeredTrackedBuffOwner then
        centeredTrackedBuffOwner = CreateFrame("Frame", nil, UIParent)
        centeredTrackedBuffOwner:SetSize(1, 1)
        centeredTrackedBuffOwner:SetFrameStrata("LOW")
        centeredTrackedBuffOwner:Hide()
        centeredTrackedBuffDriver = CreateFrame("Frame")
        centeredTrackedBuffDriver:Hide()
        centeredTrackedBuffDriver:SetScript("OnUpdate", function(self)
            centeredTrackedBuffTicks = centeredTrackedBuffTicks + 1
            if centeredTrackedBuffTicks < 2 then return end
            self:Hide()
            centeredTrackedBuffPending = false
            if centeredTrackedBuffActive then LayoutCenteredTrackedBuffs() end
        end)
    end
    if centeredTrackedBuffHooksInstalled then return true end

    local hooksReady = true
    if type(pool.ReleaseAll) == "function" then
        hooksReady = InstallTrackedBuffHook(pool, "ReleaseAll", function()
            centeredTrackedBuffNativeLayout = true
            centeredTrackedBuffRetryCount = 0
            ForgetTrackedBuffPoints()
            if centeredTrackedBuffOwner then centeredTrackedBuffOwner:Hide() end
        end) and hooksReady
    else
        hooksReady = false
    end
    if type(pool.Acquire) == "function" then
        hooksReady = InstallTrackedBuffHook(pool, "Acquire", function()
            centeredTrackedBuffNativeLayout = false
            centeredTrackedBuffRetryCount = 0
            HookCenteredTrackedBuffFrames()
            QueueCenteredTrackedBuffs()
        end) and hooksReady
    else
        hooksReady = false
    end
    if CooldownViewerBuffIconItemMixin and CooldownViewerBuffIconItemMixin.OnCooldownIDSet then
        hooksReady = InstallTrackedBuffHook(CooldownViewerBuffIconItemMixin,
            "OnCooldownIDSet", function(frame)
                HookCenteredTrackedBuffFrame(frame)
                QueueCenteredTrackedBuffs()
            end) and hooksReady
    else
        hooksReady = false
    end
    centeredTrackedBuffHooksInstalled = hooksReady
    return true
end

local function SetupCenteredTrackedBuffs()
    local enabled = IsTrackedBuffCenteringEnabled()
    if not enabled then
        if centeredTrackedBuffOwner then SetCenteredTrackedBuffsActive(false) end
        return
    end
    if EnsureCenteredTrackedBuffs() then SetCenteredTrackedBuffsActive(true) end
end

local viewerStylePending = false
local viewerStyleScheduled = false

TryApplyViewerStyles = function()
    if not viewerStylePending or IsInCombat() or editModeOpen then return end
    viewerStylePending = false
    local onlyViewerName = nativeSettingsOpen and "BuffIconCooldownViewer" or nil
    StyleIcons(onlyViewerName)
    StyleChargeCount(onlyViewerName)
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        if not onlyViewerName or viewerName == onlyViewerName then
            ApplyCooldownText(viewerName)
        end
    end
    if not nativeSettingsOpen then
        if CenterWrappedIcons then CenterWrappedIcons() end
        QueueCenteredTrackedBuffs()
    end
end

function BCDM:QueueCooldownViewerStyleRefresh()
    viewerStylePending = true
    EnsureViewerLayoutEventFrame()
    if viewerStyleScheduled then return end
    viewerStyleScheduled = true
    C_Timer.After(0, function()
        viewerStyleScheduled = false
        TryApplyViewerStyles()
    end)
end

local hooksSet = false
local cooldownViewerHookState = setmetatable({}, { __mode = "k" })
local cooldownViewerEventHooksSet = false

local function InstallCooldownViewerHook(object, method, callback)
    if not object then return false end
    local state = cooldownViewerHookState[object]
    if not state then
        state = {}
        cooldownViewerHookState[object] = state
    end
    if state[method] then return true end
    local okMethod, methodFunction = pcall(function() return object[method] end)
    if not okMethod or type(methodFunction) ~= "function" then return false end
    local ok = pcall(hooksecurefunc, object, method, callback)
    if ok then state[method] = true end
    return ok
end

local function SetHooks()
    if hooksSet then return end
    local hooksOK = true
    if not cooldownViewerEventHooksSet then
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
                nativeSettingsOpen = true
                nativeSettingsOpenPending = false
                SetCenteredTrackedBuffsActive(false)
                BCDM:QueueCooldownViewerStyleRefresh()
            end, BCDM)
            EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
                nativeSettingsOpen = false
                SetCenteredTrackedBuffsActive(IsTrackedBuffCenteringEnabled())
                BCDM:RetryPendingCooldownViewerLayoutApply()
                BCDM:QueueCooldownViewerStyleRefresh()
            end, BCDM)
            EventRegistry:RegisterCallback("EditMode.Enter", function()
                editModeOpen = true
                SetCenteredTrackedBuffsActive(false)
            end, BCDM)
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                editModeOpen = false
                SetCenteredTrackedBuffsActive(IsTrackedBuffCenteringEnabled())
                if not viewerLayoutApplying then BCDM:QueueCooldownViewerLayoutApply() end
                BCDM:QueueCooldownViewerStyleRefresh()
            end, BCDM)
            cooldownViewerEventHooksSet = true
        else
            hooksOK = false
        end
    end
    hooksOK = InstallCooldownViewerHook(CooldownViewerSettings, "RefreshLayout", function()
        BCDM:QueueCooldownViewerStyleRefresh()
        QueueCenteredTrackedBuffs()
    end) and hooksOK
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        local hookedViewerName = viewerName
        if viewer then
            if type(viewer.RefreshData) == "function" then
                hooksOK = InstallCooldownViewerHook(viewer, "RefreshData", function()
                    BCDM:QueueCooldownViewerStyleRefresh()
                    if hookedViewerName == "BuffIconCooldownViewer" then
                        QueueCenteredTrackedBuffs()
                        QueueSettingsHighlightRefresh()
                    end
                end) and hooksOK
            end
            if type(viewer.RefreshLayout) == "function" then
                hooksOK = InstallCooldownViewerHook(viewer, "RefreshLayout", function()
                    BCDM:QueueCooldownViewerStyleRefresh()
                    if hookedViewerName == "BuffIconCooldownViewer" then
                        centeredTrackedBuffNativeLayout = false
                        HookCenteredTrackedBuffFrames()
                        QueueCenteredTrackedBuffs()
                        QueueSettingsHighlightRefresh()
                    end
                end) and hooksOK
            end
        end
    end
    hooksSet = hooksOK
end

local function CenterWrappedRows(viewerName)
    local viewer = _G[viewerName]
    if not viewer or IsInCombat() or nativeSettingsOpen or editModeOpen then return end

    local okLimit, iconLimit = pcall(function() return viewer.iconLimit end)
    if not okLimit or not IsReadableNumber(iconLimit) or iconLimit < 1
        or iconLimit ~= math.floor(iconLimit) then
        return
    end
    local isHorizontal = ReadTrackedBuffBoolean(viewer, "IsHorizontal", "isHorizontal")
    local growsRight = ReadTrackedBuffBoolean(viewer, nil, "layoutFramesGoingRight")
    local growsUp = ReadTrackedBuffBoolean(viewer, nil, "layoutFramesGoingUp")
    if isHorizontal == nil or growsRight == nil or growsUp == nil then return end

    local okSpacingX, iconSpacing = pcall(function() return viewer.childXPadding end)
    local okSpacingY, rowSpacing = pcall(function() return viewer.childYPadding end)
    if not okSpacingX or not okSpacingY or not IsReadableNumber(iconSpacing)
        or not IsReadableNumber(rowSpacing) then
        return
    end

    local itemFrames, framesReady = GetViewerItemFrames(viewer)
    if not framesReady then return end
    local visibleIcons = {}
    for order, childFrame in ipairs(itemFrames) do
        if childFrame and BCDM:IsSecretValue(childFrame) then return end
        local okIndex, layoutIndex = pcall(function() return childFrame and childFrame.layoutIndex end)
        if not okIndex or BCDM:IsSecretValue(layoutIndex) then return end
        if layoutIndex ~= nil then
            if not IsReadableNumber(layoutIndex)
                or not BCDM:IsCustomizableCooldownViewerItem(childFrame) then
                return
            end
            local okShownMethod, isShown = pcall(function() return childFrame.IsShown end)
            if not okShownMethod or type(isShown) ~= "function" then return end
            local okShown, shown = pcall(isShown, childFrame)
            if not okShown or BCDM:IsSecretValue(shown) or type(shown) ~= "boolean" then return end
            if shown then
                local width = ReadTrackedBuffNumber(childFrame, "GetWidth")
                local height = ReadTrackedBuffNumber(childFrame, "GetHeight")
                local point = ReadTrackedBuffPoint(childFrame, 1)
                if not width or not height or not point then return end
                visibleIcons[#visibleIcons + 1] = {
                    frame = childFrame,
                    layoutIndex = layoutIndex,
                    order = order,
                    width = width,
                    height = height,
                    point = point,
                }
            end
        end
    end
    if #visibleIcons == 0 then return end

    table.sort(visibleIcons, function(left, right)
        if left.layoutIndex == right.layoutIndex then return left.order < right.order end
        return left.layoutIndex < right.layoutIndex
    end)

    local primarySpacing = isHorizontal and iconSpacing or rowSpacing
    local crossSpacing = isHorizontal and rowSpacing or iconSpacing
    local lines = {}
    local lineCount = math.ceil(#visibleIcons / iconLimit)
    if isHorizontal then
        for lineIndex = 1, lineCount do
            local line = { icons = {} }
            local startIndex = (lineIndex - 1) * iconLimit + 1
            local endIndex = math.min(startIndex + iconLimit - 1, #visibleIcons)
            for index = startIndex, endIndex do line.icons[#line.icons + 1] = visibleIcons[index] end
            lines[lineIndex] = line
        end
    else
        -- Native vertical grids fill each column before moving to the next.
        local columnCount = lineCount
        for column = 1, columnCount do
            local line = { icons = {} }
            for slot = 0, iconLimit - 1 do
                local index = column + slot * columnCount
                if index <= #visibleIcons then line.icons[#line.icons + 1] = visibleIcons[index] end
            end
            lines[column] = line
        end
    end

    for _, line in ipairs(lines) do
        line.primary, line.cross = 0, 0
        for index, icon in ipairs(line.icons) do
            local primary = isHorizontal and icon.width or icon.height
            local cross = isHorizontal and icon.height or icon.width
            line.primary = line.primary + primary + (index > 1 and primarySpacing or 0)
            line.cross = math.max(line.cross, cross)
        end
    end

    local verticalPoint = growsUp and "BOTTOM" or "TOP"
    local baseY = visibleIcons[1].point[5]
    local positions = {}
    if isHorizontal then
        local crossOffset = 0
        for _, line in ipairs(lines) do
            local cursor = growsRight and -line.primary / 2 or line.primary / 2
            local crossBase = baseY + (growsUp and 1 or -1) * crossOffset
            for _, icon in ipairs(line.icons) do
                local x
                if growsRight then
                    x = cursor + icon.width / 2
                    cursor = cursor + icon.width + primarySpacing
                else
                    x = cursor - icon.width / 2
                    cursor = cursor - icon.width - primarySpacing
                end
                local crossPadding = (line.cross - icon.height) / 2
                positions[icon.frame] = { verticalPoint, x,
                    crossBase + (growsUp and 1 or -1) * crossPadding }
            end
            crossOffset = crossOffset + line.cross + crossSpacing
        end
    else
        local totalCross = 0
        for index, line in ipairs(lines) do
            totalCross = totalCross + line.cross + (index > 1 and crossSpacing or 0)
        end
        local crossCursor = growsRight and -totalCross / 2 or totalCross / 2
        for _, line in ipairs(lines) do
            local x
            if growsRight then
                x = crossCursor + line.cross / 2
                crossCursor = crossCursor + line.cross + crossSpacing
            else
                x = crossCursor - line.cross / 2
                crossCursor = crossCursor - line.cross - crossSpacing
            end
            local primaryCursor = baseY
            for _, icon in ipairs(line.icons) do
                positions[icon.frame] = { verticalPoint, x, primaryCursor }
                primaryCursor = primaryCursor + (growsUp and 1 or -1)
                    * (icon.height + primarySpacing)
            end
        end
    end

    local function RestoreIcon(icon)
        local point = icon.point
        pcall(icon.frame.ClearAllPoints, icon.frame)
        pcall(icon.frame.SetPoint, icon.frame,
            point[1], point[2], point[3], point[4], point[5])
    end
    for _, icon in ipairs(visibleIcons) do
        local position = positions[icon.frame]
        local okClear = pcall(icon.frame.ClearAllPoints, icon.frame)
        local okSet = okClear and pcall(icon.frame.SetPoint, icon.frame,
            position[1], viewer, position[1], position[2], position[3])
        if not okSet then
            RestoreIcon(icon)
            for _, previous in ipairs(visibleIcons) do
                if previous == icon then break end
                RestoreIcon(previous)
            end
            return
        end
    end
end

CenterWrappedIcons = function()
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local essentialSettings = cooldownManagerSettings.Essential
    local utilitySettings = cooldownManagerSettings.Utility

    if essentialSettings and essentialSettings.CenterHorizontally then CenterWrappedRows("EssentialCooldownViewer") end
    if utilitySettings and utilitySettings.CenterHorizontally then CenterWrappedRows("UtilityCooldownViewer") end
end

function BCDM:SkinCooldownManager()
    C_CVar.SetCVar("cooldownViewerEnabled", 1)
    StyleIcons()
    StyleChargeCount()
    BCDM:QueueCooldownViewerLayoutApply()
    SetHooks()
    BCDM:QueueCooldownViewerStyleRefresh()
    SetupCenteredTrackedBuffs()
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local deferredViewerName = viewerName
        C_Timer.After(0.1, function()
            ApplyCooldownText(deferredViewerName)
        end)
    end

end

function BCDM:UpdateCooldownViewer(viewerType)
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local cooldownViewerFrame = _G[BCDM.DBViewerToCooldownManagerViewer[viewerType]]
    local viewerSettings = cooldownManagerSettings[viewerType]
    local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
    if viewerType == "Trinket" then BCDM:UpdateTrinketBar() return end
    if not IsInCombat() and ShouldSkin() then
        for _, childFrame in ipairs(GetViewerItemFrames(cooldownViewerFrame)) do
            if BCDM:IsCustomizableCooldownViewerItem(childFrame) then
            if childFrame.Icon then
                BCDM:StripTextures(childFrame.Icon)
                BCDM:ApplyIconTexCoord(childFrame.Icon, iconWidth, iconHeight, cooldownManagerSettings.General.IconZoom)
            end
            if childFrame.Cooldown then
                childFrame.Cooldown:ClearAllPoints()
                childFrame.Cooldown:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, -1)
                childFrame.Cooldown:SetPoint("BOTTOMRIGHT", childFrame, "BOTTOMRIGHT", -1, 1)
                childFrame.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
                childFrame.Cooldown:SetDrawEdge(false)
                childFrame.Cooldown:SetDrawSwipe(true)
                childFrame.Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
            end
            if childFrame.CooldownFlash then childFrame.CooldownFlash:SetAlpha(0) end
            childFrame:SetSize(iconWidth, iconHeight)
            end
        end

        StyleIcons()

        StyleChargeCount()

        ApplyCooldownText(BCDM.DBViewerToCooldownManagerViewer[viewerType])
    end

    BCDM:QueueCooldownViewerLayoutApply()
    BCDM:QueueCooldownViewerStyleRefresh()

    if viewerType == "Buffs" then
        SetupCenteredTrackedBuffs()
        QueueCenteredTrackedBuffs()
    end

    BCDM:UpdatePowerBarWidth()
    BCDM:UpdateSecondaryPowerBarWidth()
    BCDM:UpdateCastBarWidth()
end

function BCDM:UpdateCooldownViewers()
    BCDM:UpdateCooldownViewer("Essential")
    BCDM:UpdateCooldownViewer("Utility")
    BCDM:UpdateCooldownViewer("Buffs")
    BCDM:RefreshCustomTrackers()
    BCDM:UpdateTrinketBar()
    BCDM:UpdatePowerBar()
    BCDM:UpdateSecondaryPowerBar()
    BCDM:UpdateCastBar()
end
