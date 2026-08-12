local root = (...)
if type(root) ~= "string" or root == "" then root = "." end
local unpack = unpack or table.unpack

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local combat = false
InCombatLockdown = function() return combat end
UIParent = { name = "UIParent" }
function UIParent:GetEffectiveScale() return 1 end

local timers = {}
C_Timer = {}
function C_Timer.After(_, callback) timers[#timers + 1] = callback end
local function RunTimers()
    local queued = timers
    timers = {}
    for _, callback in ipairs(queued) do callback() end
end
local createdFrames = {}
local function RunFrameUpdates()
    for _, frame in ipairs(createdFrames) do
        if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame) end
    end
end
local function NewFrame(parent)
    local frame = { parent = parent, shown = true, scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        local original = self.scripts[script]
        self.scripts[script] = function(...)
            if original then original(...) end
            callback(...)
        end
    end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetPoint(index)
        if index ~= 1 or not self.point then return end
        return unpack(self.point)
    end
    function frame:GetScale() return self.scale or 1 end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:GetEffectiveScale() return 1 end
    function frame:IsProtected() return self.protected == true end
    return frame
end
CreateFrame = function(_, name, parent)
    local frame = NewFrame(parent)
    frame.name = name
    if name then _G[name] = frame end
    createdFrames[#createdFrames + 1] = frame
    return frame
end

hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(...)
        local results = { original(...) }
        callback(...)
        return unpack(results)
    end
end

local function NewItem(index, width, height, itemBacked)
    local item = NewFrame(nil)
    item.layoutIndex = index
    item.cooldownID = index
    item.Icon = {}
    item.width, item.height = width, height
    function item:IsShown() return self.shown end
    function item:GetWidth() return self.width end
    function item:GetHeight() return self.height end
    function item:GetScale() return 1 end
    function item:OnActiveStateChanged() end
    function item:IsItem() return itemBacked == true end
    return item
end

local first = NewItem(1, 30, 20)
local second = NewItem(2, 30, 20)
local viewer = NewFrame(nil)
viewer.items = { second, first }
viewer.childXPadding = 4
viewer.childYPadding = 3
viewer.layoutFramesGoingRight = true
viewer.layoutFramesGoingUp = false
viewer.horizontal = true
function viewer:GetItemFrames() return self.items end
viewer.isHorizontal = true
function viewer:GetFrameStrata() return "MEDIUM" end
function viewer:GetFrameLevel() return 5 end
local nativeRefreshLayoutCalls = 0
function viewer:RefreshLayout()
    nativeRefreshLayoutCalls = nativeRefreshLayoutCalls + 1
    for _, item in ipairs(self.items) do item:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0) end
end
function viewer:RefreshData() end
function viewer:OnAcquireItemFrame() end

EssentialCooldownViewer = NewFrame(nil)
UtilityCooldownViewer = NewFrame(nil)
BuffIconCooldownViewer = viewer
EssentialCooldownViewer.system, EssentialCooldownViewer.systemIndex = 7, 1
UtilityCooldownViewer.system, UtilityCooldownViewer.systemIndex = 7, 2
viewer.system, viewer.systemIndex = 7, 3
local savedViewerUpdates, managerViewerRebinds = 0, 0
local function UpdateViewerSystem(self, systemInfo)
    self.lastSystemInfo = systemInfo
    if systemInfo.source == "saved" then savedViewerUpdates = savedViewerUpdates + 1
    else managerViewerRebinds = managerViewerRebinds + 1 end
end
EssentialCooldownViewer.UpdateSystem = UpdateViewerSystem
UtilityCooldownViewer.UpdateSystem = UpdateViewerSystem
viewer.UpdateSystem = UpdateViewerSystem
viewer.itemFramePool = {}
function viewer.itemFramePool:EnumerateActive()
    local index = 0
    return function()
        index = index + 1
        return viewer.items[index]
    end
end
function EssentialCooldownViewer:GetItemFrames() return {} end
function UtilityCooldownViewer:GetItemFrames() return {} end
function EssentialCooldownViewer:RefreshData() end
function UtilityCooldownViewer:RefreshData() end
local function NewSystemInfo(frame, source)
    return {
        system = frame.system, systemIndex = frame.systemIndex, source = source,
        anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
        settings = {},
    }
end
local savedSystems = {
    NewSystemInfo(EssentialCooldownViewer, "saved"),
    NewSystemInfo(UtilityCooldownViewer, "saved"),
    NewSystemInfo(viewer, "saved"),
}
local managerSystems = {
    NewSystemInfo(EssentialCooldownViewer, "manager"),
    NewSystemInfo(UtilityCooldownViewer, "manager"),
    NewSystemInfo(viewer, "manager"),
}
local function FindSystem(systems, system, systemIndex)
    for _, systemInfo in ipairs(systems) do
        if systemInfo.system == system and systemInfo.systemIndex == systemIndex then return systemInfo end
    end
end
local compactFrameRefreshes, managerAnchorSyncs = 0, 0
local compactFrame = {
    system = 8, systemIndex = 1,
    UpdateSystem = function() compactFrameRefreshes = compactFrameRefreshes + 1 end,
}
savedSystems[#savedSystems + 1] = NewSystemInfo(compactFrame, "saved")
managerSystems[#managerSystems + 1] = NewSystemInfo(compactFrame, "manager")
C_EditMode = {
    GetLayouts = function()
        return { activeLayout = 3, layouts = { { systems = savedSystems } } }
    end,
}
EditModePresetLayoutManager = {
    GetCopyOfPresetLayouts = function() return { {}, {} } end,
}
securecallfunction = function(callback, ...)
    return callback(...)
end
EditModeManagerFrame = {
    ExitEditMode = function() end,
    GetActiveLayoutSystemInfo = function(_, system, systemIndex)
        return FindSystem(managerSystems, system, systemIndex)
    end,
    UpdateSystemAnchorInfo = function(_, frame)
        managerAnchorSyncs = managerAnchorSyncs + 1
        local managerInfo = FindSystem(managerSystems, frame.system, frame.systemIndex)
        managerInfo.anchorInfo = frame.lastSystemInfo.anchorInfo
        return true
    end,
}
local eventCallbacks = {}
EventRegistry = {}
function EventRegistry:RegisterCallback(event, callback, owner)
    eventCallbacks[event] = eventCallbacks[event] or {}
    table.insert(eventCallbacks[event], { callback = callback, owner = owner })
end
function EventRegistry:TriggerEvent(event, ...)
    for _, registration in ipairs(eventCallbacks[event] or {}) do
        registration.callback(registration.owner, ...)
    end
end
CooldownViewerSettings = NewFrame(nil)
CooldownViewerSettings:Hide()
function CooldownViewerSettings:RefreshLayout() end
C_CVar = { SetCVar = function() end }
C_AddOns = { IsAddOnLoaded = function() return false end }
local now = 1
GetTime = function() return now end

local layoutCalls = { load = 0, reanchor = 0, save = 0, apply = 0, anchors = {} }
local editable = true
local ready = true
local simulateEditModeApply = false
local LEMO = {}
function LEMO:IsReady() return ready end
function LEMO:LoadLayouts() layoutCalls.load = layoutCalls.load + 1 end
function LEMO:CanEditActiveLayout() return editable end
function LEMO:ReanchorFrame(frame, ...)
    layoutCalls.reanchor = layoutCalls.reanchor + 1
    layoutCalls.anchors[frame] = { ... }
end
function LEMO:SaveOnly() layoutCalls.save = layoutCalls.save + 1 end
function LEMO:ApplyChanges()
    layoutCalls.apply = layoutCalls.apply + 1
    if simulateEditModeApply then
        EventRegistry:TriggerEvent("EditMode.Enter")
        viewer:RefreshLayout()
        EventRegistry:TriggerEvent("EditMode.Exit")
    end
end

local BCDM = {
    LEMO = LEMO,
    CooldownManagerViewers = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer" },
    CooldownManagerViewerToDBViewer = {
        EssentialCooldownViewer = "Essential", UtilityCooldownViewer = "Utility", BuffIconCooldownViewer = "Buffs",
    },
    DBViewerToCooldownManagerViewer = {
        Essential = "EssentialCooldownViewer", Utility = "UtilityCooldownViewer", Buffs = "BuffIconCooldownViewer",
    },
    db = { profile = {
        General = { Fonts = { FontFlag = "", Shadow = { Enabled = false } } },
        CooldownManager = {
            Enable = false,
            General = { IconZoom = 0, BorderSize = 1, CooldownText = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "CENTER", "CENTER", 0, 0 } } },
            Essential = { Layout = { "CENTER", "CENTER", 0, 0 }, Text = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "CENTER", "CENTER", 0, 0 } } },
            Utility = { Layout = { "TOP", "EssentialCooldownViewer", "BOTTOM", 0, -1 }, Text = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "CENTER", "CENTER", 0, 0 } } },
            Buffs = { CenterBuffs = true, Layout = { "BOTTOM", "UIParent", "TOP", 0, 1 }, Text = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "CENTER", "CENTER", 0, 0 } } },
        },
    } },
    Media = { Font = "font" },
}
function BCDM:IsSecretValue(value) return value == self.secretValue end
function BCDM:ResolveAnchorParent(name) return name == "UIParent" and UIParent or _G[name] or UIParent end
function BCDM:GetIconDimensions() return 30, 20 end
function BCDM:StripTextures() end
function BCDM:ApplyIconTexCoord() end
function BCDM:AddBorder(frame) frame.bcdmStyleCount = (frame.bcdmStyleCount or 0) + 1 end
function BCDM:UpdatePowerBarWidth() end
function BCDM:UpdateSecondaryPowerBarWidth() end
function BCDM:UpdateCastBarWidth() end

assert(loadfile(root .. "/Modules/CooldownManager.lua"))("BetterCooldownManager", BCDM)
Check(BCDM_PowerBar ~= nil and BCDM_SecondaryPowerBar ~= nil and BCDM_CastBar ~= nil,
    "BCM viewer anchor names exist before addon enablement for Edit Mode replay")

BCDM:QueueCooldownViewerLayoutApply()
BCDM:QueueCooldownViewerLayoutApply()
Check(#timers == 1, "viewer layout requests coalesce into one deferred application")
local viewerLayoutEventFrame = createdFrames[4]
RunTimers()
Check(layoutCalls.load == 1 and layoutCalls.reanchor == 3 and layoutCalls.save == 1
    and layoutCalls.apply == 0 and savedViewerUpdates == 3 and managerViewerRebinds == 3
    and managerAnchorSyncs == 3 and compactFrameRefreshes == 0,
    "the layout queue securely refreshes only Cooldown Viewer systems")

function BCDM_PowerBar:GetRect() return 100, 200, 300, 20 end
BCDM.db.profile.CooldownManager.Buffs.Layout = { "BOTTOM", "BCDM_PowerBar", "TOP", 4, 5 }
BCDM:QueueCooldownViewerLayoutApply()
RunTimers()
local persistedBuffAnchor = layoutCalls.anchors[BuffIconCooldownViewer]
Check(persistedBuffAnchor[2] == UIParent and persistedBuffAnchor[3] == "BOTTOMLEFT",
    "addon-owned anchors are persisted relative to UIParent for safe login replay")
Check(persistedBuffAnchor[4] == 254 and persistedBuffAnchor[5] == 225,
    "the UIParent anchor preserves the addon frame's visual position")

combat = true
BCDM:QueueCooldownViewerLayoutApply()
RunTimers()
Check(layoutCalls.apply == 0 and layoutCalls.save == 2,
    "viewer layouts are not applied during combat")
combat = false
viewerLayoutEventFrame.scripts.OnEvent(viewerLayoutEventFrame, "PLAYER_REGEN_ENABLED")
Check(layoutCalls.save == 3, "a combat-deferred viewer layout applies after combat")

editable = false
BCDM:QueueCooldownViewerLayoutApply()
RunTimers()
Check(layoutCalls.save == 3, "preset Edit Mode layouts are left unchanged")
editable = true
viewerLayoutEventFrame.scripts.OnEvent(viewerLayoutEventFrame, "EDIT_MODE_LAYOUTS_UPDATED")
Check(layoutCalls.save == 4, "a pending viewer layout retries after leaving a preset layout")

viewer:RefreshLayout()
nativeRefreshLayoutCalls = 0
BCDM.db.profile.CooldownManager.Enable = true
BCDM:SkinCooldownManager()
RunTimers()
RunFrameUpdates()
RunFrameUpdates()
Check(nativeRefreshLayoutCalls == 0,
    "BCM initialization never invokes Blizzard's Tracked Buff RefreshLayout")
local centeredOwner = createdFrames[#createdFrames - 1]
Check(first.point[2] == centeredOwner and second.point[2] == centeredOwner,
    "native Tracked Buff rows use the BCM-owned centering anchor")
Check(first.point[4] == 0 and second.point[4] == 34,
    "native Tracked Buff rows preserve sorted layout order and spacing")

viewer:RefreshLayout()
RunFrameUpdates()
RunFrameUpdates()
Check(first.point[2] == centeredOwner and second.point[2] == centeredOwner,
    "native viewer layout changes are re-centered after Blizzard's layout call")

CooldownViewerSettings:Show()
EventRegistry:TriggerEvent("CooldownViewerSettings.OnShow", CooldownViewerSettings)
Check(first.point[2] == viewer and second.point[2] == viewer,
    "native rows return to Blizzard ownership while settings are open")
CooldownViewerSettings:Hide()
EventRegistry:TriggerEvent("CooldownViewerSettings.OnHide", CooldownViewerSettings)
RunFrameUpdates()
RunFrameUpdates()
Check(first.point[2] == centeredOwner and second.point[2] == centeredOwner,
    "native rows are re-centered after settings close")

BCDM.db.profile.CooldownManager.Enable = true
local editorSpell = NewItem(7, 44, 40, false)
viewer.items = { editorSpell }
CooldownViewerSettings:Show()
EventRegistry:TriggerEvent("CooldownViewerSettings.OnShow", CooldownViewerSettings)
viewer:RefreshData()
RunTimers()
Check(editorSpell.bcdmStyleCount == 1 and editorSpell.width == 44 and editorSpell.height == 40,
    "native Tracked Buff editor rows are skinned without changing Blizzard's layout dimensions")
CooldownViewerSettings:Hide()
EventRegistry:TriggerEvent("CooldownViewerSettings.OnHide", CooldownViewerSettings)
RunTimers()
viewer.items = { second, first }

simulateEditModeApply = true
local appliesBeforeFeedbackTest = layoutCalls.apply
BCDM:QueueCooldownViewerLayoutApply()
RunTimers()
RunTimers()
Check(layoutCalls.apply == appliesBeforeFeedbackTest and #timers == 0,
    "BCM layout refresh never enters Edit Mode or feeds back through RefreshLayout")
simulateEditModeApply = false

local appliedLayouts = layoutCalls.apply
local savesBefore = layoutCalls.save
CooldownViewerSettings:Show()
EventRegistry:TriggerEvent("CooldownViewerSettings.OnShow", CooldownViewerSettings)
BCDM:QueueCooldownViewerLayoutApply()
RunTimers()
Check(layoutCalls.apply == appliedLayouts and layoutCalls.save == savesBefore + 1,
    "viewer layouts update live without closing Blizzard Cooldown Manager settings")
CooldownViewerSettings:Hide()
EventRegistry:TriggerEvent("CooldownViewerSettings.OnHide", CooldownViewerSettings)
RunTimers()
Check(layoutCalls.apply == appliedLayouts,
    "a live viewer layout does not need a second apply after native settings close")

BetterCooldownManagerSettingsWindow = NewFrame(nil)
savesBefore = layoutCalls.save
BCDM:QueueCooldownViewerLayoutApply()
RunTimers()
Check(layoutCalls.apply == appliedLayouts and layoutCalls.save == savesBefore + 1,
    "viewer layouts update live while BCM settings are open")
BetterCooldownManagerSettingsWindow:Hide()
BCDM:RetryPendingCooldownViewerLayoutApply()
RunTimers()
Check(layoutCalls.apply == appliedLayouts,
    "a live viewer layout does not need a second apply after BCM settings close")
BetterCooldownManagerSettingsWindow = nil
BCDM:RetryPendingCooldownViewerLayoutApply()
Check(#timers == 0, "closing settings without pending positions does not apply Edit Mode layouts")

local lateSpell = NewItem(6, 12, 12, false)
viewer.items = { second, first, lateSpell }
BCDM.db.profile.CooldownManager.Enable = true
viewer:RefreshData()
RunTimers()
Check(lateSpell.bcdmStyleCount == 1 and lateSpell.width == 30 and lateSpell.height == 20,
    "spell rows acquired after login are styled after viewer data refreshes")

combat = true
viewer:RefreshLayout()
RunTimers()
local refreshCallsAfterNativeLayout = nativeRefreshLayoutCalls
BCDM:UpdateCooldownViewer("Buffs")
RunTimers()
Check(nativeRefreshLayoutCalls == refreshCallsAfterNativeLayout,
    "BCM updates never re-enter Blizzard RefreshLayout")
combat = false
viewerLayoutEventFrame.scripts.OnEvent(viewerLayoutEventFrame, "PLAYER_REGEN_ENABLED")
RunTimers()

local forbidden = NewItem(4, 30, 20, false)
function forbidden:IsForbidden() return true end
Check(not BCDM:IsCustomizableCooldownViewerItem(forbidden),
    "forbidden Cooldown Viewer rows are not customizable")
local unreadable = NewItem(5, 30, 20, false)
function unreadable:IsItem() error("secret item state") end
Check(not BCDM:IsCustomizableCooldownViewerItem(unreadable),
    "unreadable Cooldown Viewer rows are not customizable")

local optionsFile = assert(io.open(root .. "/Options/Settings.lua", "r"))
local optionsSource = optionsFile:read("*a")
optionsFile:close()
Check(not optionsSource:find("SetDisplayMode", 1, true),
    "BCM never writes Blizzard's native Cooldown Manager display mode")
Check(optionsSource:find("securecallfunction", 1, true) ~= nil,
    "automatic native Cooldown Manager opening crosses a secure call boundary")

local cooldownFile = assert(io.open(root .. "/Modules/CooldownManager.lua", "r"))
local cooldownSource = cooldownFile:read("*a")
cooldownFile:close()
Check(not cooldownSource:find("pcall(viewer.RefreshLayout", 1, true),
    "BCM has no direct native RefreshLayout restore path")
Check(not cooldownSource:find("LEMO:ApplyChanges", 1, true),
    "BCM never opens Edit Mode from addon code")
Check(not cooldownSource:find("UpdateLayoutInfo", 1, true)
    and not cooldownSource:find("registeredSystemFrames", 1, true),
    "BCM never refreshes or replaces Edit Mode manager internals")
Check(cooldownSource:find("UpdateSystemAnchorInfo", 1, true) ~= nil,
    "BCM synchronizes only native Cooldown Viewer anchors")

return failures == 0
