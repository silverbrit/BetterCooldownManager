local root = (...)
if type(root) ~= "string" or root == "" then root = "." end
local unpack = unpack or table.unpack

local failures = 0
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

local glowLibrary = {
    PixelGlow_Start = function(frame) Record("start", "Pixel", frame) end,
    PixelGlow_Stop = function(frame) Record("stop", "Pixel", frame) end,
    AutoCastGlow_Start = function(frame) Record("start", "Autocast", frame) end,
    AutoCastGlow_Stop = function(frame) Record("stop", "Autocast", frame) end,
    ProcGlow_Start = function(frame) Record("start", "Proc", frame) end,
    ProcGlow_Stop = function(frame) Record("stop", "Proc", frame) end,
    ButtonGlow_Start = function(frame) Record("start", "Button", frame) end,
    ButtonGlow_Stop = function(frame) Record("stop", "Button", frame) end,
}

LibStub = function(name)
    if name == "LibCustomGlow-1.0" then return glowLibrary end
end

local function NewFrame(parent)
    local frame = { parent = parent, shown = true, frameLevel = 1, hooks = {}, events = {}, scripts = {} }
    function frame:GetParent() return self.parent end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:ClearAllPoints() self.cleared = true end
    function frame:SetAllPoints(target) self.allPoints = target end
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

CreateFrame = function(_, _, parent) return NewFrame(parent) end
geterrorhandler = function()
    return function(message) io.stderr:write(tostring(message) .. "\n") end
end

local timers = {}
C_Timer = {}
function C_Timer.NewTimer(_, callback)
    local timer = { callback = callback, cancelled = false }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
local function RunTimers()
    local queued = timers
    timers = {}
    for _, timer in ipairs(queued) do
        if not timer.cancelled then timer.callback() end
    end
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
function target:IsItem() return false end
viewer.itemFramePool = {}
function viewer.itemFramePool:EnumerateActive()
    local yielded = false
    return function()
        if yielded then return nil end
        yielded = true
        return target
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
        Button = { Color = { 1, 1, 1, 1 }, Frequency = 0.125 },
    } } } } },
}
function BCDM:IsSecretValue() return false end
function BCDM:IsCustomizableCooldownViewerItem(frame)
    if not frame or not frame.IsItem then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    local ok, isItem = pcall(frame.IsItem, frame)
    return ok and isItem == false
end

assert(loadfile(root .. "/Modules/CustomGlows.lua"))("BetterCooldownManager", BCDM)

Check(BCDM:SetupCustomGlows() == false, "glow hooks wait for Blizzard's alert manager")
ActionButtonSpellAlertManager = manager
Check(BCDM:SetupCustomGlows() == true, "glow hooks install when Blizzard's alert manager exists")
Check(BCDM:SetupCustomGlows() == true, "glow hook setup is idempotent")

manager:ShowAlert(target)
manager:HideAlert(target)
RunTimers()
Check((calls.start.Pixel or 0) == 0, "a hidden alert cancels its deferred custom glow")

manager:ShowAlert(target)
RunTimers()
Check((calls.start.Pixel or 0) == 1, "an active Blizzard alert starts one custom glow")
Check(target.SpellActivationAlert.shown == true and target.SpellActivationAlert.alpha == 0,
    "the native alert keeps running with its artwork suppressed after the custom glow starts")
Check(target.BCDMGlowType == nil and target.BCDMActiveGlow == nil,
    "BCDM does not store glow metadata on Blizzard frames")
Check(calls.lastFrame and calls.lastFrame.parent == target and calls.lastFrame.mouseEnabled == false,
    "LibCustomGlow renders on a mouse-disabled addon-owned overlay")

manager:ShowAlert(target)
RunTimers()
Check((calls.start.Pixel or 0) == 1, "duplicate alert refreshes do not restart unchanged glows")

BCDM.db.profile.CooldownManager.General.Glow.Pixel.Thickness = 3
BCDM:RefreshCustomGlows()
RunTimers()
Check((calls.stop.Pixel or 0) >= 1 and (calls.start.Pixel or 0) >= 2,
    "settings refreshes rebuild active glow geometry")

BCDM.db.profile.CooldownManager.General.Glow.Enabled = false
local showCallsBeforeDisable, hideCallsBeforeDisable = manager.showCalls, manager.hideCalls
BCDM:RefreshCustomGlows()
Check(manager:HasAlert(target), "disabling custom glows preserves the active Blizzard alert state")
Check(target.SpellActivationAlert.shown == true and target.SpellActivationAlert.alpha == 1,
    "disabling custom glows restores the native alert artwork")
Check(manager.showCalls == showCallsBeforeDisable and manager.hideCalls == hideCallsBeforeDisable,
    "BCDM never restarts or hides an alert through Blizzard's manager")

BCDM.db.profile.CooldownManager.General.Glow.Enabled = true
BCDM:RefreshCustomGlows()
RunTimers()
Check((calls.start.Pixel or 0) >= 3 and target.SpellActivationAlert.alpha == 0,
    "enabling custom glows adopts an already-active Blizzard alert")

manager:HideAlert(target)
Check((calls.stop.Pixel or 0) >= 2, "ending the Blizzard alert stops its custom glow")
Check(target.SpellActivationAlert.alpha == 1, "ending the Blizzard alert restores its artwork alpha")

local potionTarget = NewFrame(viewer)
potionTarget.SpellActivationAlert = NewFrame(potionTarget)
function potionTarget:IsItem() return true end
local pixelStartsBeforePotion = calls.start.Pixel or 0
manager:ShowAlert(potionTarget)
RunTimers()
Check((calls.start.Pixel or 0) == pixelStartsBeforePotion and potionTarget.SpellActivationAlert.alpha == nil,
    "item-backed Cooldown Viewer rows are not adopted for custom glows")
manager:HideAlert(potionTarget)

for _, glowType in ipairs({ "Autocast", "Proc", "Button" }) do
    BCDM.db.profile.CooldownManager.General.Glow.Type = glowType
    Check(BCDM:StartCustomGlow(target, true), glowType .. " starts through the shared overlay path")
    Check((calls.start[glowType] or 0) == 1, glowType .. " calls its LibCustomGlow renderer")
end
BCDM:StopCustomGlow(target)

return failures == 0
