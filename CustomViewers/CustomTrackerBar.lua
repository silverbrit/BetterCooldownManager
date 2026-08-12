local _, BCDM = ...

local Runtime = {
    Containers = {},
    Icons = {},
    IconPool = {},
    PendingRefresh = false,
    TimerStates = setmetatable({}, { __mode = "k" }),
}
BCDM.CustomTrackerRuntime = Runtime
local UNKNOWN_ICON = 134400
local requestedItemData = {}

local function RequestItemDataOnce(itemID)
    if type(itemID) ~= "number" or BCDM:IsSecretValue(itemID) or requestedItemData[itemID] then return end
    requestedItemData[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

function BCDM:RequestCustomTrackerItemData(itemID)
    RequestItemDataOnce(itemID)
end

local function ResolveItemIcon(itemID, loadedIcon)
    local candidates = { loadedIcon }
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok then candidates[#candidates + 1] = icon end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, itemID)
        if ok then candidates[#candidates + 1] = icon end
    end
    for _, icon in ipairs(candidates) do
        if type(icon) == "number" and not BCDM:IsSecretValue(icon) and icon ~= UNKNOWN_ICON then return icon end
    end
    return UNKNOWN_ICON
end

local function ReadNumber(value)
    if type(value) ~= "number" or BCDM:IsSecretValue(value) then return end
    return value
end

local function ReadField(object, key)
    if object == nil then return end
    local ok, value = pcall(function() return object[key] end)
    if not ok or BCDM:IsSecretValue(value) then return end
    return value
end

local function SetDesaturated(texture, value)
    if texture.SetDesaturation then texture:SetDesaturation(value and 1 or 0)
    elseif texture.SetDesaturated then texture:SetDesaturated(value == true) end
end

local function ClearCooldown(cooldown)
    if C_DurationUtil and C_DurationUtil.CreateDuration and cooldown.SetCooldownFromDurationObject then
        cooldown:SetCooldownFromDurationObject(C_DurationUtil.CreateDuration(), true)
    else
        cooldown:Clear()
    end
end

local SourceAdapters = {}
BCDM.CustomTrackerSourceAdapters = SourceAdapters

SourceAdapters.spell = {
    GetMetadata = function(source)
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(source.ID)
        if not info then return end
        return info.name, info.iconID
    end,
    IsAvailable = function(source)
        return C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(source.ID) == true
    end,
    GetState = function(source)
        local charges = C_Spell.GetSpellCharges(source.ID)
        local cooldown = C_Spell.GetSpellCooldown(source.ID)
        local state = { count = nil, active = nil, ready = nil, durationObject = nil }
        local maxCharges = ReadNumber(ReadField(charges, "maxCharges"))
        if maxCharges and maxCharges > 1 then
            state.count = ReadNumber(ReadField(charges, "currentCharges"))
            state.ready = state.count and state.count > 0 or nil
            state.active = state.count and state.count <= 0 or nil
            state.durationObject = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(source.ID)
            return state
        end
        local isOnGCD = ReadField(cooldown, "isOnGCD")
        if isOnGCD == true then
            state.active, state.ready = false, true
        else
            local startTime = ReadNumber(ReadField(cooldown, "startTime"))
            local duration = ReadNumber(ReadField(cooldown, "duration"))
            if startTime and duration then
                state.active = startTime > 0 and duration > 0
                state.ready = not state.active
            end
        end
        state.durationObject = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(source.ID)
        return state
    end,
    SetTooltip = function(source, tooltip) tooltip:SetSpellByID(source.ID) end,
}

SourceAdapters.item = {
    GetMetadata = function(source)
        if not (C_Item and C_Item.GetItemInfo) then return end
        local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(source.ID)
        icon = ResolveItemIcon(source.ID, icon)
        if not name or icon == UNKNOWN_ICON then RequestItemDataOnce(source.ID) end
        return name or ("Item " .. tostring(source.ID)), icon
    end,
    IsAvailable = function(source)
        return C_Item and (not C_Item.DoesItemExistByID or C_Item.DoesItemExistByID(source.ID) == true)
    end,
    GetState = function(source)
        local count = C_Item.GetItemCount(source.ID)
        local startTime, duration = C_Item.GetItemCooldown(source.ID)
        startTime, duration = ReadNumber(startTime), ReadNumber(duration)
        local state = { count = ReadNumber(count), active = nil, ready = nil }
        if startTime and duration then
            state.active = startTime > 0 and duration > 0
            state.ready = not state.active
            if state.active and C_DurationUtil and C_DurationUtil.CreateDuration then
                state.durationObject = C_DurationUtil.CreateDuration()
                state.durationObject:SetTimeFromStart(startTime, duration)
            end
        end
        return state
    end,
    SetTooltip = function(source, tooltip) tooltip:SetItemByID(source.ID) end,
}

SourceAdapters.equipment = {
    GetMetadata = function(source)
        local itemID = GetInventoryItemID("player", source.ID)
        if not itemID then return end
        local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
        icon = ResolveItemIcon(itemID, icon)
        if not name or icon == UNKNOWN_ICON then RequestItemDataOnce(itemID) end
        return name or ("Equipment Slot " .. tostring(source.ID)), icon
    end,
    IsAvailable = function(source) return GetInventoryItemID("player", source.ID) ~= nil end,
    GetState = function(source)
        local startTime, duration = GetInventoryItemCooldown("player", source.ID)
        startTime, duration = ReadNumber(startTime), ReadNumber(duration)
        local state = { active = nil, ready = nil }
        if startTime and duration then
            state.active = startTime > 0 and duration > 0
            state.ready = not state.active
            if state.active and C_DurationUtil and C_DurationUtil.CreateDuration then
                state.durationObject = C_DurationUtil.CreateDuration()
                state.durationObject:SetTimeFromStart(startTime, duration)
            end
        end
        return state
    end,
    SetTooltip = function(source, tooltip) tooltip:SetInventoryItem("player", source.ID) end,
}

SourceAdapters.timer = {
    GetMetadata = function(source)
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(source.ID)
        if not info then return end
        return info.name, info.iconID
    end,
    IsAvailable = function(source) return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(source.ID) ~= nil end,
    GetState = function(source, entry)
        local expiration = Runtime.TimerStates[entry]
        local now = GetTime()
        if not expiration or expiration <= now then
            Runtime.TimerStates[entry] = nil
            return { active = false, ready = true }
        end
        local duration = tonumber(source.Duration) or 0
        local state = { active = true, ready = false }
        if duration > 0 and C_DurationUtil and C_DurationUtil.CreateDuration then
            state.durationObject = C_DurationUtil.CreateDuration()
            state.durationObject:SetTimeFromStart(expiration - duration, duration)
        end
        return state
    end,
    SetTooltip = function(source, tooltip) tooltip:SetSpellByID(source.ID) end,
}

function BCDM:RegisterCustomTrackerSourceAdapter(sourceType, adapter)
    if type(sourceType) ~= "string" or type(adapter) ~= "table" then return false end
    if type(adapter.GetMetadata) ~= "function" or type(adapter.GetState) ~= "function" then return false end
    SourceAdapters[sourceType] = adapter
    return true
end

local function PlayerMatchesFilters(entry)
    local classToken = select(2, UnitClass("player"))
    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then specID, specName = GetSpecializationInfo(specIndex) end
    return BCDM:EntryMatchesSpecialization(entry, specID, classToken, specName)
end

local function AcquireIcon(barID, entryID, container)
    Runtime.Icons[barID] = Runtime.Icons[barID] or {}
    local icon = Runtime.Icons[barID][entryID]
    if icon then return icon end
    icon = table.remove(Runtime.IconPool)
    if not icon then
        icon = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        icon.Icon = icon:CreateTexture(nil, "BACKGROUND")
        icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        icon.Cooldown:SetAllPoints(icon)
        icon.Cooldown:SetDrawEdge(false)
        icon.Cooldown:SetDrawBling(false)
        icon.Cooldown:SetDrawSwipe(true)
        icon.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
        icon.Count = icon:CreateFontString(nil, "OVERLAY")
        icon:SetScript("OnEnter", function(self)
            if not self.Entry or not self.EntryStyle or self.EntryStyle.Tooltip == false
                or not self.Adapter or not self.Adapter.SetTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            self.Adapter.SetTooltip(self.Entry.Source, GameTooltip)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    icon:SetParent(container)
    icon:EnableMouse(true)
    Runtime.Icons[barID][entryID] = icon
    return icon
end

local function ReleaseUnusedIcons(barID, used)
    local icons = Runtime.Icons[barID]
    if not icons then return end
    for entryID, icon in pairs(icons) do
        if not used[entryID] then
            BCDM:StopCustomGlow(icon)
            icon:Hide()
            if BCDM:HasCustomTrackerAuraDisplay(icon) then
                BCDM:HideCustomTrackerAuraDisplay(icon)
            else
                icon.Entry, icon.EntryStyle, icon.Adapter, icon.LastState = nil, nil, nil, nil
                icons[entryID] = nil
                Runtime.IconPool[#Runtime.IconPool + 1] = icon
            end
        end
    end
end

local function ConfigureIcon(icon, bar, entry, adapter, width, height)
    local general = BCDM.db.profile.General
    local cooldownGeneral = BCDM.db.profile.CooldownManager.General
    local border = cooldownGeneral.BorderSize or 0
    local _, texture = adapter.GetMetadata(entry.Source)
    icon.Entry, icon.EntryStyle, icon.Adapter = entry, BCDM:GetCustomTrackerEntrySettings(bar, entry), adapter
    icon:SetSize(width, height)
    icon:SetFrameStrata(bar.FrameStrata or "LOW")
    icon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = border,
        insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    icon:SetBackdropColor(0, 0, 0, 0)
    icon:SetBackdropBorderColor(0, 0, 0, border > 0 and 1 or 0)
    icon.Icon:ClearAllPoints()
    icon.Icon:SetPoint("TOPLEFT", border, -border)
    icon.Icon:SetPoint("BOTTOMRIGHT", -border, border)
    icon.Icon:SetTexture(texture or UNKNOWN_ICON)
    BCDM:ApplyIconTexCoord(icon.Icon, width, height, (cooldownGeneral.IconZoom or 0) * 0.5)
    local text = bar.Text or {}
    local layout = text.Layout or { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
    icon.Count:ClearAllPoints()
    icon.Count:SetPoint(layout[1], icon, layout[2], layout[3], layout[4])
    icon.Count:SetFont(BCDM.Media.Font, text.FontSize or 12, general.Fonts.FontFlag)
    local colour = text.Colour or { 1, 1, 1 }
    icon.Count:SetTextColor(colour[1], colour[2], colour[3], 1)
    BCDM:EnsureCustomTrackerAuraDisplay(icon, entry, bar)
end

local function UpdateIconState(icon, state)
    if not state then return end
    if icon.LastState then
        if state.active == nil then state.active = icon.LastState.active end
        if state.ready == nil then state.ready = icon.LastState.ready end
    end
    icon.LastState = state
    if state.durationObject and icon.Cooldown.SetCooldownFromDurationObject then
        icon.Cooldown:SetCooldownFromDurationObject(state.durationObject, true)
    elseif state.active == false then
        ClearCooldown(icon.Cooldown)
    end
    local style = icon.EntryStyle or icon.Entry
    icon.Count:SetText(style.TextEnabled ~= false and state.count and state.count > 1 and tostring(state.count) or "")
    local visualMode = style.VisualMode or "FULL"
    icon:SetAlpha(visualMode == "LOW_ALPHA" and (tonumber(style.Alpha) or 0.45) or 1)
    SetDesaturated(icon.Icon, visualMode == "DESATURATE")
    if BCDM:ShouldGlowCustomTrackerEntry(style, state) then BCDM:StartCustomGlow(icon)
    else BCDM:StopCustomGlow(icon) end
end

local function ResolveAnchor(barID, bar)
    local layout = bar.Layout or { "CENTER", "NONE", "CENTER", 0, 0 }
    local parentName = layout[2]
    local targetID = type(parentName) == "string" and tonumber(parentName:match("^BCDM_CustomTrackerBar_(%d+)$"))
    if targetID and BCDM:WouldCustomTrackerAnchorCycle(barID, targetID) then parentName = "NONE" end
    local parent = BCDM:ResolveAnchorParent(parentName)
    return layout, parent
end

local function AnchorContainer(container, barID, bar)
    local layout, parent = ResolveAnchor(barID, bar)
    container:ClearAllPoints()
    local ok = pcall(container.SetPoint, container, layout[1] or "CENTER", parent,
        layout[3] or "CENTER", tonumber(layout[4]) or 0, tonumber(layout[5]) or 0)
    if not ok then
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function LayoutIcons(container, bar, icons)
    local width, height = BCDM:GetIconDimensions(bar)
    local spacing = tonumber(bar.Spacing) or 1
    local growth = bar.GrowthDirection or "RIGHT"
    local wrap = math.max(math.floor(tonumber(bar.Columns) or 0), 0)
    local lineLimit = wrap > 0 and wrap or math.max(#icons, 1)
    local horizontal = growth == "LEFT" or growth == "RIGHT"
    local columns = horizontal and math.min(#icons, lineLimit) or math.ceil(#icons / lineLimit)
    local rows = horizontal and math.ceil(#icons / lineLimit) or math.min(#icons, lineLimit)
    local totalWidth = math.max(1, columns * width + math.max(0, columns - 1) * spacing)
    local totalHeight = math.max(1, rows * height + math.max(0, rows - 1) * spacing)
    container:SetSize(totalWidth, totalHeight)
    for index, icon in ipairs(icons) do
        local line = math.floor((index - 1) / lineLimit)
        local position = (index - 1) % lineLimit
        local x, y = 0, 0
        if horizontal then
            if growth == "LEFT" then
                x = (totalWidth / 2) - (width / 2) - position * (width + spacing)
            else
                x = -(totalWidth / 2) + (width / 2) + position * (width + spacing)
            end
            y = (totalHeight / 2) - (height / 2) - line * (height + spacing)
        else
            x = -(totalWidth / 2) + (width / 2) + line * (width + spacing)
            if growth == "UP" then
                y = -(totalHeight / 2) + (height / 2) + position * (height + spacing)
            else
                y = (totalHeight / 2) - (height / 2) - position * (height + spacing)
            end
        end
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", container, "CENTER", x, y)
        icon:Show()
    end
end

local function GetContainer(barID)
    local container = Runtime.Containers[barID]
    if container then return container end
    container = CreateFrame("Frame", "BCDM_CustomTrackerBar_" .. barID, UIParent)
    container:SetSize(1, 1)
    BCDM:RegisterOwnedFrameVisibility(container, function()
        local store = BCDM:GetCustomTrackerStore()
        return store.Bars[barID]
    end, function() BCDM:RefreshCustomTrackers() end)
    Runtime.Containers[barID] = container
    return container
end

local function RefreshBar(barID, bar)
    local container = GetContainer(barID)
    container:SetFrameStrata(bar.FrameStrata or "LOW")
    AnchorContainer(container, barID, bar)
    local previewing = BCDM.CustomTrackerSettingsPreviewBarID == barID
    local used, visible = {}, {}
    for _, entryID in ipairs(bar.EntryOrder or {}) do
        local entry = bar.Entries and bar.Entries[entryID]
        local adapter = entry and entry.Source and SourceAdapters[entry.Source.Type]
        local available = entry and adapter and (not adapter.IsAvailable or adapter.IsAvailable(entry.Source))
        local settings = entry and BCDM:GetCustomTrackerEntrySettings(bar, entry)
        local eligible = previewing or (entry and entry.Enabled ~= false and PlayerMatchesFilters(settings) and available)
        if entry and adapter and eligible then
            local name = adapter.GetMetadata(entry.Source)
            if name or previewing then
                local style = settings
                local existing = Runtime.Icons[barID] and Runtime.Icons[barID][entryID]
                local state = available and (adapter.GetState(entry.Source, entry) or {}) or {}
                if existing and existing.LastState then
                    if state.active == nil then state.active = existing.LastState.active end
                    if state.ready == nil then state.ready = existing.LastState.ready end
                end
                if previewing then
                    if style.Glow == "ACTIVE" then state.active, state.ready = true, false
                    elseif style.Glow == "READY" then state.active, state.ready = false, true end
                end
                local shouldDisplay = previewing or BCDM:ShouldDisplayCustomTrackerEntry(style, state)
                if shouldDisplay or entry.Source.Type == "spell" then
                    local icon = AcquireIcon(barID, entryID, container)
                    local width, height = BCDM:GetIconDimensions(bar)
                    ConfigureIcon(icon, bar, entry, adapter, width, height)
                    UpdateIconState(icon, state)
                    if previewing and entry.Enabled == false then
                        icon:SetAlpha(math.min(icon:GetAlpha(), 0.45))
                        SetDesaturated(icon.Icon, true)
                        BCDM:StopCustomGlow(icon)
                    end
                    used[entryID] = true
                    if shouldDisplay then visible[#visible + 1] = icon else icon:Hide() end
                end
            end
        end
    end
    ReleaseUnusedIcons(barID, used)
    LayoutIcons(container, bar, visible)
    container:SetShown(bar.Enabled ~= false and #visible > 0
        and (previewing or BCDM:ShouldShowOwnedFrame(bar)))
end

function BCDM:RefreshCustomTrackers()
    local store = self:GetCustomTrackerStore()
    local active = {}
    for _, barID in ipairs(store.BarOrder or {}) do
        if store.Bars[barID] then GetContainer(barID) end
    end
    for _, barID in ipairs(store.BarOrder or {}) do
        local bar = store.Bars[barID]
        if bar then
            active[barID] = true
            RefreshBar(barID, bar)
        end
    end
    for barID, container in pairs(Runtime.Containers) do
        if not active[barID] then
            container:Hide()
            ReleaseUnusedIcons(barID, {})
        end
    end
    self:ScheduleCustomTrackerTimerRefresh()
end

function BCDM:ScheduleCustomTrackerTimerRefresh()
    local nextExpiration
    local now = GetTime()
    for entry, expiration in pairs(Runtime.TimerStates) do
        if expiration <= now then Runtime.TimerStates[entry] = nil
        elseif not nextExpiration or expiration < nextExpiration then nextExpiration = expiration end
    end
    if Runtime.TimerWakeup then Runtime.TimerWakeup:Cancel() Runtime.TimerWakeup = nil end
    if nextExpiration and C_Timer.NewTimer then
        Runtime.TimerWakeup = C_Timer.NewTimer(math.max(0.01, nextExpiration - now), function()
            Runtime.TimerWakeup = nil
            BCDM:RefreshCustomTrackers()
        end)
    end
end

function BCDM:TriggerCustomTrackerTimers(spellID)
    spellID = ReadNumber(spellID)
    if not spellID then return end
    local now = GetTime()
    local store = self:GetCustomTrackerStore()
    for _, barID in ipairs(store.BarOrder or {}) do
        local bar = store.Bars[barID]
        for _, entryID in ipairs(bar and bar.EntryOrder or {}) do
            local entry = bar.Entries and bar.Entries[entryID]
            local source = entry and entry.Source
            local duration = source and source.Type == "timer" and tonumber(source.Duration)
            if entry and entry.Enabled ~= false and source.ID == spellID and duration and duration > 0 then
                Runtime.TimerStates[entry] = now + duration
            end
        end
    end
    self:RefreshCustomTrackers()
end

function BCDM:QueueCustomTrackerRefresh()
    if Runtime.PendingRefresh then return end
    Runtime.PendingRefresh = true
    C_Timer.After(0, function()
        Runtime.PendingRefresh = false
        BCDM:RefreshCustomTrackers()
    end)
end

local function UsesCustomTrackerItemData(itemID)
    itemID = ReadNumber(itemID)
    if not itemID then return false end
    local store = BCDM:GetCustomTrackerStore()
    for _, barID in ipairs(store.BarOrder or {}) do
        local bar = store.Bars[barID]
        for _, entryID in ipairs(bar and bar.EntryOrder or {}) do
            local entry = bar.Entries and bar.Entries[entryID]
            local source = entry and entry.Source
            if source and source.Type == "item" and source.ID == itemID then return true end
            if source and source.Type == "equipment" then
                local ok, equippedItemID = pcall(GetInventoryItemID, "player", source.ID)
                if ok and ReadNumber(equippedItemID) == itemID then return true end
            end
        end
    end
    return false
end

function BCDM:SetupCustomTrackers()
    if not Runtime.EventFrame then
        local frame = CreateFrame("Frame", "BCDMCustomTrackerEventFrame")
        for _, event in ipairs({
            "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "SPELL_UPDATE_COOLDOWN",
            "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "ITEM_COUNT_CHANGED",
            "PLAYER_EQUIPMENT_CHANGED", "ITEM_DATA_LOAD_RESULT", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
        }) do frame:RegisterEvent(event) end
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        frame:SetScript("OnEvent", function(_, event, arg1, _, spellID)
            if event == "UNIT_SPELLCAST_SUCCEEDED" then BCDM:TriggerCustomTrackerTimers(spellID)
            elseif event == "ITEM_DATA_LOAD_RESULT" then
                if UsesCustomTrackerItemData(arg1) then BCDM:QueueCustomTrackerRefresh() end
            elseif event == "PLAYER_TARGET_CHANGED" then BCDM:RefreshCustomTrackerAuraUnit("target")
            elseif event == "PLAYER_REGEN_ENABLED" then BCDM:PreparePendingCustomTrackerAuraDisplays()
            else BCDM:QueueCustomTrackerRefresh() end
        end)
        Runtime.EventFrame = frame
    end
    self:RefreshCustomTrackers()
end
