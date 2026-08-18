local root, Check = ...

local savedCreateFrame = CreateFrame
local eventFrame = { events = {} }
function eventFrame:RegisterEvent(event) self.events[event] = true end
function eventFrame:SetScript(_, callback) self.OnEvent = callback end
CreateFrame = function(_, name)
    eventFrame.name = name
    return eventFrame
end

local refreshes = 0
local BCDM = {}
assert(loadfile(root .. "/Core/Visibility.lua"))("BetterCooldownManager", BCDM)
function BCDM:RefreshOwnedFrameVisibility() refreshes = refreshes + 1 end
BCDM:SetupVisibilityEvents()

BCDM.VisibilityEventFrame.OnEvent(BCDM.VisibilityEventFrame, "PLAYER_IS_GLIDING_CHANGED", true)
Check(refreshes == 1, "truthy gliding payloads refresh visibility")
BCDM.VisibilityEventFrame.OnEvent(BCDM.VisibilityEventFrame, "PLAYER_ENTERING_WORLD", true)
Check(refreshes == 2, "truthy world-entry payloads refresh visibility")
BCDM.VisibilityEventFrame.OnEvent(BCDM.VisibilityEventFrame, "UNIT_ENTERED_VEHICLE", "target")
Check(refreshes == 2, "non-player vehicle events do not refresh visibility")
BCDM.VisibilityEventFrame.OnEvent(BCDM.VisibilityEventFrame, "UNIT_EXITED_VEHICLE", "player")
Check(refreshes == 3, "player vehicle events refresh visibility")

CreateFrame = savedCreateFrame
return true
