---
name: wow-addon-architect
description: Verified World of Warcraft addon architecture, API research, Lua 5.1, Widget API, Blizzard UI source, taint, protected-frame, secret-value, cooldown, cast, resource, and Cooldown Manager guidance. Use when Codex changes, reviews, tests, or explains BetterCooldownManager or other Retail WoW addon UI code.
---

# WoW Addon Architect

## Workflow

1. Establish the target client version. BetterCooldownManager targets Retail 12.1.
2. Read `AGENTS.md`, the root README, the relevant package README, `.context/api.md`, and `.context/patterns.md` before editing.
3. Identify the ownership boundary: Blizzard-owned viewer objects versus BCM-owned tracker, trinket, cast, and resource frames.
4. Verify API and widget facts against Warcraft Wiki, the Lua 5.1 manual, and `.libraries/wow-ui-source/Interface/AddOns`. If local Blizzard source is absent, report that it must be refreshed instead of guessing.
5. Implement through existing module boundaries. Prefer guarded reads, addon-owned state, coalesced events, duration bindings, and shared schedulers.
   For custom spell auras, use 12.1 AuraContainers prepared outside combat and configure AuraButtons during their initialization callback.
6. Keep migrations lossless and idempotent. Preserve old data until the new representation is known to be complete.
7. Validate with focused pure-Lua tests, Lua 5.1 syntax checks, `git diff --check`, and live-WoW scenarios appropriate to the change.

## Guardrails

- Do not invent WoW APIs, enums, widget methods, or Blizzard object fields.
- Treat Blizzard frame, cooldown, aura, and tooltip data as potentially secret or inaccessible.
- Do not introduce `UnitAura` enumeration for custom tracker state.
- Do not inspect AuraButton visibility or mutate returned AuraButtons outside the guarded initialization/style path; their visibility may be secret-controlled.
- Do not write BCM metadata onto Blizzard-owned frames or take ownership of their visibility.
- Do not add permanent polling or one updater per tracked entry.
- Keep Lua compatible with WoW's Lua 5.1 environment.
- Make unverified behavior and required live validation explicit.

## Review priorities

Lead with runtime errors, taint/forbidden risks, secret-value misuse, migration data loss, broken profile behavior, event leaks, and missing tests. Confirm the staged diff and commit boundary before committing.
