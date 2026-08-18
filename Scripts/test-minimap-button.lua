local BCDM, Check = ...

local previous = {
    LibStub = LibStub,
    db = BCDM.db,
    dataObject = BCDM.MinimapDataObject,
    toggleSettings = BCDM.ToggleSettings,
}

local dataBroker = { created = {} }
function dataBroker:NewDataObject(name, object)
    self.created[name] = object
    return object
end

local dbIcon = { registered = {}, shown = {}, hidden = {} }
function dbIcon:IsRegistered(name) return self.registered[name] ~= nil end
function dbIcon:Register(name, object, settings)
    self.registered[name] = { object = object, settings = settings }
end
function dbIcon:Show(name) self.shown[name] = (self.shown[name] or 0) + 1 end
function dbIcon:Hide(name) self.hidden[name] = (self.hidden[name] or 0) + 1 end

LibStub = function(name)
    if name == "LibDataBroker-1.1" then return dataBroker end
    if name == "LibDBIcon-1.0" then return dbIcon end
end

local toggles = 0
BCDM.db = { global = { MinimapButton = { Show = true, Angle = 225 } } }
BCDM.MinimapDataObject = nil
BCDM.ToggleSettings = function() toggles = toggles + 1 end
BCDM:SetupMinimapButton()

local registration = dbIcon.registered["Better Cooldown Manager"]
Check(registration and registration.object.type == "launcher" and registration.object.icon,
    "the minimap launcher is registered through LibDataBroker and LibDBIcon")
Check(registration.settings.minimapPos == 225 and registration.settings.hide == false
    and registration.settings.Show == nil and registration.settings.Angle == nil,
    "legacy minimap visibility and angle settings migrate to LibDBIcon storage")
Check(dbIcon.shown["Better Cooldown Manager"] == 1,
    "the default minimap launcher is shown through LibDBIcon")

registration.object.OnClick(registration.object, "LeftButton")
Check(toggles == 1, "the LibDataBroker launcher toggles BCM settings")

local tooltip = { lines = {} }
function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
registration.object.OnTooltipShow(tooltip)
Check(#tooltip.lines == 2, "the LibDataBroker launcher provides its tooltip content")

BCDM.db.global.MinimapButton.hide = true
BCDM:UpdateMinimapButton()
Check(dbIcon.hidden["Better Cooldown Manager"] == 1,
    "the global setting hides the launcher through LibDBIcon")
Check(dataBroker.created["Better Cooldown Manager"] == registration.object,
    "refreshing visibility does not recreate the LibDataBroker object")

local sourceFile = assert(io.open("Core/MinimapButton.lua", "r"))
local source = sourceFile:read("*a")
sourceFile:close()
Check(not source:find("CreateFrame", 1, true) and not source:find("SetScript", 1, true)
    and not source:find("OnUpdate", 1, true),
    "the minimap integration does not implement a custom button or drag updater")

LibStub = previous.LibStub
BCDM.db = previous.db
BCDM.MinimapDataObject = previous.dataObject
BCDM.ToggleSettings = previous.toggleSettings

return true
