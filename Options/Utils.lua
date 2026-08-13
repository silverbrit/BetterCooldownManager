local _, BCDM = ...

local SettingsCanvas = LibStub("LibSharedCanvas-1.0")
local AceLocale = LibStub("AceLocale-3.0", true)
local LocaleTable = AceLocale and AceLocale:GetLocale("BetterCooldownManager", true) or nil

local M = {}
BCDM.SettingsUtils = M

M.SELECTOR_ICON_SIZE = 44
M.SELECTED_ICON_SIZE = 48
M.SETTINGS_ICON_CROP = 0.08
M.DISPLAY_MODES = {
    { text = "Always", value = "ALWAYS" }, { text = "Ready Only", value = "READY" },
    { text = "Active Only", value = "ACTIVE" },
}
M.VISUAL_MODES = {
    { text = "Full", value = "FULL" }, { text = "Desaturate", value = "DESATURATE" },
    { text = "Lower Alpha", value = "LOW_ALPHA" },
}
M.GLOW_MODES = {
    { text = "No Glow", value = "NONE" }, { text = "Glow Ready", value = "READY" },
    { text = "Glow Active", value = "ACTIVE" },
}

function M.SetSettingsIcon(texture, icon)
    if not texture then return end
    texture:SetTexture(icon or 134400)
    local crop = M.SETTINGS_ICON_CROP
    texture:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
end

local unpack = unpack

local function IsFontString(widget)
    return widget and type(widget.GetObjectType) == "function" and widget:GetObjectType() == "FontString"
end

local function GetDropdownButtonLabel(button)
    if type(button) ~= "table" or not IsFontString(button.fontString) then return nil end
    return button.fontString
end

local function CaptureLabelLayout(label)
    if not IsFontString(label) or label.bcdmMediaLayoutCaptured == true then return end
    label.bcdmMediaLayoutCaptured = true
    label.bcdmMediaAnchorPoints = {}
    for index = 1, label:GetNumPoints() do
        label.bcdmMediaAnchorPoints[index] = { label:GetPoint(index) }
    end
    if type(label.GetJustifyH) == "function" then
        label.bcdmMediaJustifyH = label:GetJustifyH()
    end
end

local function RestoreLabelLayout(label)
    if not IsFontString(label) or label.bcdmMediaLayoutCaptured ~= true then return end
    label:ClearAllPoints()
    for _, pointData in ipairs(label.bcdmMediaAnchorPoints or {}) do
        label:SetPoint(unpack(pointData))
    end
    if type(label.bcdmMediaJustifyH) == "string" and type(label.SetJustifyH) == "function" then
        label:SetJustifyH(label.bcdmMediaJustifyH)
    end
end

local function CaptureLabelFont(label)
    if not IsFontString(label) or label.bcdmMediaFontCaptured == true then return end
    label.bcdmMediaFontCaptured = true
    if type(label.GetFontObject) == "function" then
        label.bcdmMediaFontObject = label:GetFontObject()
    end
end

local function RestoreLabelFont(label)
    if not IsFontString(label) or label.bcdmMediaFontCaptured ~= true then return end
    if type(label.SetFontObject) == "function" and label.bcdmMediaFontObject then
        label:SetFontObject(label.bcdmMediaFontObject)
    end
end

local previewFontObjects = {}
local previewFontObjectCount = 0

local function GetPreviewFontObject(mediaPath, size, flags)
    if type(mediaPath) ~= "string" or mediaPath == "" then return nil end
    size = type(size) == "number" and size > 0 and size or 12
    flags = type(flags) == "string" and flags or ""
    local key = mediaPath .. "\031" .. tostring(size) .. "\031" .. flags
    if previewFontObjects[key] then return previewFontObjects[key] end

    previewFontObjectCount = previewFontObjectCount + 1
    local fontObject = CreateFont("BCDM_MenuPreviewFont_" .. previewFontObjectCount)
    if not fontObject or type(fontObject.SetFont) ~= "function"
        or fontObject:SetFont(mediaPath, size, flags) == false then
        return nil
    end
    previewFontObjects[key] = fontObject
    return fontObject
end

local function EnsurePreviewTexture(button)
    if type(button) ~= "table" then return nil end
    if button.bcdmMediaPreviewTexture then return button.bcdmMediaPreviewTexture end
    if type(button.AttachTexture) ~= "function" then return nil end
    button.bcdmMediaPreviewTexture = button:AttachTexture()
    return button.bcdmMediaPreviewTexture
end

function M.L(key)
    if not key then return key end
    return (LocaleTable and rawget(LocaleTable, key)) or key
end

function M.Values(map, order)
    local values = {}
    local seen = {}
    if type(order) == "table" then
        for _, key in ipairs(order) do
            if map[key] ~= nil then
                values[#values + 1] = { text = tostring(map[key]), value = key }
                seen[key] = true
            end
        end
    end
    local remainder = {}
    for key, label in pairs(map or {}) do
        if not seen[key] then
            remainder[#remainder + 1] = { text = tostring(label), value = key }
        end
    end
    table.sort(remainder, function(a, b) return a.text < b.text end)
    for _, value in ipairs(remainder) do values[#values + 1] = value end
    return values
end

function M.GetSharedMediaPath(mediaType, mediaName)
    if type(mediaType) ~= "string" or mediaType == ""
        or type(mediaName) ~= "string" or mediaName == "" then
        return nil
    end
    local LSM = BCDM.LSM
    if not LSM or type(LSM.IsValid) ~= "function" or type(LSM.Fetch) ~= "function"
        or LSM:IsValid(mediaType, mediaName) ~= true then
        return nil
    end
    return LSM:Fetch(mediaType, mediaName)
end

function M.ApplyMenuMediaPreview(button, mediaType, mediaName, mediaPath)
    local label = GetDropdownButtonLabel(button)
    if not label then return end

    CaptureLabelLayout(label)
    CaptureLabelFont(label)
    local texture = EnsurePreviewTexture(button)
    if texture and type(texture.Hide) == "function" then texture:Hide() end
    mediaPath = type(mediaPath) == "string" and mediaPath or M.GetSharedMediaPath(mediaType, mediaName)

    if mediaType == "font" then
        RestoreLabelLayout(label)
        if type(mediaPath) == "string" and mediaPath ~= "" and type(label.SetFontObject) == "function" then
            local _, currentSize, currentFlags = label:GetFont()
            local fontObject = GetPreviewFontObject(mediaPath, currentSize, currentFlags)
            if fontObject then label:SetFontObject(fontObject) else RestoreLabelFont(label) end
        else
            RestoreLabelFont(label)
        end
        return
    end

    RestoreLabelFont(label)
    if mediaType ~= "statusbar" or type(mediaPath) ~= "string" or mediaPath == "" or not texture then
        RestoreLabelLayout(label)
        return
    end

    if type(button.GetWidth) == "function" and type(button.SetWidth) == "function"
        and type(button:GetWidth()) == "number" and button:GetWidth() < 420 then
        button:SetWidth(420)
    end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", 24, -2)
    texture:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 24, 2)
    texture:SetWidth(150)
    texture:SetDrawLayer("BACKGROUND", 1)
    texture:SetTexture(mediaPath)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:Show()

    label:ClearAllPoints()
    label:SetPoint("LEFT", texture, "RIGHT", 10, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -12, 0)
    label:SetJustifyH("LEFT")
    label:SetText(mediaName)
end

function M.CreateMenuMediaPreviewInitializer(mediaType, mediaName)
    local mediaPath = M.GetSharedMediaPath(mediaType, mediaName)
    return function(button)
        M.ApplyMenuMediaPreview(button, mediaType, mediaName, mediaPath)
    end
end

function M.DecorateMediaDropdownValues(mediaType, values)
    local decorated = {}
    for _, entry in ipairs(type(values) == "table" and values or {}) do
        if type(entry) == "table" then
            local row = {}
            for key, value in pairs(entry) do row[key] = value end
            local mediaName = row.value or row.text
            if type(mediaName) == "string" and mediaName ~= "" then
                row.initializer = M.CreateMenuMediaPreviewInitializer(mediaType, mediaName)
            end
            decorated[#decorated + 1] = row
        end
    end
    return decorated
end

function M.MediaValues(mediaType)
    return function()
        local values = {}
        local mediaList = BCDM.LSM and BCDM.LSM:List(mediaType)
        for _, mediaName in ipairs(type(mediaList) == "table" and mediaList or {}) do
            values[#values + 1] = { text = mediaName, value = mediaName }
        end
        return M.DecorateMediaDropdownValues(mediaType, values)
    end
end

function M.SupportsSharedMediaPreviews()
    local LSM = BCDM.LSM
    return LSM and type(LSM.IsValid) == "function" and type(LSM.Fetch) == "function"
end

function M.NewPanel(config)
    config = type(config) == "table" and config or {}
    if config.scrollTopInset == nil then config.scrollTopInset = 0 end
    if config.topInset == nil then config.topInset = -1 end
    local panel, controls = SettingsCanvas.CreatePanel(config)
    controls.panel = panel
    panel.Refresh = function(self) SettingsCanvas.RefreshPanel(self) end
    panel.OnRefresh = panel.Refresh
    panel.OnCommit = function() end
    panel:SetScript("OnShow", panel.Refresh)
    controls.scrollFrame:SetScript("OnSizeChanged", panel.Refresh)
    return panel, controls
end

function M.Section(controls, title, expanded)
    local section = SettingsCanvas.CreateSection(controls.scrollChild, M.L(title), 0, expanded ~= false)
    controls:RegisterSection(section)
    return section
end

function M.Add(controls, section, row)
    SettingsCanvas.AddSectionRow(controls, section, row)
    return row
end

function M.Text(controls, section, text, options)
    local row = SettingsCanvas.CreateTextRow(section.Content, M.L(text))
    if options and type(options.hidden) == "function" then
        local refresh = row.Refresh
        function row:Refresh()
            if refresh then refresh(self) end
            self:SetShown(not options.hidden())
        end
    end
    return M.Add(controls, section, row)
end

function M.Subsection(controls, section, text)
    return M.Add(controls, section, SettingsCanvas.CreateSubsectionRow(section.Content, M.L(text)))
end

function M.Checkbox(controls, section, title, getValue, setValue, options)
    return M.Add(controls, section, SettingsCanvas.CreateCheckboxRow(
        section.Content, M.L(title), getValue, setValue, options
    ))
end

function M.Dropdown(controls, section, title, getValue, setValue, valuesProvider, options)
    return M.Add(controls, section, SettingsCanvas.CreateDropdownRow(
        section.Content, M.L(title), getValue, setValue, valuesProvider, options
    ))
end

function M.Slider(controls, section, title, getValue, setValue, config)
    config = config or {}
    if not config.formatter then
        local decimals = config.step and config.step < 1 and 1 or 0
        config.formatter = function(value)
            if type(value) ~= "number" then return "--" end
            return string.format("%." .. decimals .. "f", value)
        end
    end
    return M.Add(controls, section, SettingsCanvas.CreateSliderRow(
        section.Content, M.L(title), getValue, setValue, config
    ))
end

function M.Input(controls, section, title, getValue, setValue, options)
    options = options or {}
    local Canvas = M.Canvas
    local row = Canvas.CreateBaseRow(section.Content, 28)
    row.Label = Canvas.CreateLabel(row, M.L(title), "GameFontHighlight")
    row.Label:SetPoint("LEFT", 0, 0)
    row.Label:SetWidth(options.labelWidth or 170)
    row.Input = Canvas.CreateInput(row)
    row.Input:SetPoint("LEFT", row.Label, "RIGHT", 10, 0)
    row.Input:SetPoint("RIGHT", row, "RIGHT", -(options.rightInset or 0), 0)
    row.Input:SetAutoFocus(false)
    if options.maxLetters then row.Input:SetMaxLetters(options.maxLetters) end

    local function Restore()
        row.Input:SetText(tostring(getValue() or ""))
    end
    local function Commit()
        if type(options.disabled) == "function" and options.disabled() then Restore() return end
        local value = row.Input:GetText() or ""
        if options.trim ~= false then value = value:match("^%s*(.-)%s*$") end
        setValue(value)
        if row.lscRefreshPanel then row.lscRefreshPanel() else Restore() end
    end
    row.Input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.Input:SetScript("OnEscapePressed", function(self)
        self.lscCancelEdit = true
        self:ClearFocus()
    end)
    row.Input:SetScript("OnEditFocusLost", function(self)
        if self.lscCancelEdit then self.lscCancelEdit = nil Restore() else Commit() end
    end)
    function row:Refresh()
        local hidden = type(options.hidden) == "function" and options.hidden() == true
        self:SetShown(not hidden)
        if hidden then return end
        local disabled = type(options.disabled) == "function" and options.disabled() == true
        Canvas.SetFontStringEnabled(self.Label, not disabled)
        Canvas.SetWidgetEnabled(self.Input, not disabled)
        if not self.Input:HasFocus() then Restore() end
    end
    Restore()
    return M.Add(controls, section, row)
end

function M.Color(controls, section, title, getValue, setValue, options)
    return M.Add(controls, section, SettingsCanvas.CreateColorRow(
        section.Content, M.L(title), getValue, setValue, options
    ))
end

function M.ColorChoices(controls, section, title, getValue, setValue, choicesProvider, options)
    options = options or {}
    local Canvas = M.Canvas
    local row = Canvas.CreateBaseRow(section.Content, 44)
    row.Label = Canvas.CreateLabel(row, M.L(title), "GameFontHighlight")
    row.Label:SetPoint("LEFT", 0, 0)
    row.Label:SetWidth(170)
    row.Choices = {}

    local function ShowTooltip(button, choice)
        if not GameTooltip then return end
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(M.L(choice.text or tostring(choice.value)))
        if choice.description then GameTooltip:AddLine(M.L(choice.description), 1, 1, 1, true) end
        GameTooltip:Show()
    end

    local function EnsureChoice(index)
        if row.Choices[index] then return row.Choices[index] end
        local button = CreateFrame("Button", nil, row)
        button:SetSize(82, 38)
        button.Border = button:CreateTexture(nil, "BORDER")
        button.Border:SetPoint("TOPLEFT", 0, 0)
        button.Border:SetPoint("TOPRIGHT", 0, 0)
        button.Border:SetHeight(20)
        button.Border:SetColorTexture(0, 0, 0, 1)
        button.Left = button:CreateTexture(nil, "ARTWORK")
        button.Left:SetPoint("TOPLEFT", 2, -2)
        button.Left:SetPoint("BOTTOMRIGHT", button.Border, "BOTTOM", 0, 2)
        button.Right = button:CreateTexture(nil, "ARTWORK")
        button.Right:SetPoint("TOPLEFT", button.Border, "TOP", 0, -2)
        button.Right:SetPoint("BOTTOMRIGHT", button.Border, "BOTTOMRIGHT", -2, 2)
        button.Text = Canvas.CreateLabel(button, "", "GameFontHighlightSmall")
        button.Text:SetPoint("TOP", button.Border, "BOTTOM", 0, -3)
        button.Text:SetWidth(82)
        button:SetScript("OnEnter", function(self) if self.choice then ShowTooltip(self, self.choice) end end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        button:SetScript("OnClick", function(self)
            local choice = self.choice
            if not choice or (type(options.disabled) == "function" and options.disabled()) then return end
            setValue(choice.value)
            if choice.editColor and type(choice.getColor) == "function" and type(choice.setColor) == "function" then
                Canvas.ShowColorPicker(choice.getColor(), function(colour)
                    choice.setColor(colour)
                    if row.lscRefreshPanel then row.lscRefreshPanel() end
                end)
            end
            if row.lscRefreshPanel then row.lscRefreshPanel() end
        end)
        row.Choices[index] = button
        return button
    end

    function row:Refresh()
        local hidden = type(options.hidden) == "function" and options.hidden() == true
        self:SetShown(not hidden)
        if hidden then return end
        local disabled = type(options.disabled) == "function" and options.disabled() == true
        local choices = choicesProvider() or {}
        local selected = getValue()
        local previous
        for index, choice in ipairs(choices) do
            local button = EnsureChoice(index)
            button.choice = choice
            button:ClearAllPoints()
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
            else button:SetPoint("LEFT", row, "LEFT", 180, 0) end
            previous = button
            local colour = Canvas.NormalizeColorTable(choice.getColor and choice.getColor() or choice.color)
            local second = Canvas.NormalizeColorTable(choice.getSecondColor and choice.getSecondColor() or colour)
            button.Left:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
            button.Right:SetColorTexture(second[1], second[2], second[3], second[4])
            button.Text:SetText(M.L(choice.text or tostring(choice.value)))
            local active = choice.value == selected
            button.Border:SetColorTexture(active and 1 or 0, active and 0.82 or 0, 0, 1)
            Canvas.SetWidgetEnabled(button, not disabled)
            button:SetAlpha(disabled and 0.4 or active and 1 or 0.35)
            button:Show()
        end
        for index = #choices + 1, #self.Choices do self.Choices[index]:Hide() end
        Canvas.SetFontStringEnabled(self.Label, not disabled)
    end

    return M.Add(controls, section, row)
end

function M.Buttons(controls, section, buttons, options)
    local row = SettingsCanvas.CreateButtonRow(section.Content, buttons)
    if options and type(options.disabled) == "function" then
        local refresh = row.Refresh
        function row:Refresh()
            if refresh then refresh(self) end
            local enabled = not options.disabled()
            for _, button in ipairs(self.Buttons or {}) do SettingsCanvas.SetWidgetEnabled(button, enabled) end
        end
    end
    return M.Add(controls, section, row)
end

function M.Get(rootProvider, path)
    local value = rootProvider()
    for index = 1, #path do
        if type(value) ~= "table" then return nil end
        value = value[path[index]]
    end
    return value
end

function M.Set(rootProvider, path, value)
    local target = rootProvider()
    for index = 1, #path - 1 do
        local key = path[index]
        if type(target[key]) ~= "table" then target[key] = {} end
        target = target[key]
    end
    target[path[#path]] = value
end

function M.Access(rootProvider, path, onChanged)
    return function()
        return M.Get(rootProvider, path)
    end, function(value)
        M.Set(rootProvider, path, value)
        if onChanged then onChanged(value) end
    end
end

function M.ColorAccess(rootProvider, path, onChanged, withAlpha)
    return function()
        return M.Get(rootProvider, path)
    end, function(value)
        if not withAlpha then value = { value[1], value[2], value[3] } end
        M.Set(rootProvider, path, value)
        if onChanged then onChanged(value) end
    end
end

M.Canvas = SettingsCanvas
