local _, BCDM = ...

local U = BCDM.SettingsUtils
local Canvas = U.Canvas
local selectedBarID
local selectedEntryID
local customTrackerPanel
local entryDialog

local ANCHOR_POINTS = {
    { text = "Top Left", value = "TOPLEFT" }, { text = "Top", value = "TOP" },
    { text = "Top Right", value = "TOPRIGHT" }, { text = "Left", value = "LEFT" },
    { text = "Center", value = "CENTER" }, { text = "Right", value = "RIGHT" },
    { text = "Bottom Left", value = "BOTTOMLEFT" }, { text = "Bottom", value = "BOTTOM" },
    { text = "Bottom Right", value = "BOTTOMRIGHT" },
}

local GROWTH = {
    { text = "Right", value = "RIGHT" }, { text = "Left", value = "LEFT" },
    { text = "Up", value = "UP" }, { text = "Down", value = "DOWN" },
}

local STRATA = {
    { text = "Background", value = "BACKGROUND" }, { text = "Low", value = "LOW" },
    { text = "Medium", value = "MEDIUM" }, { text = "High", value = "HIGH" },
    { text = "Dialog", value = "DIALOG" }, { text = "Tooltip", value = "TOOLTIP" },
}

local function Store()
    return BCDM:GetCustomTrackerStore()
end

local function SelectedBar()
    local store = Store()
    if selectedBarID and store.Bars[selectedBarID] then return store.Bars[selectedBarID] end
    selectedBarID = store.BarOrder[1]
    return selectedBarID and store.Bars[selectedBarID] or nil
end

local function SelectedEntry()
    local bar = SelectedBar()
    if not bar then
        selectedEntryID = nil
        return nil
    end
    if selectedEntryID and bar.Entries and bar.Entries[selectedEntryID] then
        return bar.Entries[selectedEntryID]
    end
    selectedEntryID = bar.EntryOrder and bar.EntryOrder[1] or nil
    return selectedEntryID and bar.Entries[selectedEntryID] or nil
end

local function SetCustomTrackerSettingsPreview(barID)
    if BCDM.CustomTrackerSettingsPreviewBarID == barID then return end
    BCDM.CustomTrackerSettingsPreviewBarID = barID
    BCDM:RefreshCustomTrackers()
end

local function RefreshSelectedBarHighlight()
    if not customTrackerPanel or not customTrackerPanel:IsShown() then
        BCDM:HideSettingsHighlight("CustomTrackerOverlay")
        return
    end
    local bar = SelectedBar()
    SetCustomTrackerSettingsPreview(bar and selectedBarID or nil)
    local container = selectedBarID and BCDM.CustomTrackerRuntime
        and BCDM.CustomTrackerRuntime.Containers[selectedBarID]
    if not bar or bar.Enabled == false or not container then
        BCDM:HideSettingsHighlight("CustomTrackerOverlay")
        return
    end
    local width, height = BCDM:GetIconDimensions(bar)
    local point = select(1, container:GetPoint(1)) or (bar.Layout and bar.Layout[1]) or "CENTER"
    local icons = BCDM.CustomTrackerRuntime.Icons[selectedBarID]
    BCDM:ShowSettingsHighlightForFrames("CustomTrackerOverlay", icons, container, {
        width = width,
        height = height,
        point = point,
    })
end

local function Changed(panel)
    BCDM:RefreshCustomTrackers()
    RefreshSelectedBarHighlight()
    panel:Refresh()
end

local function BarValues()
    local values = {}
    for _, barID in ipairs(Store().BarOrder) do
        local bar = Store().Bars[barID]
        if bar then values[#values + 1] = { text = bar.Name or ("Tracker Bar " .. barID), value = barID } end
    end
    return values
end

local function AnchorValues()
    local values = {}
    local anchors = BCDM:GetAnchorParents("CustomTrackers")
    if anchors then
        for _, key in ipairs(anchors[2]) do
            values[#values + 1] = { text = anchors[1][key], value = key }
        end
    end
    for _, barID in ipairs(Store().BarOrder) do
        if barID ~= selectedBarID then
            local bar = Store().Bars[barID]
            values[#values + 1] = { text = "BCDM: " .. (bar.Name or ("Tracker Bar " .. barID)), value = "BCDM_CustomTrackerBar_" .. barID }
        end
    end
    return values
end

local function AccessBar(field, panel, fallback)
    return function()
        local bar = SelectedBar()
        local value = bar and bar[field]
        if value == nil then return fallback end
        return value
    end, function(value)
        local bar = SelectedBar()
        if not bar then return end
        bar[field] = value
        Changed(panel)
    end
end

local function AccessBarPath(path, panel, fallback)
    return function()
        local value = SelectedBar()
        for index = 1, #path do
            if type(value) ~= "table" then return fallback end
            value = value[path[index]]
        end
        if value == nil then return fallback end
        return value
    end, function(value)
        local target = SelectedBar()
        if not target then return end
        for index = 1, #path - 1 do
            local key = path[index]
            if type(target[key]) ~= "table" then target[key] = {} end
            target = target[key]
        end
        target[path[#path]] = value
        Changed(panel)
    end
end

local function AccessLayout(index, panel, fallback)
    return function()
        local bar = SelectedBar()
        local value = bar and bar.Layout and bar.Layout[index]
        if value == nil then return fallback end
        return value
    end, function(value)
        local bar = SelectedBar()
        if not bar then return end
        bar.Layout = bar.Layout or { "CENTER", "NONE", "CENTER", 0, 0 }
        if index == 2 then
            local targetID = type(value) == "string" and tonumber(value:match("^BCDM_CustomTrackerBar_(%d+)$"))
            if targetID and BCDM:WouldCustomTrackerAnchorCycle(selectedBarID, targetID) then
                BCDM:PrettyPrint("That anchor would create a tracker-bar cycle.")
                return
            end
        end
        bar.Layout[index] = value
        Changed(panel)
    end
end

local function CreateManagement(panel, controls)
    local section = U.Section(controls, "Tracker Bars", true)
    U.Text(controls, section, "Create any number of named bars and mix spells, items, equipment, and timers in each bar.")
    U.Dropdown(controls, section, "Selected Bar", function()
        SelectedBar()
        return selectedBarID
    end, function(value)
        selectedBarID = value
        selectedEntryID = nil
        SelectedEntry()
        RefreshSelectedBarHighlight()
        panel:Refresh()
    end, BarValues, { forceSingleColumn = true, minWidth = 360 })

    local getEnabled, setEnabled = AccessBar("Enabled", panel, false)
    U.Checkbox(controls, section, "Enable Bar", getEnabled, setEnabled, {
        disabled = function() return SelectedBar() == nil end,
    })

    U.Buttons(controls, section, {
        { text = "Add Bar", width = 120, click = function()
            selectedBarID = BCDM:AddCustomTrackerBar()
            selectedEntryID = nil
            Changed(panel)
        end },
        { text = "Duplicate", width = 120, disabled = function() return SelectedBar() == nil end, click = function()
            if selectedBarID then
                selectedBarID = BCDM:DuplicateCustomTrackerBar(selectedBarID)
                selectedEntryID = nil
                Changed(panel)
            end
        end },
        { text = "Rename", width = 120, disabled = function() return SelectedBar() == nil end, click = function()
            local bar = SelectedBar()
            if not bar then return end
            StaticPopupDialogs.BCDM_RENAME_TRACKER_BAR = {
                text = "Rename Tracker Bar",
                button1 = "Rename",
                button2 = CANCEL,
                hasEditBox = true,
                editBoxWidth = 300,
                maxLetters = 64,
                OnShow = function(dialog, data)
                    local editBox = dialog:GetEditBox()
                    editBox:SetText(data.name or "")
                    editBox:SetFocus()
                    editBox:HighlightText()
                end,
                OnAccept = function(dialog, data)
                    local name = dialog:GetEditBox():GetText():match("^%s*(.-)%s*$")
                    if name ~= "" and BCDM:RenameCustomTrackerBar(data.barID, name) then Changed(data.panel) end
                end,
                EditBoxOnEnterPressed = function(editBox)
                    local dialog = editBox:GetParent()
                    if dialog:GetButton1():IsEnabled() then dialog:GetButton1():Click() end
                end,
                EditBoxOnTextChanged = function(editBox)
                    local name = editBox:GetText():match("^%s*(.-)%s*$")
                    editBox:GetParent():GetButton1():SetEnabled(name ~= "")
                end,
                EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            local dialog = StaticPopup_Show("BCDM_RENAME_TRACKER_BAR", nil, nil, {
                barID = selectedBarID,
                name = bar.Name,
                panel = panel,
            })
            if dialog then dialog:SetFrameStrata("TOOLTIP") end
        end },
        { text = "Delete", width = 120, disabled = function() return SelectedBar() == nil end, click = function()
            if not selectedBarID then return end
            local deleting = selectedBarID
            BCDM:CreatePrompt("Delete Tracker Bar", "Delete this tracker bar and all of its entries?", function()
                BCDM:DeleteCustomTrackerBar(deleting)
                selectedBarID = nil
                selectedEntryID = nil
                Changed(panel)
            end)
        end },
    })
end

local function AddLayoutControls(panel, controls)
    local section = U.Section(controls, "Selected Bar Layout & Positioning", true)
    local function Disabled() return SelectedBar() == nil end
    local get, set = AccessLayout(1, panel, "CENTER")
    U.Dropdown(controls, section, "Anchor From", get, set, function() return ANCHOR_POINTS end, { disabled = Disabled })
    get, set = AccessLayout(2, panel, "NONE")
    U.Dropdown(controls, section, "Anchor Parent", get, set, AnchorValues,
        { disabled = Disabled, maxHeight = 420, forceSingleColumn = true, minWidth = 360 })
    get, set = AccessLayout(3, panel, "CENTER")
    U.Dropdown(controls, section, "Anchor To", get, set, function() return ANCHOR_POINTS end, { disabled = Disabled })
    get, set = AccessLayout(4, panel, 0)
    U.Slider(controls, section, "X Offset", get, set, { min = -3000, max = 3000, step = 0.1, disabled = Disabled })
    get, set = AccessLayout(5, panel, 0)
    U.Slider(controls, section, "Y Offset", get, set, { min = -3000, max = 3000, step = 0.1, disabled = Disabled })
    get, set = AccessBar("GrowthDirection", panel, "RIGHT")
    U.Dropdown(controls, section, "Growth Direction", get, set, function() return GROWTH end, { disabled = Disabled })
    get, set = AccessBar("Spacing", panel, 1)
    U.Slider(controls, section, "Icon Spacing", get, set, { min = -1, max = 32, step = 0.1, disabled = Disabled })
    get, set = AccessBar("Columns", panel, 0)
    U.Slider(controls, section, "Wrap After", get, set, { min = 0, max = 24, step = 1, disabled = Disabled })
    get, set = AccessBar("FrameStrata", panel, "LOW")
    U.Dropdown(controls, section, "Frame Strata", get, set, function() return STRATA end, { disabled = Disabled })
end

local function AddIconSettings(panel, controls)
    local section = U.Section(controls, "Icon Settings", true)
    local function Disabled() return SelectedBar() == nil end
    local function AspectLocked()
        local bar = SelectedBar()
        return not bar or bar.KeepAspectRatio ~= false
    end
    local function AspectUnlocked()
        local bar = SelectedBar()
        return not bar or bar.KeepAspectRatio == false
    end

    U.Checkbox(controls, section, "Keep Aspect Ratio", function()
        local bar = SelectedBar()
        return bar and bar.KeepAspectRatio ~= false
    end, function(value)
        local bar = SelectedBar()
        if not bar then return end
        local fallback = bar.IconSize or bar.IconWidth or bar.IconHeight or 38
        bar.KeepAspectRatio = value
        if value then bar.IconSize = bar.IconWidth or bar.IconHeight or fallback
        else
            bar.IconWidth = bar.IconWidth or fallback
            bar.IconHeight = bar.IconHeight or fallback
        end
        Changed(panel)
    end, { disabled = Disabled })

    local get, set = AccessBar("IconSize", panel, 38)
    U.Slider(controls, section, "Icon Size", get, set, {
        min = 16, max = 128, step = 0.1, disabled = AspectUnlocked,
    })
    get, set = AccessBar("IconWidth", panel, 38)
    U.Slider(controls, section, "Icon Width", get, set, {
        min = 16, max = 128, step = 0.1, disabled = AspectLocked,
    })
    get, set = AccessBar("IconHeight", panel, 38)
    U.Slider(controls, section, "Icon Height", get, set, {
        min = 16, max = 128, step = 0.1, disabled = AspectLocked,
    })
end

local function AddTextSettings(panel, controls)
    local section = U.Section(controls, "Text Settings", true)
    local function Disabled() return SelectedBar() == nil end
    U.Text(controls, section, "Controls charge, stack, and item-count text on this tracker bar.")

    local get, set = AccessBarPath({ "Text", "Layout", 1 }, panel, "BOTTOMRIGHT")
    U.Dropdown(controls, section, "Anchor From", get, set, function() return ANCHOR_POINTS end, { disabled = Disabled })
    get, set = AccessBarPath({ "Text", "Layout", 2 }, panel, "BOTTOMRIGHT")
    U.Dropdown(controls, section, "Anchor To", get, set, function() return ANCHOR_POINTS end, { disabled = Disabled })
    get, set = AccessBarPath({ "Text", "Layout", 3 }, panel, 0)
    U.Slider(controls, section, "X Offset", get, set, { min = -500, max = 500, step = 0.1, disabled = Disabled })
    get, set = AccessBarPath({ "Text", "Layout", 4 }, panel, 0)
    U.Slider(controls, section, "Y Offset", get, set, { min = -500, max = 500, step = 0.1, disabled = Disabled })
    get, set = AccessBarPath({ "Text", "FontSize" }, panel, 12)
    U.Slider(controls, section, "Font Size", get, set, { min = 6, max = 72, step = 1, disabled = Disabled })
    get, set = AccessBarPath({ "Text", "Colour" }, panel, { 1, 1, 1 })
    U.Color(controls, section, "Font Colour", get, set, { disabled = Disabled })
end

local function ResolveSpellID(value)
    if type(value) ~= "string" and type(value) ~= "number" then return end
    if type(value) == "string" then
        value = value:match("^%s*(.-)%s*$")
        if value == "" then return end
    end
    local numeric = tonumber(value)
    if numeric and (numeric <= 0 or numeric >= math.huge) then return end
    if not C_Spell or type(C_Spell.GetSpellInfo) ~= "function" then return end
    local ok, info = pcall(C_Spell.GetSpellInfo, numeric or value)
    if not ok then return end
    return info and info.spellID
end

local function EntryName(entry)
    local source = entry.Source or {}
    local adapter = BCDM.CustomTrackerSourceAdapters and BCDM.CustomTrackerSourceAdapters[source.Type]
    local name, icon
    if adapter and adapter.GetMetadata then name, icon = adapter.GetMetadata(source) end
    return name or (source.Type .. " " .. tostring(source.ID)), icon
end

local function EntryItemCount(entry)
    local source = type(entry) == "table" and entry.Source
    if not (type(source) == "table" and source.Type == "item" and C_Item and C_Item.GetItemCount) then return "" end
    local ok, count = pcall(C_Item.GetItemCount, source.ID)
    if not ok or type(count) ~= "number" or BCDM:IsSecretValue(count) or count <= 0 then return "" end
    return tostring(count)
end

local DISPLAY_MODES = U.DISPLAY_MODES
local VISUAL_MODES = U.VISUAL_MODES
local GLOW_MODES = U.GLOW_MODES

local EQUIPMENT_SLOTS = {
    { text = "Head", value = 1 }, { text = "Neck", value = 2 }, { text = "Shoulder", value = 3 },
    { text = "Shirt", value = 4 }, { text = "Chest", value = 5 }, { text = "Waist", value = 6 },
    { text = "Legs", value = 7 }, { text = "Feet", value = 8 }, { text = "Wrist", value = 9 },
    { text = "Hands", value = 10 }, { text = "Finger 1", value = 11 }, { text = "Finger 2", value = 12 },
    { text = "Trinket 1", value = 13 }, { text = "Trinket 2", value = 14 }, { text = "Back", value = 15 },
    { text = "Main Hand", value = 16 }, { text = "Off Hand", value = 17 }, { text = "Tabard", value = 19 },
}

local function SetupFilterMenu(button, entry, panel)
    if type(button.SetupMenu) ~= "function" then return end
    button:SetupMenu(function(_, root)
        root:SetScrollMode(420)
        for _, classEntry in ipairs(BCDM:GetClassSpecCatalog(entry.FilterClass)) do
            local submenu = root:CreateButton(classEntry.className or classEntry.classToken)
            for _, specEntry in ipairs(classEntry.specs or {}) do
                local value = specEntry.specID
                submenu:CreateCheckbox(specEntry.specName or tostring(specEntry.specID), function()
                    return entry.SpecFilters and entry.SpecFilters[value] == true
                end, function()
                    entry.SpecFilters = entry.SpecFilters or {}
                    entry.SpecFilters[value] = not entry.SpecFilters[value] or nil
                    Changed(panel)
                end)
            end
        end
    end)
end

local SOURCE_LABELS = {
    spell = "Spell",
    item = "Item",
    equipment = "Equipment Slot",
    timer = "Cast Timer",
}

local UNKNOWN_ICON = 134400

local function RequestItemData(itemID)
    if itemID and BCDM.RequestCustomTrackerItemData then BCDM:RequestCustomTrackerItemData(itemID) end
end

local function CreateEntryDialog()
    if entryDialog then return entryDialog end

    local dialog = CreateFrame("Frame", "BCDMCustomTrackerEntryDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(430, 230)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(100)
    dialog:SetClampedToScreen(true)
    dialog:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    dialog:SetBackdropColor(0.025, 0.025, 0.035, 0.98)
    dialog:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    dialog:Hide()

    dialog.Title = Canvas.CreateLabel(dialog, "Add Tracker Entry", "GameFontNormalLarge")
    dialog.Title:SetPoint("TOPLEFT", 18, -16)
    dialog.Title:SetTextColor(1, 0.82, 0)
    dialog.Close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.Close:SetPoint("TOPRIGHT", -2, -2)
    dialog.Close:SetScript("OnClick", function() dialog:Hide() end)

    dialog.Icon = dialog:CreateTexture(nil, "ARTWORK")
    dialog.Icon:SetSize(44, 44)
    dialog.Icon:SetPoint("TOPLEFT", 18, -50)
    dialog.Icon:SetTexture(UNKNOWN_ICON)
    dialog.PreviewName = Canvas.CreateLabel(dialog, "Enter a source below", "GameFontHighlight")
    dialog.PreviewName:SetPoint("TOPLEFT", dialog.Icon, "TOPRIGHT", 12, -2)
    dialog.PreviewName:SetPoint("RIGHT", dialog, "RIGHT", -18, 0)
    dialog.PreviewName:SetWordWrap(false)
    dialog.PreviewSource = Canvas.CreateLabel(dialog, "", "GameFontHighlightSmall")
    dialog.PreviewSource:SetPoint("TOPLEFT", dialog.PreviewName, "BOTTOMLEFT", 0, -6)
    dialog.PreviewSource:SetTextColor(0.65, 0.65, 0.65)

    dialog.PrimaryLabel = Canvas.CreateLabel(dialog, "Spell ID or Name", "GameFontHighlightSmall")
    dialog.PrimaryLabel:SetPoint("TOPLEFT", 18, -106)
    dialog.Primary = Canvas.CreateInput(dialog)
    dialog.Primary:SetPoint("TOPLEFT", dialog.PrimaryLabel, "BOTTOMLEFT", 0, -4)
    dialog.Primary:SetPoint("RIGHT", dialog, "RIGHT", -18, 0)

    dialog.DurationLabel = Canvas.CreateLabel(dialog, "Duration (seconds)", "GameFontHighlightSmall")
    dialog.DurationLabel:SetPoint("TOPLEFT", dialog.Primary, "BOTTOMLEFT", 0, -10)
    dialog.Duration = Canvas.CreateInput(dialog)
    dialog.Duration:SetPoint("TOPLEFT", dialog.DurationLabel, "BOTTOMLEFT", 0, -4)
    dialog.Duration:SetWidth(130)

    dialog.Error = Canvas.CreateLabel(dialog, "", "GameFontHighlightSmall")
    dialog.Error:SetPoint("BOTTOMLEFT", 18, 18)
    dialog.Error:SetPoint("RIGHT", dialog, "RIGHT", -190, 0)
    dialog.Error:SetTextColor(1, 0.25, 0.2)

    dialog.Cancel = Canvas.CreateActionButton(dialog, "Cancel")
    dialog.Cancel:SetSize(86, 26)
    dialog.Cancel:SetPoint("BOTTOMRIGHT", -18, 14)
    dialog.Cancel:SetScript("OnClick", function() dialog:Hide() end)
    dialog.Add = Canvas.CreateActionButton(dialog, "Add")
    dialog.Add:SetSize(86, 26)
    dialog.Add:SetPoint("RIGHT", dialog.Cancel, "LEFT", -8, 0)

    function dialog:ResolveSource()
        if self.Mode == "item" then
            local itemID = tonumber(self.Primary:GetText())
            if not itemID or itemID <= 0 or itemID >= math.huge or itemID ~= math.floor(itemID) then return nil end
            return itemID
        end
        return ResolveSpellID(self.Primary:GetText())
    end

    function dialog:RefreshPreview()
        local sourceID = self:ResolveSource()
        local sourceType = self.Mode == "timer" and "timer" or self.Mode
        local adapter = BCDM.CustomTrackerSourceAdapters and BCDM.CustomTrackerSourceAdapters[sourceType]
        local name, icon
        if sourceID and adapter and adapter.GetMetadata then
            if sourceType == "item" then RequestItemData(sourceID) end
            name, icon = adapter.GetMetadata({ Type = sourceType, ID = sourceID })
        end
        self.Icon:SetTexture(icon or UNKNOWN_ICON)
        self.PreviewName:SetText(name or (sourceID and ((SOURCE_LABELS[sourceType] or "Source") .. " " .. sourceID)
            or "Enter a source below"))
        self.PreviewSource:SetText(sourceID and ((SOURCE_LABELS[sourceType] or sourceType) .. " ID: " .. sourceID) or "")
    end

    function dialog:SchedulePreview()
        if self.PreviewTimer then self.PreviewTimer:Cancel() end
        self.PreviewTimer = C_Timer.NewTimer(0.12, function()
            dialog.PreviewTimer = nil
            if dialog:IsShown() then dialog:RefreshPreview() end
        end)
    end

    function dialog:Submit()
        local sourceID = self:ResolveSource()
        if not sourceID then
            self.Error:SetText(self.Mode == "item" and "Enter a valid positive item ID."
                or "Enter a valid spell ID or name.")
            return
        end
        local duration
        if self.Mode == "timer" then
            duration = tonumber(self.Duration:GetText())
            if not duration or duration <= 0 or duration >= math.huge then
                self.Error:SetText("Enter a duration greater than zero.")
                return
            end
        end
        if not selectedBarID or not Store().Bars[selectedBarID] then
            self.Error:SetText("Select a tracker bar first.")
            return
        end

        local extra
        if self.Mode == "spell" or self.Mode == "timer" then
            local class = select(2, UnitClass("player"))
            extra = { SpecFilters = BCDM:BuildSpecFilters(class), FilterClass = class, Duration = duration }
        else
            extra = { SpecFilters = BCDM:BuildSpecFilters() }
            RequestItemData(sourceID)
        end
        selectedEntryID = BCDM:AddCustomTrackerEntry(selectedBarID, self.Mode, sourceID, extra)
        self:Hide()
        Changed(self.Panel)
    end

    function dialog:ShowFor(mode, panel)
        self.Mode, self.Panel = mode, panel
        self.Title:SetText(mode == "spell" and "Add Spell" or mode == "item" and "Add Item" or "Add Cast Timer")
        self.PrimaryLabel:SetText(mode == "item" and "Item ID" or "Spell ID or Name")
        self.Primary:SetText("")
        self.Duration:SetText("")
        self.Error:SetText("")
        local isTimer = mode == "timer"
        self.DurationLabel:SetShown(isTimer)
        self.Duration:SetShown(isTimer)
        self:SetHeight(isTimer and 270 or 230)
        self:RefreshPreview()
        self:Show()
        self:Raise()
        self.Primary:SetFocus()
    end

    dialog.Primary:SetScript("OnTextChanged", function() dialog:SchedulePreview() end)
    dialog.Primary:SetScript("OnEnterPressed", function() dialog:Submit() end)
    dialog.Primary:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog.Duration:SetScript("OnEnterPressed", function() dialog:Submit() end)
    dialog.Duration:SetScript("OnEscapePressed", function() dialog:Hide() end)
    dialog.Add:SetScript("OnClick", function() dialog:Submit() end)
    dialog:SetScript("OnHide", function()
        if dialog.PreviewTimer then dialog.PreviewTimer:Cancel() dialog.PreviewTimer = nil end
        dialog.Primary:ClearFocus()
        dialog.Duration:ClearFocus()
    end)

    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = dialog:GetName() end
    entryDialog = dialog
    return dialog
end

local function AddEquipmentEntry(slotID, panel)
    if not selectedBarID or not Store().Bars[selectedBarID] then return end
    selectedEntryID = BCDM:AddCustomTrackerEntry(selectedBarID, "equipment", slotID, {
        SpecFilters = BCDM:BuildSpecFilters(),
    })
    Changed(panel)
end

local function OpenAddEntryMenu(owner, panel)
    if not selectedBarID or not MenuUtil or type(MenuUtil.CreateContextMenu) ~= "function" then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if type(root.SetMinimumWidth) == "function" then root:SetMinimumWidth(190) end
        root:CreateButton("Spell", function() CreateEntryDialog():ShowFor("spell", panel) end)
        root:CreateButton("Item", function() CreateEntryDialog():ShowFor("item", panel) end)
        local equipment = root:CreateButton("Equipment Slot")
        for _, slot in ipairs(EQUIPMENT_SLOTS) do
            equipment:CreateButton(slot.text, function() AddEquipmentEntry(slot.value, panel) end)
        end
        root:CreateButton("Cast Timer", function() CreateEntryDialog():ShowFor("timer", panel) end)
    end)
end

local function AddCursorEntry(panel)
    if not selectedBarID or not Store().Bars[selectedBarID] or type(GetCursorInfo) ~= "function" then return false end
    local cursorType, cursorInfo1, _, cursorInfo3 = GetCursorInfo()
    local sourceType, sourceID, extra
    if cursorType == "item" then
        if BCDM:IsSecretValue(cursorInfo1) then return false end
        sourceType, sourceID = "item", tonumber(cursorInfo1)
        if not sourceID or sourceID <= 0 then return false end
        extra = { SpecFilters = BCDM:BuildSpecFilters() }
        RequestItemData(sourceID)
    elseif cursorType == "spell" then
        local cursorSpell = cursorInfo3 or cursorInfo1
        if BCDM:IsSecretValue(cursorSpell) then return false end
        sourceType, sourceID = "spell", ResolveSpellID(cursorSpell)
        if not sourceID then return false end
        local class = select(2, UnitClass("player"))
        extra = { SpecFilters = BCDM:BuildSpecFilters(class), FilterClass = class }
    else
        return false
    end
    selectedEntryID = BCDM:AddCustomTrackerEntry(selectedBarID, sourceType, sourceID, extra)
    if not selectedEntryID then return false end
    ClearCursor()
    Changed(panel)
    return true
end

local function CreateEntries(panel, controls)
    local section = U.Section(controls, "Selected Bar Entries", true)
    U.Text(controls, section,
        "Drag to reorder. Click an icon to edit it, use + to add an entry, or drop a bag item or spellbook spell onto +.")

    local ICON_SIZE, ICON_STEP = U.SELECTOR_ICON_SIZE, U.SELECTOR_ICON_SIZE + 6
    local strip = Canvas.CreateBaseRow(section.Content, 56)
    U.Add(controls, section, strip)
    strip.Buttons = {}
    strip.Left = Canvas.CreateActionButton(strip, "<")
    strip.Left:SetSize(22, 44)
    strip.Left:SetPoint("LEFT", 0, 0)
    strip.Right = Canvas.CreateActionButton(strip, ">")
    strip.Right:SetSize(22, 44)
    strip.Scroll = CreateFrame("ScrollFrame", nil, strip)
    strip.Scroll:SetPoint("TOPLEFT", strip.Left, "TOPRIGHT", 6, 0)
    strip.Scroll:SetPoint("BOTTOMRIGHT", strip.Right, "BOTTOMLEFT", -6, 0)
    strip.Scroll:EnableMouseWheel(true)
    strip.Child = CreateFrame("Frame", nil, strip.Scroll)
    strip.Child:SetHeight(ICON_SIZE)
    strip.Child:SetWidth(1)
    strip.Scroll:SetScrollChild(strip.Child)
    strip.Marker = strip.Child:CreateTexture(nil, "OVERLAY")
    strip.Marker:SetColorTexture(1, 0.82, 0, 1)
    strip.Marker:SetSize(3, ICON_SIZE + 6)
    strip.Marker:Hide()

    local function SetHorizontalScroll(value)
        local range = strip.Scroll:GetHorizontalScrollRange() or 0
        strip.Scroll:SetHorizontalScroll(math.max(0, math.min(range, value or 0)))
        strip.Left:SetEnabled(strip.Scroll:GetHorizontalScroll() > 0)
        strip.Right:SetEnabled(strip.Scroll:GetHorizontalScroll() < range)
    end

    strip.Scroll:SetScript("OnScrollRangeChanged", function(_, horizontalRange)
        local offset = strip.Scroll:GetHorizontalScroll()
        strip.Left:SetEnabled(offset > 0)
        strip.Right:SetEnabled(offset < (horizontalRange or 0))
    end)

    strip.Left:SetScript("OnClick", function() SetHorizontalScroll(strip.Scroll:GetHorizontalScroll() - ICON_STEP * 3) end)
    strip.Right:SetScript("OnClick", function() SetHorizontalScroll(strip.Scroll:GetHorizontalScroll() + ICON_STEP * 3) end)
    strip.Scroll:SetScript("OnMouseWheel", function(_, delta)
        SetHorizontalScroll(strip.Scroll:GetHorizontalScroll() - delta * ICON_STEP * 2)
    end)

    local function FindEntryIndex(order, entryID)
        for index, id in ipairs(order or {}) do
            if id == entryID then return index end
        end
    end

    local function StyleEntryButton(button)
        if button.Selected then button:SetBackdropBorderColor(1, 0.82, 0, 1)
        elseif button.Hovered then button:SetBackdropBorderColor(1, 0.82, 0, 0.65)
        else button:SetBackdropBorderColor(0.2, 0.2, 0.2, 1) end
    end

    local function StopDragging()
        if not strip.DragEntryID then return end
        local entryID, target = strip.DragEntryID, strip.DragTarget
        strip.DragEntryID, strip.DragTarget, strip.DragSource = nil, nil, nil
        strip:SetScript("OnUpdate", nil)
        strip.Marker:Hide()
        if target and BCDM:ReorderCustomTrackerEntry(selectedBarID, entryID, target) then Changed(panel)
        else panel:Refresh() end
    end

    local function UpdateDragging()
        local bar = SelectedBar()
        local order = bar and bar.EntryOrder or {}
        if not strip.DragEntryID or #order == 0 then return end
        local scale = strip.Scroll:GetEffectiveScale()
        local cursorX = select(1, GetCursorPosition()) / scale
        local scrollLeft, scrollRight = strip.Scroll:GetLeft(), strip.Scroll:GetRight()
        if scrollLeft and cursorX < scrollLeft + 18 then
            SetHorizontalScroll(strip.Scroll:GetHorizontalScroll() - 8)
        elseif scrollRight and cursorX > scrollRight - 18 then
            SetHorizontalScroll(strip.Scroll:GetHorizontalScroll() + 8)
        end
        local childLeft = strip.Child:GetLeft()
        if not childLeft then return end
        local localX = cursorX - childLeft
        local target = math.floor(((localX - ICON_SIZE / 2) / ICON_STEP) + 1.5)
        target = math.max(1, math.min(#order, target))
        strip.DragTarget = target
        local targetButton = strip.Buttons[target]
        if targetButton then
            strip.Marker:ClearAllPoints()
            if target > (strip.DragSource or target) then
                strip.Marker:SetPoint("LEFT", targetButton, "RIGHT", 2, 0)
            else
                strip.Marker:SetPoint("RIGHT", targetButton, "LEFT", -2, 0)
            end
            strip.Marker:Show()
        end
    end

    local function EnsureEntryButton(index)
        if strip.Buttons[index] then return strip.Buttons[index] end
        local button = CreateFrame("Button", nil, strip.Child, "BackdropTemplate")
        button:SetSize(ICON_SIZE, ICON_SIZE)
        button:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetPoint("TOPLEFT", 2, -2)
        button.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
        button.Count = button:CreateFontString(nil, "OVERLAY")
        button:RegisterForClicks("LeftButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnClick", function(self)
            if not self.EntryID then return end
            selectedEntryID = self.EntryID
            panel:Refresh()
        end)
        button:SetScript("OnDragStart", function(self)
            local bar = SelectedBar()
            local source = bar and FindEntryIndex(bar.EntryOrder, self.EntryID)
            if not source then return end
            GameTooltip:Hide()
            selectedEntryID = self.EntryID
            strip.DragEntryID, strip.DragSource, strip.DragTarget = self.EntryID, source, source
            strip:SetScript("OnUpdate", UpdateDragging)
            UpdateDragging()
        end)
        button:SetScript("OnDragStop", StopDragging)
        button:SetScript("OnEnter", function(self)
            self.Hovered = true
            StyleEntryButton(self)
            if not self.Entry then return end
            local source = self.Entry.Source or {}
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.EntryName or "Tracker Entry", 1, 0.82, 0)
            GameTooltip:AddLine((SOURCE_LABELS[source.Type] or source.Type or "Source") .. " ID: " .. tostring(source.ID), 1, 1, 1)
            GameTooltip:AddLine("Click to edit. Drag to reorder.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            self.Hovered = false
            StyleEntryButton(self)
            GameTooltip:Hide()
        end)
        strip.Buttons[index] = button
        return button
    end

    strip.Add = CreateFrame("Button", nil, strip, "BackdropTemplate")
    strip.Add:SetSize(ICON_SIZE, ICON_SIZE)
    strip.Add:SetPoint("RIGHT", 0, 0)
    strip.Right:SetPoint("RIGHT", strip.Add, "LEFT", -6, 0)
    strip.Add:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    strip.Add:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
    strip.Add.Text = strip.Add:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    strip.Add.Text:SetPoint("CENTER", 0, 1)
    strip.Add.Text:SetText("+")
    strip.Add.Text:SetTextColor(1, 0.82, 0)
    strip.Add:SetScript("OnClick", function(self) OpenAddEntryMenu(self, panel) end)
    strip.Add:RegisterForDrag("LeftButton")
    strip.Add:SetScript("OnReceiveDrag", function() AddCursorEntry(panel) end)
    Canvas.AttachTooltip(strip.Add, "Add Entry",
        "Click to add an entry, or drag an item from your bags or a spell from your spellbook here.")

    function strip:Refresh()
        local bar = SelectedBar()
        local order = bar and bar.EntryOrder or {}
        if self.BarID ~= selectedBarID then
            self.BarID = selectedBarID
            self.Scroll:SetHorizontalScroll(0)
        end
        SelectedEntry()
        for index, entryID in ipairs(order) do
            local entry = bar.Entries[entryID]
            local button = EnsureEntryButton(index)
            local name, icon = EntryName(entry)
            button.EntryID, button.Entry, button.EntryName = entryID, entry, name
            U.SetSettingsIcon(button.Icon, icon or UNKNOWN_ICON)
            local style = BCDM:GetCustomTrackerEntrySettings(bar, entry)
            local visualMode = style.VisualMode or "FULL"
            local disabled = entry.Enabled == false
            if button.Icon.SetDesaturation then
                button.Icon:SetDesaturation((disabled or visualMode == "DESATURATE") and 1 or 0)
            end
            local alpha = disabled and 0.45 or visualMode == "LOW_ALPHA" and (tonumber(style.Alpha) or 0.45) or 1
            button.Icon:SetAlpha(alpha)
            local text = bar.Text or {}
            local layout = text.Layout or { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
            button.Count:ClearAllPoints()
            button.Count:SetPoint(layout[1], button, layout[2], layout[3], layout[4])
            button.Count:SetFont((BCDM.Media and BCDM.Media.Font) or STANDARD_TEXT_FONT,
                text.FontSize or 12, BCDM.db.profile.General.Fonts.FontFlag)
            local colour = text.Colour or { 1, 1, 1 }
            button.Count:SetTextColor(colour[1], colour[2], colour[3], 1)
            button.Count:SetText(style.TextEnabled ~= false and EntryItemCount(entry) or "")
            button.Count:SetAlpha(alpha)
            if not disabled and style.Glow and style.Glow ~= "NONE" then BCDM:StartCustomGlow(button)
            else BCDM:StopCustomGlow(button) end
            button.Selected = entryID == selectedEntryID
            button:ClearAllPoints()
            button:SetPoint("LEFT", self.Child, "LEFT", (index - 1) * ICON_STEP, 0)
            StyleEntryButton(button)
            button:Show()
        end
        for index = #order + 1, #self.Buttons do
            BCDM:StopCustomGlow(self.Buttons[index])
            self.Buttons[index]:Hide()
        end
        self.Add:SetShown(bar ~= nil)
        local contentWidth = math.max(1, #order * ICON_STEP - (ICON_STEP - ICON_SIZE))
        self.Child:SetWidth(math.max(contentWidth, self.Scroll:GetWidth()))
        self.Scroll:UpdateScrollChildRect()
        SetHorizontalScroll(self.Scroll:GetHorizontalScroll())
    end
    strip:HookScript("OnHide", function()
        for _, button in ipairs(strip.Buttons) do BCDM:StopCustomGlow(button) end
    end)

    U.Subsection(controls, section, "Selected Entry Settings")

    local header = Canvas.CreateBaseRow(section.Content, 58)
    U.Add(controls, section, header)
    header.Empty = Canvas.CreateLabel(header, "This bar has no entries yet. Use + above to add one.", "GameFontHighlight")
    header.Empty:SetPoint("LEFT", 0, 0)
    header.Icon = header:CreateTexture(nil, "ARTWORK")
    header.Icon:SetSize(U.SELECTED_ICON_SIZE, U.SELECTED_ICON_SIZE)
    header.Icon:SetPoint("LEFT", 0, 0)
    header.Name = Canvas.CreateLabel(header, "", "GameFontNormalLarge")
    header.Name:SetPoint("TOPLEFT", header.Icon, "TOPRIGHT", 12, -4)
    header.Name:SetPoint("RIGHT", header, "RIGHT", -245, 0)
    header.Name:SetWordWrap(false)
    header.Source = Canvas.CreateLabel(header, "", "GameFontHighlightSmall")
    header.Source:SetPoint("TOPLEFT", header.Name, "BOTTOMLEFT", 0, -6)
    header.Source:SetTextColor(0.65, 0.65, 0.65)
    header.Enabled = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    header.Enabled:SetSize(24, 24)
    header.Enabled:SetPoint("RIGHT", header, "RIGHT", -120, 0)
    header.EnabledLabel = Canvas.CreateLabel(header, "Enabled", "GameFontHighlight")
    header.EnabledLabel:SetPoint("RIGHT", header.Enabled, "LEFT", -2, 0)
    header.Delete = Canvas.CreateActionButton(header, "Delete")
    header.Delete:SetSize(92, 26)
    header.Delete:SetPoint("RIGHT", 0, 0)
    header.Enabled:SetScript("OnClick", function(self)
        local entry = SelectedEntry()
        if entry then entry.Enabled = self:GetChecked() == true Changed(panel) end
    end)
    header.Delete:SetScript("OnClick", function()
        local bar = SelectedBar()
        if not bar or not selectedEntryID then return end
        local index = FindEntryIndex(bar.EntryOrder, selectedEntryID)
        if not index or not BCDM:DeleteCustomTrackerEntry(selectedBarID, selectedEntryID) then return end
        selectedEntryID = bar.EntryOrder[index] or bar.EntryOrder[index - 1]
        Changed(panel)
    end)
    function header:Refresh()
        local entry = SelectedEntry()
        self.Empty:SetText(SelectedBar() and "This bar has no entries yet. Use + above to add one."
            or "Create or select a tracker bar to add entries.")
        self.Empty:SetShown(entry == nil)
        for _, region in ipairs({ self.Icon, self.Name, self.Source, self.Enabled, self.EnabledLabel, self.Delete }) do
            region:SetShown(entry ~= nil)
        end
        if not entry then return end
        local name, icon = EntryName(entry)
        local source = entry.Source or {}
        U.SetSettingsIcon(self.Icon, icon or UNKNOWN_ICON)
        self.Name:SetText(name)
        local sourceText = (SOURCE_LABELS[source.Type] or source.Type or "Source") .. " ID: " .. tostring(source.ID)
        if source.Type == "timer" then sourceText = sourceText .. "  •  " .. tostring(source.Duration or 0) .. " seconds" end
        self.Source:SetText(sourceText)
        self.Enabled:SetChecked(entry.Enabled ~= false)
    end

    local function NoEntry() return SelectedEntry() == nil end
    local function EntryField(field, fallback)
        return function()
            local entry = SelectedEntry()
            local value = entry and entry[field]
            return value == nil and fallback or value
        end, function(value)
            local entry = SelectedEntry()
            if entry then entry[field] = value Changed(panel) end
        end
    end
    local function EntryStyleField(field, fallback)
        return function()
            local bar, entry = SelectedBar(), SelectedEntry()
            local style = entry and BCDM:GetCustomTrackerEntrySettings(bar, entry)
            local value = style and style[field]
            return value == nil and fallback or value
        end, function(value)
            local entry = SelectedEntry()
            if entry then entry[field] = value Changed(panel) end
        end
    end

    local get, set
    U.Checkbox(controls, section, "Use Shared Settings", function()
        local entry = SelectedEntry()
        return entry and entry.OverrideBarSettings ~= true
    end, function(value)
        local bar, entry = SelectedBar(), SelectedEntry()
        if not entry then return end
        if value ~= true and entry.OverrideBarSettings ~= true then
            local shared = BCDM:GetCustomTrackerEntrySettings(bar, entry)
            entry.DisplayMode = shared.DisplayMode or "ALWAYS"
            entry.VisualMode = shared.VisualMode or "FULL"
            entry.Alpha = tonumber(shared.Alpha) or 0.45
            entry.Glow = shared.Glow or "NONE"
            entry.TextEnabled = shared.TextEnabled ~= false
            entry.Tooltip = shared.Tooltip ~= false
            entry.FilterClass = shared.FilterClass
            entry.SpecFilters = nil
            if type(shared.SpecFilters) == "table" then
                entry.SpecFilters = {}
                for specID, enabled in pairs(shared.SpecFilters) do
                    if enabled == true then entry.SpecFilters[specID] = true end
                end
            end
            entry.ClassSpecFilters = nil
            if type(shared.ClassSpecFilters) == "table" then
                entry.ClassSpecFilters = {}
                for key, enabled in pairs(shared.ClassSpecFilters) do
                    if enabled == true then entry.ClassSpecFilters[key] = true end
                end
            end
        end
        entry.OverrideBarSettings = value ~= true
        Changed(panel)
    end, { hidden = NoEntry })
    local function SharedEntryStyle()
        local entry = SelectedEntry()
        return not entry or entry.OverrideBarSettings ~= true
    end
    get, set = EntryStyleField("DisplayMode", "ALWAYS")
    U.Dropdown(controls, section, "Display Mode", get, set, function() return DISPLAY_MODES end,
        { hidden = SharedEntryStyle })
    get, set = EntryStyleField("VisualMode", "FULL")
    U.Dropdown(controls, section, "Appearance", get, set, function() return VISUAL_MODES end,
        { hidden = SharedEntryStyle })
    get, set = EntryStyleField("Alpha", 0.45)
    U.Slider(controls, section, "Opacity", get, set, {
        min = 0.05, max = 1, step = 0.05,
        hidden = function()
            local entry = SelectedEntry()
            return not entry or entry.OverrideBarSettings ~= true or entry.VisualMode ~= "LOW_ALPHA"
        end,
        formatter = function(value) return string.format("%.0f%%", (tonumber(value) or 0) * 100) end,
    })
    get, set = EntryStyleField("Glow", "NONE")
    U.Dropdown(controls, section, "Glow", get, set, function() return GLOW_MODES end,
        { hidden = SharedEntryStyle })
    get, set = EntryStyleField("TextEnabled", true)
    U.Checkbox(controls, section, "Show Text", get, set, { hidden = SharedEntryStyle })
    get, set = EntryStyleField("Tooltip", true)
    U.Checkbox(controls, section, "Show Tooltip", get, set, { hidden = SharedEntryStyle })

    local filters = Canvas.CreateBaseRow(section.Content, 28)
    U.Add(controls, section, filters)
    filters.Label = Canvas.CreateLabel(filters, "Class / Specialization", "GameFontHighlight")
    filters.Label:SetPoint("LEFT", 0, 0)
    filters.Dropdown = Canvas.CreateDropdown(filters)
    filters.Dropdown:SetPoint("RIGHT", 0, 0)
    filters.Dropdown:SetWidth(320)
    filters.Dropdown:OverrideText("Choose Class / Specialization")
    function filters:Refresh()
        local entry = SelectedEntry()
        self:SetShown(entry ~= nil and entry.OverrideBarSettings == true)
        if not entry or entry.OverrideBarSettings ~= true then return end
        SetupFilterMenu(self.Dropdown, entry, panel)
        self.Dropdown:OverrideText("Choose Class / Specialization")
    end

    local aura = Canvas.CreateBaseRow(section.Content, 52)
    U.Add(controls, section, aura)
    aura.Label = Canvas.CreateLabel(aura, "Extra Aura IDs", "GameFontHighlight")
    aura.Label:SetPoint("TOPLEFT", 0, -2)
    aura.Help = Canvas.CreateLabel(aura, "Optional comma-separated overrides; source spell matching remains automatic.", "GameFontHighlightSmall")
    aura.Help:SetPoint("TOPLEFT", aura.Label, "BOTTOMLEFT", 0, -4)
    aura.Help:SetTextColor(0.65, 0.65, 0.65)
    aura.Input = Canvas.CreateInput(aura)
    aura.Input:SetPoint("TOPRIGHT", 0, 4)
    aura.Input:SetWidth(315)
    aura.Input:SetScript("OnEnterPressed", function(input)
        local entry = SelectedEntry()
        if not entry or not entry.Source or entry.Source.Type ~= "spell" then return end
        local auraIDs = BCDM:NormalizeCustomTrackerAuraIDs(input:GetText())
        entry.Source.AuraIDs = #auraIDs > 0 and auraIDs or nil
        input:ClearFocus()
        Changed(panel)
    end)
    aura.Input:SetScript("OnEscapePressed", function(input)
        local entry = SelectedEntry()
        local auraIDs = entry and entry.Source and BCDM:NormalizeCustomTrackerAuraIDs(entry.Source.AuraIDs) or {}
        input:SetText(table.concat(auraIDs, ", "))
        input:ClearFocus()
    end)
    function aura:Refresh()
        local entry = SelectedEntry()
        local shown = entry and entry.Source and entry.Source.Type == "spell"
        self:SetShown(shown == true)
        if not shown or self.Input:HasFocus() then return end
        local auraIDs = BCDM:NormalizeCustomTrackerAuraIDs(entry.Source.AuraIDs)
        entry.Source.AuraIDs = #auraIDs > 0 and auraIDs or nil
        self.Input:SetText(table.concat(auraIDs, ", "))
    end

    local sharedSection = U.Section(controls, "Shared Entry Settings", true)
    U.Text(controls, sharedSection, "Applied to every entry unless that entry enables its own override.")
    local function NoBar() return SelectedBar() == nil end
    local getShared, setShared = AccessBarPath({ "EntrySettings", "DisplayMode" }, panel, "ALWAYS")
    U.Dropdown(controls, sharedSection, "Display Mode", getShared, setShared, function() return DISPLAY_MODES end,
        { disabled = NoBar })
    getShared, setShared = AccessBarPath({ "EntrySettings", "VisualMode" }, panel, "FULL")
    U.Dropdown(controls, sharedSection, "Appearance", getShared, setShared, function() return VISUAL_MODES end,
        { disabled = NoBar })
    getShared, setShared = AccessBarPath({ "EntrySettings", "Alpha" }, panel, 0.45)
    U.Slider(controls, sharedSection, "Opacity", getShared, setShared, {
        min = 0.05, max = 1, step = 0.05,
        hidden = function()
            local bar = SelectedBar()
            return not bar or not bar.EntrySettings or bar.EntrySettings.VisualMode ~= "LOW_ALPHA"
        end,
        formatter = function(value) return string.format("%.0f%%", (tonumber(value) or 0) * 100) end,
    })
    getShared, setShared = AccessBarPath({ "EntrySettings", "Glow" }, panel, "NONE")
    U.Dropdown(controls, sharedSection, "Glow", getShared, setShared, function() return GLOW_MODES end,
        { disabled = NoBar })
    getShared, setShared = AccessBarPath({ "EntrySettings", "TextEnabled" }, panel, true)
    U.Checkbox(controls, sharedSection, "Show Text", getShared, setShared, { disabled = NoBar })
    getShared, setShared = AccessBarPath({ "EntrySettings", "Tooltip" }, panel, true)
    U.Checkbox(controls, sharedSection, "Show Tooltip", getShared, setShared, { disabled = NoBar })

    local sharedFilters = Canvas.CreateBaseRow(sharedSection.Content, 28)
    U.Add(controls, sharedSection, sharedFilters)
    sharedFilters.Label = Canvas.CreateLabel(sharedFilters, "Class / Specialization", "GameFontHighlight")
    sharedFilters.Label:SetPoint("LEFT", 0, 0)
    sharedFilters.Dropdown = Canvas.CreateDropdown(sharedFilters)
    sharedFilters.Dropdown:SetPoint("RIGHT", 0, 0)
    sharedFilters.Dropdown:SetWidth(320)
    sharedFilters.Dropdown:OverrideText("Choose Class / Specialization")
    function sharedFilters:Refresh()
        local bar = SelectedBar()
        self:SetShown(bar ~= nil)
        if not bar then return end
        bar.EntrySettings = bar.EntrySettings or {}
        if type(bar.EntrySettings.SpecFilters) ~= "table"
            and type(bar.EntrySettings.ClassSpecFilters) ~= "table" then
            bar.EntrySettings.SpecFilters = BCDM:BuildSpecFilters(bar.EntrySettings.FilterClass)
        end
        SetupFilterMenu(self.Dropdown, bar.EntrySettings, panel)
        self.Dropdown:OverrideText("Choose Class / Specialization")
    end

    local itemData = CreateFrame("Frame", nil, panel)
    itemData:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    itemData:RegisterEvent("BAG_UPDATE_DELAYED")
    itemData:SetScript("OnEvent", function(_, event, itemID)
        if event == "ITEM_DATA_LOAD_RESULT" and entryDialog and entryDialog:IsShown() and entryDialog.Mode == "item"
            and entryDialog:ResolveSource() == itemID then
            entryDialog:SchedulePreview()
        end
        if itemData.PendingRefresh then return end
        itemData.PendingRefresh = true
        C_Timer.After(0, function()
            itemData.PendingRefresh = nil
            if panel:IsShown() then panel:Refresh() end
        end)
    end)
end

function BCDM:AddCustomTrackerSettings(panel, controls)
    customTrackerPanel = panel
    CreateManagement(panel, controls)
    CreateEntries(panel, controls)
    self:AddVisibilityPolicySettings(panel, controls, "Selected Bar Visibility", SelectedBar,
        { "Visibility" }, { "UseSharedVisibility" }, function() self:RefreshCustomTrackers() end)
    AddLayoutControls(panel, controls)
    AddIconSettings(panel, controls)
    AddTextSettings(panel, controls)
    panel.RefreshSettingsHighlight = RefreshSelectedBarHighlight
    panel:HookScript("OnShow", function()
        RefreshSelectedBarHighlight()
    end)
    panel:HookScript("OnHide", function()
        SetCustomTrackerSettingsPreview(nil)
        BCDM:HideSettingsHighlight("CustomTrackerOverlay")
        if entryDialog and entryDialog.Panel == panel then entryDialog:Hide() end
    end)
end
