local _, BCDM = ...

local pendingFull = false
local pendingStructure = false
local pendingState = false
local scheduled = false
local retryFrame
local Schedule

local function EnsureRetryFrame()
    if retryFrame then return end
    if not CreateFrame then return end
    retryFrame = CreateFrame("Frame")
    retryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    retryFrame:SetScript("OnEvent", function() Schedule() end)
end

local function RunPending()
    scheduled = false
    if (pendingFull or pendingStructure) and InCombatLockdown and InCombatLockdown() then
        EnsureRetryFrame()
        return
    end
    if pendingFull then
        pendingFull, pendingStructure, pendingState = false, false, false
        BCDM:UpdateBCDM()
    elseif pendingStructure then
        pendingStructure, pendingState = false, false
        if BCDM.RefreshCustomTrackers then BCDM:RefreshCustomTrackers() end
        if BCDM.UpdateTrinketBar then BCDM:UpdateTrinketBar() end
        if BCDM.UpdatePowerBars then BCDM:UpdatePowerBars() end
        if BCDM.UpdateCastBar then BCDM:UpdateCastBar() end
        if BCDM.QueueCooldownViewerLayoutApply then BCDM:QueueCooldownViewerLayoutApply() end
        if BCDM.QueueCooldownViewerStyleRefresh then BCDM:QueueCooldownViewerStyleRefresh() end
    elseif pendingState then
        pendingState = false
        if BCDM.RefreshCustomTrackerStates then BCDM:RefreshCustomTrackerStates() end
        if BCDM.RefreshTrinketCooldowns then BCDM:RefreshTrinketCooldowns() end
        if BCDM.RefreshPowerBarValues then
            BCDM:RefreshPowerBarValues()
        elseif BCDM.UpdatePowerBars then
            BCDM:UpdatePowerBars()
        end
    end
end

Schedule = function()
    if scheduled or not C_Timer or type(C_Timer.After) ~= "function" then return end
    scheduled = true
    C_Timer.After(0, RunPending)
end

function BCDM:QueueRuntimeRefresh(kind)
    if kind == "full" then
        pendingFull = true
    elseif kind == "structure" then
        if not pendingFull then pendingStructure = true end
    elseif kind == "state" and not pendingFull and not pendingStructure then
        pendingState = true
    else
        return false
    end
    Schedule()
    return true
end
