local _, BCDM = ...

local U = BCDM.SettingsUtils

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/lafees-damage-type-tracker"

local function GetAPI()
    local api = _G.LafeeDamageTrackerAPI
    if type(api) == "table" and type(api.IsReady) == "function" and api:IsReady() then return api end
end

local function IsInstalled()
    if not (C_AddOns and C_AddOns.DoesAddOnExist) then return false end
    local ok, installed = pcall(C_AddOns.DoesAddOnExist, "Lafee_damage_tracker")
    return ok and installed == true
end

local function Values(entries)
    return function() return entries end
end

local function CreateUnavailablePanel()
    local panel, controls = U.NewPanel()
    local section = U.Section(controls, "Lafee Damage Type Tracker", true)
    U.Text(controls, section, IsInstalled()
        and "Lafee Damage Type Tracker is installed but its integration API is unavailable. Enable it and reload the UI to manage it here."
        or "Track the share of physical and magical damage taken with Lafee Damage Type Tracker.")
    U.Buttons(controls, section, {{
        text = "Install Lafee Damage Tracker", width = 240,
        click = function() BCDM:OpenURL("Lafee Damage Type Tracker on CurseForge", CURSEFORGE_URL) end,
    }})
    return panel
end

function BCDM:CreateLafeeDamageTrackerPanel()
    local api = GetAPI()
    if not api then return CreateUnavailablePanel() end

    local panel, controls = U.NewPanel()
    local copySource
    local function Refresh()
        if panel.Refresh then panel:Refresh() end
        if panel.RefreshSettingsHighlight then panel:RefreshSettingsHighlight() end
    end
    local function Get(option) return function() return api:GetOption(option) end end
    local function Set(option)
        return function(value) api:SetOption(option, value) Refresh() end
    end
    local function IsFree() return api:GetOption("anchorMode") ~= "FREE" end
    local function IsAnchored() return api:GetOption("anchorMode") == "FREE" end

    local general = U.Section(controls, "Damage Type Tracker", true)
    U.Text(controls, general, "Active character: " .. tostring(api:GetCurrentCharacterKey() or "-"))
    U.Checkbox(controls, general, "Show Bar", Get("shown"), Set("shown"))
    U.Dropdown(controls, general, "Bar Style", Get("barStyle"), Set("barStyle"), Values({
        { text = "Square", value = "SQUARE" }, { text = "Classic", value = "CLASSIC" },
    }))
    U.Slider(controls, general, "Analysis Window", Get("window"), Set("window"),
        { min = 2, max = 10, step = 1, formatter = function(value) return tostring(value) .. " s" end })

    local anchor = U.Section(controls, "Anchoring & Position", true)
    U.Dropdown(controls, anchor, "Anchor Mode", Get("anchorMode"), Set("anchorMode"), Values({
        { text = "Free", value = "FREE" },
        { text = "Anchored", value = "ANCHORED" },
    }))

    local function PointValues()
        local values = {}
        for _, entry in ipairs(api:GetAnchorPoints() or {}) do
            values[#values + 1] = { text = entry.label or entry.name, value = entry.name }
        end
        return values
    end
    local function ParentValues()
        local values = {}
        for _, entry in ipairs(api:GetAnchorParents() or {}) do
            values[#values + 1] = { text = entry.label or entry.name, value = entry.name }
        end
        return values
    end
    U.Dropdown(controls, anchor, "Anchor From", Get("anchorFrom"), Set("anchorFrom"), PointValues,
        { disabled = IsAnchored })
    U.Dropdown(controls, anchor, "Anchor Parent", Get("anchorParent"), Set("anchorParent"), ParentValues,
        { disabled = IsAnchored, maxHeight = 420, forceSingleColumn = true })
    U.Dropdown(controls, anchor, "Anchor To", Get("anchorTo"), Set("anchorTo"), PointValues,
        { disabled = IsAnchored })
    U.Input(controls, anchor, "Manual Frame", Get("anchorParent"), Set("anchorParent"),
        { disabled = IsAnchored, maxLetters = 80 })
    U.Slider(controls, anchor, "X Offset", Get("bcdmOffsetX"), Set("bcdmOffsetX"),
        { min = -500, max = 500, step = 1, disabled = IsAnchored })
    U.Slider(controls, anchor, "Y Offset", Get("bcdmOffsetY"), Set("bcdmOffsetY"),
        { min = -500, max = 500, step = 1, disabled = IsAnchored })
    U.Checkbox(controls, anchor, "Match Anchor Width", Get("matchPowerBarWidth"), Set("matchPowerBarWidth"),
        { disabled = IsAnchored })
    U.Slider(controls, anchor, "Free X Position", Get("x"), Set("x"),
        { min = -600, max = 600, step = 5, disabled = IsFree })
    U.Slider(controls, anchor, "Free Y Position", Get("y"), Set("y"),
        { min = -400, max = 400, step = 5, disabled = IsFree })

    local size = U.Section(controls, "Size", true)
    local function WidthDisabled()
        return api:GetOption("anchorMode") ~= "FREE" and api:GetOption("matchPowerBarWidth") == true
    end
    U.Slider(controls, size, "Width", Get("width"), Set("width"),
        { min = 140, max = 420, step = 10, disabled = WidthDisabled })
    U.Slider(controls, size, "Height", Get("height"), Set("height"), { min = 10, max = 32, step = 1 })

    local minimap = U.Section(controls, "Minimap Button", true)
    U.Checkbox(controls, minimap, "Show Minimap Button",
        function() return api:GetOption("minimap.hide") ~= true end,
        function(value) api:SetOption("minimap.hide", value ~= true) Refresh() end)
    U.Slider(controls, minimap, "Button Angle", Get("minimap.angle"), Set("minimap.angle"),
        { min = 0, max = 359, step = 1, formatter = function(value) return tostring(value) .. "°" end })

    local profiles = U.Section(controls, "Character Profiles", true)
    local function ProfileValues()
        local values = {}
        local current = api:GetCurrentCharacterKey()
        for _, key in ipairs(api:GetCharacterKeys() or {}) do
            if key ~= current then values[#values + 1] = { text = key, value = key } end
        end
        if not copySource or copySource == current then copySource = values[1] and values[1].value end
        return values
    end
    U.Dropdown(controls, profiles, "Copy Configuration From",
        function() return copySource end, function(value) copySource = value end, ProfileValues,
        { disabled = function() return #ProfileValues() == 0 end, maxHeight = 360, forceSingleColumn = true })
    U.Buttons(controls, profiles, {{
        text = "Copy Configuration", width = 190,
        click = function() if copySource then api:CopyProfile(copySource) Refresh() end end,
    }}, { disabled = function() return not copySource end })

    local actions = U.Section(controls, "Actions", true)
    U.Buttons(controls, actions, {
        { text = "Reset Free Position", width = 180, click = function() api:ResetPosition() Refresh() end },
        { text = "Clear Tracked Damage", width = 190, click = function() api:ClearDamage() end },
        { text = "Open Native LDT Options", width = 210, click = function() api:OpenOptions() end },
    })

    local highlightKey = "LafeeDamageTrackerSettingsOverlay"
    panel.RefreshSettingsHighlight = function()
        local tracker = api:GetTrackerFrame()
        if panel:IsShown() and tracker and api:GetOption("shown") then
            BCDM:ShowSettingsHighlight(highlightKey, tracker)
        else
            BCDM:HideSettingsHighlight(highlightKey)
        end
    end
    panel:HookScript("OnShow", function() api:Refresh() panel.RefreshSettingsHighlight() end)
    panel:HookScript("OnHide", function() BCDM:HideSettingsHighlight(highlightKey) end)
    return panel
end
