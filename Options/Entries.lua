local _, BCDM = ...

local U = BCDM.SettingsUtils
local Canvas = U.Canvas
local state = {}

local function SpellInfo(spellID)
    local info = C_Spell.GetSpellInfo(spellID)
    if not info then return "Spell " .. tostring(spellID), 134400 end
    return info.name or ("Spell " .. tostring(spellID)), info.iconID or 134400
end

local function ItemInfo(itemID)
    local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    return name or ("Item " .. tostring(itemID)), icon or 134400
end

local function ResolveSpellID(input)
    if not input or input == "" then return nil end
    local info = C_Spell.GetSpellInfo(tonumber(input) or input)
    return info and info.spellID or nil
end

local function ClassSpecOptions()
    local options = {}
    for _, classEntry in ipairs(BCDM:GetClassSpecCatalog()) do
        for _, specEntry in ipairs(classEntry.specs or {}) do
            options[#options + 1] = {
                text = string.format("%s - %s", classEntry.className or classEntry.classToken,
                    specEntry.specName or specEntry.specToken),
                value = classEntry.classToken .. ":" .. specEntry.specToken,
            }
        end
    end
    return options
end

local function ParseClassSpec(value)
    if type(value) ~= "string" then return nil end
    return value:match("^([^:]+):(.+)$")
end

local function InitialClassSpec(viewerType)
    if state[viewerType] and state[viewerType].classSpec then return state[viewerType].classSpec end
    local playerClass = select(2, UnitClass("player"))
    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then specID, specName = GetSpecializationInfo(specIndex) end
    local specToken = BCDM:NormalizeSpecToken(specName, specID, specIndex)
    local candidate = playerClass and specToken and (playerClass .. ":" .. specToken) or nil
    for _, option in ipairs(ClassSpecOptions()) do
        if option.value == candidate then return candidate end
    end
    local options = ClassSpecOptions()
    return options[1] and options[1].value or nil
end

local function RecommendedOptions(viewerType, classToken, specToken)
    local fetchOptions
    if viewerType == "Custom" or viewerType == "AdditionalCustom" then
        fetchOptions = { includeSpells = true, classToken = classToken, specToken = specToken }
    elseif viewerType == "Item" then
        fetchOptions = { includeItems = true }
    else
        fetchOptions = { includeSpells = true, includeItems = true }
    end
    local options = {}
    for _, entry in ipairs(BCDM:FetchData(fetchOptions) or {}) do
        local name, icon
        if entry.entryType == "spell" then name, icon = SpellInfo(entry.id)
        else name, icon = ItemInfo(entry.id) end
        options[#options + 1] = {
            text = string.format("|T%s:16:16|t %s [%d]", tostring(icon), name, entry.id),
            value = entry.entryType .. ":" .. entry.id,
        }
    end
    return options
end

local function ParseRecommended(value)
    if not value then return nil end
    local entryType, id = value:match("^(%a+):(%d+)$")
    return entryType, tonumber(id)
end

local function CurrentEntries(viewerType, classToken, specToken)
    local source
    if viewerType == "Custom" or viewerType == "AdditionalCustom" then
        local spells = BCDM.db.profile.CooldownManager[viewerType].Spells
        source = spells[classToken] and spells[classToken][specToken] or {}
    elseif viewerType == "Item" then
        source = BCDM.db.profile.CooldownManager.Item.Items
    else
        source = BCDM.db.profile.CooldownManager.ItemSpell.ItemsSpells
    end
    local entries = {}
    for id, data in pairs(source or {}) do entries[#entries + 1] = { id = id, data = data } end
    table.sort(entries, function(a, b)
        local ai, bi = a.data.layoutIndex or math.huge, b.data.layoutIndex or math.huge
        if ai == bi then return tonumber(a.id) < tonumber(b.id) end
        return ai < bi
    end)
    return entries
end

local function ShowEntryTooltip(entry, owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    if entry.data.entryType == "item" then GameTooltip:SetItemByID(entry.id)
    elseif entry.data.entryType == "spell" then GameTooltip:SetSpellByID(entry.id)
    elseif C_Item.GetItemInfo(entry.id) then GameTooltip:SetItemByID(entry.id)
    else GameTooltip:SetSpellByID(entry.id) end
    GameTooltip:Show()
end

local function NormalizeClassSpecValue(value)
    if type(value) ~= "string" then return nil end
    local classToken, specToken = value:upper():match("^(%u+):([%u%d_]+)$")
    if not classToken or not specToken then return nil end
    return classToken .. ":" .. (BCDM:NormalizeSpecToken(specToken) or specToken)
end

local function ResolveFilterClass(entry)
    if entry.data.entryType ~= "spell" then return nil end
    if entry.data.filterClass then return tostring(entry.data.filterClass):upper() end

    local discoveredClass
    for value, enabled in pairs(entry.data.classSpecFilters or {}) do
        if enabled then
            local normalized = NormalizeClassSpecValue(value)
            local classToken = normalized and normalized:match("^([^:]+):")
            if classToken then
                if discoveredClass and discoveredClass ~= classToken then return nil end
                discoveredClass = classToken
            end
        end
    end
    return discoveredClass or select(2, UnitClass("player"))
end

local function SetupFilterMenu(button, entry, onChanged)
    if type(button.SetupMenu) ~= "function" then return end
    button:SetupMenu(function(_, root)
        root:SetScrollMode(420)
        local filterClass = ResolveFilterClass(entry)
        local catalog = BCDM:GetClassSpecCatalog(filterClass)
        local validValues = {}
        for _, classEntry in ipairs(catalog) do
            for _, specEntry in ipairs(classEntry.specs or {}) do
                validValues[classEntry.classToken .. ":" .. specEntry.specToken] = true
            end
        end

        local effectiveFilters = {}
        if type(entry.data.classSpecFilters) == "table" then
            for value, enabled in pairs(entry.data.classSpecFilters) do
                local normalized = enabled and NormalizeClassSpecValue(value) or nil
                if normalized and validValues[normalized] then effectiveFilters[normalized] = true end
            end
        else
            -- A missing filter table is the legacy "Always" state. Present it as all valid
            -- specializations selected so the first edit narrows that existing behavior.
            for value, enabled in pairs(BCDM:BuildClassSpecFilters(filterClass) or {}) do
                local normalized = enabled and NormalizeClassSpecValue(value) or nil
                if normalized and validValues[normalized] then effectiveFilters[normalized] = true end
            end
        end

        for _, classEntry in ipairs(catalog) do
            local submenu = root:CreateButton(classEntry.className or classEntry.classToken)
            for _, specEntry in ipairs(classEntry.specs or {}) do
                local value = classEntry.classToken .. ":" .. specEntry.specToken
                submenu:CreateCheckbox(specEntry.specName or specEntry.specToken, function()
                    return effectiveFilters[value] == true
                end, function()
                    effectiveFilters[value] = not effectiveFilters[value] or nil
                    -- Keep an explicitly empty table distinct from a never-configured entry.
                    entry.data.classSpecFilters = {}
                    for filterValue, enabled in pairs(effectiveFilters) do
                        if enabled then entry.data.classSpecFilters[filterValue] = true end
                    end
                    entry.data.filterClass = entry.data.entryType == "spell" and filterClass or nil
                    onChanged()
                end)
            end
        end
    end)
end

function BCDM:AddViewerEntrySettings(panel, controls, viewerType)
    if viewerType ~= "Custom" and viewerType ~= "AdditionalCustom"
        and viewerType ~= "Item" and viewerType ~= "ItemSpell" then return end

    state[viewerType] = state[viewerType] or {}
    local section = U.Section(controls,
        viewerType == "Item" and "Custom Items" or viewerType == "ItemSpell" and "Items & Spells" or "Custom Spells", true)
    local editor = Canvas.CreateBaseRow(section.Content, 120)
    U.Add(controls, section, editor)

    local classSpecDropdown
    if viewerType == "Custom" or viewerType == "AdditionalCustom" then
        local classSpecLabel = Canvas.CreateLabel(editor, "Editing spell list for", "GameFontHighlight")
        classSpecLabel:SetPoint("TOPLEFT", 0, 0)
        classSpecDropdown = Canvas.CreateDropdown(editor)
        classSpecDropdown:SetPoint("TOPLEFT", classSpecLabel, "BOTTOMLEFT", 0, -6)
        classSpecDropdown:SetWidth(300)
        Canvas.AttachDropdownMenu(classSpecDropdown, ClassSpecOptions, function()
            return state[viewerType].classSpec or InitialClassSpec(viewerType)
        end, function(value)
            state[viewerType].classSpec = value
            panel:Refresh()
        end, "Select class and specialization...", { maxHeight = 420, forceSingleColumn = true, minWidth = 300 })
    end

    local firstInput = Canvas.CreateInput(editor)
    firstInput:SetWidth(viewerType == "ItemSpell" and 190 or 260)
    firstInput:SetPoint("TOPLEFT", classSpecDropdown or editor, classSpecDropdown and "BOTTOMLEFT" or "TOPLEFT", 6, classSpecDropdown and -12 or 0)

    local firstAdd = Canvas.CreateActionButton(editor, viewerType == "Item" and "Add Item" or "Add Spell")
    firstAdd:SetWidth(100)
    firstAdd:SetPoint("LEFT", firstInput, "RIGHT", 8, 0)

    local secondInput, secondAdd
    if viewerType == "ItemSpell" then
        secondInput = Canvas.CreateInput(editor)
        secondInput:SetWidth(190)
        secondInput:SetPoint("LEFT", firstAdd, "RIGHT", 18, 0)
        secondAdd = Canvas.CreateActionButton(editor, "Add Item")
        secondAdd:SetWidth(100)
        secondAdd:SetPoint("LEFT", secondInput, "RIGHT", 8, 0)
    end

    local recommended = Canvas.CreateDropdown(editor)
    recommended:SetPoint("TOPLEFT", firstInput, "BOTTOMLEFT", -6, -10)
    recommended:SetPoint("RIGHT", editor, "RIGHT", 0, 0)

    local racialButtons
    if viewerType == "Custom" or viewerType == "AdditionalCustom" then
        racialButtons = Canvas.CreateButtonRow(editor, {
            { text = "Add Racials", width = 130, click = function()
                BCDM:AddRacials(viewerType) BCDM:UpdateCooldownViewer(viewerType) panel:Refresh()
            end },
            { text = "Remove Racials", width = 140, click = function()
                BCDM:RemoveRacials(viewerType) BCDM:UpdateCooldownViewer(viewerType) panel:Refresh()
            end },
        })
        racialButtons:SetPoint("TOPLEFT", recommended, "BOTTOMLEFT", 0, -10)
        racialButtons:SetPoint("RIGHT", editor, "RIGHT", 0, 0)
    end

    local entryRows = {}
    local function AddEntry(entryType, id)
        local classToken, specToken = ParseClassSpec(state[viewerType].classSpec or InitialClassSpec(viewerType))
        if viewerType == "Custom" or viewerType == "AdditionalCustom" then
            if entryType == "spell" and id then BCDM:AdjustSpellList(id, "add", viewerType, classToken, specToken) end
        elseif viewerType == "Item" then
            if entryType == "item" and id then BCDM:AdjustItemList(id, "add") end
        elseif id then
            BCDM:AdjustItemsSpellsList(id, "add", entryType)
        end
        BCDM:UpdateCooldownViewer(viewerType)
        panel:Refresh()
    end
    firstAdd:SetScript("OnClick", function()
        local id = viewerType == "Item" and tonumber(firstInput:GetText()) or ResolveSpellID(firstInput:GetText())
        AddEntry(viewerType == "Item" and "item" or "spell", id)
        if id then firstInput:SetText("") end
    end)
    firstInput:SetScript("OnEnterPressed", function(self) firstAdd:Click() self:ClearFocus() end)
    if secondAdd then
        secondAdd:SetScript("OnClick", function()
            local id = tonumber(secondInput:GetText())
            AddEntry("item", id)
            if id then secondInput:SetText("") end
        end)
        secondInput:SetScript("OnEnterPressed", function(self) secondAdd:Click() self:ClearFocus() end)
    end

    Canvas.AttachDropdownMenu(recommended, function()
        local classToken, specToken = ParseClassSpec(state[viewerType].classSpec or InitialClassSpec(viewerType))
        return RecommendedOptions(viewerType, classToken, specToken)
    end, function() return nil end, function(value)
        local entryType, id = ParseRecommended(value)
        AddEntry(entryType, id)
    end, "Add from recommended list...", { maxHeight = 420, forceSingleColumn = true, minWidth = 420 })

    local function EnsureEntryRow(index)
        if entryRows[index] then return entryRows[index] end
        local row = CreateFrame("Frame", nil, editor)
        row:SetHeight(28)
        row.Check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.Check:SetSize(24, 24)
        row.Check:SetPoint("LEFT", 0, 0)
        row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.Label:SetPoint("LEFT", row.Check, "RIGHT", 4, 0)
        row.Label:SetJustifyH("LEFT")
        row.Label:SetWordWrap(false)
        row.Label:SetMaxLines(1)
        row.Up = Canvas.CreateActionButton(row, "Up")
        row.Up:SetSize(54, 24)
        row.Down = Canvas.CreateActionButton(row, "Down")
        row.Down:SetSize(54, 24)
        row.Remove = Canvas.CreateActionButton(row, "Remove")
        row.Remove:SetSize(76, 24)
        row.Filters = Canvas.CreateDropdown(row)
        row.Filters:SetSize(120, 24)
        row.Remove:SetPoint("RIGHT", 0, 0)
        row.Down:SetPoint("RIGHT", row.Remove, "LEFT", -6, 0)
        row.Up:SetPoint("RIGHT", row.Down, "LEFT", -6, 0)
        row.Filters:SetPoint("RIGHT", row.Up, "LEFT", -6, 0)
        entryRows[index] = row
        return row
    end

    function editor:Refresh()
        local classSpec = state[viewerType].classSpec or InitialClassSpec(viewerType)
        state[viewerType].classSpec = classSpec
        if classSpecDropdown then Canvas.RefreshDropdownState(classSpecDropdown, false) end
        Canvas.RefreshDropdownState(recommended, false)
        local classToken, specToken = ParseClassSpec(classSpec)
        local entries = CurrentEntries(viewerType, classToken, specToken)
        local previousRow
        for index, entry in ipairs(entries) do
            local row = EnsureEntryRow(index)
            row:ClearAllPoints()
            if previousRow then
                row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -6)
            else
                row:SetPoint("TOPLEFT", racialButtons or recommended, "BOTTOMLEFT", 0, -10)
            end
            row:SetPoint("RIGHT", editor, "RIGHT", 0, 0)
            previousRow = row
            local entryType = entry.data.entryType
            local name, icon
            if entryType == "item" or (not entryType and viewerType == "Item") then name, icon = ItemInfo(entry.id)
            else name, icon = SpellInfo(entry.id) end
            row.Label:SetText(string.format("[%s] |T%s:16:16|t %s", entry.data.layoutIndex or "?", tostring(icon), name))
            row.Check:SetChecked(entry.data.isActive ~= false)
            row.Check:SetScript("OnClick", function(self)
                entry.data.isActive = self:GetChecked() == true
                BCDM:UpdateCooldownViewer(viewerType)
            end)
            row.Up:SetScript("OnClick", function()
                if viewerType == "Custom" or viewerType == "AdditionalCustom" then
                    BCDM:AdjustSpellLayoutIndex(-1, entry.id, viewerType, classToken, specToken)
                elseif viewerType == "Item" then BCDM:AdjustItemLayoutIndex(-1, entry.id)
                else BCDM:AdjustItemsSpellsLayoutIndex(-1, entry.id) end
                panel:Refresh()
            end)
            row.Down:SetScript("OnClick", function()
                if viewerType == "Custom" or viewerType == "AdditionalCustom" then
                    BCDM:AdjustSpellLayoutIndex(1, entry.id, viewerType, classToken, specToken)
                elseif viewerType == "Item" then BCDM:AdjustItemLayoutIndex(1, entry.id)
                else BCDM:AdjustItemsSpellsLayoutIndex(1, entry.id) end
                panel:Refresh()
            end)
            row.Remove:SetScript("OnClick", function()
                if viewerType == "Custom" or viewerType == "AdditionalCustom" then
                    BCDM:AdjustSpellList(entry.id, "remove", viewerType, classToken, specToken)
                elseif viewerType == "Item" then BCDM:AdjustItemList(entry.id, "remove")
                else BCDM:AdjustItemsSpellsList(entry.id, "remove") end
                BCDM:UpdateCooldownViewer(viewerType)
                panel:Refresh()
            end)
            row:SetScript("OnEnter", function(self) ShowEntryTooltip(entry, self) end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if viewerType == "Item" or viewerType == "ItemSpell" then
                row.Filters:Show()
                row.Filters:OverrideText("Load Conditions")
                SetupFilterMenu(row.Filters, entry, function() BCDM:UpdateCooldownViewer(viewerType) end)
            else row.Filters:Hide() end
            row.Label:ClearAllPoints()
            row.Label:SetPoint("LEFT", row.Check, "RIGHT", 4, 0)
            row.Label:SetPoint("RIGHT", (viewerType == "Item" or viewerType == "ItemSpell") and row.Filters or row.Up, "LEFT", -10, 0)
            row:Show()
        end
        for index = #entries + 1, #entryRows do entryRows[index]:Hide() end
        local controlsHeight = racialButtons and 160 or 62
        local entriesHeight = #entries > 0 and (10 + (#entries * 28) + ((#entries - 1) * 6)) or 0
        self:SetHeight(math.max(120, controlsHeight + entriesHeight + 4))
    end
end
