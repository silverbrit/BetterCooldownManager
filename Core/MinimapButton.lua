local _, BCDM = ...

local DEFAULT_ANGLE = 225
local BUTTON_SIZE = 30

local function GetSettings()
    local global = BCDM.db and BCDM.db.global
    if not global then return nil end
    global.MinimapButton = global.MinimapButton or {}
    return global.MinimapButton
end

function BCDM.GetMinimapButtonOffset(angle, radius)
    angle = type(angle) == "number" and angle or DEFAULT_ANGLE
    radius = type(radius) == "number" and radius or 80
    local radians = math.rad(angle)
    return math.cos(radians) * radius, math.sin(radians) * radius
end

local function PositionButton(button, angle)
    if not button or not Minimap then return end
    if type(button.GetParent) == "function" and button:GetParent() ~= Minimap then return end
    local width = type(Minimap.GetWidth) == "function" and Minimap:GetWidth() or 140
    local height = type(Minimap.GetHeight) == "function" and Minimap:GetHeight() or width
    local radius = math.max(width or 140, height or 140) / 2 + 5
    local x, y = BCDM.GetMinimapButtonOffset(angle, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function PositionButtonAtCursor(button)
    if not Minimap or type(GetCursorPosition) ~= "function" then return end
    if type(button.GetParent) == "function" and button:GetParent() ~= Minimap then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local centerX, centerY = Minimap:GetCenter()
    if type(cursorX) ~= "number" or type(cursorY) ~= "number"
        or type(scale) ~= "number" or scale <= 0
        or type(centerX) ~= "number" or type(centerY) ~= "number" then return end
    local angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    button.dragAngle = angle
    PositionButton(button, angle)
end

local function CreateMinimapButton()
    if BCDM.MinimapButton or not Minimap then return BCDM.MinimapButton end

    local button = CreateFrame("Button", "BCDM_MinimapButton", Minimap)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:SetClampedToScreen(true)

    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.icon = button.Icon
    button.Icon:SetSize(20, 20)
    button.Icon:SetPoint("CENTER")
    button.Icon:SetTexture("Interface\\AddOns\\BetterCooldownManager\\Media\\Logo.png")
    button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function()
        if BCDM.ToggleSettings then BCDM:ToggleSettings() end
    end)
    button:SetScript("OnDragStart", function(self)
        if self:GetParent() ~= Minimap then return end
        self:SetScript("OnUpdate", PositionButtonAtCursor)
        PositionButtonAtCursor(self)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local settings = GetSettings()
        if settings and type(self.dragAngle) == "number" then settings.Angle = self.dragAngle end
        self.dragAngle = nil
    end)
    button:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragAngle = nil
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(BCDM.ADDON_NAME or "Better Cooldown Manager")
        GameTooltip:AddLine("Left-click to toggle settings.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    BCDM.MinimapButton = button
    return button
end

function BCDM:UpdateMinimapButton()
    local settings = GetSettings()
    local button = CreateMinimapButton()
    if not settings or not button then return end
    PositionButton(button, settings.Angle)
    button:SetShown(settings.Show ~= false)
end

function BCDM:SetupMinimapButton()
    self:UpdateMinimapButton()
end
