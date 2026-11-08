# Architecture

This document explains how Copicol is built: its modules, data flow, storage and iCloud sync, and the reasons behind them. Read it before changing capture, storage or sync. Commands and contribution rules are in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Overview

- **Platform**: macOS 14 or later, universal binary, menu bar app (`LSUIElement`, no Dock icon).
- **Stack**: Swift 6 toolchain in Swift 5 language mode; SwiftUI, with AppKit where SwiftUI is not enough (`NSPanel`, `NSPasteboard`, `NSStatusItem`, `CGEvent`); SwiftData; CloudKit (optional); LinkPresentation; Carbon (global shortcut); ServiceManagement (login item). No third-party dependencies.
- **Project**: `project.yml` (XcodeGen) generates `Copicol.xcodeproj`. The testable logic lives in a local Swift package, `CopicolCore`, tested without a host app.
- **Pattern**: MVVM with `@Observable`. `AppDelegate` is the composition root. The only singleton is `ClipboardMonitor.shared`, because there is a single general pasteboard.

## Modules

| Module | Location | Responsibility |
|---|---|---|
| Models | `CopicolCore/Sources/CopicolCore/Models` | SwiftData models and content kinds |
| Capture | `CopicolCore/Sources/CopicolCore/Capture` | Read the pasteboard into a `CapturedContent` value (privacy filters, type detection), write items back, hash content, prepare image files |
| Storage | `CopicolCore/Sources/CopicolCore/Storage` | `ClipStore` (ingest, deduplication, retention, pinboards), `FileStore` (large payloads on disk), SwiftData containers |
| Search | `CopicolCore/Sources/CopicolCore/Search` | `ClipQuery`: full-text search, type filters, history or pinboard scope |
| Sync | `CopicolCore/Sources/CopicolCore/Sync` | `CloudMirror`: reconciliation between the local history and the iCloud mirror |
| ClipboardMonitor | `Copicol/ClipboardMonitor` | Poll the pasteboard every 200 ms; fetch link titles and icons |
| HotKey | `Copicol/HotKey` | Global shortcut, key combinations, keyboard layouts |
| PasteService | `Copicol/PasteService` | Write the pasteboard, reactivate the target app, post ⌘V; Accessibility permission; drag providers |
| ShelfUI | `Copicol/ShelfUI` | Non-activating panel, controller (animation, keyboard), view model, cards, tabs, preview |
| Settings | `Copicol/Settings` | Preferences, settings window, launch at login |
| MenuBar, Onboarding | `Copicol/MenuBar`, `Copicol/Onboarding` | Status item menu; welcome window and Accessibility setup |

```
project.yml                          XcodeGen spec: targets, Debug/Release/iCloud configurations, schemes
CopicolCore/
├── Sources/CopicolCore/
│   ├── Models/        ClipKind, ClipItem, Pinboard, SyncedClip (+ SyncTombstone, PendingDeletion)
│   ├── Capture/       CapturedContent, ContentClassifier, PasteboardReader, PasteboardWriter,
│   │                  PayloadBuilder, ContentHasher, HexColor
│   ├── Storage/       ClipStore, FileStore, StorageFactory, RetentionPolicy
│   ├── Search/        ClipQuery
│   └── Sync/          CloudMirror, CloudSyncAvailability
└── Tests/CopicolCoreTests/
Copicol/
├── App/               Entry point, AppDelegate (composition root), SwiftUI window helper
├── ClipboardMonitor/  Pasteboard polling, link metadata
├── HotKey/            Global shortcut
├── PasteService/      Paste, Accessibility, drag and drop
├── ShelfUI/           Panel, controller, view model, views
├── Settings/          Preferences and settings window
├── MenuBar/           Status item
├── Onboarding/        Welcome window
└── Resources/         Entitlements and asset catalog (Info.plist is generated)
Tools/Screenshots/     Offscreen renderer for docs/images (development only)
```

## Data flow

### Capture

1. `ClipboardMonitor` reads `NSPasteboard.general.changeCount` every 200 ms.
2. On a change, `PasteboardReader` extracts the content in priority order: file URLs, image (unless the pasteboard also holds real text), color, text with its RTF and HTML versions, URL. It ignores the change when the pasteboard is empty, marked concealed, transient or auto-generated, written by an excluded app (the frontmost app or the declared `org.nspasteboard.source`), written by Copicol itself, unsupported, or holds an image over 100 MB.
3. `ClipStore.ingest` computes a SHA-256 hash of the kind and content off the main thread. If an item with that hash exists, it is moved back to the top (`lastUsedAt`, `copyCount`). Otherwise the files are prepared in a detached task (TIFF to PNG conversion, 512 px thumbnail) and written to disk, then the item is inserted.
4. `ClipStore.didChangeNotification` lets the shelf reload if it is open. For links, the page title and icon are then fetched with LinkPresentation (10 s timeout).

### Paste

1. When the shelf opens, it remembers the frontmost application: the paste target.
2. On paste, the shelf closes immediately. `PasteService` writes the item to the pasteboard (all its representations, or plain text only), tagged with `org.nspasteboard.source` so that the monitor skips it, and moves the item to the top.
3. In direct paste mode, with Accessibility granted, it reactivates the target app and posts ⌘V with `CGEvent` 0.12 s later. The key code for V is resolved for the current keyboard layout (including layouts such as Dvorak-QWERTY ⌘). In *copy only* mode, the user pastes.

### Shelf

`ShelfPanel` is a non-activating `NSPanel` that can become key: it receives keystrokes without activating Copicol, so the previous app stays frontmost for the paste. A local key monitor sends keys to `ShelfController.handleKeyDown`; a global mouse monitor and app-activation notifications close the shelf. Its background is an `NSVisualEffectView` with a rounded mask. The preview is a child panel placed above (or beside) the shelf.

### Global shortcut

Carbon `RegisterEventHotKey` needs no permission. If the combination is already taken, registration is retried once after 2 s and the settings window shows the conflict. The shortcut is suspended while the user records a new one.

## Storage

```
~/Library/Containers/io.github.romainrg.Copicol/Data/Library/Application Support/Copicol/
├── Library.store     history (SwiftData "Local" container, never synced)
├── Boards.store      pinboards and iCloud mirror (SwiftData "Boards" container, can sync)
└── Items/<uuid>/     content.rtf, content.html, image.png, thumbnail.png, favicon.png
```

The sandbox redirects `~/Library/Application Support/Copicol/` into the app container. Two SwiftData containers keep the full history out of CloudKit's reach. If a store cannot be opened, Copicol offers to archive it into a `Backup-<date>` folder and start again with an empty one.

### Data model

**`ClipItem`** (*Local* container, `Library.store`)

| Property | Type | Role |
|---|---|---|
| `id` | UUID | Identifier, also the name of the `Items/<id>/` folder |
| `kindRaw` | String | `text`, `richText`, `image`, `file`, `link` or `color` |
| `createdAt`, `lastUsedAt`, `modifiedAt` | Date | Creation; last copy or paste (sorting, retention); last pinning change (iCloud conflicts) |
| `copyCount` | Int | How many times the same content was copied |
| `text`, `linkURL`, `linkTitle`, `colorHex`, `filePaths` | String?, [String] | Lightweight content |
| `imageWidth`, `imageHeight`, `byteSize` | Int | Metadata |
| `payloadNames` | [String] | Files present on disk (`content.rtf`, `image.png`…) |
| `contentHash` | String | SHA-256 of kind and content, for deduplication |
| `sourceBundleID`, `sourceAppName` | String? | Source application (its icon is resolved for display) |
| `pinboardID` | UUID? | Pinboard the item belongs to; when set, the item is never purged |
| `searchText` | String | Normalized index (case, accents, width): text, link title, URL, file names, app name |
| `isSynced` | Bool | Already exported to iCloud |

**`Pinboard`** (*Boards*): `id`, `name`, `colorHex`, `sortIndex`, `createdAt`.

**`SyncedClip`** (*Boards*): the iCloud copy of a text, link or color item: `contentHash`, `kindRaw`, `text`, `linkURL`, `linkTitle`, `colorHex`, source app, dates and `pinboardID`.

**`SyncTombstone`** (*Boards*): `contentHash`, `deletedAt`. Records an explicit deletion for the other Macs; kept for 30 days.

**`PendingDeletion`** (*Local*): `contentHash`, `deletedAt`. A deletion made while sync was off, turned into a `SyncTombstone` when sync is turned back on.

Models in the *Boards* container follow CloudKit's constraints: a default value on every property, no unique constraints, no relationships. A `ClipItem` references its pinboard by identifier rather than by relationship, because the two live in different containers.

**Preferences** (`UserDefaults`): `shelfHotKey`, `shelfPosition`, `cardSize`, `retention`, `excludedBundleIDs`, `playsSounds`, `pasteMode`, `alwaysPastePlainText`, `isCapturePaused`, `hasCompletedOnboarding`, `iCloudSyncEnabled`.

### Retention

The retention period (1 day, 1 week, 1 month or unlimited) counts from the last copy or paste of an item. The purge runs at launch and every hour; pinned items are never purged. Orphan files are cleaned up at launch.

## Concurrency

`ClipStore`, the view models and the UI are `@MainActor`. Hashing and image processing run in detached tasks on `Sendable` values (`CapturedContent`, `PreparedPayload`). Captures are processed one at a time through a task chain, so a burst of copies keeps its order.

## Sandbox and entitlements

`Copicol/Resources/Copicol.entitlements`:

| Entitlement | Use |
|---|---|
| `com.apple.security.app-sandbox` | The app is sandboxed. |
| `com.apple.security.network.client` | Titles and icons of copied links (LinkPresentation). |
| `com.apple.security.files.user-selected.read-only` | Choosing an app to exclude with an open panel. |

**Pasting from the sandbox.** `CGEvent.post` is allowed for a sandboxed app once the user grants Accessibility. Copicol uses the sandbox-compatible APIs `CGRequestPostEventAccess` and `CGPreflightPostEventAccess`, along with `AXIsProcessTrusted`; no sandbox exception is needed.

`Copicol/Resources/CopicolCloud.entitlements`, used only by the `iCloud` build configuration, adds CloudKit with the `iCloud.io.github.romainrg.Copicol` container and `aps-environment`.

## iCloud sync

Sync is **off by default** and gated twice:

1. **At build time**: only the `iCloud` configuration signs the app with `CopicolCloud.entitlements`, which requires an Apple developer team. Debug and Release builds, signed ad hoc, lack the entitlement, and the setting is disabled with an explanation.
2. **At run time**: Settings › iCloud › « Synchroniser avec iCloud », applied on relaunch.

```sh
xcodegen generate
xcodebuild -project Copicol.xcodeproj -scheme Copicol -configuration iCloud \
  -derivedDataPath build -destination 'generic/platform=macOS' \
  DEVELOPMENT_TEAM=<your team ID> -allowProvisioningUpdates build
```

The `iCloud.io.github.romainrg.Copicol` container must be available to your team. For your own builds, replace it in `CopicolCloud.entitlements` together with `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`. For a distributed build, set `aps-environment` to `production` and deploy the CloudKit schema to production in CloudKit Console.

**What syncs**: pinboards, and text, link and color items under 1 MB, through `SyncedClip`. Images, files and rich text stay on the Mac. `CloudMirror` reconciles at launch, after each CloudKit import (`NSPersistentStoreRemoteChange`) and every 5 minutes:

- a local item without an iCloud copy is exported. A missing copy never deletes a local item, so a reset iCloud database or a changed account cannot empty the history;
- a copy coming from another Mac is imported, unless it is older than this Mac's retention period and not pinned;
- an **explicit deletion** (Delete, Clear history) leaves a `SyncTombstone`: the other Macs delete the item unless it was used or pinned there since. A deletion made while sync is off is queued (`PendingDeletion`) and applied when sync is turned back on;
- **retention purges never propagate**: each Mac applies its own retention period;
- usage dates merge by maximum, and pinning follows the most recent pinning change (`modifiedAt`), so pasting an item on one Mac does not undo a pin made on another.

## Testing

`CopicolCoreTests` covers deduplication, type detection and pasteboard reading and writing, retention, search and the iCloud mirror (two simulated Macs sharing an in-memory *Boards* container). Tests use private named pasteboards, in-memory containers and a controllable clock, so they never touch the user's data.

The shelf, the paste flow and the windows are not tested automatically: driving them requires the Accessibility and Screen Recording permissions. `Tools/Screenshots` renders the real shelf views offscreen with demo data, which catches layout regressions visually.

## Known limitations

- **Dragging several files** to another app only passes the first one (a SwiftUI `NSItemProvider` carries a single file). Pasting with ↩ passes them all.
- **Files**: only their paths are kept. If the original file is moved or deleted, pasting it produces an invalid path.
- **iCloud**: tombstones are kept for 30 days, so a Mac that stays offline longer can re-export an item deleted in the meantime. iCloud copies of items purged by retention remain available to the other Macs.
- **Language**: the interface is French only.
