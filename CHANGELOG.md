# Changelog

All notable changes to Copicol are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-08

First public release.

### Added

- Clipboard capture: plain text, rich text (RTF/HTML), images (PNG/TIFF), files, links with title and icon, and hex colors, with the source app and date.
- Deduplication: copying existing content moves it back to the top of the history.
- Privacy filters: concealed, transient and auto-generated pasteboard content is ignored, as are copies made in excluded apps (1Password, Bitwarden, Keychain Access and Passwords by default).
- Shelf: a panel that slides up from the bottom, left or right edge of the active screen, opened with a configurable global shortcut (⇧⌘V by default), with keyboard navigation, context menu, large preview and drag and drop to other apps.
- Direct paste into the previous app (requires the Accessibility permission), plain-text paste, and a copy-only mode.
- Search that ignores case and accents, with filters by type.
- Pinboards: named, color-coded tabs whose items are never purged.
- Menu bar item to open the shelf, pause capture, clear the history, open the settings and quit.
- Settings: shortcut, retention (1 day, 1 week, 1 month or unlimited), excluded apps, launch at login, sounds, shelf position, card size and paste mode.
- Optional iCloud sync of pinboards and text items under 1 MB, for builds signed with an Apple developer team.
- Universal disk image (Apple silicon and Intel): open it and drag Copicol onto the Applications folder.

[Unreleased]: https://github.com/romainrg/Copicol/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/romainrg/Copicol/releases/tag/v0.1.0
