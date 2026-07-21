local _, BCDM = ...

function BCDM.ComputeTrackedBuffLayout(count, iconWidth, iconHeight, spacing, isHorizontal)
    count = math.max(0, count or 0)
    iconWidth = math.max(0, iconWidth or 0)
    iconHeight = math.max(0, iconHeight or 0)
    spacing = spacing or 0

    local positions = {}
    if count == 0 then return 0, 0, positions end

    if isHorizontal then
        for index = 1, count do
            positions[index] = { (index - 1) * (iconWidth + spacing), 0 }
        end
        return count * iconWidth + (count - 1) * spacing, iconHeight, positions
    end

    for index = 1, count do
        positions[index] = { 0, -((index - 1) * (iconHeight + spacing)) }
    end
    return iconWidth, count * iconHeight + (count - 1) * spacing, positions
end

function BCDM.ScaleTrackedBuffGeometry(iconWidth, iconHeight, xOffset, yOffset, frameScale)
    if not frameScale or frameScale < 0.01 then frameScale = 1 end
    local inverseScale = 1 / frameScale
    return iconWidth * inverseScale, iconHeight * inverseScale,
        xOffset * inverseScale, yOffset * inverseScale
end

function BCDM.SortTrackedBuffFrames(frames)
    table.sort(frames, function(left, right)
        return (left.layoutIndex or 0) < (right.layoutIndex or 0)
    end)
    return frames
end

function BCDM.CollectRenderableTrackedBuffFrames(frames)
    local renderableFrames = {}
    for _, frame in ipairs(frames or {}) do
        if frame and frame.Icon and frame.cooldownID ~= nil
            and frame.IsShown and frame:IsShown() then
            renderableFrames[#renderableFrames + 1] = frame
        end
    end
    return BCDM.SortTrackedBuffFrames(renderableFrames)
end

local function ShouldSkin()
    if not BCDM.db.profile.CooldownManager.Enable then return false end
    if C_AddOns.IsAddOnLoaded("ElvUI") and ElvUI[1].private.skins.blizzard.cooldownManager then return false end
    if C_AddOns.IsAddOnLoaded("MasqueBlizzBars") then return false end
    return true
end

local function NudgeViewer(viewerName, xOffset, yOffset)
    local viewerFrame = _G[viewerName]
    if not viewerFrame then return end
    local point, relativeTo, relativePoint, currentX, currentY = viewerFrame:GetPoint(1)
    viewerFrame:ClearAllPoints()
    viewerFrame:SetPoint(point, relativeTo, relativePoint, currentX + xOffset, currentY + yOffset)
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
    local CooldownManagerDB = BCDM.db.profile
    local GeneralDB = CooldownManagerDB.General
    local CooldownTextDB = CooldownManagerDB.CooldownManager.General.CooldownText
    local Viewer = _G[cooldownViewer]
    if not Viewer then return end
    for _, icon in ipairs({ Viewer:GetChildren() }) do
        if icon and icon.Cooldown then
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

local function Position()
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewerSettings = cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]]
        local viewerFrame = _G[viewerName]
        if viewerFrame and (viewerName == "UtilityCooldownViewer" or viewerName == "BuffIconCooldownViewer") then
            viewerFrame:ClearAllPoints()
            local anchorParent = BCDM:ResolveAnchorParent(viewerSettings.Layout[2])
            viewerFrame:SetPoint(viewerSettings.Layout[1], anchorParent, viewerSettings.Layout[3], viewerSettings.Layout[4], viewerSettings.Layout[5])
            viewerFrame:SetFrameStrata("LOW")
        elseif viewerFrame then
            viewerFrame:ClearAllPoints()
            viewerFrame:SetPoint(viewerSettings.Layout[1], UIParent, viewerSettings.Layout[3], viewerSettings.Layout[4], viewerSettings.Layout[5])
            viewerFrame:SetFrameStrata("LOW")
        end
        NudgeViewer(viewerName, -0.1, 0)
    end
end

local function StyleIcons()
    if not ShouldSkin() then return end
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        local viewerSettings = cooldownManagerSettings[BCDM.CooldownManagerViewerToDBViewer[viewerName]]
        local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
        for _, childFrame in ipairs({_G[viewerName]:GetChildren()}) do
            if childFrame then
                if childFrame.Icon then
                    BCDM:StripTextures(childFrame.Icon)
                    local iconZoomAmount = cooldownManagerSettings.General.IconZoom * 0.5
                    BCDM:ApplyIconTexCoord(childFrame.Icon, iconWidth, iconHeight, iconZoomAmount)
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
                childFrame:SetSize(iconWidth, iconHeight)
                BCDM:AddBorder(childFrame)
                if not childFrame.layoutIndex then childFrame:SetShown(false) end
            end
        end
    end
end

local function SetHooks()
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() if InCombatLockdown() then return end Position() end)
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() if InCombatLockdown() then return end BCDM.LEMO:LoadLayouts() Position() end)
    hooksecurefunc(CooldownViewerSettings, "RefreshLayout", function() if InCombatLockdown() then return end BCDM:UpdateBCDM() end)
end

local function StyleChargeCount()
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local generalSettings = BCDM.db.profile.General
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        for _, childFrame in ipairs({ _G[viewerName]:GetChildren() }) do
            if childFrame and childFrame.ChargeCount and childFrame.ChargeCount.Current then
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
        for _, childFrame in ipairs({ _G[viewerName]:GetChildren() }) do
            if childFrame and childFrame.Applications then
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

local trackedBuffContainer
local trackedBuffDriver
local trackedBuffLayoutPending = false
local trackedBuffLayoutTicks = 0
local trackedBuffRestorePending = false
local trackedBuffCenteringActive = false
local trackedBuffViewerHooked = false
local trackedBuffLastDirectLayout = 0
local trackedBuffAnchors = setmetatable({}, { __mode = "k" })
local trackedBuffFrameHooks = setmetatable({}, { __mode = "k" })

local function IsTrackedBuffCenteringEnabled()
    local profile = BCDM.db and BCDM.db.profile
    local settings = profile and profile.CooldownManager and profile.CooldownManager.Buffs
    return settings and settings.CenterBuffs == true
end

local function ClearTrackedBuffAnchors()
    for frame in pairs(trackedBuffAnchors) do
        trackedBuffAnchors[frame] = nil
    end
end

local function ReapplyTrackedBuffPositions()
    if not trackedBuffCenteringActive then return end
    for frame, anchor in pairs(trackedBuffAnchors) do
        if frame and anchor then
            frame:ClearAllPoints()
            frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
        end
    end
end

local function PositionTrackedBuffContainer()
    if not trackedBuffContainer then return end
    local settings = BCDM.db.profile.CooldownManager.Buffs
    local layout = settings.Layout
    local anchorParent = BCDM:ResolveAnchorParent(layout[2])
    local xOffset = (layout[4] or 0) - 0.1
    local yOffset = layout[5] or 0

    trackedBuffContainer:ClearAllPoints()
    local positioned = pcall(trackedBuffContainer.SetPoint, trackedBuffContainer,
        layout[1], anchorParent, layout[3], xOffset, yOffset)
    if not positioned then
        trackedBuffContainer:SetPoint(layout[1], UIParent, layout[3], xOffset, yOffset)
    end
end

local function LayoutTrackedBuffs()
    local viewer = BuffIconCooldownViewer
    if not trackedBuffCenteringActive or not trackedBuffContainer or not viewer then return 0 end

    local pool = viewer.itemFramePool
    if not pool or not pool.EnumerateActive then return 0 end

    local activeFrames = {}
    for frame in pool:EnumerateActive() do
        activeFrames[#activeFrames + 1] = frame
    end
    local icons = BCDM.CollectRenderableTrackedBuffFrames(activeFrames)
    local currentIcons = {}
    for _, frame in ipairs(icons) do
        currentIcons[frame] = true
    end

    for frame in pairs(trackedBuffAnchors) do
        if not currentIcons[frame] then trackedBuffAnchors[frame] = nil end
    end

    local count = #icons
    if count == 0 then
        trackedBuffContainer:SetSize(1, 1)
        PositionTrackedBuffContainer()
        return 0
    end

    local settings = BCDM.db.profile.CooldownManager.Buffs
    local iconWidth, iconHeight = BCDM:GetIconDimensions(settings)
    local isHorizontal = viewer.isHorizontal == true
    local spacing = isHorizontal and (viewer.childXPadding or 0) or (viewer.childYPadding or 0)
    local totalWidth, totalHeight, positions = BCDM.ComputeTrackedBuffLayout(
        count, iconWidth, iconHeight, spacing, isHorizontal)

    trackedBuffContainer:SetSize(totalWidth, totalHeight)
    PositionTrackedBuffContainer()

    for index, frame in ipairs(icons) do
        local position = positions[index]
        local frameWidth, frameHeight, xOffset, yOffset = BCDM.ScaleTrackedBuffGeometry(
            iconWidth, iconHeight, position[1], position[2], frame:GetScale())
        frame:SetSize(frameWidth, frameHeight)
        local anchor = { "TOPLEFT", trackedBuffContainer, "TOPLEFT", xOffset, yOffset }
        trackedBuffAnchors[frame] = anchor
        frame:ClearAllPoints()
        frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    end

    return count
end

local function QueueTrackedBuffLayout()
    if trackedBuffLayoutPending or not trackedBuffCenteringActive or not trackedBuffDriver then return end
    trackedBuffLayoutPending = true
    trackedBuffLayoutTicks = 0
    trackedBuffDriver:Show()
end

local function HookTrackedBuffFrame(frame)
    if not frame or trackedBuffFrameHooks[frame] then return end
    trackedBuffFrameHooks[frame] = true

    hooksecurefunc(frame, "SetPoint", function(_, _, relativeTo)
        local anchor = trackedBuffAnchors[frame]
        if not trackedBuffCenteringActive or not anchor or relativeTo == anchor[2] then return end
        frame:ClearAllPoints()
        frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    end)

    if frame.OnActiveStateChanged then
        hooksecurefunc(frame, "OnActiveStateChanged", function()
            if not trackedBuffCenteringActive then return end
            ReapplyTrackedBuffPositions()
            QueueTrackedBuffLayout()
        end)
    end
end

local function HookTrackedBuffFrames()
    local viewer = BuffIconCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not pool or not pool.EnumerateActive then return end
    for frame in pool:EnumerateActive() do
        HookTrackedBuffFrame(frame)
    end
end

local function EnsureTrackedBuffCentering()
    local viewer = BuffIconCooldownViewer
    if not viewer then return end

    if not trackedBuffContainer then
        trackedBuffContainer = CreateFrame("Frame", nil, UIParent)
        trackedBuffContainer:SetSize(1, 1)
        trackedBuffContainer:SetFrameStrata("LOW")

        trackedBuffDriver = CreateFrame("Frame")
        trackedBuffDriver:Hide()
        trackedBuffDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
        trackedBuffDriver:SetScript("OnEvent", function()
            if not trackedBuffRestorePending or trackedBuffCenteringActive then return end
            trackedBuffRestorePending = false
            if BuffIconCooldownViewer and BuffIconCooldownViewer.RefreshLayout then
                BuffIconCooldownViewer:RefreshLayout()
            end
        end)
        trackedBuffDriver:SetScript("OnUpdate", function(self)
            trackedBuffLayoutTicks = trackedBuffLayoutTicks + 1
            if trackedBuffLayoutTicks < 2 then return end
            self:Hide()
            trackedBuffLayoutPending = false
            if trackedBuffCenteringActive then
                HookTrackedBuffFrames()
                LayoutTrackedBuffs()
            end
        end)
    end

    if trackedBuffViewerHooked then return end
    trackedBuffViewerHooked = true

    if viewer.itemFramePool then
        hooksecurefunc(viewer.itemFramePool, "Acquire", HookTrackedBuffFrames)
    end
    hooksecurefunc(viewer, "RefreshLayout", function()
        if not trackedBuffCenteringActive then return end
        HookTrackedBuffFrames()
        local now = GetTime()
        if now - trackedBuffLastDirectLayout < 0.05 then
            QueueTrackedBuffLayout()
            return
        end
        trackedBuffLastDirectLayout = now
        LayoutTrackedBuffs()
    end)
end

local function SetupTrackedBuffCentering()
    EnsureTrackedBuffCentering()
    if not trackedBuffContainer then return end
    local enabled = IsTrackedBuffCenteringEnabled()
    if enabled then
        trackedBuffCenteringActive = true
        trackedBuffRestorePending = false
        trackedBuffContainer:Show()
        HookTrackedBuffFrames()
        LayoutTrackedBuffs()
    elseif trackedBuffCenteringActive then
        trackedBuffCenteringActive = false
        trackedBuffLayoutPending = false
        if trackedBuffDriver then trackedBuffDriver:Hide() end
        ClearTrackedBuffAnchors()
        if trackedBuffContainer then trackedBuffContainer:Hide() end
        if InCombatLockdown() then
            trackedBuffRestorePending = true
        elseif BuffIconCooldownViewer and BuffIconCooldownViewer.RefreshLayout then
            BuffIconCooldownViewer:RefreshLayout()
        end
    end
end

local function CenterWrappedRows(viewerName)
    local viewer = _G[viewerName]
    if not viewer then return end

    local iconLimit = viewer.iconLimit
    if not iconLimit or iconLimit <= 0 then return end

    local visibleIcons = {}
    for _, childFrame in ipairs({ viewer:GetChildren() }) do
        if childFrame and childFrame:IsShown() and childFrame.layoutIndex then
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

local function CenterWrappedIcons()
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local essentialSettings = cooldownManagerSettings.Essential
    local utilitySettings = cooldownManagerSettings.Utility

    if essentialSettings and essentialSettings.CenterHorizontally then CenterWrappedRows("EssentialCooldownViewer") end
    if utilitySettings and utilitySettings.CenterHorizontally then CenterWrappedRows("UtilityCooldownViewer") end
end

function BCDM:SkinCooldownManager()
    local LEMO = BCDM.LEMO
    LEMO:LoadLayouts()
    C_CVar.SetCVar("cooldownViewerEnabled", 1)
    StyleIcons()
    StyleChargeCount()
    Position()
    SetHooks()
    SetupTrackedBuffCentering()
    if EssentialCooldownViewer and EssentialCooldownViewer.RefreshLayout then hooksecurefunc(EssentialCooldownViewer, "RefreshLayout", function() CenterWrappedIcons() end) end
    if UtilityCooldownViewer and UtilityCooldownViewer.RefreshLayout then hooksecurefunc(UtilityCooldownViewer, "RefreshLayout", function() CenterWrappedIcons() end) end
    for _, viewerName in ipairs(BCDM.CooldownManagerViewers) do
        C_Timer.After(0.1, function() ApplyCooldownText(viewerName) end)
    end

    C_Timer.After(1, function()
        if not InCombatLockdown() then
            LEMO:ApplyChanges()
        end
    end)
end

function BCDM:UpdateCooldownViewer(viewerType)
    local cooldownManagerSettings = BCDM.db.profile.CooldownManager
    local cooldownViewerFrame = _G[BCDM.DBViewerToCooldownManagerViewer[viewerType]]
    local viewerSettings = cooldownManagerSettings[viewerType]
    local iconWidth, iconHeight = BCDM:GetIconDimensions(viewerSettings)
    if viewerType == "Trinket" then BCDM:UpdateTrinketBar() return end
    for _, childFrame in ipairs({cooldownViewerFrame:GetChildren()}) do
        if childFrame then
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

    Position()

    if viewerType == "Buffs" then SetupTrackedBuffCentering() end

    StyleChargeCount()

    ApplyCooldownText(BCDM.DBViewerToCooldownManagerViewer[viewerType])

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
