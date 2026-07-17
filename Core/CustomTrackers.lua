local _, BCDM = ...

local SCHEMA_VERSION = 1
local LEGACY_VIEWERS = {
    { key = "Custom", name = "Custom Cooldowns", entries = "Spells", sourceType = "spell", frame = "BCDM_CustomCooldownViewer" },
    { key = "AdditionalCustom", name = "Additional Custom", entries = "Spells", sourceType = "spell", frame = "BCDM_AdditionalCustomCooldownViewer" },
    { key = "Item", name = "Custom Items", entries = "Items", sourceType = "item", frame = "BCDM_CustomItemBar" },
    { key = "ItemSpell", name = "Items & Spells", entries = "ItemsSpells", frame = "BCDM_CustomItemSpellBar" },
}

local function Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[Copy(key, seen)] = Copy(child, seen)
    end
    return result
end

local function NewStore()
    return {
        SchemaVersion = SCHEMA_VERSION,
        NextBarID = 1,
        NextEntryID = 1,
        BarOrder = {},
        Bars = {},
    }
end

local function NormalizeOrder(order, records)
    local normalized, seen = {}, {}
    for _, id in ipairs(type(order) == "table" and order or {}) do
        if records[id] and not seen[id] then
            normalized[#normalized + 1] = id
            seen[id] = true
        end
    end
    local missing = {}
    for id in pairs(records) do
        if not seen[id] then missing[#missing + 1] = id end
    end
    table.sort(missing)
    for _, id in ipairs(missing) do normalized[#normalized + 1] = id end
    return normalized
end

local function GetTrackerStore(profile)
    if type(profile) ~= "table" then return end
    profile.CooldownManager = type(profile.CooldownManager) == "table" and profile.CooldownManager or {}
    local store = profile.CooldownManager.CustomTrackers
    if type(store) ~= "table" then
        store = NewStore()
        profile.CooldownManager.CustomTrackers = store
    end
    store.Bars = type(store.Bars) == "table" and store.Bars or {}
    store.BarOrder = NormalizeOrder(store.BarOrder, store.Bars)
    store.NextBarID = math.max(tonumber(store.NextBarID) or 1, 1)
    store.NextEntryID = math.max(tonumber(store.NextEntryID) or 1, 1)
    store.SchemaVersion = tonumber(store.SchemaVersion) or 0
    return store
end

local function AllocateID(store, field, records)
    local id = math.max(tonumber(store[field]) or 1, 1)
    while records[id] do id = id + 1 end
    store[field] = id + 1
    return id
end

local function AllocateEntryID(store)
    local id = math.max(tonumber(store.NextEntryID) or 1, 1)
    local function InUse(candidate)
        for _, bar in pairs(store.Bars) do
            if bar.Entries and bar.Entries[candidate] then return true end
        end
        return false
    end
    while InUse(id) do id = id + 1 end
    store.NextEntryID = id + 1
    return id
end

local function CopyAppearance(legacy)
    local bar = {}
    for key, value in pairs(legacy) do
        if key ~= "Spells" and key ~= "Items" and key ~= "ItemsSpells" then
            bar[key] = Copy(value)
        end
    end
    bar.Enabled = legacy.Enabled ~= false
    bar.UseSharedVisibility = legacy.UseSharedVisibility ~= false
    bar.Visibility = Copy(legacy.Visibility or (BCDM.NewVisibilityPolicy and BCDM:NewVisibilityPolicy()))
    bar.EntryOrder = {}
    bar.Entries = {}
    return bar
end

local function EntrySort(a, b)
    local ai = tonumber(a.data and a.data.layoutIndex) or math.huge
    local bi = tonumber(b.data and b.data.layoutIndex) or math.huge
    if ai == bi then
        if a.sourceType == b.sourceType then return tonumber(a.sourceID) < tonumber(b.sourceID) end
        return a.sourceType < b.sourceType
    end
    return ai < bi
end

local function CollectSpellEntries(legacy)
    local merged = {}
    for classToken, specs in pairs(type(legacy.Spells) == "table" and legacy.Spells or {}) do
        for specToken, spells in pairs(type(specs) == "table" and specs or {}) do
            for spellID, data in pairs(type(spells) == "table" and spells or {}) do
                spellID = tonumber(spellID)
                if spellID then
                    local entry = merged[spellID]
                    if not entry then
                        entry = { sourceType = "spell", sourceID = spellID, data = Copy(type(data) == "table" and data or {}) }
                        entry.data.classSpecFilters = {}
                        merged[spellID] = entry
                    end
                    entry.data.classSpecFilters[tostring(classToken):upper() .. ":" .. tostring(specToken):upper()] = true
                    if tonumber(data and data.layoutIndex) and tonumber(data.layoutIndex) < (tonumber(entry.data.layoutIndex) or math.huge) then
                        entry.data.layoutIndex = tonumber(data.layoutIndex)
                    end
                    if data and data.isActive ~= false then entry.data.isActive = true end
                end
            end
        end
    end
    local entries = {}
    for _, entry in pairs(merged) do entries[#entries + 1] = entry end
    table.sort(entries, EntrySort)
    return entries
end

local function CollectFlatEntries(legacy, field, fallbackType)
    local entries = {}
    for sourceID, data in pairs(type(legacy[field]) == "table" and legacy[field] or {}) do
        sourceID = tonumber(sourceID)
        if sourceID then
            data = Copy(type(data) == "table" and data or {})
            entries[#entries + 1] = {
                sourceType = data.entryType or fallbackType,
                sourceID = sourceID,
                data = data,
            }
        end
    end
    table.sort(entries, EntrySort)
    return entries
end

local function AddMigratedEntry(store, bar, legacyEntry)
    local entryID = AllocateEntryID(store)
    local data = legacyEntry.data or {}
    bar.Entries[entryID] = {
        ID = entryID,
        Enabled = data.isActive ~= false,
        DisplayMode = "ALWAYS",
        VisualMode = "FULL",
        Alpha = 0.45,
        Tooltip = true,
        Glow = "NONE",
        ClassSpecFilters = Copy(data.classSpecFilters),
        FilterClass = data.filterClass,
        Source = {
            Type = legacyEntry.sourceType,
            ID = legacyEntry.sourceID,
        },
    }
    bar.EntryOrder[#bar.EntryOrder + 1] = entryID
end

local function HasEntries(entries)
    return type(entries) == "table" and #entries > 0
end

function BCDM:NewCustomTrackerStore()
    return NewStore()
end

function BCDM:GetCustomTrackerStore(profile)
    return GetTrackerStore(profile or (self.db and self.db.profile))
end

function BCDM:MigrateCustomTrackerProfile(profile)
    if type(profile) ~= "table" then return false end
    local store = GetTrackerStore(profile)
    if store.SchemaVersion >= SCHEMA_VERSION and store.LegacyMigrated then return false end

    local cooldownManager = profile.CooldownManager
    local pending, frameMap = {}, {}
    for _, descriptor in ipairs(LEGACY_VIEWERS) do
        local legacy = cooldownManager[descriptor.key]
        if type(legacy) == "table" then
            local entries = descriptor.entries == "Spells" and CollectSpellEntries(legacy)
                or CollectFlatEntries(legacy, descriptor.entries, descriptor.sourceType)
            if HasEntries(entries) then
                pending[#pending + 1] = { descriptor = descriptor, legacy = legacy, entries = entries }
            end
        end
    end

    for _, migration in ipairs(pending) do
        local barID = AllocateID(store, "NextBarID", store.Bars)
        local bar = CopyAppearance(migration.legacy)
        bar.ID = barID
        bar.Name = migration.descriptor.name
        store.Bars[barID] = bar
        store.BarOrder[#store.BarOrder + 1] = barID
        frameMap[migration.descriptor.frame] = "BCDM_CustomTrackerBar_" .. barID
        for _, legacyEntry in ipairs(migration.entries) do AddMigratedEntry(store, bar, legacyEntry) end
    end

    for _, barID in ipairs(store.BarOrder) do
        local bar = store.Bars[barID]
        if bar and type(bar.Layout) == "table" and frameMap[bar.Layout[2]] then
            bar.Layout[2] = frameMap[bar.Layout[2]]
        end
    end

    store.SchemaVersion = SCHEMA_VERSION
    store.LegacyMigrated = true
    store.BarOrder = NormalizeOrder(store.BarOrder, store.Bars)
    for _, descriptor in ipairs(LEGACY_VIEWERS) do cooldownManager[descriptor.key] = nil end
    return #pending > 0
end

function BCDM:MigrateCustomTrackerProfiles(db)
    local profiles = db and db.sv and db.sv.profiles
    if type(profiles) ~= "table" then return end
    for _, profile in pairs(profiles) do
        self:MigrateCustomTrackerProfile(profile)
    end
end

function BCDM:AddCustomTrackerBar(name)
    local store = self:GetCustomTrackerStore()
    local id = AllocateID(store, "NextBarID", store.Bars)
    store.Bars[id] = {
        ID = id,
        Name = (type(name) == "string" and name ~= "") and name or ("Tracker Bar " .. id),
        Enabled = true,
        UseSharedVisibility = true,
        Visibility = self.NewVisibilityPolicy and self:NewVisibilityPolicy() or nil,
        IconSize = 38,
        IconWidth = 38,
        IconHeight = 38,
        KeepAspectRatio = true,
        FrameStrata = "LOW",
        Layout = { "CENTER", "NONE", "CENTER", 0, 0 },
        Spacing = 1,
        GrowthDirection = "RIGHT",
        Columns = 0,
        Text = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 2 } },
        EntryOrder = {},
        Entries = {},
    }
    store.BarOrder[#store.BarOrder + 1] = id
    return id
end

function BCDM:RenameCustomTrackerBar(barID, name)
    local bar = self:GetCustomTrackerStore().Bars[barID]
    if not bar or type(name) ~= "string" or name == "" then return false end
    bar.Name = name
    return true
end

function BCDM:MoveCustomTrackerBar(barID, direction)
    local store = self:GetCustomTrackerStore()
    for index, id in ipairs(store.BarOrder) do
        if id == barID then
            local target = index + direction
            if target < 1 or target > #store.BarOrder then return false end
            store.BarOrder[index], store.BarOrder[target] = store.BarOrder[target], store.BarOrder[index]
            return true
        end
    end
    return false
end

function BCDM:DuplicateCustomTrackerBar(barID)
    local store = self:GetCustomTrackerStore()
    local source = store.Bars[barID]
    if not source then return end
    local copyID = self:AddCustomTrackerBar((source.Name or "Tracker Bar") .. " Copy")
    local duplicate = Copy(source)
    duplicate.ID, duplicate.Name, duplicate.Entries, duplicate.EntryOrder = copyID, store.Bars[copyID].Name, {}, {}
    for _, entryID in ipairs(source.EntryOrder or {}) do
        local entry = source.Entries and source.Entries[entryID]
        if entry then
            local newEntryID = AllocateEntryID(store)
            duplicate.Entries[newEntryID] = Copy(entry)
            duplicate.Entries[newEntryID].ID = newEntryID
            duplicate.EntryOrder[#duplicate.EntryOrder + 1] = newEntryID
        end
    end
    store.Bars[copyID] = duplicate
    return copyID
end

function BCDM:DeleteCustomTrackerBar(barID)
    local store = self:GetCustomTrackerStore()
    if not store.Bars[barID] then return false end
    store.Bars[barID] = nil
    store.BarOrder = NormalizeOrder(store.BarOrder, store.Bars)
    local deletedFrame = "BCDM_CustomTrackerBar_" .. barID
    for _, bar in pairs(store.Bars) do
        if type(bar.Layout) == "table" and bar.Layout[2] == deletedFrame then bar.Layout[2] = "NONE" end
    end
    return true
end

function BCDM:WouldCustomTrackerAnchorCycle(barID, targetBarID)
    if not targetBarID then return false end
    if barID == targetBarID then return true end
    local bars, seen = self:GetCustomTrackerStore().Bars, {}
    local current = targetBarID
    while current and not seen[current] do
        if current == barID then return true end
        seen[current] = true
        local bar = bars[current]
        local parent = bar and bar.Layout and bar.Layout[2]
        current = type(parent) == "string" and tonumber(parent:match("^BCDM_CustomTrackerBar_(%d+)$")) or nil
    end
    return current ~= nil
end

function BCDM:AddCustomTrackerEntry(barID, sourceType, sourceID, extra)
    local store = self:GetCustomTrackerStore()
    local bar = store.Bars[barID]
    if not bar or type(sourceType) ~= "string" then return end
    local entryID = AllocateEntryID(store)
    bar.Entries[entryID] = {
        ID = entryID,
        Enabled = true,
        DisplayMode = "ALWAYS",
        VisualMode = "FULL",
        Alpha = 0.45,
        Tooltip = true,
        Glow = "NONE",
        ClassSpecFilters = extra and Copy(extra.ClassSpecFilters),
        FilterClass = extra and extra.FilterClass,
        Source = { Type = sourceType, ID = tonumber(sourceID), Duration = extra and tonumber(extra.Duration) },
    }
    bar.EntryOrder[#bar.EntryOrder + 1] = entryID
    return entryID
end

function BCDM:ShouldDisplayCustomTrackerEntry(entry, state)
    if type(entry) ~= "table" or entry.Enabled == false then return false end
    local mode = entry.DisplayMode or "ALWAYS"
    if mode == "READY" then return state and state.ready == true end
    if mode == "ACTIVE" then return state and state.active == true end
    return true
end

function BCDM:ShouldGlowCustomTrackerEntry(entry, state)
    if type(entry) ~= "table" or type(state) ~= "table" then return false end
    if entry.Glow == "READY" then return state.ready == true end
    if entry.Glow == "ACTIVE" then return state.active == true end
    return false
end

function BCDM:MoveCustomTrackerEntry(barID, entryID, direction)
    local bar = self:GetCustomTrackerStore().Bars[barID]
    if not bar then return false end
    for index, id in ipairs(bar.EntryOrder) do
        if id == entryID then
            local target = index + direction
            if target < 1 or target > #bar.EntryOrder then return false end
            bar.EntryOrder[index], bar.EntryOrder[target] = bar.EntryOrder[target], bar.EntryOrder[index]
            return true
        end
    end
    return false
end

function BCDM:DeleteCustomTrackerEntry(barID, entryID)
    local bar = self:GetCustomTrackerStore().Bars[barID]
    if not bar or not bar.Entries[entryID] then return false end
    bar.Entries[entryID] = nil
    bar.EntryOrder = NormalizeOrder(bar.EntryOrder, bar.Entries)
    return true
end
