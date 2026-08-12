# AGENTS.md

This is the canonical AI working guide for BetterCooldownManager. Assistant-specific files should point here instead of duplicating project state.

## Project overview

BetterCooldownManager is a Retail World of Warcraft addon that styles Blizzard Cooldown Manager viewers and owns optional custom tracker, trinket, power, secondary-power, and cast bars.

- `Core/` owns lifecycle, defaults, migrations, shared data, public APIs, and event coordination.
- `Modules/` owns Blizzard Cooldown Manager styling and BCM-owned cast/resource bars.
- `CustomViewers/` owns BCM-created cooldown tracker frames.
- `Options/` owns LibSharedCanvas pages, profile controls, and entry editors.
- `Libraries/` contains bundled dependencies; edit them only for an explicit dependency fix.

## First reads

Before changing code, read the root `README.md`, the README for the package being changed, `.context/api.md`, and `.context/patterns.md`. For deep WoW API, widget, taint, secret-value, or Blizzard UI work, use `.codex/skills/wow-addon-architect/SKILL.md`.

Use `.libraries/wow-ui-source/Interface/AddOns` for Blizzard implementation research. If it is missing, refresh it with `install-deps.sh`; do not substitute assumptions about FrameXML.

## Runtime guardrails

- Target Retail WoW 12.1 (`120100`) and Lua 5.1.
- Verify API names and signatures. Do not invent enum values, widget methods, or Blizzard frame fields.
- Treat cooldown, aura, tooltip, and Blizzard-frame values as potentially secret or inaccessible.
- Do not add `UnitAura`-driven custom tracker logic or mutate Blizzard Cooldown Viewer row ownership.
- Use `CustomAuraContainerTemplate` for custom spell aura presentation. Create containers outside combat, configure AuraButtons in their initialization callback, and never branch on their secret-controlled shown state.
- Keep BCM-owned behavior on BCM-owned frames. Store metadata about Blizzard frames in addon-owned side tables.
- Prefer event-driven refreshes and shared schedulers over per-entry `OnUpdate` handlers or permanent polling.
- Use guarded reads and degrade cleanly when a value cannot safely be inspected.
- Keep migrations idempotent and preserve legacy data until conversion has completed successfully.

## Documentation

Update package READMEs when behavior, architecture, configuration, or developer workflow changes materially. Keep `.context/patterns.md` focused on durable lessons rather than a changelog.

## Verification

After Lua changes, run the available pure-Lua tests, Lua 5.1 syntax checks, and `git diff --check`. Also run `bash -n install-deps.sh` after tooling changes. Pure-Lua checks do not replace live WoW testing for combat, taint, secret values, cooldown behavior, or Edit Mode.

## Git workflow

- `upstream` is the official `DaleHuntGB/BetterCooldownManager` repository and must remain fetch-only with a disabled push URL.
- Development occurs on local feature branches. Do not create a fork, push, or open a pull request unless the user explicitly authorizes it.
- The eventual `origin` remote belongs to the Silverbrit fork. Rebase onto current `upstream/main` and run full validation before the first push.
- Keep feature phases in focused, buildable commits with their relevant tests. Inspect staged scope before every commit.
- Never include `.libraries`, editor caches, or unrelated user changes in a commit.
