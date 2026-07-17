# Options

Better Cooldown Manager hosts its LibSettingsCanvas panels in a draggable, resizable addon-owned window and also registers them with Blizzard's AddOns Settings.

- `Settings.lua` keeps addon-wide controls, shared visibility, and shared bar appearance on the root page,
  registers the Cooldown Viewer page, and owns the individual viewer, power bar, and cast bar pages.
- `Profiles.lua` owns profile management, specialization and Edit Mode layout routing, and import/export controls.
- `Entries.lua` owns named custom-bar management and the spell, item, equipment, timer, ordering,
  activation, appearance, load-condition, and optional extra aura-ID editors for each entry.
- `Utils.lua` adapts BCDM state and callbacks to `LibSettingsCanvas-1.0` rows.
- `Window.lua` hosts those panels in BCDM's draggable and resizable settings window.

Reusable panel layout, collapsible sections, standard controls, tooltips, and profile layouts belong to
`Libraries/LibSettingsCanvas-1.0`. BCDM-specific state and update behavior remain in this directory.
