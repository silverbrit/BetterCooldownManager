# BetterCooldownManager

[![Join Discord](https://img.shields.io/badge/Discord-7289DA?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/UZCgWRYvVE)
[![Twitch](https://img.shields.io/badge/Subscribe-9146FF?style=for-the-badge&logo=twitch&logoColor=white)](https://www.twitch.tv/subs/UnhaltedGB)
[![Patreon](https://img.shields.io/badge/Patreon-FF424D?style=for-the-badge&logo=patreon&logoColor=white)](https://patreon.com/Unhalted)
[![Donate](https://img.shields.io/badge/Donate-1E88E5?style=for-the-badge&logo=streamlabs&logoColor=white)](https://streamelements.com/unhaltedgb/tip)
[![KoFi](https://img.shields.io/badge/KoFi-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://ko-fi.com/unhalted)

## Supported clients

This package targets Retail 12.1.5 (`120105`) only. The retained WoW Forever 1.60.1 (`16001`) integration shares the modern Cooldown Viewer, Edit Mode, and AuraContainer code, but is not advertised by this TOC. Its client-specific paths expose nine playable classes, mana/rage/energy colours, and target-based rogue/cat combo points, hide Retail-only resource and empowered-cast options, and preserve saved Retail settings.

`install-deps.sh` refreshes the Retail PTR UI source in `.libraries/wow-ui-source` and Forever's `forever` branch in `.libraries/wow-ui-source-forever`. Run `lua5.1 Scripts/test.lua` for pure-Lua checks; combat, secret-value handling, and Edit Mode still require live testing on both clients.

## Features
- Clean, Pixel Border Skinning. Borders can be adjusted.
- Minimap button for opening the Better Cooldown Manager settings.
- Custom Cooldown Text, Tweaks & Glows.
- Custom Power & Secondary Power Colours.
- Power Bar, Secondary Power Bar & Cast Bar with Anchoring & Auto Adjustment for Width.
- Power text can show Current / Maximum; optional mana-cost prediction darkens the pending spend while casting, using native widgets for secret values.
- Custom Tracker Bars: Add any known spell, item, equipment slot, or cast timer.
- Custom Trinket Bar: Automatically creates trackers for equipped trinkets.
- API for AddOns to add their own anchors to Utility, Tracked Buffs, Custom Trackers, and Trinket Bars.
- WoW Forever exposes Blizzard's Main Hand, Off Hand, and Ranged swing timers as anchor parents, styled with BCM's shared textures, font, border size, and class-coloured fill. Position, size, visibility, and timing remain controlled by Blizzard/Edit Mode.

## Libraries
- [Ace3](https://www.curseforge.com/wow/addons/ace3): Provides the addon lifecycle, profiles, localization, and serialization.
- [LibSharedCanvas-1.0](https://github.com/silverbrit/LibSharedCanvas): Provides the shared settings canvas, collapsible sections, controls, and profile layouts used by BetterCooldownManager's draggable options window and Blizzard AddOns Settings.
- [LibDeflate](https://github.com/SafeteeWoW/LibDeflate.git): Handles importing/exporting of profiles.
- [LibDualSpec](https://github.com/AdiAddons/LibDualSpec-1.0.git): Handles specialization profiles.
- [LibSharedMedia](https://www.curseforge.com/wow/addons/libsharedmedia-3-0): Handles all additional media for the AddOn.
- [LibEditModeOverride](https://github.com/plusmouse/LibEditModeOverride): Helps manage EditMode securely.
- [LibDataBroker-1.1](https://www.curseforge.com/wow/addons/libdatabroker-1-1): Exposes the minimap launcher to addon managers.
- [LibDBIcon-1.0](https://www.curseforge.com/wow/addons/libdbicon-1-0): Registers the standard minimap button.

All of these libraries contribute to the success of BetterCooldownManager & are highly appreciated by myself.
