local BCDM, Check = ...

local previous = {
    CreateFrame = CreateFrame,
    GameTooltip = GameTooltip,
    GetCursorPosition = GetCursorPosition,
    Minimap = Minimap,
    db = BCDM.db,
    minimapButton = BCDM.MinimapButton,
    toggleSettings = BCDM.ToggleSettings,
    atan2 = math.atan2,
}

if not math.atan2 then math.atan2 = function(y, x) return math.atan(y, x) end end

local minimap = {}
function minimap:GetWidth() return 140 end
function minimap:GetHeight() return 140 end
function minimap:GetFrameLevel() return 4 end
function minimap:GetEffectiveScale() return 1 end
function minimap:GetCenter() return 100, 100 end
Minimap = minimap

local createdButton
local function NewTexture()
    local texture = {}
    function texture:SetSize() end
    function texture:SetPoint() end
    function texture:SetTexture() end
    function texture:SetTexCoord() end
    function texture:SetAllPoints() end
    function texture:SetColorTexture() end
    function texture:SetBlendMode() end
    return texture
end

CreateFrame = function(_, name, parent, template)
    local button = { name = name, parent = parent, template = template, scripts = {} }
    function button:SetSize() end
    function button:SetFrameStrata() end
    function button:SetFrameLevel() end
    function button:SetClampedToScreen() end
    function button:SetBackdrop() end
    function button:SetBackdropColor() end
    function button:SetBackdropBorderColor() end
    function button:GetParent() return self.parent end
    function button:CreateTexture() return NewTexture() end
    function button:RegisterForClicks() end
    function button:RegisterForDrag() end
    function button:SetScript(script, callback) self.scripts[script] = callback end
    function button:ClearAllPoints() self.point = nil end
    function button:SetPoint(...) self.point = { ... } end
    function button:SetShown(shown) self.shown = shown end
    createdButton = button
    return button
end

GameTooltip = {
    SetOwner = function() end,
    AddLine = function() end,
    Show = function() end,
    Hide = function() end,
}
GetCursorPosition = function() return 200, 100 end

local toggles = 0
BCDM.db = { global = { MinimapButton = { Show = true, Angle = 225 } } }
BCDM.MinimapButton = nil
BCDM.ToggleSettings = function() toggles = toggles + 1 end
BCDM:SetupMinimapButton()

Check(createdButton and createdButton.parent == minimap and createdButton.name == "BCDM_MinimapButton",
    "the minimap button is a named direct child of Minimap for button-bar collectors")
Check(createdButton.Icon == createdButton.icon,
    "the minimap button exposes its visible artwork through the common icon field")
Check(createdButton.point and createdButton.point[2] == minimap and createdButton.shown == true,
    "the minimap button uses its saved visible position")
local collectedPoint = createdButton.point
createdButton.parent = {}
BCDM.db.global.MinimapButton.Angle = 90
BCDM:UpdateMinimapButton()
Check(createdButton.point == collectedPoint,
    "BCM does not reposition the button after an addon bar reparents it")
createdButton.parent = minimap
createdButton.scripts.OnClick(createdButton)
Check(toggles == 1, "the minimap button toggles BCM settings")
createdButton.scripts.OnDragStart(createdButton)
createdButton.scripts.OnUpdate(createdButton)
createdButton.scripts.OnDragStop(createdButton)
Check(math.abs(BCDM.db.global.MinimapButton.Angle) < 0.0001
    and createdButton.scripts.OnUpdate == nil,
    "dragging persists the minimap angle without leaving a permanent updater")
BCDM.db.global.MinimapButton.Show = false
BCDM:UpdateMinimapButton()
Check(createdButton.shown == false, "the global setting hides the minimap button")

CreateFrame = previous.CreateFrame
GameTooltip = previous.GameTooltip
GetCursorPosition = previous.GetCursorPosition
Minimap = previous.Minimap
BCDM.db = previous.db
BCDM.MinimapButton = previous.minimapButton
BCDM.ToggleSettings = previous.toggleSettings
math.atan2 = previous.atan2

return true
