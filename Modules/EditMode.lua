local _, BCDM = ...
BCDM.EditModeLayoutsLayouts = {}

-- Thank you Meeres & Alf for this.
-- Alf provided most of the code, I just adapted where appropriate.

function BCDM:GetLayouts()
    wipe(BCDM.EditModeLayoutsLayouts)
    local layoutInfo = C_EditMode.GetLayouts()
    for i, info in pairs(layoutInfo.layouts) do
        table.insert(BCDM.EditModeLayoutsLayouts, info.layoutName)
    end
    return BCDM.EditModeLayoutsLayouts
end

local function GetIndexForName(name)
    local layoutInfo = C_EditMode.GetLayouts()
    for i, info in pairs(layoutInfo.layouts) do
        if info.layoutName == name then
            local offset = 2
            local index = i + offset
            if index == layoutInfo.activeLayout then return end
            return index
        end
    end
end

function BCDM:SetupEditModeManager()
    local EditModeManagerEventFrame = CreateFrame("Frame")
    EditModeManagerEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    EditModeManagerEventFrame:RegisterEvent("ZONE_CHANGED")
    EditModeManagerEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    EditModeManagerEventFrame:SetScript("OnEvent", function() BCDM:UpdateLayout() end)
end

function BCDM:UpdateLayout()
    local DIFFICULTY_IDS = {
        [14] = BCDM.db.global.EditModeManager.RaidLayouts.Normal,
        [15] = BCDM.db.global.EditModeManager.RaidLayouts.Heroic,
        [16] = BCDM.db.global.EditModeManager.RaidLayouts.Mythic,
        [17] = BCDM.db.global.EditModeManager.RaidLayouts.LFR,
    }
    if BCDM.db.global.EditModeManager.SwapOnInstanceDifficulty then
        local DifficultyID = select(3, GetInstanceInfo())
        local layoutName = DIFFICULTY_IDS[DifficultyID]
        if not layoutName then return end
        if layoutName then
            local index = GetIndexForName(layoutName)
            if index then
                BCDM:PrettyPrint("Layout Set - |cFF8080FF" .. layoutName .. "|r")
                if type(securecallfunction) ~= "function" then return end
                local changed = pcall(securecallfunction, C_EditMode.SetActiveLayout, index)
                if not changed then return end
                BCDM:QueueCooldownViewerLayoutApply()
                return layoutName, index
            end
        end
    end
end
