local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local secretDuration = setmetatable({}, {
    __lt = function() error("secret duration was compared") end,
    __tostring = function() error("secret duration was formatted") end,
    __index = function() error("secret duration was read") end,
})
local secretStageList = {}
local secretText = setmetatable({}, {
    __tostring = function() error("secret text was formatted") end,
    __index = function() error("secret text was read") end,
})
local castInfo, channelInfo
local durations = {}

local function NewRegion(width, height)
    local region = { width = width or 200, height = height or 24, shown = true }
    function region:SetColorTexture(...) self.color = { ... } end
    function region:SetSize(widthValue, heightValue) self.width, self.height = widthValue, heightValue end
    function region:SetPoint(...) self.point = { ... } end
    function region:ClearAllPoints() self.point = nil end
    function region:SetParent(parent) self.parent = parent end
    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:SetTexture(texture) self.texture = texture end
    function region:SetTexCoord(...) self.texCoord = { ... } end
    function region:SetFont(...) self.font = { ... } end
    function region:SetTextColor(...) self.textColor = { ... } end
    function region:SetShadowColor(...) self.shadowColor = { ... } end
    function region:SetShadowOffset(...) self.shadowOffset = { ... } end
    function region:SetText(text) self.text = text end
    return region
end

local function NewFrame(name, parent)
    local frame = NewRegion(200, 24)
    frame.name, frame.parent, frame.events, frame.scripts = name, parent, {}, {}
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        local previous = self.scripts[script]
        self.scripts[script] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function frame:GetScript(script) return self.scripts[script] end
    function frame:IsShown() return self.shown end
    function frame:Show()
        local wasShown = self.shown
        self.shown = true
        if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frame:Hide() self.shown = false end
    function frame:SetBackdrop(value) self.backdrop = value end
    function frame:SetBackdropBorderColor(...) self.borderColor = { ... } end
    function frame:SetBackdropColor(...) self.backdropColor = { ... } end
    function frame:SetFrameStrata(value) self.strata = value end
    function frame:SetWidth(value) self.width, self.widthWrites = value, (self.widthWrites or 0) + 1 end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:CreateTexture() return NewRegion(self.width, self.height) end
    function frame:CreateFontString() return NewRegion(self.width, self.height) end
    function frame:SetStatusBarTexture(value) self.statusTexture = value end
    function frame:SetStatusBarColor(...) self.statusColor = { ... } end
    function frame:SetReverseFill(value) self.reverseFill = value end
    function frame:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
    function frame:SetValue(value) self.value = value end
    function frame:SetTimerDuration(duration, interpolation, direction)
        self.timerCalls = self.timerCalls or {}
        self.timerCalls[#self.timerCalls + 1] = {
            duration = duration, interpolation = interpolation, direction = direction,
        }
    end
    function frame:SetToTargetValue() self.snapped = true end
    return frame
end

local anchor = NewFrame("Anchor", nil)
anchor.width = 180
UIParent = NewFrame("UIParent", nil)
local nativeCastBar = { shown = true, showCastbar = true, casting = false, channeling = false, calls = {} }
function nativeCastBar:UpdateShownState(shown) self.shown = shown end
function nativeCastBar:OnEvent(event)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        self.channeling, self.casting = true, false
    elseif event == "PLAYER_ENTERING_WORLD" then
        self.enteringWorldCalls = (self.enteringWorldCalls or 0) + 1
        if channelInfo then
            self.channeling, self.casting = true, false
            self.shown = self.showCastbar
        elseif castInfo then
            self.channeling, self.casting = false, true
            self.shown = self.showCastbar
        else
            self.channeling, self.casting, self.shown = false, false, false
        end
    end
end
function nativeCastBar:SetAndUpdateShowCastbar(shown)
    self.showCastbar = shown
    self.calls[#self.calls + 1] = shown
    if self.casting then self:OnEvent("PLAYER_ENTERING_WORLD") else self:UpdateShownState(false) end
end
PlayerCastingBarFrame = nativeCastBar

local timers = {}
C_Timer = {}
function C_Timer.NewTimer(delay, callback)
    local timer = { delay = delay, callback = callback, cancelled = false }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
local function RunTimers()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do
        if not timer.cancelled then timer.callback() end
    end
end

C_DurationUtil = {
    CreateDurationTextBinding = function()
        local binding = { enabled = false }
        function binding:SetFormatter(formatter) self.formatter = formatter end
        function binding:SetFontString(fontString) self.fontString = fontString end
        function binding:SetUpdateInterval(interval) self.interval = interval end
        function binding:SetExpiredText(text) self.expiredText = text end
        function binding:SetZeroDurationText(text) self.zeroText = text end
        function binding:SetEnabled(enabled) self.enabled = enabled end
        function binding:SetDuration(duration) self.duration = duration end
        function binding:UpdateFontString() self.updates = (self.updates or 0) + 1 end
        return binding
    end,
}
C_StringUtil = {
    CreateSecondsFormatter = function()
        local formatter = {}
        function formatter:SetDesiredUnitCount() end
        function formatter:SetMinInterval() end
        function formatter:SetDefaultAbbreviation() end
        function formatter:SetRounding() end
        function formatter:SetMillisecondsThreshold() end
        return formatter
    end,
}
Enum = {
    StatusBarInterpolation = { Immediate = "immediate" },
    StatusBarTimerDirection = { ElapsedTime = "elapsed", RemainingTime = "remaining" },
    SecondsFormatterInterval = { Seconds = 0 },
    SecondsFormatterAbbreviation = { None = 0 },
    SecondsFormatterRounding = { Truncate = 1 },
}
RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.6, b = 1 } }
UnitClass = function() return "Mage", "MAGE" end
UnitCastingInfo = function()
    if not castInfo then return end
    return castInfo.name, castInfo.displayName, castInfo.texture, 1000, 3000, false,
        castInfo.guid, castInfo.notInterruptible, castInfo.spellID, castInfo.id
end
UnitChannelInfo = function()
    if not channelInfo then return end
    return channelInfo.name, channelInfo.displayName, channelInfo.texture, 1000, 3000, false,
        channelInfo.notInterruptible, channelInfo.spellID, channelInfo.empowered, channelInfo.stages, channelInfo.id
end
UnitCastingDuration = function() return durations.cast end
UnitChannelDuration = function() return durations.channel end
UnitEmpoweredChannelDuration = function() return durations.empower end
UnitEmpoweredStagePercentages = function() return durations.stages end
CreateFrame = function(_, name, parent)
    local frame = NewFrame(name, parent)
    if name then _G[name] = frame end
    return frame
end

local BCDM = {
    BACKDROP = {},
    Media = { Font = "font", Foreground = "foreground" },
    db = { profile = {
        General = { Fonts = { FontFlag = "", Shadow = { Enabled = false } } },
        CooldownManager = { General = { BorderSize = 1, IconZoom = 0 } },
        CastBar = {
            Enabled = true, Width = 200, Height = 24, MatchWidthOfAnchor = true,
            FrameStrata = "LOW", FillDirection = "RIGHT", BackgroundColour = { 0, 0, 0, 1 },
            ForegroundColour = { 1, 1, 1, 1 }, ColourMode = "CUSTOM",
            InterruptibleColour = { 0, 1, 0, 1 }, NonInterruptibleColour = { 1, 0, 0, 1 },
            EmpowerPips = { Colour = { 1, 1, 1, 1 }, Width = 1 },
            Layout = { "TOP", "BCDM_TestAnchor", "BOTTOM", 0, 0 },
            Text = {
                SpellName = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "LEFT", "LEFT", 0, 0 }, MaxCharacters = 20 },
                CastTime = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "RIGHT", "RIGHT", 0, 0 } },
            },
            Icon = { Enabled = true, Layout = "LEFT" },
        },
    } },
}
_G.BCDM_TestAnchor = anchor
function BCDM:IsSecretValue(value)
    return value == secretDuration or value == secretStageList or value == secretText
end
function BCDM:ResolveBarFillColour() return 1, 1, 1, 1 end
function BCDM:ApplyStatusBarDirection(statusBar, direction) statusBar.direction = direction end
function BCDM:ResolveAnchorParent() return anchor end
function BCDM:RegisterOwnedFrameVisibility(frame, _, refresh)
    frame:HookScript("OnShow", function(self)
        if refresh and self.CastActive and self.HasDuration then refresh(self) end
    end)
end

_G.BCDM_CastBar = nil
assert(loadfile(root .. "/Modules/CastBar.lua"))("BetterCooldownManager", BCDM)
BCDM:CreateCastBar()
local bar = BCDM.CastBar
local handleEvent = BCDM._CastBarTest.HandleEvent
local displayCastText = BCDM._CastBarTest.GetDisplayCastText

local leftSmartQuote = "\226\128\152"
local rightSmartQuote = "\226\128\153"
Check(displayCastText("L" .. rightSmartQuote .. "été" .. leftSmartQuote .. "café", 99) == "L'été'café",
    "French smart quotes normalize to ASCII apostrophes")
Check(displayCastText("l`été", 99) == "l'été", "backticks normalize to ASCII apostrophes")
local korean = "한국어테스트"
for length, expected in ipairs({ "한", "한국", "한국어", "한국어테" }) do
    Check(displayCastText(korean, length) == expected, "Korean text truncates at UTF-8 code point length " .. length)
end
Check(displayCastText(nil, 2) == "" and displayCastText(123, 2) == "", "nil and non-string cast text are empty")
local returnedSecretText
local secretTextOK = pcall(function() returnedSecretText = displayCastText(secretText, 1) end)
Check(secretTextOK and returnedSecretText == secretText, "secret cast text passes through without inspection")

Check(nativeCastBar.shown == false, "enabling BCM hides the native cast bar through Blizzard's API")
Check(bar.events.PLAYER_ENTERING_WORLD and bar.events.UNIT_SPELLCAST_DELAYED and bar.events.UNIT_SPELLCAST_CHANNEL_UPDATE
    and bar.events.UNIT_SPELLCAST_EMPOWER_UPDATE, "resync and timing update events are registered")

local function StartNormal(id, duration)
    castInfo = { name = "Arcane Cast", displayName = "Arcane Cast", texture = 123,
        guid = "secret-guid", notInterruptible = false, spellID = 1, id = id }
    channelInfo = nil
    durations.cast = duration
    handleEvent(bar, "UNIT_SPELLCAST_START", "player", "guid", 1, id)
end

local firstDuration = {}
StartNormal(101, secretDuration)
Check(bar.CastActive and bar.ActiveCastID == 101 and bar.HasDuration, "normal casts bind their duration object")
Check(bar.Status.timerCalls[#bar.Status.timerCalls].duration == secretDuration
    and bar.Status.timerCalls[#bar.Status.timerCalls].interpolation == Enum.StatusBarInterpolation.Immediate
    and bar.Status.timerCalls[#bar.Status.timerCalls].direction == Enum.StatusBarTimerDirection.ElapsedTime,
    "normal casts use immediate elapsed native duration fill")
Check(bar.CastTimeBinding.duration == secretDuration and bar.scripts.OnUpdate == nil,
    "secret durations go directly to widgets without a Lua countdown")

local ok = pcall(function()
    durations.cast = nil
    StartNormal(102, nil)
end)
Check(ok and bar.CastActive and not bar.HasDuration and not bar:IsShown(),
    "a nil cast duration fails closed without replacing the prior timer with nil")

castInfo = { name = "World Cast", displayName = "World Cast", texture = 123,
    guid = "world-cast-guid", notInterruptible = false, spellID = 4, id = 1501 }
channelInfo = nil
durations.cast = firstDuration
handleEvent(bar, "PLAYER_ENTERING_WORLD", true, false)
Check(bar.CastActive and bar.ActiveKind == "cast" and bar.ActiveCastID == 1501,
    "PLAYER_ENTERING_WORLD resyncs a current cast without a start event")
handleEvent(bar, "UNIT_SPELLCAST_STOP", "player", "guid", 4, 1501)

castInfo = nil
channelInfo = { name = "World Channel", displayName = "World Channel", texture = 456,
    guid = "world-channel-guid", notInterruptible = true, spellID = 5, empowered = false, stages = nil, id = 1502 }
durations.channel = firstDuration
handleEvent(bar, "PLAYER_ENTERING_WORLD", false, true)
Check(bar.CastActive and bar.ActiveKind == "channel" and bar.ActiveCastID == 1502,
    "PLAYER_ENTERING_WORLD resyncs a current channel without a start event")
handleEvent(bar, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 5, nil, nil)

StartNormal(201, firstDuration)
local activeID = bar.ActiveCastID
handleEvent(bar, "UNIT_SPELLCAST_FAILED", "player", "guid", 1, 200)
Check(bar.CastActive and bar.ActiveCastID == activeID, "a stale failed cast ID leaves the current cast visible")
handleEvent(bar, "UNIT_SPELLCAST_INTERRUPTED", "player", "guid", 1, "interrupting-guid", 200)
Check(bar.CastActive, "a stale interrupted cast ID leaves the current cast visible")
handleEvent(bar, "UNIT_SPELLCAST_STOP", "player", "guid", 1, 200)
Check(bar.CastActive, "a stale stopped cast ID leaves the current cast visible")
handleEvent(bar, "UNIT_SPELLCAST_STOP", "player", "guid", 1, nil)
Check(not bar.CastActive and bar.ActiveCastID == nil, "a missing stopped cast ID still clears the active cast")
StartNormal(202, firstDuration)
handleEvent(bar, "UNIT_SPELLCAST_FAILED", "player", "guid", 1, nil)
Check(not bar.CastActive and bar.ActiveCastID == nil, "a missing failed cast ID still clears the active cast")
StartNormal(203, firstDuration)
handleEvent(bar, "UNIT_SPELLCAST_INTERRUPTED", "player", "guid", 1, "interrupting-guid", nil)
Check(not bar.CastActive and bar.ActiveCastID == nil, "a missing interrupted cast ID still clears the active cast")
StartNormal(204, firstDuration)
handleEvent(bar, "UNIT_SPELLCAST_FAILED", "player", "guid", 1, 204)
Check(not bar.CastActive and bar.ActiveCastID == nil, "a matching failed cast ID clears the active cast")

castInfo = { name = "No ID Cast", displayName = "No ID Cast", texture = 123,
    guid = "no-id-guid", notInterruptible = false, spellID = 6, id = nil }
channelInfo = nil
durations.cast = firstDuration
handleEvent(bar, "UNIT_SPELLCAST_START", "player", "guid", 6, nil)
Check(bar.CastActive and bar.ActiveCastID == nil, "casts may remain active without a readable cast ID")
handleEvent(bar, "UNIT_SPELLCAST_STOP", "player", "guid", 6, 999)
Check(not bar.CastActive and bar.ActiveCastID == nil, "a numeric stop ID cannot stale-match a missing active ID")

local channelDuration = {}
channelInfo = { name = "Channel", displayName = "Channel", texture = 456,
    guid = "channel-guid", notInterruptible = true, spellID = 2, empowered = false, stages = nil, id = 301 }
durations.channel = channelDuration
ok = pcall(function() handleEvent(bar, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 2, 301) end)
Check(ok and bar.CastActive and bar.ActiveKind == "channel", "channel starts remain valid with readable metadata")
Check(bar.Status.timerCalls[#bar.Status.timerCalls].duration == channelDuration
    and bar.Status.timerCalls[#bar.Status.timerCalls].direction == Enum.StatusBarTimerDirection.RemainingTime,
    "channel duration binds with RemainingTime")
local channelCalls = #bar.Status.timerCalls
durations.channel = {}
handleEvent(bar, "UNIT_SPELLCAST_CHANNEL_UPDATE", "player", "guid", 2, 301)
Check(#bar.Status.timerCalls == channelCalls + 1 and bar.Status.timerCalls[#bar.Status.timerCalls].duration == durations.channel,
    "channel updates rebind the current duration")
durations.channel = nil
Check(pcall(function() handleEvent(bar, "UNIT_SPELLCAST_CHANNEL_UPDATE", "player", "guid", 2, 301) end),
    "a nil channel duration is ignored safely")
handleEvent(bar, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 2, "interrupting-guid", 999)
Check(bar.CastActive and bar.ActiveCastID == 301, "a stale channel stop ID leaves the current channel visible")
handleEvent(bar, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid", 2, nil, nil)
Check(not bar.CastActive and bar.ActiveCastID == nil, "channel stop clears the active ID when castBarID is nil")

local empowerDuration = {}
channelInfo = { name = "Empower", displayName = "Empower", texture = 789,
    guid = "empower-guid", notInterruptible = false, spellID = 3, empowered = true, stages = nil, id = 401 }
durations.empower = empowerDuration
durations.stages = nil
ok = pcall(function() handleEvent(bar, "UNIT_SPELLCAST_EMPOWER_START", "player", "guid", 3, 401) end)
Check(ok and bar.CastActive and bar.ActiveKind == "empower" and #bar.Pips == 0,
    "nil empowered stages do not error or create invalid pips")
Check(bar.Status.timerCalls[#bar.Status.timerCalls].duration == empowerDuration
    and bar.Status.timerCalls[#bar.Status.timerCalls].direction == Enum.StatusBarTimerDirection.ElapsedTime,
    "empowered casts use the verified elapsed direction")
local empowerCalls = #bar.Status.timerCalls
durations.empower = {}
handleEvent(bar, "UNIT_SPELLCAST_EMPOWER_UPDATE", "player", "guid", 3, 401)
Check(#bar.Status.timerCalls == empowerCalls + 1 and bar.Status.timerCalls[#bar.Status.timerCalls].duration == durations.empower,
    "empowered updates rebind the current duration")
durations.empower = nil
Check(pcall(function() handleEvent(bar, "UNIT_SPELLCAST_EMPOWER_UPDATE", "player", "guid", 3, 401) end),
    "a nil empowered duration is ignored safely")
handleEvent(bar, "UNIT_SPELLCAST_EMPOWER_STOP", "player", "guid", 3, false, nil, 999)
Check(bar.CastActive and bar.ActiveCastID == 401, "a stale empower stop ID leaves the current empower visible")
handleEvent(bar, "UNIT_SPELLCAST_EMPOWER_STOP", "player", "guid", 3, false, nil, nil)
Check(not bar.CastActive and bar.ActiveCastID == nil, "empower stop clears the active ID when castBarID is nil")

StartNormal(501, {})
local delayedCalls = #bar.Status.timerCalls
durations.cast = {}
handleEvent(bar, "UNIT_SPELLCAST_DELAYED", "player", "guid", 1, 501)
Check(#bar.Status.timerCalls == delayedCalls + 1 and bar.Status.timerCalls[#bar.Status.timerCalls].duration == durations.cast,
    "delayed cast updates rebind the current duration")

castInfo = nil
channelInfo = { name = "Native Channel", displayName = "Native Channel", texture = 456,
    guid = "native-channel-guid", notInterruptible = true, spellID = 7, empowered = false, stages = nil, id = 601 }
durations.channel = {}
handleEvent(bar, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7, 601)
nativeCastBar:OnEvent("UNIT_SPELLCAST_CHANNEL_START")
local oldNativeCallCount = #nativeCastBar.calls
local oldNativeResyncCount = nativeCastBar.enteringWorldCalls or 0
BCDM.db.profile.CastBar.Enabled = false
BCDM:UpdateCastBar()
Check(nativeCastBar.shown == true and #nativeCastBar.calls > oldNativeCallCount
    and (nativeCastBar.enteringWorldCalls or 0) > oldNativeResyncCount,
    "disabling BCM restores an active channel through Blizzard's entering-world resync")
Check(not bar.CastActive and bar.ActiveCastID == nil and bar.scripts.OnEvent == nil
    and bar.scripts.OnUpdate == nil and next(bar.events) == nil and not bar.CastTimeBinding.enabled,
    "disabling BCM clears events, duration bindings, IDs, and updater scripts")

channelInfo = nil
BCDM.db.profile.CastBar.Enabled = true
BCDM:UpdateCastBar()
bar.widthWrites = 0
anchor.width = 120
BCDM:UpdateCastBarWidth()
anchor.width = 240
BCDM:UpdateCastBarWidth()
RunTimers()
Check(bar.width == 240 and bar.widthWrites == 1,
    "only the newest delayed width callback applies current anchor settings")

return failures == 0
