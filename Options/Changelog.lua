local _, BCDM = ...

-- Generated runtime copy of the current CHANGELOG.md release; WoW cannot read Markdown files.
BCDM.ChangelogText = [=[
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
]=]
