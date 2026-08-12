local BCDM, Check = ...

local candidates, candidatesReadable = BCDM.BuildTrackedBuffAuraCandidates({
    spellID = 300,
    overrideSpellID = 100,
    overrideTooltipSpellID = 400,
    linkedSpellIDs = { 200, 300, 100 },
})
Check(candidatesReadable and table.concat(candidates, ",") == "100,200,300,400",
    "tracked buff aura candidates are readable, sorted, and deduplicated")

candidates, candidatesReadable = BCDM.BuildTrackedBuffAuraCandidates({
    hasAura = false,
    linkedSpellIDs = {},
})
Check(candidatesReadable and #candidates == 0,
    "entries without associated aura spell IDs do not become aura groups")

local infoByCooldownID = {
    [10] = { spellID = 100, linkedSpellIDs = { 101 } },
    [20] = { linkedSpellIDs = {} },
    [30] = { spellID = 300, linkedSpellIDs = { 101, 301 } },
    [40] = { spellID = 400, linkedSpellIDs = { 401 }, equipSlot = 13 },
    [50] = { linkedSpellIDs = {}, spellCategoryID = 4 },
}
local catalog, readable, signature = BCDM.BuildTrackedBuffAuraCatalog({
    10,
    20,
    30,
    40,
    50,
}, function(cooldownID) return infoByCooldownID[cooldownID] end)
Check(readable and #catalog.auras == 2 and #catalog.items == 2,
    "tracked buffs partition aura and item-backed entries")
Check(catalog.auras[1].cooldownID == 10 and catalog.auras[2].cooldownID == 30
    and catalog.items[1].cooldownID == 40 and catalog.items[2].cooldownID == 50,
    "each replacement section preserves Blizzard's configured order")
Check(table.concat(catalog.auras[1].spellIDs, ",") == "100,101"
    and table.concat(catalog.auras[2].spellIDs, ",") == "300,301",
    "the first configured entry claims shared aura candidates without duplicate icons")
Check(catalog.items[1].kind == "equipment" and catalog.items[1].equipSlot == 13
    and table.concat(catalog.items[1].spellIDs, ",") == "400,401",
    "equipped item entries retain their slot and aura candidates")
Check(catalog.items[2].kind == "category" and catalog.items[2].spellCategoryID == 4,
    "category items remain present without aura candidates")
Check(signature == "A:10:100,101;A:30:300,301;E:40:13:400,401;I:50:4:",
    "hybrid catalog signatures are stable")

local fixedLayout = BCDM.GetTrackedBuffFixedLayout(3, 2, 32, 24, 1, true)
Check(fixedLayout.auraExtent == 98 and fixedLayout.itemExtent == 65
    and fixedLayout.sectionGap == 1 and fixedLayout.width == 164 and fixedLayout.height == 24,
    "horizontal hybrid layout reserves aura and item capacity without secret size reads")
fixedLayout = BCDM.GetTrackedBuffFixedLayout(2, 1, 32, 24, 2, false)
Check(fixedLayout.width == 32 and fixedLayout.height == 76,
    "vertical hybrid layout reserves the configured icon height and spacing")

local secretStart, secretDuration = {}, {}
local forwardedStart, forwardedDuration
local forwarded = BCDM.ForwardTrackedBuffItemCooldown({
    SetCooldown = function(_, startTime, duration)
        forwardedStart, forwardedDuration = startTime, duration
    end,
}, function() return secretStart, secretDuration end)
Check(forwarded and forwardedStart == secretStart and forwardedDuration == secretDuration,
    "item cooldown values are forwarded to the widget without Lua arithmetic")

local failedCatalog, failedReadable = BCDM.BuildTrackedBuffAuraCatalog({
    "secret",
}, function() return nil end)
Check(failedCatalog == nil and failedReadable == false,
    "unreadable native catalog fields fail closed")
