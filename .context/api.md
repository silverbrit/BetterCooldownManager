# API

Verify World of Warcraft APIs at <https://warcraft.wiki.gg/wiki/World_of_Warcraft_API>, widget methods at <https://warcraft.wiki.gg/wiki/Widget_API>, and Lua behavior in the <https://www.lua.org/manual/5.1/> manual.

Use `.libraries/wow-ui-source/Interface/AddOns` for Blizzard implementation research. Refresh the local snapshot when required files are absent.

## Forever 1.60.1 notes

- Detect Forever using the fourth `GetBuildInfo()` return (`16001`), not just the modern UI family/project ID.
- `.libraries/wow-ui-source-forever/Interface/AddOns` is Gethe's `forever` branch (verified at build 69913). Camelot overrides are selected by the Blizzard TOCs; the presence of a Retail file alone does not mean it loads on Forever.
- `Blizzard_FrameXMLBase/Camelot/Constants.lua` lists nine playable class tokens in `CLASS_SORT_ORDER`. Use `Constants.UICharacterClasses` for IDs rather than assuming IDs are contiguous.
- `Blizzard_UnitFrame/Blizzard_UnitFrame.toc` excludes Retail class-resource widgets on Camelot. Its shared `Mainline/ComboFrame.lua` reads `GetComboPoints("player", "target")`, `UnitPowerMax` for the maximum, and refreshes on `PLAYER_TARGET_CHANGED` as well as power events.
- `Blizzard_DeprecatedSpecialization` does not load on Camelot: use `C_SpecializationInfo.GetSpecialization` / `GetSpecializationInfo`, not the deprecated globals. Camelot's `ClassTalents` UI uses two talent groups via `GetActiveSpecGroup`, not Retail specialization profile slots.
- Forever includes the modern Cooldown Viewer, Edit Mode, duration, and custom AuraContainer APIs. Keep the same ownership and secret-value guardrails as Retail.

## Retail 12.1 / 12.1.5 notes

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
- In 12.1.5, `Cooldown:SetCooldown` and `Cooldown:Clear` cannot be called from tainted code on protected cooldown frames. BCM's custom cooldowns are addon-owned; do not apply these methods to protected Blizzard frames.
- Castbar IDs are unique per unit token in 12.1.5. Query with lowercase `"player"` to match `UNIT_SPELLCAST_*` events; never compare IDs from different unit tokens.
- In 12.1.5, `CustomAuraButton`'s `RemoveDispelTypeTexture` and `RemovePandemicRegion` accept a region reference rather than the index formerly returned by their Add methods.
- Re-verify exact signatures against the installed PTR source before adding or changing API calls.
