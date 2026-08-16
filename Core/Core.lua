local _, BCDM = ...
local BetterCooldownManager = LibStub("AceAddon-3.0"):NewAddon("BetterCooldownManager")

function BetterCooldownManager:OnInitialize()
    BCDM.db = LibStub("AceDB-3.0"):New("BCDMDB", BCDM:GetDefaultDB(), true)
    BCDM:NormalizeEssentialAnchorProfiles(BCDM.db)
    BCDM:NormalizeBarColourProfiles(BCDM.db)
    BCDM:NormalizeRemovedSettingsProfiles(BCDM.db)
    BCDM:MigrateCustomTrackerProfiles(BCDM.db)
    BCDM.LDS:EnhanceDatabase(BCDM.db, "BetterCooldownManager")
    for k, v in pairs(BCDM:GetDefaultDB()) do
        if BCDM.db.profile[k] == nil then
            BCDM.db.profile[k] = v
        end
    end
    if BCDM.db.global.UseGlobalProfile then BCDM.db:SetProfile(BCDM.db.global.GlobalProfile or "Default") end
    local function HandleProfileLayoutChanged()
        BCDM:UpdateBCDM()
        BCDM:QueueCooldownViewerLayoutApply()
        if BCDM.RefreshSettings then BCDM:RefreshSettings() end
    end
    BCDM.db.RegisterCallback(BCDM, "OnProfileChanged", HandleProfileLayoutChanged)
    BCDM.db.RegisterCallback(BCDM, "OnProfileCopied", HandleProfileLayoutChanged)
    BCDM.db.RegisterCallback(BCDM, "OnProfileReset", HandleProfileLayoutChanged)
    BCDM:RegisterSettings()
end

function BetterCooldownManager:OnEnable()
    BCDM:Init()
    BCDM:SetupEventManager()
    BCDM:SetupVisibilityEvents()
    BCDM:SkinCooldownManager()
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
