local root = (...)
if type(root) ~= "string" or root == "" then root = "." end

local failures = 0
local function Check(condition, message)
    if condition then return end
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local secretValue = {}
local auraResult
local castCountResult
C_UnitAuras = {
    GetPlayerAuraBySpellID = function() return auraResult end,
}
C_Spell = {
    GetSpellCastCount = function() return castCountResult end,
}

local barHidden = false
local BCDM = {
    db = { profile = { SecondaryPowerBar = {} } },
    SecondaryPowerBar = { Hide = function() barHidden = true end },
}
function BCDM:IsSecretValue(value) return value == secretValue end
function BCDM:GetCurrentSecondaryResource() return nil end

assert(loadfile(root .. "/Modules/SecondaryPowerBar.lua"))("BetterCooldownManager", BCDM)

local readers = BCDM._SecondaryResourceReaders
auraResult = nil
local value, readable = readers.GetAuraStacks(100)
Check(value == 0 and readable, "a readable missing aura produces zero stacks")

auraResult = { applications = 4 }
value, readable = readers.GetAuraStacks(100)
Check(value == 4 and readable, "readable aura applications are returned")

auraResult = { applications = secretValue }
value, readable = readers.GetAuraStacks(100)
Check(value == nil and not readable, "secret aura applications fail closed")

auraResult = secretValue
value, readable = readers.IsInMetamorphosis(100)
Check(value == nil and not readable, "secret aura presence is not used as resource state")

C_UnitAuras.GetPlayerAuraBySpellID = function() error("restricted aura") end
value, readable = readers.GetAuraStacks(100)
Check(value == nil and not readable, "restricted aura APIs fail closed")

castCountResult = 3
value, readable = readers.GetSpellCharges(100)
Check(value == 3 and readable, "readable spell cast counts are returned")

castCountResult = secretValue
value, readable = readers.GetSpellCharges(100)
Check(value == nil and not readable, "secret spell cast counts fail closed")

C_Spell.GetSpellCastCount = function() error("restricted cooldown") end
value, readable = readers.GetSpellCharges(100)
Check(value == nil and not readable, "restricted spell cast counts fail closed")

local hostilePayload = setmetatable({}, {
    __eq = function() error("UNIT_AURA payload was inspected") end,
})
BCDM._SecondaryPowerBarOnEvent(nil, "UNIT_AURA", hostilePayload)
Check(barHidden, "UNIT_AURA refreshes without inspecting its secret payload")

return failures == 0
