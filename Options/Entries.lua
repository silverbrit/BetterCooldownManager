local _, BCDM = ...

local U = BCDM.SettingsUtils
local Canvas = U.Canvas
local selectedBarID

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

local function Changed(panel)
    BCDM:RefreshCustomTrackers()
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
    local anchors = BCDM.AnchorParents.CustomTrackers
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
        panel:Refresh()
    end, BarValues, { forceSingleColumn = true, minWidth = 360 })

    local nameRow = Canvas.CreateBaseRow(section.Content, 34)
    U.Add(controls, section, nameRow)
    local nameInput = Canvas.CreateInput(nameRow)
    nameInput:SetPoint("LEFT", 0, 0)
    nameInput:SetWidth(300)
    local rename = Canvas.CreateActionButton(nameRow, "Rename")
    rename:SetPoint("LEFT", nameInput, "RIGHT", 8, 0)
    rename:SetWidth(100)
    rename:SetScript("OnClick", function()
        if selectedBarID and BCDM:RenameCustomTrackerBar(selectedBarID, nameInput:GetText()) then
            nameInput:SetText("")
            Changed(panel)
        end
    end)
    nameInput:SetScript("OnEnterPressed", function(self) rename:Click() self:ClearFocus() end)

    U.Buttons(controls, section, {
        { text = "Add Bar", width = 110, click = function()
            selectedBarID = BCDM:AddCustomTrackerBar()
            Changed(panel)
        end },
        { text = "Duplicate", width = 110, click = function()
            if selectedBarID then selectedBarID = BCDM:DuplicateCustomTrackerBar(selectedBarID) Changed(panel) end
        end },
        { text = "Move Up", width = 100, click = function()
            if selectedBarID then BCDM:MoveCustomTrackerBar(selectedBarID, -1) Changed(panel) end
        end },
        { text = "Move Down", width = 110, click = function()
            if selectedBarID then BCDM:MoveCustomTrackerBar(selectedBarID, 1) Changed(panel) end
        end },
        { text = "Delete", width = 100, click = function()
            if not selectedBarID then return end
            local deleting = selectedBarID
            BCDM:CreatePrompt("Delete Tracker Bar", "Delete this tracker bar and all of its entries?", function()
                BCDM:DeleteCustomTrackerBar(deleting)
                selectedBarID = nil
                Changed(panel)
            end)
        end },
    })
end

local function AddLayoutControls(panel, controls)
    local section = U.Section(controls, "Selected Bar Layout", true)
    local function Disabled() return SelectedBar() == nil end
    local getEnabled, setEnabled = AccessBar("Enabled", panel, false)
    U.Checkbox(controls, section, "Enable Bar", getEnabled, setEnabled, { disabled = Disabled })
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
    get, set = AccessBar("IconSize", panel, 38)
    U.Slider(controls, section, "Icon Size", get, set, { min = 16, max = 128, step = 1, disabled = Disabled })
    get, set = AccessBar("FrameStrata", panel, "LOW")
    U.Dropdown(controls, section, "Frame Strata", get, set, function() return STRATA end, { disabled = Disabled })
end

local function ResolveSpellID(value)
    local numeric = tonumber(value)
    local info = C_Spell.GetSpellInfo(numeric or value)
    return info and info.spellID
end

local function EntryName(entry)
    local source = entry.Source or {}
    local adapter = BCDM.CustomTrackerSourceAdapters and BCDM.CustomTrackerSourceAdapters[source.Type]
    local name, icon = adapter and adapter.GetMetadata and adapter.GetMetadata(source)
    return name or (source.Type .. " " .. tostring(source.ID)), icon
end

local function CreateEntries(panel, controls)
    local section = U.Section(controls, "Selected Bar Entries", true)
    local addRow = Canvas.CreateBaseRow(section.Content, 38)
    U.Add(controls, section, addRow)
    local spellInput = Canvas.CreateInput(addRow)
    spellInput:SetPoint("LEFT", 0, 0)
    spellInput:SetWidth(210)
    local addSpell = Canvas.CreateActionButton(addRow, "Add Spell")
    addSpell:SetPoint("LEFT", spellInput, "RIGHT", 8, 0)
    addSpell:SetWidth(100)
    local itemInput = Canvas.CreateInput(addRow)
    itemInput:SetPoint("LEFT", addSpell, "RIGHT", 18, 0)
    itemInput:SetWidth(170)
    local addItem = Canvas.CreateActionButton(addRow, "Add Item")
    addItem:SetPoint("LEFT", itemInput, "RIGHT", 8, 0)
    addItem:SetWidth(100)

    addSpell:SetScript("OnClick", function()
        local spellID = ResolveSpellID(spellInput:GetText())
        if selectedBarID and spellID then
            local class = select(2, UnitClass("player"))
            BCDM:AddCustomTrackerEntry(selectedBarID, "spell", spellID, {
                ClassSpecFilters = BCDM:BuildClassSpecFilters(class), FilterClass = class,
            })
            spellInput:SetText("")
            Changed(panel)
        end
    end)
    spellInput:SetScript("OnEnterPressed", function(self) addSpell:Click() self:ClearFocus() end)
    addItem:SetScript("OnClick", function()
        local itemID = tonumber(itemInput:GetText())
        if selectedBarID and itemID then
            BCDM:AddCustomTrackerEntry(selectedBarID, "item", itemID, { ClassSpecFilters = BCDM:BuildClassSpecFilters() })
            itemInput:SetText("")
            Changed(panel)
        end
    end)
    itemInput:SetScript("OnEnterPressed", function(self) addItem:Click() self:ClearFocus() end)

    local rows = {}
    local function EnsureRow(index)
        if rows[index] then return rows[index] end
        local row = CreateFrame("Frame", nil, section.Content)
        row:SetHeight(28)
        row.Check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.Check:SetSize(24, 24)
        row.Check:SetPoint("LEFT", 0, 0)
        row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.Label:SetPoint("LEFT", row.Check, "RIGHT", 4, 0)
        row.Label:SetJustifyH("LEFT")
        row.Label:SetWordWrap(false)
        row.Remove = Canvas.CreateActionButton(row, "Remove")
        row.Remove:SetSize(76, 24)
        row.Remove:SetPoint("RIGHT", 0, 0)
        row.Down = Canvas.CreateActionButton(row, "Down")
        row.Down:SetSize(54, 24)
        row.Down:SetPoint("RIGHT", row.Remove, "LEFT", -6, 0)
        row.Up = Canvas.CreateActionButton(row, "Up")
        row.Up:SetSize(54, 24)
        row.Up:SetPoint("RIGHT", row.Down, "LEFT", -6, 0)
        row.Label:SetPoint("RIGHT", row.Up, "LEFT", -10, 0)
        rows[index] = row
        return row
    end

    local list = Canvas.CreateBaseRow(section.Content, 28)
    U.Add(controls, section, list)
    function list:Refresh()
        local bar = SelectedBar()
        local order = bar and bar.EntryOrder or {}
        local previous
        for index, entryID in ipairs(order) do
            local entry = bar.Entries[entryID]
            local row = EnsureRow(index)
            row:SetParent(self)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", previous or self, previous and "BOTTOMLEFT" or "TOPLEFT", 0, previous and -6 or 0)
            row:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            previous = row
            local name, icon = EntryName(entry)
            row.Label:SetText(string.format("|T%s:16:16|t %s", tostring(icon), name))
            row.Check:SetChecked(entry.Enabled ~= false)
            row.Check:SetScript("OnClick", function(button) entry.Enabled = button:GetChecked() == true Changed(panel) end)
            row.Up:SetScript("OnClick", function() BCDM:MoveCustomTrackerEntry(selectedBarID, entryID, -1) Changed(panel) end)
            row.Down:SetScript("OnClick", function() BCDM:MoveCustomTrackerEntry(selectedBarID, entryID, 1) Changed(panel) end)
            row.Remove:SetScript("OnClick", function() BCDM:DeleteCustomTrackerEntry(selectedBarID, entryID) Changed(panel) end)
            row:Show()
        end
        for index = #order + 1, #rows do rows[index]:Hide() end
        self:SetHeight(math.max(28, #order * 34))
    end
end

function BCDM:AddCustomTrackerSettings(panel, controls)
    CreateManagement(panel, controls)
    AddLayoutControls(panel, controls)
    self:AddVisibilityPolicySettings(panel, controls, "Selected Bar Visibility", SelectedBar,
        { "Visibility" }, { "UseSharedVisibility" }, function() self:RefreshCustomTrackers() end)
    CreateEntries(panel, controls)
end
