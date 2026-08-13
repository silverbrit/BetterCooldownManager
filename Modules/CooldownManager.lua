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

local function GetSavedActiveLayout(layouts)
    if type(layouts) ~= "table" or type(layouts.layouts) ~= "table"
        or type(layouts.activeLayout) ~= "number"
        or BCDM:IsSecretValue(layouts.activeLayout) then return nil end
    local presetManager = EditModePresetLayoutManager
    if not presetManager or type(presetManager.GetCopyOfPresetLayouts) ~= "function"
        or type(securecallfunction) ~= "function" then return nil end
    local ok, presets = pcall(securecallfunction,
        presetManager.GetCopyOfPresetLayouts, presetManager)
    if not ok or type(presets) ~= "table" then return nil end
    return layouts.layouts[layouts.activeLayout - #presets]
end

local function GetLayoutSystem(layout, viewer)
    if type(layout) ~= "table" or type(layout.systems) ~= "table" then return nil end
    for _, systemInfo in ipairs(layout.systems) do
        if systemInfo.system == viewer.system and systemInfo.systemIndex == viewer.systemIndex then
            return systemInfo
        end
    end
end

local function RefreshCooldownViewerLayouts(editMode, layouts)
    if not editMode or editMode.overrideLayoutInfo
        or type(editMode.GetActiveLayoutSystemInfo) ~= "function"
        or type(editMode.UpdateSystemAnchorInfo) ~= "function"
        or type(securecallfunction) ~= "function" then
        return editMode and editMode.overrideLayoutInfo ~= nil
    end

    local activeLayout = GetSavedActiveLayout(layouts)
    if not activeLayout then return false end
    local updated = false
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        local savedSystemInfo = viewer and GetLayoutSystem(activeLayout, viewer)
        if savedSystemInfo and type(viewer.UpdateSystem) == "function" then
            local gotManagerInfo, managerSystemInfo = pcall(securecallfunction,
                editMode.GetActiveLayoutSystemInfo, editMode, viewer.system, viewer.systemIndex)
            if not gotManagerInfo or type(managerSystemInfo) ~= "table" then return false end

            -- Apply only this native Cooldown Viewer, copy its clean resulting
            -- anchor into Blizzard's existing layout, then restore the shared
            -- system-info reference. Never assign Edit Mode manager fields.
            if not pcall(securecallfunction, viewer.UpdateSystem, viewer, savedSystemInfo)
                or not pcall(securecallfunction, editMode.UpdateSystemAnchorInfo, editMode, viewer)
                or not pcall(securecallfunction, viewer.UpdateSystem, viewer, managerSystemInfo) then
                return false
            end
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
                if viewerName == "EssentialCooldownViewer" then
                    LEMO:ReanchorFrame(viewer, layout[1], UIParent, layout[2], layout[3], layout[4])
                else
                    local anchorParent, relativePoint, xOffset, yOffset = GetPersistentViewerAnchor(layout)
                    if not anchorParent then return "anchor-not-ready" end
                    LEMO:ReanchorFrame(viewer, layout[1], anchorParent, relativePoint, xOffset, yOffset)
                end
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
        or nativeSettingsOpenPending or editModeOpen
        or IsSettingsFrameShown(EditModeManagerFrame) then return end
    local LEMO = BCDM.LEMO
    if not LEMO or not LEMO.IsReady or not LEMO:IsReady() then return end

    viewerLayoutApplying = true
    local ok, result = ApplyViewerLayouts()
    viewerLayoutApplying = false
    if ok then
        viewerLayoutPending = false
        viewerLayoutErrorReported = false
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

local function StyleIcons(onlyViewerName)
    if IsInCombat() then return end
    if not ShouldSkin() then return end
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        if not onlyViewerName or viewerName == onlyViewerName then
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
        if not onlyViewerName or viewerName == onlyViewerName then
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

-- Native tracked-buff centering follows EUIStandaloneCooldownManager's path:
-- enumerate Blizzard's active pool, sort by layoutIndex, and reapply addon-owned
-- anchors after Blizzard changes active state or lays the viewer out again.
function BCDM.ComputeCenteredTrackedBuffLayout(sizes, spacing, isHorizontal, growsForward)
    sizes = sizes or {}
    spacing = type(spacing) == "number" and not BCDM:IsSecretValue(spacing) and spacing or 0
    local function Dimension(size, key)
        local value = size and size[key]
        if type(value) ~= "number" or BCDM:IsSecretValue(value) or value < 0 then return 0 end
        return value
    end

    local total, width, height = 0, 0, 0
    for index, size in ipairs(sizes) do
        local itemWidth, itemHeight = Dimension(size, "width"), Dimension(size, "height")
        width, height = math.max(width, itemWidth), math.max(height, itemHeight)
        total = total + (isHorizontal and itemWidth or itemHeight) + (index > 1 and spacing or 0)
    end

    local positions = {}
    local cursor = growsForward and -total / 2 or total / 2
    for index, size in ipairs(sizes) do
        local itemWidth, itemHeight = Dimension(size, "width"), Dimension(size, "height")
        local extent = isHorizontal and itemWidth or itemHeight
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
local centeredTrackedBuffFrameHooks = setmetatable({}, { __mode = "k" })
local centeredTrackedBuffAnchors = setmetatable({}, { __mode = "k" })
local centeredTrackedBuffOriginalPoints = setmetatable({}, { __mode = "k" })
local QueueCenteredTrackedBuffs

local function IsTrackedBuffCenteringEnabled()
    local profile = BCDM.db and BCDM.db.profile
    local cooldownManager = profile and profile.CooldownManager
    local settings = cooldownManager and cooldownManager.Buffs
    return cooldownManager and cooldownManager.Enable == true and settings and settings.CenterBuffs == true
end

local function ReadTrackedBuffNumber(frame, methodName, fallback)
    local okMethod, method = pcall(function() return frame and frame[methodName] end)
    if not okMethod or type(method) ~= "function" then return fallback end
    local ok, value = pcall(method, frame)
    if ok and type(value) == "number" and not BCDM:IsSecretValue(value) and value > 0 then
        return value
    end
    return fallback
end

local function ReadTrackedBuffScale(frame)
    local scale = ReadTrackedBuffNumber(frame, "GetScale", 1)
    return scale >= 0.01 and scale or 1
end

local function IsReadableTrackedBuffPointValue(value)
    return value == nil or (type(value) == "number" and not BCDM:IsSecretValue(value))
end

local function CaptureTrackedBuffPoints(frame)
    if centeredTrackedBuffOriginalPoints[frame] then return end
    local points = {}
    local okCount, count = pcall(function() return frame:GetNumPoints() end)
    if okCount and type(count) == "number" and not BCDM:IsSecretValue(count) then
        for index = 1, count do
            local ok, point, relativeTo, relativePoint, x, y = pcall(function()
                return frame:GetPoint(index)
            end)
            if ok and type(point) == "string" and IsReadableTrackedBuffPointValue(x)
                and IsReadableTrackedBuffPointValue(y) then
                points[#points + 1] = { point, relativeTo, relativePoint, x, y }
            end
        end
    end
    if #points > 0 then centeredTrackedBuffOriginalPoints[frame] = points end
end

local function RestoreTrackedBuffPoints()
    for frame in pairs(centeredTrackedBuffAnchors) do centeredTrackedBuffAnchors[frame] = nil end
    for frame, points in pairs(centeredTrackedBuffOriginalPoints) do
        pcall(function() frame:ClearAllPoints() end)
        for _, point in ipairs(points) do
            pcall(function()
                frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
            end)
        end
        centeredTrackedBuffOriginalPoints[frame] = nil
    end
end

local function RestoreTrackedBuffFramePoints(frame)
    local points = centeredTrackedBuffOriginalPoints[frame]
    centeredTrackedBuffAnchors[frame] = nil
    if not points then return end
    pcall(function() frame:ClearAllPoints() end)
    for _, point in ipairs(points) do
        pcall(function()
            frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end)
    end
    centeredTrackedBuffOriginalPoints[frame] = nil
end

local function ReapplyCenteredTrackedBuffPositions()
    for frame, anchor in pairs(centeredTrackedBuffAnchors) do
        pcall(function() frame:ClearAllPoints() end)
        pcall(function()
            frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
        end)
    end
end

local function GetTrackedBuffViewerSettings(viewer)
    local isHorizontal = true
    if type(viewer.IsHorizontal) == "function" then
        local ok, value = pcall(viewer.IsHorizontal, viewer)
        if ok and type(value) == "boolean" and not BCDM:IsSecretValue(value) then isHorizontal = value end
    else
        local ok, value = pcall(function() return viewer.isHorizontal end)
        if ok and type(value) == "boolean" and not BCDM:IsSecretValue(value) then isHorizontal = value end
    end

    local directionField = isHorizontal and "layoutFramesGoingRight" or "layoutFramesGoingUp"
    local okDirection, direction = pcall(function() return viewer[directionField] end)
    local growsForward = true
    if okDirection and type(direction) == "boolean" and not BCDM:IsSecretValue(direction) then
        growsForward = direction
    end

    local spacingField = isHorizontal and "childXPadding" or "childYPadding"
    local okSpacing, spacing = pcall(function() return viewer[spacingField] end)
    if not okSpacing or type(spacing) ~= "number" or BCDM:IsSecretValue(spacing) then spacing = 0 end
    return isHorizontal, growsForward, spacing
end

local function GetCenteredTrackedBuffEntries()
    local viewer = BuffIconCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return {} end

    local settings = BCDM.db and BCDM.db.profile and BCDM.db.profile.CooldownManager
        and BCDM.db.profile.CooldownManager.Buffs
    local fallbackWidth, fallbackHeight = 32, 32
    if settings and BCDM.GetIconDimensions then
        local ok, width, height = pcall(BCDM.GetIconDimensions, BCDM, settings)
        if ok and type(width) == "number" and type(height) == "number"
            and not BCDM:IsSecretValue(width) and not BCDM:IsSecretValue(height)
            and width > 0 and height > 0 then
            fallbackWidth, fallbackHeight = width, height
        end
    end

    local entries = {}
    for frame in pool:EnumerateActive() do
        local okIcon, icon = pcall(function() return frame.Icon end)
        local active = true
        local okActiveMethod, isActive = pcall(function() return frame and frame.IsActive end)
        if okActiveMethod and type(isActive) == "function" then
            local okActive, value = pcall(isActive, frame)
            active = okActive and not BCDM:IsSecretValue(value) and value == true
        end
        local okShown, shown = false, false
        local okShownMethod, isShown = pcall(function() return frame and frame.IsShown end)
        if okShownMethod and type(isShown) == "function" then
            okShown, shown = pcall(isShown, frame)
        end
        if active and okShown and not BCDM:IsSecretValue(shown) and shown == true and okIcon and icon then
            local okIndex, layoutIndex = pcall(function() return frame.layoutIndex end)
            if not okIndex or type(layoutIndex) ~= "number" or BCDM:IsSecretValue(layoutIndex) then
                layoutIndex = 99999
            end
            local scale = ReadTrackedBuffScale(frame)
            entries[#entries + 1] = {
                frame = frame,
                layoutIndex = layoutIndex,
                order = #entries + 1,
                width = ReadTrackedBuffNumber(frame, "GetWidth", fallbackWidth) * scale,
                height = ReadTrackedBuffNumber(frame, "GetHeight", fallbackHeight) * scale,
                scale = scale,
            }
        end
    end
    return BCDM.SortTrackedBuffFrames(entries)
end

local function PositionCenteredTrackedBuffOwner(width, height)
    if not centeredTrackedBuffOwner then return end
    local settings = BCDM.db and BCDM.db.profile and BCDM.db.profile.CooldownManager
        and BCDM.db.profile.CooldownManager.Buffs
    local layout = settings and settings.Layout or { "CENTER", "NONE", "CENTER", 0, 0 }
    local anchorParent, relativePoint, xOffset, yOffset = GetPersistentViewerAnchor(layout)
    if not anchorParent then
        anchorParent = BCDM.ResolveAnchorParent
            and BCDM:ResolveAnchorParent(layout[2]) or UIParent
        relativePoint, xOffset, yOffset = layout[3], layout[4], layout[5]
    end
    anchorParent = anchorParent or UIParent
    relativePoint = relativePoint or "CENTER"
    xOffset, yOffset = xOffset or 0, yOffset or 0
    centeredTrackedBuffOwner:ClearAllPoints()
    local ok = pcall(centeredTrackedBuffOwner.SetPoint, centeredTrackedBuffOwner,
        layout[1] or "CENTER", anchorParent, relativePoint, xOffset, yOffset)
    if not ok then
        pcall(centeredTrackedBuffOwner.SetPoint, centeredTrackedBuffOwner,
            layout[1] or "CENTER", UIParent, relativePoint, xOffset, yOffset)
    end
    centeredTrackedBuffOwner:SetSize(width, height)
end

local function LayoutCenteredTrackedBuffs()
    if not centeredTrackedBuffActive or not centeredTrackedBuffOwner then return end

    local viewer = BuffIconCooldownViewer
    if not viewer then return end
    local entries = GetCenteredTrackedBuffEntries()
    local currentFrames = {}
    for _, entry in ipairs(entries) do currentFrames[entry.frame] = true end
    for frame in pairs(centeredTrackedBuffAnchors) do
        if not currentFrames[frame] then RestoreTrackedBuffFramePoints(frame) end
    end

    local isHorizontal, growsForward, spacing = GetTrackedBuffViewerSettings(viewer)
    local width, height, positions = BCDM.ComputeCenteredTrackedBuffLayout(
        entries, spacing, isHorizontal, growsForward)
    centeredTrackedBuffOwner:SetSize(width, height)
    PositionCenteredTrackedBuffOwner(width, height)
    centeredTrackedBuffOwner:Show()

    for index, entry in ipairs(entries) do
        local position = positions[index]
        CaptureTrackedBuffPoints(entry.frame)
        local scale = entry.scale
        local x = (position[1] + width / 2 - entry.width / 2) / scale
        local y = (position[2] - height / 2 + entry.height / 2) / scale
        local anchor = { "TOPLEFT", centeredTrackedBuffOwner, "TOPLEFT", x, y }
        centeredTrackedBuffAnchors[entry.frame] = anchor
        pcall(function() entry.frame:ClearAllPoints() end)
        pcall(function()
            entry.frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
        end)
    end
end

local function HookCenteredTrackedBuffFrame(frame)
    if not frame or centeredTrackedBuffFrameHooks[frame] then return end
    centeredTrackedBuffFrameHooks[frame] = true
    local okSetPoint, setPoint = pcall(function() return frame.SetPoint end)
    if okSetPoint and type(setPoint) == "function" then
        hooksecurefunc(frame, "SetPoint", function(_, point, relativeTo, relativePoint, x, y)
            local anchor = centeredTrackedBuffAnchors[frame]
            if not centeredTrackedBuffActive or not anchor or relativeTo == anchor[2] then return end
            if type(point) == "string" and IsReadableTrackedBuffPointValue(x)
                and IsReadableTrackedBuffPointValue(y) then
                centeredTrackedBuffOriginalPoints[frame] = {
                    { point, relativeTo, relativePoint, x, y },
                }
            end
            pcall(function() frame:ClearAllPoints() end)
            pcall(function()
                frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
            end)
        end)
    end
    local okActiveState, activeStateChanged = pcall(function() return frame.OnActiveStateChanged end)
    if okActiveState and type(activeStateChanged) == "function" then
        hooksecurefunc(frame, "OnActiveStateChanged", function()
            if centeredTrackedBuffActive then
                ReapplyCenteredTrackedBuffPositions()
                QueueCenteredTrackedBuffs()
            end
        end)
    end
end

local function HookCenteredTrackedBuffFrames()
    local viewer = BuffIconCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return end
    for frame in pool:EnumerateActive() do HookCenteredTrackedBuffFrame(frame) end
end

QueueCenteredTrackedBuffs = function()
    if not centeredTrackedBuffActive or centeredTrackedBuffPending
        or not centeredTrackedBuffDriver then return end
    centeredTrackedBuffPending = true
    centeredTrackedBuffTicks = 0
    centeredTrackedBuffDriver:Show()
end

local function SetCenteredTrackedBuffsActive(enabled)
    enabled = enabled == true
    if enabled == centeredTrackedBuffActive then
        if enabled then HookCenteredTrackedBuffFrames(); QueueCenteredTrackedBuffs() end
        return
    end
    if enabled and not centeredTrackedBuffOwner then return end
    centeredTrackedBuffActive = enabled
    centeredTrackedBuffPending = false
    if centeredTrackedBuffDriver then centeredTrackedBuffDriver:Hide() end
    if enabled then
        centeredTrackedBuffOwner:Show()
        HookCenteredTrackedBuffFrames()
        QueueCenteredTrackedBuffs()
    else
        RestoreTrackedBuffPoints()
        if centeredTrackedBuffOwner then centeredTrackedBuffOwner:Hide() end
    end
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
    centeredTrackedBuffHooksInstalled = true
    if type(pool.Acquire) == "function" then
        hooksecurefunc(pool, "Acquire", function()
            HookCenteredTrackedBuffFrames()
            QueueCenteredTrackedBuffs()
        end)
    end
    if CooldownViewerBuffIconItemMixin and CooldownViewerBuffIconItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffIconItemMixin, "OnCooldownIDSet", function(frame)
            HookCenteredTrackedBuffFrame(frame)
            QueueCenteredTrackedBuffs()
        end)
    end
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
local function SetHooks()
    if hooksSet then return end
    hooksSet = true
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
            nativeSettingsOpen = true
            nativeSettingsOpenPending = false
            SetCenteredTrackedBuffsActive(IsTrackedBuffCenteringEnabled())
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
            SetCenteredTrackedBuffsActive(IsTrackedBuffCenteringEnabled())
        end, BCDM)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            editModeOpen = false
            SetCenteredTrackedBuffsActive(IsTrackedBuffCenteringEnabled())
            if not viewerLayoutApplying then BCDM:QueueCooldownViewerLayoutApply() end
            BCDM:QueueCooldownViewerStyleRefresh()
        end, BCDM)
    end
    hooksecurefunc(CooldownViewerSettings, "RefreshLayout", function()
        BCDM:QueueCooldownViewerStyleRefresh()
        QueueCenteredTrackedBuffs()
    end)
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        local hookedViewerName = viewerName
        if viewer then
            if viewer.RefreshData then
                hooksecurefunc(viewer, "RefreshData", function()
                    BCDM:QueueCooldownViewerStyleRefresh()
                    if hookedViewerName == "BuffIconCooldownViewer" then QueueCenteredTrackedBuffs() end
                end)
            end
            if viewer.RefreshLayout then
                hooksecurefunc(viewer, "RefreshLayout", function()
                    BCDM:QueueCooldownViewerStyleRefresh()
                    if hookedViewerName == "BuffIconCooldownViewer" then QueueCenteredTrackedBuffs() end
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
    if not IsInCombat() then
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
