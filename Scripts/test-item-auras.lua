local root = (...) or "."
local BCDM = { Media = { Font = "font" }, db = { profile = {
    General = { Fonts = { FontFlag = "" } }, CooldownManager = { General = {} },
} } }
local secret = {}
function BCDM:IsSecretValue(value) return value == secret end
function BCDM:GetIconDimensions() return 40, 40 end
function BCDM:GetCustomTrackerEntrySettings() return {} end
function BCDM:ApplyIconTexCoord() end
assert(loadfile(root .. "/Core/CustomTrackers.lua"))("BetterCooldownManager", BCDM)
assert(loadfile(root .. "/CustomViewers/AuraSourceDisplay.lua"))("BetterCooldownManager", BCDM)

local combat, inaccessible = false, false
InCombatLockdown = function() return combat end
CustomAuraContainerSlotDefaultOptions = {}
local itemSpell = 1236994 -- Potion of Recklessness's use effect is also its buff.
C_Item = { GetItemSpell = function(id)
    assert(id == 241288)
    return "Potion of Recklessness", itemSpell
end }

local function Noop() end
local methods = {}
for _, name in ipairs({ "ClearAllPoints", "SetAllPoints", "SetPoint", "SetFrameLevel",
    "SetDesaturation", "SetFont", "SetAlpha", "SetMouseMotionEnabled", "SetDrawEdge",
    "SetDrawBling", "SetDrawSwipe", "SetSwipeColor", "SetSwipeTexture" }) do
    methods[name] = Noop
end
local function NewObject()
    return setmetatable({}, { __index = methods })
end
function methods:GetFrameLevel() return 1 end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() error("must not inspect aura visibility") end
function methods:CanBeAccessedInContext() return not inaccessible end
function methods:CreateTexture() return NewObject() end
function methods:CreateFontString() return NewObject() end
function methods:GetCountdownFontString() return self.text end
function methods:SetTextColor(...)
    assert(not inaccessible, "must not restyle inaccessible aura regions")
    self.colour = { ... }
end
function methods:SetHideCountdownNumbers(hidden) self.hideNumbers = hidden end
function methods:SetUnit(unit) self.unit = unit end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetDurationCooldown(cooldown) self.boundCooldown = cooldown end
function methods:SetIcon(icon) self.boundIcon = icon end
function methods:SetApplicationCount(count) self.boundCount = count end
function methods:SetAuraSlotCandidateFilters(_, filters) self.filters = filters end
function methods:AddAuraSlot(_, filter, options)
    self.filter, self.filters = filter, options.candidateFilters
    self.button = NewObject()
    options.initializeFrame(self.button)
    return self.button
end
CreateFrame = function(kind, _, parent)
    local frame = NewObject()
    frame.parent = parent
    if kind == "Cooldown" then frame.text = NewObject() end
    return frame
end

local icon = NewObject()
icon.Cooldown = NewObject()
icon.Cooldown.remaining = 270
local entry = { Source = { Type = "item", ID = 241288 } }
assert(BCDM:EnsureCustomTrackerAuraDisplay(icon, entry, {}))
local state = BCDM.CustomTrackerAuraRuntime.States[icon]
assert(#state.containers == 1, "items only track player buffs")
local container = state.containers[1].container
assert(container.unit == "player" and container.filter == "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY")
assert(container.filters.includeSpellIDs[1236994] and not container.filters.includeSpellIDs[241288])
local visual = state.visuals[1]
assert(container.button.boundCooldown == visual.cooldown and container.button.boundIcon == visual.icon)
assert(visual.cooldown.hideNumbers == false and table.concat(visual.cooldown.text.colour, ",") == "1,1,0,1")
assert(icon.Cooldown.remaining == 270, "normal cooldown continues underneath the native aura layer")

inaccessible = true
assert(BCDM:EnsureCustomTrackerAuraDisplay(icon, entry, {}), "inaccessible buttons retain their prepared style")
inaccessible = false
combat = true
assert(not BCDM:EnsureCustomTrackerAuraDisplay(NewObject(), entry, {}), "creation waits until out of combat")
combat = false
for _, value in ipairs({ false, secret, "invalid" }) do
    itemSpell = value
    assert(not BCDM:EnsureCustomTrackerAuraDisplay(NewObject(), entry, {}), "unreadable use spells cannot become candidates")
end
itemSpell = nil
assert(not BCDM:EnsureCustomTrackerAuraDisplay(NewObject(), entry, {}), "items without use spells remain cooldown-only")
itemSpell = 1236994
BCDM:HideCustomTrackerAuraDisplay(icon)
assert(not container.enabled and not state.layer.shown)
assert(BCDM:HasCustomTrackerAuraDisplay(icon), "aura-owning item icons remain stable instead of returning to the pool")
local spellIcon = NewObject()
assert(BCDM:EnsureCustomTrackerAuraDisplay(spellIcon, { Source = { Type = "spell", ID = 100 } }, {}))
assert(#BCDM.CustomTrackerAuraRuntime.States[spellIcon].containers == 2, "spell target and player tracking is unchanged")
return true
