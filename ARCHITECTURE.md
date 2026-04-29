# Simple Podcast Manager Architecture

## Summary

Simple Podcast Manager is a native macOS app built in Swift. The app uses `SwiftUI` for the UI and a plain Swift sync engine for feed processing, device validation, sync planning, safe deletion, and optional eject behavior. `ffmpeg` is provided as a bundled external executable in release builds, with an optional custom path override for development and advanced users.

The architecture should stay simple:

- one app
- one language
- one sync engine in process
- one explicit safety model

## System Design

The app has two layers:

- `UI layer`: configuration, device state, sync controls, progress, results
- `Core layer`: feed fetch, episode selection, conversion, sync planning, execution, direct device deletion, eject

The UI should not contain sync logic. It should call a single coordinator in the core layer and render progress updates.

## Main Modules

### UI Layer

- `SimplePodcastManagerApp`: app lifecycle and main window setup
- `MainView`: primary single-window interface
- `FeedEditorView`: add or edit feeds
- `SettingsView`: optional custom `ffmpeg` path
- `SyncViewModel`: bind UI to sync engine and expose progress/state
- `DeviceViewModel`: monitor device availability and selected target

### Core Layer

- `SyncCoordinator`: top-level orchestrator for a sync run
- `FeedService`: fetch, cache, and parse RSS feeds
- `FeedCacheStore`: persist parsed feed snapshots and HTTP validators per subscription
- `DownloadService`: download episode media into a temporary workspace
- `AudioConversionService`: convert unsupported input to MP3 using `ffmpeg`
- `DeviceService`: discover mounted devices, validate target paths, optionally eject
- `SyncPlanner`: calculate copy, skip, delete, and eject actions
- `DeviceFileService`: perform scoped copies and deletes on the device
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
   - if real run, execute copy/delete
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

## Feed Refresh And Cache

Feed refresh should be fast on startup and polite to RSS hosts.

The app keeps a derived feed cache under app support:

- `feed-cache/<subscription-id>.json`

Each cache file stores:

- subscription ID and RSS URL
- fetched-at date
- HTTP `ETag` and `Last-Modified` validators when the host provides them
- parsed feed summary metadata, including title, artwork, and description
- parsed episode metadata, including RSS `itunes:duration` when present

Startup loads cached parsed feeds immediately so the episode list can appear before network refresh finishes. A background refresh still runs after startup.

Refresh behavior:

- send `If-None-Match` when a cached `ETag` exists
- send `If-Modified-Since` when a cached `Last-Modified` exists
- use cached parsed data when the server returns `304 Not Modified`
- parse and replace the cache when the server returns a fresh `200 OK` feed
- if refresh fails and a cache exists, keep showing cached episodes and surface a feed issue that names the saved feed date
- if refresh fails and no cache exists, show the refresh failure with no feed preview data

The feed cache is derived data. It should not be included in app data export/import, and deleting or retargeting a subscription should remove its stale cache file.

Cache files include a format version. Bump the format version when adding parsed fields that should appear immediately from cached data, such as episode duration. Otherwise feeds that correctly return `304 Not Modified` can keep serving old cached episode records without the new fields.

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
- any uncertain or malformed path must abort the destructive portion of the run

V1 does not require Sony-specific identification beyond these rules.

## Sync Layout And Deletion

Managed files should live under per-podcast folders:

- `[device root]/music/<podcast-name>/`

This is the default layout for v1 because it makes ownership safer than a flat directory.

Delete behavior:

- only delete files in managed podcast folders under `[device root]/music`
- only delete files the app can confidently associate with a configured feed
- never bulk-delete by loose pattern matching
- prefer exact planned file URLs over directory-wide operations

## Audio Conversion

All synced output on the device should be MP3.

- if a downloaded enclosure is already acceptable MP3 output, keep it
- otherwise convert it through `ffmpeg`
- conversion happens in a temporary workspace on the Mac before copy-to-device

Release builds should bundle `ffmpeg` at `Simple Podcast Manager.app/Contents/Resources/ffmpeg`. If the user sets a custom path in Settings, that path takes precedence. The app should surface missing `ffmpeg` or conversion failures clearly in the UI.

## Safety Model

These rules are non-negotiable:

- only modify files on the external device
- only write inside `[device root]/music`
- only delete app-managed podcast files inside `[device root]/music`
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
- bundled `ffmpeg` invoked with `Process`
- dry-run uses the exact same planner as real sync
