local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local function wipeTable(value)
    for key in pairs(value) do value[key] = nil end
end
wipe = wipeTable

local secretValue = {}
local secretMaximum = {}
local secretApplications = {}
local secretChargedPoint = {}
local auraByID = {}
local maxBySpell = {}
local castCountResult = 3
local powerValues = {}
local powerError = false
local staggerSecret = false
local partialPower = 0
local partialCalls = 0
local chargedPowerPoints
local runeDataAvailable = true
local runeReadyStates = { true, true, true, true, true, true }
local currentDescriptor
local collapsingStarCost = 40

C_UnitAuras = {
    GetPlayerAuraBySpellID = function(spellID) return auraByID[spellID] end,
}
C_Spell = {
    GetSpellCastCount = function() return castCountResult end,
    GetSpellMaxCumulativeAuraApplications = function(spellID) return maxBySpell[spellID] end,
}
C_SpellBook = { IsSpellKnown = function() return false end }

Enum = { PowerType = {
    Mana = 0, ComboPoints = 4, Runes = 5, SoulShards = 7,
    HolyPower = 9, Maelstrom = 11, Chi = 12, ArcaneCharges = 16, Essence = 19,
} }
RAID_CLASS_COLORS = {}
UnitClass = function() return "", "DEMONHUNTER" end
GetCollapsingStarCost = function() return collapsingStarCost end
UnitPower = function(_, powerType, unmodified)
    if powerError then error("restricted power") end
    if unmodified then return powerValues.fractional end
    return powerValues[powerType]
end
UnitPowerMax = function(_, powerType)
    if powerError then error("restricted power max") end
    return powerValues.max and powerValues.max[powerType]
end
UnitPowerDisplayMod = function() return 1000 end
UnitPartialPower = function()
    partialCalls = partialCalls + 1
    return partialPower
end
UnitHealthMax = function() return powerValues.healthMax end
UnitStagger = function()
    if powerError or staggerSecret then return secretValue end
    return powerValues.stagger or 0
end
GetUnitChargedPowerPoints = function() return chargedPowerPoints end
GetRuneCooldown = function(runeIndex)
    if not runeDataAvailable then return end
    return 0, 0, runeReadyStates[runeIndex]
end
GetTime = function() return 0 end
AbbreviateLargeNumbers = function(value) return tostring(value) end

local createdFrames = {}
local function NewStatusBar()
    local bar = {
        shown = false,
        reverseFill = false,
        minValue = nil,
        maxValue = nil,
        value = nil,
    }
    function bar:SetStatusBarTexture() end
    function bar:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
    function bar:SetValue(value) self.value = value end
    function bar:SetStatusBarColor(...) self.colour = { ... } end
    function bar:SetReverseFill(reverse) self.reverseFill = reverse end
    function bar:Show() self.shown = true end
    function bar:Hide() self.shown = false end
    function bar:SetScript(name, script) self[name] = script end
    function bar:SetParent(parent) self.parent = parent end
    function bar:ClearAllPoints() end
    function bar:SetSize(width, height) self.width, self.height = width, height end
    function bar:SetWidth(width) self.width = width end
    function bar:SetHeight(height) self.height = height end
    function bar:SetPoint(...) self.point = { ... } end
    return bar
end
CreateFrame = function()
    local frame = NewStatusBar()
    createdFrames[#createdFrames + 1] = frame
    return frame
end

local barHidden = false
local barShown = false
local statusShown = false
local statusValue
local statusMin
local statusMax
local textValue
local tickCount
local clearTickCount = 0
local secondaryBar = {
    GetWidth = function() return 100 end,
    GetHeight = function() return 20 end,
    Hide = function() barHidden = true end,
    Show = function() barShown = true end,
    Status = {
        SetMinMaxValues = function(_, minValue, maxValue) statusMin, statusMax = minValue, maxValue end,
        SetValue = function(_, value) statusValue = value end,
        SetStatusBarColor = function() end,
        Show = function() statusShown = true end,
        Hide = function() statusShown = false end,
        SetScript = function() end,
    },
    Text = { SetText = function(_, value) textValue = value end },
}
local BCDM = {
    db = { profile = {
        General = { Colours = {
            PrimaryPower = {},
            SecondaryPower = {
                CHARGED_COMBO_POINTS = { 0.2, 0.4, 1, 1 },
                ESSENCE_RECHARGE = { 0.2, 0.8, 1, 1 },
                RUNE_RECHARGE = { 0.2, 0.8, 1, 1 },
                STAGGER_COLOURS = { LIGHT = {}, MODERATE = {}, HEAVY = {} },
            },
        } },
        SecondaryPowerBar = {
            Text = { Mode = "AUTO", ShowStaggerDPS = false },
            HideTicks = false,
            FillDirection = "RIGHT",
            ColourMode = "CUSTOM",
            ForegroundColour = { 1, 1, 1, 1 },
        },
    } },
    SecondaryPowerBar = secondaryBar,
    Media = { Foreground = "foreground" },
}
function BCDM:IsSecretValue(value)
    return value == secretValue or value == secretMaximum
        or value == secretApplications or value == secretChargedPoint
end
function BCDM:GetCurrentSecondaryResource() return currentDescriptor end
function BCDM:ResolveBarFillColour() return 1, 1, 1, 1 end
function BCDM:ApplyStatusBarDirection(bar, direction) bar:SetReverseFill(direction == "LEFT") end
function BCDM:ClearTicks() clearTickCount = clearTickCount + 1 end
function BCDM:CreateTicks(count) tickCount = count end
function BCDM:FormatResourceText() return "formatted" end

assert(loadfile(root .. "/Modules/SecondaryPowerBar.lua"))("BetterCooldownManager", BCDM)

local readers = BCDM._SecondaryResourceReaders
local value, readable, widget

auraByID[100] = nil
value, readable, widget = readers.GetAuraStacks(100)
Check(value == 0 and readable and not widget, "a readable missing aura produces zero stacks")
auraByID[100] = { applications = 4 }
value, readable, widget = readers.GetAuraStacks(100)
Check(value == 4 and readable and not widget, "readable aura applications are returned")
auraByID[100] = { applications = nil }
value, readable, widget = readers.GetAuraStacks(100)
Check(value == nil and not readable and not widget, "nil applications on an existing aura fail closed")
auraByID[100] = { applications = secretApplications }
value, readable, widget = readers.GetAuraStacks(100)
Check(value == secretApplications and not readable and widget, "secret aura applications reach the protected widget path")
auraByID[100] = secretValue
value, readable = readers.IsInMetamorphosis(100)
Check(value == nil and not readable, "secret aura presence is not used as resource state")
auraByID[100] = nil
C_UnitAuras.GetPlayerAuraBySpellID = function() error("restricted aura") end
value, readable = readers.GetAuraStacks(100)
Check(value == nil and not readable, "restricted aura APIs fail closed")
C_UnitAuras.GetPlayerAuraBySpellID = function(spellID) return auraByID[spellID] end

castCountResult = 3
value, readable, widget = readers.GetSpellCharges(100)
Check(value == 3 and readable and not widget, "readable spell cast counts are returned")
castCountResult = secretValue
value, readable, widget = readers.GetSpellCharges(100)
Check(value == secretValue and not readable and widget, "secret spell cast counts remain available for protected widgets")
C_Spell.GetSpellCastCount = function() error("restricted cooldown") end
value, readable = readers.GetSpellCharges(100)
Check(value == nil and not readable, "restricted spell cast counts fail closed")
C_Spell.GetSpellCastCount = function() return castCountResult end

local devourer = {
    kind = "DEVOURER_SOUL", sourceSpellID = 1225789, transformedSourceSpellID = 1227702,
    metamorphosisAuraID = 1217607, maximumSpellID = 1225789, maximum = 50,
}
auraByID[1217607] = nil
auraByID[1225789] = { applications = 12 }
auraByID[1227702] = { applications = 30 }
maxBySpell[1225789] = 50
local sourceSpellID
value, statusMax, widget, sourceSpellID = readers.GetDevourerValues(devourer)
Check(value == 12 and statusMax == 50 and sourceSpellID == 1225789,
    "Devourer reads Dark Heart outside Void Metamorphosis")
auraByID[1217607] = {}
value, statusMax, widget, sourceSpellID = readers.GetDevourerValues(devourer)
Check(value == 30 and statusMax == collapsingStarCost and sourceSpellID == 1227702,
    "Devourer switches to Silence the Whispers and Collapsing Star in Void Metamorphosis")
maxBySpell[1225789] = 35
auraByID[1217607] = nil
value, statusMax = readers.GetDevourerValues(devourer)
Check(statusMax == 35, "Devourer normal maximum comes from the native cumulative-aura API")

local maelstrom = { kind = "AURA_STACKS", sourceSpellID = 344179, maximumSpellID = 344179, maximum = 5 }
auraByID[344179] = { applications = 4 }
maxBySpell[344179] = 5
value, readable = readers.GetAuraStacks(344179)
local nativeMax = readers.GetSpellMaximum(344179, 5)
Check(value == 4 and nativeMax == 5 and readable, "Maelstrom Weapon normally has five stacks")
maxBySpell[344179] = 10
nativeMax = readers.GetSpellMaximum(344179, 5)
Check(nativeMax == 10, "Maelstrom Weapon uses the native ten-stack maximum with Raging Maelstrom")
currentDescriptor = maelstrom
BCDM.db.profile.SecondaryPowerBar.HideTicks = false
maxBySpell[344179] = 5
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_AURA", "player")
Check(tickCount == 5, "Maelstrom tick count follows the native five-stack maximum")
maxBySpell[344179] = 10
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_AURA", "player")
Check(tickCount == 10, "Maelstrom tick count refreshes when its maximum changes")

C_Spell.GetSpellCastCount = function() return castCountResult end
currentDescriptor = { kind = "SPELL_CHARGES", sourceSpellID = 228477, maximum = 6 }
castCountResult = secretValue
barHidden, barShown, statusValue, textValue = false, false, nil, nil
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_AURA", "player")
Check(statusValue == secretValue and barShown and not barHidden and textValue == "",
    "secret Vengeance fragments render through StatusBar without Lua inspection")

currentDescriptor = { kind = "STANDARD", powerType = Enum.PowerType.HolyPower }
powerValues[Enum.PowerType.HolyPower] = secretValue
powerValues.max = { [Enum.PowerType.HolyPower] = secretMaximum }
barHidden, barShown, statusValue = false, false, nil
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_UPDATE", "player")
Check(statusValue == secretValue and statusMax == secretMaximum and barShown and not barHidden,
    "secret UnitPower and UnitPowerMax values reach widgets without arithmetic")
staggerSecret = true
powerValues.healthMax = 100
currentDescriptor = { kind = "STAGGER" }
barHidden, barShown, statusValue = false, false, nil
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_HEALTH", "player")
Check(statusValue == secretValue and barShown and not barHidden,
    "secret UnitStagger values reach the protected StatusBar without percentage arithmetic")
staggerSecret = false

currentDescriptor = { kind = "SOUL_SHARDS", powerType = Enum.PowerType.SoulShards, fractional = true, tickCount = 5 }
powerError = false
powerValues.fractional = 25
powerValues.max[Enum.PowerType.SoulShards] = 5
barHidden, barShown = false, false
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_FREQUENT", "player", "SOUL_SHARDS")
Check(statusValue == 25 and barShown, "UNIT_POWER_FREQUENT refreshes fractional Soul Shards")
powerValues.fractional = 35
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_FREQUENT", "player", "SOUL_SHARDS")
Check(statusValue == 35, "fractional Soul Shards update on every frequent-power event")

currentDescriptor = { kind = "COMBO_POINTS", powerType = Enum.PowerType.ComboPoints }
powerValues[Enum.PowerType.ComboPoints] = 2
powerValues.max[Enum.PowerType.ComboPoints] = 5
chargedPowerPoints = secretValue
BCDM.db.profile.SecondaryPowerBar.FillDirection = "LEFT"
local hostilePowerPayload = setmetatable({}, { __eq = function() error("UNIT_POWER_POINT_CHARGE payload was inspected") end })
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_POINT_CHARGE", hostilePowerPayload)
Check(statusValue == 2 and barShown, "UNIT_POWER_POINT_CHARGE refreshes combo points without inspecting its payload")
chargedPowerPoints = { 1, secretChargedPoint, 3 }
local chargedPointLookup = readers.GetChargedPowerPointLookup()
Check(chargedPointLookup[1] and chargedPointLookup[3] and not chargedPointLookup[2],
    "a readable charged-point table ignores secret elements without indexing them")
local comboBarsReversed = true
for _, frame in ipairs(createdFrames) do
    if frame.value == 2 and frame.reverseFill ~= true then comboBarsReversed = false end
end
Check(comboBarsReversed, "left fill applies to visible combo-point StatusBars")
chargedPowerPoints = nil

currentDescriptor = { kind = "RUNES", powerType = Enum.PowerType.Runes, tickCount = 6 }
powerValues[Enum.PowerType.Runes] = 6
runeReadyStates = { true, true, true, false, false, false }
runeDataAvailable = true
BCDM.db.profile.SecondaryPowerBar.HideTicks = true
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_UPDATE", "player")
Check(statusValue == 3 and textValue == "3" and statusMin == 0 and statusMax == 6 and statusShown,
    "DK HideTicks counts ready runes instead of using UnitPower")
runeReadyStates[2] = nil
barHidden, barShown, statusShown = false, false, true
BCDM._SecondaryPowerBarOnEvent(nil, "RUNE_POWER_UPDATE")
Check(barHidden and not barShown and not statusShown,
    "an unavailable rune ready state hides the aggregate display")
runeReadyStates[2] = true
BCDM.db.profile.SecondaryPowerBar.HideTicks = false
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_MAXPOWER", "player")
Check(#createdFrames >= 6, "turning DK HideTicks off recreates rune bars")
local runeBarsReversed = true
for _, frame in ipairs(createdFrames) do
    if frame.value ~= nil and frame.reverseFill ~= true then runeBarsReversed = false end
end
Check(runeBarsReversed, "left fill applies to visible rune StatusBars")
runeDataAvailable = false
barHidden, barShown, statusShown = false, false, true
BCDM._SecondaryPowerBarOnEvent(nil, "RUNE_POWER_UPDATE")
Check(barHidden and not barShown and not statusShown,
    "missing rune cooldown data clears stale rune state and hides the bar")
runeDataAvailable = true
BCDM._SecondaryPowerBarOnEvent(nil, "RUNE_POWER_UPDATE")
Check(barShown and tickCount == 6, "rune display recovers after cooldown data returns")

currentDescriptor = { kind = "ESSENCE", powerType = Enum.PowerType.Essence }
powerValues[Enum.PowerType.Essence] = 2
powerValues.max[Enum.PowerType.Essence] = 5
partialPower = secretValue
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_FREQUENT", "player")
Check(statusValue == 2, "secret UnitPartialPower does not enter Lua arithmetic")
partialPower = 250
local essenceFrameStart = #createdFrames + 1
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_MAXPOWER", "player")
local essenceFrameEnd = #createdFrames
Check(statusValue == 2, "Essence updates through the max-power refresh path")
partialCalls = 0
powerValues[Enum.PowerType.Essence] = 5
partialPower = secretValue
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_FREQUENT", "player")
local allEssenceBarsShown = true
for index = essenceFrameStart, essenceFrameEnd do
    if not createdFrames[index].shown then allEssenceBarsShown = false end
end
Check(partialCalls == 0 and allEssenceBarsShown,
    "full readable Essence renders every child point without querying UnitPartialPower")
partialPower = 250
local essenceBarsReversed = true
for _, frame in ipairs(createdFrames) do
    if frame.maxValue == 1 and frame.reverseFill ~= true then essenceBarsReversed = false end
end
Check(essenceBarsReversed, "left fill applies to visible Essence StatusBars")

powerError = true
currentDescriptor = { kind = "STANDARD", powerType = Enum.PowerType.HolyPower }
barHidden, barShown = false, false
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_POWER_UPDATE", "player")
Check(barHidden and not barShown, "unreadable resource data remains hidden after a full update")
powerError = false

local eventFrame = { unregistered = {} }
function eventFrame:UnregisterEvent(event) self.unregistered[event] = true end
currentDescriptor = nil
barHidden = false
BCDM._SecondaryPowerBarOnEvent(eventFrame, "UNIT_POWER_FREQUENT", "player")
Check(eventFrame.unregistered.UNIT_POWER_FREQUENT and eventFrame.unregistered.UNIT_POWER_POINT_CHARGE,
    "unsupported specs unregister high-frequency resource events")
local hostilePayload = setmetatable({}, { __eq = function() error("UNIT_AURA payload was inspected") end })
barHidden = false
BCDM._SecondaryPowerBarOnEvent(eventFrame, "UNIT_AURA", hostilePayload)
Check(barHidden, "UNIT_AURA refreshes without inspecting its payload")

if failures > 0 then os.exit(1) end
return true
