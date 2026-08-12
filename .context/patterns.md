# Patterns

## Ownership boundary

BCM may fully configure frames it creates. Blizzard Cooldown Viewer frames remain Blizzard-owned: observe and style them only through the existing guarded integration paths. Shared visibility and custom entry policies never apply to Blizzard Essential, Utility, BuffIcon, or BuffBar rows.

Tracked-buff centering is a BCM-owned hybrid replacement. Build ordered spell and item catalogs outside combat from `BuffIconCooldownViewer:GetCooldownIDs()` plus static `spellID`, override IDs, `linkedSpellIDs`, `equipSlot`, and `spellCategoryID`; pooled rows can lack cooldown IDs whenever the native viewer is hidden. Aura-backed spell entries use `CustomAuraContainerTemplate`, while item-backed entries use stable BCM frames with optional one-slot AuraContainer overlays. Reserve the configured aura capacity before the item section: the main AuraContainer applies secret-wrapped live dimensions, so addon-owned item frames must anchor to a fixed safe owner rather than its moving edge. Keep item slots visible without branching on cooldown readiness, and forward equipment timing without inspecting it. Never reanchor pooled native rows or call their `RefreshLayout`/`RefreshData` methods. Only hide the native BuffIcon viewer after at least one replacement entry is ready; an empty or unreadable catalog must fail open. Retain native visibility and icon-scale values per active layout, use the supported 40px-based Edit Mode icon scale for the editor preview, restore both values when replacement mode stops or the session ends, and hide the replacement while native Cooldown Manager or Edit Mode is open.

Retail 12.1 reserves `/cdm` for Blizzard's Cooldown Manager panel. BCM must leave that alias unclaimed and expose its settings through `/bcdm`, `/bettercooldownmanager`, and `/bcm`.

Apply Blizzard Edit Mode system positions only through the coalesced LibEditModeOverride queue. Profile, import, specialization, settings, and Edit Mode callbacks all feed that queue; direct `ClearAllPoints`, `SetPoint`, or `ApplyChanges` calls must not provide alternate viewer-layout paths. Never persist a Blizzard viewer relative to a `BCDM_*` frame name: translate that desired anchor to equivalent `UIParent` coordinates first. Legacy layouts may be replayed before AceAddon enablement, so the BCM-owned frame names exposed as Viewer anchors must be registered during addon file loading and configured by reusing those frames later.

`LibEditModeOverride:ApplyChanges()` briefly opens Edit Mode, which closes special and native settings windows through Blizzard's panel manager. Keep queued viewer positions pending while either BCM settings or `CooldownViewerSettings` is shown or a native-panel open request is pending, then retry after those windows close. Observe native Settings and Edit Mode lifecycle through `EventRegistry`; native `RefreshLayout` hooks may only queue addon-owned work. Automatic native-panel opening uses `securecallfunction` and preserves Blizzard's last selected tab.

## Custom tracker model

Use stable numeric bar and entry IDs. Keep presentation order in explicit arrays rather than relying on table iteration. Source adapters expose metadata, state, availability, and relevant events through one contract; layout code must not contain source-specific API branches.

Keep tracker migrations idempotent. Convert every profile, preserve appearance and filters, and remove legacy fields only after a complete successful conversion.

## Events and timers

Coalesce bursts of events into one refresh. Use one shared timer scheduler for fixed-duration entries. Do not create one ticker or `OnUpdate` script per icon.

Keep source-specific reads behind adapters. Spell and item sources resolve native cooldown state, equipment sources use inventory-slot cooldowns, and timer sources store session-only completion times from successful player casts.

Spell aura presentation is separate from cooldown-state policy. AuraContainers own active aura visibility and duration widgets; BCM keeps the normal cooldown beneath them and never converts secret aura visibility into Lua state.

## Visibility and anchoring

Resolve shared versus local visibility first, apply mode/instance policy, then veto states, then enabled/source availability. Validate inter-bar anchors as a graph, reject cycles, and fall back to `UIParent` for missing or unsafe targets.

Custom tracker icons must occupy the bounds of their anchored container. Horizontal right growth starts at the container's left edge, left growth starts at its right edge, and vertical growth uses the equivalent bottom/top edge. Do not place the first icon at container center because corner anchors then drift by half the bar size.

## Secret-safe rendering

Guard API reads that may return secret values. When a state cannot safely be interpreted, retain the last valid visual or fail closed instead of probing further. Never use aura enumeration as a fallback for custom cooldown state.

Pre-create AuraContainers outside combat. Configure returned AuraButtons during the container initialization callback, keep their parent entry frames stable, and update candidate filters only outside combat.

Treat `UNIT_AURA` as a refresh signal without inspecting its payload. Aura presence, application counts, and spell cast counts must be readable before they drive a custom resource bar; otherwise hide that BCM-owned display until a later readable refresh.

## BCM-owned bars

Put reusable resource and cast presentation decisions in `Core/BarBehavior.lua`; modules remain responsible for their own events and frame updates. Shared settings are defaults, while explicit per-bar visibility choices override them.

For equipped trinkets, source linked aura candidates from the 12.1 Cooldown Viewer `EquipSlotEssential` and `EquipSlotTracked` catalog records, then bind stack text through `CustomAuraContainerTemplate` and `SetApplicationCount`. Do not enumerate player auras or read secret aura stack values in addon Lua.

## Custom glows

Keep BCDM glow state in weak addon-owned tables and render LibCustomGlow styles on mouse-disabled BCM overlays fitted to spell-only targets. Never adopt an item-backed, forbidden, or unreadable Cooldown Viewer row, and never store BCDM lifecycle fields or LibCustomGlow objects on Blizzard frames. Suppress native artwork only after the custom renderer starts successfully, then restore its alpha when the alert ends or custom glows are disabled.
