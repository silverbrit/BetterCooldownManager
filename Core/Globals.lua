local _, BCDM = ...
BCDMG = BCDMG or {}

BCDM.IS_DEATHKNIGHT = select(2, UnitClass("player")) == "DEATHKNIGHT"
BCDM.IS_MONK = select(2, UnitClass("player")) == "MONK"

BCDM.CooldownManagerViewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", }

BCDM.CooldownManagerViewerToDBViewer = {
    EssentialCooldownViewer = "Essential",
    UtilityCooldownViewer = "Utility",
    BuffIconCooldownViewer = "Buffs",
}

BCDM.DBViewerToCooldownManagerViewer = {
    Essential = "EssentialCooldownViewer",
    Utility = "UtilityCooldownViewer",
    Buffs = "BuffIconCooldownViewer",
}

BCDM.LSM = LibStub("LibSharedMedia-3.0")
BCDM.LDS = LibStub("LibDualSpec-1.0")
BCDM.LEMO = LibStub("LibEditModeOverride-1.0")

BCDM.ADDON_NAME = C_AddOns.GetAddOnMetadata("BetterCooldownManager", "Title")
BCDM.ADDON_VERSION = C_AddOns.GetAddOnMetadata("BetterCooldownManager", "Version")
BCDM.CAST_BAR_TEST_MODE = false

if BCDM.LSM then BCDM.LSM:Register("statusbar", "Better Blizzard", [[Interface\AddOns\BetterCooldownManager\Media\BetterBlizzard.blp]]) end

function BCDM:PrettyPrint(MSG) print(BCDM.ADDON_NAME .. ":|r " .. MSG) end

function BCDM:ResolveLSM()
    local LSM = BCDM.LSM
    local General = BCDM.db.profile.General
    BCDM.Media = BCDM.Media or {}
    BCDM.Media.Font = LSM:Fetch("font", General.Fonts.Font)
        or LSM:Fetch("font", "Friz Quadrata TT") or STANDARD_TEXT_FONT
    BCDM.Media.Foreground = LSM:Fetch("statusbar", General.Textures.Foreground) or "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
    BCDM.Media.Background = LSM:Fetch("statusbar", General.Textures.Background) or "Interface\\Buttons\\WHITE8X8"
    BCDM.BACKDROP = { bgFile = BCDM.Media.Background, edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = BCDM.db.profile.CooldownManager.General.BorderSize, insets = {left = 0, right = 0, top = 0, bottom = 0} }
end

local function SetupSlashCommands()
    SLASH_BCDM1 = "/bcdm"
    SLASH_BCDM2 = "/bettercooldownmanager"
    SLASH_BCDM3 = "/bcm"
    SlashCmdList["BCDM"] = function() BCDM:CreateGUI() end
    if BCDM.db.global.DisplayLoginMessage then BCDM:PrettyPrint("'|cFF8080FF/bcdm|r' for in-game configuration.") end

    SLASH_BCDMRELOAD1 = "/rl"
    SlashCmdList["BCDMRELOAD"] = function() C_UI.Reload() end
end

local function PixelPerfect(value)
    if not value then return 0 end
    local _, screenHeight = GetPhysicalScreenSize()
    local uiScale = UIParent:GetEffectiveScale()
    local pixelSize = 768 / screenHeight / uiScale
    return pixelSize * math.floor(value / pixelSize + 0.5333)
end

local frameBorders = setmetatable({}, { __mode = "k" })

function BCDM:AddBorder(parentFrame)
    if not parentFrame then return end
    local borderSize = BCDM.db.profile.CooldownManager.General.BorderSize or 1
    local borderColour = { r = 0, g = 0, b = 0, a = 1 }
    local borderInset = PixelPerfect(0)
    local borders = frameBorders[parentFrame]
    local borderAnchor = parentFrame.Icon or parentFrame
    if not borders then
        local function CreateBorderLine() return parentFrame:CreateTexture(nil, "OVERLAY") end
        local topBorder = CreateBorderLine()
        topBorder:SetPoint("TOPLEFT", borderAnchor, "TOPLEFT", borderInset, -borderInset)
        topBorder:SetPoint("TOPRIGHT", borderAnchor, "TOPRIGHT", -borderInset, -borderInset)
        local bottomBorder = CreateBorderLine()
        bottomBorder:SetPoint("BOTTOMLEFT", borderAnchor, "BOTTOMLEFT", borderInset, borderInset)
        bottomBorder:SetPoint("BOTTOMRIGHT", borderAnchor, "BOTTOMRIGHT", -borderInset, borderInset)
        local leftBorder = CreateBorderLine()
        leftBorder:SetPoint("TOPLEFT", borderAnchor, "TOPLEFT", borderInset, -borderInset)
        leftBorder:SetPoint("BOTTOMLEFT", borderAnchor, "BOTTOMLEFT", borderInset, borderInset)
        local rightBorder = CreateBorderLine()
        rightBorder:SetPoint("TOPRIGHT", borderAnchor, "TOPRIGHT", -borderInset, -borderInset)
        rightBorder:SetPoint("BOTTOMRIGHT", borderAnchor, "BOTTOMRIGHT", -borderInset, borderInset)
        borders = { topBorder, bottomBorder, leftBorder, rightBorder }
        frameBorders[parentFrame] = borders
    end
    local top, bottom, left, right = unpack(borders)
    if top and bottom and left and right then
        local pixelSize = PixelPerfect(borderSize)
        top:SetHeight(pixelSize)
        bottom:SetHeight(pixelSize)
        left:SetWidth(pixelSize)
        right:SetWidth(pixelSize)
        local shouldShow = borderSize > 0
        for _, border in ipairs(borders) do
            border:SetColorTexture(borderColour.r, borderColour.g, borderColour.b, borderColour.a)
            border:SetShown(shouldShow)
        end
    end
end

function BCDM:StripTextures(textureToStrip)
    if not textureToStrip then return end
    if textureToStrip.GetMaskTexture then
        local i = 1
        local textureMask = textureToStrip:GetMaskTexture(i)
        while textureMask do
            textureToStrip:RemoveMaskTexture(textureMask)
            i = i + 1
            textureMask = textureToStrip:GetMaskTexture(i)
        end
    end
    local textureParent = textureToStrip:GetParent()
    if textureParent then
        for _, textureRegion in ipairs({ textureParent:GetRegions() }) do
            if textureRegion:IsObjectType("Texture") and textureRegion ~= textureToStrip and textureRegion:IsShown() then
                textureRegion:SetTexture(nil)
                textureRegion:Hide()
            end
        end
    end
end

function BCDM:GetIconDimensions(viewerDB)
    if not viewerDB then return 0, 0, true end
    local keepAspect = viewerDB.KeepAspectRatio
    if keepAspect == nil then
        keepAspect = true
    end

    local fallbackSize = viewerDB.IconSize or viewerDB.IconWidth or viewerDB.IconHeight or 32
    if keepAspect then
        return fallbackSize, fallbackSize, true
    end

    local iconWidth = viewerDB.IconWidth or fallbackSize
    local iconHeight = viewerDB.IconHeight or fallbackSize
    return iconWidth, iconHeight, false
end

function BCDM:GetIconTexCoords(width, height, baseZoom)
    local zoom = baseZoom or 0
    if zoom < 0 then zoom = 0 end
    if zoom > 0.49 then zoom = 0.49 end

    local left = zoom
    local right = 1 - zoom
    local top = zoom
    local bottom = 1 - zoom

    if not width or not height or width <= 0 or height <= 0 then
        return left, right, top, bottom
    end

    local aspect = width / height
    local uSpan = right - left
    local vSpan = bottom - top

    if aspect > 1 then
        local targetVSpan = uSpan / aspect
        local extra = (vSpan - targetVSpan) / 2
        if extra > 0 then
            top = top + extra
            bottom = bottom - extra
        end
    elseif aspect < 1 then
        local targetUSpan = vSpan * aspect
        local extra = (uSpan - targetUSpan) / 2
        if extra > 0 then
            left = left + extra
            right = right - extra
        end
    end

    return left, right, top, bottom
end

function BCDM:ApplyIconTexCoord(texture, width, height, baseZoom)
    if not texture then return end
    local left, right, top, bottom = BCDM:GetIconTexCoords(width, height, baseZoom)
    texture:SetTexCoord(left, right, top, bottom)
end

function BCDM:IsSecretValue(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

function BCDM:Init()
    SetupSlashCommands()
    BCDM:ResolveLSM()
    if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then C_AddOns.LoadAddOn("Blizzard_CooldownViewer") end
end

function BCDM:CopyTable(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[self:CopyTable(key, seen)] = self:CopyTable(child, seen)
    end
    return copy
end

function BCDM:UpdateBCDM()
    BCDM:ResolveLSM()
    BCDM:UpdateCooldownViewer("Essential")
    BCDM:UpdateCooldownViewer("Utility")
    BCDM:UpdateCooldownViewer("Buffs")
    BCDM:UpdatePowerBar()
    BCDM:UpdateSecondaryPowerBar()
    BCDM:UpdateCastBar()
    BCDM:RefreshCustomTrackers()
    BCDM:UpdateTrinketBar()
    BCDM:RefreshCustomGlows()
    if BCDM.QueueCooldownViewerLayoutApply then BCDM:QueueCooldownViewerLayoutApply() end
end

BCDM.SettingsHighlights = {}

function BCDM:ShouldShowSettingsHighlights()
    local settings = self.db and self.db.global and self.db.global.SettingsWindow
    return not settings or settings.ShowSelectedElementHighlight ~= false
end

local EMPTY_HIGHLIGHT_OFFSETS = {
    TOPLEFT = { -8, 8 }, TOP = { 0, 8 }, TOPRIGHT = { 8, 8 },
    LEFT = { -8, 0 }, CENTER = { 0, 0 }, RIGHT = { 8, 0 },
    BOTTOMLEFT = { -8, -8 }, BOTTOM = { 0, -8 }, BOTTOMRIGHT = { 8, -8 },
}

local function CreateSettingsHighlight(key, globalName)
    local highlight = BCDM.SettingsHighlights[key]
    if highlight then return highlight end
    highlight = CreateFrame("Frame", globalName, UIParent, "BackdropTemplate")
    highlight:SetBackdrop({
        edgeFile = "Interface\\AddOns\\BetterCooldownManager\\Media\\Glow.tga",
        edgeSize = 8,
        insets = { left = -8, right = -8, top = -8, bottom = -8 },
    })
    highlight:SetBackdropColor(0, 0, 0, 0)
    highlight:SetBackdropBorderColor(64/255, 128/255, 255/255, 1)
    highlight:SetFrameStrata("DIALOG")
    highlight:Hide()
    BCDM.SettingsHighlights[key] = highlight
    return highlight
end

function BCDM:ShowSettingsHighlight(key, target, options)
    local highlight = self.SettingsHighlights[key] or CreateSettingsHighlight(key)
    if not self:ShouldShowSettingsHighlights() then highlight:Hide() return end
    if not target then highlight:Hide() return end
    options = options or {}
    local ok = pcall(function()
        highlight:ClearAllPoints()
        if options.empty == true then
            local point = options.point or "CENTER"
            local offset = EMPTY_HIGHLIGHT_OFFSETS[point] or EMPTY_HIGHLIGHT_OFFSETS.CENTER
            highlight:SetSize((options.width or 1) + 16, (options.height or 1) + 16)
            highlight:SetPoint(point, target, point, offset[1], offset[2])
        else
            highlight:SetPoint("TOPLEFT", target, "TOPLEFT", -8, 8)
            highlight:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 8, -8)
        end
    end)
    highlight:SetShown(ok)
end

function BCDM:HideSettingsHighlight(key)
    local highlight = self.SettingsHighlights[key]
    if highlight then highlight:Hide() end
end

function BCDM:HideAllSettingsHighlights()
    for _, highlight in pairs(self.SettingsHighlights) do
        highlight:Hide()
    end
end

function BCDM:ShowSettingsHighlightForFrames(key, frames, fallbackTarget, options)
    if not self:ShouldShowSettingsHighlights() then
        self:HideSettingsHighlight(key)
        return
    end
    local parentScale = UIParent:GetEffectiveScale()
    local left, bottom, right, top
    for _, frame in pairs(frames or {}) do
        if frame and frame:IsShown() then
            local frameLeft, frameBottom, width, height = frame:GetRect()
            if frameLeft and frameBottom and width and height then
                local scale = frame:GetEffectiveScale() / parentScale
                frameLeft, frameBottom = frameLeft * scale, frameBottom * scale
                width, height = width * scale, height * scale
                left = not left and frameLeft or math.min(left, frameLeft)
                bottom = not bottom and frameBottom or math.min(bottom, frameBottom)
                right = not right and (frameLeft + width) or math.max(right, frameLeft + width)
                top = not top and (frameBottom + height) or math.max(top, frameBottom + height)
            end
        end
    end

    if not left then
        options = options or {}
        options.empty = true
        self:ShowSettingsHighlight(key, fallbackTarget, options)
        return
    end

    local highlight = self.SettingsHighlights[key] or CreateSettingsHighlight(key)
    highlight:ClearAllPoints()
    highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - 8, bottom - 8)
    highlight:SetSize((right - left) + 16, (top - bottom) + 16)
    highlight:Show()
end

function BCDM:CreateCooldownViewerOverlays()
    for _, viewerName in ipairs(self.CooldownManagerViewers) do
        local viewer = _G[viewerName]
        if viewer then
            local key = viewerName .. "Overlay"
            local highlight = CreateSettingsHighlight(key, "BCDM_" .. key)
            highlight:SetPoint("TOPLEFT", viewer, "TOPLEFT", -8, 8)
            highlight:SetPoint("BOTTOMRIGHT", viewer, "BOTTOMRIGHT", 8, -8)
            self[key] = highlight
        end
    end
end

function BCDM:ClearTicks()
    for _, tick in ipairs(BCDM.SecondaryPowerBar.Ticks) do
        tick:Hide()
    end
end

function BCDM:CreateTicks(count)
    BCDM:ClearTicks()
    if not count or count <= 1 then return end
    if count > 10 then count = 10 end
    local width = BCDM.SecondaryPowerBar.Status:GetWidth()
    for i = 1, count - 1 do
        local tick = BCDM.SecondaryPowerBar.Ticks[i]
        if not tick then
            tick = BCDM.SecondaryPowerBar.Status:CreateTexture(nil, "OVERLAY")
            tick:SetColorTexture(0, 0, 0, 1)
            BCDM.SecondaryPowerBar.Ticks[i] = tick
        end
        local tickPosition = (i / count) * width
        tick:ClearAllPoints()
        tick:SetSize(1, BCDM.SecondaryPowerBar:GetHeight() - 2)
        tick:SetPoint("LEFT", BCDM.SecondaryPowerBar.Status, "LEFT", tickPosition - 0.1, 0)
        tick:SetDrawLayer("OVERLAY", 7)
        tick:Show()
    end
end


function BCDM:OpenURL(title, urlText)
    StaticPopupDialogs["BCDM_URL_POPUP"] = {
        text = title or "",
        button1 = CLOSE,
        hasEditBox = true,
        editBoxWidth = 300,
        OnShow = function(self)
            self.EditBox:SetText(urlText or "")
            self.EditBox:SetFocus()
            self.EditBox:HighlightText()
        end,
        OnAccept = function(self) end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    local urlDialog = StaticPopup_Show("BCDM_URL_POPUP")
    if urlDialog then
        urlDialog:SetFrameStrata("TOOLTIP")
    end
    return urlDialog
end

function BCDM:CreatePrompt(title, text, onAccept, onCancel, acceptText, cancelText)
    StaticPopupDialogs["BCDM_PROMPT_DIALOG"] = {
        text = text or "",
        button1 = acceptText or ACCEPT,
        button2 = cancelText or CANCEL,
        OnAccept = function(self, data)
            if data and data.onAccept then
                data.onAccept()
            end
        end,
        OnCancel = function(self, data)
            if data and data.onCancel then
                data.onCancel()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        showAlert = true,
    }
    local promptDialog = StaticPopup_Show("BCDM_PROMPT_DIALOG", title, text)
    if promptDialog then
        promptDialog.data = { onAccept = onAccept, onCancel = onCancel }
        promptDialog:SetFrameStrata("TOOLTIP")
    end
    return promptDialog
end

BCDM.AnchorParents = {
    ["Essential"] = {
        {
            ["UtilityCooldownViewer"] = "|cFF00AEF7Blizzard|r: Utility Cooldown Viewer",
            ["BCDM_PowerBar"] = "|cFF8080FFBCDM|r: Power Bar",
            ["BCDM_SecondaryPowerBar"] = "|cFF8080FFBCDM|r: Secondary Power Bar",
            ["NONE"] = "|cFF00AEF7Blizzard|r: UIParent",
        },
        { "NONE", "UtilityCooldownViewer", "BCDM_PowerBar", "BCDM_SecondaryPowerBar" },
    },
    ["Utility"] = {
        {
            ["EssentialCooldownViewer"] = "|cFF00AEF7Blizzard|r: Essential Cooldown Viewer",
            ["BCDM_PowerBar"] = "|cFF8080FFBCDM|r: Power Bar",
            ["BCDM_SecondaryPowerBar"] = "|cFF8080FFBCDM|r: Secondary Power Bar",
            ["NONE"] = "|cFF00AEF7Blizzard|r: UIParent",
        },
        { "EssentialCooldownViewer", "NONE", "BCDM_PowerBar", "BCDM_SecondaryPowerBar"},
    },
    ["Buffs"] = {
        {
            ["EssentialCooldownViewer"] = "|cFF00AEF7Blizzard|r: Essential Cooldown Viewer",
            ["UtilityCooldownViewer"] = "|cFF00AEF7Blizzard|r: Utility Cooldown Viewer",
            ["NONE"] = "|cFF00AEF7Blizzard|r: UIParent",
            ["BCDM_PowerBar"] = "|cFF8080FFBCDM|r: Power Bar",
            ["BCDM_SecondaryPowerBar"] = "|cFF8080FFBCDM|r: Secondary Power Bar",
            ["BCDM_CastBar"] = "|cFF8080FFBCDM|r: Cast Bar",
        },
        { "EssentialCooldownViewer", "UtilityCooldownViewer", "NONE", "BCDM_PowerBar", "BCDM_SecondaryPowerBar", "BCDM_CastBar" },
    },
    ["CustomTrackers"] = {
        {
            ["EssentialCooldownViewer"] = "|cFF00AEF7Blizzard|r: Essential Cooldown Viewer",
            ["UtilityCooldownViewer"] = "|cFF00AEF7Blizzard|r: Utility Cooldown Viewer",
            ["NONE"] = "|cFF00AEF7Blizzard|r: UIParent",
            ["PlayerFrame"] = "|cFF00AEF7Blizzard|r: Player Frame",
            ["TargetFrame"] = "|cFF00AEF7Blizzard|r: Target Frame",
            ["BCDM_PowerBar"] = "|cFF8080FFBCDM|r: Power Bar",
            ["BCDM_SecondaryPowerBar"] = "|cFF8080FFBCDM|r: Secondary Power Bar",
            ["BCDM_CastBar"] = "|cFF8080FFBCDM|r: Cast Bar",
            ["BCDM_TrinketBar"] = "|cFF8080FFBCDM|r: Trinket Bar",
        },
        { "EssentialCooldownViewer", "UtilityCooldownViewer", "NONE", "PlayerFrame", "TargetFrame",
            "BCDM_PowerBar", "BCDM_SecondaryPowerBar", "BCDM_CastBar", "BCDM_TrinketBar" },
    },
    ["Trinket"] = {
        {
            ["EssentialCooldownViewer"] = "|cFF00AEF7Blizzard|r: Essential Cooldown Viewer",
            ["UtilityCooldownViewer"] = "|cFF00AEF7Blizzard|r: Utility Cooldown Viewer",
            ["NONE"] = "|cFF00AEF7Blizzard|r: UIParent",
            ["PlayerFrame"] = "|cFF00AEF7Blizzard|r: Player Frame",
            ["TargetFrame"] = "|cFF00AEF7Blizzard|r: Target Frame",
            ["BCDM_PowerBar"] = "|cFF8080FFBCDM|r: Power Bar",
            ["BCDM_SecondaryPowerBar"] = "|cFF8080FFBCDM|r: Secondary Power Bar",
        },
        { "EssentialCooldownViewer", "UtilityCooldownViewer", "NONE", "PlayerFrame", "TargetFrame", "BCDM_PowerBar", "BCDM_SecondaryPowerBar" },
    },
    ["Power"] = {
        {
            ["EssentialCooldownViewer"] = "|cFF00AEF7Blizzard|r: Essential Cooldown Viewer",
            ["UtilityCooldownViewer"] = "|cFF00AEF7Blizzard|r: Utility Cooldown Viewer",
            ["BCDM_SecondaryPowerBar"] = "|cFF8080FFBCDM|r: Secondary Power Bar",
        },
        { "EssentialCooldownViewer", "UtilityCooldownViewer", "BCDM_SecondaryPowerBar" },
    },
    ["SecondaryPower"] = {
        {
            ["EssentialCooldownViewer"] = "|cFF00AEF7Blizzard|r: Essential Cooldown Viewer",
            ["UtilityCooldownViewer"] = "|cFF00AEF7Blizzard|r: Utility Cooldown Viewer",
            ["BCDM_PowerBar"] = "|cFF8080FFBCDM|r: Power Bar",
        },
        { "EssentialCooldownViewer", "UtilityCooldownViewer", "BCDM_PowerBar"},
    },
    ["CastBar"] = {
        {
            ["EssentialCooldownViewer"] = "|cFF00AEF7Blizzard|r: Essential Cooldown Viewer",
            ["UtilityCooldownViewer"] = "|cFF00AEF7Blizzard|r: Utility Cooldown Viewer",
            ["BCDM_PowerBar"] = "|cFF8080FFBCDM|r: Power Bar",
            ["BCDM_SecondaryPowerBar"] = "|cFF8080FFBCDM|r: Secondary Power Bar",
        },
        { "EssentialCooldownViewer", "UtilityCooldownViewer", "BCDM_PowerBar", "BCDM_SecondaryPowerBar" },
    }
}

StaticPopupDialogs["BCDM_RELOAD"] = {
    text = "You must |cFFFF4040reload|r in order for changes to take effect. Do you want to reload now?",
    button1 = "Reload",
    button2 = "Cancel",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
function BCDM:PromptReload()
    StaticPopup_Show("BCDM_RELOAD")
end
