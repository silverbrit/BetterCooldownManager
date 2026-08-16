local root = (...)
if type(root) ~= "string" or root == "" then root = "." end
local unpack = unpack or table.unpack

local failures = 0
local inCombat = false
InCombatLockdown = function() return inCombat end
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local calls = { start = {}, stop = {} }
local function Record(bucket, glowType, frame)
    calls[bucket][glowType] = (calls[bucket][glowType] or 0) + 1
    calls.lastFrame = frame
end

local glowFailures = { start = {}, stop = {} }
local function MaybeFail(bucket, glowType)
    if glowFailures[bucket][glowType] then error(bucket .. " failure") end
end

local glowLibrary = {
    PixelGlow_Start = function(frame)
        Record("start", "Pixel", frame)
        MaybeFail("start", "Pixel")
    end,
    PixelGlow_Stop = function(frame)
        MaybeFail("stop", "Pixel")
        Record("stop", "Pixel", frame)
    end,
    AutoCastGlow_Start = function(frame)
        Record("start", "Autocast", frame)
        MaybeFail("start", "Autocast")
    end,
    AutoCastGlow_Stop = function(frame)
        MaybeFail("stop", "Autocast")
        Record("stop", "Autocast", frame)
    end,
    ProcGlow_Start = function(frame)
        Record("start", "Proc", frame)
        MaybeFail("start", "Proc")
    end,
    ProcGlow_Stop = function(frame)
        MaybeFail("stop", "Proc")
        Record("stop", "Proc", frame)
    end,
    ButtonGlow_Start = function(frame, color, frequency)
        Record("start", "Button", frame)
        MaybeFail("start", "Button")
        calls.buttonColor, calls.buttonFrequency = color, frequency
    end,
    ButtonGlow_Stop = function(frame)
        MaybeFail("stop", "Button")
        Record("stop", "Button", frame)
    end,
}

LibStub = function(name)
    if name == "LibCustomGlow-1.0" then return glowLibrary end
end

local createdFrames = {}
local reportedErrors = {}
local function NewFrame(parent)
    local frame = {
        parent = parent, shown = true, frameLevel = 1, width = 36, height = 36,
        frameStrata = "MEDIUM", hooks = {}, events = {}, scripts = {}
    }
    function frame:GetParent() return self.parent end
    function frame:GetSize() return self.width, self.height end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:GetFrameStrata() return self.frameStrata end
    function frame:SetFrameStrata(strata) self.frameStrata = strata end
    function frame:ClearAllPoints() self.cleared = true end
    function frame:SetAllPoints(target)
        if self.failSetAllPoints then error("forbidden layout") end
        self.allPoints = target
    end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
    function frame:Show() self.shown = true end
    function frame:Hide()
        self.shown = false
        for _, callback in ipairs(self.hooks.OnHide or {}) do callback(self) end
    end
    function frame:HookScript(script, callback)
        self.hooks[script] = self.hooks[script] or {}
        self.hooks[script][#self.hooks[script] + 1] = callback
    end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:SetAlpha(alpha) self.alpha = alpha end
    function frame:GetAlpha() return self.alpha or 1 end
    return frame
end

CreateFrame = function(_, _, parent)
    local frame = NewFrame(parent)
    createdFrames[#createdFrames + 1] = frame
    return frame
end
geterrorhandler = function()
    return function(message) reportedErrors[#reportedErrors + 1] = tostring(message) end
end

hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(...)
        local results = { original(...) }
        callback(...)
        return unpack(results)
    end
end

local manager = { activeAlerts = {}, showCalls = 0, hideCalls = 0 }
function manager:ShowAlert(frame)
    self.showCalls = self.showCalls + 1
    self.activeAlerts[frame] = true
    frame.SpellActivationAlert:Show()
end
function manager:HideAlert(frame)
    self.hideCalls = self.hideCalls + 1
    self.activeAlerts[frame] = nil
    frame.SpellActivationAlert:Hide()
end
function manager:HasAlert(frame) return self.activeAlerts[frame] == true end

local viewer = NewFrame(nil)
local target = NewFrame(viewer)
target.SpellActivationAlert = NewFrame(target)
target.SpellActivationAlert:SetAlpha(0.4)
target.Cooldown = {}
function target.Cooldown:IsShown() return true end
function target.Cooldown:GetCooldownDuration() return 4000 end
function target:IsItem() return false end

local secondTarget = NewFrame(viewer)
secondTarget.SpellActivationAlert = NewFrame(secondTarget)
secondTarget.SpellActivationAlert:SetAlpha(0.4)
function secondTarget:IsItem() return false end

viewer.itemFramePool = { activeFrames = { [target] = true, [secondTarget] = true } }
function viewer.itemFramePool:EnumerateActive()
    return next, self.activeFrames, nil
end
function viewer.itemFramePool:IsActive(frame)
    return self.activeFrames[frame] == true
end
function viewer.itemFramePool:Release(frame)
    if not self.activeFrames[frame] then return false end
    self.activeFrames[frame] = nil
    frame:Hide()
    return true
end
function viewer.itemFramePool:ReleaseAll()
    for frame in pairs(self.activeFrames) do
        self.activeFrames[frame] = nil
        frame:Hide()
    end
end

EssentialCooldownViewer = viewer
ActionButtonSpellAlertManager = nil

local BCDM = {
    CooldownManagerViewers = { "EssentialCooldownViewer" },
    db = { profile = { CooldownManager = { General = { Glow = {
        Enabled = true,
        Type = "Pixel",
        Pixel = { Color = { 1, 1, 1, 1 }, Lines = 5, Frequency = 0.25, Length = 2, Thickness = 1, XOffset = -1, YOffset = -1, Border = false },
        Autocast = { Color = { 1, 1, 1, 1 }, Particles = 10, Frequency = 0.25, Scale = 1, XOffset = -1, YOffset = -1 },
        Proc = { Color = { 1, 1, 1, 1 }, StartAnim = true, Duration = 1, XOffset = 0, YOffset = 0 },
        Button = { Color = { 0.95, 0.95, 0, 0.9 }, UseColor = false, Frequency = 0.3 },
    } } } } },
}
local secretFrameLevel = {}
function BCDM:IsSecretValue(value) return value == secretFrameLevel end
function BCDM:IsCustomizableCooldownViewerItem(frame)
    if not frame or not frame.IsItem then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    local ok, isItem = pcall(frame.IsItem, frame)
    return ok and isItem == false
end

assert(loadfile(root .. "/Modules/CustomGlows.lua"))("BetterCooldownManager", BCDM)

local savedProfile = BCDM.db.profile
local legacyGlow = {
    GlowType = "Proc",
    Type = "Button",
    Button = { Color = { 0.2, 0.3, 0.4, 0.5 }, UseColor = false },
}
setmetatable(legacyGlow, {
    __index = {
        Button = { Color = { 0.95, 0.95, 0, 0.9 }, UseColor = false, Frequency = 0.3 },
    },
})
BCDM.db.profile = { CooldownManager = { General = { Glow = legacyGlow } } }
local migratedGlow = BCDM:GetCustomGlowSettings()
Check(migratedGlow.Type == "Proc" and migratedGlow.GlowType == nil,
    "legacy GlowType wins over AceDB's materialized Button default")
Check(migratedGlow.Button.UseColor == true and migratedGlow.Button.Color[1] == 0.2,
    "legacy customized Button colours remain enabled")

local defaultButtonGlow = { Type = "Button", Button = { Color = { 0.95, 0.95, 0, 0.9 } } }
BCDM.db.profile = { CooldownManager = { General = { Glow = defaultButtonGlow } } }
local defaultedGlow = BCDM:GetCustomGlowSettings()
Check(defaultedGlow.Button.UseColor == false, "new Button defaults keep custom colours opt-in")

local explicitButtonGlow = {
    Type = "Button",
    Button = { Color = { 0.2, 0.3, 0.4, 0.5 }, UseColor = false },
}
BCDM.db.profile = { CooldownManager = { General = { Glow = explicitButtonGlow } } }
Check(BCDM:GetCustomGlowSettings().Button.UseColor == false,
    "an explicit Button colour opt-out is preserved")
BCDM.db.profile = savedProfile

Check(BCDM:SetupCustomGlows() == false, "glow hooks wait for Blizzard's alert manager")
local retryFrame = createdFrames[#createdFrames]
Check(retryFrame and retryFrame.events.ADDON_LOADED, "glow hooks register a late-load retry event")
ActionButtonSpellAlertManager = manager
retryFrame.scripts.OnEvent(retryFrame, "ADDON_LOADED", "Blizzard_ActionBar")
Check(BCDM:SetupCustomGlows() == true, "glow hooks install when Blizzard's alert manager exists")
Check(BCDM:SetupCustomGlows() == true, "glow hook setup is idempotent")

manager:ShowAlert(target)
Check((calls.start.Pixel or 0) == 1, "an active Blizzard alert starts one custom glow immediately")
Check(target.SpellActivationAlert.shown == true and target.SpellActivationAlert.alpha == 0,
    "the native alert is suppressed after the custom glow starts")
manager:HideAlert(target)
Check((calls.stop.Pixel or 0) >= 1 and target.SpellActivationAlert.alpha == 0.4,
    "ending the Blizzard alert stops the custom glow and restores its alpha")

manager:ShowAlert(target)
Check((calls.start.Pixel or 0) == 2, "a new Blizzard alert starts a new custom glow")
Check(target.SpellActivationAlert.shown == true and target.SpellActivationAlert.alpha == 0,
    "the replacement native alert is suppressed immediately")
Check(target.BCDMGlowType == nil and target.BCDMActiveGlow == nil,
    "BCDM does not store glow metadata on Blizzard frames")
Check(calls.lastFrame and calls.lastFrame.parent == target and calls.lastFrame.mouseEnabled == false,
    "LibCustomGlow renders on a mouse-disabled addon-owned overlay")
Check(calls.lastFrame and calls.lastFrame.cooldown == target.Cooldown,
    "the overlay exposes the source cooldown to ButtonGlow")
local glowOverlay = calls.lastFrame
glowOverlay.failSetAllPoints = true
Check(BCDM:StartCustomGlow(target), "geometry failures retain the last valid glow")
glowOverlay.failSetAllPoints = false

manager:ShowAlert(target)
Check((calls.start.Pixel or 0) == 2, "duplicate alert refreshes do not restart unchanged glows")

target.width = 48
target.height = 48
Check(BCDM:StartCustomGlow(target), "same-type starts accept target geometry changes")
Check((calls.start.Pixel or 0) == 3, "target geometry changes rebuild the active glow")
target.frameLevel = secretFrameLevel
Check(BCDM:StartCustomGlow(target), "secret frame levels fail closed without breaking glow state")
target.frameLevel = 1
target.width, target.height = 36, 36

BCDM.db.profile.CooldownManager.General.Glow.Pixel.Thickness = 3
BCDM:RefreshCustomGlows()
Check((calls.stop.Pixel or 0) >= 2 and (calls.start.Pixel or 0) >= 3,
    "settings refreshes rebuild active glow geometry")

manager:HideAlert(target)
local startsBeforeFailedStart = calls.start.Pixel or 0
local stopsBeforeFailedStart = calls.stop.Pixel or 0
glowFailures.start.Pixel = true
manager:ShowAlert(target)
Check((calls.start.Pixel or 0) > startsBeforeFailedStart
    and (calls.stop.Pixel or 0) > stopsBeforeFailedStart,
    "a failed start invokes the matching library stop")
Check(target.SpellActivationAlert.shown == true and target.SpellActivationAlert.alpha == 0.4,
    "a failed custom start leaves native artwork visible")
glowFailures.start.Pixel = nil
manager:HideAlert(target)

manager:ShowAlert(target)
local startsBeforeFailedStop = calls.start.Pixel or 0
glowFailures.stop.Pixel = true
Check(not BCDM:StopCustomGlow(target), "a failed library stop reports an incomplete cleanup")
Check(target.SpellActivationAlert.alpha == 0.4,
    "a failed replacement stop leaves native artwork visible")
Check(not BCDM:StartCustomGlow(target, true) and (calls.start.Pixel or 0) == startsBeforeFailedStop,
    "a failed stop prevents another renderer from starting")
glowFailures.stop.Pixel = nil
Check(BCDM:StopCustomGlow(target), "failed renderer cleanup succeeds on retry")
Check(#reportedErrors == 2, "renderer failures are reported once")
manager:HideAlert(target)

manager:ShowAlert(target)
manager:ShowAlert(secondTarget)
Check(target.SpellActivationAlert.alpha == 0 and secondTarget.SpellActivationAlert.alpha == 0,
    "active alerts are suppressed before disabling")
BCDM.db.profile.CooldownManager.General.Glow.Enabled = false
local showCallsBeforeDisable, hideCallsBeforeDisable = manager.showCalls, manager.hideCalls
BCDM:RefreshCustomGlows()
Check(manager:HasAlert(target) and manager:HasAlert(secondTarget),
    "disabling custom glows preserves every active Blizzard alert")
Check(target.SpellActivationAlert.shown == true and target.SpellActivationAlert.alpha == 0.4
    and secondTarget.SpellActivationAlert.shown == true and secondTarget.SpellActivationAlert.alpha == 0.4,
    "disabling custom glows restores every native alert alpha")
Check(manager.showCalls == showCallsBeforeDisable and manager.hideCalls == hideCallsBeforeDisable,
    "BCDM never restarts or hides an alert through Blizzard's manager")

BCDM.db.profile.CooldownManager.General.Glow.Enabled = true
BCDM:RefreshCustomGlows()
Check((calls.start.Pixel or 0) >= 4 and target.SpellActivationAlert.alpha == 0,
    "enabling custom glows adopts an already-active Blizzard alert")

manager:HideAlert(target)
manager:HideAlert(secondTarget)
Check((calls.stop.Pixel or 0) >= 3, "ending the Blizzard alert stops its custom glow")
Check(target.SpellActivationAlert.alpha == 0.4 and secondTarget.SpellActivationAlert.alpha == 0.4,
    "ending Blizzard alerts restores their native alpha")

manager:ShowAlert(target)
Check(target.SpellActivationAlert.alpha == 0, "the pooled row has an active custom glow before release")
viewer.itemFramePool:ReleaseAll()
Check(not manager:HasAlert(target), "pool release clears Blizzard alert state")
Check(target.SpellActivationAlert.alpha == 0.4, "pool release restores native alert alpha")
local startsBeforeInactiveRefresh = calls.start.Pixel or 0
BCDM:RefreshCustomGlows()
Check((calls.start.Pixel or 0) == startsBeforeInactiveRefresh,
    "RefreshCustomGlows does not restart a released row")
viewer.itemFramePool.activeFrames[target] = true
manager:ShowAlert(target)
Check((calls.start.Pixel or 0) >= 5 and target.SpellActivationAlert.alpha == 0,
    "a recycled row starts and suppresses its new custom glow")
manager:HideAlert(target)

local potionTarget = NewFrame(viewer)
potionTarget.SpellActivationAlert = NewFrame(potionTarget)
potionTarget.SpellActivationAlert:SetAlpha(0.4)
function potionTarget:IsItem() return true end
local pixelStartsBeforePotion = calls.start.Pixel or 0
manager:ShowAlert(potionTarget)
Check((calls.start.Pixel or 0) == pixelStartsBeforePotion and potionTarget.SpellActivationAlert.alpha == 0.4,
    "item-backed Cooldown Viewer rows are not adopted for custom glows")
manager:HideAlert(potionTarget)

local forbiddenTarget = NewFrame(viewer)
forbiddenTarget.SpellActivationAlert = NewFrame(forbiddenTarget)
forbiddenTarget.SpellActivationAlert:SetAlpha(0.4)
function forbiddenTarget:IsItem() return false end
function forbiddenTarget:IsForbidden() return true end
local startsBeforeForbidden = calls.start.Pixel or 0
manager:ShowAlert(forbiddenTarget)
Check((calls.start.Pixel or 0) == startsBeforeForbidden and forbiddenTarget.SpellActivationAlert.alpha == 0.4,
    "forbidden Cooldown Viewer rows are not adopted for custom glows")
manager:HideAlert(forbiddenTarget)

local combatTarget = NewFrame(viewer)
combatTarget.SpellActivationAlert = NewFrame(combatTarget)
combatTarget.SpellActivationAlert:SetAlpha(0.4)
function combatTarget:IsItem() return false end
local createdBeforeCombat = #createdFrames
inCombat = true
manager:ShowAlert(combatTarget)
Check(#createdFrames == createdBeforeCombat and combatTarget.SpellActivationAlert.alpha == 0.4,
    "combat prevents creating an unprepared glow overlay")
manager:HideAlert(combatTarget)
inCombat = false

for _, glowType in ipairs({ "Autocast", "Proc", "Button" }) do
    BCDM.db.profile.CooldownManager.General.Glow.Type = glowType
    Check(BCDM:StartCustomGlow(target, true), glowType .. " starts through the shared overlay path")
    Check((calls.start[glowType] or 0) == 1, glowType .. " calls its LibCustomGlow renderer")
end
Check(calls.buttonColor == nil and calls.buttonFrequency == 0.3,
    "ButtonGlow keeps ElvUI's original texture colours by default")
BCDM.db.profile.CooldownManager.General.Glow.Button.UseColor = true
Check(BCDM:StartCustomGlow(target, true), "ButtonGlow accepts its optional custom colour")
Check(calls.start.Button == 2 and calls.buttonColor
    and calls.buttonColor[1] == 0.95 and calls.buttonColor[2] == 0.95
    and calls.buttonColor[3] == 0 and calls.buttonColor[4] == 0.9,
    "ButtonGlow applies the configured custom colour when enabled")
BCDM:StopCustomGlow(target)

return failures == 0
