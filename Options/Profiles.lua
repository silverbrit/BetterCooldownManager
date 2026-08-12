local _, BCDM = ...

local Canvas = LibStub("LibSharedCanvas-1.0")
local U = BCDM.SettingsUtils
local profilesPanel

local function ProfileNames(exclude)
    local names = {}
    if not BCDM.db then return names end
    local profiles = BCDM.db:GetProfiles({}, true)
    table.sort(profiles)
    for _, name in ipairs(profiles) do
        if name ~= exclude then names[#names + 1] = { text = name, value = name } end
    end
    return names
end

local function HasProfile(name)
    if not name then return false end
    for _, option in ipairs(ProfileNames()) do
        if option.value == name then return true end
    end
    return false
end

local function ShowExport(text)
    StaticPopupDialogs.BCDM_EXPORT_PROFILE = {
        text = "Export Profile",
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 420,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self, data)
            self.EditBox:SetText(data or "")
            self.EditBox:HighlightText()
            self.EditBox:SetFocus()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEnterPressed = function(self) self:HighlightText() end,
    }
    StaticPopup_Show("BCDM_EXPORT_PROFILE", nil, nil, text)
end

local function CreateProfilesPanel()
    local panel, controls = U.NewPanel()
    controls.state = { copy = nil, delete = nil, export = nil }

    local management, managementControls = Canvas.CreateProfileManagementSection(controls.scrollChild, "Profiles", {
        introText = "Switch the active profile, create new ones, copy settings between profiles, and remove unused profiles.",
        resetDescription = "Reset the current profile back to its default values, in case your configuration is broken, or you simply want to start over.",
        currentProfileText = "Current Profile: |cffffd100Default|r",
        chooseDescription = "Create a new profile by entering a name in the edit box, or switch to one of the existing profiles.",
        copyDescription = "Copy the settings from one existing profile into the currently active profile.",
        deleteDescription = "Delete existing and unused profiles from the database to save space, and cleanup the SavedVariables file.",
        resetButtonText = "Reset Profile",
        newLabel = "New",
        existingLabel = "Existing Profiles",
        createButtonText = "Create",
        copyLabel = "Copy From",
        copyButtonText = "Copy",
        deleteLabel = "Delete a Profile",
        deleteButtonText = "Delete",
    }, { compactLayout = true })
    controls:RegisterSection(management)

    local globalSection = U.Section(controls, "Account-wide Profile", true)
    U.Text(controls, globalSection, "Use one selected profile across every character on this account.")
    U.Checkbox(controls, globalSection, "Use Global Profile", function()
        return BCDM.db.global.UseGlobalProfile == true
    end, function(value)
        BCDM.db.global.UseGlobalProfile = value == true
        if value and HasProfile(BCDM.db.global.GlobalProfile) then
            BCDM.db:SetProfile(BCDM.db.global.GlobalProfile)
        end
        BCDM:UpdateBCDM()
        panel:Refresh()
    end, { disabled = function() return BCDM.db:IsDualSpecEnabled() end })
    U.Dropdown(controls, globalSection, "Global Profile", function()
        return BCDM.db.global.GlobalProfile
    end, function(value)
        BCDM.db.global.GlobalProfile = value
        if BCDM.db.global.UseGlobalProfile then BCDM.db:SetProfile(value) end
        BCDM:UpdateBCDM()
    end, function() return ProfileNames() end, {
        disabled = function() return BCDM.db.global.UseGlobalProfile ~= true end,
    })

    local specSection = U.Section(controls, "Specialization Profiles", true)
    U.Checkbox(controls, specSection, "Enable Specialization Profiles", function()
        return BCDM.db:IsDualSpecEnabled()
    end, function(value)
        BCDM.db:SetDualSpecEnabled(value)
        BCDM:UpdateBCDM()
        panel:Refresh()
    end, { disabled = function() return BCDM.db.global.UseGlobalProfile == true end })
    for index = 1, GetNumSpecializations() do
        local _, specName = GetSpecializationInfo(index)
        U.Dropdown(controls, specSection, specName or ("Specialization " .. index), function()
            return BCDM.db:GetDualSpecProfile(index)
        end, function(value)
            BCDM.db:SetDualSpecProfile(value, index)
        end, function() return ProfileNames() end, {
            disabled = function()
                return BCDM.db.global.UseGlobalProfile == true or not BCDM.db:IsDualSpecEnabled()
            end,
        })
    end

    local editModeSection = U.Section(controls, "Edit Mode Layout Routing", true)
    U.Text(controls, editModeSection,
        "Choose the account-wide Edit Mode layout to activate for each raid difficulty.")
    U.Checkbox(controls, editModeSection, "Swap on Instance Difficulty", function()
        return BCDM.db.global.EditModeManager.SwapOnInstanceDifficulty == true
    end, function(value)
        BCDM.db.global.EditModeManager.SwapOnInstanceDifficulty = value == true
        BCDM:UpdateLayout()
        BCDM:UpdateBCDM()
        panel:Refresh()
    end)
    local function LayoutValues()
        local result = {}
        for _, layoutName in pairs(BCDM:GetLayouts() or {}) do
            result[#result + 1] = { text = layoutName, value = layoutName }
        end
        table.sort(result, function(a, b) return a.text < b.text end)
        return result
    end
    for _, difficulty in ipairs({ "LFR", "Normal", "Heroic", "Mythic" }) do
        U.Dropdown(controls, editModeSection, difficulty .. " Layout", function()
            return BCDM.db.global.EditModeManager.RaidLayouts[difficulty]
        end, function(value)
            BCDM.db.global.EditModeManager.RaidLayouts[difficulty] = value
            BCDM:UpdateLayout()
            BCDM:UpdateBCDM()
        end, LayoutValues, { disabled = function()
            return BCDM.db.global.EditModeManager.SwapOnInstanceDifficulty ~= true
        end })
    end

    local sharing, sharingControls = Canvas.CreateProfileSharingSection(controls.scrollChild, "Profile Sharing")
    controls:RegisterSection(sharing)

    local function Refresh()
        if not BCDM.db then return end
        local current = BCDM.db:GetCurrentProfile()
        if not HasProfile(controls.state.copy) or controls.state.copy == current then controls.state.copy = nil end
        if not HasProfile(controls.state.delete) or controls.state.delete == current then controls.state.delete = nil end
        if not HasProfile(controls.state.export) then controls.state.export = current end

        managementControls.currentProfileLabel:SetText("Current Profile: |cffffd100" .. current .. "|r")
        local routedProfile = BCDM.db.global.UseGlobalProfile == true or BCDM.db:IsDualSpecEnabled()
        Canvas.RefreshDropdownState(managementControls.activeDropdown, routedProfile)
        Canvas.RefreshDropdownState(managementControls.copyDropdown,
            routedProfile or (controls.state.copy == nil and #ProfileNames(current) == 0))
        Canvas.RefreshDropdownState(managementControls.deleteDropdown,
            routedProfile or (controls.state.delete == nil and #ProfileNames(current) == 0))
        Canvas.RefreshDropdownState(sharingControls.exportDropdown, false)
        managementControls.copyButton:SetEnabled(controls.state.copy ~= nil and not routedProfile)
        managementControls.deleteButton:SetEnabled(controls.state.delete ~= nil and not routedProfile)
        sharingControls.exportButton:SetEnabled(controls.state.export ~= nil)
        Canvas.SetWidgetEnabled(managementControls.createNameEdit, not BCDM.db.global.UseGlobalProfile)
        Canvas.SetWidgetEnabled(managementControls.createButton, not BCDM.db.global.UseGlobalProfile)
        Canvas.SetWidgetEnabled(managementControls.resetButton, not BCDM.db.global.UseGlobalProfile)
        Canvas.RefreshPanel(panel)
    end

    Canvas.AttachDropdownMenu(managementControls.activeDropdown, function() return ProfileNames() end,
        function() return BCDM.db:GetCurrentProfile() end, function(name)
            BCDM.db:SetProfile(name)
            BCDM:UpdateBCDM()
            Refresh()
        end, "Select profile...")
    Canvas.AttachDropdownMenu(managementControls.copyDropdown,
        function() return ProfileNames(BCDM.db:GetCurrentProfile()) end,
        function() return controls.state.copy end, function(name) controls.state.copy = name Refresh() end,
        "Select profile...")
    Canvas.AttachDropdownMenu(managementControls.deleteDropdown,
        function() return ProfileNames(BCDM.db:GetCurrentProfile()) end,
        function() return controls.state.delete end, function(name) controls.state.delete = name Refresh() end,
        "Select profile...")
    Canvas.AttachDropdownMenu(sharingControls.exportDropdown, function() return ProfileNames() end,
        function() return controls.state.export end, function(name) controls.state.export = name Refresh() end,
        "Select profile...")

    managementControls.createButton:SetScript("OnClick", function()
        local name = strtrim(managementControls.createNameEdit:GetText() or "")
        if name == "" or name:find("[%c|]") then
            BCDM:PrettyPrint("Enter a valid profile name.")
            return
        end
        BCDM.db:SetProfile(name)
        managementControls.createNameEdit:SetText("")
        BCDM:UpdateBCDM()
        Refresh()
    end)
    managementControls.resetButton:SetScript("OnClick", function()
        local name = BCDM.db:GetCurrentProfile()
        BCDM:CreatePrompt("Reset Profile", "Reset '" .. name .. "' to defaults?", function()
            BCDM.db:ResetProfile()
            BCDM:UpdateBCDM()
            Refresh()
        end)
    end)
    managementControls.copyButton:SetScript("OnClick", function()
        local source = controls.state.copy
        if not source then return end
        BCDM:CreatePrompt("Copy Profile", "Copy '" .. source .. "' into the current profile?", function()
            BCDM.db:CopyProfile(source)
            controls.state.copy = nil
            BCDM:UpdateBCDM()
            Refresh()
        end)
    end)
    managementControls.deleteButton:SetScript("OnClick", function()
        local name = controls.state.delete
        if not name then return end
        BCDM:CreatePrompt("Delete Profile", "Delete profile '" .. name .. "'?", function()
            BCDM.db:DeleteProfile(name)
            controls.state.delete = nil
            Refresh()
        end)
    end)
    sharingControls.exportButton:SetScript("OnClick", function()
        local name = controls.state.export or BCDM.db:GetCurrentProfile()
        local encoded = BCDMG:ExportBCDM(name)
        if encoded then ShowExport(encoded) end
    end)
    sharingControls.importButton:SetScript("OnClick", function()
        local encoded = strtrim(sharingControls.importDataEdit:GetText() or "")
        if encoded ~= "" then
            BCDM:ImportSavedVariables(encoded)
            sharingControls.importDataEdit:SetText("")
        end
    end)

    panel:SetScript("OnShow", Refresh)
    controls.scrollFrame:SetScript("OnSizeChanged", Refresh)
    panel.Refresh = Refresh
    panel.OnRefresh = Refresh
    BCDMG.RefreshProfiles = Refresh
    return panel
end

function BCDM:RegisterProfilesSettings(parentCategory)
    profilesPanel = profilesPanel or CreateProfilesPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(parentCategory, profilesPanel, U.L("Profiles"))
    Settings.RegisterAddOnCategory(category)
    return profilesPanel
end
