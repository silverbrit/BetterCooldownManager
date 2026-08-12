local _, BCDM = ...

local WINDOW_NAME = "BetterCooldownManagerSettingsWindow"
local DEFAULT_WIDTH = 1180
local DEFAULT_HEIGHT = 760
local MIN_WIDTH = 900
local MIN_HEIGHT = 600
local NAV_WIDTH = 230
local FOOTER_HEIGHT = 34

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
    return BCDM.db.global.SettingsWindow
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
    frame:SetBackdropColor(0.035, 0.035, 0.035, 0.72)
    frame:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.9)
    RestoreWindowGeometry(frame)

    frame.TitleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.TitleBar:SetPoint("TOPLEFT", 1, -1)
    frame.TitleBar:SetPoint("TOPRIGHT", -1, -1)
    frame.TitleBar:SetHeight(48)
    frame.TitleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.TitleBar:SetBackdropColor(0.015, 0.015, 0.015, 0.82)
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
    frame.Navigation:SetBackdropColor(0.02, 0.02, 0.02, 0.5)
    frame.Navigation:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.8)

    frame.NavigationContent = CreateFrame("Frame", nil, frame.Navigation)
    frame.NavigationContent:SetPoint("TOPLEFT", 8, -8)
    frame.NavigationContent:SetPoint("BOTTOMRIGHT", -8, 8)

    frame.Content = CreateFrame("Frame", nil, frame)
    frame.Content:SetPoint("TOPLEFT", frame.Navigation, "TOPRIGHT", 14, 0)
    frame.Content:SetPoint("BOTTOMRIGHT", -18, FOOTER_HEIGHT + 12)

    frame.Footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Footer:SetPoint("BOTTOMLEFT", 1, 1)
    frame.Footer:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.Footer:SetHeight(FOOTER_HEIGHT)
    frame.Footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame.Footer:SetBackdropColor(0.015, 0.015, 0.015, 0.82)

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

    frame:SetScript("OnShow", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            if type(HideUIPanel) == "function" then HideUIPanel(SettingsPanel)
            else SettingsPanel:Hide() end
        end
        local selectedEntry = frame.Entries[1]
        for _, entry in ipairs(frame.Entries) do
            if entry.name == selectedPanelName then selectedEntry = entry break end
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
