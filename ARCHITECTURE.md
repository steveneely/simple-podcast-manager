# Simple Podcast Manager Architecture

## Summary

Simple Podcast Manager is a native Swift macOS app. It uses `SwiftUI` for the UI and an in-process sync engine for feeds, device validation, planning, file operations, and eject behavior. An external `ffmpeg` executable handles optional non-MP3 conversion.

The architecture should stay simple:

- one app
- one language
- one sync engine in process
- one explicit safety model

## System Design

The app has two layers:

- `UI layer`: configuration, device state, sync controls, progress, results
- `Core layer`: feed fetch, episode selection, conversion, sync planning, execution, direct device deletion, eject

The UI should not contain sync logic. It should call focused core services and render progress updates.

## Main Modules

### UI Layer

- `SimplePodcastManagerApp`: app lifecycle and main window setup
- `MainView`: primary single-window interface
- `FeedEditorView`: add or edit feeds
- `OPMLImportReviewView`: review standard OPML subscriptions before adding them
- `SettingsView`: appearance, optional custom `ffmpeg` path, insecure episode download preference, device podcast folder, app data backup and restore, and automatic update preference
- `FeedPreviewViewModel`: load cached feed data and refresh RSS feeds
- `PreparationPreviewViewModel`: download/prepare local episode files and track local download history
- `SyncPlanViewModel`: build the full-device plan shown before execution
- `SyncExecutionViewModel`: execute the selected plan and expose progress/state
- `DeviceViewModel`: monitor device availability and selected target
- `DeviceLibraryViewModel`: inspect app-managed files already on the selected device
- `AppUpdater`: app-target wrapper around Sparkle for installed-app updates; disabled for local `swift run` builds

### Core Layer

- `FeedResolving`: validate an edited RSS feed before replacing a working subscription and return its parsed cache entry
- `FeedService`: refresh, cache, and parse saved RSS subscriptions
- `FeedCacheStore`: persist parsed feed snapshots and HTTP validators per subscription
- `OPMLSubscriptionService`: parse, validate, de-duplicate, and export standard OPML subscription lists
- `DownloadService`: download episode media into the app's local media workspace
- `AudioConversionService`: convert unsupported input to MP3 using `ffmpeg`
- `DeviceService`: discover mounted devices, validate target paths, optionally eject
- `SyncPlanner`: calculate copy, skip, delete, and eject actions, verify the complete plan fits, and order selected deletions before copies
- `SyncExecutor`: perform scoped copies and deletes on the device
- `SafetyValidator`: verify all device paths before any mutation

### Domain Models

The core domain models are:

- `FeedSubscription`
- `Episode`
- `DeviceInfo`
- `SyncAction`
- `SyncPlan`
- `AppSettings`
- `SyncResult`

## Data Flow

Expected runtime flow:

1. The app loads persisted feeds and settings.
2. The user adds a podcast by entering an RSS feed URL.
3. The app immediately creates a `FeedSubscription`, shows it as loading, and resolves its metadata and episodes in the background.
4. `DeviceService` monitors mounted volumes and identifies valid candidates.
5. The user downloads the episodes they want to prepare locally.
6. The user clicks `Sync`.
7. `SyncPlanViewModel` builds the full-device plan:
   - validate device
   - build a `SyncPlan`
   - show planned copies, skips, deletions, and optional eject
8. `SyncExecutionViewModel` executes the plan:
   - copy prepared MP3 files
   - delete selected app-managed device files
   - optionally eject after success
9. Progress and result state are rendered in the UI.

The plan shown to the user is the plan executed by the app.

## Episode Download Security

Episode downloads use HTTPS whenever possible. When a feed publishes an HTTP enclosure, `DownloadService` first tries the equivalent HTTPS URL. HTTPS URLs that redirect to HTTP are also treated as insecure.

If the secure attempt fails, the UI asks before downloading that episode over HTTP. The user may approve one download or persist an app-wide preference in Settings. The main app keeps App Transport Security enabled; an approved HTTP fallback is isolated to that episode by invoking the system `curl` executable with only HTTP and HTTPS protocols permitted. Feed loading, artwork, updates, and unapproved episode downloads remain protected by ATS.

## RSS Subscription

Subscriptions are RSS-first. The add/edit flow captures a feed URL, resolves title and artwork metadata from the feed, and stores the subscription.

The new-subscription flow should be:

- user enters an RSS feed URL
- the app validates and stores the URL immediately with a temporary title derived from its host
- the editor closes and the new show displays a loading state
- a background refresh fetches episodes and replaces the temporary title, artwork, and description with RSS metadata
- later refreshes can update the stored title and artwork if the feed changes

Editing an existing subscription remains validate-before-save. The app resolves the edited URL before replacing a working subscription, so an invalid edit cannot discard previously working feed data.

OPML import is subscription-only: it validates HTTP(S) feed URLs, skips subscriptions already present and duplicates within the file, then lets normal feed refresh resolve current feed metadata. OPML export contains only feed titles and URLs, keeping local downloads, settings, and history out of a portable subscription list.

Manual entry and OPML import share the same atomic subscription persistence and targeted background-refresh path. A manual entry is a batch of one; an OPML import is a batch of many. Only newly added subscriptions are refreshed, and existing preview data remains visible.

## Feed Refresh And Cache

Feed refresh should be fast on startup and polite to RSS hosts.

The app keeps a derived feed cache under app support:

- `feed-cache/<subscription-id>.json`

Each cache file stores:

- subscription ID and RSS URL
- fetched-at date
- HTTP `ETag` and `Last-Modified` validators when the host provides them
- parsed feed summary metadata, including title, artwork, and description
- parsed episode metadata, including RSS `itunes:duration` and episode description when present

Startup loads cached parsed feeds immediately so the episode list can appear before network refresh finishes. A background refresh still runs after startup.

Enabled feeds refresh with a small concurrency limit. This avoids serial network waits when several subscriptions are configured without opening an unbounded number of connections.

Refresh behavior:

- send `If-None-Match` when a cached `ETag` exists
- send `If-Modified-Since` when a cached `Last-Modified` exists
- use cached parsed data when the server returns `304 Not Modified`
- parse and replace the cache when the server returns a fresh `200 OK` feed
- if refresh fails and a cache exists, keep showing cached episodes and surface a feed issue that names the saved feed date
- if refresh fails and no cache exists, show the refresh failure with no feed preview data

The feed cache is derived data. It should not be included in app data export/import, and deleting or retargeting a subscription should remove its stale cache file.

## Device Detection

Device detection is conservative and explicit.

Detection rules:

- inspect mounted volumes under `/Volumes`
- consider only removable or external volumes
- read optional `[device root]/.spmconfig` for Simple Podcast Manager device settings
- use the configured `podcast-dir` as the podcast sync target, such as `music` or `podcasts`
- default to `[device root]/music` when `.spmconfig` is absent or does not specify `podcast-dir`
- require the resolved podcast sync target to exist before selecting the device

Selection behavior:

- if exactly one valid device is present, auto-select it
- if multiple valid devices are present, require user selection
- if no valid device is present, disable sync

Validation gates before mutation:

- the device root must still be mounted
- `.spmconfig` writes must resolve to exactly `[device root]/.spmconfig`
- podcast media writes and deletes must resolve inside the configured podcast sync target
- configured podcast paths must be relative paths inside the mounted device
- no other device-root files or sibling folders may be written or deleted
- any uncertain or malformed path must abort the destructive portion of the run

The app does not require manufacturer-specific identification beyond these rules.

Device library refresh should inventory the configured podcast directory once and derive per-subscription and other-audio views from that snapshot. External players can have slow storage, so avoid repeatedly walking the same directory for every subscription. Device inventory and sync planning perform filesystem reads outside the main actor so a slow device does not freeze the UI.

## Sync Layout And Deletion

Managed files live under per-podcast folders:

- `[configured podcast directory]/<podcast-name>/`

This layout makes ownership safer than a flat directory.

Delete behavior:

- only delete files automatically when the app can confidently associate them with a configured feed
- only delete other audio inside the configured podcast directory after explicit per-file user selection and confirmation
- never bulk-delete by loose pattern matching
- prefer exact planned file URLs over directory-wide operations

## Audio Conversion

All synced output on the device should be MP3.

- if a downloaded enclosure is already acceptable MP3 output, keep it
- otherwise convert it through `ffmpeg`
- finalize every MP3 with a small, deterministic ID3v2.3 tag using the RSS episode and podcast titles, plus prepared cover art when available
- use `ffmpeg` only to convert audio; native Swift code handles MP3 metadata consistently afterward
- conversion happens in the app's local media workspace on the Mac before copy-to-device

RSS metadata is authoritative. Podcast enclosure files may contain missing, stale, or placeholder ID3 tags because podcast apps normally display metadata from the RSS feed. Offline MP3 players cannot access that feed, so Simple Podcast Manager writes the RSS episode title and podcast title into a deterministic ID3v2.3 tag before syncing.

Release builds may bundle `ffmpeg` at `Simple Podcast Manager.app/Contents/Resources/ffmpeg`. If the user sets a custom path in Settings, that path takes precedence. The app should surface missing `ffmpeg`, conversion, and metadata-writing failures clearly. Artwork preparation is best effort: audio preparation should continue without cover art if artwork fetching or image conversion fails.

## Update System

Installed app builds use Sparkle 2 for in-app updates.

Update design:

- the DMG remains the first-install path
- installed `.app` bundles expose `Simple Podcast Manager > Check for Updates…`
- Settings reads and writes Sparkle's own automatic-check preference rather than maintaining a parallel app setting
- when automatic checks are enabled, the installed app checks once per launch and shows Sparkle's update window only when a newer version is available
- `SUAllowsAutomaticUpdates` is false so a background check can notify the user but cannot silently download, install, or relaunch the app
- local development builds launched with `swift run "Simple Podcast Manager"` disable update checks
- Sparkle reads an HTTPS appcast from `SUFeedURL`
- Sparkle verifies update archives with the public EdDSA key in `SUPublicEDKey`
- Sparkle compares the numeric `CFBundleVersion` to determine whether an update is newer
- `CFBundleShortVersionString` is the user-visible version shown in update UI
- `SPMReleaseTag` identifies the matching GitHub release artifact

Do not keep a parallel GitHub-release update checker in the app UI. Sparkle owns installed-app update behavior.

## Safety Model

These rules are non-negotiable:

- only modify files on the external device
- only write `.spmconfig` at `[device root]/.spmconfig` for app-managed device configuration, including the podcast target folder
- only write podcast media inside the configured podcast directory, defaulting to `[device root]/music`
- only delete app-managed podcast files automatically inside the configured podcast directory
- only delete other audio inside that directory after explicit per-file user selection and confirmation
- never touch the Mac's local Trash
- never modify other device-root files or other folders on the device
- never delete outside the configured podcast directory
- refuse mutation if the device path cannot be proven safe

## Technology Choices

- all Swift implementation
- `SwiftUI` UI
- single main window
- JSON or plist-backed local config storage
- direct RSS entry as the subscription path
- feed title and artwork resolved from RSS metadata
- per-podcast subfolders under the configured device podcast directory
- optional `ffmpeg` invoked with `Process`
