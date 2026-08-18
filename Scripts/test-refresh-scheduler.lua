local root, BCDM, Check = ...
if type(root) ~= "string" or root == "" then root = "." end

local savedTimer = C_Timer
local savedMethods = {
    UpdateBCDM = BCDM.UpdateBCDM,
    RefreshCustomTrackers = BCDM.RefreshCustomTrackers,
    UpdateTrinketBar = BCDM.UpdateTrinketBar,
    RefreshCustomTrackerStates = BCDM.RefreshCustomTrackerStates,
    RefreshTrinketCooldowns = BCDM.RefreshTrinketCooldowns,
    RefreshPowerBarValues = BCDM.RefreshPowerBarValues,
}
local callbacks = {}
local calls = {}
C_Timer = { After = function(_, callback) callbacks[#callbacks + 1] = callback end }
BCDM.UpdateBCDM = function() calls.full = (calls.full or 0) + 1 end
BCDM.RefreshCustomTrackers = function() calls.structure = (calls.structure or 0) + 1 end
BCDM.UpdateTrinketBar = function() calls.structure = (calls.structure or 0) + 1 end
BCDM.RefreshCustomTrackerStates = function() calls.state = (calls.state or 0) + 1 end
BCDM.RefreshTrinketCooldowns = function() calls.state = (calls.state or 0) + 1 end
BCDM.RefreshPowerBarValues = function() calls.state = (calls.state or 0) + 1 end

assert(loadfile(root .. "/Core/RefreshScheduler.lua"))("BetterCooldownManager", BCDM)
BCDM:QueueRuntimeRefresh("state")
BCDM:QueueRuntimeRefresh("state")
Check(#callbacks == 1, "runtime state refreshes coalesce into one timer")
callbacks[1]()
Check(calls.state == 3 and not calls.full and not calls.structure,
    "state refresh dispatches each state owner once")

BCDM:QueueRuntimeRefresh("state")
BCDM:QueueRuntimeRefresh("structure")
BCDM:QueueRuntimeRefresh("full")
Check(#callbacks == 2, "higher-priority refreshes reuse the queued timer")
callbacks[2]()
Check(calls.full == 1 and calls.structure == nil and calls.state == 3,
    "full refresh subsumes pending structure and state work")

BCDM.UpdateBCDM = savedMethods.UpdateBCDM
BCDM.RefreshCustomTrackers = savedMethods.RefreshCustomTrackers
BCDM.UpdateTrinketBar = savedMethods.UpdateTrinketBar
BCDM.RefreshCustomTrackerStates = savedMethods.RefreshCustomTrackerStates
BCDM.RefreshTrinketCooldowns = savedMethods.RefreshTrinketCooldowns
BCDM.RefreshPowerBarValues = savedMethods.RefreshPowerBarValues
C_Timer = savedTimer
return true
