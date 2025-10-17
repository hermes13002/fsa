# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
- Prepare for enhancements: better tests, more robust scanning, CLI flags (future).

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
