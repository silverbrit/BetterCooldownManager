# Custom Viewers

`CustomTrackerBar.lua` owns reusable named tracker bars and the shared source-adapter contract for spells, items, equipment slots, and fixed-duration cast timers. Bar and entry IDs are stable profile data; display order lives in explicit arrays. Non-aura runtime icons are pooled; structural events rebuild eligible icons while cooldown and charge events update existing icon state through one coalesced event frame. Spell cooldown availability is separate from current-player spell knowledge, so known AuraContainer-only spell IDs can render without pretending they are learned cooldowns while unknown or foreign-class/racial IDs stay hidden.

`AuraSourceDisplay.lua` gives spell entries a Retail 12.1-only AuraContainer layer. Player helpful and player-cast target helpful/harmful auras bind directly to Blizzard-managed icon, cooldown, stack, and tooltip widgets. Containers are prepared outside combat and stable spell frames are not returned to the generic pool. The ordinary spell cooldown remains underneath when no candidate aura is active.

Item sources require at least one readable inventory copy and disappear when their count reaches zero. Equipment sources read the currently equipped item and its slot cooldown. Timer sources match readable player `UNIT_SPELLCAST_SUCCEEDED` spell IDs, keep expiration state only for the current session, and share one scheduled wakeup for the next expiration.

`TrinketBar.lua` remains a separate automatic viewer for equipped trinkets, with shared behavior and optional per-slot overrides. Equipped-item and Cooldown Viewer catalog changes rebuild its slots; cooldown events update existing slot widgets without rescanning tooltips or catalog records. Its AuraContainer candidates use every readable 12.1 equip-slot catalog spell field (`spellID`, override spell IDs, and linked spell IDs) without probing aura data in Lua.

Legacy Custom, Additional Custom, Item, and Items & Spells profiles are converted by `Core/CustomTrackers.lua`. Migration is idempotent, merges repeated spell specialization data, remaps inter-viewer anchors, normalizes optional extra aura IDs, and removes legacy fields only after conversion succeeds.

BCM owns these frames and may apply visibility and entry behavior to them. Blizzard Cooldown Viewer rows remain outside this package's ownership.
