# Patterns

## Ownership boundary

BCM may fully configure frames it creates. Blizzard Cooldown Viewer frames remain Blizzard-owned: observe and style them only through the existing guarded integration paths. Shared visibility and custom entry policies never apply to Blizzard Essential, Utility, BuffIcon, or BuffBar rows.

## Custom tracker model

Use stable numeric bar and entry IDs. Keep presentation order in explicit arrays rather than relying on table iteration. Source adapters expose metadata, state, availability, and relevant events through one contract; layout code must not contain source-specific API branches.

Keep tracker migrations idempotent. Convert every profile, preserve appearance and filters, and remove legacy fields only after a complete successful conversion.

## Events and timers

Coalesce bursts of events into one refresh. Use one shared timer scheduler for fixed-duration entries. Do not create one ticker or `OnUpdate` script per icon.

## Visibility and anchoring

Resolve shared versus local visibility first, apply macro or mode/instance policy, then veto states, then enabled/source availability. Validate inter-bar anchors as a graph, reject cycles, and fall back to `UIParent` for missing or unsafe targets.

## Secret-safe rendering

Guard API reads that may return secret values. When a state cannot safely be interpreted, retain the last valid visual or fail closed instead of probing further. Never use aura enumeration as a fallback for custom cooldown state.
