# LibSettingsCanvas-1.0

`LibSettingsCanvas-1.0` is a small LibStub library for custom Blizzard Settings canvas panels.

It owns the reusable Settings UI shell shared by BetterTrackedBars, BetterLootWindow, and BetterKeystoneDisplay:

- scroll-frame panel setup
- collapsible section headers
- row relayout
- labels, edit boxes, buttons, dropdowns, checkboxes, compact sliders with typed numeric input, and color swatches
- hover tooltip wiring for custom canvas rows
- icon/text action lists for blacklist-style panels
- generic profile-management and profile-sharing section layouts

The profile section helpers use fixed layouts and retain their content height during normal panel refreshes.

Addon-specific data reads, writes, option lists, and profile behavior should stay in the consuming addon.

To embed it in another addon, load `LibSettingsCanvas-1.0.lua` after `LibStub`, or include this directory's `lib.xml`.
