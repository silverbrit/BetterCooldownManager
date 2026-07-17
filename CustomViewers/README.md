# Custom Viewers

`CustomTrackerBar.lua` owns reusable named tracker bars and the shared spell/item source-adapter contract. Bar and entry IDs are stable profile data; display order lives in explicit arrays. Runtime icons are pooled and refreshed through one coalesced event frame.

`TrinketBar.lua` remains a separate automatic viewer for equipped usable trinkets.

Legacy Custom, Additional Custom, Item, and Items & Spells profiles are converted by `Core/CustomTrackers.lua`. Migration is idempotent, merges repeated spell specialization data, remaps inter-viewer anchors, and removes legacy fields only after conversion succeeds.

BCM owns these frames and may apply visibility and entry behavior to them. Blizzard Cooldown Viewer rows remain outside this package's ownership.
