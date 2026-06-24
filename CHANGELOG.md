# Changelog

All notable changes to Halo are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-23

### Added
- Single minimap launcher (LibDBIcon) that gathers all other addon buttons.
- Detection of both LibDBIcon buttons and legacy hand-parented minimap buttons,
  including buttons that register after login.
- Animated flyout tray with a flat, modern dark theme (fade + scale, hover
  highlights, soft shadow) laid out in a reflowing grid.
- Custom settings panel via the modern `Settings` API: columns, tile size,
  spacing, open-on-hover, auto-hide, tray opacity, tray scale, and a per-button
  opt-out list.
- Lossless release: opted-out buttons return to the minimap with their original
  anchors intact.
- Slash commands: `/halo`, `/halo config`, `/halo reset`, `/halo help` (and `/hl`).
- Headless CI: luacheck plus a mock-WoW load test that simulates a full session.
- BigWigs packager release workflow.

[Unreleased]: https://github.com/adbergen/Halo/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/adbergen/Halo/releases/tag/v1.0.0
