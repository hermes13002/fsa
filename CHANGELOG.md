# Changelog

All notable changes to this project will be documented in this file.

## [0.0.2] - 2025-10-18
### Docs & UX Improvements
- Replaced `log()` with `print()` to ensure console output is visible when running `fsa generate`.
- Updated README with clearer installation and usage instructions.

### Bug Fixes
- Fixed an issue where re-running `fsa generate` would **duplicate the `fonts:` block** in `pubspec.yaml`, causing a `Duplicate mapping key` error.

### Behavior Fixes
- Finalized **font grouping strategy** to **keep font families separate (case-sensitive)** rather than merging similar names.
- Skipped implementation of removed-assets/fonts logging for now (only additions printed in CLI).

## [0.0.1] - 2025-10-17
- Initial release
  - CLI: `fsa generate` to scan `assets/` and `fonts/` and produce outputs.
  - Pubspec editor: rewrites `flutter:` → `assets:` and `fonts:` as explicit multiline blocks.
  - Generator: creates `lib/core/assets/app_assets.dart` with:
    - Uppercase constants preserving file format suffixes (e.g. `LOGO_PNG`).
    - Grouped classes per top-level asset folder and an aggregator `AppAssets`.
    - `AppFontFamilies` for discovered font families.
  - Safe-mode behavior: preserves stable order and avoids destructive edits.
  - README and basic package metadata.

---

## [Unreleased]
- Prepare for enhancements: better tests, more robust scanning, CLI flags (future).
