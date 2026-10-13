# Changelog

## 34 (October 13 2026)

### Updated

- Updated interface compatibility to Retail 12.1.5 only (`120105`); older Retail and WoW Forever interfaces are no longer advertised by this package.
- Changed cast-time text to show tenths of a second instead of whole seconds.
- Updated addon/minimap branding and launcher tooltips, and kept Better Tracked Bars settings embedded in the native options panel.
- Updated dependency tooling to retain separate Retail PTR and WoW Forever UI-source snapshots for API verification.
- Retained the unreleased WoW Forever-specific class/resource menus, target-based combo points, talent-group profile routing, and native swing-timer styling/anchors in code; the TOC for this release remains Retail-only.

### Added

- Added optional mana-cost prediction on the power bar using native widgets for secret cast costs and maximum mana, with either fill direction and cast-event cleanup.
- Added player-aura presentation for item trackers using the item's use-effect spell ID, with yellow active-aura countdowns; equipped trinket aura overlays now also bind their icon and duration cooldown.

### Fixed

- Hide unavailable spells and depleted item trackers, and stop disabled item cooldowns such as used Healthstones from repeatedly flashing before their timer starts.
- Show passive and on-use trinkets by default, reset and migrate their default anchors for UIParent, ElvUI, or EllesmereUI, and match selector/reorder positions to the live bar's growth direction.
- Use client-specific class lists and namespaced specialization queries while preserving saved settings for unavailable classes.
- Apply native viewer layouts, Pandemic anchors, glow cleanup, and settings/tab changes through their secure native call boundaries to reduce shared Cooldown Viewer taint.
- Keep viewer positions in the coalesced Edit Mode save path without opening Edit Mode or closing settings, and refresh matched-width bars after native viewer layout changes.
- Preserve full cast spell names with clipping and duration-text spacing, and correct preview refresh, centering, and anchor behavior.

### Performance

- Coalesce lifecycle/settings refreshes, defer settings work, cache resource and equipped-trinket lookups, and avoid unchanged visibility writes or tracker-timer rescheduling.
- Expanded regression coverage for cast/resource bars, item auras, trinket ordering, native viewer integration, secret-value handling, and retained client-specific paths.

## 33 (August 18 2026)

- Thanks to Unhalted for letting us continue development on Better Cooldown Manager for 12.1 and beyond. If you have suggestions or find an issue, please let us know on Discord.

### Settings

- Replaced the legacy AceGUI configuration window with a draggable, resizable LibSharedCanvas-1.0 window, while retaining access through Blizzard's AddOns Settings.
- Reorganized settings into focused pages for viewers, bars, trackers, profiles, and media, with profile controls, previews, and highlights.
- Added a dedicated Tracked Bars page that embeds Better Tracked Bars settings when the optional addon is installed.
- Added controls for viewer layout and anchors, icon/text/glow appearance, bar visibility, fill direction, sparks, and resource/cast text modes.

### Custom Trackers and Auras

- Replaced the legacy Custom Cooldowns and Additional Custom viewers with named, reorderable mixed-source tracker bars.
- Added spell, item, equipment-slot, and fixed-duration cast sources with shared defaults, per-entry overrides, class/specialization filters, load conditions, inactive states, glows, tooltips, and live previews.
- Added Retail 12.1 `CustomAuraContainerTemplate` presentation for player and target auras, including extra aura IDs and automatic cooldown fallback, without `UnitAura` reconstruction.
- Added idempotent migration for legacy tracker profiles while preserving order, appearance, filters, anchors, and entry settings.

### Trinkets and Resource Bars

- Reworked the Trinket Viewer around equipped slots 13/14, asynchronous item loading, cooldown events, passive/on-use filtering, ordering, and active-aura stack counts.
- Updated power, secondary-power, and cast bars with secret-safe value handling, matched widths, configurable colours/text/fill direction, sparks, interruptibility, and empowered cast stages.

### Blizzard Integration and Safety

- Kept Blizzard Cooldown Viewer and native bar frames Blizzard-owned; BCM only styles and positions them through guarded addon-owned metadata.
- Added protected/inaccessible anchor fallbacks, combat-safe refreshes, dynamic Edit Mode preset handling, and safer Tracked Buff centering/restoration to reduce taint and layout races.
