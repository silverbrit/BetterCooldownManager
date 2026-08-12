local _, BCDM = ...

local EARLY_VIEWER_ANCHOR_NAMES = {
    "BCDM_PowerBar",
    "BCDM_SecondaryPowerBar",
    "BCDM_CastBar",
}

function BCDM:EnsureCooldownViewerAnchorFrames()
    if not CreateFrame or not UIParent then return end
    for _, frameName in ipairs(EARLY_VIEWER_ANCHOR_NAMES) do
        if not _G[frameName] then
            CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
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
local TryApplyViewerLayouts
local TryApplyViewerStyles
local CenterWrappedIcons
local viewerLayoutEventFrame
local nativeSettingsOpen = false
local editModeOpen = false
local nativeSettingsOpenPending = false

local function EnsureViewerLayoutEventFrame()
    if viewerLayoutEventFrame then return end
    viewerLayoutEventFrame = CreateFrame("Frame")
    viewerLayoutEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    viewerLayoutEventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    viewerLayoutEventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
    viewerLayoutEventFrame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
    viewerLayoutEventFrame:SetScript("OnEvent", function(_, event)
        if viewerLayoutPending and TryApplyViewerLayouts then TryApplyViewerLayouts() end
        if (event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED")
            and BCDM.QueueCooldownViewerStyleRefresh then
            BCDM:QueueCooldownViewerStyleRefresh()
        end
        if TryApplyViewerStyles then TryApplyViewerStyles() end
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
    local function IsReadableNumber(value)
        return not BCDM:IsSecretValue(value) and type(value) == "number"
    end
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
    local anchorName = layout[2]
    local anchorParent = BCDM:ResolveAnchorParent(anchorName)
    if type(anchorName) ~= "string" or not anchorName:match("^BCDM_") then
        return anchorParent, layout[3], layout[4] or 0, layout[5] or 0
    end

    if not _G[anchorName] then return nil end
    local anchorX, anchorY = BCDM.GetUIParentAnchorPosition(anchorParent, layout[3])
    if not anchorX then return nil end
    return UIParent, "BOTTOMLEFT", anchorX + (layout[4] or 0), anchorY + (layout[5] or 0)
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
                if viewerName == "EssentialCooldownViewer" then
                    LEMO:ReanchorFrame(viewer, layout[1], UIParent, layout[2], layout[3], layout[4])
                else
                    local anchorParent, relativePoint, xOffset, yOffset = GetPersistentViewerAnchor(layout)
                    if not anchorParent then return "anchor-not-ready" end
                    LEMO:ReanchorFrame(viewer, layout[1], anchorParent, relativePoint, xOffset, yOffset)
                end
            end
        end
        if BCDM.PrepareTrackedBuffVisibilityOverride then
            BCDM:PrepareTrackedBuffVisibilityOverride(LEMO)
        end
        LEMO:ApplyChanges()
        if BCDM.CommitTrackedBuffVisibilityOverride then
            BCDM:CommitTrackedBuffVisibilityOverride()
        end
        return "applied"
    end)
    if not ok then return false, result end
    if result == "not-editable" or result == "anchor-not-ready" then return false, result end
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

function BCDM:IsApplyingCooldownViewerLayout()
    return viewerLayoutApplying
end

TryApplyViewerLayouts = function()
    if not viewerLayoutPending or viewerLayoutApplying or IsInCombat()
        or AreCooldownSettingsShown() then return end
    local LEMO = BCDM.LEMO
    if not LEMO or not LEMO.IsReady or not LEMO:IsReady() then return end

    viewerLayoutApplying = true
    local ok, result = ApplyViewerLayouts()
    viewerLayoutApplying = false
    if ok then
        viewerLayoutPending = false
        viewerLayoutErrorReported = false
    elseif result ~= "combat" and result ~= "not-ready" and result ~= "not-editable"
        and result ~= "anchor-not-ready"
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

local function ShouldStyleNativeViewer(viewerName)
    return viewerName ~= "BuffIconCooldownViewer"
        or not BCDM.ShouldStyleNativeTrackedBuffViewer
        or BCDM:ShouldStyleNativeTrackedBuffViewer()
end

local function StyleIcons(onlyViewerName)
    if IsInCombat() then return end
    if not ShouldSkin() then return end
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        if (not onlyViewerName or viewerName == onlyViewerName) and ShouldStyleNativeViewer(viewerName) then
        local viewerSettings = cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]]
        local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
        local preserveNativeSize = onlyViewerName == "BuffIconCooldownViewer"
        for _, childFrame in ipairs(GetViewerItemFrames(_G[viewerName])) do
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
                BCDM:AddBorder(childFrame)
            end
        end
        end
    end
end

local function StyleChargeCount(onlyViewerName)
    if IsInCombat() then return end
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local generalSettings = BCDM.db.profile.General
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        if (not onlyViewerName or viewerName == onlyViewerName) and ShouldStyleNativeViewer(viewerName) then
        for _, childFrame in ipairs(GetViewerItemFrames(_G[viewerName])) do
            if BCDM:IsCustomizableCooldownViewerItem(childFrame)
                and childFrame.ChargeCount and childFrame.ChargeCount.Current then
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

local viewerStylePending = false
local viewerStyleScheduled = false

TryApplyViewerStyles = function()
    if not viewerStylePending or IsInCombat() or editModeOpen then return end
    viewerStylePending = false
    local onlyViewerName = nativeSettingsOpen and "BuffIconCooldownViewer" or nil
    StyleIcons(onlyViewerName)
    StyleChargeCount(onlyViewerName)
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        if (not onlyViewerName or viewerName == onlyViewerName) and ShouldStyleNativeViewer(viewerName) then
            ApplyCooldownText(viewerName)
        end
    end
    if not nativeSettingsOpen and CenterWrappedIcons then CenterWrappedIcons() end
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
local function SetHooks()
    if hooksSet then return end
    hooksSet = true
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
            nativeSettingsOpen = true
            nativeSettingsOpenPending = false
            if BCDM.SetTrackedBuffAuraEditorVisible then BCDM:SetTrackedBuffAuraEditorVisible(true) end
            BCDM:QueueCooldownViewerStyleRefresh()
        end, BCDM)
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
            nativeSettingsOpen = false
            if BCDM.SetTrackedBuffAuraEditorVisible then BCDM:SetTrackedBuffAuraEditorVisible(false) end
            BCDM:RetryPendingCooldownViewerLayoutApply()
            BCDM:QueueCooldownViewerStyleRefresh()
            if BCDM.QueueTrackedBuffAuraRefresh then BCDM:QueueTrackedBuffAuraRefresh("settings-closed") end
        end, BCDM)
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            editModeOpen = true
            if BCDM.SetTrackedBuffAuraEditorVisible then BCDM:SetTrackedBuffAuraEditorVisible(true) end
        end, BCDM)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            editModeOpen = false
            if BCDM.SetTrackedBuffAuraEditorVisible then
                BCDM:SetTrackedBuffAuraEditorVisible(false, viewerLayoutApplying)
            end
            if not viewerLayoutApplying then BCDM:QueueCooldownViewerLayoutApply() end
            BCDM:QueueCooldownViewerStyleRefresh()
            if not viewerLayoutApplying and BCDM.QueueTrackedBuffAuraRefresh then
                BCDM:QueueTrackedBuffAuraRefresh("edit-mode-exit")
            end
        end, BCDM)
    end
    hooksecurefunc(CooldownViewerSettings, "RefreshLayout", function()
        BCDM:QueueCooldownViewerStyleRefresh()
        if BCDM.QueueTrackedBuffAuraRefresh then BCDM:QueueTrackedBuffAuraRefresh("settings-layout") end
    end)
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        local hookedViewerName = viewerName
        if viewer then
            if viewer.RefreshData then
                hooksecurefunc(viewer, "RefreshData", function()
                    BCDM:QueueCooldownViewerStyleRefresh()
                    if hookedViewerName == "BuffIconCooldownViewer" and not viewerLayoutApplying
                        and BCDM.QueueTrackedBuffAuraRefresh then
                        BCDM:QueueTrackedBuffAuraRefresh("native-data")
                    end
                end)
            end
            if viewer.RefreshLayout then
                hooksecurefunc(viewer, "RefreshLayout", function()
                    BCDM:QueueCooldownViewerStyleRefresh()
                    if hookedViewerName == "BuffIconCooldownViewer" and not viewerLayoutApplying
                        and BCDM.QueueTrackedBuffAuraRefresh then
                        BCDM:QueueTrackedBuffAuraRefresh("native-layout")
                    end
                end)
            end
        end
    end
end

local function CenterWrappedRows(viewerName)
    local viewer = _G[viewerName]
    if not viewer or IsInCombat() then return end

    local iconLimit = viewer.iconLimit
    if not iconLimit or iconLimit <= 0 then return end

    local visibleIcons = {}
    for _, childFrame in ipairs(GetViewerItemFrames(viewer)) do
        if childFrame and childFrame.layoutIndex
            and not BCDM:IsCustomizableCooldownViewerItem(childFrame) then
            return
        end
        local okShown, shown = false, false
        if childFrame and childFrame.IsShown then okShown, shown = pcall(childFrame.IsShown, childFrame) end
        if childFrame and childFrame.layoutIndex and okShown
            and not BCDM:IsSecretValue(shown) and shown == true then
            table.insert(visibleIcons, childFrame)
        end
    end

    table.sort(visibleIcons, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)

    local visibleCount = #visibleIcons
    if visibleCount == 0 then return end

    local iconWidth = visibleIcons[1]:GetWidth()
    local iconHeight = visibleIcons[1]:GetHeight()
    local iconSpacing = viewer.childXPadding or 0
    local rowSpacing = viewer.childYPadding or 0
    local rowHeight = (iconHeight > 0 and iconHeight or iconWidth) + rowSpacing

    local basePoint, _, _, _, baseY = visibleIcons[1]:GetPoint(1)
    if not basePoint or not baseY then return end
    local anchorPoint = "TOP"
    local relativePoint = "TOP"
    local yDirection = -1
    if basePoint and basePoint:find("BOTTOM") then
        anchorPoint = "BOTTOM"
        relativePoint = "BOTTOM"
        yDirection = 1
    end

    local rowCount = math.ceil(visibleCount / iconLimit)
    for rowIndex = 1, rowCount do
        local rowStart = (rowIndex - 1) * iconLimit + 1
        local rowEnd = math.min(rowStart + iconLimit - 1, visibleCount)
        local rowIcons = rowEnd - rowStart + 1
        local rowWidth = (rowIcons * iconWidth) + ((rowIcons - 1) * iconSpacing)
        local startX = -rowWidth / 2 + iconWidth / 2
        local rowY = baseY + yDirection * (rowIndex - 1) * rowHeight

        for index = rowStart, rowEnd do
            local iconFrame = visibleIcons[index]
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint(anchorPoint, viewer, relativePoint, startX + (index - rowStart) * (iconWidth + iconSpacing), rowY)
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
    if BCDM.SetupTrackedBuffAuraViewer then BCDM:SetupTrackedBuffAuraViewer() end
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local deferredViewerName = viewerName
        C_Timer.After(0.1, function()
            if ShouldStyleNativeViewer(deferredViewerName) then ApplyCooldownText(deferredViewerName) end
        end)
    end

end

function BCDM:UpdateCooldownViewer(viewerType)
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local cooldownViewerFrame = _G[BCDM.DBViewerToCooldownManagerViewer[viewerType]]
    local viewerSettings = cooldownManagerSettings[viewerType]
    local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
    if viewerType == "Trinket" then BCDM:UpdateTrinketBar() return end
    if not IsInCombat() and ShouldStyleNativeViewer(BCDM.DBViewerToCooldownManagerViewer[viewerType]) then
        for _, childFrame in ipairs(GetViewerItemFrames(cooldownViewerFrame)) do
            if BCDM:IsCustomizableCooldownViewerItem(childFrame) then
            if childFrame.Icon and ShouldSkin() then
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

    if viewerType == "Buffs" and BCDM.QueueTrackedBuffAuraRefresh then
        BCDM:QueueTrackedBuffAuraRefresh("viewer-update")
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
