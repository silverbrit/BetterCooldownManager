# Changelog

## Unreleased

### Settings

- Replaced the AceGUI configuration window with a draggable, resizable Better Cooldown Manager window powered by LibSharedCanvas-1.0, while retaining access through Blizzard's AddOns Settings.
- Added dedicated categories for individual cooldown viewers, power bars, the cast bar, and profiles, with all sections expanded by default.
- Reorganized settings by scope: shared appearance options remain on the main page, viewer-specific options live with their viewer, resource colours live with their respective power bars, and Edit Mode layout routing now lives under Profiles.
- Removed the redundant Cooldown Viewers category and moved native viewer skinning, icon zoom, cooldown text, and custom glow settings to General according to their actual scope.
- Blizzard's Cooldown Manager now opens automatically to the matching Spells or Buffs tab when Essential Cooldowns, Utility Cooldowns, or Tracked Buffs is selected in the standalone settings window.
- Removed redundant or empty settings groups and simplified category navigation.
- Added compact, typeable numeric fields to every slider.
- Added LibSharedMedia font previews and status-bar texture swatches.
- Added a persistent Community & Support footer and installed version display to the addon-owned settings window.
- Added the Better Cooldown Manager logo beside the settings-window title.
- Removed obsolete Apply Size Changes controls and misleading Edit Mode refresh guidance.
- Standardized profile-scoped General settings on Shared terminology and renamed the Buff Icons category to Tracked Buffs.
- Added a dedicated Tracked Bars settings page recommending Better Tracked Bars.
- The standalone Tracked Bars page now embeds Better Tracked Bars settings when the compatible optional addon is installed and enabled.
- Added location highlights for the trinket viewer and selected custom tracker bar, including empty-bar footprints.
- Added selected-element highlights for resource and cast bars, a global highlight toggle, and consistent disabled-section treatment for their settings pages.
- Trinket Viewer now includes passive trinkets by default, offers an on-use-only filter, and displays active-aura stacks from 12.1 equip-slot aura metadata.
- Added an equipped-trinket selector, live Settings preview, shared entry behavior, and optional per-slot overrides matching Custom Trackers.
- Added drag ordering for equipped trinket slots and applied the saved order to the runtime bar.
- Standardized Custom Tracker and Trinket settings icon sizing and cropping, and removed Blizzard's cooldown bling border from the runtime Trinket Viewer.
- Fixed custom tracker and trinket location highlights lagging behind section changes or using offset container bounds.
- Fixed custom tracker corner anchors drifting by half the bar size because icon layout started at the container center.
- Tightened profile-management spacing and aligned the first Settings section with the navigation panel.
- Clarified cast and secondary-resource controls by hiding unsupported colour choices and renaming the non-interruptible cast test.

### Cooldown Viewers and Profiles

- Migrated the existing viewer layout, anchoring, icon, text, glow, spell, item, ordering, and load-condition controls to the new Settings interface.
- Added shared visibility policies with optional per-bar overrides for BCM-owned custom tracker, trinket, resource, and cast bars.

### Custom Trackers

- Replaced separate Custom Cooldowns and Additional Custom configurations with named, duplicable mixed-source tracker bars.
- Replaced the dense entry rows with a scrollable icon strip, drag ordering, focused selected-entry controls, and a type-aware add menu.
- Added per-bar Custom Tracker icon dimensions and charge, stack, and item-count text settings.
- Added live Custom Tracker Settings previews for configured entries, including appearance, glow, text, and entries currently filtered or unavailable.
- Added shared Custom Tracker display, appearance, glow, text, tooltip, class, and specialization settings with opt-in per-entry overrides, and real bag counts in the entry editor.
- Split shared entry defaults into their own collapsible section and added item/spell drag-and-drop onto the entry list's + button.
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

- Added a modular Options implementation built around the externally maintained LibSharedCanvas-1.0.
- Removed the AceGUI, AceDBOptions, and unused SharedMedia widget dependencies.
- Added `install-deps.sh` for refreshing vendored libraries.
- Updated packaging configuration to include only the required libraries.
- Added Retail 12.1 Blizzard UI source installation, pure-Lua model tests, and repository-local Codex architecture guidance.
- Removed the legacy Disable Aura Overlay hooks and manual aura/cooldown reconstruction.
- Replaced continuous Buff Icon centering polling with coalesced Blizzard layout and shown-state hooks.
