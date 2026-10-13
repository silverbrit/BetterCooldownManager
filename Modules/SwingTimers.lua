local _, BCDM = ...

local FRAME_NAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }
local eventFrame

local function Skin(frame)
    if not BCDM:IsSafeAnchorParent(frame) then return end
    local status = frame.StatusBar
    for _, region in ipairs({ frame.Background, frame.Border, status, status.TypeLabel,
        status.TimeLabel, status.TypeLabelShadow }) do
        local accessible = region:CanBeAccessedInContext()
        if BCDM:IsSecretValue(accessible) or accessible ~= true then return end
    end

    local profile = BCDM.db.profile
    local border = profile.CooldownManager.General.BorderSize or 1
    local fontSize = profile.CooldownManager.General.CooldownText.FontSize or 15
    local colour = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
    frame.Background:SetTexture(BCDM.Media.Background)
    frame.Background:SetVertexColor(62 / 255, 62 / 255, 62 / 255, 1)
    frame.Border:SetTexture(nil)
    status.TypeLabelShadow:SetTexture(nil)
    status:SetStatusBarTexture(BCDM.Media.Foreground)
    if colour then status:SetStatusBarColor(colour.r, colour.g, colour.b) end
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", frame, "TOPLEFT", border, -border)
    status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -border, border)
    for _, label in ipairs({ status.TypeLabel, status.TimeLabel }) do
        label:SetFont(BCDM.Media.Font, fontSize, profile.General.Fonts.FontFlag)
    end
    BCDM:AddBorder(frame)
end

function BCDM:SkinSwingTimers()
    if not self.IS_WOW_FOREVER or not self.db or not self.Media then return end
    if InCombatLockdown() then return end
    for _, name in ipairs(FRAME_NAMES) do
        -- Native frames can temporarily be inaccessible. Retry on the next refresh.
        pcall(Skin, _G[name])
    end
end

function BCDM:SetupSwingTimers()
    if not self.IS_WOW_FOREVER then return end
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("ADDON_LOADED")
        eventFrame:SetScript("OnEvent", function(_, event, addon)
            if event == "PLAYER_REGEN_ENABLED" or addon == "Blizzard_SwingTimer" then
                BCDM:SkinSwingTimers()
            end
        end)
    end
    self:SkinSwingTimers()
end
