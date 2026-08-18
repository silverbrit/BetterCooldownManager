local _, BCDM = ...

-- Generated runtime copy of CHANGELOG.md; WoW cannot read Markdown files.
BCDM.ChangelogText = [=[
# Changelog

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
]=]
