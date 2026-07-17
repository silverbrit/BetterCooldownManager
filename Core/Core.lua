local _, BCDM = ...
local BetterCooldownManager = LibStub("AceAddon-3.0"):NewAddon("BetterCooldownManager")

function BetterCooldownManager:OnInitialize()
    BCDM.db = LibStub("AceDB-3.0"):New("BCDMDB", BCDM:GetDefaultDB(), true)
    BCDM:MigrateCustomTrackerProfiles(BCDM.db)
    BCDM.LDS:EnhanceDatabase(BCDM.db, "BetterCooldownManager")
    for k, v in pairs(BCDM:GetDefaultDB()) do
        if BCDM.db.profile[k] == nil then
            BCDM.db.profile[k] = v
        end
    end
    if BCDM.db.global.UseGlobalProfile then BCDM.db:SetProfile(BCDM.db.global.GlobalProfile or "Default") end
    BCDM.db.RegisterCallback(BCDM, "OnProfileChanged", function()
        BCDM:UpdateBCDM()
        if BCDM.RefreshSettings then BCDM:RefreshSettings() end
    end)
    BCDM:RegisterSettings()
end

function BetterCooldownManager:OnEnable()
    BCDM:CheckAddOns()
    BCDM:Init()
    BCDM:SetupEventManager()
    BCDM:SetupVisibilityEvents()
    BCDM:SkinCooldownManager()
    BCDM:DisableAuraOverlay()
    BCDM:SetupCustomGlows()
    BCDM:CreatePowerBar()
    BCDM:CreateSecondaryPowerBar()
    BCDM:CreateCastBar()
    C_Timer.After(0.1, function()
        BCDM:SetupCustomTrackers()
        BCDM:SetupTrinketBar()
        BCDM:CreateCooldownViewerOverlays()
    end)
    BCDM:SetupEditModeManager()
end
