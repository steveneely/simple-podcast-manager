# PodcastSwift Architecture

## Summary

PodcastSwift is a native macOS app built in Swift. The app uses `SwiftUI` for the UI and a plain Swift sync engine for feed processing, device validation, sync planning, retention, safe deletion, and optional eject behavior. `ffmpeg` is the only planned external dependency.

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

- `PodcastSwiftApp`: app lifecycle and main window setup
- `MainView`: primary single-window interface
- `DiscoveryView`: search for podcasts and subscribe from results
- `FeedEditorView`: add or edit feeds and retention values
- `SettingsView`: `ffmpeg` path, dry-run default, eject-after-sync default
- `SyncViewModel`: bind UI to sync engine and expose progress/state
- `DeviceViewModel`: monitor device availability and selected target

### Core Layer

- `SyncCoordinator`: top-level orchestrator for a sync run
- `PodcastDiscoveryService`: query podcast directories and normalize search results
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

- `DiscoveryResult`
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
2. If the user searches for a podcast, `PodcastDiscoveryService` queries the discovery provider and returns normalized results.
3. The user subscribes to a discovery result, which creates a `FeedSubscription` from the resolved RSS feed URL.
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

## Podcast Discovery

Podcast discovery should be RSS-first. The purpose of discovery is to help the user find a podcast feed to subscribe to, not to integrate with a playback platform.

Primary provider for v1:

- Podcast Index search API

Optional fallback provider after v1:

- Apple iTunes Search API for podcast directory search

Not part of the core design:

- direct Apple Podcasts library integration
- Spotify-based subscription or sync workflows

Provider behavior:

- user enters a search term
- the provider returns normalized `DiscoveryResult` items
- each result should include enough information to show title, publisher or author, artwork, summary, and resolved feed URL when available
- the user can subscribe by converting a result into a local `FeedSubscription`

If a discovery result does not contain a usable RSS feed URL, it should not be subscribable in v1.

Provider selection defaults:

- use Podcast Index as the primary provider
- keep manual RSS entry available at all times
- do not block the app on Apple- or Spotify-specific integrations

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
- Podcast Index as the primary podcast discovery source
- manual RSS entry remains supported even when discovery is unavailable
- per-podcast subfolders under device `music`
- one retention rule: keep latest `N`
- `ffmpeg` invoked with `Process`
- dry-run uses the exact same planner as real sync
