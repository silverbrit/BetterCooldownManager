# Options

Better Cooldown Manager hosts its LibSharedCanvas panels in a draggable, resizable addon-owned window and also registers them with Blizzard's AddOns Settings.

- Forever hides Retail-only resource colours, secondary-to-primary swapping, and empowered-cast controls. Class/spec menus use Blizzard's client-specific class list (including sparse class IDs); imported settings for unavailable classes are retained, not deleted. Its Main Hand, Off Hand, and Ranged swing timer frames are available as anchor parents.
- `Settings.lua` keeps addon-wide controls, including minimap-button visibility, shared visibility, and shared bar appearance on the root page,
  and owns the individual viewer, power bar, and cast bar pages; cast spell names remain full and are clipped only at the available space before the duration text.
- Power Bar text supports `Current / Maximum` (for example `141 / 141`). `Show Mana Cost Prediction` defaults on and highlights the pending mana cost during casts, in either fill direction. Cast/power events clear or refresh it. A clipped StatusBar extends backward from the native mana-fill endpoint, forwarding secret cast IDs, costs, and maximum mana to accepting APIs/widgets without Lua arithmetic. Inaccessible data suppresses the preview.
- `Profiles.lua` owns profile management, specialization and Edit Mode layout routing, and import/export controls. Forever offers primary/secondary talent-group profile slots instead of Retail specialization slots.
- `Entries.lua` owns named custom-bar management, the drag-to-reorder icon strip, focused entry editor,
  and spell, item, equipment, timer, load-condition, and optional extra aura-ID controls. Spell load-condition menus expose every class/spec so racial and shared bars can be configured across characters; cast timers retain their originating-class scope. New entries start with no selections, which means unrestricted, and become specialization-restricted after the first selection.
- `Trinkets.lua` owns equipped-slot selection, shared trinket behavior, and focused per-slot overrides. Its selector and drag targets follow the live bar's left-to-right order (top-to-bottom for vertical bars), including reversed growth. New defaults show all equipped trinkets and center the bar on Blizzard's UIParent unless ElvUI or EllesmereUI Unit Frames provides a player-frame anchor.
- The Tracked Bars page embeds Better Tracked Bars' registered settings canvas in the standalone window when that optional addon is loaded, with the recommendation page as a fallback.
- `Utils.lua` adapts BCDM state and callbacks to `LibSharedCanvas-1.0` rows.
- `Changelog.lua` contains the generated runtime copy of the current `CHANGELOG.md` release notes.
- `Window.lua` hosts those LibSharedCanvas panels in BCDM's draggable and resizable settings window, including the sidebar Changelog page and persisted opacity control.
- Essential and Utility share the same configurable parent-anchor model. Essential, Utility, and Tracked Buff pages continue to open Blizzard's native Cooldown Manager automatically on the matching Spells or Buffs tab. Both opening the panel and selecting its tab use the native secure-call boundary, since tab selection can rebuild shared cooldown data. Viewer anchor changes save through LibEditModeOverride and securely update only the native Cooldown Viewer systems without opening Edit Mode, replacing Edit Mode manager state, or refreshing CompactUnitFrames, so both windows remain usable; addon-owned and late-loading ElvUI or EllesmereUI parents are persisted through `UIParent`, and changes are still deferred during combat, Edit Mode, or a pending native-panel open.

Reusable panel layout, collapsible sections, standard controls, tooltips, and profile layouts belong to the external
[`LibSharedCanvas-1.0`](https://github.com/silverbrit/LibSharedCanvas) dependency. BCDM-specific state and update behavior remain in this directory.
