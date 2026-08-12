local _, BCDM = ...

local Runtime = {
    States = setmetatable({}, { __mode = "k" }),
    TrinketStates = setmetatable({}, { __mode = "k" }),
    FailedSignatures = setmetatable({}, { __mode = "k" }),
    PendingPreparation = false,
    PendingTrinketPreparation = false,
}
BCDM.CustomTrackerAuraRuntime = Runtime

local DEFINITIONS = {
    {
        unit = "target",
        slots = {
            { key = "harmful", filter = "HARMFUL|PLAYER", priority = 3 },
            { key = "helpful", filter = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", priority = 2 },
        },
    },
    {
        unit = "player",
        slots = {
            { key = "helpful", filter = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", priority = 1 },
        },
    },
}

local function IsInCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function Call(object, methodName, ...)
    if not object then return false end
    local okRead, method = pcall(function() return object[methodName] end)
    if not okRead or type(method) ~= "function" then return false end
    return pcall(method, object, ...)
end

local function EnsureAuraContainerLoaded()
    if type(CustomAuraContainerSlotDefaultOptions) == "table" then return true end
    if IsInCombat() then return false end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return type(CustomAuraContainerSlotDefaultOptions) == "table"
end

local function ReadOverrideSpellID(source)
    if not (type(source) == "table" and C_Spell and type(C_Spell.GetOverrideSpell) == "function") then return end
    local ok, overrideSpellID = pcall(C_Spell.GetOverrideSpell, source.ID)
    if not ok or BCDM:IsSecretValue(overrideSpellID) or type(overrideSpellID) ~= "number" then return end
    return overrideSpellID
end

local function BuildCandidateFilter(source)
    local spellIDs = BCDM:BuildCustomTrackerAuraCandidateIDs(source, ReadOverrideSpellID(source))
    local includeSpellIDs, signatureParts = {}, {}
    for index, spellID in ipairs(spellIDs) do
        includeSpellIDs[spellID] = true
        signatureParts[index] = tostring(spellID)
    end
    return { includeSpellIDs = includeSpellIDs }, table.concat(signatureParts, ","), #spellIDs > 0
end

local function SetTextureDesaturated(texture, desaturated)
    if not texture then return end
    if Call(texture, "SetDesaturation", desaturated and 1 or 0) then return end
    Call(texture, "SetDesaturated", desaturated == true)
end

local function ApplyVisualStyleUnsafe(visual, icon, entry, bar)
    if type(visual) ~= "table" then return false end
    local general = BCDM.db.profile.General
    local cooldownGeneral = BCDM.db.profile.CooldownManager.General
    local border = cooldownGeneral.BorderSize or 0
    local width, height = BCDM:GetIconDimensions(bar)
    local text = bar.Text or {}
    local layout = text.Layout or { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
    local colour = text.Colour or { 1, 1, 1 }
    local style = BCDM:GetCustomTrackerEntrySettings(bar, entry)

    visual.icon:ClearAllPoints()
    visual.icon:SetPoint("TOPLEFT", visual.button, "TOPLEFT", border, -border)
    visual.icon:SetPoint("BOTTOMRIGHT", visual.button, "BOTTOMRIGHT", -border, border)
    BCDM:ApplyIconTexCoord(visual.icon, width, height, (cooldownGeneral.IconZoom or 0) * 0.5)
    SetTextureDesaturated(visual.icon, (style.VisualMode or "FULL") == "DESATURATE")

    visual.cooldown:ClearAllPoints()
    visual.cooldown:SetPoint("TOPLEFT", visual.button, "TOPLEFT", border, -border)
    visual.cooldown:SetPoint("BOTTOMRIGHT", visual.button, "BOTTOMRIGHT", -border, border)
    visual.cooldown:SetDrawEdge(false)
    visual.cooldown:SetDrawBling(false)
    visual.cooldown:SetDrawSwipe(true)
    visual.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    if visual.cooldown.SetSwipeTexture then visual.cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8") end

    visual.count:ClearAllPoints()
    visual.count:SetPoint(layout[1], visual.button, layout[2], layout[3], layout[4])
    visual.count:SetFont(BCDM.Media.Font, text.FontSize or 12, general.Fonts.FontFlag)
    visual.count:SetTextColor(colour[1], colour[2], colour[3], 1)
    visual.count:SetAlpha(style.TextEnabled ~= false and 1 or 0)

    Call(visual.button, "SetMouseMotionEnabled", style.Tooltip ~= false)
    return true
end

local function ApplyVisualStyle(visual, icon, entry, bar)
    local ok, applied = pcall(ApplyVisualStyleUnsafe, visual, icon, entry, bar)
    return ok and applied == true
end

local function InitializeAuraButton(icon, entry, bar, auraButton, container, layer, priority)
    local visual = {
        button = auraButton,
        icon = auraButton:CreateTexture(nil, "ARTWORK"),
        cooldown = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate"),
        count = auraButton:CreateFontString(nil, "OVERLAY"),
    }
    if not Call(auraButton, "ClearAllPoints")
        or not Call(auraButton, "SetAllPoints", container)
        or not Call(auraButton, "SetFrameLevel", (layer:GetFrameLevel() or 1) + priority)
        or not ApplyVisualStyle(visual, icon, entry, bar)
        or not Call(auraButton, "SetDurationCooldown", visual.cooldown)
        or not Call(auraButton, "SetIcon", visual.icon)
        or not Call(auraButton, "SetApplicationCount", visual.count, {})
    then
        return nil
    end
    return visual
end

local function CreateDisplayState(icon, entry, bar, candidateFilters, signature)
    local layer = CreateFrame("Frame", nil, icon)
    layer:SetAllPoints(icon)
    layer:SetFrameLevel((icon:GetFrameLevel() or 1) + 10)

    local state = { layer = layer, signature = signature, containers = {}, slots = {}, visuals = {}, enabled = true }
    for _, definition in ipairs(DEFINITIONS) do
        local container = CreateFrame("AuraContainer", nil, layer, "CustomAuraContainerTemplate")
        container:SetAllPoints(layer)
        container:SetUnit(definition.unit)
        for _, slot in ipairs(definition.slots) do
            local initializedVisual
            local function InitializeFrame(auraButton)
                initializedVisual = InitializeAuraButton(icon, entry, bar, auraButton, container, layer, slot.priority)
            end
            local ok, auraButton = Call(container, "AddAuraSlot", slot.key, slot.filter, {
                candidateFilters = candidateFilters,
                initializeFrame = InitializeFrame,
            })
            if not ok or not auraButton or not initializedVisual then return nil end
            state.slots[#state.slots + 1] = { container = container, key = slot.key }
            state.visuals[#state.visuals + 1] = initializedVisual
        end
        if not Call(container, "SetEnabled", true) then return nil end
        state.containers[#state.containers + 1] = { container = container, unit = definition.unit }
    end
    layer:Show()
    return state
end

local function UpdateCandidateFilters(state, candidateFilters, signature)
    if state.signature == signature then return true end
    if IsInCombat() then return false end
    for _, slot in ipairs(state.slots) do
        if not Call(slot.container, "SetAuraSlotCandidateFilters", slot.key, candidateFilters) then return false end
    end
    state.signature = signature
    return true
end

function BCDM:HasCustomTrackerAuraDisplay(icon)
    return icon and Runtime.States[icon] ~= nil
end

local function SetDisplayEnabled(state, enabled)
    if not state then return end
    state.enabled = enabled == true
    for _, containerState in ipairs(state.containers or {}) do
        Call(containerState.container, "SetEnabled", state.enabled)
    end
    if state.container then Call(state.container, "SetEnabled", state.enabled) end
end

function BCDM:HideCustomTrackerAuraDisplay(icon)
    local state = icon and Runtime.States[icon]
    if state and state.layer then
        SetDisplayEnabled(state, false)
        state.layer:Hide()
    end
end

function BCDM:EnsureCustomTrackerAuraDisplay(icon, entry, bar)
    local source = type(entry) == "table" and entry.Source
    if not (icon and type(source) == "table" and source.Type == "spell") then
        self:HideCustomTrackerAuraDisplay(icon)
        return false
    end

    local candidateFilters, signature, hasCandidates = BuildCandidateFilter(source)
    if not hasCandidates then
        self:HideCustomTrackerAuraDisplay(icon)
        return false
    end

    local state = Runtime.States[icon]
    if state then
        if not UpdateCandidateFilters(state, candidateFilters, signature) then
            self:HideCustomTrackerAuraDisplay(icon)
            Runtime.PendingPreparation = true
            return false
        end
        if IsInCombat() then
            Runtime.PendingPreparation = true
        else
            for _, visual in ipairs(state.visuals) do ApplyVisualStyle(visual, icon, entry, bar) end
        end
        SetDisplayEnabled(state, true)
        state.layer:Show()
        return true
    end

    if IsInCombat() or not EnsureAuraContainerLoaded() then
        Runtime.PendingPreparation = true
        return false
    end
    if Runtime.FailedSignatures[icon] == signature then return false end

    local ok, created = pcall(CreateDisplayState, icon, entry, bar, candidateFilters, signature)
    if not ok or not created then
        Runtime.FailedSignatures[icon] = signature
        return false
    end
    Runtime.States[icon] = created
    Runtime.FailedSignatures[icon] = nil
    Runtime.PendingPreparation = false
    return true
end

function BCDM:PreparePendingCustomTrackerAuraDisplays()
    if IsInCombat() then return end
    if Runtime.PendingPreparation then
        Runtime.PendingPreparation = false
        self:RefreshCustomTrackers()
    end
    if Runtime.PendingTrinketPreparation then
        Runtime.PendingTrinketPreparation = false
        self:UpdateTrinketBar()
    end
end

function BCDM:RefreshCustomTrackerAuraUnit(unit)
    for _, state in pairs(Runtime.States) do
        for _, containerState in ipairs(state.enabled and state.containers or {}) do
            if unit == nil or containerState.unit == unit then
                Call(containerState.container, "UpdateAllAuras")
            end
        end
    end
end

local function ApplyTrinketCountStyle(state, settings, entrySettings)
    local text = settings.Text or {}
    local layout = text.Layout or { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
    local colour = text.Colour or { 1, 1, 1 }
    local fonts = BCDM.db.profile.General.Fonts
    state.count:ClearAllPoints()
    state.count:SetPoint(layout[1], state.button, layout[2], layout[3], layout[4])
    state.count:SetFont(BCDM.Media.Font, text.FontSize or 15, fonts.FontFlag)
    state.count:SetTextColor(colour[1], colour[2], colour[3], 1)
    state.count:SetAlpha((not entrySettings or entrySettings.TextEnabled ~= false) and 1 or 0)
    if fonts.Shadow.Enabled then
        state.count:SetShadowColor(unpack(fonts.Shadow.Colour))
        state.count:SetShadowOffset(fonts.Shadow.OffsetX, fonts.Shadow.OffsetY)
    else
        state.count:SetShadowColor(0, 0, 0, 0)
        state.count:SetShadowOffset(0, 0)
    end
end

local function BuildTrinketCandidateFilters(spellIDs)
    local includeSpellIDs, signatureParts = {}, {}
    for _, spellID in ipairs(spellIDs or {}) do
        if type(spellID) == "number" and spellID > 0 and not includeSpellIDs[spellID] then
            includeSpellIDs[spellID] = true
            signatureParts[#signatureParts + 1] = tostring(spellID)
        end
    end
    return { includeSpellIDs = includeSpellIDs }, table.concat(signatureParts, ","), #signatureParts > 0
end

local function CreateTrinketCountState(icon, candidateFilters, signature, settings, entrySettings)
    local layer = CreateFrame("Frame", nil, icon)
    layer:SetAllPoints(icon)
    layer:SetFrameLevel((icon:GetFrameLevel() or 1) + 10)
    local container = CreateFrame("AuraContainer", nil, layer, "CustomAuraContainerTemplate")
    container:SetAllPoints(layer)
    container:SetUnit("player")

    local state = { layer = layer, container = container, signature = signature, enabled = true }
    local initialized
    local function InitializeFrame(auraButton)
        state.button = auraButton
        state.count = auraButton:CreateFontString(nil, "OVERLAY")
        if not Call(auraButton, "SetAllPoints", container)
            or not Call(auraButton, "SetFrameLevel", (layer:GetFrameLevel() or 1) + 1)
            or not Call(auraButton, "SetMouseMotionEnabled", false) then return end
        ApplyTrinketCountStyle(state, settings, entrySettings)
        initialized = Call(auraButton, "SetApplicationCount", state.count, {})
    end
    local ok, button = Call(container, "AddAuraSlot", "active", "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY", {
        candidateFilters = candidateFilters,
        initializeFrame = InitializeFrame,
    })
    if not ok or not button or not initialized or not Call(container, "SetEnabled", true) then return end
    layer:Show()
    return state
end

function BCDM:HideTrinketAuraCountDisplay(icon)
    local state = icon and Runtime.TrinketStates[icon]
    if state then
        SetDisplayEnabled(state, false)
        state.layer:Hide()
    end
end

function BCDM:EnsureTrinketAuraCountDisplay(icon, spellIDs, settings, entrySettings)
    local candidateFilters, signature, hasCandidates = BuildTrinketCandidateFilters(spellIDs)
    if not icon or not hasCandidates then
        self:HideTrinketAuraCountDisplay(icon)
        return false
    end

    local state = Runtime.TrinketStates[icon]
    if state then
        if state.signature ~= signature then
            if IsInCombat() then
                self:HideTrinketAuraCountDisplay(icon)
                Runtime.PendingTrinketPreparation = true
                return false
            end
            if not Call(state.container, "SetAuraSlotCandidateFilters", "active", candidateFilters) then
                self:HideTrinketAuraCountDisplay(icon)
                return false
            end
            state.signature = signature
        end
        if IsInCombat() then
            Runtime.PendingTrinketPreparation = true
        else
            ApplyTrinketCountStyle(state, settings, entrySettings)
        end
        SetDisplayEnabled(state, true)
        state.layer:Show()
        return true
    end

    if IsInCombat() or not EnsureAuraContainerLoaded() then
        Runtime.PendingTrinketPreparation = true
        return false
    end
    local ok, created = pcall(CreateTrinketCountState, icon, candidateFilters, signature, settings, entrySettings)
    if not ok or not created then return false end
    Runtime.TrinketStates[icon] = created
    return true
end
