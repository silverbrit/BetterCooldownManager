local _, BCDM = ...

local SPECIALIZATION = {
    ARCANE = 62,
    SHADOW = 258,
    ELEMENTAL = 262,
    ENHANCEMENT = 263,
    DESTRUCTION = 267,
    BREWMASTER = 268,
    WINDWALKER = 269,
    BLOOD = 250,
    FROST = 251,
    UNHOLY = 252,
    VENGEANCE = 581,
    DEVOURER = 1480,
}

local SWAP_ELIGIBLE = {
    [66] = true, [70] = true,
    [263] = true,
    [1467] = true, [1473] = true,
    [265] = true, [266] = true, [267] = true,
}

local RUNE_COLOUR_KEY = {
    [SPECIALIZATION.BLOOD] = "BLOOD",
    [SPECIALIZATION.FROST] = "FROST",
    [SPECIALIZATION.UNHOLY] = "UNHOLY",
}

local function Descriptor(key, kind, powerType, specID, extra)
    local descriptor = {
        key = key,
        kind = kind,
        powerType = powerType,
        specID = specID,
        swapToPrimaryEligible = SWAP_ELIGIBLE[specID] == true,
    }
    for field, value in pairs(extra or {}) do descriptor[field] = value end
    return descriptor
end

function BCDM:ResolveSecondaryResource(context)
    context = context or {}
    local class = context.class
    local specID = context.specID
    local formID = context.formID or 0
    local showMana = context.showMana == true
    local power = context.powerTypes or (Enum and Enum.PowerType)
    if not class or not specID or not power then return nil end

    if class == "MONK" then
        if specID == SPECIALIZATION.BREWMASTER then
            return Descriptor("STAGGER", "STAGGER", nil, specID)
        elseif specID == SPECIALIZATION.WINDWALKER then
            return Descriptor(power.Chi, "STANDARD", power.Chi, specID)
        end
    elseif class == "ROGUE" then
        return Descriptor(power.ComboPoints, "COMBO_POINTS", power.ComboPoints, specID)
    elseif class == "DRUID" and formID == 1 then
        return Descriptor(power.ComboPoints, "STANDARD", power.ComboPoints, specID)
    elseif class == "PALADIN" then
        return Descriptor(power.HolyPower, "STANDARD", power.HolyPower, specID)
    elseif class == "WARLOCK" then
        return Descriptor(power.SoulShards, "SOUL_SHARDS", power.SoulShards, specID, {
            fractional = specID == SPECIALIZATION.DESTRUCTION,
            tickCount = 5,
        })
    elseif class == "MAGE" and specID == SPECIALIZATION.ARCANE then
        return Descriptor(power.ArcaneCharges, "STANDARD", power.ArcaneCharges, specID)
    elseif class == "EVOKER" then
        return Descriptor(power.Essence, "ESSENCE", power.Essence, specID)
    elseif class == "DEATHKNIGHT" then
        return Descriptor(power.Runes, "RUNES", power.Runes, specID, {
            runeColourKey = RUNE_COLOUR_KEY[specID],
            tickCount = 6,
        })
    elseif class == "DEMONHUNTER" then
        if specID == SPECIALIZATION.VENGEANCE then
            return Descriptor("SOUL_FRAGMENTS", "SPELL_CHARGES", nil, specID, {
                sourceSpellID = 228477,
                maximum = 6,
                tickCount = 6,
            })
        elseif specID == SPECIALIZATION.DEVOURER then
            return Descriptor("SOUL", "DEVOURER_SOUL", nil, specID, {
                sourceSpellID = 1217605,
                metamorphosisAuraID = 1217607,
                soulGluttonSpellID = 1247534,
            })
        end
    elseif class == "SHAMAN" then
        if specID == SPECIALIZATION.ENHANCEMENT then
            return Descriptor(power.Maelstrom, "AURA_STACKS", power.Maelstrom, specID, {
                sourceSpellID = 344179,
                maximum = 10,
                tickCount = 10,
            })
        elseif specID == SPECIALIZATION.ELEMENTAL and showMana then
            return Descriptor(power.Mana, "STANDARD", power.Mana, specID)
        end
    elseif class == "PRIEST" and specID == SPECIALIZATION.SHADOW and showMana then
        return Descriptor(power.Mana, "STANDARD", power.Mana, specID)
    end
end

function BCDM:GetCurrentSecondaryResource()
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    local settings = self.db and self.db.profile and self.db.profile.SecondaryPowerBar
    return self:ResolveSecondaryResource({
        class = select(2, UnitClass("player")),
        specID = specID,
        formID = GetShapeshiftFormID and GetShapeshiftFormID() or 0,
        showMana = settings and (settings.ShowMana or settings.ShowManaBar) == true,
    })
end

function BCDM:CanSwapSecondaryResourceToPrimary()
    local descriptor = self:GetCurrentSecondaryResource()
    return descriptor and descriptor.swapToPrimaryEligible == true or false
end
