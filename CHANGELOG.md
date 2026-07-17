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

### Cooldown Viewers and Profiles

- Migrated the existing viewer layout, anchoring, icon, text, glow, spell, item, ordering, and load-condition controls to the new Settings interface.

### Development

- Added a modular Options implementation built around LibSettingsCanvas-1.0.
- Removed the AceGUI, AceDBOptions, and unused SharedMedia widget dependencies.
- Added `install-deps.sh` for refreshing vendored libraries.
- Updated packaging configuration to include only the required libraries.
