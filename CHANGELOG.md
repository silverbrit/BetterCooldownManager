# Changelog

## Unreleased

### Settings

- Replaced the AceGUI configuration window with a draggable, resizable Better Cooldown Manager window powered by LibSettingsCanvas-1.0, while retaining access through Blizzard's AddOns Settings.
- Added dedicated categories for cooldown viewers, power bars, the cast bar, and profiles, with all sections expanded by default.
- Reorganized settings by scope: shared appearance options remain on the main page, viewer-specific options live with their viewer, resource colours live with their respective power bars, and Edit Mode layout routing now lives under Profiles.
- Removed redundant or empty settings groups and simplified category navigation.
- Added compact, typeable numeric fields to every slider.
- Added LibSharedMedia font previews and status-bar texture swatches.
- Added a persistent Community & Support footer and installed version display to the addon-owned settings window.
- Removed obsolete Apply Size Changes controls and misleading Edit Mode refresh guidance.
- Standardized profile-scoped General settings on Shared terminology and renamed the Buff Icons category to Tracked Buffs.
- Added location highlights for the trinket viewer and selected custom tracker bar, including empty-bar footprints.
- Trinket Viewer now includes passive trinkets by default, offers an on-use-only filter, and displays active-aura stacks from 12.1 equip-slot aura metadata.
- Fixed custom tracker and trinket location highlights lagging behind section changes or using offset container bounds.
- Fixed custom tracker corner anchors drifting by half the bar size because icon layout started at the container center.

### Cooldown Viewers and Profiles

- Migrated the existing viewer layout, anchoring, icon, text, glow, spell, item, ordering, and load-condition controls to the new Settings interface.
- Added shared visibility policies with optional per-bar overrides for BCM-owned custom tracker, trinket, resource, and cast bars.

### Custom Trackers

- Replaced separate Custom Cooldowns and Additional Custom configurations with named, reorderable, duplicable mixed-source tracker bars.
- Added lossless profile migration for legacy spell, item, and item-spell trackers, including specialization filters and anchor remapping.
- Added equipment-slot cooldown and fixed-duration spellcast timer sources.
- Added per-entry ready/active display rules, inactive appearance, glow state, tooltips, and class/specialization filters.
- Added Retail 12.1 AuraContainer presentation for active player and target spell auras, including optional extra aura IDs and automatic cooldown fallback.
- Removed the dormant BuffBar implementation and settings.

### Cast and Resource Bars

- Added fill direction, optional sparks, and current/maximum/percent text modes.
- Reworked the trinket viewer around persistent equipment-slot icons, asynchronous item loading, and slot cooldown events.
- Added interruptible and non-interruptible cast colours, configurable empowered-stage pips, fill direction, and richer Settings previews.

### Development

- Added a modular Options implementation built around LibSettingsCanvas-1.0.
- Removed the AceGUI, AceDBOptions, and unused SharedMedia widget dependencies.
- Added `install-deps.sh` for refreshing vendored libraries.
- Updated packaging configuration to include only the required libraries.
- Added Retail 12.1 Blizzard UI source installation, pure-Lua model tests, and repository-local Codex architecture guidance.
- Removed the legacy Disable Aura Overlay hooks and manual aura/cooldown reconstruction.
- Replaced continuous Buff Icon centering polling with coalesced Blizzard layout and shown-state hooks.
