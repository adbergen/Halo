# Changelog

All notable changes to Halo are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Drag-to-reorder buttons within the tray (grid mode); order is saved. A ghost
  icon lifts and follows the cursor while the other tiles glide to open a gap at
  the drop slot (midpoint targeting), then the ghost flies into place and fades.
- Shared eased-tween engine (UI/Animation.lua) powering the drag/drop motion.
- Radial layout mode — buttons orbit the launcher in a ring.
- Search box that appears once 10+ buttons are collected and filters the tray.
- Profile management UI (create/switch/copy/delete) via AceDB profiles.
- Masque skinning support for the launcher button.
- Options to opt specific Blizzard minimap frames into the tray: Looking For
  Group, Mail, Tracking, and Battlegrounds (off by default).
- `/halo scan` diagnostic listing every collected button's render state.

### Fixed
- Collected buttons now render inside the tray instead of behind it (LibDBIcon
  locks its buttons' frame strata via SetFixedFrameStrata; Halo unlocks them and
  the tray sits at MEDIUM strata to match).
- Buttons no longer escape back to the minimap (Halo takes sole authority over an
  adopted button's SetPoint).
- Layout is fault-tolerant: one problematic button can't abort the whole tray.
- Quest pins and small map markers are no longer collected (20px size floor).

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
