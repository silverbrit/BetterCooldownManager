local root = (...) or "."
local function SecretError() error("secret inspected") end
local secret = setmetatable({}, { __lt = SecretError, __le = SecretError,
    __add = SecretError, __sub = SecretError, __mul = SecretError, __div = SecretError,
    __tostring = SecretError })
local current, maximum, powerType, spell, cost = 100, 200, 0, 123, 30
local texture = {}
function texture:Hide() self.shown = false end
function texture:Show() self.shown = true end
function texture:ClearAllPoints() self.points = {} end
function texture:SetPoint(...) self.points[#self.points + 1] = { ... } end
function texture:SetWidth(width) self.width = width end
function texture:SetReverseFill(reverse) self.reverse = reverse end
function texture:SetMinMaxValues(_, max) self.maximum = max end
function texture:SetValue(value) self.value = value end
local fillTexture = {}
local settings = { Enabled = true, ShowManaCostPrediction = true, FillDirection = "RIGHT" }
local BCDM = {
    db = { profile = { PowerBar = settings } },
    PowerBar = { CostPrediction = texture, Status = {
        GetWidth = function() return 400 end,
        GetStatusBarTexture = function() return fillTexture end,
    } },
    IsSecretValue = function(_, value) return rawequal(value, secret) end,
}
local env = setmetatable({
    CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end,
    UnitPowerType = function() return powerType end,
    UnitPower = function() return current end,
    UnitPowerMax = function() return maximum end,
    UnitCastingInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, spell end,
    C_Spell = { GetSpellPowerCost = function(id)
        assert(rawequal(id, spell), "spell ID is passed directly to the accepting API")
        return { { type = 0, cost = cost } }
    end },
}, { __index = _G })
setfenv(assert(loadfile(root .. "/Modules/PowerBar.lua")), env)("BCDM", BCDM)
BCDM:UpdatePowerCostPrediction()
assert(texture.shown and texture.width == 400 and texture.value == 30 and texture.maximum == 200)
assert(texture.reverse and texture.points[1][2] == fillTexture
    and texture.points[1][1] == "TOPRIGHT" and texture.points[1][3] == "TOPRIGHT")
settings.FillDirection = "LEFT"
BCDM:UpdatePowerCostPrediction()
assert(texture.shown and not texture.reverse)
assert(texture.points[1][1] == "TOPLEFT" and texture.points[1][3] == "TOPLEFT")
spell = nil
BCDM:UpdatePowerCostPrediction()
assert(not texture.shown, "cast stop/interruption clears prediction")
spell, current = 123, secret
BCDM:UpdatePowerCostPrediction()
assert(texture.shown, "secret current mana does not suppress prediction")
spell, maximum, cost = secret, secret, secret
BCDM:UpdatePowerCostPrediction()
assert(texture.shown and rawequal(texture.value, secret) and rawequal(texture.maximum, secret),
    "secret spell, maximum and cost pass directly to native API/widgets")
spell, maximum, cost, powerType = 123, 200, 30, 3
BCDM:UpdatePowerCostPrediction()
assert(not texture.shown, "non-mana bars do not show mana predictions")
powerType, maximum = 0, 0
BCDM:UpdatePowerCostPrediction()
assert(not texture.shown, "zero maximum cannot divide by zero")
maximum, settings.ShowManaCostPrediction = 200, false
BCDM:UpdatePowerCostPrediction()
assert(not texture.shown, "prediction can be disabled")
-- Exercise actual bar creation without Blizzard's XML colour constants.
local noop = function() end
local methods = setmetatable({}, { __index = function() return noop end })
local function Widget()
    return setmetatable({}, { __index = methods })
end
methods.CreateTexture, methods.CreateFontString = Widget, Widget
function methods:SetColorTexture(...) self.colour = { ... } end
function methods:SetStatusBarColor(...) self.colour = { ... } end
function methods:SetClipsChildren(clips) self.clips = clips end
function methods:Hide() self.hidden = true end
function methods:Show() self.hidden = false end
env._G = {}
env.MANAPREDICTIONBLUE = false
env.CreateFrame, env.hooksecurefunc = Widget, noop
env.UnitClass = function() return "Mage", "MAGE" end
env.RAID_CLASS_COLORS = {}
BCDM.Media = { Font = "font", Foreground = "texture" }
BCDM.db.profile.General = { Fonts = { FontFlag = "OUTLINE", Shadow = { Enabled = false } },
    Colours = { PrimaryPower = {} } }
BCDM.db.profile.CooldownManager = { General = { BorderSize = 1 } }
settings.BackgroundColour = { 0, 0, 0, 1 }
settings.Text = { Enabled = true, FontSize = 12, Colour = { 1, 1, 1 },
    Layout = { "CENTER", "CENTER", 0, 0 } }
BCDM.GetCurrentSecondaryResource = noop
BCDM.GetPowerBarLayout = function() return { "CENTER", "NONE", "CENTER", 0, 0 } end
BCDM.SetSafeAnchorPoint, BCDM.ApplyStatusBarDirection = noop, noop
BCDM.AnchorStatusBarSpark, BCDM.RegisterOwnedFrameVisibility = noop, noop
BCDM.ApplyPowerBarOwnership = noop
BCDM.ResolveBarFillColour = function() return 0, 0, 1, 1 end
BCDM:CreatePowerBar()
assert(BCDM.PowerBar.CostPrediction.colour[1] == 0
    and BCDM.PowerBar.CostPrediction.colour[4] == 0.55
    and BCDM.PowerBar.CostPrediction.hidden and BCDM.PowerBar.Status.clips,
    "bar creation prepares a clipped dark prediction without native colour globals")
return true
