local _, BCDM = ...

local registrations = setmetatable({}, { __mode = "k" })

function BCDM:NewVisibilityPolicy()
    return {
        Mode = "ALWAYS",
        Instances = { OpenWorld = true, Dungeon = true, Raid = true, Arena = true, Battleground = true },
        HideMounted = false,
        HideDead = false,
        HideVehicle = false,
        HideResting = false,
    }
end

function BCDM:EvaluateVisibilityState(policy, state)
    if type(policy) ~= "table" then return true end
    state = type(state) == "table" and state or {}
    if policy.Mode == "IN_COMBAT" and not state.Combat then return false end
    if policy.Mode == "OUT_OF_COMBAT" and state.Combat then return false end
    local instances = policy.Instances or {}
    if state.Instance and instances[state.Instance] == false then return false end
    if policy.HideMounted and state.Mounted then return false end
    if policy.HideDead and state.Dead then return false end
    if policy.HideVehicle and state.Vehicle then return false end
    if policy.HideResting and state.Resting then return false end
    return true
end

local function CurrentInstance()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType == "none" then return "OpenWorld" end
    if instanceType == "raid" then return "Raid" end
    if instanceType == "arena" then return "Arena" end
    if instanceType == "pvp" then return "Battleground" end
    return "Dungeon"
end

local function CurrentState()
    local gliding = C_PlayerInfo and C_PlayerInfo.GetGlidingInfo and C_PlayerInfo.GetGlidingInfo()
    return {
        Combat = InCombatLockdown() == true,
        Instance = CurrentInstance(),
        Mounted = IsMounted() == true or gliding == true,
        Dead = UnitIsDeadOrGhost("player") == true,
        Vehicle = UnitInVehicle("player") == true,
        Resting = IsResting() == true,
    }
end

function BCDM:GetOwnedFrameVisibilityPolicy(config)
    if type(config) ~= "table" or config.UseSharedVisibility ~= false then
        return self.db and self.db.profile and self.db.profile.Visibility
    end
    return config.Visibility
end

function BCDM:ShouldShowOwnedFrame(config)
    return self:EvaluateVisibilityState(self:GetOwnedFrameVisibilityPolicy(config), CurrentState())
end

function BCDM:RegisterOwnedFrameVisibility(frame, configProvider, refresh)
    if not frame or registrations[frame] then return end
    registrations[frame] = {
        Config = configProvider,
        Refresh = refresh,
        PolicyVisible = self:ShouldShowOwnedFrame(configProvider and configProvider()),
    }
    frame:HookScript("OnShow", function(self)
        local registration = registrations[self]
        local config = registration and registration.Config and registration.Config()
        if not BCDM:ShouldShowOwnedFrame(config) then self:Hide() end
    end)
    if frame:IsShown() and not self:ShouldShowOwnedFrame(configProvider and configProvider()) then frame:Hide() end
end

function BCDM:RefreshOwnedFrameVisibility()
    for frame, registration in pairs(registrations) do
        local config = registration.Config and registration.Config()
        local policyVisible = self:ShouldShowOwnedFrame(config)
        if policyVisible ~= registration.PolicyVisible then
            registration.PolicyVisible = policyVisible
            if not policyVisible then
                frame:Hide()
            elseif registration.Refresh then
                registration.Refresh(frame)
            end
        elseif frame:IsShown() and not policyVisible then
            frame:Hide()
        end
    end
end

function BCDM:SetupVisibilityEvents()
    if self.VisibilityEventFrame then return end
    local frame = CreateFrame("Frame", "BCDMVisibilityEventFrame")
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_IS_GLIDING_CHANGED", "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST",
        "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "PLAYER_UPDATE_RESTING",
    }) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent", function(_, _, unit)
        if unit and unit ~= "player" then return end
        BCDM:RefreshOwnedFrameVisibility()
    end)
    self.VisibilityEventFrame = frame
end
