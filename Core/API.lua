local _, BCDM = ...
local Serialize = LibStub:GetLibrary("AceSerializer-3.0")
local Compress = LibStub:GetLibrary("LibDeflate")

local function EncodeProfile(profile)
    local serialized = Serialize:Serialize({ profile = profile })
    return "!BCDM_" .. Compress:EncodeForPrint(Compress:CompressDeflate(serialized))
end

local function DecodeProfile(encoded)
    if type(encoded) ~= "string" or encoded:sub(1, 6) ~= "!BCDM_" then return end
    local decoded = Compress:DecodeForPrint(encoded:sub(7))
    if not decoded then return end
    local decompressed = Compress:DecompressDeflate(decoded)
    if not decompressed then return end
    local success, data = Serialize:Deserialize(decompressed)
    return success and type(data) == "table" and type(data.profile) == "table" and data.profile or nil
end

local function ReplaceProfile(profile, name)
    BCDM.db:SetProfile(name)
    wipe(BCDM.db.profile)
    for key, value in pairs(profile) do BCDM.db.profile[key] = value end
    if BCDMG.RefreshProfiles then BCDMG.RefreshProfiles() end
    BCDM:UpdateBCDM()
    BCDM:QueueCooldownViewerLayoutApply()
end

function BCDMG:ExportBCDM(profileKey)
    local profile = BCDM.db.profiles[profileKey]
    return profile and EncodeProfile(profile) or nil
end

function BCDMG:ImportBCDM(importString, profileKey)
    local profile = DecodeProfile(importString)
    if not profile then BCDM:PrettyPrint("Invalid Import String.") return end
    BCDM:NormalizeImportedProfile(profile)
    BCDM.db.profiles[profileKey] = profile
    BCDM.db:SetProfile(profileKey)
    BCDM:UpdateBCDM()
    BCDM:QueueCooldownViewerLayoutApply()
end

function BCDM:ImportSavedVariables(encodedInfo, profileName)
    local profile = DecodeProfile(encodedInfo)
    if not profile then BCDM:PrettyPrint("Invalid Import String.") return end
    BCDM:NormalizeImportedProfile(profile)
    if profileName then
        ReplaceProfile(profile, profileName)
        return
    end

    StaticPopupDialogs["BCDM_IMPORT_NEW_PROFILE"] = {
        text = BCDM.ADDON_NAME .. " - Profile Name?",
        button1 = "Import",
        button2 = "Cancel",
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self)
            local name = self.EditBox:GetText()
            if not name or name == "" then
                BCDM:PrettyPrint("Please enter a valid profile name.")
                return
            end
            ReplaceProfile(profile, name)
        end,
    }

    StaticPopup_Show("BCDM_IMPORT_NEW_PROFILE")
end

-- AddOn Developers can call BCDMG:AddAnchors("AddOnName", {"ViewerType1"}, { AnchorKey = "Display Name" }).
function BCDMG:AddAnchors(addOnName, addToTypes, anchorTable)
    if not C_AddOns.IsAddOnLoaded(addOnName) then return end
    if type(addToTypes) ~= "table" or type(anchorTable) ~= "table" then return end
    for _, typeName in ipairs(addToTypes) do
        if typeName == "Custom" or typeName == "AdditionalCustom" then typeName = "CustomTrackers" end
        if BCDM.AnchorParents[typeName] then
            local displayNames = BCDM.AnchorParents[typeName][1]
            local keyList = BCDM.AnchorParents[typeName][2]
            for anchorKey, displayName in pairs(anchorTable) do
                if not displayNames[anchorKey] then
                    displayNames[anchorKey] = displayName
                    table.insert(keyList, anchorKey)
                end
            end
        end
    end
end
