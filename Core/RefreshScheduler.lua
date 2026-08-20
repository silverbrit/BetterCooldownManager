local _, BCDM = ...

local pendingFull = false
local pendingStructure = false
local pendingState = false
local scheduled = false
local retryFrame
local Schedule

local function EnsureRetryFrame()
    if retryFrame then return end
    retryFrame = CreateFrame("Frame")
    retryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    retryFrame:SetScript("OnEvent", function() Schedule() end)
end

local function RunPending()
    scheduled = false
    if (pendingFull or pendingStructure) and InCombatLockdown() then
        EnsureRetryFrame()
        return
    end
    if pendingFull then
        pendingFull, pendingStructure, pendingState = false, false, false
        BCDM:UpdateBCDM()
    elseif pendingStructure then
        pendingStructure, pendingState = false, false
        BCDM:RefreshCustomTrackers()
        BCDM:UpdateTrinketBar()
        BCDM:UpdatePowerBars()
        BCDM:UpdateCastBar()
        BCDM:QueueCooldownViewerLayoutApply()
        BCDM:QueueCooldownViewerStyleRefresh()
    elseif pendingState then
        pendingState = false
        BCDM:RefreshCustomTrackerStates()
        BCDM:RefreshTrinketCooldowns()
        BCDM:RefreshPowerBarValues()
    end
end

Schedule = function()
    if scheduled then return end
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
