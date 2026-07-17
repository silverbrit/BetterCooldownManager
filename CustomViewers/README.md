# Custom Viewers

`CustomTrackerBar.lua` owns reusable named tracker bars and the shared source-adapter contract for spells, items, equipment slots, and fixed-duration cast timers. Bar and entry IDs are stable profile data; display order lives in explicit arrays. Runtime icons are pooled and refreshed through one coalesced event frame.

Equipment sources read the currently equipped item and its slot cooldown. Timer sources match readable player `UNIT_SPELLCAST_SUCCEEDED` spell IDs, keep expiration state only for the current session, and share one scheduled wakeup for the next expiration.

`TrinketBar.lua` remains a separate automatic viewer for equipped usable trinkets.

Legacy Custom, Additional Custom, Item, and Items & Spells profiles are converted by `Core/CustomTrackers.lua`. Migration is idempotent, merges repeated spell specialization data, remaps inter-viewer anchors, and removes legacy fields only after conversion succeeds.

BCM owns these frames and may apply visibility and entry behavior to them. Blizzard Cooldown Viewer rows remain outside this package's ownership.
