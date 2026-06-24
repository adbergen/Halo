# Contributing to Halo

Thanks for your interest! Halo aims to be small, modern, and exceptionally tidy —
contributions should keep it that way.

## Getting set up

1. Clone the repo into your AddOns folder (or clone elsewhere and symlink):
   `World of Warcraft\_classic_\Interface\AddOns\Halo`
2. Make changes, then `/reload` in-game to test. Enable `/console scriptErrors 1`
   to surface Lua errors.

## Before you open a PR

Run both checks locally — they must pass (CI runs them too):

```bash
luacheck .          # style + static analysis
lua Tests/run.lua   # headless load test under a mock WoW API
```

If you add a new `.lua` file, add it to `Halo.toc` (and to the `FILES` list in
`Tests/run.lua`) in the correct load order.

## Conventions

- **Indentation:** real tabs (see `.editorconfig`).
- **No globals:** everything hangs off the shared `ns` table passed via `...`.
  The only intentional globals are `HaloDB` and the slash command tokens.
- **Modules:** one responsibility per file. Detection, collection, look, and
  config stay separate.
- **Comments:** explain *why*, not *what*. Each file opens with a short purpose
  block.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:` …).
- **Localization:** user-facing strings go through `ns.L["..."]` and are added to
  `Locales/enUS.lua`.

## Releasing (maintainers)

1. Update `CHANGELOG.md` and the `## Version` in `Halo.toc`.
2. Tag and push: `git tag v1.2.3 && git push --tags`.
3. The release workflow packages the zip and creates the GitHub Release.
