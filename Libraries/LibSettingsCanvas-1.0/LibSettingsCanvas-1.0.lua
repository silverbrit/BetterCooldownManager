local MAJOR, MINOR = "LibSettingsCanvas-1.0", 6
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
	return
end

local floor = math.floor

local DEFAULT_ROW_LABEL_WIDTH = 245
local DEFAULT_CONTROL_WIDTH = 320
local DEFAULT_SLIDER_INPUT_WIDTH = 56
local DEFAULT_SLIDER_INPUT_GAP = 8
local DEFAULT_COLOR_SWATCH_WIDTH = 28
local DEFAULT_COLOR_SWATCH_HEIGHT = 18

local function ResolveConfig(config)
	config = type(config) == "table" and config or {}
	config.rowLabelWidth = config.rowLabelWidth or DEFAULT_ROW_LABEL_WIDTH
	config.controlWidth = config.controlWidth or DEFAULT_CONTROL_WIDTH
	config.sliderInputWidth = config.sliderInputWidth or DEFAULT_SLIDER_INPUT_WIDTH
	config.sliderInputGap = config.sliderInputGap or DEFAULT_SLIDER_INPUT_GAP
	config.sliderControlWidth = config.sliderControlWidth
		or (config.controlWidth - config.sliderInputWidth - config.sliderInputGap)
	config.colorSwatchWidth = config.colorSwatchWidth or DEFAULT_COLOR_SWATCH_WIDTH
	config.colorSwatchHeight = config.colorSwatchHeight or DEFAULT_COLOR_SWATCH_HEIGHT
	return config
end

local function ResolveTooltipText(textOrProvider)
	if type(textOrProvider) == "function" then
		local ok, value = pcall(textOrProvider)
		if ok then
			textOrProvider = value
		else
			return nil
		end
	end

	if type(textOrProvider) ~= "string" or textOrProvider == "" then
		return nil
	end

	return textOrProvider
end

function lib.AttachTooltip(widget, title, description)
	if type(widget) ~= "table" then
		return
	end

	local function ShowTooltip(owner)
		if type(GameTooltip) ~= "table" or type(GameTooltip.SetOwner) ~= "function" then
			return
		end

		local tooltipTitle = ResolveTooltipText(title)
		local tooltipDescription = ResolveTooltipText(description)
		if not tooltipTitle and not tooltipDescription then
			return
		end

		GameTooltip:SetOwner(owner or widget, "ANCHOR_CURSOR")

		if tooltipTitle then
			GameTooltip:SetText(tooltipTitle, 1, 0.82, 0, 1, true)
			if tooltipDescription then
				GameTooltip:AddLine(tooltipDescription, 1, 1, 1, true)
			end
		elseif tooltipDescription then
			GameTooltip:SetText(tooltipDescription, 1, 1, 1, 1, true)
		end

		GameTooltip:Show()
	end

	local function HideTooltip(owner)
		if type(GameTooltip) ~= "table" or type(GameTooltip.Hide) ~= "function" then
			return
		end

		if type(GameTooltip.IsOwned) == "function" and GameTooltip:IsOwned(owner or widget) ~= true then
			return
		end

		GameTooltip:Hide()
	end

	if type(widget.EnableMouse) == "function" then
		widget:EnableMouse(true)
	end

	if type(widget.HookScript) == "function" then
		widget:HookScript("OnEnter", function(self)
			ShowTooltip(self)
		end)
		widget:HookScript("OnLeave", function(self)
			HideTooltip(self)
		end)
		return
	end

	if type(widget.SetScript) == "function" then
		widget:SetScript("OnEnter", function(self)
			ShowTooltip(self)
		end)
		widget:SetScript("OnLeave", function(self)
			HideTooltip(self)
		end)
	end
end

local function AttachRowTooltip(row, title, description, ...)
	lib.AttachTooltip(row, title, description)

	for index = 1, select("#", ...) do
		local widget = select(index, ...)
		if widget then
			lib.AttachTooltip(widget, title, description)
		end
	end
end

function lib.CreateSection(parent, title, contentHeight, defaultExpanded)
	local section = CreateFrame("Frame", nil, parent)

	section.headerHeight = 34
	section.contentHeight = type(contentHeight) == "number" and contentHeight or 0
	section.expanded = defaultExpanded ~= false

	section.Header = CreateFrame("Button", nil, section)
	section.Header:SetPoint("TOPLEFT", 0, 0)
	section.Header:SetPoint("TOPRIGHT", 0, 0)
	section.Header:SetHeight(section.headerHeight)

	section.Header.BG = section:CreateTexture(nil, "BACKGROUND")
	section.Header.BG:SetPoint("TOPLEFT", section, "TOPLEFT", 0, 0)
	section.Header.BG:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, 0)
	section.Header.BG:SetHeight(section.headerHeight)
	section.Header.BG:SetColorTexture(0.02, 0.02, 0.03, 0.84)
	section.Header:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")

	local headerHighlight = section.Header:GetHighlightTexture()
	if headerHighlight and type(headerHighlight.SetVertexColor) == "function" then
		headerHighlight:SetVertexColor(1, 0.82, 0, 0.08)
	end

	section.TitleText = section.Header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	section.TitleText:SetPoint("LEFT", 8, -1)
	section.TitleText:SetText(title)
	section.TitleText:SetTextColor(1, 0.82, 0)

	section.ToggleText = section.Header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	section.ToggleText:SetPoint("RIGHT", -8, -1)
	section.ToggleText:SetTextColor(1, 0.82, 0)

	section.Content = CreateFrame("Frame", nil, section)
	section.Content:SetPoint("TOPLEFT", 10, -section.headerHeight - 6)
	section.Content:SetPoint("TOPRIGHT", -6, -section.headerHeight - 6)
	section.Content:SetHeight(section.contentHeight)

	function section:SetContentHeight(height)
		height = type(height) == "number" and height or 0
		if height < 0 then
			height = 0
		end

		if self.contentHeight == height then
			return
		end

		self.contentHeight = height
		self.Content:SetHeight(height)
		self:SetExpanded(self.expanded)
	end

	function section:SetExpanded(expanded)
		self.expanded = expanded == true
		self.Content:SetShown(self.expanded)
		self:SetHeight(self.headerHeight + (self.expanded and (self.contentHeight + 12) or 0))
		self.ToggleText:SetText(self.expanded and "-" or "+")

		if type(self.OnExpandedChanged) == "function" then
			self:OnExpandedChanged(self.expanded)
		end
	end

	section.Header:SetScript("OnClick", function()
		section:SetExpanded(not section.expanded)
	end)

	section:SetExpanded(section.expanded)
	return section
end

function lib.CreateLabel(parent, text, fontObject)
	local label = parent:CreateFontString(nil, "ARTWORK", fontObject or "GameFontHighlight")
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

function lib.CreateInput(parent)
	local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	editBox:SetAutoFocus(false)
	editBox:SetHeight(26)
	editBox:SetFontObject("ChatFontNormal")
	editBox:SetTextColor(1, 1, 1)
	editBox:SetHighlightColor(1, 0.82, 0, 0.35)
	editBox:SetTextInsets(8, 8, 0, 0)
	editBox:SetMaxLetters(0)
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	editBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	return editBox
end

function lib.CreateActionButton(parent, text)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetHeight(24)
	button:SetText(text)
	return button
end

function lib.CreateDropdown(parent)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetHeight(26)
	return dropdown
end

function lib.AttachDropdownMenu(dropdown, optionsProvider, selectedValueProvider, onValueSelected, emptyText, config)
	if type(dropdown) ~= "table" then
		return
	end

	dropdown._lscOptionsProvider = optionsProvider
	dropdown._lscSelectedValueProvider = selectedValueProvider
	dropdown._lscOnValueSelected = onValueSelected
	dropdown._lscEmptyText = emptyText or "Select..."
	dropdown._lscMenuConfig = type(config) == "table" and config or {}

	if type(dropdown.SetupMenu) ~= "function" then
		return
	end

	dropdown:SetupMenu(function(_, rootDescription)
		local menuConfig = dropdown._lscMenuConfig or {}
		if type(menuConfig.maxHeight) == "number" and menuConfig.maxHeight > 0 then
			rootDescription:SetScrollMode(menuConfig.maxHeight)
		elseif type(rootDescription.SetScrollMode) == "function" then
			rootDescription:SetScrollMode(260)
		end

		if menuConfig.forceSingleColumn == true
			and type(MenuConstants) == "table"
			and type(MenuConstants.VerticalGridDirection) == "number"
		then
			rootDescription:SetGridMode(MenuConstants.VerticalGridDirection, 1)
		end

		if type(menuConfig.minWidth) == "number" and menuConfig.minWidth > 0 then
			rootDescription:SetMinimumWidth(menuConfig.minWidth)
		end

		local options = optionsProvider and optionsProvider() or {}
		if #options == 0 then
			if type(rootDescription.CreateTitle) == "function" then
				rootDescription:CreateTitle(menuConfig.emptyText or "No options available")
			end
			return
		end

		for _, option in ipairs(options) do
			local value = option.value
			local text = option.text
			if value ~= nil and type(text) == "string" and text ~= "" then
				local radio = rootDescription:CreateRadio(text, function(candidate)
					return selectedValueProvider and selectedValueProvider() == candidate
				end, function(candidate)
					if onValueSelected then
						onValueSelected(candidate)
					end
				end, value)

				if type(option.initializer) == "function" and radio and type(radio.AddInitializer) == "function" then
					radio:AddInitializer(option.initializer)
				end
			end
		end
	end)
end

function lib.RefreshDropdownState(dropdown, disabled)
	if not dropdown then
		return
	end

	local options = dropdown._lscOptionsProvider and dropdown._lscOptionsProvider() or {}
	local selectedValue = dropdown._lscSelectedValueProvider and dropdown._lscSelectedValueProvider() or nil
	local text = dropdown._lscEmptyText or "Select..."

	for _, option in ipairs(options) do
		if option.value == selectedValue then
			text = option.text
			break
		end
	end

	if #options == 0 then
		text = "No options"
		disabled = true
	end

	if type(dropdown.OverrideText) == "function" then
		dropdown:OverrideText(text)
	end

	if type(dropdown.SetEnabled) == "function" then
		dropdown:SetEnabled(disabled ~= true)
	end

	dropdown:SetAlpha(disabled and 0.55 or 1)
end

function lib.NormalizeColorTable(colorTable, fallback)
	local source = type(colorTable) == "table" and colorTable or fallback
	if type(source) ~= "table" then
		source = { 1, 1, 1, 1 }
	end

	local red = type(source[1]) == "number" and source[1] or 1
	local green = type(source[2]) == "number" and source[2] or 1
	local blue = type(source[3]) == "number" and source[3] or 1
	local alpha = type(source[4]) == "number" and source[4] or 1

	if alpha < 0 then
		alpha = 0
	elseif alpha > 1 then
		alpha = 1
	end

	return { red, green, blue, alpha }
end

local function GetColorPickerRGBA()
	if ColorPickerFrame and ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker then
		local picker = ColorPickerFrame.Content.ColorPicker
		if type(picker.GetColorRGB) == "function" then
			local red, green, blue = picker:GetColorRGB()
			local alpha = type(picker.GetColorAlpha) == "function" and picker:GetColorAlpha() or 1
			return red, green, blue, alpha
		end
	end

	if ColorPickerFrame and type(ColorPickerFrame.GetColorRGB) == "function" then
		local red, green, blue = ColorPickerFrame:GetColorRGB()
		local alpha = type(ColorPickerFrame.GetColorAlpha) == "function" and ColorPickerFrame:GetColorAlpha() or 1
		return red, green, blue, alpha
	end

	return 1, 1, 1, 1
end

function lib.ShowColorPicker(colorTable, onChanged)
	if not ColorPickerFrame or type(onChanged) ~= "function" then
		return
	end

	local initialColor = lib.NormalizeColorTable(colorTable)

	local function ApplyCurrentColor()
		local red, green, blue, alpha = GetColorPickerRGBA()
		onChanged({ red, green, blue, alpha }, false)
	end

	local function CancelColor()
		onChanged({ initialColor[1], initialColor[2], initialColor[3], initialColor[4] }, true)
	end

	local info = {
		r = initialColor[1],
		g = initialColor[2],
		b = initialColor[3],
		opacity = initialColor[4],
		hasOpacity = true,
		swatchFunc = ApplyCurrentColor,
		opacityFunc = ApplyCurrentColor,
		cancelFunc = CancelColor,
	}

	if type(ColorPickerFrame.SetupColorPickerAndShow) == "function" then
		ColorPickerFrame:SetupColorPickerAndShow(info)
		return
	end

	ColorPickerFrame.func = ApplyCurrentColor
	ColorPickerFrame.opacityFunc = ApplyCurrentColor
	ColorPickerFrame.cancelFunc = CancelColor
	ColorPickerFrame.hasOpacity = true
	ColorPickerFrame.opacity = initialColor[4]
	ColorPickerFrame.previousValues = {
		r = initialColor[1],
		g = initialColor[2],
		b = initialColor[3],
		opacity = initialColor[4],
	}

	if type(ColorPickerFrame.SetColorRGB) == "function" then
		ColorPickerFrame:SetColorRGB(initialColor[1], initialColor[2], initialColor[3])
	end

	if type(ShowUIPanel) == "function" then
		ShowUIPanel(ColorPickerFrame)
	else
		ColorPickerFrame:Show()
	end
end

function lib.SetFontStringEnabled(fontString, enabled)
	if not fontString then
		return
	end

	fontString:SetAlpha(enabled and 1 or 0.55)
end

function lib.SetWidgetEnabled(widget, enabled)
	if not widget then
		return
	end

	if type(widget.SetEnabled) == "function" then
		widget:SetEnabled(enabled)
	end

	widget:SetAlpha(enabled and 1 or 0.55)
end

function lib.CreateBaseRow(parent, height)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(height)
	row.baseHeight = height
	return row
end

function lib.CreateTextRow(parent, text)
	local row = lib.CreateBaseRow(parent, 24)
	row.Text = lib.CreateLabel(row, text, "GameFontHighlight")
	row.Text:SetPoint("LEFT", 0, 0)
	row.Text:SetPoint("RIGHT", 0, 0)
	row.Text:SetJustifyH("LEFT")
	row.Text:SetJustifyV("MIDDLE")

	function row:Refresh()
		self:SetShown(true)
	end

	return row
end

function lib.CreateSubsectionRow(parent, text)
	local row = lib.CreateBaseRow(parent, 22)
	row.Text = lib.CreateLabel(row, text, "GameFontNormal")
	row.Text:SetPoint("LEFT", 0, 0)
	row.Text:SetPoint("RIGHT", 0, 0)
	row.Text:SetJustifyH("LEFT")
	row.Text:SetJustifyV("MIDDLE")
	row.Text:SetTextColor(1, 0.82, 0)

	function row:Refresh()
		self:SetShown(true)
	end

	return row
end

function lib.CreateCheckboxRow(parent, title, getValue, setValue, options, config)
	options = type(options) == "table" and options or {}
	config = ResolveConfig(config)

	local row = lib.CreateBaseRow(parent, 28)
	row.Label = lib.CreateLabel(row, title, "GameFontHighlight")
	row.Label:SetPoint("LEFT", 0, 0)
	row.Label:SetWidth(config.rowLabelWidth)
	if type(row.Label.SetWordWrap) == "function" then
		row.Label:SetWordWrap(false)
	end

	row.CheckButton = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.CheckButton:SetSize(24, 24)
	row.CheckButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)

	if row.CheckButton.Text then
		row.CheckButton.Text:SetText("")
		row.CheckButton.Text:Hide()
	end

	if row.CheckButton.text then
		row.CheckButton.text:SetText("")
		row.CheckButton.text:Hide()
	end

	row.CheckButton:SetScript("OnClick", function(self)
		if row.lscRefreshing == true then
			return
		end

		setValue(self:GetChecked() == true)
		if row.lscRefreshPanel then
			row.lscRefreshPanel()
		end
	end)

	AttachRowTooltip(row, title, options.description, row.CheckButton)

	function row:Refresh()
		local hidden = type(options.hidden) == "function" and options.hidden() == true
		self:SetShown(not hidden)
		if hidden then
			return
		end

		local disabled = type(options.disabled) == "function" and options.disabled() == true
		self.lscRefreshing = true
		self.CheckButton:SetChecked(getValue() == true)
		self.lscRefreshing = false

		lib.SetWidgetEnabled(self.CheckButton, not disabled)
		lib.SetFontStringEnabled(self.Label, not disabled)
	end

	return row
end

function lib.CreateDropdownRow(parent, title, getValue, setValue, valuesProvider, options, config)
	options = type(options) == "table" and options or {}
	config = ResolveConfig(config)

	local row = lib.CreateBaseRow(parent, 28)
	row.Label = lib.CreateLabel(row, title, "GameFontHighlight")
	row.Label:SetPoint("LEFT", 0, 0)
	row.Label:SetWidth(config.rowLabelWidth)
	if type(row.Label.SetWordWrap) == "function" then
		row.Label:SetWordWrap(false)
	end

	row.Dropdown = lib.CreateDropdown(row)
	row.Dropdown:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.Dropdown:SetWidth(options.width or config.controlWidth)

	lib.AttachDropdownMenu(
		row.Dropdown,
		valuesProvider,
		getValue,
		function(value)
			setValue(value)
			if row.lscRefreshPanel then
				row.lscRefreshPanel()
			end
		end,
		options.emptyText,
		{
			maxHeight = options.maxHeight,
			minWidth = options.minWidth,
			forceSingleColumn = options.forceSingleColumn,
			emptyText = options.noOptionsText,
		}
	)

	AttachRowTooltip(row, title, options.description, row.Dropdown)

	function row:Refresh()
		local hidden = type(options.hidden) == "function" and options.hidden() == true
		self:SetShown(not hidden)
		if hidden then
			return
		end

		local disabled = type(options.disabled) == "function" and options.disabled() == true
		lib.RefreshDropdownState(self.Dropdown, disabled)
		lib.SetFontStringEnabled(self.Label, not disabled)
		lib.SetWidgetEnabled(self.Dropdown, not disabled)
	end

	return row
end

function lib.CreateSliderRow(parent, title, getValue, setValue, config)
	config = ResolveConfig(config)

	local row = lib.CreateBaseRow(parent, 28)
	row.Label = lib.CreateLabel(row, title, "GameFontHighlight")
	row.Label:SetPoint("LEFT", 0, 0)
	row.Label:SetWidth(config.rowLabelWidth)
	if type(row.Label.SetWordWrap) == "function" then
		row.Label:SetWordWrap(false)
	end

	local formatter = config.formatter or function(value)
		return tostring(value)
	end

	local minValue = config.min or 0
	local maxValue = config.max or 1
	local valueStep = config.step or 1
	local numSteps = math.max(1, floor(((maxValue - minValue) / valueStep) + 0.5))
	local formattedMaximum = tostring(formatter(maxValue))
	local usesPercent = formattedMaximum:find("%", 1, true) ~= nil

	row.ValueInput = lib.CreateInput(row)
	row.ValueInput:SetWidth(config.sliderInputWidth)
	row.ValueInput:SetPoint("RIGHT", row, "RIGHT", -(config.rightInset or 0), 0)
	row.ValueInput:SetJustifyH("CENTER")
	row.ValueDisplay = lib.CreateLabel(row.ValueInput, "", "GameFontHighlightSmall")
	row.ValueDisplay:SetPoint("LEFT", row.ValueInput, "LEFT", 8, 0)
	row.ValueDisplay:SetPoint("RIGHT", row.ValueInput, "RIGHT", -8, 0)
	row.ValueDisplay:SetJustifyH("CENTER")
	row.ValueDisplay:SetJustifyV("MIDDLE")

	row.Slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
	row.Slider:SetPoint("RIGHT", row.ValueInput, "LEFT", -config.sliderInputGap, 0)
	row.Slider:SetWidth(config.width or config.sliderControlWidth)
	row.Slider:SetHeight(20)
	local function SetDisplayedValue(value)
		local text = tostring(formatter(value))
		row.ValueInput:SetText(text)
		row.ValueDisplay:SetText(text)
	end

	local function RefreshInputAppearance(disabled)
		if row.ValueInput:HasFocus() then
			row.ValueDisplay:Hide()
			row.ValueInput:SetTextColor(1, 1, 1, 1)
		else
			row.ValueInput:SetTextColor(1, 1, 1, 0)
			if disabled then row.ValueDisplay:SetTextColor(0.5, 0.5, 0.5, 1)
			else row.ValueDisplay:SetTextColor(1, 1, 1, 1) end
			row.ValueDisplay:Show()
		end
	end

	local initialValue = getValue()
	SetDisplayedValue(initialValue)
	RefreshInputAppearance(type(config.disabled) == "function" and config.disabled() == true)
	row.Slider:Init(initialValue, minValue, maxValue, numSteps, {})

	local function NormalizeInput(text)
		text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
		local numericText = text:gsub("%%", "")
		local value = tonumber(numericText)
		if not value then
			return nil
		end
		if usesPercent then
			value = value / 100
		end
		value = math.max(minValue, math.min(maxValue, value))
		value = minValue + floor(((value - minValue) / valueStep) + 0.5) * valueStep
		return math.max(minValue, math.min(maxValue, value))
	end

	local function RestoreInput()
		SetDisplayedValue(getValue())
		RefreshInputAppearance(type(config.disabled) == "function" and config.disabled() == true)
	end

	local function CommitInput()
		local disabled = type(config.disabled) == "function" and config.disabled() == true
		local value = not disabled and NormalizeInput(row.ValueInput:GetText()) or nil
		if value == nil then
			RestoreInput()
			return
		end

		row.lscRefreshing = true
		row.Slider:SetValue(value)
		row.lscRefreshing = false
		setValue(value)
		if row.lscRefreshPanel then
			row.lscRefreshPanel()
		else
			RestoreInput()
		end
	end

	row.ValueInput:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	row.ValueInput:SetScript("OnEscapePressed", function(self)
		self.lscCancelEdit = true
		self:ClearFocus()
	end)
	row.ValueInput:SetScript("OnEditFocusGained", function(self)
		row.ValueDisplay:Hide()
		self:SetTextColor(1, 1, 1, 1)
		self:HighlightText()
	end)
	row.ValueInput:SetScript("OnEditFocusLost", function(self)
		if self.lscCancelEdit then
			self.lscCancelEdit = nil
			RestoreInput()
			return
		end
		CommitInput()
	end)

	row.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if row.lscRefreshing == true then
			return
		end

		setValue(value)
		if row.lscRefreshPanel then
			row.lscRefreshPanel()
		else
			RestoreInput()
		end
	end)

	AttachRowTooltip(
		row,
		title,
		config.description,
		row.Slider,
		row.Slider.Slider,
		row.Slider.Back,
		row.Slider.Forward,
		row.Slider.BackButton,
		row.Slider.ForwardButton,
		row.Slider.DecrementButton,
		row.Slider.IncrementButton,
		row.ValueInput
	)

	function row:Refresh()
		local hidden = type(config.hidden) == "function" and config.hidden() == true
		self:SetShown(not hidden)
		if hidden then
			return
		end

		local disabled = type(config.disabled) == "function" and config.disabled() == true
		self.lscRefreshing = true
		local value = getValue()
		self.Slider:SetValue(value)
		if not self.ValueInput:HasFocus() then
			SetDisplayedValue(value)
		end
		self.lscRefreshing = false

		lib.SetFontStringEnabled(self.Label, not disabled)
		lib.SetWidgetEnabled(self.Slider, not disabled)
		if self.Slider.Slider then
			lib.SetWidgetEnabled(self.Slider.Slider, not disabled)
		end
		lib.SetWidgetEnabled(self.ValueInput, not disabled)
		RefreshInputAppearance(disabled)
	end

	return row
end

function lib.UpdateColorSwatch(button, colorTable)
	local color = lib.NormalizeColorTable(colorTable)
	button.Swatch:SetColorTexture(color[1], color[2], color[3], color[4])
end

function lib.CreateColorRow(parent, title, getValue, setValue, options, config)
	options = type(options) == "table" and options or {}
	config = ResolveConfig(config)

	local row = lib.CreateBaseRow(parent, 28)
	row.Label = lib.CreateLabel(row, title, "GameFontHighlight")
	row.Label:SetPoint("LEFT", 0, 0)
	row.Label:SetWidth(config.rowLabelWidth)
	if type(row.Label.SetWordWrap) == "function" then
		row.Label:SetWordWrap(false)
	end

	row.ColorButton = CreateFrame("Button", nil, row)
	row.ColorButton:SetSize(config.colorSwatchWidth, config.colorSwatchHeight)
	row.ColorButton:SetPoint("RIGHT", row, "RIGHT", -6, 0)

	row.ColorButton.Border = row.ColorButton:CreateTexture(nil, "BORDER")
	row.ColorButton.Border:SetPoint("TOPLEFT", -1, 1)
	row.ColorButton.Border:SetPoint("BOTTOMRIGHT", 1, -1)
	row.ColorButton.Border:SetColorTexture(0, 0, 0, 1)

	row.ColorButton.Background = row.ColorButton:CreateTexture(nil, "BACKGROUND")
	row.ColorButton.Background:SetAllPoints()
	row.ColorButton.Background:SetColorTexture(0.18, 0.18, 0.18, 1)

	row.ColorButton.Swatch = row.ColorButton:CreateTexture(nil, "ARTWORK")
	row.ColorButton.Swatch:SetPoint("TOPLEFT", 1, -1)
	row.ColorButton.Swatch:SetPoint("BOTTOMRIGHT", -1, 1)

	row.ColorButton:SetScript("OnClick", function()
		if type(options.disabled) == "function" and options.disabled() == true then
			return
		end

		lib.ShowColorPicker(getValue(), function(color)
			setValue(color)
			if row.lscRefreshPanel then
				row.lscRefreshPanel()
			end
		end)
	end)

	AttachRowTooltip(row, title, options.description, row.ColorButton)

	function row:Refresh()
		local hidden = type(options.hidden) == "function" and options.hidden() == true
		self:SetShown(not hidden)
		if hidden then
			return
		end

		local disabled = type(options.disabled) == "function" and options.disabled() == true
		lib.UpdateColorSwatch(self.ColorButton, getValue())
		lib.SetFontStringEnabled(self.Label, not disabled)
		lib.SetWidgetEnabled(self.ColorButton, not disabled)
	end

	return row
end

function lib.CreateButtonRow(parent, buttons)
	local row = lib.CreateBaseRow(parent, 28)
	row.Buttons = {}

	local previousButton
	for _, buttonInfo in ipairs(buttons or {}) do
		if type(buttonInfo) == "table" and type(buttonInfo.text) == "string" and buttonInfo.text ~= "" then
			local button = lib.CreateActionButton(row, buttonInfo.text)
			button:SetWidth(buttonInfo.width or 150)
			if previousButton then
				button:SetPoint("LEFT", previousButton, "RIGHT", 8, 0)
			else
				button:SetPoint("LEFT", row, "LEFT", 0, 0)
			end
			button:SetPoint("TOP", row, "TOP", 0, 0)
			button:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
			button:SetScript("OnClick", function()
				if type(buttonInfo.click) == "function" then
					buttonInfo.click()
				end
			end)
			table.insert(row.Buttons, button)
			previousButton = button
		end
	end

	function row:Refresh()
		self:SetShown(#self.Buttons > 0)
		for _, button in ipairs(self.Buttons) do
			lib.SetWidgetEnabled(button, true)
		end
	end

	return row
end

function lib.CreateIconTextActionList(parent, config)
	config = type(config) == "table" and config or {}

	local rowCount = type(config.rowCount) == "number" and config.rowCount or 10
	local rowHeight = type(config.rowHeight) == "number" and config.rowHeight or 22
	local rowSpacing = type(config.rowSpacing) == "number" and config.rowSpacing or 6
	local iconSize = type(config.iconSize) == "number" and config.iconSize or 18
	local actionWidth = type(config.actionWidth) == "number" and config.actionWidth or 72
	local actionText = type(config.actionText) == "string" and config.actionText or "Remove"

	local list = CreateFrame("Frame", nil, parent)
	list:SetHeight(math.max(1, rowCount * rowHeight + math.max(0, rowCount - 1) * rowSpacing))
	list.Rows = {}
	list.rowCount = rowCount
	list.config = config

	local previousRow
	for index = 1, rowCount do
		local row = CreateFrame("Frame", nil, list)
		row:SetHeight(rowHeight)
		row:EnableMouse(true)
		if index == 1 then
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
		else
			row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -rowSpacing)
		end
		row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)

		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.Icon:SetSize(iconSize, iconSize)

		row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 8, 0)
		row.Text:SetPoint("RIGHT", row, "RIGHT", -(actionWidth + 10), 0)
		row.Text:SetJustifyH("LEFT")
		row.Text:SetWordWrap(false)

		row.ActionButton = lib.CreateActionButton(row, actionText)
		row.ActionButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.ActionButton:SetSize(actionWidth, math.max(20, rowHeight - 2))

		local function ShowRowTooltip(owner)
			local onEnter = list.config and list.config.onEnter
			if type(onEnter) == "function" then
				onEnter(row.item, owner or row)
			end
		end

		local function HideRowTooltip(owner)
			local onLeave = list.config and list.config.onLeave
			if type(onLeave) == "function" then
				onLeave(row.item, owner or row)
			elseif type(GameTooltip) == "table" and type(GameTooltip.Hide) == "function" then
				GameTooltip:Hide()
			end
		end

		row:SetScript("OnEnter", function(self)
			ShowRowTooltip(self)
		end)
		row:SetScript("OnLeave", function(self)
			HideRowTooltip(self)
		end)
		row.ActionButton:SetScript("OnEnter", function(self)
			ShowRowTooltip(self)
		end)
		row.ActionButton:SetScript("OnLeave", function(self)
			HideRowTooltip(self)
		end)
		row.ActionButton:SetScript("OnClick", function()
			local onAction = list.config and list.config.onAction
			if type(onAction) == "function" then
				onAction(row.item, row)
			end
		end)

		row:Hide()
		list.Rows[index] = row
		previousRow = row
	end

	function list:Refresh(items)
		if type(items) ~= "table" then
			items = {}
		end

		local shownRows = 0
		for index = 1, self.rowCount do
			local row = self.Rows[index]
			local item = items[index]
			if item ~= nil then
				local text = item
				local icon = nil
				if type(self.config.getText) == "function" then
					text = self.config.getText(item)
				end
				if type(self.config.getIcon) == "function" then
					icon = self.config.getIcon(item)
				end

				row.item = item
				row.Text:SetText(tostring(text or ""))
				row.Icon:SetTexture(icon or config.fallbackIcon or 134400)
				row:Show()
				shownRows = shownRows + 1
			else
				row.item = nil
				row.Icon:SetTexture(nil)
				row.Text:SetText("")
				row:Hide()
			end
		end

		return shownRows
	end

	return list
end

function lib.CreateProfileManagementSection(parent, title, strings, config)
	strings = type(strings) == "table" and strings or {}
	config = type(config) == "table" and config or {}

	local section = lib.CreateSection(parent, title or strings.title or "Profiles", 0, config.defaultExpanded ~= false)
	section.lscManualLayout = true
	local controls = {}

	local introText = lib.CreateLabel(
		section.Content,
		strings.introText or "Switch the active profile, create new ones, copy settings between profiles, and remove unused profiles.",
		"GameFontHighlightLarge"
	)
	introText:SetPoint("TOPLEFT", 0, -6)
	introText:SetPoint("RIGHT", 0, 0)
	controls.introText = introText

	local resetDesc = lib.CreateLabel(
		section.Content,
		strings.resetDescription or "Reset the current profile back to its default values.",
		"GameFontHighlightLarge"
	)
	resetDesc:SetPoint("TOPLEFT", 0, -48)
	resetDesc:SetPoint("RIGHT", 0, 0)
	controls.resetDescription = resetDesc

	controls.resetButton = lib.CreateActionButton(section.Content, strings.resetButtonText or "Reset Profile")
	controls.resetButton:SetPoint("TOPLEFT", 0, -94)
	controls.resetButton:SetWidth(config.resetButtonWidth or 180)

	controls.currentProfileLabel =
		lib.CreateLabel(section.Content, strings.currentProfileText or "Current Profile: |cffffd100Default|r", "GameFontHighlightLarge")
	controls.currentProfileLabel:SetPoint("LEFT", controls.resetButton, "RIGHT", 16, 0)

	local chooseDesc = lib.CreateLabel(
		section.Content,
		strings.chooseDescription or "Create a new profile by entering a name in the edit box, or switch to one of the existing profiles.",
		"GameFontHighlightLarge"
	)
	chooseDesc:SetPoint("TOPLEFT", 0, -128)
	chooseDesc:SetPoint("RIGHT", 0, 0)
	controls.chooseDesc = chooseDesc

	local newLabel = lib.CreateLabel(section.Content, strings.newLabel or "New", "GameFontNormalLarge")
	newLabel:SetPoint("TOPLEFT", 0, -186)
	newLabel:SetTextColor(1, 0.82, 0)
	controls.newLabel = newLabel

	controls.activeDropdownLabel = lib.CreateLabel(section.Content, strings.existingLabel or "Existing Profiles", "GameFontNormalLarge")
	controls.activeDropdownLabel:SetPoint("TOPLEFT", config.existingColumnX or 330, -186)
	controls.activeDropdownLabel:SetTextColor(1, 0.82, 0)

	controls.createNameEdit = lib.CreateInput(section.Content)
	controls.createNameEdit:SetPoint("TOPLEFT", 6, -214)
	controls.createNameEdit:SetWidth(config.createInputWidth or 200)

	controls.createButton = lib.CreateActionButton(section.Content, strings.createButtonText or "Create")
	controls.createButton:SetPoint("LEFT", controls.createNameEdit, "RIGHT", 10, 0)
	controls.createButton:SetWidth(config.createButtonWidth or 90)

	controls.activeDropdown = lib.CreateDropdown(section.Content)
	controls.activeDropdown:SetPoint("TOPLEFT", config.existingColumnX or 330, -214)
	controls.activeDropdown:SetPoint("RIGHT", 0, 0)

	local copyDesc = lib.CreateLabel(
		section.Content,
		strings.copyDescription or "Copy the settings from one existing profile into the currently active profile.",
		"GameFontHighlightLarge"
	)
	copyDesc:SetPoint("TOPLEFT", 0, -258)
	copyDesc:SetPoint("RIGHT", 0, 0)
	controls.copyDescription = copyDesc

	local copyLabel = lib.CreateLabel(section.Content, strings.copyLabel or "Copy From", "GameFontNormalLarge")
	copyLabel:SetPoint("TOPLEFT", 0, -312)
	copyLabel:SetTextColor(1, 0.82, 0)
	controls.copyLabel = copyLabel

	controls.copyDropdown = lib.CreateDropdown(section.Content)
	controls.copyDropdown:SetPoint("TOPLEFT", 0, -340)
	controls.copyDropdown:SetPoint("RIGHT", -100, 0)

	controls.copyButton = lib.CreateActionButton(section.Content, strings.copyButtonText or "Copy")
	controls.copyButton:SetPoint("LEFT", controls.copyDropdown, "RIGHT", 10, 0)
	controls.copyButton:SetPoint("RIGHT", 0, 0)

	local deleteDesc = lib.CreateLabel(
		section.Content,
		strings.deleteDescription or "Delete existing and unused profiles from the database.",
		"GameFontHighlightLarge"
	)
	deleteDesc:SetPoint("TOPLEFT", 0, -380)
	deleteDesc:SetPoint("RIGHT", 0, 0)
	controls.deleteDescription = deleteDesc

	local deleteLabel = lib.CreateLabel(section.Content, strings.deleteLabel or "Delete a Profile", "GameFontNormalLarge")
	deleteLabel:SetPoint("TOPLEFT", 0, -434)
	deleteLabel:SetTextColor(1, 0.82, 0)
	controls.deleteLabel = deleteLabel

	controls.deleteDropdown = lib.CreateDropdown(section.Content)
	controls.deleteDropdown:SetPoint("TOPLEFT", 0, -462)
	controls.deleteDropdown:SetPoint("RIGHT", -100, 0)

	controls.deleteButton = lib.CreateActionButton(section.Content, strings.deleteButtonText or "Delete")
	controls.deleteButton:SetPoint("LEFT", controls.deleteDropdown, "RIGHT", 10, 0)
	controls.deleteButton:SetPoint("RIGHT", 0, 0)

	local contentHeight = type(config.contentHeight) == "number" and config.contentHeight or 496
	section:SetContentHeight(contentHeight)

	return section, controls
end

function lib.CreateProfileSharingSection(parent, title, strings, config)
	strings = type(strings) == "table" and strings or {}
	config = type(config) == "table" and config or {}

	local section = lib.CreateSection(parent, title or strings.title or "Profile Sharing", 0, config.defaultExpanded ~= false)
	section.lscManualLayout = true
	local controls = {}

	controls.exportLabel = lib.CreateLabel(section.Content, strings.exportLabel or "Export Profile", "GameFontNormalLarge")
	controls.exportLabel:SetPoint("TOPLEFT", 0, -10)
	controls.exportLabel:SetTextColor(1, 0.82, 0)

	controls.exportDropdown = lib.CreateDropdown(section.Content)
	controls.exportDropdown:SetPoint("TOPLEFT", 0, -38)
	controls.exportDropdown:SetPoint("RIGHT", -(config.actionColumnWidth or 100), 0)

	controls.exportButton = lib.CreateActionButton(section.Content, strings.exportButtonText or "Export")
	controls.exportButton:SetPoint("LEFT", controls.exportDropdown, "RIGHT", 10, 0)
	controls.exportButton:SetPoint("RIGHT", 0, 0)

	controls.importLabel = lib.CreateLabel(section.Content, strings.importLabel or "Import String", "GameFontNormalLarge")
	controls.importLabel:SetPoint("TOPLEFT", 0, -76)
	controls.importLabel:SetTextColor(1, 0.82, 0)

	controls.importDataEdit = lib.CreateInput(section.Content)
	controls.importDataEdit:SetPoint("TOPLEFT", 6, -104)
	controls.importDataEdit:SetPoint("RIGHT", -(config.actionColumnWidth or 100), 0)

	controls.importButton = lib.CreateActionButton(section.Content, strings.importButtonText or "Import")
	controls.importButton:SetPoint("LEFT", controls.importDataEdit, "RIGHT", 10, 0)
	controls.importButton:SetPoint("RIGHT", 0, 0)

	section:SetContentHeight(type(config.contentHeight) == "number" and config.contentHeight or 136)
	return section, controls
end

function lib.CreatePanel(config)
	config = ResolveConfig(config)

	local panel = CreateFrame("Frame")
	local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 0, -8)
	scrollFrame:SetPoint("BOTTOMRIGHT", -24, 8)

	if scrollFrame.ScrollBar then
		scrollFrame.ScrollBar:Hide()
		scrollFrame.ScrollBar:HookScript("OnShow", function(self)
			self:Hide()
		end)
	end

	if type(ScrollUtil) == "table" and type(ScrollUtil.InitScrollFrameWithScrollBar) == "function" then
		local minimalScrollBar = CreateFrame("EventFrame", nil, scrollFrame, "MinimalScrollBar")
		minimalScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -2)
		minimalScrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, -2)
		ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, minimalScrollBar)
	end

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetPoint("TOPLEFT")
	scrollChild:SetSize(1, 1)
	scrollFrame:SetScrollChild(scrollChild)

	local controls = {
		scrollFrame = scrollFrame,
		scrollChild = scrollChild,
		sections = {},
		rows = {},
		topInset = config.topInset or -6,
		sectionLeftInset = config.sectionLeftInset or 8,
		sectionRightInset = config.sectionRightInset or -4,
		sectionSpacing = config.sectionSpacing or 10,
		bottomPadding = config.bottomPadding or 20,
	}
	panel.controls = controls

	function controls:RelayoutSections()
		local y = self.topInset
		if type(self.LayoutBeforeSections) == "function" then
			y = self:LayoutBeforeSections(y)
		end

		for _, section in ipairs(self.sections) do
			section:ClearAllPoints()
			section:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", self.sectionLeftInset, y)
			section:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", self.sectionRightInset, y)
			y = y - section:GetHeight() - self.sectionSpacing
		end

		self.scrollChild:SetHeight(math.max(1, -y + self.bottomPadding))
	end

	function controls:RegisterSection(section)
		section.OnExpandedChanged = function()
			self:RelayoutSections()
		end

		table.insert(self.sections, section)
		self:RelayoutSections()
	end

	return panel, controls
end

function lib.AddSectionRow(controls, section, row)
	row.lscRefreshPanel = function()
		local panel = controls and controls.panel
		if panel and type(panel.Refresh) == "function" then
			panel:Refresh()
		elseif type(controls.RefreshPanel) == "function" then
			controls:RefreshPanel()
		end
	end

	section.rows = section.rows or {}
	table.insert(section.rows, row)
	table.insert(controls.rows, row)
end

function lib.RefreshSectionRows(section)
	local y = -6
	for _, row in ipairs(section.rows or {}) do
		if row:IsShown() then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", section.Content, "TOPLEFT", 0, y)
			row:SetPoint("TOPRIGHT", section.Content, "TOPRIGHT", 0, y)
			y = y - row:GetHeight() - 8
		end
	end

	section:SetContentHeight(math.max(0, -y))
end

function lib.RefreshPanel(panel)
	if not panel or not panel.controls or panel.lscRefreshing == true then
		return
	end

	panel.lscRefreshing = true

	local controls = panel.controls
	for _, row in ipairs(controls.rows or {}) do
		if type(row.Refresh) == "function" then
			row:Refresh()
		end
	end

	for _, section in ipairs(controls.sections or {}) do
		if section.lscManualLayout ~= true then
			lib.RefreshSectionRows(section)
		end
	end

	local scrollWidth = controls.scrollFrame:GetWidth()
	if type(scrollWidth) == "number" and scrollWidth > 0 then
		controls.scrollChild:SetWidth(math.max(1, scrollWidth - 26))
	end

	controls:RelayoutSections()
	panel.lscRefreshing = false
end
