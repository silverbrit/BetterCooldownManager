local _, BCDM = ...

local U = BCDM.SettingsUtils
local Canvas = U.Canvas
local UNKNOWN_ICON = 134400
local selectedSlot = 13

local DISPLAY_MODES = U.DISPLAY_MODES
local VISUAL_MODES = U.VISUAL_MODES
local GLOW_MODES = U.GLOW_MODES

local function Settings()
    return BCDM.db.profile.CooldownManager.Trinket
end

local function Slot()
    return BCDM:GetTrinketSlotRecord(Settings(), selectedSlot)
end

local function ResolvedSettings()
    return BCDM:GetTrinketSlotSettings(Settings(), selectedSlot)
end

local function Changed(panel, callback)
    callback()
    panel:Refresh()
end

local function SetupFilterMenu(button, target, panel, callback)
    if type(button.SetupMenu) ~= "function" then return end
    button:SetupMenu(function(_, root)
        root:SetScrollMode(420)
        for _, classEntry in ipairs(BCDM:GetClassSpecCatalog(target.FilterClass)) do
            local submenu = root:CreateButton(classEntry.className or classEntry.classToken)
            for _, specEntry in ipairs(classEntry.specs or {}) do
                local value = specEntry.specID
                submenu:CreateCheckbox(specEntry.specName or tostring(value), function()
                    return target.SpecFilters and target.SpecFilters[value] == true
                end, function()
                    target.SpecFilters = target.SpecFilters or {}
                    target.SpecFilters[value] = not target.SpecFilters[value] or nil
                    Changed(panel, callback)
                end)
            end
        end
    end)
end

local function CopyFilters(target, source)
    target.FilterClass = source.FilterClass
    target.SpecFilters = nil
    if type(source.SpecFilters) == "table" then
        target.SpecFilters = {}
        for specID, enabled in pairs(source.SpecFilters) do
            if enabled == true then target.SpecFilters[specID] = true end
        end
    end
    target.ClassSpecFilters = nil
    if type(source.ClassSpecFilters) == "table" then
        target.ClassSpecFilters = {}
        for key, enabled in pairs(source.ClassSpecFilters) do
            if enabled == true then target.ClassSpecFilters[key] = true end
        end
    end
end

local function ItemMetadata(slotID)
    local itemID = GetInventoryItemID("player", slotID)
    if not itemID or BCDM:IsSecretValue(itemID) then return "Empty Trinket Slot", UNKNOWN_ICON end
    local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return name or ("Item " .. tostring(itemID)), icon or GetInventoryItemTexture("player", slotID) or UNKNOWN_ICON, itemID
end

function BCDM:AddTrinketEntrySettings(panel, controls, behavior, callback)
    U.Text(controls, behavior, "Select an equipped trinket to edit its slot settings.")
    local strip = Canvas.CreateBaseRow(behavior.Content, 56)
    U.Add(controls, behavior, strip)
    strip.Buttons = {}
    strip.Marker = strip:CreateTexture(nil, "OVERLAY")
    strip.Marker:SetColorTexture(1, 0.82, 0, 1)
    strip.Marker:SetSize(3, U.SELECTOR_ICON_SIZE + 6)
    strip.Marker:Hide()
    local function UpdateDragging()
        if not strip.DragSlot then return end
        local first, second = strip.Buttons[1], strip.Buttons[2]
        local firstCenter, secondCenter = first and first:GetCenter(), second and second:GetCenter()
        if not firstCenter or not secondCenter then return end
        local cursorX = GetCursorPosition() / strip:GetEffectiveScale()
        strip.DragTarget = cursorX < ((firstCenter + secondCenter) * 0.5) and 1 or 2
        strip.Marker:ClearAllPoints()
        if strip.DragTarget == 1 then strip.Marker:SetPoint("RIGHT", first, "LEFT", -3, 0)
        else strip.Marker:SetPoint("LEFT", second, "RIGHT", 3, 0) end
        strip.Marker:Show()
    end
    local function StopDragging()
        if not strip.DragSlot then return end
        local slotID, target = strip.DragSlot, strip.DragTarget
        strip.DragSlot, strip.DragTarget = nil, nil
        strip:SetScript("OnUpdate", nil)
        strip.Marker:Hide()
        if target and BCDM:ReorderTrinketSlot(Settings(), slotID, target) then
            Changed(panel, callback)
        else
            panel:Refresh()
        end
    end
    for index, slotID in ipairs({ 13, 14 }) do
        local button = CreateFrame("Button", nil, strip, "BackdropTemplate")
        button:SetSize(U.SELECTOR_ICON_SIZE, U.SELECTOR_ICON_SIZE)
        button:SetPoint("LEFT", (index - 1) * (U.SELECTOR_ICON_SIZE + 6), 0)
        button:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetPoint("TOPLEFT", 2, -2)
        button.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
        button.SlotID = slotID
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnClick", function(self)
            selectedSlot = self.SlotID
            panel:Refresh()
        end)
        button:SetScript("OnEnter", function(self)
            local name, _, itemID = ItemMetadata(self.SlotID)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(name, 1, 0.82, 0)
            GameTooltip:AddLine("Trinket Slot " .. (self.SlotID == 13 and "1" or "2"), 1, 1, 1)
            if itemID then GameTooltip:AddLine("Item ID: " .. itemID, 0.7, 0.7, 0.7) end
            GameTooltip:AddLine("Click to edit. Drag to reorder.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnDragStart", function(self)
            selectedSlot = self.SlotID
            strip.DragSlot = self.SlotID
            strip.DragTarget = self == strip.Buttons[1] and 1 or 2
            strip:SetScript("OnUpdate", UpdateDragging)
            UpdateDragging()
        end)
        button:SetScript("OnDragStop", StopDragging)
        strip.Buttons[index] = button
    end
    function strip:Refresh()
        local order = BCDM:GetTrinketSlotOrder(Settings())
        for index, button in ipairs(self.Buttons) do
            button.SlotID = order[index]
            local _, icon = ItemMetadata(button.SlotID)
            local slot = BCDM:GetTrinketSlotRecord(Settings(), button.SlotID)
            local entrySettings = BCDM:GetTrinketSlotSettings(Settings(), button.SlotID)
            local visualMode = entrySettings.VisualMode or "FULL"
            U.SetSettingsIcon(button.Icon, icon)
            if button.Icon.SetDesaturation then
                button.Icon:SetDesaturation((slot.Enabled == false or visualMode == "DESATURATE") and 1 or 0)
            end
            button.Icon:SetAlpha(slot.Enabled == false and 0.45
                or visualMode == "LOW_ALPHA" and (tonumber(entrySettings.Alpha) or 0.45) or 1)
            if slot.Enabled ~= false and entrySettings.Glow and entrySettings.Glow ~= "NONE" then
                BCDM:StartCustomGlow(button)
            else
                BCDM:StopCustomGlow(button)
            end
            button:SetBackdropBorderColor(button.SlotID == selectedSlot and 1 or 0.2,
                button.SlotID == selectedSlot and 0.82 or 0.2, button.SlotID == selectedSlot and 0 or 0.2, 1)
        end
    end
    strip:HookScript("OnHide", function()
        strip.DragSlot, strip.DragTarget = nil, nil
        strip:SetScript("OnUpdate", nil)
        strip.Marker:Hide()
        for _, button in ipairs(strip.Buttons) do BCDM:StopCustomGlow(button) end
    end)

    U.Subsection(controls, behavior, "Selected Trinket Settings")
    local header = Canvas.CreateBaseRow(behavior.Content, 58)
    U.Add(controls, behavior, header)
    header.Icon = header:CreateTexture(nil, "ARTWORK")
    header.Icon:SetSize(U.SELECTED_ICON_SIZE, U.SELECTED_ICON_SIZE)
    header.Icon:SetPoint("LEFT", 0, 0)
    header.Name = Canvas.CreateLabel(header, "", "GameFontNormalLarge")
    header.Name:SetPoint("TOPLEFT", header.Icon, "TOPRIGHT", 12, -4)
    header.Name:SetPoint("RIGHT", header, "RIGHT", -150, 0)
    header.Name:SetWordWrap(false)
    header.Source = Canvas.CreateLabel(header, "", "GameFontHighlightSmall")
    header.Source:SetPoint("TOPLEFT", header.Name, "BOTTOMLEFT", 0, -6)
    header.Source:SetTextColor(0.65, 0.65, 0.65)
    header.Enabled = CreateFrame("CheckButton", nil, header, "UICheckButtonTemplate")
    header.Enabled:SetSize(24, 24)
    header.Enabled:SetPoint("RIGHT", 0, 0)
    header.EnabledLabel = Canvas.CreateLabel(header, "Enabled", "GameFontHighlight")
    header.EnabledLabel:SetPoint("RIGHT", header.Enabled, "LEFT", -2, 0)
    header.Enabled:SetScript("OnClick", function(self)
        Slot().Enabled = self:GetChecked() == true
        Changed(panel, callback)
    end)
    function header:Refresh()
        local name, icon, itemID = ItemMetadata(selectedSlot)
        U.SetSettingsIcon(self.Icon, icon)
        self.Name:SetText(name)
        self.Source:SetText("Trinket Slot " .. (selectedSlot == 13 and "1" or "2")
            .. (itemID and ("  •  Item ID: " .. itemID) or ""))
        self.Enabled:SetChecked(Slot().Enabled ~= false)
    end

    U.Checkbox(controls, behavior, "Use Shared Settings", function()
        return Slot().OverrideBarSettings ~= true
    end, function(value)
        local slot = Slot()
        if value ~= true and slot.OverrideBarSettings ~= true then
            local shared = ResolvedSettings()
            slot.DisplayMode = shared.DisplayMode or "ALWAYS"
            slot.VisualMode = shared.VisualMode or "FULL"
            slot.Alpha = tonumber(shared.Alpha) or 0.45
            slot.Glow = shared.Glow or "NONE"
            slot.TextEnabled = shared.TextEnabled ~= false
            slot.Tooltip = shared.Tooltip ~= false
            CopyFilters(slot, shared)
        end
        slot.OverrideBarSettings = value ~= true
        Changed(panel, callback)
    end)

    local function UsingShared() return Slot().OverrideBarSettings ~= true end
    local function SlotField(field, fallback)
        return function()
            local value = ResolvedSettings()[field]
            return value == nil and fallback or value
        end, function(value)
            Slot()[field] = value
            Changed(panel, callback)
        end
    end
    local get, set = SlotField("DisplayMode", "ALWAYS")
    U.Dropdown(controls, behavior, "Display Mode", get, set, function() return DISPLAY_MODES end,
        { hidden = UsingShared })
    get, set = SlotField("VisualMode", "FULL")
    U.Dropdown(controls, behavior, "Appearance", get, set, function() return VISUAL_MODES end,
        { hidden = UsingShared })
    get, set = SlotField("Alpha", 0.45)
    U.Slider(controls, behavior, "Opacity", get, set, {
        min = 0.05, max = 1, step = 0.05,
        hidden = function() return UsingShared() or Slot().VisualMode ~= "LOW_ALPHA" end,
        formatter = function(value) return string.format("%.0f%%", (tonumber(value) or 0) * 100) end,
    })
    get, set = SlotField("Glow", "NONE")
    U.Dropdown(controls, behavior, "Glow", get, set, function() return GLOW_MODES end,
        { hidden = UsingShared })
    get, set = SlotField("TextEnabled", true)
    U.Checkbox(controls, behavior, "Show Text", get, set, { hidden = UsingShared })
    get, set = SlotField("Tooltip", true)
    U.Checkbox(controls, behavior, "Show Tooltip", get, set, { hidden = UsingShared })

    local filters = Canvas.CreateBaseRow(behavior.Content, 28)
    U.Add(controls, behavior, filters)
    filters.Label = Canvas.CreateLabel(filters, "Class / Specialization", "GameFontHighlight")
    filters.Label:SetPoint("LEFT", 0, 0)
    filters.Dropdown = Canvas.CreateDropdown(filters)
    filters.Dropdown:SetPoint("RIGHT", 0, 0)
    filters.Dropdown:SetWidth(320)
    filters.Dropdown:OverrideText("Choose Class / Specialization")
    function filters:Refresh()
        self:SetShown(not UsingShared())
        if UsingShared() then return end
        SetupFilterMenu(self.Dropdown, Slot(), panel, callback)
        self.Dropdown:OverrideText("Choose Class / Specialization")
    end

    local shared = U.Section(controls, "Shared Trinket Settings", true)
    U.Text(controls, shared, "Applied to both trinket slots unless a slot enables its own override.")
    local function SharedTarget()
        local settings = Settings()
        settings.EntrySettings = type(settings.EntrySettings) == "table" and settings.EntrySettings or {}
        if type(settings.EntrySettings.SpecFilters) ~= "table"
            and type(settings.EntrySettings.ClassSpecFilters) ~= "table" then
            settings.EntrySettings.SpecFilters = BCDM:BuildSpecFilters(settings.EntrySettings.FilterClass)
        end
        return settings.EntrySettings
    end
    local function SharedField(field, fallback)
        return function()
            local value = SharedTarget()[field]
            return value == nil and fallback or value
        end, function(value)
            SharedTarget()[field] = value
            Changed(panel, callback)
        end
    end
    get, set = SharedField("DisplayMode", "ALWAYS")
    U.Dropdown(controls, shared, "Display Mode", get, set, function() return DISPLAY_MODES end)
    get, set = SharedField("VisualMode", "FULL")
    U.Dropdown(controls, shared, "Appearance", get, set, function() return VISUAL_MODES end)
    get, set = SharedField("Alpha", 0.45)
    U.Slider(controls, shared, "Opacity", get, set, {
        min = 0.05, max = 1, step = 0.05,
        hidden = function() return SharedTarget().VisualMode ~= "LOW_ALPHA" end,
        formatter = function(value) return string.format("%.0f%%", (tonumber(value) or 0) * 100) end,
    })
    get, set = SharedField("Glow", "NONE")
    U.Dropdown(controls, shared, "Glow", get, set, function() return GLOW_MODES end)
    get, set = SharedField("TextEnabled", true)
    U.Checkbox(controls, shared, "Show Text", get, set)
    get, set = SharedField("Tooltip", true)
    U.Checkbox(controls, shared, "Show Tooltip", get, set)

    local sharedFilters = Canvas.CreateBaseRow(shared.Content, 28)
    U.Add(controls, shared, sharedFilters)
    sharedFilters.Label = Canvas.CreateLabel(sharedFilters, "Class / Specialization", "GameFontHighlight")
    sharedFilters.Label:SetPoint("LEFT", 0, 0)
    sharedFilters.Dropdown = Canvas.CreateDropdown(sharedFilters)
    sharedFilters.Dropdown:SetPoint("RIGHT", 0, 0)
    sharedFilters.Dropdown:SetWidth(320)
    sharedFilters.Dropdown:OverrideText("Choose Class / Specialization")
    function sharedFilters:Refresh()
        SetupFilterMenu(self.Dropdown, SharedTarget(), panel, callback)
        self.Dropdown:OverrideText("Choose Class / Specialization")
    end

    local itemData = CreateFrame("Frame", nil, panel)
    itemData:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    itemData:SetScript("OnEvent", function()
        if panel:IsShown() then panel:Refresh() end
    end)
end
