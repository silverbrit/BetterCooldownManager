local _, BCDM = ...

local DATA_OBJECT_NAME = "Better Cooldown Manager"
local ICON_TEXTURE = "Interface\\AddOns\\BetterCooldownManager\\Media\\Logo.png"

local function GetSettings()
    local global = BCDM.db and BCDM.db.global
    if not global then return nil end

    local settings = global.MinimapButton or {}
    global.MinimapButton = settings
    if settings.minimapPos == nil and type(settings.Angle) == "number" then
        settings.minimapPos = settings.Angle
    end
    if settings.hide == nil then settings.hide = settings.Show == false end
    settings.Angle = nil
    settings.Show = nil
    return settings
end

local function GetLibraries()
    if not LibStub then return end
    return LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
end

local function CreateDataObject(dataBroker)
    if BCDM.MinimapDataObject then return BCDM.MinimapDataObject end

    BCDM.MinimapDataObject = dataBroker:NewDataObject(DATA_OBJECT_NAME, {
        type = "launcher",
        icon = ICON_TEXTURE,
        OnClick = function(_, button)
            if button == "LeftButton" and BCDM.ToggleSettings then BCDM:ToggleSettings() end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(BCDM.ADDON_NAME or DATA_OBJECT_NAME)
            tooltip:AddLine("Left-click to |cff00ff00open settings|r", 1, 1, 1)
        end,
    })
    return BCDM.MinimapDataObject
end

function BCDM:UpdateMinimapButton()
    local settings = GetSettings()
    local dataBroker, dbIcon = GetLibraries()
    if not settings or not dataBroker or not dbIcon then return end

    if not dbIcon:IsRegistered(DATA_OBJECT_NAME) then
        dbIcon:Register(DATA_OBJECT_NAME, CreateDataObject(dataBroker), settings)
    end
    if settings.hide then dbIcon:Hide(DATA_OBJECT_NAME) else dbIcon:Show(DATA_OBJECT_NAME) end
end

function BCDM:SetupMinimapButton()
    self:UpdateMinimapButton()
end
