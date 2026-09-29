# Party XP

Party XP adds small experience bars beside Blizzard party member frames. A party member must also have Party XP installed for their XP to appear: World of Warcraft exposes your own XP to addons, and Party XP shares it with your party through addon messages. Bars disappear for max-level members, missing data, raids, and when disabled.

On your first login with Party XP, a one-time popup explains that other party members need the addon for their XP bars to appear.

The addon supports Blizzard's standard and raid-style party frames. It does not attach to third-party unit frames.

## Settings

Open Escape -> Options -> AddOns -> Party XP, or type `/partyxp` or `/pxp` to open the same settings panel. You can change bar width, height, position, offsets, opacity, and color. The Appearance section also offers Classic, Flat, Gloss, and Striped fills; optional Thin, Bold, or Gold borders; and rounded edges. The XP text section can show each member's exact current / max XP at one of nine points on the bar, with separate horizontal and vertical offsets. XP text is off by default. `/partyxp on` and `/partyxp off` toggle the bars. Settings are saved between sessions.

## Local installation

Run `./scripts/copy-to-wow.ps1` in PowerShell to copy the addon to installed WoW clients. Pass `-WowRoot "D:\World of Warcraft"` if automatic discovery misses your installation. Use `-WhatIf` to preview destinations.

The included Ace3 configuration libraries, bar textures, and addon icon are copied with the addon. The Ace3 libraries come from [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3) at commit `a3604956e6e98a2b41144e7dbffadb21b917f828`; their license is in `Libs/LICENSE-Ace3.txt`. To rebuild the bar textures and icon, run `python scripts/build-media.py`.

## Development

Run `busted --output=TAP` from this directory. The test drives addon loading, party messages, XP changes, frame switching, stale data, and settings against a mocked game runtime. For a repeatable result, run `./scripts/test.ps1`; it writes `artifacts/party-xp-e2e.tap`. CI uploads the same artifact.

For an in-game check, run `./scripts/copy-to-wow.ps1`, log into two characters with the addon, group them, and open Escape -> Options -> AddOns -> Party XP. Check that `/partyxp` opens that same page and that settings update the bars. The receiving character should see the other character's XP bar after they group; test both Blizzard party-frame styles and a max-level character.

The release workflow follows BuffTimers' BigWigs packager setup. A `v*` tag creates GitHub releases for Retail, Classic Era, Mists of Pandaria, and Forever. CurseForge or Wago publication can be added when this addon has project IDs and API tokens.
