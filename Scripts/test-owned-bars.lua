local root, BCDM, Check = ...

local function frame()
    return {
        shown = false,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetWidth = function(self, width) self.width = width end,
    }
end

local oldDB = BCDM.db
local oldShouldShow = BCDM.ShouldShowOwnedFrame
local oldSetShown = BCDM.SetOwnedFrameShown
local oldGetResource = BCDM.GetCurrentSecondaryResource
local oldPowerBar = BCDM.PowerBar
local oldSecondaryPowerBar = BCDM.SecondaryPowerBar
local oldRenderable = BCDM._SecondaryResourceRenderable
local oldDisplayVisible = BCDM._SecondaryDisplayVisible
local oldOwner = BCDM._SecondaryOwnsPrimaryPosition

local descriptor = { swapToPrimaryEligible = true }
local profile = {
    PowerBar = { Enabled = true },
    SecondaryPowerBar = {
        Enabled = true, SwapToPowerBarPosition = true, Visible = true,
    },
}
local powerBar, secondaryPowerBar = frame(), frame()
BCDM.db = { profile = profile }
BCDM.GetCurrentSecondaryResource = function() return descriptor end
BCDM.ShouldShowOwnedFrame = function(_, settings) return settings.Visible ~= false end
BCDM.SetOwnedFrameShown = function(_, target, _, shown)
    if target then
        if shown then target:Show() else target:Hide() end
    end
    return shown == true
end
BCDM.PowerBar, BCDM.SecondaryPowerBar = powerBar, secondaryPowerBar

local function apply(renderable)
    return BCDM:ApplyPowerBarOwnership(renderable)
end

profile.SecondaryPowerBar.Enabled = false
apply(true)
Check(powerBar.shown and not secondaryPowerBar.shown,
    "swap does not hide the primary when secondary is disabled")

profile.SecondaryPowerBar.Enabled = true
profile.SecondaryPowerBar.Visible = false
apply(true)
Check(powerBar.shown and not secondaryPowerBar.shown,
    "swap does not hide the primary when secondary visibility policy vetoes display")

profile.SecondaryPowerBar.Visible = true
apply(true)
Check(not powerBar.shown and secondaryPowerBar.shown,
    "supported visible secondary owns the primary position")

BCDM.GetCurrentSecondaryResource = function() return nil end
apply(false)
Check(powerBar.shown and not secondaryPowerBar.shown,
    "unsupported resources hide secondary and restore primary")

BCDM.GetCurrentSecondaryResource = function() return descriptor end
profile.SecondaryPowerBar.SwapToPowerBarPosition = false
apply(true)
Check(powerBar.shown and secondaryPowerBar.shown,
    "profile changes recompute bar ownership")

profile.SecondaryPowerBar.SwapToPowerBarPosition = true
profile.SecondaryPowerBar.Visible = false
apply(true)
Check(powerBar.shown and not secondaryPowerBar.shown,
    "visibility changes apply without another world event")

for _, formID in ipairs({ 31, 32, 33, 34, 35 }) do
    Check(BCDM:ResolvePrimaryDisplayPowerType(8, "DRUID", 1, formID) == 8,
        "Balance Moonkin forms retain their display power")
    for _, specialization in ipairs({ 2, 3, 4 }) do
        Check(BCDM:ResolvePrimaryDisplayPowerType(8, "DRUID", specialization, formID) == Enum.PowerType.Mana,
            "non-Balance Moonkin forms use Mana")
    end
end

local savedCreateFrame = CreateFrame
local savedPowerGlobals = {
    UnitClass = UnitClass, UnitPowerType = UnitPowerType, UnitPower = UnitPower,
    UnitPowerMax = UnitPowerMax, UnitPowerPercent = UnitPowerPercent,
    GetSpecialization = GetSpecialization, GetShapeshiftFormID = GetShapeshiftFormID,
    CurveConstants = CurveConstants, RAID_CLASS_COLORS = RAID_CLASS_COLORS,
}
local eventFrame = {}
function eventFrame:RegisterEvent() end
function eventFrame:RegisterUnitEvent() end
function eventFrame:SetScript() end
CreateFrame = function() return eventFrame end

local currentPower, currentType, currentMax = 10, 0, 100
local updatedColour
local powerModule = {
    db = { profile = {
        General = {
            Colours = {
                PrimaryPower = { [0] = { 1, 0, 0 }, [3] = { 0, 1, 0 } },
            },
        },
        PowerBar = { Text = { Mode = "AUTO" } },
    } },
    PowerBar = {
        Status = {
            SetStatusBarColor = function(_, r, g, b) updatedColour = { r, g, b } end,
            SetMinMaxValues = function(_, minimum, maximum) currentMax = maximum end,
            SetValue = function(_, value) currentPower = value end,
        },
        Text = { SetText = function() end },
    },
}
function powerModule:ResolveBarFillColour(_, _, context)
    local colour = context.PowerTypeColour
    return colour[1], colour[2], colour[3], colour[4] or 1
end
powerModule.ResolvePrimaryDisplayPowerType = function(_, powerType, class, specialization, formID)
    return BCDM:ResolvePrimaryDisplayPowerType(powerType, class, specialization, formID)
end
powerModule.ApplyPowerBarOwnership = function() end
UnitClass = function() return "", "MAGE" end
UnitPowerType = function() return currentType end
UnitPower = function() return currentPower end
UnitPowerMax = function() return currentMax end
UnitPowerPercent = function() return 50 end
GetSpecialization = function() return 1 end
GetShapeshiftFormID = function() return 0 end
CurveConstants = { ScaleTo100 = 100 }
RAID_CLASS_COLORS = {}
assert(loadfile((root or ".") .. "/Modules/PowerBar.lua"))("BetterCooldownManager", powerModule)
powerModule._PowerBarOnEvent(nil, "UNIT_DISPLAYPOWER")
local firstColour = updatedColour and table.concat(updatedColour, ",")
currentType, currentPower, currentMax = 3, 25, 120
powerModule._PowerBarOnEvent(nil, "UNIT_DISPLAYPOWER")
Check(currentPower == 25 and currentMax == 120 and table.concat(updatedColour, ",") ~= firstColour,
    "UNIT_DISPLAYPOWER refreshes power values and colour")

CreateFrame = savedCreateFrame
for name, value in pairs(savedPowerGlobals) do _G[name] = value end

local savedUIParent = UIParent
local savedAnchor = _G.OwnedBarsTestAnchor
UIParent = {}
_G.OwnedBarsTestAnchor = { GetWidth = function() return 111 end }
local cycleProfile = {
    PowerBar = { Layout = { "BOTTOM", "BCDM_SecondaryPowerBar", "TOP", 0, 0 } },
    SecondaryPowerBar = { Layout = { "BOTTOM", "BCDM_PowerBar", "TOP", 0, 0 } },
    CastBar = { Layout = { "TOP", "BCDM_PowerBar", "BOTTOM", 0, 0 } },
}
BCDM.db = { profile = cycleProfile }
local _, cycleParent = BCDM:GetPowerBarLayout("PowerBar", false)
Check(cycleParent == UIParent, "Power and Secondary anchor cycles fall back to UIParent")
cycleProfile.PowerBar.Layout = { "BOTTOM", "BCDM_CastBar", "TOP", 0, 0 }
local _, longerCycleParent = BCDM:GetPowerBarLayout("PowerBar", false)
Check(longerCycleParent == UIParent, "longer BCM anchor cycles fall back to UIParent")
cycleProfile.PowerBar.Layout = { "BOTTOM", "OwnedBarsTestAnchor", "TOP", 0, 0 }
cycleProfile.SecondaryPowerBar.Layout = { "BOTTOM", "UIParent", "TOP", 0, 0 }
local swappedLayout, swappedParent = BCDM:GetPowerBarLayout("SecondaryPowerBar", true)
Check(swappedLayout == cycleProfile.PowerBar.Layout and swappedParent == _G.OwnedBarsTestAnchor,
    "editing the primary anchor moves the visible swapped secondary owner")

local savedTimer = C_Timer
local callbacks = {}
C_Timer = {
    NewTimer = function(_, callback)
        callbacks[#callbacks + 1] = callback
        return { Cancel = function() end }
    end,
}
assert(loadfile((root or ".") .. "/Modules/SecondaryPowerBar.lua"))("BetterCooldownManager", BCDM)
local widthPower, widthSecondary = frame(), frame()
BCDM.PowerBar, BCDM.SecondaryPowerBar = widthPower, widthSecondary
BCDM.GetCurrentSecondaryResource = function() return nil end
cycleProfile.PowerBar.Layout = { "BOTTOM", "OwnedBarsTestAnchor", "TOP", 0, 0 }
cycleProfile.SecondaryPowerBar.Layout = { "BOTTOM", "OwnedBarsTestAnchor", "TOP", 0, 0 }
cycleProfile.PowerBar.MatchWidthOfAnchor = true
cycleProfile.SecondaryPowerBar.MatchWidthOfAnchor = true
BCDM._SecondaryOwnsPrimaryPosition = false
BCDM:QueuePowerBarWidthUpdates()
_G.OwnedBarsTestAnchor.GetWidth = function() return 222 end
BCDM:QueuePowerBarWidthUpdates()
callbacks[1]()
Check(widthPower.width == nil and widthSecondary.width == nil,
    "stale width callbacks do not apply old configuration")
callbacks[2]()
Check(widthPower.width == 222 and widthSecondary.width == 222,
    "the newest delayed width callback applies both bar widths")

C_Timer = savedTimer
UIParent = savedUIParent
_G.OwnedBarsTestAnchor = savedAnchor
BCDM.db = oldDB
BCDM.ShouldShowOwnedFrame = oldShouldShow
BCDM.SetOwnedFrameShown = oldSetShown
BCDM.GetCurrentSecondaryResource = oldGetResource
BCDM.PowerBar = oldPowerBar
BCDM.SecondaryPowerBar = oldSecondaryPowerBar
BCDM._SecondaryResourceRenderable = oldRenderable
BCDM._SecondaryDisplayVisible = oldDisplayVisible
BCDM._SecondaryOwnsPrimaryPosition = oldOwner

return true
