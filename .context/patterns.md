# Patterns

## Ownership boundary

BCM may fully configure frames it creates. Blizzard Cooldown Viewer frames remain Blizzard-owned: observe and style them through guarded integration paths; the explicit Center Buffs option may also apply EUI-style addon-owned anchors without reparenting or taking ownership of Blizzard lifecycle or visibility state. Shared visibility and custom entry policies never apply to Blizzard Essential, Utility, BuffIcon, or BuffBar rows.

Tracked-buff centering keeps Blizzard's pooled `BuffIconCooldownViewer` rows. Follow EUI's native-frame path: enumerate `itemFramePool:EnumerateActive()`, filter readable shown frames, sort addon-owned entry metadata by Blizzard `layoutIndex`, position the visible set against a BCM-owned anchor, and reapply stored points after `OnActiveStateChanged` or viewer layout hooks. Do not enumerate auras, read cooldown state, call Blizzard `RefreshLayout`/`RefreshData`, reparent rows, or write addon metadata onto Blizzard frames. Disable the addon anchors while native Cooldown Manager or Edit Mode is open so Blizzard owns the editor preview.

Retail 12.1 reserves `/cdm` for Blizzard's Cooldown Manager panel. BCM must leave that alias unclaimed and expose its settings through `/bcdm`, `/bettercooldownmanager`, and `/bcm`.

Apply Blizzard Edit Mode system positions only through the coalesced LibEditModeOverride queue. Profile, import, specialization, settings, and Edit Mode callbacks all feed that queue; direct `ClearAllPoints`, `SetPoint`, or `ApplyChanges` calls must not provide alternate viewer-layout paths. Never persist a Blizzard viewer relative to a `BCDM_*` frame name: translate that desired anchor to equivalent `UIParent` coordinates first. Legacy layouts may be replayed before AceAddon enablement, so the BCM-owned frame names exposed as Viewer anchors must be registered during addon file loading and configured by reusing those frames later.

`LibEditModeOverride:ApplyChanges()` briefly opens Edit Mode, which closes special and native settings windows through Blizzard's panel manager and taints protected Edit Mode refreshes when initiated by BCM. Save queued layout data with `SaveOnly()`, then securely update each native Cooldown Viewer system and synchronize only its resulting anchor with the initialized Edit Mode manager. Never call `UpdateLayoutInfo`, replace `registeredSystemFrames`, or refresh CompactUnitFrames from BCM: even restoring a Blizzard field after an addon write leaves it tainted. Keep positions pending during combat, active Edit Mode, or a native-panel open request, then retry afterward. Observe native Settings and Edit Mode lifecycle through `EventRegistry`; native `RefreshLayout` hooks may only queue addon-owned work. Automatic native-panel opening uses `securecallfunction` and preserves Blizzard's last selected tab.

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

Pre-create AuraContainers outside combat. Configure returned AuraButtons during the container initialization callback, anchor custom regions to the AuraButton before passing them to `SetApplicationCount`, `SetDurationCooldown`, or `SetIcon`, keep their parent entry frames stable, and update candidate filters only outside combat.

Treat `UNIT_AURA` as a refresh signal without inspecting its payload. Aura presence, application counts, and spell cast counts must be readable before they drive a custom resource bar; otherwise hide that BCM-owned display until a later readable refresh.

## BCM-owned bars

Put reusable resource and cast presentation decisions in `Core/BarBehavior.lua`; modules remain responsible for their own events and frame updates. Shared settings are defaults, while explicit per-bar visibility choices override them.

For equipped trinkets, source linked aura candidates from the 12.1 Cooldown Viewer `EquipSlotEssential` and `EquipSlotTracked` catalog records, then bind stack text through `CustomAuraContainerTemplate` and `SetApplicationCount`. Do not enumerate player auras or read secret aura stack values in addon Lua.

## Custom glows

Keep BCDM glow state in weak addon-owned tables and render LibCustomGlow styles on mouse-disabled BCM overlays fitted to spell-only targets. Never adopt an item-backed, forbidden, or unreadable Cooldown Viewer row, and never store BCDM lifecycle fields or LibCustomGlow objects on Blizzard frames. Suppress native artwork only after the custom renderer starts successfully, then restore its alpha when the alert ends or custom glows are disabled.
