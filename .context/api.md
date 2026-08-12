# API

Verify World of Warcraft APIs at <https://warcraft.wiki.gg/wiki/World_of_Warcraft_API>, widget methods at <https://warcraft.wiki.gg/wiki/Widget_API>, and Lua behavior in the <https://www.lua.org/manual/5.1/> manual.

Use `.libraries/wow-ui-source/Interface/AddOns` for Blizzard implementation research. Refresh the local snapshot when required files are absent.

## Retail 12.1 notes

- Secret values and forbidden objects are separate failure modes. Do not compare, stringify, index with, or branch on a value unless its readability is established.
- Aura index, slot, and instance queries can error when auras are secret. Custom trackers must not depend on `UnitAura` iteration.
- Custom spell aura presentation uses `CustomAuraContainerTemplate`, `AddAuraSlot`, and bound `SetDurationCooldown`, `SetIcon`, and `SetApplicationCount` widgets. Create containers outside combat and configure aura buttons inside their initialization callback.
- AuraButton visibility is secret-controlled. Never query it to drive entry layout, Ready/Active policies, or glow state; those remain cooldown-state decisions.
- `SetParent` and `SetPoint` can error when forbidden aspects propagate. BCM-owned frames should anchor only to safe known frames and fall back to `UIParent` when an imported anchor fails.
- Prefer `C_DurationUtil.CreateDuration()` and widget duration bindings when they can accept source timing without Lua countdown polling.
- Equipment cooldown trackers use `GetInventoryItemCooldown("player", slot)` and refresh from equipment/bag/cooldown events.
- Tracked Buff spell-category items resolve their last readable concrete source with `C_Spell.GetLastCategoryCooldownSource`. Prefer `C_Spell.GetSpellCooldownDuration` for category timing; equipment timing may be forwarded directly to an addon-owned Cooldown widget without arithmetic or readiness branches, retaining the last visual if the widget rejects secret arguments.
- `UnitCastingInfo("player")` returns `notInterruptible` in position 8; `UnitChannelInfo("player")` returns it in position 7. Guard either value before branching because cast information can be secret.
- `UNIT_SPELLCAST_INTERRUPTIBLE` and `UNIT_SPELLCAST_NOT_INTERRUPTIBLE` provide a readable event-state transition without re-reading or restarting the cast duration.
- `StatusBar:SetReverseFill` is the verified widget method for leftward resource and cast-bar fill.
- Re-verify exact signatures against the installed PTR source before adding or changing API calls.
