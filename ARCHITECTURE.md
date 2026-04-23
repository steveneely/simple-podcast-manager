# S Podcast Manager Architecture

## Summary

S Podcast Manager is a native macOS app built in Swift. The app uses `SwiftUI` for the UI and a plain Swift sync engine for feed processing, device validation, sync planning, retention, safe deletion, and optional eject behavior. `ffmpeg` is the only planned external dependency.

The architecture should stay simple:

- one app
- one language
- one sync engine in process
- one explicit safety model

## System Design

The app has two layers:

- `UI layer`: configuration, device state, sync controls, progress, results
- `Core layer`: feed fetch, episode selection, conversion, sync planning, execution, retention, trash cleanup, eject

The UI should not contain sync logic. It should call a single coordinator in the core layer and render progress updates.

## Main Modules

### UI Layer

- `SPodcastManagerApp`: app lifecycle and main window setup
- `MainView`: primary single-window interface
- `FeedEditorView`: add or edit feeds and retention values
- `SettingsView`: `ffmpeg` path, dry-run default, eject-after-sync default
- `SyncViewModel`: bind UI to sync engine and expose progress/state
- `DeviceViewModel`: monitor device availability and selected target

### Core Layer

- `SyncCoordinator`: top-level orchestrator for a sync run
- `FeedService`: fetch and parse RSS feeds
- `DownloadService`: download episode media into a temporary workspace
- `AudioConversionService`: convert unsupported input to MP3 using `ffmpeg`
- `DeviceService`: discover mounted devices, validate target paths, optionally eject
- `SyncPlanner`: calculate copy, skip, delete, trash cleanup, and eject actions
- `RetentionService`: apply "keep latest N episodes" logic
- `DeviceFileService`: perform scoped copies and deletes on the device
- `TrashCleanupService`: clear only the device `.Trashes`
- `SafetyValidator`: verify all device paths before any mutation
- `SyncReporter`: publish structured progress and final result summaries

### Domain Models

At minimum, v1 should define:

- `FeedSubscription`
- `Episode`
- `DeviceInfo`
- `RetentionPolicy`
- `SyncAction`
- `SyncPlan`
- `AppSettings`
- `SyncResult`

## Data Flow

Expected runtime flow:

1. The app loads persisted feeds and settings.
2. The user adds a podcast by entering an RSS feed URL.
3. The app resolves feed metadata from RSS and creates a `FeedSubscription`.
4. `DeviceService` monitors mounted volumes and identifies valid candidates.
5. The user clicks `Sync`.
6. `SyncViewModel` calls `SyncCoordinator`.
7. `SyncCoordinator` runs the pipeline:
   - validate device
   - fetch feeds
   - select desired episodes
   - download missing media
   - convert to MP3 if required
   - build a `SyncPlan`
   - if dry-run, stop after planning and report the plan
   - if real run, execute copy/delete/trash cleanup
   - optionally eject after success
8. `SyncReporter` emits progress and result events to the UI.

The planner and executor must share the same decision logic. Dry-run is not a separate implementation path.

## RSS Subscription

Subscription should be RSS-first. The purpose of add/edit flow is to capture a feed URL, resolve title and artwork metadata from the feed itself, and store a clean subscription the sync engine can trust.

The flow should be:

- user enters an RSS feed URL
- the app fetches the feed and reads title/artwork metadata
- the app stores the resolved subscription
- later refreshes can update the stored title and artwork if the feed changes

## Device Detection

V1 device detection should be conservative and explicit.

Detection rules:

- inspect mounted volumes under `/Volumes`
- consider only removable or external volumes
- require a `music` directory at the volume root
- treat `[device root]/music` as the only writable sync target

Selection behavior:

- if exactly one valid device is present, auto-select it
- if multiple valid devices are present, require user selection
- if no valid device is present, disable sync

Validation gates before mutation:

- the device root must still be mounted
- the target sync directory must resolve to exactly `[device root]/music`
- the trash cleanup directory must resolve to exactly `[device root]/.Trashes`
- any uncertain or malformed path must abort the destructive portion of the run

V1 does not require Sony-specific identification beyond these rules.

## Sync Layout And Retention

Managed files should live under per-podcast folders:

- `[device root]/music/<podcast-name>/`

This is the default layout for v1 because it makes ownership and retention safer than a flat directory.

Retention rule for v1:

- keep latest `N` episodes per feed

Delete behavior:

- only delete files in managed podcast folders under `[device root]/music`
- only delete files the app can confidently associate with a configured feed
- never bulk-delete by loose pattern matching
- prefer exact planned file URLs over directory-wide operations

## Trash Cleanup

Trash cleanup is intentionally narrow.

- only clear `[device root]/.Trashes`
- never touch `~/.Trash`
- never touch any other local Trash location
- if the device has no `.Trashes`, skip cleanup without error

## Audio Conversion

All synced output on the device should be MP3.

- if a downloaded enclosure is already acceptable MP3 output, keep it
- otherwise convert it through `ffmpeg`
- conversion happens in a temporary workspace on the Mac before copy-to-device

The app should surface missing `ffmpeg` or conversion failures clearly in the UI.

## Safety Model

These rules are non-negotiable:

- only modify files on the external device
- only write inside `[device root]/music`
- only permanently delete by clearing `[device root]/.Trashes`
- never touch the Mac's local Trash
- never delete outside app-managed podcast folders
- refuse mutation if the device path cannot be proven safe

Implementation priority should follow this order:

1. path validation
2. sync planning
3. execution

The app should be biased toward refusing unsafe work, even if that occasionally blocks a valid run.

## Defaults Chosen For V1

- all Swift implementation
- `SwiftUI` UI
- single main window
- JSON or plist-backed local config storage
- direct RSS entry as the subscription path
- feed title and artwork resolved from RSS metadata
- per-podcast subfolders under device `music`
- one retention rule: keep latest `N`
- `ffmpeg` invoked with `Process`
- dry-run uses the exact same planner as real sync
