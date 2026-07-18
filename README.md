# BetterCooldownManager

[![Join Discord](https://img.shields.io/badge/Discord-7289DA?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/UZCgWRYvVE)
[![Twitch](https://img.shields.io/badge/Subscribe-9146FF?style=for-the-badge&logo=twitch&logoColor=white)](https://www.twitch.tv/subs/UnhaltedGB)
[![Patreon](https://img.shields.io/badge/Patreon-FF424D?style=for-the-badge&logo=patreon&logoColor=white)](https://patreon.com/Unhalted)
[![Donate](https://img.shields.io/badge/Donate-1E88E5?style=for-the-badge&logo=streamlabs&logoColor=white)](https://streamelements.com/unhaltedgb/tip)
[![KoFi](https://img.shields.io/badge/KoFi-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://ko-fi.com/unhalted)

## Announcement
- **Issues** are closed for now as I focus on real-life and other ventures. I am happy with the position of BetterCooldownManager. Development will continue but at a slower rate.
- **Pull Requests** can be made but will likely be ignored / looked at less frequently. Please check all closed **Pull Requests** to ensure you are not creating something already denied.

## Features
- Clean, Pixel Border Skinning. Borders can be adjusted.
- Custom Cooldown Text & Tweaks.
- Clickable custom, power-type, class, specialization, and cast-state fill-colour swatches without conflicting toggles.
- Power Bar, Secondary Power Bar & Cast Bar with anchoring, automatic width matching, fill direction, and display controls.
- Named Custom Tracker Bars: create, rename, duplicate, reorder, and anchor reusable mixed-source bars.
- Track spells, items, equipment slots, and fixed-duration cast timers together.
- Custom spells use Retail 12.1 AuraContainers for active player and target auras, with normal cooldowns underneath as the automatic fallback.
- Per-entry ready/active visibility, inactive appearance, glow state, tooltip, class, and specialization behavior.
- Shared visibility rules with per-bar overrides for combat, instance type, mounted/skyriding, dead, vehicle, resting, and macro-condition states.
- Resource text modes, per-bar smoothing overrides, and optional power-bar sparks.
- Class, interruptibility, or custom cast-colour modes plus configurable empowered-stage pips and Settings previews.
- Custom Trinket Bar: This bar will automatically create trackers for equipped & usable trinkets.
- API for AddOns to add anchors to Utility, Buff Icons, Custom Trackers, and Trinket Bars.

## Libraries
- [Ace3](https://www.curseforge.com/wow/addons/ace3): Provides the addon lifecycle, profiles, localization, and serialization.
- **LibSettingsCanvas-1.0:** Provides the shared settings canvas, collapsible sections, controls, and profile layouts used by BetterCooldownManager's draggable options window and Blizzard AddOns Settings.
- [LibDeflate](https://github.com/SafeteeWoW/LibDeflate.git): Handles importing/exporting of profiles.
- [LibDualSpec](https://github.com/AdiAddons/LibDualSpec-1.0.git): Handles specialization profiles.
- [LibSharedMedia](https://www.curseforge.com/wow/addons/libsharedmedia-3-0): Handles all additional media for the AddOn.
- [LibEditModeOverride](https://github.com/plusmouse/LibEditModeOverride): Helps manage EditMode securely.

All of these libraries contribute to the success of BetterCooldownManager & are highly appreciated by myself.

## About the Project
This is a passion project & this has to be maintained as much as possible in order for the longevity of the AddOn. It is solo-developed, but some very kind people from the community have already started contributing.

## Development

The repository targets Retail 12.1 and includes local Codex architecture guidance in `AGENTS.md`, `.context/`, and `.codex/skills/wow-addon-architect/`. Run `install-deps.sh` to refresh development-only Blizzard UI sources and libraries, then use `lua Scripts/test.lua .` for the pure-Lua model tests.

Secondary-resource rules are centralized in `Core/ResourceCatalog.lua`; bar modules consume its descriptors instead of maintaining their own class/spec lookup chains. Custom tracker specialization filters are stored by numeric specialization ID, with legacy token filters retained only when they cannot be converted safely.
