local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

Enum = {
    EditModeCooldownViewerSetting = { IconSize = 3, VisibleSetting = 7 },
    CooldownViewerVisibleSetting = { Always = 0, InCombat = 1, Hidden = 2 },
}
BuffIconCooldownViewer = {}

local frameSettings = {
    [Enum.EditModeCooldownViewerSetting.IconSize] = 110,
    [Enum.EditModeCooldownViewerSetting.VisibleSetting] = Enum.CooldownViewerVisibleSetting.InCombat,
}
local saved = 0
local LEMO = {}
function LEMO:GetActiveLayout() return "Raid" end
function LEMO:GetFrameSetting(frame, setting)
    Check(frame == BuffIconCooldownViewer and frameSettings[setting] ~= nil,
        "native preview reads target supported Tracked Buff Edit Mode settings")
    return frameSettings[setting]
end
function LEMO:SetFrameSetting(frame, setting, value)
    Check(frame == BuffIconCooldownViewer and frameSettings[setting] ~= nil,
        "native preview writes target supported Tracked Buff Edit Mode settings")
    frameSettings[setting] = value
end
function LEMO:IsReady() return true end
function LEMO:LoadLayouts() end
function LEMO:SaveOnly() saved = saved + 1 end

local BCDM = {
    LEMO = LEMO,
    db = {
        global = { CooldownViewer = { NativeTrackedBuffVisibility = {} } },
        profile = { CooldownManager = {
            Enable = true,
            Buffs = { CenterBuffs = true, IconWidth = 32, IconHeight = 32 },
        } },
    },
}
function BCDM:IsSecretValue() return false end
function BCDM:GetIconDimensions(settings) return settings.IconWidth, settings.IconHeight end

assert(loadfile(root .. "/Modules/TrackedBuffAuraViewer.lua"))("BetterCooldownManager", BCDM)
BCDM.TrackedBuffAuraRuntime.ready = true

Check(BCDM:PrepareTrackedBuffVisibilityOverride(LEMO),
    "ready aura replacement prepares the native visibility override")
Check(frameSettings[Enum.EditModeCooldownViewerSetting.VisibleSetting]
        == Enum.CooldownViewerVisibleSetting.Hidden,
    "ready aura replacement hides the native viewer through Edit Mode")
Check(frameSettings[Enum.EditModeCooldownViewerSetting.IconSize] == 80,
    "the native editor preview uses BCM's configured 32px icon size")
Check(BCDM.db.global.CooldownViewer.NativeTrackedBuffVisibility.Raid.value
        == Enum.CooldownViewerVisibleSetting.InCombat,
    "the original visibility is retained per active layout")
Check(BCDM.db.global.CooldownViewer.NativeTrackedBuffVisibility.Raid.iconSize == 110,
    "the original native icon scale is retained per active layout")
BCDM:CommitTrackedBuffVisibilityOverride()
Check(BCDM.db.global.CooldownViewer.NativeTrackedBuffVisibility.Raid ~= nil,
    "committing a hide keeps the restoration record")

BCDM.db.profile.CooldownManager.Buffs.CenterBuffs = false
Check(BCDM:PrepareTrackedBuffVisibilityOverride(LEMO),
    "disabling the replacement prepares native visibility restoration")
Check(frameSettings[Enum.EditModeCooldownViewerSetting.VisibleSetting]
        == Enum.CooldownViewerVisibleSetting.InCombat
        and frameSettings[Enum.EditModeCooldownViewerSetting.IconSize] == 110,
    "disabling the replacement restores the user's visibility and icon scale")
BCDM:CommitTrackedBuffVisibilityOverride()
Check(BCDM.db.global.CooldownViewer.NativeTrackedBuffVisibility.Raid == nil,
    "successful restoration clears its ownership record")

BCDM.db.profile.CooldownManager.Buffs.CenterBuffs = true
BCDM.TrackedBuffAuraRuntime.ready = true
BCDM:PrepareTrackedBuffVisibilityOverride(LEMO)
BCDM:RestoreTrackedBuffVisibilityForLogout()
Check(frameSettings[Enum.EditModeCooldownViewerSetting.VisibleSetting]
        == Enum.CooldownViewerVisibleSetting.InCombat
        and frameSettings[Enum.EditModeCooldownViewerSetting.IconSize] == 110 and saved == 1,
    "logout restores and saves native visibility and icon scale without applying Edit Mode")

local container = { enabled = true, shown = true }
function container:SetEnabled(enabled) self.enabled = enabled end
function container:SetShown(shown) self.shown = shown end
local owner = { shown = true }
function owner:SetShown(shown) self.shown = shown end
BCDM.TrackedBuffAuraRuntime.container = container
BCDM.TrackedBuffAuraRuntime.owner = owner
BCDM.TrackedBuffAuraRuntime.ready = true
Check(not BCDM:ShouldStyleNativeTrackedBuffViewer(),
    "the hidden native viewer is not styled while the replacement is active")
BCDM:SetTrackedBuffAuraEditorVisible(true)
Check(container.enabled and container.shown and not owner.shown,
    "native editor visibility hides only the BCM-owned parent layer")
Check(BCDM:ShouldStyleNativeTrackedBuffViewer(),
    "the native Tracked Buff editor preview remains eligible for BCM styling")

local sourceFile = assert(io.open(root .. "/Modules/TrackedBuffAuraViewer.lua", "r"))
local source = sourceFile:read("*a")
sourceFile:close()
Check(source:find("SetFlowLayoutAnchorPoint", 1, true)
        and source:find("SetFlowLayoutGrowthDirection", 1, true)
        and source:find("SetFlowLayoutMaximumLineSize", 1, true),
    "tracked buff layout uses the Retail 12.1 flow-layout API")
Check(not source:find("SetAuraLayoutAnchorPoint", 1, true)
        and not source:find("SetAuraLayoutGrowthDirection", 1, true)
        and not source:find("SetAuraLayoutRowWidth", 1, true),
    "tracked buff layout does not call removed AuraContainer layout methods")
Check(source:find("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", 1, true) ~= nil,
    "tracked buff replacement refreshes after the active specialization changes")

return failures == 0
