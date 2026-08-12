local _, BCDM = ...

local SCHEMA_VERSION = 3
local DEFAULT_ENTRY_SETTINGS = {
    DisplayMode = "ALWAYS",
    VisualMode = "FULL",
    Alpha = 0.45,
    Glow = "NONE",
    TextEnabled = true,
    Tooltip = true,
}
local LEGACY_SPEC_IDS = {
    ["MAGE:ARCANE"] = 62, ["MAGE:FIRE"] = 63, ["MAGE:FROST"] = 64,
    ["PALADIN:HOLY"] = 65, ["PALADIN:PROTECTION"] = 66, ["PALADIN:RETRIBUTION"] = 70,
    ["WARRIOR:ARMS"] = 71, ["WARRIOR:FURY"] = 72, ["WARRIOR:PROTECTION"] = 73,
    ["DRUID:BALANCE"] = 102, ["DRUID:FERAL"] = 103, ["DRUID:GUARDIAN"] = 104, ["DRUID:RESTORATION"] = 105,
    ["DEATHKNIGHT:BLOOD"] = 250, ["DEATHKNIGHT:FROST"] = 251, ["DEATHKNIGHT:UNHOLY"] = 252,
    ["HUNTER:BEASTMASTERY"] = 253, ["HUNTER:MARKSMANSHIP"] = 254, ["HUNTER:SURVIVAL"] = 255,
    ["PRIEST:DISCIPLINE"] = 256, ["PRIEST:HOLY"] = 257, ["PRIEST:SHADOW"] = 258,
    ["ROGUE:ASSASSINATION"] = 259, ["ROGUE:OUTLAW"] = 260, ["ROGUE:SUBTLETY"] = 261,
    ["SHAMAN:ELEMENTAL"] = 262, ["SHAMAN:ENHANCEMENT"] = 263, ["SHAMAN:RESTORATION"] = 264,
    ["WARLOCK:AFFLICTION"] = 265, ["WARLOCK:DEMONOLOGY"] = 266, ["WARLOCK:DESTRUCTION"] = 267,
    ["MONK:BREWMASTER"] = 268, ["MONK:WINDWALKER"] = 269, ["MONK:MISTWEAVER"] = 270,
    ["DEMONHUNTER:HAVOC"] = 577, ["DEMONHUNTER:VENGEANCE"] = 581, ["DEMONHUNTER:DEVOURER"] = 1480,
    ["EVOKER:DEVASTATION"] = 1467, ["EVOKER:PRESERVATION"] = 1468, ["EVOKER:AUGMENTATION"] = 1473,
}
local LEGACY_VIEWERS = {
    { key = "Custom", name = "Custom Cooldowns", entries = "Spells", sourceType = "spell", frame = "BCDM_CustomCooldownViewer" },
    { key = "AdditionalCustom", name = "Additional Custom", entries = "Spells", sourceType = "spell", frame = "BCDM_AdditionalCustomCooldownViewer" },
    { key = "Item", name = "Custom Items", entries = "Items", sourceType = "item", frame = "BCDM_CustomItemBar" },
    { key = "ItemSpell", name = "Items & Spells", entries = "ItemsSpells", frame = "BCDM_CustomItemSpellBar" },
}

local function NormalizeAuraIDs(value)
    local normalized, seen = {}, {}
    local function Add(candidate)
        candidate = tonumber(candidate)
        if candidate and candidate > 0 and candidate == math.floor(candidate) and not seen[candidate] then
            normalized[#normalized + 1] = candidate
            seen[candidate] = true
        end
    end
    if type(value) == "string" then
        for candidate in value:gmatch("[^,%s]+") do Add(candidate) end
    elseif type(value) == "table" then
        for _, candidate in ipairs(value) do Add(candidate) end
    end
    return normalized
end

function BCDM:NormalizeCustomTrackerAuraIDs(value)
    return NormalizeAuraIDs(value)
end

function BCDM:BuildCustomTrackerAuraCandidateIDs(source, overrideSpellID)
    local candidates, seen = {}, {}
    local function Add(candidate)
        candidate = tonumber(candidate)
        if candidate and candidate > 0 and candidate == math.floor(candidate) and not seen[candidate] then
            candidates[#candidates + 1] = candidate
            seen[candidate] = true
        end
    end
    if type(source) == "table" and source.Type == "spell" then
        Add(source.ID)
        Add(overrideSpellID)
        for _, candidate in ipairs(NormalizeAuraIDs(source.AuraIDs)) do Add(candidate) end
    end
    return candidates
end

local function NormalizeStoreAuraIDs(store)
    local changed = false
    for _, bar in pairs(store.Bars or {}) do
        for _, entry in pairs(type(bar.Entries) == "table" and bar.Entries or {}) do
            local source = type(entry) == "table" and entry.Source
            if type(source) == "table" and source.Type == "spell" and source.AuraIDs ~= nil then
                local normalized = NormalizeAuraIDs(source.AuraIDs)
                local same = type(source.AuraIDs) == "table" and #source.AuraIDs == #normalized
                if same then
                    for index, spellID in ipairs(normalized) do
                        if source.AuraIDs[index] ~= spellID then same = false break end
                    end
                end
                if not same then changed = true end
                source.AuraIDs = #normalized > 0 and normalized or nil
            end
        end
    end
    return changed
end

local function NormalizeSpecFilters(filters)
    local normalized = {}
    for specID, enabled in pairs(type(filters) == "table" and filters or {}) do
        specID = tonumber(specID)
        if enabled == true and specID and specID > 0 and specID == math.floor(specID) then
            normalized[specID] = true
        end
    end
    return normalized
end

local function SameTrueMap(left, right)
    if type(left) ~= "table" then return next(right) == nil end
    for key, enabled in pairs(left) do
        if enabled ~= true or right[key] ~= true then return false end
    end
    for key, enabled in pairs(right) do
        if enabled == true and left[key] ~= true then return false end
    end
    return true
end

local function NormalizeStoreSpecFilters(store)
    local changed = false
    for _, bar in pairs(store.Bars or {}) do
        for _, entry in pairs(type(bar.Entries) == "table" and bar.Entries or {}) do
            if type(entry) == "table" then
                local hasSpecFilters = type(entry.SpecFilters) == "table"
                local hasLegacyFilters = type(entry.ClassSpecFilters) == "table"
                local normalized = NormalizeSpecFilters(entry.SpecFilters)
                local unresolved = {}
                for legacyKey, enabled in pairs(type(entry.ClassSpecFilters) == "table" and entry.ClassSpecFilters or {}) do
                    if enabled == true then
                        local normalizedKey = tostring(legacyKey):upper():gsub("%s+", "")
                        local specID = LEGACY_SPEC_IDS[normalizedKey]
                        if specID then normalized[specID] = true else unresolved[legacyKey] = true end
                    end
                end
                if hasSpecFilters or hasLegacyFilters then
                    if not SameTrueMap(entry.SpecFilters, normalized)
                        or not SameTrueMap(entry.ClassSpecFilters, unresolved) then changed = true end
                    entry.SpecFilters = normalized
                    entry.ClassSpecFilters = next(unresolved) and unresolved or nil
                end
            end
        end
    end
    return changed
end

local function GetClassIdByToken(classToken)
    if not classToken then return end
    local count = (C_ClassInfo and C_ClassInfo.GetNumClasses and C_ClassInfo.GetNumClasses())
        or (GetNumClasses and GetNumClasses()) or 0
    for classID = 1, count do
        local info = C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(classID)
        local classFile = info and info.classFile
        if not classFile and GetClassInfo then
            local _, fallbackClassFile = GetClassInfo(classID)
            classFile = fallbackClassFile
        end
        if classFile == classToken then return classID end
    end
end

function BCDM:GetOrderedClassTokens(targetClassToken)
    local tokens, seen = {}, {}
    local target = targetClassToken and tostring(targetClassToken):upper()
    local function Add(token)
        token = token and tostring(token):upper()
        if token and (not target or token == target) and not seen[token] then
            tokens[#tokens + 1], seen[token] = token, true
        end
    end
    for _, classID in ipairs(CLASS_SORT_ORDER or {}) do
        local info = C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(classID)
        Add(info and info.classFile)
    end
    local count = (C_ClassInfo and C_ClassInfo.GetNumClasses and C_ClassInfo.GetNumClasses())
        or (GetNumClasses and GetNumClasses()) or 0
    for classID = 1, count do
        local info = C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(classID)
        local token = info and info.classFile
        if not token and GetClassInfo then
            local _, fallbackToken = GetClassInfo(classID)
            token = fallbackToken
        end
        Add(token)
    end
    Add(target)
    table.sort(tokens, function(left, right)
        local leftID, rightID = GetClassIdByToken(left), GetClassIdByToken(right)
        local leftInfo = leftID and C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(leftID)
        local rightInfo = rightID and C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(rightID)
        local leftName = leftInfo and leftInfo.className or (leftID and GetClassInfo and GetClassInfo(leftID)) or left
        local rightName = rightInfo and rightInfo.className or (rightID and GetClassInfo and GetClassInfo(rightID)) or right
        return leftName == rightName and left < right or tostring(leftName) < tostring(rightName)
    end)
    return tokens
end

function BCDM:GetClassSpecCatalog(targetClassToken)
    local catalog = {}
    for _, classToken in ipairs(self:GetOrderedClassTokens(targetClassToken)) do
        local classID = GetClassIdByToken(classToken)
        local info = classID and C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(classID)
        local classEntry = { classToken = classToken, classId = classID,
            className = info and info.className or (classID and GetClassInfo and GetClassInfo(classID)), specs = {} }
        local count = classID and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
            and C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
        for index = 1, count do
            local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classID, index)
            if type(specID) == "table" then
                local specInfo = specID
                specID, specName, specIcon = specInfo.specID or specInfo.id, specInfo.name, specInfo.icon
            end
            if specID then
                classEntry.specs[#classEntry.specs + 1] = {
                    specID = specID, specName = specName or tostring(specID), specIcon = specIcon, specIndex = index,
                }
            end
        end
        if #classEntry.specs > 0 then catalog[#catalog + 1] = classEntry end
    end
    return catalog
end

function BCDM:BuildSpecFilters(targetClassToken)
    local filters = {}
    for _, classEntry in ipairs(self:GetClassSpecCatalog(targetClassToken)) do
        for _, specEntry in ipairs(classEntry.specs) do filters[specEntry.specID] = true end
    end
    return filters
end

function BCDM:EntryMatchesSpecialization(entry, specID, classToken, specName)
    if type(entry) ~= "table" then return false end
    local filters = entry.SpecFilters
    local legacy = entry.ClassSpecFilters
    if type(filters) ~= "table" and type(legacy) ~= "table" then return true end
    if type(filters) == "table" and filters[tonumber(specID)] == true then return true end
    if type(legacy) == "table" and classToken and specName then
        local expected = tostring(classToken):upper() .. ":" .. tostring(specName):upper():gsub("%s+", "")
        for legacyKey, enabled in pairs(legacy) do
            if enabled == true and tostring(legacyKey):upper():gsub("%s+", "") == expected then return true end
        end
    end
    return false
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
            bar[key] = BCDM:CopyTable(value)
        end
    end
    bar.Enabled = legacy.Enabled ~= false
    bar.UseSharedVisibility = legacy.UseSharedVisibility ~= false
    bar.Visibility = BCDM:CopyTable(legacy.Visibility or (BCDM.NewVisibilityPolicy and BCDM:NewVisibilityPolicy()))
    bar.EntrySettings = BCDM:CopyTable(legacy.EntrySettings or DEFAULT_ENTRY_SETTINGS)
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
                        entry = { sourceType = "spell", sourceID = spellID, data = BCDM:CopyTable(type(data) == "table" and data or {}) }
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
            data = BCDM:CopyTable(type(data) == "table" and data or {})
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
        OverrideBarSettings = true,
        VisualMode = "FULL",
        Alpha = 0.45,
        Tooltip = true,
        TextEnabled = true,
        Glow = "NONE",
        ClassSpecFilters = BCDM:CopyTable(data.classSpecFilters),
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

function BCDM:GetCustomTrackerStore(profile)
    return GetTrackerStore(profile or (self.db and self.db.profile))
end

function BCDM:MigrateCustomTrackerProfile(profile)
    if type(profile) ~= "table" then return false end
    local store = GetTrackerStore(profile)
    local auraIDsChanged = NormalizeStoreAuraIDs(store)
    local specFiltersChanged = NormalizeStoreSpecFilters(store)
    if store.SchemaVersion >= SCHEMA_VERSION and store.LegacyMigrated then
        return auraIDsChanged or specFiltersChanged
    end
    local changed = store.SchemaVersion < SCHEMA_VERSION or store.LegacyMigrated ~= true
    if auraIDsChanged or specFiltersChanged then changed = true end

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

    if NormalizeStoreSpecFilters(store) then changed = true end

    store.SchemaVersion = SCHEMA_VERSION
    store.LegacyMigrated = true
    store.BarOrder = NormalizeOrder(store.BarOrder, store.Bars)
    for _, descriptor in ipairs(LEGACY_VIEWERS) do cooldownManager[descriptor.key] = nil end
    return changed or #pending > 0
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
    if type(name) ~= "string" or name == "" then
        local usedNames = {}
        for _, bar in pairs(store.Bars) do
            if type(bar) == "table" and type(bar.Name) == "string" then usedNames[bar.Name] = true end
        end
        local displayIndex = 1
        while usedNames["Tracker Bar " .. displayIndex] do displayIndex = displayIndex + 1 end
        name = "Tracker Bar " .. displayIndex
    end
    local entrySettings = BCDM:CopyTable(DEFAULT_ENTRY_SETTINGS)
    entrySettings.SpecFilters = self:BuildSpecFilters()
    store.Bars[id] = {
        ID = id,
        Name = name,
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
        EntrySettings = entrySettings,
        Text = { FontSize = 12, Colour = { 1, 1, 1 }, Layout = { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 } },
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

function BCDM:DuplicateCustomTrackerBar(barID)
    local store = self:GetCustomTrackerStore()
    local source = store.Bars[barID]
    if not source then return end
    local copyID = self:AddCustomTrackerBar((source.Name or "Tracker Bar") .. " Copy")
    local duplicate = BCDM:CopyTable(source)
    duplicate.ID, duplicate.Name, duplicate.Entries, duplicate.EntryOrder = copyID, store.Bars[copyID].Name, {}, {}
    for _, entryID in ipairs(source.EntryOrder or {}) do
        local entry = source.Entries and source.Entries[entryID]
        if entry then
            local newEntryID = AllocateEntryID(store)
            duplicate.Entries[newEntryID] = BCDM:CopyTable(entry)
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
    local auraIDs = sourceType == "spell" and NormalizeAuraIDs(extra and extra.AuraIDs) or {}
    bar.Entries[entryID] = {
        ID = entryID,
        Enabled = true,
        DisplayMode = "ALWAYS",
        OverrideBarSettings = false,
        VisualMode = "FULL",
        Alpha = 0.45,
        Tooltip = true,
        TextEnabled = true,
        Glow = "NONE",
        SpecFilters = extra and BCDM:CopyTable(extra.SpecFilters),
        FilterClass = extra and extra.FilterClass,
        Source = {
            Type = sourceType,
            ID = tonumber(sourceID),
            Duration = extra and tonumber(extra.Duration),
            AuraIDs = #auraIDs > 0 and auraIDs or nil,
        },
    }
    bar.EntryOrder[#bar.EntryOrder + 1] = entryID
    return entryID
end

function BCDM:GetCustomTrackerEntrySettings(bar, entry)
    if type(entry) == "table" and entry.OverrideBarSettings == true then return entry end
    local shared = type(bar) == "table" and bar.EntrySettings
    return type(shared) == "table" and shared or DEFAULT_ENTRY_SETTINGS
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

function BCDM:ReorderCustomTrackerEntry(barID, entryID, targetIndex)
    local bar = self:GetCustomTrackerStore().Bars[barID]
    if not bar or type(targetIndex) ~= "number" then return false end
    targetIndex = math.floor(targetIndex)
    targetIndex = math.max(1, math.min(#bar.EntryOrder, targetIndex))
    for index, id in ipairs(bar.EntryOrder) do
        if id == entryID then
            if index == targetIndex then return false end
            table.remove(bar.EntryOrder, index)
            table.insert(bar.EntryOrder, targetIndex, entryID)
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
