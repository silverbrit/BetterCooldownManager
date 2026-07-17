# API

Verify World of Warcraft APIs at <https://warcraft.wiki.gg/wiki/World_of_Warcraft_API>, widget methods at <https://warcraft.wiki.gg/wiki/Widget_API>, and Lua behavior in the <https://www.lua.org/manual/5.1/> manual.

Use `.libraries/wow-ui-source/Interface/AddOns` for Blizzard implementation research. Refresh the local snapshot when required files are absent.

## Retail 12.1 notes

- Secret values and forbidden objects are separate failure modes. Do not compare, stringify, index with, or branch on a value unless its readability is established.
- Aura index, slot, and instance queries can error when auras are secret. Custom trackers must not depend on `UnitAura` iteration.
- `SetParent` and `SetPoint` can error when forbidden aspects propagate. BCM-owned frames should anchor only to safe known frames and fall back to `UIParent` when an imported anchor fails.
- Prefer `C_DurationUtil.CreateDuration()` and widget duration bindings when they can accept source timing without Lua countdown polling.
- Equipment cooldown trackers use `GetInventoryItemCooldown("player", slot)` and refresh from equipment/bag/cooldown events.
- Re-verify exact signatures against the installed PTR source before adding or changing API calls.
