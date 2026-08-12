local _, BCDM = ...

local function IsInPetBattle()
    return C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()
end

local function HideFrameForPetBattle(frameToHide)
    if not frameToHide then return end
    if not frameToHide.BCDMPetBattleHooked then
        frameToHide.BCDMPetBattleHooked = true
        frameToHide:HookScript("OnShow", function(self) if IsInPetBattle() then self:Hide() end end)
    end
    frameToHide:Hide()
end

local function HidePetBattleFrames()
    HideFrameForPetBattle(BCDM.PowerBar)
    HideFrameForPetBattle(BCDM.SecondaryPowerBar)
    HideFrameForPetBattle(BCDM.CastBar)
    for _, container in pairs(BCDM.CustomTrackerRuntime and BCDM.CustomTrackerRuntime.Containers or {}) do
        HideFrameForPetBattle(container)
    end
    HideFrameForPetBattle(BCDM.TrinketBarContainer)
end

local function HandlePetBattleVisibility(event)
    if event == "PET_BATTLE_OPENING_START" or event == "PET_BATTLE_OPENING_DONE" then
        HidePetBattleFrames()
        return true
    end

    if IsInPetBattle() then
        HidePetBattleFrames()
        return true
    end

    return false
end

function BCDM:SetupEventManager()
    local BCDMEventManager = CreateFrame("Frame", "BCDMEventManagerFrame")
    BCDMEventManager:RegisterEvent("PLAYER_ENTERING_WORLD")
    BCDMEventManager:RegisterEvent("LOADING_SCREEN_DISABLED")
    BCDMEventManager:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    BCDMEventManager:RegisterEvent("TRAIT_CONFIG_UPDATED")
    BCDMEventManager:RegisterEvent("PET_BATTLE_OPENING_START")
    BCDMEventManager:RegisterEvent("PET_BATTLE_OPENING_DONE")
    BCDMEventManager:RegisterEvent("PET_BATTLE_CLOSE")
    BCDMEventManager:SetScript("OnEvent", function(_, event, ...)
        if HandlePetBattleVisibility(event) then return end
        if InCombatLockdown() then return end
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            local unit = ...
            if unit ~= "player" then return end
            BCDM:UpdateBCDM()
            BCDM:QueueCooldownViewerLayoutApply()
            if BCDM.RefreshSettings then BCDM:RefreshSettings() end
        else
            BCDM:UpdateBCDM()
        end
    end)
end
