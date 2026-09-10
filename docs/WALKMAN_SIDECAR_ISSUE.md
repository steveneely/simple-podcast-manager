# Walkman playlist failures caused by macOS sidecars

## Decision and scope

Introduced in **v1.20.1, build 102** after testing Steve's **Sony Walkman NW-E394, firmware 1.01**. Sync removes verified AppleDouble metadata files matching app-managed podcast media before automatic eject. Retain this behavior when changing copying, device inventory, or sync execution.

This document records a local device investigation and its resulting compatibility decision. It is not a Sony specification or a claim about every Walkman model. The exact firmware implementation was not reverse engineered.

## What the experiments established

The original suspicion was a 127-character filename or playlist path limit: shortening names appeared to make previously failing playlists work. Controlled tests did not support that diagnosis.

- Copies of a known-good MP3 with filenames of **127, 128, and 129 bytes** all played directly through Folder view and through the test playlist. This disproves a universal 127-byte filename limit for the tested playback paths. It does not establish the device's maximum full-path length or behavior for every encoding.
- Episodes renamed to `apple`, `banana`, and `cherry` inside a differently named folder still displayed podcast and episode titles from their embedded metadata. Renaming files did not replace those titles with the fruit names.
- Folder and playlist views could disagree about which episode occupied an entry. One playlist entry displayed “Russia's New Push to Torment” and made the player nearly unresponsive, requiring navigation back through several menu levels. Reversing the playlist moved that problematic entry to the beginning; the failure was not tied to the third playlist line.
- In the sidecar investigation, the clean three-episode test displayed the expected order and played all three files. The deliberate follow-up reproduced an incorrect third title, “Huge Crowds Gather,” which failed to play even though the first entry with that title played. The subsequent clean test again displayed and played all three correctly. The repeated failure/recovery was the reason to implement sidecar cleanup instead of treating the first successful refresh as proof of a stale-index fix.

The supported conclusion is that macOS sidecars can disrupt the player's media indexing or playlist resolution. The symptoms are consistent with the firmware treating a sidecar ending in `.mp3` as a media candidate, but its scanner, database layout, and playlist lookup algorithm remain unverified. Do not describe a specific buffer size, operating system, or internal indexing algorithm as established by these tests.

## Why a metadata file matters

A macOS copy to a filesystem that cannot store its metadata natively can produce a companion named `._episode.mp3` beside `episode.mp3`. This AppleDouble file carries filesystem metadata; it is not a second playable MP3. Its name still ends in `.mp3`, which makes it relevant to a device scanning files for its media library.

Embedded MP3 tags, including title, podcast/album information, and embedded artwork, are inside the actual audio file. Removing the matching AppleDouble companion leaves that MP3 and its embedded tags intact. The fix does not strip or rewrite audio metadata.

## Why the implementation is deliberately small

We chose exact companion cleanup during sync rather than filename truncation, changing the copy mechanism, rebuilding the player's library, or tracking device index state. These alternatives were unnecessary for the reproduced problem and would broaden the behavior or safety surface.

The user explicitly chose to keep sidecar cleanup out of the visible sync plan. It is automatic compatibility work associated with managed media, not another selectable audio deletion. Failures still appear as sync failures.

The implementation contract is:

1. `SyncPlan.existingManagedEpisodeURLs` supplies the known managed media inventory. `metadataCleanupTargets` combines that inventory with copy destinations and excludes media selected for removal. Existing media must be included so a sync can repair a device even when nothing new needs copying.
2. `SyncExecutor` considers only the exact `._` companion of each target under the configured device podcast directory. It validates the media and companion paths, rejects symlink paths, and requires the media to be a regular file.
3. `LocalFileSystem.isAppleDoubleFile` requires a regular companion file, AppleDouble magic, version 2, a nonempty entry table, and entry offsets and lengths within the file. A `._` prefix alone is insufficient evidence for deletion.
4. Cleanup runs after the media actions and before automatic eject, or at sync completion when automatic eject is disabled. `SyncPlan.hasWork` allows cleanup of existing managed media without requiring a new download.
5. A cleanup failure preserves completed transfers, reports incomplete sync, and prevents automatic eject. Unknown companion contents are left untouched. The separate manual-eject action is unchanged.

This is not permission to run a recursive `._*` sweep or `dot_clean` over the device. Do not clean orphan companions, unrelated audio, playlist companions, folder companions, device-root files, or player database files through this sync path. Folder migration has its own separately validated cleanup policy. Audio deletion continues to require the existing ownership, selection, and path checks.

## Regression checks

The behavior is covered by [AppleDoubleFileTests](../Tests/SimplePodcastManagerCoreTests/AppleDoubleFileTests.swift), [SyncExecutorTests](../Tests/SimplePodcastManagerCoreTests/SyncExecutorTests.swift), [SyncPlannerTests](../Tests/SimplePodcastManagerCoreTests/SyncPlannerTests.swift), and [SyncPlanTests](../Tests/SimplePodcastManagerCoreTests/SyncPlanTests.swift). Preserve coverage for valid and malformed companions, unrelated files, unsafe paths, cleanup of retained media without copies, and cleanup failure before eject.

Use the disposable FAT disk-image workflow in [AGENTS.md](../AGENTS.md#manual-disk-image-device-test) for filesystem and app checks. It cannot emulate the Walkman firmware. If device behavior needs retesting, use explicitly authorized disposable tracks and playlists on the player; compare the same audio and playlist with and without verified companions, eject normally, let the player scan, and record both displayed titles and actual playback. Reintroducing the suspected cause and removing it again is needed to distinguish this issue from a coincidental library refresh. Do not reset or delete the player's database to make a test pass.
