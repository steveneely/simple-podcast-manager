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
- `MainView`: primary single-window interface; shows device status and the last completed sync
- `FeedSidebarView`: show selection and grouped refresh, edit, and remove actions for the selected feed
- `FeedEditorView`: add or edit feeds
- `OPMLImportReviewView`: review standard OPML subscriptions before adding them
- `SettingsView`: app preferences, optional review-first device cleanup, device podcast folder, app data backup and restore
- `FeedPreviewViewModel`: load cached feed data and refresh RSS feeds
- `PreparationPreviewViewModel`: download/prepare local episode files and track local download history
- `AutomaticDownloadViewModel`: plan automatic downloads after successful feed refreshes and persist feed baselines
- `FeedActivityViewModel`: maintain independent new-episode and last-publication state for sidebar indicators
- `SyncPlanViewModel`: build the full-device plan shown before execution
- `SyncExecutionViewModel`: execute the selected plan and expose progress in the sync dialog
- `DeviceViewModel`: monitor device availability and selected target
- `DeviceLibraryViewModel`: inspect app-managed files already on the selected device
- `AppUpdater`: app-target wrapper around Sparkle for installed-app updates; disabled for local `swift run` builds

### Core Layer

- `FeedResolving`: validate an edited RSS feed before replacing a working subscription and return its parsed cache entry
- `FeedService`: refresh, cache, and parse saved RSS subscriptions
- `FeedCacheStore`: persist parsed feed snapshots and HTTP validators per subscription
- `AutomaticDownloadPlanner`: identify newly observed episodes and apply the per-feed download limit
- `AutomaticDownloadStateStore`: persist observed and pending episode IDs per subscription
- `FeedActivityPlanner` and `FeedActivityStateStore`: detect new feed prefixes, preserve conservative baselines, and persist activity in indexed SQLite rows
- `OPMLSubscriptionService`: parse, validate, de-duplicate, and export standard OPML subscription lists
- `DownloadService`: download episode media into the app's local media workspace
- `AudioConversionService`: convert unsupported input to MP3 using `ffmpeg`
- `DeviceService`: discover mounted devices, validate target paths, optionally eject
- `SyncPlanner`: calculate copy, skip, selected age-cleanup, manual delete, and eject actions; verify the complete plan fits; and order selected deletions before copies
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

1. The app loads persisted feeds and settings off the main actor without selecting a show, then concurrently loads cached feed previews, one SQLite startup snapshot, and mounted-device discovery. Cached episodes can render as soon as their cache read finishes. Network refresh and device inventory then proceed independently in the background.
2. The user adds a podcast by entering an RSS feed URL.
3. The app immediately creates a `FeedSubscription`, shows it as loading, and resolves its metadata and episodes in the background.
4. `DeviceService` monitors mounted volumes and identifies valid candidates.
5. A successful refresh updates independent show-activity state; failed feeds do not advance their baselines. The user downloads episodes manually, or automatic-download settings prepare new episodes.
6. The user clicks `Sync`.
7. `SyncPlanViewModel` builds the full-device plan:
   - validate device
   - identify app-managed episodes older than the configured cleanup threshold
   - exclude any cleanup candidates the user unchecked in the current review
   - build a `SyncPlan`
   - show planned copies, skips, deletions, and optional eject
8. `SyncExecutionViewModel` executes the plan:
   - copy prepared MP3 files
   - delete selected app-managed device files
   - optionally eject after success
9. Progress and result state are rendered in the UI.

Feed activity is separate from automatic downloads. Existing feeds establish a no-badge baseline, only episodes ahead of a previously observed episode are normally considered new, explicitly opening a show marks its current episodes seen, and a fully successful sync acknowledges prepared episodes copied or already present. The sidebar appends blue new-episode text or an orange inactive label to each show's episode count; refresh errors take precedence. No show is implicitly opened at startup, after app-data restore, or when the selected show is removed. Feed URL changes establish a fresh baseline. Activity state is included in app-data backups.

The plan shown to the user is the plan executed by the app.

## Podcast Download Security

Episode audio and artwork use HTTPS whenever possible. When a feed publishes an HTTP URL, the app first tries the equivalent HTTPS URL. HTTPS URLs that redirect to HTTP are also treated as insecure.

If the secure attempt fails, the UI asks before downloading over HTTP. A one-time approval covers that episode's audio and artwork and allows its show icon to load for the current app session. The user may instead save an app-wide preference in Settings. The main app keeps App Transport Security enabled; approved HTTP fallbacks use the system `curl` executable with only HTTP and HTTPS protocols permitted. RSS feeds, Sparkle updates, and unapproved downloads remain protected by ATS.

## RSS Subscription

Subscriptions are RSS-first. The add/edit flow captures a feed URL, resolves title and artwork metadata from the feed, and stores the subscription.

The app expects RSS and calls FeedKit's RSS-specific parser directly. It does not use FeedKit's universal format detection.

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

## Local Persistence

Small configuration data remains in `config.json`. Growing episode state is stored in `episodes.sqlite3` through GRDB and the SQLite library supplied by macOS:

- prepared episodes
- download history
- removal history
- automatic-download baselines and pending episodes

Each record is keyed by subscription and episode identity. New and updated records use transactional upserts instead of rewriting an entire history file. Database setup, legacy import, and large reads run outside the main actor.

Startup reads prepared episodes, download history, removal history, automatic-download state, and feed activity in one consistent SQLite read transaction. The UI builds keyed indexes for feed episodes and per-episode status so SwiftUI rendering does not repeatedly scan growing history arrays.

On first use, the database imports `prepared-episodes.json`, `downloaded-episodes.json`, and `removed-episodes.json` in one transaction. Automatic-download state uses a separate one-time import so upgrades from development builds can retain `automatic-downloads.json`. Import markers are written only after every source file decodes and every row is stored. The source JSON files remain available for recovery and are not imported again.

App data backups remain version-1 JSON directories. v1.9 can restore v1.8 backups; new backups also include `automatic-downloads.json`. Restore validates the complete backup before changing live data, writes all episode state in one database transaction, and restores the previous snapshot if applying the backup fails.

## Automatic Downloads

Automatic downloads run after startup, full, targeted, and new-subscription refreshes. They prepare files on the Mac but do not start a device sync.

The app stores stable episode IDs as indexed SQLite rows, with current episodes ordered newest first. Existing `automatic-downloads.json` state is imported once and retained for recovery. The first successful refresh for a new, re-enabled, or retargeted subscription records a baseline without downloading older episodes. Later successful refreshes can prepare the latest 1, 2, 3, or all newly observed episodes for each included feed. Episodes outside a numeric limit are recorded as observed so they do not download on a later refresh.

Failed refreshes do not advance the baseline. Failed media downloads remain pending for a later successful refresh, while download history prevents deleted local files from being downloaded again. Turning automatic downloads off clears pending work. Disabled feeds discard their baseline; excluded feeds keep their baseline current.

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

Every mutation must pass the safety boundaries below. Uncertain or malformed paths stop the operation.

The app does not require manufacturer-specific identification beyond these rules.

Device library refresh should inventory the configured podcast directory once and derive per-subscription and other-audio views from that snapshot. External players can have slow storage, so avoid repeatedly walking the same directory for every subscription. Device inventory and sync planning perform filesystem reads outside the main actor so a slow device does not freeze the UI.

## Sync Layout And Deletion

Managed files live under per-podcast folders:

- `[configured podcast directory]/<podcast-name>/`

This layout makes ownership safer than a flat directory.

Delete behavior:

- never schedule a deletion unless the user selected that file
- optional device cleanup starts disabled and only preselects eligible files for the current Sync review
- define cleanup age from the publication date encoded in an app-managed filename, using UTC calendar-day boundaries
- consider a file old only when its publication day is strictly earlier than the configured cutoff; a file exactly at the cutoff is retained
- never automatically select an undated file, unrelated audio, or a file that cannot be associated with a current subscription
- show every proposed cleanup deletion with its own checkbox and rebuild the executable plan after selection changes
- show a clear cleanup or removal notice before starting any plan that contains deletions; age-cleanup copy names the configured threshold and points back to Settings
- identify app-managed episodes from their podcast folder and filename metadata
- only delete other audio inside the configured podcast directory after explicit per-file user selection and confirmation
- never bulk-delete by loose pattern matching
- prefer exact planned file URLs over directory-wide operations

## Audio Conversion

All synced output on the device should be MP3.

- if a downloaded enclosure is already acceptable MP3 output, keep it
- otherwise convert it through `ffmpeg`
- finalize every MP3 with a small, deterministic ID3v2.3 tag using the RSS episode and podcast titles, plus prepared cover art when available
- Settings can prefix `TIT2` with the RSS publication date in fixed `MM.dd` format; this applies only to new downloads
- keep Unicode in ID3 text, including characters such as `ö` and `ß`
- use printable ASCII for device filenames, prefixed with `yyyy.MM.dd` when the publication date is available and suffixed with the podcast title
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

## Safety Boundaries

All device mutations pass through `SafetyValidator` and the scoped file services.

- write `.spmconfig` only at `[device root]/.spmconfig`
- write and delete podcast media only inside the configured podcast directory, which defaults to `[device root]/music`
- delete files only after explicit selection in the current plan review; age cleanup may preselect only proven app-managed files and must allow per-file opt-out
- keep the plan shown to the user identical to the plan passed to the executor
- validate every action again immediately before execution
- other audio also requires a separate explicit selection and confirmation
- never touch the Mac's Trash, sibling device folders, or other files at the device root
- refuse the mutation when a path cannot be proven safe
