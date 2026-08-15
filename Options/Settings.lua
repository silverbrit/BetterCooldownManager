local _, BCDM = ...

local U = BCDM.SettingsUtils
local L = U.L

local initialized = false
local rootCategory
local rootCategoryID
local panels = {}
local panelEntries = {}

local ANCHOR_POINTS = {
    { text = L("Top Left"), value = "TOPLEFT" },
    { text = L("Top"), value = "TOP" },
    { text = L("Top Right"), value = "TOPRIGHT" },
    { text = L("Left"), value = "LEFT" },
    { text = L("Center"), value = "CENTER" },
    { text = L("Right"), value = "RIGHT" },
    { text = L("Bottom Left"), value = "BOTTOMLEFT" },
    { text = L("Bottom"), value = "BOTTOM" },
    { text = L("Bottom Right"), value = "BOTTOMRIGHT" },
}

local GROWTH_DIRECTIONS = {
    { text = L("Up"), value = "UP" },
    { text = L("Down"), value = "DOWN" },
    { text = L("Left"), value = "LEFT" },
    { text = L("Right"), value = "RIGHT" },
}

local FRAME_STRATA = {
    { text = "Background", value = "BACKGROUND" },
    { text = "Low", value = "LOW" },
    { text = "Medium", value = "MEDIUM" },
    { text = "High", value = "HIGH" },
    { text = "Dialog", value = "DIALOG" },
    { text = "Fullscreen", value = "FULLSCREEN" },
    { text = "Fullscreen Dialog", value = "FULLSCREEN_DIALOG" },
    { text = "Tooltip", value = "TOOLTIP" },
}

local function ProfileRoot() return BCDM.db.profile end
local function GlobalRoot() return BCDM.db.global end
local function RefreshAll() BCDM:UpdateBCDM() end
local function RefreshViewers() BCDM:UpdateCooldownViewers() end

local function PathCheckbox(controls, section, title, root, path, changed, options)
    local getValue, setValue = U.Access(root, path, changed)
    return U.Checkbox(controls, section, title, getValue, setValue, options)
end

local function PathDropdown(controls, section, title, root, path, changed, values, options)
    local getValue, setValue = U.Access(root, path, changed)
    return U.Dropdown(controls, section, title, getValue, setValue, values, options)
end

local function PathSlider(controls, section, title, root, path, changed, config)
    local getValue, setValue = U.Access(root, path, changed)
    return U.Slider(controls, section, title, getValue, setValue, config)
end

local function PathColor(controls, section, title, root, path, changed, withAlpha, options)
    local getValue, setValue = U.ColorAccess(root, path, changed, withAlpha)
    return U.Color(controls, section, title, getValue, setValue, options)
end

local function DisabledWhen(path, expected)
    return function()
        local value = U.Get(ProfileRoot, path)
        if expected == nil then return value ~= true end
        return value == expected
    end
end

local VISIBILITY_MODES = {
    { text = "Always", value = "ALWAYS" },
    { text = "In Combat", value = "IN_COMBAT" },
    { text = "Out of Combat", value = "OUT_OF_COMBAT" },
}

function BCDM:AddVisibilityPolicySettings(panel, controls, title, rootProvider, policyPath, useSharedPath, changed, disabled)
    local section = U.Section(controls, title, true)
    local function Refresh(value)
        if changed then changed(value) end
        if panel and panel.Refresh then panel:Refresh() end
    end
    local hidden
    if useSharedPath then
        local getShared, setShared = U.Access(rootProvider, useSharedPath, Refresh)
        U.Checkbox(controls, section, "Use Shared Visibility", getShared, setShared, { disabled = disabled })
        hidden = function() return getShared() ~= false end
    end
    local function Options()
        if not hidden and not disabled then return nil end
        return { hidden = hidden, disabled = disabled }
    end
    local function ChildPath(...)
        local path = {}
        for index, key in ipairs(policyPath) do path[index] = key end
        for index = 1, select("#", ...) do path[#path + 1] = select(index, ...) end
        return path
    end
    local get, set = U.Access(rootProvider, ChildPath("Mode"), Refresh)
    U.Dropdown(controls, section, "Visibility Mode", get, set, function() return VISIBILITY_MODES end, Options())
    for _, instance in ipairs({ "OpenWorld", "Dungeon", "Raid", "Arena", "Battleground" }) do
        get, set = U.Access(rootProvider, ChildPath("Instances", instance), Refresh)
        U.Checkbox(controls, section, "Show in " .. (instance == "OpenWorld" and "Open World" or instance), get, set, Options())
    end
    for _, toggle in ipairs({
        { "HideMounted", "Hide While Mounted or Skyriding" }, { "HideDead", "Hide While Dead" },
        { "HideVehicle", "Hide in Vehicles" }, { "HideResting", "Hide While Resting" },
    }) do
        get, set = U.Access(rootProvider, ChildPath(toggle[1]), Refresh)
        U.Checkbox(controls, section, toggle[2], get, set, Options())
    end

end

local function RegisterPanel(parentCategory, name, panel, isRoot)
    local displayName = L(name)
    local category
    if isRoot then
        category = Settings.RegisterCanvasLayoutCategory(panel, displayName)
    else
        category = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, displayName)
    end
    Settings.RegisterAddOnCategory(category)
    panel:Hide()
    panels[#panels + 1] = panel
    panelEntries[#panelEntries + 1] = {
        name = isRoot and L("General") or displayName,
        panel = panel,
    }
    return category
end

local AddSharedCooldownSettings

local function CreateGeneralPanel()
    local panel, controls = U.NewPanel()

    local general = U.Section(controls, "General", true)
    PathCheckbox(controls, general, "Display Login Message", GlobalRoot,
        { "DisplayLoginMessage" })
    PathCheckbox(controls, general, "Skin Blizzard Cooldown Viewers", ProfileRoot,
        { "CooldownManager", "Enable" }, function() BCDM:PromptReload() end, {
            description = L("Apply Better Cooldown Manager styling to Blizzard's Essential, Utility, and Tracked Buff viewers. A UI reload is required when changing this setting."),
        })
    PathCheckbox(controls, general, "Show Selected Element Highlight", GlobalRoot,
        { "SettingsWindow", "ShowSelectedElementHighlight" }, function(value)
            if value then BCDM:RefreshSettings() else BCDM:HideAllSettingsHighlights() end
        end, {
            description = L("Show a blue outline around the element configured by the current settings page."),
        })

    BCDM:AddVisibilityPolicySettings(panel, controls, "Shared Visibility", ProfileRoot,
        { "Visibility" }, nil, function() BCDM:RefreshOwnedFrameVisibility() end)

    local appearance = U.Section(controls, "Shared Appearance", true)
    U.Text(controls, appearance,
        "These settings are shared by cooldown viewers, power bars, and the cast bar.")
    PathSlider(controls, appearance, "Border Size", ProfileRoot,
        { "CooldownManager", "General", "BorderSize" }, RefreshAll,
        { min = 0, max = 3, step = 1 })
    PathSlider(controls, appearance, "Icon Zoom", ProfileRoot,
        { "CooldownManager", "General", "IconZoom" }, RefreshViewers, {
            min = 0, max = 1, step = 0.01,
            formatter = function(value) return string.format("%d%%", value * 100) end,
        })
    PathDropdown(controls, appearance, "Font", ProfileRoot,
        { "General", "Fonts", "Font" }, RefreshAll, U.MediaValues("font"), {
            maxHeight = 420, forceSingleColumn = true, minWidth = 360,
        })
    PathDropdown(controls, appearance, "Font Flag", ProfileRoot,
        { "General", "Fonts", "FontFlag" }, RefreshAll, function()
            return {
                { text = "None", value = "" },
                { text = "Outline", value = "OUTLINE" },
                { text = "Thick Outline", value = "THICKOUTLINE" },
                { text = "Monochrome", value = "MONOCHROME" },
            }
        end)
    PathCheckbox(controls, appearance, "Enable Font Shadow", ProfileRoot,
        { "General", "Fonts", "Shadow", "Enabled" }, RefreshAll)
    local shadowDisabled = DisabledWhen({ "General", "Fonts", "Shadow", "Enabled" })
    PathColor(controls, appearance, "Shadow Colour", ProfileRoot,
        { "General", "Fonts", "Shadow", "Colour" }, RefreshAll, true, { disabled = shadowDisabled })
    PathSlider(controls, appearance, "Shadow Offset X", ProfileRoot,
        { "General", "Fonts", "Shadow", "OffsetX" }, RefreshAll,
        { min = -10, max = 10, step = 0.1, disabled = shadowDisabled })
    PathSlider(controls, appearance, "Shadow Offset Y", ProfileRoot,
        { "General", "Fonts", "Shadow", "OffsetY" }, RefreshAll,
        { min = -10, max = 10, step = 0.1, disabled = shadowDisabled })

    local barAppearance = U.Section(controls, "Shared Bar Appearance", true)
    U.Text(controls, barAppearance,
        "These settings are shared by the power bar, secondary power bar, and cast bar.")
    PathDropdown(controls, barAppearance, "Foreground Texture", ProfileRoot,
        { "General", "Textures", "Foreground" }, RefreshAll, U.MediaValues("statusbar"), {
            maxHeight = 420, forceSingleColumn = true,
            minWidth = U.SupportsSharedMediaPreviews() and 430 or nil,
        })
    PathDropdown(controls, barAppearance, "Background Texture", ProfileRoot,
        { "General", "Textures", "Background" }, RefreshAll, U.MediaValues("statusbar"), {
            maxHeight = 420, forceSingleColumn = true,
            minWidth = U.SupportsSharedMediaPreviews() and 430 or nil,
        })

    AddSharedCooldownSettings(controls)

    local support = U.Section(controls, "Community & Support", true)
    U.Text(controls, support, "Open a link popup to join the community, report issues, or support development.")
    U.Buttons(controls, support, {
        { text = "Discord", width = 130, click = function() BCDM:OpenURL("Discord", "https://discord.gg/UZCgWRYvVE") end },
        { text = "GitHub", width = 130, click = function() BCDM:OpenURL("GitHub", "https://github.com/DaleHuntGB/BetterCooldownManager") end },
        { text = "Twitch", width = 130, click = function() BCDM:OpenURL("Twitch", "https://www.twitch.tv/unhaltedgb") end },
    })

    return panel
end

local function OpenBlizzardCooldownManager(displayMode)
    if InCombatLockdown() then
        BCDM:PrettyPrint("Blizzard's Cooldown Manager cannot be opened during combat.")
        return
    end

    if BCDM.SetCooldownViewerOpenPending then BCDM:SetCooldownViewerOpenPending(true) end

    local function OpenNativeSettings()
        local opened = false
        local shown = false
        if CooldownViewerSettings and type(CooldownViewerSettings.ShowUIPanel) == "function"
            and type(securecallfunction) == "function" then
            opened = pcall(securecallfunction, CooldownViewerSettings.ShowUIPanel, CooldownViewerSettings)
        elseif CooldownViewerSettings and type(ShowUIPanel) == "function" then
            opened = pcall(ShowUIPanel, CooldownViewerSettings)
        end
        if opened and CooldownViewerSettings and CooldownViewerSettings.IsShown then
            local okShown, isShown = pcall(CooldownViewerSettings.IsShown, CooldownViewerSettings)
            shown = okShown and isShown == true
        end
        if BCDM.SetCooldownViewerOpenPending then BCDM:SetCooldownViewerOpenPending(false) end
        if not opened or not shown then
            BCDM:PrettyPrint("Blizzard's Cooldown Manager is not available.")
        elseif displayMode and type(CooldownViewerSettings.SetDisplayMode) == "function" then
            pcall(CooldownViewerSettings.SetDisplayMode, CooldownViewerSettings, displayMode)
        end
    end

    if SettingsPanel and SettingsPanel:IsShown() then
        if type(HideUIPanel) == "function" then HideUIPanel(SettingsPanel)
        else SettingsPanel:Hide() end
    end

    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, OpenNativeSettings)
    else OpenNativeSettings() end
end

AddSharedCooldownSettings = function(controls)
    local cooldownText = U.Section(controls, "Shared Cooldown Text", true)
    PathColor(controls, cooldownText, "Text Colour", ProfileRoot,
        { "CooldownManager", "General", "CooldownText", "Colour" }, RefreshViewers, false)
    PathCheckbox(controls, cooldownText, "Scale By Icon Size", ProfileRoot,
        { "CooldownManager", "General", "CooldownText", "ScaleByIconSize" }, RefreshViewers)
    PathDropdown(controls, cooldownText, "Anchor From", ProfileRoot,
        { "CooldownManager", "General", "CooldownText", "Layout", 1 }, RefreshViewers,
        function() return ANCHOR_POINTS end)
    PathDropdown(controls, cooldownText, "Anchor To", ProfileRoot,
        { "CooldownManager", "General", "CooldownText", "Layout", 2 }, RefreshViewers,
        function() return ANCHOR_POINTS end)
    PathSlider(controls, cooldownText, "X Offset", ProfileRoot,
        { "CooldownManager", "General", "CooldownText", "Layout", 3 }, RefreshViewers,
        { min = -500, max = 500, step = 0.1 })
    PathSlider(controls, cooldownText, "Y Offset", ProfileRoot,
        { "CooldownManager", "General", "CooldownText", "Layout", 4 }, RefreshViewers,
        { min = -500, max = 500, step = 0.1 })
    PathSlider(controls, cooldownText, "Font Size", ProfileRoot,
        { "CooldownManager", "General", "CooldownText", "FontSize" }, RefreshViewers,
        { min = 6, max = 72, step = 1 })

    local glow = U.Section(controls, "Custom Glows", true)
    PathCheckbox(controls, glow, "Enable Custom Glow", ProfileRoot,
        { "CooldownManager", "General", "Glow", "Enabled" }, function() BCDM:RefreshCustomGlows() end)
    PathDropdown(controls, glow, "Glow Type", ProfileRoot,
        { "CooldownManager", "General", "Glow", "Type" }, function() BCDM:RefreshCustomGlows() end,
        function()
            return {
                { text = "Pixel", value = "Pixel" },
                { text = "Autocast", value = "Autocast" },
                { text = "Proc", value = "Proc" },
                { text = "Button", value = "Button" },
            }
        end)
    local function GlowHidden(glowType)
        return function() return U.Get(ProfileRoot, { "CooldownManager", "General", "Glow", "Type" }) ~= glowType end
    end
    local function AddGlowColor(glowType)
        PathColor(controls, glow, glowType .. " Glow Colour", ProfileRoot,
            { "CooldownManager", "General", "Glow", glowType, "Color" },
            function() BCDM:RefreshCustomGlows() end, true, { hidden = GlowHidden(glowType) })
    end
    AddGlowColor("Pixel")
    PathCheckbox(controls, glow, "Pixel Border", ProfileRoot,
        { "CooldownManager", "General", "Glow", "Pixel", "Border" }, function() BCDM:RefreshCustomGlows() end,
        { hidden = GlowHidden("Pixel") })
    for _, entry in ipairs({
        { "Lines", 1, 20, 1 }, { "Frequency", -2, 2, 0.05 }, { "Length", 1, 20, 1 },
        { "Thickness", 1, 10, 1 }, { "XOffset", -20, 20, 1, "X Offset" }, { "YOffset", -20, 20, 1, "Y Offset" },
    }) do
        PathSlider(controls, glow, "Pixel " .. (entry[5] or entry[1]), ProfileRoot,
            { "CooldownManager", "General", "Glow", "Pixel", entry[1] }, function() BCDM:RefreshCustomGlows() end,
            { min = entry[2], max = entry[3], step = entry[4], hidden = GlowHidden("Pixel") })
    end
    AddGlowColor("Autocast")
    for _, entry in ipairs({
        { "Particles", 1, 30, 1 }, { "Frequency", -2, 2, 0.05 }, { "Scale", 0.25, 3, 0.05 },
        { "XOffset", -20, 20, 1, "X Offset" }, { "YOffset", -20, 20, 1, "Y Offset" },
    }) do
        PathSlider(controls, glow, "Autocast " .. (entry[5] or entry[1]), ProfileRoot,
            { "CooldownManager", "General", "Glow", "Autocast", entry[1] }, function() BCDM:RefreshCustomGlows() end,
            { min = entry[2], max = entry[3], step = entry[4], hidden = GlowHidden("Autocast") })
    end
    AddGlowColor("Proc")
    PathCheckbox(controls, glow, "Start Proc Animation", ProfileRoot,
        { "CooldownManager", "General", "Glow", "Proc", "StartAnim" }, function() BCDM:RefreshCustomGlows() end,
        { hidden = GlowHidden("Proc") })
    for _, entry in ipairs({ { "Duration", 0.1, 5, 0.1 }, { "XOffset", -20, 20, 1, "X Offset" }, { "YOffset", -20, 20, 1, "Y Offset" } }) do
        PathSlider(controls, glow, "Proc " .. (entry[5] or entry[1]), ProfileRoot,
            { "CooldownManager", "General", "Glow", "Proc", entry[1] }, function() BCDM:RefreshCustomGlows() end,
            { min = entry[2], max = entry[3], step = entry[4], hidden = GlowHidden("Proc") })
    end
    AddGlowColor("Button")
    PathSlider(controls, glow, "Button Frequency", ProfileRoot,
        { "CooldownManager", "General", "Glow", "Button", "Frequency" }, function() BCDM:RefreshCustomGlows() end,
        { min = -2, max = 2, step = 0.05, hidden = GlowHidden("Button") })

end

local function AnchorValues(viewerType)
    return function()
        local anchors = BCDM:GetAnchorParents(viewerType)
        return anchors and U.Values(anchors[1], anchors[2]) or {}
    end
end

local function DisableSectionsWhen(controls, firstIndex, disabledProvider)
    local function AttachDisabledState(section)
        local blocker = CreateFrame("Button", nil, section)
        blocker:SetAllPoints(section)
        blocker:SetFrameLevel(section:GetFrameLevel() + 100)
        blocker:EnableMouse(true)
        blocker:Hide()

        local refresher = CreateFrame("Frame", nil, section)
        function refresher:Refresh()
            local disabled = disabledProvider() == true
            section:SetAlpha(disabled and 0.45 or 1)
            blocker:SetShown(disabled)
        end
        controls.rows[#controls.rows + 1] = refresher
    end
    for index = firstIndex, #controls.sections do
        AttachDisabledState(controls.sections[index])
    end
end

local function CreateViewerPanel(viewerType)
    local panel, controls = U.NewPanel()
    local RefreshViewerHighlight
    local function TrinketViewerDisabled()
        return viewerType == "Trinket"
            and BCDM.db.profile.CooldownManager.Trinket.Enabled ~= true
    end
    local function ViewerChanged()
        if viewerType == "Trinket" then BCDM:UpdateTrinketBar()
        else BCDM:UpdateCooldownViewer(viewerType) end
        if RefreshViewerHighlight then RefreshViewerHighlight() end
    end
    local isCustom = viewerType == "Trinket"
    local hasAnchorParent = viewerType ~= "Essential"
    if viewerType == "Trinket" then
        local trinkets = U.Section(controls, "Trinkets", true)
        PathCheckbox(controls, trinkets, "Enable Trinket Viewer", ProfileRoot,
            { "CooldownManager", "Trinket", "Enabled" }, ViewerChanged)
        PathCheckbox(controls, trinkets, "Display On-Use Only", ProfileRoot,
            { "CooldownManager", "Trinket", "DisplayOnUseOnly" }, ViewerChanged, {
                description = L("Hide equipped trinkets that do not have an on-use spell."),
                disabled = TrinketViewerDisabled,
            })
        local behavior = U.Section(controls, "Trinket Viewer", true)
        if type(BCDM.AddTrinketEntrySettings) == "function" then
            BCDM:AddTrinketEntrySettings(panel, controls, behavior, ViewerChanged)
        end
        BCDM:AddVisibilityPolicySettings(panel, controls, "Visibility", ProfileRoot,
            { "CooldownManager", "Trinket", "Visibility" },
            { "CooldownManager", "Trinket", "UseSharedVisibility" }, ViewerChanged)
    end

    local layout = U.Section(controls, "Layout & Positioning", true)
    if viewerType == "Essential" or viewerType == "Utility" then
        PathCheckbox(controls, layout, "Center Second Row Horizontally", ProfileRoot,
            { "CooldownManager", viewerType, "CenterHorizontally" }, function() BCDM:PromptReload() end, {
                description = L("A UI reload is required when changing this setting."),
            })
    elseif viewerType == "Buffs" then
        PathCheckbox(controls, layout, "Center Buffs", ProfileRoot,
            { "CooldownManager", "Buffs", "CenterBuffs" }, function() BCDM:PromptReload() end, {
                description = L("Keeps Blizzard's active Tracked Buff icons centered using the native pool and layout order. A UI reload is required."),
            })
    end
    PathDropdown(controls, layout, "Anchor From", ProfileRoot,
        { "CooldownManager", viewerType, "Layout", 1 }, ViewerChanged, function() return ANCHOR_POINTS end)
    if hasAnchorParent then
        PathDropdown(controls, layout, "Anchor Parent", ProfileRoot,
            { "CooldownManager", viewerType, "Layout", 2 }, ViewerChanged, AnchorValues(viewerType), {
                maxHeight = 420, forceSingleColumn = true,
            })
    end
    local anchorToIndex = hasAnchorParent and 3 or 2
    local xIndex = hasAnchorParent and 4 or 3
    local yIndex = hasAnchorParent and 5 or 4
    PathDropdown(controls, layout, "Anchor To", ProfileRoot,
        { "CooldownManager", viewerType, "Layout", anchorToIndex }, ViewerChanged, function() return ANCHOR_POINTS end)
    if isCustom then
        PathDropdown(controls, layout, "Growth Direction", ProfileRoot,
            { "CooldownManager", viewerType, "GrowthDirection" }, ViewerChanged, function() return GROWTH_DIRECTIONS end)
        PathSlider(controls, layout, "Icon Spacing", ProfileRoot,
            { "CooldownManager", viewerType, "Spacing" }, ViewerChanged, { min = -1, max = 32, step = 0.1 })
        PathDropdown(controls, layout, "Frame Strata", ProfileRoot,
            { "CooldownManager", viewerType, "FrameStrata" }, ViewerChanged, function() return FRAME_STRATA end)
    end
    PathSlider(controls, layout, "X Offset", ProfileRoot,
        { "CooldownManager", viewerType, "Layout", xIndex }, ViewerChanged, { min = -3000, max = 3000, step = 0.1 })
    PathSlider(controls, layout, "Y Offset", ProfileRoot,
        { "CooldownManager", viewerType, "Layout", yIndex }, ViewerChanged, { min = -3000, max = 3000, step = 0.1 })

    local icons = U.Section(controls, "Icon Settings", true)
    PathCheckbox(controls, icons, "Keep Aspect Ratio", ProfileRoot,
        { "CooldownManager", viewerType, "KeepAspectRatio" }, function(value)
            local db = BCDM.db.profile.CooldownManager[viewerType]
            local fallback = db.IconSize or db.IconWidth or db.IconHeight or 32
            if value then db.IconSize = db.IconWidth or db.IconHeight or fallback
            else db.IconWidth = db.IconWidth or fallback db.IconHeight = db.IconHeight or fallback end
            ViewerChanged()
        end)
    PathSlider(controls, icons, "Icon Size", ProfileRoot,
        { "CooldownManager", viewerType, "IconSize" }, ViewerChanged,
        { min = 16, max = 128, step = 0.1, disabled = function()
            return BCDM.db.profile.CooldownManager[viewerType].KeepAspectRatio == false
        end })
    PathSlider(controls, icons, "Icon Width", ProfileRoot,
        { "CooldownManager", viewerType, "IconWidth" }, ViewerChanged,
        { min = 16, max = 128, step = 0.1, disabled = function()
            return BCDM.db.profile.CooldownManager[viewerType].KeepAspectRatio ~= false
        end })
    PathSlider(controls, icons, "Icon Height", ProfileRoot,
        { "CooldownManager", viewerType, "IconHeight" }, ViewerChanged,
        { min = 16, max = 128, step = 0.1, disabled = function()
            return BCDM.db.profile.CooldownManager[viewerType].KeepAspectRatio ~= false
        end })
    do
        local text = U.Section(controls, "Text Settings", true)
        PathDropdown(controls, text, "Anchor From", ProfileRoot,
            { "CooldownManager", viewerType, "Text", "Layout", 1 }, ViewerChanged, function() return ANCHOR_POINTS end)
        PathDropdown(controls, text, "Anchor To", ProfileRoot,
            { "CooldownManager", viewerType, "Text", "Layout", 2 }, ViewerChanged, function() return ANCHOR_POINTS end)
        PathSlider(controls, text, "X Offset", ProfileRoot,
            { "CooldownManager", viewerType, "Text", "Layout", 3 }, ViewerChanged, { min = -500, max = 500, step = 0.1 })
        PathSlider(controls, text, "Y Offset", ProfileRoot,
            { "CooldownManager", viewerType, "Text", "Layout", 4 }, ViewerChanged, { min = -500, max = 500, step = 0.1 })
        PathSlider(controls, text, "Font Size", ProfileRoot,
            { "CooldownManager", viewerType, "Text", "FontSize" }, ViewerChanged, { min = 6, max = 72, step = 1 })
        PathColor(controls, text, "Font Colour", ProfileRoot,
            { "CooldownManager", viewerType, "Text", "Colour" }, ViewerChanged, false)
    end

    if type(BCDM.AddViewerEntrySettings) == "function" then
        BCDM:AddViewerEntrySettings(panel, controls, viewerType)
    end

    if viewerType == "Trinket" then
        -- Keep the master section interactive while visually and functionally
        -- disabling every viewer-specific section beneath it.
        DisableSectionsWhen(controls, 2, TrinketViewerDisabled)
    end

    local overlayName = BCDM.DBViewerToCooldownManagerViewer[viewerType]
    local overlayKey = overlayName and (overlayName .. "Overlay") or "TrinketViewerOverlay"
    RefreshViewerHighlight = function()
        if not panel:IsShown() then return end
        if viewerType == "Trinket" then
            local target = BCDM.TrinketBarContainer
            local settings = BCDM.db.profile.CooldownManager.Trinket
            if not settings.Enabled then
                BCDM:HideSettingsHighlight(overlayKey)
                return
            end
            local hasVisibleIcon = false
            for _, icon in pairs(BCDM.TrinketBarIcons or {}) do
                if icon and icon:IsShown() then hasVisibleIcon = true break end
            end
            if not hasVisibleIcon then
                BCDM:HideSettingsHighlight(overlayKey)
                return
            end
            local width, height = BCDM:GetIconDimensions(settings)
            local point = target and select(1, target:GetPoint(1)) or settings.Layout[1]
            BCDM:ShowSettingsHighlightForFrames(overlayKey, BCDM.TrinketBarIcons, target, {
                width = width, height = height, point = point,
            })
        else
            local nativeTarget = _G[overlayName]
            if viewerType == "Buffs" then
                local target = BCDM:GetTrackedBuffSettingsHighlightTarget()
                if target ~= nativeTarget then
                    BCDM:ShowSettingsHighlight(overlayKey, target)
                    return
                end
                local frames = BCDM:GetTrackedBuffSettingsHighlightFrames()
                if #frames > 0 then
                    BCDM:ShowSettingsHighlightForFrames(overlayKey, frames, target)
                    return
                end
            end
            BCDM:ShowSettingsHighlight(overlayKey, nativeTarget)
        end
    end
    panel.RefreshSettingsHighlight = RefreshViewerHighlight
    if viewerType == "Essential" or viewerType == "Utility" or viewerType == "Buffs" then
        panel.OnStandaloneSettingsActivated = function()
            OpenBlizzardCooldownManager(viewerType == "Buffs" and "auras" or "spells")
        end
    end
    panel:HookScript("OnShow", function()
        if viewerType == "Trinket" then
            BCDM.TrinketSettingsPreview = true
            BCDM:UpdateTrinketBar()
        end
        RefreshViewerHighlight()
    end)
    panel:HookScript("OnHide", function()
        if viewerType == "Trinket" then
            BCDM.TrinketSettingsPreview = nil
            BCDM:UpdateTrinketBar()
        end
        BCDM:HideSettingsHighlight(overlayKey)
    end)

    return panel
end

local function IsBetterTrackedBarsInstalled()
    if not (C_AddOns and C_AddOns.DoesAddOnExist) then return false end
    local ok, installed = pcall(C_AddOns.DoesAddOnExist, "BetterTrackedBars")
    return ok and installed == true
end

local function GetBetterTrackedBarsSettingsPanel()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("BetterTrackedBars")) then return end
    if not (SettingsPanel and type(SettingsPanel.GetAllCategories) == "function"
        and type(SettingsPanel.GetLayout) == "function") then return end

    local okCategories, categories = pcall(SettingsPanel.GetAllCategories, SettingsPanel)
    if not okCategories or type(categories) ~= "table" then return end
    local category
    for _, candidate in ipairs(categories) do
        local okName, name = pcall(candidate.GetName, candidate)
        if okName and name == "Better Tracked Bars" then
            category = candidate
            break
        end
    end
    if not category then return end
    local okLayout, layout = pcall(SettingsPanel.GetLayout, SettingsPanel, category)
    if not okLayout or not layout or type(layout.GetFrame) ~= "function" then return end
    local okFrame, settingsPanel = pcall(layout.GetFrame, layout)
    if okFrame and settingsPanel then return settingsPanel end
end

local function CreateTrackedBarsPanel()
    local panel, controls = U.NewPanel()
    local section = U.Section(controls, "Tracked Bars", true)
    U.Text(controls, section,
        IsBetterTrackedBarsInstalled()
            and "Better Tracked Bars is installed but its settings are unavailable. Enable it and reload the UI to manage it here."
            or "Looking for tracked buff and cooldown bars? Better Tracked Bars is compatible with Better Cooldown Manager and can be used alongside it.")
    U.Buttons(controls, section, {
        {
            text = "Install Better Tracked Bars",
            width = 220,
            click = function()
                BCDM:OpenURL("Better Tracked Bars on CurseForge",
                    "https://www.curseforge.com/wow/addons/better-tracked-bars")
            end,
        },
    })

    local function DetachEmbeddedPanel()
        local embedded = panel.EmbeddedBetterTrackedBarsPanel
        if embedded then
            embedded:Hide()
            embedded:ClearAllPoints()
            embedded:SetParent(UIParent)
            panel.EmbeddedBetterTrackedBarsPanel = nil
        end
        controls.scrollFrame:Show()
    end

    function panel:OnStandaloneSettingsActivated()
        local embedded = GetBetterTrackedBarsSettingsPanel()
        if not embedded or embedded == self then
            DetachEmbeddedPanel()
            return
        end

        controls.scrollFrame:Hide()
        self.EmbeddedBetterTrackedBarsPanel = embedded
        embedded:SetParent(self)
        embedded:ClearAllPoints()
        embedded:SetAllPoints(self)
        embedded:Show()
        if type(embedded.OnRefresh) == "function" then embedded:OnRefresh()
        elseif type(embedded.Refresh) == "function" then embedded:Refresh() end
    end

    panel.OnSettingsDeactivated = DetachEmbeddedPanel
    return panel
end

local function CreateCustomTrackersPanel()
    local panel, controls = U.NewPanel()
    BCDM:AddCustomTrackerSettings(panel, controls)
    return panel
end

local function AddPrimaryPowerColours(panel, controls)
    local section = U.Section(controls, "Power Type Colours", true)
    U.Text(controls, section, "Used when the Power Type colour mode is selected.")
    local names = {
        [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy", [6] = "Runic Power",
        [8] = "Astral Power", [11] = "Maelstrom", [13] = "Insanity", [17] = "Fury", [18] = "Pain",
    }
    for _, powerType in ipairs({ 0, 1, 2, 3, 6, 8, 11, 13, 17, 18 }) do
        PathColor(controls, section, names[powerType], ProfileRoot,
            { "General", "Colours", "PrimaryPower", powerType }, RefreshAll, false)
    end
    U.Buttons(controls, section, {
        { text = L("Reset Power Bar Colours"), width = 210, click = function()
            BCDM.db.profile.General.Colours.PrimaryPower = BCDM:CopyTable(
                BCDM:GetDefaultDB().profile.General.Colours.PrimaryPower)
            RefreshAll()
            panel:Refresh()
        end },
    })
end

local function AddSecondaryPowerColours(panel, controls, disabled)
    local section = U.Section(controls, "Secondary Resource Colours", true)
    U.Text(controls, section, "Used by Power Type and Specialization modes, plus contextual resource-state colours.")
    local names = {
        { Enum.PowerType.Chi, "Chi" }, { Enum.PowerType.ComboPoints, "Combo Points" },
        { Enum.PowerType.HolyPower, "Holy Power" }, { Enum.PowerType.ArcaneCharges, "Arcane Charges" },
        { Enum.PowerType.Essence, "Essence" }, { Enum.PowerType.SoulShards, "Soul Shards" },
        { Enum.PowerType.Runes, "Runes" }, { Enum.PowerType.Maelstrom, "Maelstrom" },
        { "SOUL_FRAGMENTS", "Soul Fragments" }, { "SOUL", "Soul" },
        { "STAGGER", "Stagger" }, { "RUNE_RECHARGE", "Rune on Cooldown" },
        { "CHARGED_COMBO_POINTS", "Charged Combo Points" }, { "ESSENCE_RECHARGE", "Essence on Cooldown" },
    }
    for _, entry in ipairs(names) do
        PathColor(controls, section, entry[2], ProfileRoot,
            { "General", "Colours", "SecondaryPower", entry[1] }, RefreshAll, true, { disabled = disabled })
    end
    for _, runeType in ipairs({ "FROST", "UNHOLY", "BLOOD" }) do
        local label = runeType:sub(1, 1) .. runeType:sub(2):lower()
        PathColor(controls, section, label .. " Rune", ProfileRoot,
            { "General", "Colours", "SecondaryPower", "RUNES", runeType }, RefreshAll, true, { disabled = disabled })
    end
    for _, state in ipairs({ "LIGHT", "MODERATE", "HEAVY" }) do
        local label = state:sub(1, 1) .. state:sub(2):lower()
        PathColor(controls, section, label .. " Stagger", ProfileRoot,
            { "General", "Colours", "SecondaryPower", "STAGGER_COLOURS", state }, RefreshAll, true, { disabled = disabled })
    end
    U.Buttons(controls, section, {
        { text = L("Reset Resource Colours"), width = 210, click = function()
            BCDM.db.profile.General.Colours.SecondaryPower = BCDM:CopyTable(
                BCDM:GetDefaultDB().profile.General.Colours.SecondaryPower)
            RefreshAll()
            panel:Refresh()
        end },
    }, { disabled = disabled })
end

local function CreateBarPanel(barType)
    local panel, controls = U.NewPanel()
    local RefreshBarHighlight
    local function update()
        if barType == "PowerBar" then BCDM:UpdatePowerBar()
        elseif barType == "SecondaryPowerBar" then BCDM:UpdateSecondaryPowerBar()
        else BCDM:UpdateCastBar() end
        if RefreshBarHighlight then RefreshBarHighlight() end
    end
    local function UnsupportedSecondary()
        return barType == "SecondaryPowerBar" and BCDM:GetCurrentSecondaryResource() == nil
    end
    local function EnabledDisabled() return UnsupportedSecondary() or BCDM.db.profile[barType].Enabled ~= true end
    local function ClassColour()
        local colour = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        return colour and { colour.r, colour.g, colour.b, 1 } or { 1, 1, 1, 1 }
    end
    local function CustomColour() return BCDM.db.profile[barType].ForegroundColour end
    local function SetCustomColour(colour)
        BCDM.db.profile[barType].ForegroundColour = colour
        update()
    end
    local function PowerTypeColour()
        local colours = BCDM.db.profile.General.Colours
        if barType == "PowerBar" then
            return colours.PrimaryPower[UnitPowerType("player")] or CustomColour()
        end
        local descriptor = BCDM:GetCurrentSecondaryResource()
        local colour = descriptor and colours.SecondaryPower[descriptor.key]
        if not colour and descriptor and descriptor.powerType == Enum.PowerType.Mana then
            colour = colours.PrimaryPower[Enum.PowerType.Mana]
        end
        return colour or CustomColour()
    end
    local function SpecializationColour()
        local descriptor = BCDM:GetCurrentSecondaryResource()
        local runeColours = BCDM.db.profile.General.Colours.SecondaryPower.RUNES
        return descriptor and descriptor.runeColourKey and runeColours[descriptor.runeColourKey] or PowerTypeColour()
    end
    local function ColourModeChoices()
        local choices = {
            { text = "Custom", value = "CUSTOM", getColor = CustomColour, setColor = SetCustomColour, editColor = true,
                description = "Use and edit the bar's custom fill colour." },
            { text = "Class", value = "CLASS", getColor = ClassColour },
        }
        if barType == "CastBar" then
            choices[#choices + 1] = {
                text = "Cast State", value = "INTERRUPTIBILITY",
                getColor = function() return BCDM.db.profile.CastBar.InterruptibleColour end,
                getSecondColor = function() return BCDM.db.profile.CastBar.NonInterruptibleColour end,
                description = "Use separate colours for interruptible and non-interruptible casts.",
            }
        elseif not UnsupportedSecondary() then
            choices[#choices + 1] = { text = "Power Type", value = "POWER_TYPE", getColor = PowerTypeColour }
            if barType == "SecondaryPowerBar" and BCDM.IS_DEATHKNIGHT then
                choices[#choices + 1] = { text = "Specialization", value = "SPECIALIZATION", getColor = SpecializationColour }
            end
        end
        return choices
    end

    local behavior = U.Section(controls, "Toggles & Colours", true)
    if barType == "SecondaryPowerBar" then
        U.Text(controls, behavior, "No supported secondary resource for this specialization.", {
            hidden = function() return not UnsupportedSecondary() end,
        })
    end
    PathCheckbox(controls, behavior, "Enable " .. (barType == "CastBar" and "Cast Bar" or barType == "PowerBar" and "Power Bar" or "Secondary Power Bar"),
        ProfileRoot, { barType, "Enabled" }, barType == "CastBar" and function() BCDM:PromptReload() end or update,
        { disabled = UnsupportedSecondary })
    local getColourMode, setColourMode = U.Access(ProfileRoot, { barType, "ColourMode" }, update)
    U.ColorChoices(controls, behavior, "Fill Colour", getColourMode, setColourMode, ColourModeChoices, {
            disabled = EnabledDisabled,
        })
    if barType ~= "CastBar" then
        PathCheckbox(controls, behavior, "Show Spark", ProfileRoot,
            { barType, "ShowSpark" }, update, { disabled = EnabledDisabled })
    end
    PathDropdown(controls, behavior, "Fill Direction", ProfileRoot,
        { barType, "FillDirection" }, update, function()
            return { { text = "Right", value = "RIGHT" }, { text = "Left", value = "LEFT" } }
        end, { disabled = EnabledDisabled })
    PathCheckbox(controls, behavior, "Match Width Of Anchor", ProfileRoot,
        { barType, "MatchWidthOfAnchor" }, update, { disabled = EnabledDisabled })
    if barType == "SecondaryPowerBar" then
        PathCheckbox(controls, behavior, "Hide Ticks", ProfileRoot,
            { barType, "HideTicks" }, update, { disabled = EnabledDisabled })
        if BCDM.IS_MONK then
            PathCheckbox(controls, behavior, "Colour by Stagger", ProfileRoot,
                { barType, "ColourByState" }, update, { disabled = EnabledDisabled })
            PathCheckbox(controls, behavior, "Stagger Damage Per Second", ProfileRoot,
                { barType, "Text", "ShowStaggerDPS" }, update, { disabled = EnabledDisabled })
        end
        PathCheckbox(controls, behavior, "Swap To Power Bar Position", ProfileRoot,
            { barType, "SwapToPowerBarPosition" }, update, {
                disabled = function() return EnabledDisabled() or not BCDM:CanSwapSecondaryResourceToPrimary() end,
                description = L("Automatically uses the primary power bar position when appropriate."),
            })
    end
    PathColor(controls, behavior, "Background Colour", ProfileRoot,
        { barType, "BackgroundColour" }, update, true, { disabled = EnabledDisabled })
    if barType == "CastBar" then
        PathColor(controls, behavior, "Interruptible Colour", ProfileRoot,
            { "CastBar", "InterruptibleColour" }, update, true, { disabled = function()
                return EnabledDisabled() or BCDM.db.profile.CastBar.ColourMode ~= "INTERRUPTIBILITY"
            end })
        PathColor(controls, behavior, "Non-Interruptible Colour", ProfileRoot,
            { "CastBar", "NonInterruptibleColour" }, update, true, { disabled = function()
                return EnabledDisabled() or BCDM.db.profile.CastBar.ColourMode ~= "INTERRUPTIBILITY"
            end })
        PathColor(controls, behavior, "Empower Pip Colour", ProfileRoot,
            { "CastBar", "EmpowerPips", "Colour" }, update, true, { disabled = EnabledDisabled })
        PathSlider(controls, behavior, "Empower Pip Width", ProfileRoot,
            { "CastBar", "EmpowerPips", "Width" }, update,
            { min = 1, max = 8, step = 1, disabled = EnabledDisabled })
        U.Buttons(controls, behavior, {
            { text = "Normal Test", width = 130, disabled = EnabledDisabled, click = function()
                BCDM.CAST_BAR_TEST_STATE = "NORMAL" BCDM:CreateTestCastBar()
            end },
            { text = "Uninterruptible Test", width = 160, disabled = function()
                return EnabledDisabled() or BCDM.db.profile.CastBar.ColourMode ~= "INTERRUPTIBILITY"
            end, click = function()
                BCDM.CAST_BAR_TEST_STATE = "NON_INTERRUPTIBLE" BCDM:CreateTestCastBar()
            end },
            { text = "Empowered Test", width = 130, disabled = EnabledDisabled, click = function()
                BCDM.CAST_BAR_TEST_STATE = "EMPOWERED" BCDM:CreateTestCastBar()
            end },
        })
    end

    BCDM:AddVisibilityPolicySettings(panel, controls, "Visibility", ProfileRoot,
        { barType, "Visibility" }, { barType, "UseSharedVisibility" }, update, UnsupportedSecondary)

    if barType == "PowerBar" then
        AddPrimaryPowerColours(panel, controls)
    elseif barType == "SecondaryPowerBar" then
        AddSecondaryPowerColours(panel, controls, UnsupportedSecondary)
    end

    local layout = U.Section(controls, "Layout & Positioning", true)
    PathDropdown(controls, layout, "Anchor From", ProfileRoot,
        { barType, "Layout", 1 }, update, function() return ANCHOR_POINTS end, { disabled = EnabledDisabled })
    local anchorType = barType == "SecondaryPowerBar" and "SecondaryPower" or barType
    PathDropdown(controls, layout, "Anchor Parent", ProfileRoot,
        { barType, "Layout", 2 }, update, AnchorValues(anchorType), { disabled = EnabledDisabled, maxHeight = 420 })
    PathDropdown(controls, layout, "Anchor To", ProfileRoot,
        { barType, "Layout", 3 }, update, function() return ANCHOR_POINTS end, { disabled = EnabledDisabled })
    PathSlider(controls, layout, "Width", ProfileRoot,
        { barType, "Width" }, update, { min = 50, max = 3000, step = 0.1, disabled = function()
            return EnabledDisabled() or BCDM.db.profile[barType].MatchWidthOfAnchor == true
        end })
    PathSlider(controls, layout, "Height", ProfileRoot,
        { barType, "Height" }, update, { min = 5, max = 500, step = 0.1, disabled = EnabledDisabled })
    if barType == "PowerBar" then
        PathSlider(controls, layout, "Height (No Secondary Bar)", ProfileRoot,
            { barType, "HeightWithoutSecondary" }, update, { min = 5, max = 500, step = 0.1, disabled = EnabledDisabled })
    elseif barType == "SecondaryPowerBar" then
        PathSlider(controls, layout, "Height (No Primary Bar)", ProfileRoot,
            { barType, "HeightWithoutPrimary" }, update, { min = 5, max = 500, step = 0.1, disabled = function()
                return EnabledDisabled() or BCDM.db.profile.SecondaryPowerBar.SwapToPowerBarPosition ~= true
            end })
    end
    PathSlider(controls, layout, "X Offset", ProfileRoot,
        { barType, "Layout", 4 }, update, { min = -3000, max = 3000, step = 0.1, disabled = EnabledDisabled })
    PathSlider(controls, layout, "Y Offset", ProfileRoot,
        { barType, "Layout", 5 }, update, { min = -3000, max = 3000, step = 0.1, disabled = EnabledDisabled })
    PathDropdown(controls, layout, "Frame Strata", ProfileRoot,
        { barType, "FrameStrata" }, update, function() return FRAME_STRATA end, { disabled = EnabledDisabled })

    if barType == "CastBar" then
        local icon = U.Section(controls, "Icon Settings", true)
        PathCheckbox(controls, icon, "Enable Cast Icon", ProfileRoot,
            { "CastBar", "Icon", "Enabled" }, update, { disabled = EnabledDisabled })
        PathDropdown(controls, icon, "Icon Position", ProfileRoot,
            { "CastBar", "Icon", "Layout" }, update, function()
                return { { text = L("Left"), value = "LEFT" }, { text = L("Right"), value = "RIGHT" } }
            end, { disabled = function() return EnabledDisabled() or BCDM.db.profile.CastBar.Icon.Enabled ~= true end })
    end

    local text = U.Section(controls, "Text Settings", true)
    if barType ~= "CastBar" then
        PathCheckbox(controls, text, "Enable Power Text", ProfileRoot,
            { barType, "Text", "Enabled" }, update, { disabled = EnabledDisabled })
        local function TextDisabled()
            return EnabledDisabled() or BCDM.db.profile[barType].Text.Enabled ~= true
        end
        PathDropdown(controls, text, "Text Mode", ProfileRoot,
            { barType, "Text", "Mode" }, update, function()
                return {
                    { text = "Automatic", value = "AUTO" },
                    { text = "Current", value = "CURRENT" },
                    { text = "Current / Maximum", value = "CURRENT_MAX" },
                    { text = "Percent", value = "PERCENT" },
                }
            end, { disabled = TextDisabled })
        PathDropdown(controls, text, "Anchor From", ProfileRoot,
            { barType, "Text", "Layout", 1 }, update, function() return ANCHOR_POINTS end, { disabled = TextDisabled })
        PathDropdown(controls, text, "Anchor To", ProfileRoot,
            { barType, "Text", "Layout", 2 }, update, function() return ANCHOR_POINTS end, { disabled = TextDisabled })
        PathSlider(controls, text, "X Offset", ProfileRoot,
            { barType, "Text", "Layout", 3 }, update, { min = -500, max = 500, step = 0.1, disabled = TextDisabled })
        PathSlider(controls, text, "Y Offset", ProfileRoot,
            { barType, "Text", "Layout", 4 }, update, { min = -500, max = 500, step = 0.1, disabled = TextDisabled })
        PathSlider(controls, text, "Font Size", ProfileRoot,
            { barType, "Text", "FontSize" }, update, { min = 6, max = 72, step = 1, disabled = TextDisabled })
        PathColor(controls, text, "Font Colour", ProfileRoot,
            { barType, "Text", "Colour" }, update, false, { disabled = TextDisabled })
    else
        for _, textType in ipairs({ "SpellName", "CastTime" }) do
            U.Subsection(controls, text, textType == "SpellName" and "Spell Name" or "Cast Time")
            PathDropdown(controls, text, "Anchor From", ProfileRoot,
                { "CastBar", "Text", textType, "Layout", 1 }, update, function() return ANCHOR_POINTS end, { disabled = EnabledDisabled })
            PathDropdown(controls, text, "Anchor To", ProfileRoot,
                { "CastBar", "Text", textType, "Layout", 2 }, update, function() return ANCHOR_POINTS end, { disabled = EnabledDisabled })
            PathSlider(controls, text, "X Offset", ProfileRoot,
                { "CastBar", "Text", textType, "Layout", 3 }, update, { min = -500, max = 500, step = 0.1, disabled = EnabledDisabled })
            PathSlider(controls, text, "Y Offset", ProfileRoot,
                { "CastBar", "Text", textType, "Layout", 4 }, update, { min = -500, max = 500, step = 0.1, disabled = EnabledDisabled })
            PathSlider(controls, text, "Font Size", ProfileRoot,
                { "CastBar", "Text", textType, "FontSize" }, update, { min = 6, max = 72, step = 1, disabled = EnabledDisabled })
            PathColor(controls, text, "Colour", ProfileRoot,
                { "CastBar", "Text", textType, "Colour" }, update, false, { disabled = EnabledDisabled })
            if textType == "SpellName" then
                PathSlider(controls, text, "Max Characters", ProfileRoot,
                    { "CastBar", "Text", "SpellName", "MaxCharacters" }, update,
                    { min = 0, max = 100, step = 1, disabled = EnabledDisabled })
            end
        end
        function panel:OnSettingsActivated()
            BCDM.CAST_BAR_TEST_MODE = true
            BCDM:CreateTestCastBar()
        end
        function panel:OnSettingsDeactivated()
            BCDM.CAST_BAR_TEST_MODE = false
            BCDM:CreateTestCastBar()
        end
        panel:HookScript("OnShow", panel.OnSettingsActivated)
        panel:HookScript("OnHide", panel.OnSettingsDeactivated)
    end

    DisableSectionsWhen(controls, 2, EnabledDisabled)

    if barType == "PowerBar" or barType == "SecondaryPowerBar" or barType == "CastBar" then
        local highlightKey = barType .. "SettingsOverlay"
        RefreshBarHighlight = function()
            local target = barType == "PowerBar" and BCDM.PowerBar
                or barType == "SecondaryPowerBar" and BCDM.SecondaryPowerBar
                or BCDM.CastBar
            if not panel:IsShown() or EnabledDisabled() or not target then
                BCDM:HideSettingsHighlight(highlightKey)
                return
            end
            BCDM:ShowSettingsHighlight(highlightKey, target)
        end
        panel.RefreshSettingsHighlight = RefreshBarHighlight
        panel:HookScript("OnShow", RefreshBarHighlight)
        panel:HookScript("OnHide", function() BCDM:HideSettingsHighlight(highlightKey) end)
    end

    return panel
end

function BCDM:RefreshSettings()
    for _, panel in ipairs(panels) do
        if type(panel.Refresh) == "function" then panel:Refresh() end
        if type(panel.RefreshSettingsHighlight) == "function" then panel:RefreshSettingsHighlight() end
    end
    if BCDMG and type(BCDMG.RefreshProfiles) == "function" then BCDMG.RefreshProfiles() end
end

function BCDM:GetSettingsPanels()
    return panelEntries
end

function BCDM:RegisterSettings()
    if initialized or type(Settings) ~= "table" then return end
    initialized = true

    BCDMG:AddAnchors("ElvUI", { "Utility", "CustomTrackers", "Trinket" }, {
        ElvUF_Player = "|cff1784d1ElvUI|r: Player Frame",
        ElvUF_Target = "|cff1784d1ElvUI|r: Target Frame",
    })

    rootCategory = RegisterPanel(nil, "Better Cooldown Manager", CreateGeneralPanel(), true)
    for _, viewer in ipairs({
        { "Essential", "Essential Cooldowns" }, { "Utility", "Utility Cooldowns" }, { "Buffs", "Tracked Buffs" },
        { "Trinket", "Trinkets" },
    }) do
        RegisterPanel(rootCategory, viewer[2], CreateViewerPanel(viewer[1]))
        if viewer[1] == "Buffs" then
            RegisterPanel(rootCategory, "Tracked Bars", CreateTrackedBarsPanel())
        end
    end
    RegisterPanel(rootCategory, "Custom Trackers", CreateCustomTrackersPanel())
    RegisterPanel(rootCategory, "Power Bar", CreateBarPanel("PowerBar"))
    RegisterPanel(rootCategory, "Secondary Power Bar", CreateBarPanel("SecondaryPowerBar"))
    RegisterPanel(rootCategory, "Cast Bar", CreateBarPanel("CastBar"))
    if type(BCDM.RegisterProfilesSettings) == "function" then
        local profilesPanel = BCDM:RegisterProfilesSettings(rootCategory)
        if profilesPanel then
            panels[#panels + 1] = profilesPanel
            panelEntries[#panelEntries + 1] = { name = L("Profiles"), panel = profilesPanel }
        end
    end

    rootCategoryID = rootCategory and rootCategory.GetID and rootCategory:GetID() or nil
end

function BCDM:OpenBlizzardSettings()
    if not initialized then self:RegisterSettings() end
    if type(self.CloseSettings) == "function" then self:CloseSettings() end
    if rootCategoryID and type(Settings) == "table" then Settings.OpenToCategory(rootCategoryID) end
end
