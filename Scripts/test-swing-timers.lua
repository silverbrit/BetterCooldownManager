local root = (...) or "."
local combat, blocked, borders, events = false, false, 0, {}
local function Region()
    return {
        CanBeAccessedInContext = function() return not blocked end,
        SetTexture = function(self, value) self.texture = value end,
        SetVertexColor = function(self, ...) self.colour = { ... } end,
        SetStatusBarTexture = function(self, value) self.texture = value end,
        SetStatusBarColor = function(self, ...) self.colour = { ... } end,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        SetFont = function(self, ...) self.font = { ... } end,
    }
end
local env = setmetatable({
    InCombatLockdown = function() return combat end,
    UnitClass = function() return "Shaman", "SHAMAN" end,
    RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } },
    CreateFrame = function()
        return {
            RegisterEvent = function(_, event) events[event] = true end,
            SetScript = function(_, _, callback) events.callback = callback end,
        }
    end,
}, { __index = _G })
env._G = env
local frames = {}
for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
    local status = Region()
    status.TypeLabel, status.TimeLabel, status.TypeLabelShadow = Region(), Region(), Region()
    local frame = { Background = Region(), Border = Region(), StatusBar = status }
    frames[#frames + 1], env[name] = frame, frame
end
local BCDM = {
    IS_WOW_FOREVER = false,
    Media = { Background = "background", Foreground = "foreground", Font = "font" },
    db = { profile = {
        General = { Fonts = { FontFlag = "OUTLINE" } },
        CooldownManager = { General = { BorderSize = 1, CooldownText = { FontSize = 15 } } },
    } },
    IsSafeAnchorParent = function(_, frame) return frame ~= nil end,
    IsSecretValue = function() return false end,
    AddBorder = function() borders = borders + 1 end,
}
setfenv(assert(loadfile(root .. "/Modules/SwingTimers.lua")), env)("BCDM", BCDM)
BCDM:SetupSwingTimers()
assert(borders == 0 and not events.callback, "Retail is untouched")
BCDM.IS_WOW_FOREVER, combat = true, true
BCDM:SetupSwingTimers()
assert(borders == 0 and events.PLAYER_REGEN_ENABLED and events.ADDON_LOADED)
combat = false
events.callback(nil, "PLAYER_REGEN_ENABLED")
assert(borders == 3, "all swing timers are skinned after combat")
for _, frame in ipairs(frames) do
    assert(frame.StatusBar.texture == "foreground" and frame.Background.texture == "background")
    assert(frame.StatusBar.colour[2] == 0.44 and frame.StatusBar.TimeLabel.font[2] == 15)
    assert(frame.StatusBar.points[1][4] == 1 and frame.Border.texture == nil)
    local fields = 0
    for _ in pairs(frame) do fields = fields + 1 end
    assert(fields == 3, "no addon metadata or lifecycle overrides on native frames")
end
blocked = true
BCDM:SkinSwingTimers()
assert(borders == 3, "inaccessible regions are left untouched")
blocked = false
BCDM.Media.Foreground = "changed"
BCDM:SkinSwingTimers()
assert(frames[1].StatusBar.texture == "changed", "profile/media changes refresh the skin")
env.SwingTimerOffHandFrame = nil
BCDM:SkinSwingTimers()
assert(borders == 8, "missing frames do not prevent styling other timers")
return true
