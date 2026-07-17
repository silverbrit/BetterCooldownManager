local _, BCDM = ...

local function NormalizeSpecName(specName)
    if not specName then return end
    return tostring(specName):gsub("%s+", ""):upper()
end

BCDM.SpecIdToToken = BCDM.SpecIdToToken or {
    [62] = "ARCANE",
    [63] = "FIRE",
    [64] = "FROST",
    [65] = "HOLY",
    [66] = "PROTECTION",
    [70] = "RETRIBUTION",
    [71] = "ARMS",
    [72] = "FURY",
    [73] = "PROTECTION",
    [102] = "BALANCE",
    [103] = "FERAL",
    [104] = "GUARDIAN",
    [105] = "RESTORATION",
    [250] = "BLOOD",
    [251] = "FROST",
    [252] = "UNHOLY",
    [253] = "BEASTMASTERY",
    [254] = "MARKSMANSHIP",
    [255] = "SURVIVAL",
    [256] = "DISCIPLINE",
    [257] = "HOLY",
    [258] = "SHADOW",
    [259] = "ASSASSINATION",
    [260] = "OUTLAW",
    [261] = "SUBTLETY",
    [262] = "ELEMENTAL",
    [263] = "ENHANCEMENT",
    [264] = "RESTORATION",
    [265] = "AFFLICTION",
    [266] = "DEMONOLOGY",
    [267] = "DESTRUCTION",
    [268] = "BREWMASTER",
    [269] = "WINDWALKER",
    [270] = "MISTWEAVER",
    [577] = "HAVOC",
    [581] = "VENGEANCE",
    [1480] = "DEVOURER",
    [1467] = "DEVASTATION",
    [1468] = "PRESERVATION",
    [1473] = "AUGMENTATION",
}

function BCDM:NormalizeSpecToken(specToken, specId, specIndex)
    local id = specId
    if not id and specIndex then
        id = GetSpecializationInfo(specIndex)
    end
    if not id and type(specToken) == "number" then
        id = specToken
    end
    if id and self.SpecIdToToken and self.SpecIdToToken[id] then
        return self.SpecIdToToken[id]
    end
    if specToken then
        return NormalizeSpecName(specToken)
    end
end

local function GetClassIdByToken(classToken)
    if not classToken then return end
    if CLASS_SORT_ORDER and C_ClassInfo and C_ClassInfo.GetClassInfo then
        for _, classId in ipairs(CLASS_SORT_ORDER) do
            local classInfo = C_ClassInfo.GetClassInfo(classId)
            if classInfo and classInfo.classFile == classToken then
                return classId
            end
        end
    end
    local numClasses = GetNumClasses()
    if numClasses then
        for classId = 1, numClasses do
            local classInfo = C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(classId)
            if classInfo and classInfo.classFile == classToken then
                return classId
            elseif GetClassInfo then
                local _, classFile = GetClassInfo(classId)
                if classFile == classToken then
                    return classId
                end
            end
        end
    end
end

local function BuildSpecNameTokenMap(classId)
    local map = {}
    if not classId then return map end
    if not (C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID and GetSpecializationInfoForClassID) then
        return map
    end
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
    if not numSpecs then return map end
    for i = 1, numSpecs do
        local specID, specName = GetSpecializationInfoForClassID(classId, i)
        if type(specID) == "table" then
            local info = specID
            specID = info.specID or info.id
            specName = info.name or specName
        end
        local token = BCDM:NormalizeSpecToken(specName, specID)
        local normalizedName = NormalizeSpecName(specName)
        if token and normalizedName then
            map[normalizedName] = token
        end
    end
    return map
end

function BCDM:GetOrderedClassTokens(targetClassToken)
    local orderedClasses = {}
    local seenClasses = {}
    local normalizedTarget = targetClassToken and tostring(targetClassToken):upper()

    local function AddClassToken(classToken)
        if not classToken then return end
        classToken = tostring(classToken):upper()
        if normalizedTarget and classToken ~= normalizedTarget then
            return
        end
        if seenClasses[classToken] then
            return
        end
        orderedClasses[#orderedClasses + 1] = classToken
        seenClasses[classToken] = true
    end

    if CLASS_SORT_ORDER and C_ClassInfo and C_ClassInfo.GetClassInfo then
        for _, classId in ipairs(CLASS_SORT_ORDER) do
            local classInfo = C_ClassInfo.GetClassInfo(classId)
            if classInfo and classInfo.classFile then
                AddClassToken(classInfo.classFile)
            end
        end
    end

    local numClasses = (C_ClassInfo and C_ClassInfo.GetNumClasses and C_ClassInfo.GetNumClasses()) or (GetNumClasses and GetNumClasses())
    if numClasses then
        for classId = 1, numClasses do
            local classInfo = C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(classId)
            if classInfo and classInfo.classFile then
                AddClassToken(classInfo.classFile)
            elseif GetClassInfo then
                local _, classFile = GetClassInfo(classId)
                AddClassToken(classFile)
            end
        end
    end

    if normalizedTarget and not seenClasses[normalizedTarget] then
        AddClassToken(normalizedTarget)
    end

    table.sort(orderedClasses, function(a, b)
        local aId = GetClassIdByToken(a)
        local bId = GetClassIdByToken(b)

        local aInfo = aId and C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(aId)
        local bInfo = bId and C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(bId)

        local aName = (aInfo and aInfo.className) or (aId and GetClassInfo and select(1, GetClassInfo(aId))) or a
        local bName = (bInfo and bInfo.className) or (bId and GetClassInfo and select(1, GetClassInfo(bId))) or b

        aName = tostring(aName)
        bName = tostring(bName)

        if aName == bName then
            return a < b
        end

        return aName < bName
    end)

    return orderedClasses
end

function BCDM:GetClassSpecCatalog(targetClassToken)
    local catalog = {}

    for _, classToken in ipairs(self:GetOrderedClassTokens(targetClassToken)) do
        local classId = GetClassIdByToken(classToken)
        local classInfo = classId and C_ClassInfo and C_ClassInfo.GetClassInfo and C_ClassInfo.GetClassInfo(classId)
        local className = classInfo and classInfo.className
        if (not className) and GetClassInfo and classId then
            className = select(1, GetClassInfo(classId))
        end

        local classEntry = {
            classToken = classToken,
            classId = classId,
            className = className,
            specs = {},
        }

        if classId and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
            local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
            if numSpecs then
                for i = 1, numSpecs do
                    local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classId, i)
                    if type(specID) == "table" then
                        local info = specID
                        specID = info.specID or info.id
                        specName = info.name or specName
                        specIcon = info.icon or specIcon
                    end
                    if specID and (not specIcon) and C_SpecializationInfo.GetSpecializationInfoByID then
                        local info = C_SpecializationInfo.GetSpecializationInfoByID(specID)
                        if info then
                            specName = specName or info.name
                            specIcon = specIcon or info.icon
                        end
                    end
                    local specToken = self:NormalizeSpecToken(specName, specID)
                    if specToken then
                        classEntry.specs[#classEntry.specs + 1] = {
                            specID = specID,
                            specName = specName,
                            specIcon = specIcon,
                            specToken = specToken,
                            specIndex = i,
                        }
                    end
                end
            end
        end

        if #classEntry.specs > 0 then
            catalog[#catalog + 1] = classEntry
        end
    end

    return catalog
end

function BCDM:BuildClassSpecFilters(targetClassToken)
    local classSpecFilters = {}

    for _, classEntry in ipairs(self:GetClassSpecCatalog(targetClassToken)) do
        for _, specEntry in ipairs(classEntry.specs) do
            classSpecFilters[classEntry.classToken .. ":" .. specEntry.specToken] = true
        end
    end

    if next(classSpecFilters) then
        return classSpecFilters
    end
    return {}
end

-- Event check for equipped trinkets; trinket icons are driven directly from slots 13/14.
local trinketCheckEvent = CreateFrame("Frame")
trinketCheckEvent:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
trinketCheckEvent:RegisterEvent("PLAYER_LOGIN")
trinketCheckEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
trinketCheckEvent:SetScript("OnEvent", function(self, event, slot)
    if InCombatLockdown() then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, function() BCDM:FetchEquippedTrinkets() end)
        return
    elseif event == "PLAYER_EQUIPMENT_CHANGED" and (slot == 13 or slot == 14) then
        BCDM:FetchEquippedTrinkets()
    end
end)

function BCDM:FetchEquippedTrinkets()
    if InCombatLockdown() then return end
    if not BCDM.db.profile.CooldownManager.Trinket.Enabled then
        if BCDM.TrinketBarContainer then BCDM.TrinketBarContainer:Hide() end
        return
    end
    BCDM:UpdateCooldownViewer("Trinket")
end
