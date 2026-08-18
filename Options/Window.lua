local _, BCDM = ...

local U = BCDM.SettingsUtils

local WINDOW_NAME = "BetterCooldownManagerSettingsWindow"
local DEFAULT_WIDTH = 1180
local DEFAULT_HEIGHT = 760
local MIN_WIDTH = 900
local MIN_HEIGHT = 600
local NAV_WIDTH = 230
local FOOTER_HEIGHT = 34
local NAV_FOOTER_HEIGHT = 42
local DEFAULT_WINDOW_OPACITY = 0.72
local OPACITY_SETTINGS_VERSION = 2
local MIN_WINDOW_OPACITY = 0.5
local MAX_WINDOW_OPACITY = 1

local settingsWindow
local selectedPanelName

local function DisplayVersion()
    local version = tostring(BCDM.ADDON_VERSION or "")
    if version == "" or version:find("@project%-version@") then return "Development" end
    if version:match("^[vV]") then return version end
    return "v" .. version
end

local function WindowSettings()
    BCDM.db.global.SettingsWindow = BCDM.db.global.SettingsWindow or {}
    local settings = BCDM.db.global.SettingsWindow
    if settings.OpacityVersion ~= OPACITY_SETTINGS_VERSION then
        settings.Opacity = DEFAULT_WINDOW_OPACITY
        settings.OpacityVersion = OPACITY_SETTINGS_VERSION
    end
    return settings
end

-- CHANGELOG.md is canonical; WoW cannot read Markdown at runtime, so keep this
-- packaged copy synchronized when the source changelog changes.
local CHANGELOG_TEXT = [[
# Changelog

## Unreleased

### Settings

- Added a bottom-left Changelog page sourced from this file and a title-bar opacity slider that preserves the original default transparency while making 100% fully opaque.
- Replaced the AceGUI configuration window with a draggable, resizable Better Cooldown Manager window powered by LibSharedCanvas-1.0, while retaining access through Blizzard's AddOns Settings.
- Added dedicated categories for individual cooldown viewers, power bars, the cast bar, and profiles, with all sections expanded by default.
- Reorganized settings by scope: shared appearance options remain on the main page, viewer-specific options live with their viewer, resource colours live with their respective power bars, and Edit Mode layout routing now lives under Profiles.
- Removed the redundant Cooldown Viewers category and moved native viewer skinning, icon zoom, cooldown text, and custom glow settings to General according to their actual scope.
- Blizzard's Cooldown Manager now opens automatically to the matching Spells or Buffs tab when Essential Cooldowns, Utility Cooldowns, or Tracked Buffs is selected in the standalone settings window.
- Removed redundant or empty settings groups and simplified category navigation.
- Added compact, typeable numeric fields to every slider.
- Added LibSharedMedia font previews and status-bar texture swatches.
- Added a persistent Community & Support footer and installed version display to the addon-owned settings window.
- Added the Better Cooldown Manager logo beside the settings-window title.
- Removed obsolete Apply Size Changes controls and misleading Edit Mode refresh guidance.
- Standardized profile-scoped General settings on Shared terminology and renamed the Buff Icons category to Tracked Buffs.
- Added a dedicated Tracked Bars settings page recommending Better Tracked Bars.
- The standalone Tracked Bars page now embeds Better Tracked Bars settings when the compatible optional addon is installed and enabled.
- Added location highlights for the trinket viewer and selected custom tracker bar, including empty-bar footprints.
- Added selected-element highlights for resource and cast bars, a global highlight toggle, and consistent disabled-section treatment for their settings pages.
- Trinket Viewer now includes passive trinkets by default, offers an on-use-only filter, and displays active-aura stacks from 12.1 equip-slot aura metadata.
- Added an equipped-trinket selector, live Settings preview, shared entry behavior, and optional per-slot overrides matching Custom Trackers.
- Added drag ordering for equipped trinket slots and applied the saved order to the runtime bar.
- Standardized Custom Tracker and Trinket settings icon sizing and cropping, and removed Blizzard's cooldown bling border from the runtime Trinket Viewer.
- Fixed custom tracker and trinket location highlights lagging behind section changes or using offset container bounds.
- Fixed custom tracker corner anchors drifting by half the bar size because icon layout started at the container center.
- Tightened profile-management spacing and aligned the first Settings section with the navigation panel.
- Clarified cast and secondary-resource controls by hiding unsupported colour choices and renaming the non-interruptible cast test.

### Cooldown Viewers and Profiles

- Migrated the existing viewer layout, anchoring, icon, text, glow, spell, item, ordering, and load-condition controls to the new Settings interface.
- Added shared visibility policies with optional per-bar overrides for BCM-owned custom tracker, trinket, resource, and cast bars.

### Custom Trackers

- Replaced separate Custom Cooldowns and Additional Custom configurations with named, duplicable mixed-source tracker bars.
- Replaced the dense entry rows with a scrollable icon strip, drag ordering, focused selected-entry controls, and a type-aware add menu.
- Added per-bar Custom Tracker icon dimensions and charge, stack, and item-count text settings.
- Added live Custom Tracker Settings previews for configured entries, including appearance, glow, text, and entries currently filtered or unavailable.
- Added shared Custom Tracker display, appearance, glow, text, tooltip, class, and specialization settings with opt-in per-entry overrides, and real bag counts in the entry editor.
- Split shared entry defaults into their own collapsible section and added item/spell drag-and-drop onto the entry list's + button.
- Added lossless profile migration for legacy spell, item, and item-spell trackers, including specialization filters and anchor remapping.
- Added equipment-slot cooldown and fixed-duration spellcast timer sources.
- Added per-entry ready/active display rules, inactive appearance, glow state, tooltips, and class/specialization filters.
- Added Retail 12.1 AuraContainer presentation for active player and target spell auras, including optional extra aura IDs and automatic cooldown fallback.
- Removed the dormant BuffBar implementation and settings.

### Cast and Resource Bars

- Fixed Power Bar anchor-parent selection and secret-safe resource text rendering.
- Added fill direction, optional sparks, and current/maximum/percent text modes.
- Reworked the trinket viewer around persistent equipment-slot icons, asynchronous item loading, and slot cooldown events.
- Added interruptible and non-interruptible cast colours, configurable empowered-stage pips, fill direction, and richer Settings previews.

### Development

- Removed unused media assets and moved direct library loading from `Libraries/Init.xml` into the addon TOC.
- Added a modular Options implementation built around the externally maintained LibSharedCanvas-1.0.
- Removed the AceGUI, AceDBOptions, and unused SharedMedia widget dependencies.
- Added `install-deps.sh` for refreshing vendored libraries.
- Updated packaging configuration to include only the required libraries.
- Added Retail 12.1 Blizzard UI source installation, pure-Lua model tests, and repository-local Codex architecture guidance.
- Removed the legacy Disable Aura Overlay hooks and manual aura/cooldown reconstruction.
- Replaced continuous Buff Icon centering polling with coalesced Blizzard layout and shown-state hooks.
]]

local function ClampWindowOpacity(value)
    value = tonumber(value) or DEFAULT_WINDOW_OPACITY
    return math.max(MIN_WINDOW_OPACITY, math.min(MAX_WINDOW_OPACITY, value))
end

local function GetWindowOpacity()
    return ClampWindowOpacity(WindowSettings().Opacity)
end

local function SaveWindowGeometry(frame)
    if not BCDM.db then return end
    local settings = WindowSettings()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    settings.Point = point or "CENTER"
    settings.RelativePoint = relativePoint or "CENTER"
    settings.X = x or 0
    settings.Y = y or 0
    settings.Width = frame:GetWidth()
    settings.Height = frame:GetHeight()
end

local function RestoreWindowGeometry(frame)
    local settings = WindowSettings()
    frame:ClearAllPoints()
    frame:SetPoint(settings.Point or "CENTER", UIParent, settings.RelativePoint or "CENTER", settings.X or 0, settings.Y or 0)
    frame:SetSize(math.max(MIN_WIDTH, settings.Width or DEFAULT_WIDTH), math.max(MIN_HEIGHT, settings.Height or DEFAULT_HEIGHT))
end

local function SetButtonSelected(button, selected)
    button.Selected:SetShown(selected)
    button.Text:SetTextColor(selected and 1 or 0.9, selected and 0.82 or 0.9, selected and 0 or 0.9)
end

local function DetachPanel(panel)
    if not panel then return end
    BCDM:HideAllSettingsHighlights()
    if type(panel.OnSettingsDeactivated) == "function" then panel:OnSettingsDeactivated() end
    panel:Hide()
    panel:ClearAllPoints()
    panel:SetParent(UIParent)
end

local function SelectPanel(frame, entry)
    if not entry or frame.ActiveEntry == entry then
        if entry and type(entry.panel.Refresh) == "function" then entry.panel:Refresh() end
        if entry and type(entry.panel.OnSettingsActivated) == "function" then
            entry.panel:OnSettingsActivated()
        end
        if entry and type(entry.panel.RefreshSettingsHighlight) == "function" then
            entry.panel:RefreshSettingsHighlight()
        end
        if entry and type(entry.panel.OnStandaloneSettingsActivated) == "function" then
            entry.panel:OnStandaloneSettingsActivated()
        end
        return
    end

    if frame.ActiveEntry then
        SetButtonSelected(frame.ActiveEntry.button, false)
        DetachPanel(frame.ActiveEntry.panel)
    end

    frame.ActiveEntry = entry
    selectedPanelName = entry.name
    SetButtonSelected(entry.button, true)

    local panel = entry.panel
    panel:SetParent(frame.Content)
    panel:ClearAllPoints()
    panel:SetAllPoints(frame.Content)
    panel:Show()
    if type(panel.OnSettingsActivated) == "function" then panel:OnSettingsActivated() end
    if type(panel.Refresh) == "function" then panel:Refresh() end
    if type(panel.RefreshSettingsHighlight) == "function" then panel:RefreshSettingsHighlight() end
    if type(panel.OnStandaloneSettingsActivated) == "function" then
        panel:OnStandaloneSettingsActivated()
    end
end

local function CreateNavigationButton(parent, entry, previousButton)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(31)
    button:SetPoint("LEFT", 0, 0)
    button:SetPoint("RIGHT", 0, 0)
    if previousButton then button:SetPoint("TOP", previousButton, "BOTTOM", 0, -2)
    else button:SetPoint("TOP", 0, -4) end

    button.Selected = button:CreateTexture(nil, "BACKGROUND")
    button.Selected:SetAllPoints()
    button.Selected:SetColorTexture(1, 0.82, 0, 0.13)
    button.Selected:Hide()

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.07)

    button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    button.Text:SetPoint("LEFT", 14, 0)
    button.Text:SetPoint("RIGHT", -8, 0)
    button.Text:SetJustifyH("LEFT")
    button.Text:SetWordWrap(false)
    button.Text:SetText(entry.name)
    SetButtonSelected(button, false)
    return button
end

local function AddChangelogLine(controls, section, text)
    local row = U.Text(controls, section, "• " .. text)
    row.Text:ClearAllPoints()
    row.Text:SetPoint("TOPLEFT")
    row.Text:SetJustifyV("TOP")
    row.Text:SetWordWrap(true)
    local baseRefresh = row.Refresh
    function row:Refresh()
        baseRefresh(self)
        local width = controls.scrollFrame:GetWidth()
        if type(width) == "number" and width > 0 then
            self.Text:SetWidth(math.max(1, width - 48))
        end
        self:SetHeight(math.max(24, (self.Text:GetStringHeight() or 14) + 4))
    end
    return row
end

local function CreateChangelogPanel()
    local panel, controls = U.NewPanel()
    local section
    for line in CHANGELOG_TEXT:gmatch("[^\r\n]+") do
        local hashes, heading = line:match("^(#+)%s+(.+)$")
        if hashes and #hashes == 2 then
            section = U.Section(controls, heading, true)
        elseif hashes and #hashes == 3 and section then
            U.Subsection(controls, section, heading)
        elseif section and line:match("^%- ") then
            AddChangelogLine(controls, section, line:sub(3))
        end
    end
    panel:Hide()
    return panel
end

local function CreateOpacitySlider(parent, frame)
    local slider = CreateFrame("Frame", nil, parent)
    slider:SetSize(96, 16)
    slider:SetPoint("RIGHT", frame.CloseButton, "LEFT", -8, 0)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(2)
    track:SetPoint("LEFT", 6, 0)
    track:SetPoint("RIGHT", -6, 0)
    track:SetColorTexture(1, 1, 1, 0.1)

    local thumb = CreateFrame("Button", nil, slider)
    thumb:SetSize(12, 10)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetColorTexture(1, 0.82, 0, 0.8)

    local function SetOpacity(alpha)
        alpha = ClampWindowOpacity(alpha)
        WindowSettings().Opacity = alpha
        frame:SetAlpha(1)

        local scale
        if alpha < DEFAULT_WINDOW_OPACITY then
            scale = alpha / DEFAULT_WINDOW_OPACITY
        else
            scale = 1 + (alpha - DEFAULT_WINDOW_OPACITY) / (MAX_WINDOW_OPACITY - DEFAULT_WINDOW_OPACITY)
        end
        local function BackdropAlpha(base)
            if alpha < DEFAULT_WINDOW_OPACITY then return base * scale end
            return base + (1 - base) * (scale - 1)
        end
        frame:SetBackdropColor(0.035, 0.035, 0.035, BackdropAlpha(0.72))
        frame.TitleBar:SetBackdropColor(0.015, 0.015, 0.015, BackdropAlpha(0.82))
        frame.Navigation:SetBackdropColor(0.02, 0.02, 0.02, BackdropAlpha(0.5))
        frame.Footer:SetBackdropColor(0.015, 0.015, 0.015, BackdropAlpha(0.82))

        local fraction = (alpha - MIN_WINDOW_OPACITY) / (MAX_WINDOW_OPACITY - MIN_WINDOW_OPACITY)
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", fraction * track:GetWidth(), 0)
    end

    local function ReadCursorOpacity()
        local cursorX = GetCursorPosition()
        local scale = slider:GetEffectiveScale()
        local left = track:GetLeft()
        local width = track:GetWidth()
        if not scale or not left or not width or width <= 0 then return end
        local fraction = (cursorX / scale - left) / width
        return MIN_WINDOW_OPACITY + math.max(0, math.min(1, fraction))
            * (MAX_WINDOW_OPACITY - MIN_WINDOW_OPACITY)
    end

    local dragging
    local function StopDragging()
        dragging = false
        thumb:SetScript("OnUpdate", nil)
    end
    local function StartDragging()
        dragging = true
        thumb:SetScript("OnUpdate", function()
            if dragging then
                local alpha = ReadCursorOpacity()
                if alpha then SetOpacity(alpha) end
            end
        end)
        local alpha = ReadCursorOpacity()
        if alpha then SetOpacity(alpha) end
    end

    thumb:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartDragging() end
    end)
    thumb:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopDragging() end
    end)

    local trackButton = CreateFrame("Button", nil, slider)
    trackButton:SetAllPoints()
    trackButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartDragging() end
    end)
    trackButton:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopDragging() end
    end)

    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        SetOpacity(GetWindowOpacity() + delta * 0.05)
    end)
    slider:SetScript("OnShow", function()
        SetOpacity(GetWindowOpacity())
    end)
    SetOpacity(GetWindowOpacity())
    return slider
end

local function CreateSupportButton(parent, previousButton, text, icon, popupTitle, url, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 120, 26)
    button:SetPoint("LEFT", previousButton or parent.Label, "RIGHT", previousButton and 6 or 14, 0)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    button.Text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    button.Text:SetPoint("CENTER")
    button.Text:SetText(string.format("|T%s:18:18|t %s", icon, text))
    button:SetScript("OnClick", function() BCDM:OpenURL(popupTitle, url) end)
    button:SetScript("OnEnter", function() button.Text:SetTextColor(1, 0.82, 0) end)
    button:SetScript("OnLeave", function() button.Text:SetTextColor(1, 1, 1) end)
    return button
end

local function CreateSettingsWindow()
    if settingsWindow then return settingsWindow end

    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if type(frame.SetResizeBounds) == "function" then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 1600, 1000)
    else
        frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        frame:SetMaxResize(1600, 1000)
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.035, 0.035, 0.035, 1)
    frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.9)
    RestoreWindowGeometry(frame)
    frame:SetAlpha(1)

    frame.TitleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.TitleBar:SetPoint("TOPLEFT", 1, -1)
    frame.TitleBar:SetPoint("TOPRIGHT", -1, -1)
    frame.TitleBar:SetHeight(48)
    frame.TitleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.TitleBar:SetBackdropColor(0.015, 0.015, 0.015, 1)
    frame.TitleBar:EnableMouse(true)
    frame.TitleBar:RegisterForDrag("LeftButton")
    frame.TitleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.TitleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveWindowGeometry(frame)
    end)

    frame.Logo = frame.TitleBar:CreateTexture(nil, "ARTWORK")
    frame.Logo:SetPoint("LEFT", 16, 0)
    frame.Logo:SetSize(30, 30)
    frame.Logo:SetTexture("Interface\\AddOns\\BetterCooldownManager\\Media\\Logo.png")

    frame.Title = frame.TitleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.Title:SetPoint("LEFT", frame.Logo, "RIGHT", 8, 0)
    frame.Title:SetText("Better Cooldown Manager")
    frame.Title:SetTextColor(1, 0.82, 0)

    frame.Version = frame.TitleBar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.Version:SetPoint("LEFT", frame.Title, "RIGHT", 10, -1)
    frame.Version:SetText(DisplayVersion())
    frame.Version:SetTextColor(0.58, 0.6, 0.68)

    frame.CloseButton = CreateFrame("Button", nil, frame.TitleBar, "UIPanelCloseButton")
    frame.CloseButton:SetPoint("RIGHT", -5, 0)
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)

    frame.Navigation = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Navigation:SetPoint("TOPLEFT", 12, -60)
    frame.Navigation:SetPoint("BOTTOMLEFT", 12, FOOTER_HEIGHT + 12)
    frame.Navigation:SetWidth(NAV_WIDTH)
    frame.Navigation:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.Navigation:SetBackdropColor(0.02, 0.02, 0.02, 1)
    frame.Navigation:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.8)

    frame.NavigationContent = CreateFrame("Frame", nil, frame.Navigation)
    frame.NavigationContent:SetPoint("TOPLEFT", 8, -8)
    frame.NavigationContent:SetPoint("BOTTOMRIGHT", -8, NAV_FOOTER_HEIGHT + 8)

    frame.NavigationFooter = CreateFrame("Frame", nil, frame.Navigation)
    frame.NavigationFooter:SetPoint("BOTTOMLEFT", 8, 8)
    frame.NavigationFooter:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.NavigationFooter:SetHeight(NAV_FOOTER_HEIGHT - 8)
    local navigationDivider = frame.NavigationFooter:CreateTexture(nil, "ARTWORK")
    navigationDivider:SetPoint("TOPLEFT")
    navigationDivider:SetPoint("TOPRIGHT")
    navigationDivider:SetHeight(1)
    navigationDivider:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    frame.Content = CreateFrame("Frame", nil, frame)
    frame.Content:SetPoint("TOPLEFT", frame.Navigation, "TOPRIGHT", 14, 0)
    frame.Content:SetPoint("BOTTOMRIGHT", -18, FOOTER_HEIGHT + 12)

    frame.Footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Footer:SetPoint("BOTTOMLEFT", 1, 1)
    frame.Footer:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.Footer:SetHeight(FOOTER_HEIGHT)
    frame.Footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.Footer:SetBackdropColor(0.015, 0.015, 0.015, 1)

    frame.Footer.Label = frame.Footer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Footer.Label:SetPoint("LEFT", 14, 0)
    frame.Footer.Label:SetText("Community & Support")
    frame.Footer.Label:SetTextColor(1, 0.82, 0)

    local discord = CreateSupportButton(frame.Footer, nil, "Discord",
        "Interface\\AddOns\\BetterCooldownManager\\Media\\Support\\Discord.png",
        "Better Cooldown Manager Discord", "https://discord.gg/UZCgWRYvVE", 120)
    local github = CreateSupportButton(frame.Footer, discord, "GitHub",
        "Interface\\AddOns\\BetterCooldownManager\\Media\\Support\\GitHub.png",
        "Better Cooldown Manager GitHub", "https://github.com/DaleHuntGB/BetterCooldownManager", 120)
    local twitch = CreateSupportButton(frame.Footer, github, "Twitch",
        "Interface\\AddOns\\BetterCooldownManager\\Media\\Support\\Twitch.png",
        "UnhaltedGB on Twitch", "https://www.twitch.tv/unhaltedgb", 120)
    CreateSupportButton(frame.Footer, twitch, "Support",
        "Interface\\AddOns\\BetterCooldownManager\\Media\\Support\\Ko-Fi.png",
        "Support Better Cooldown Manager", "https://ko-fi.com/unhalted", 130)
    CreateOpacitySlider(frame.TitleBar, frame)

    frame.ResizeButton = CreateFrame("Button", nil, frame)
    frame.ResizeButton:SetSize(20, 20)
    frame.ResizeButton:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.ResizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.ResizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.ResizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.ResizeButton:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    frame.ResizeButton:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SaveWindowGeometry(frame)
        if frame.ActiveEntry and type(frame.ActiveEntry.panel.Refresh) == "function" then frame.ActiveEntry.panel:Refresh() end
    end)

    frame.Entries = BCDM:GetSettingsPanels() or {}
    local previousButton
    for _, entry in ipairs(frame.Entries) do
        entry.button = CreateNavigationButton(frame.NavigationContent, entry, previousButton)
        entry.button:SetScript("OnClick", function() SelectPanel(frame, entry) end)
        previousButton = entry.button
    end

    frame.ChangelogEntry = { name = "Changelog", panel = CreateChangelogPanel() }
    frame.ChangelogEntry.button = CreateNavigationButton(frame.NavigationFooter, frame.ChangelogEntry)
    frame.ChangelogEntry.button:SetHeight(28)
    frame.ChangelogEntry.button:SetScript("OnClick", function()
        SelectPanel(frame, frame.ChangelogEntry)
    end)
    frame:SetScript("OnShow", function()
        frame:SetAlpha(1)
        if SettingsPanel and SettingsPanel:IsShown() then
            if type(HideUIPanel) == "function" then HideUIPanel(SettingsPanel)
            else SettingsPanel:Hide() end
        end
        local selectedEntry = frame.Entries[1]
        if selectedPanelName == frame.ChangelogEntry.name then
            selectedEntry = frame.ChangelogEntry
        else
            for _, entry in ipairs(frame.Entries) do
                if entry.name == selectedPanelName then selectedEntry = entry break end
            end
        end
        SelectPanel(frame, selectedEntry)
    end)
    frame:SetScript("OnHide", function()
        SaveWindowGeometry(frame)
        if frame.ActiveEntry then
            SetButtonSelected(frame.ActiveEntry.button, false)
            DetachPanel(frame.ActiveEntry.panel)
            frame.ActiveEntry = nil
        end
        if BCDM.RetryPendingCooldownViewerLayoutApply then
            BCDM:RetryPendingCooldownViewerLayoutApply()
        end
    end)
    frame:SetScript("OnSizeChanged", function()
        if frame.ActiveEntry and type(frame.ActiveEntry.panel.Refresh) == "function" then frame.ActiveEntry.panel:Refresh() end
    end)

    if SettingsPanel and type(SettingsPanel.HookScript) == "function" then
        SettingsPanel:HookScript("OnShow", function()
            if frame:IsShown() then frame:Hide() end
        end)
    end

    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, WINDOW_NAME) end
    frame:Hide()
    settingsWindow = frame
    return frame
end

function BCDM:OpenSettings()
    if type(self.GetSettingsPanels) ~= "function" or #(self:GetSettingsPanels() or {}) == 0 then self:RegisterSettings() end
    local frame = CreateSettingsWindow()
    frame:Show()
    frame:Raise()
end

function BCDM:CloseSettings()
    if settingsWindow then settingsWindow:Hide() end
end

function BCDM:ToggleSettings()
    if settingsWindow and settingsWindow:IsShown() then self:CloseSettings()
    else self:OpenSettings() end
end

function BCDM:CreateGUI()
    self:ToggleSettings()
end

function BCDMG:OpenBCDMGUI() BCDM:OpenSettings() end
function BCDMG:CloseBCDMGUI() BCDM:CloseSettings() end
