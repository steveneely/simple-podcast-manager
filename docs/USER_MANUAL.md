# Simple Podcast Manager quick start

Simple Podcast Manager downloads podcast episodes and syncs them to a standalone MP3 player.

## Install the app

Download the latest DMG from [GitHub Releases](https://github.com/steveneely/simple-podcast-manager/releases/latest), open it, and drag the app to Applications.

The app is not yet Developer ID signed or notarized. If macOS blocks it, follow Apple's guidance for [safely opening apps on your Mac](https://support.apple.com/en-us/102445) and allow it in System Settings > Privacy & Security.

## Prepare your MP3 player

Connect the player. By default, it needs a `music` folder at its top level. To use another folder, select the player and open `Settings > Device > Device Podcast Folder`. The app asks before creating a missing folder.

## Add podcasts

1. Click `Add Podcast`, or the plus button in the Podcasts list.
2. Search by title or creator, or select `Feed URL` and paste an RSS feed address.
3. Choose the podcast and click `Add Podcast`.

Podcasts already in your library are marked `Added`. If search fails, click `Try Again` or use the RSS feed URL.

## Download episodes

1. Select a podcast.
2. Click the download button beside each episode you want.
3. Wait for the downloads to finish.

Non-MP3 episodes require a separately installed [FFmpeg](https://www.ffmpeg.org/download.html). Select its `ffmpeg` executable under `Settings > Advanced > FFmpeg Path`.

If audio or artwork requires unencrypted HTTP, the app asks permission. Allow it once for that episode, or save permission for future downloads in Settings.

Downloaded MP3s are stored in `~/Library/Application Support/SimplePodcastManager/PreparedMedia/prepared`.

## Sync

1. Connect the player and wait for it to appear in the Device section.
2. Click `Sync`.
3. Review the copies, deletions, sizes, and any playlist changes. Uncheck deletions you do not want.
4. Choose whether to eject the player or delete local downloads afterward.
5. Click `Sync` to confirm.

The app checks that the selected plan fits before changing the player. Unchecking a deletion can change the space required. Deleted files are removed directly from the player, not moved to Trash.

## Manage podcasts

Select a podcast to reveal its Refresh, Edit, and Remove controls. In Edit, turn off `Podcast enabled` to stop refreshing it.

After the first refresh establishes a baseline, blue `new` marks episodes not yet downloaded or synced. Selecting a podcast does not clear it. New indicators appear after refresh and automatic downloads finish.

The lower-left refresh summary reports new episodes, completed downloads, and problems. Click it for details. Orange marks items needing attention; `Up to date` means there is nothing to review. Active download progress appears beside the Device section.

Click `Name` or `Updated` beside `Podcasts` to change the sort field; click the arrow to reverse the order.

An orange `Inactive` label means the latest dated episode is more than six months old by default. Change the threshold or turn it off under `Settings > General > Inactive Podcasts`. Hover over the label for the publication date. Podcasts that are disabled, lack trustworthy dates, or have a refresh error are not marked inactive.

### Import and export

Use `File > Import Podcasts…` to import an OPML file from another podcast app. Review the list before adding it; existing subscriptions and duplicates are skipped.

Use `File > Export Podcasts…` to export your subscriptions. OPML contains podcast titles and RSS feed URLs, not playlists or downloaded audio.

## Automatic downloads

Under `Settings > Downloads > Automatic Downloads`, choose `Latest 1`, `Latest 2`, `Latest 3`, or `All new`. Choose `Off` for manual downloads.

The limit applies separately to each included podcast after refresh. The first successful refresh establishes a baseline without downloading older episodes. Edit a podcast to change `Include in automatic downloads`.

Automatic downloads prepare files on your Mac. They do not start Sync.

## Playlists

Switch between `Podcasts` and `Playlists` using the library selector, or press ⌘1 and ⌘2.

### Create and edit a playlist

1. Choose `File > Add Playlist…` (⇧⌘N), or click the plus button in Playlists.
2. Enter a unique name, choose an icon, and click `Save`.
3. In Podcasts, open an episode's playlist menu and choose the playlist. The app offers to download episodes that are not available locally or on the connected player.
4. Open the playlist and drag manually added episodes to reorder them.

Select a playlist to reveal Edit and Delete. Removing an entry does not delete its audio. Deleting a playlist removes its definition; its app-managed device file is removed on the next successful sync.

Deleting an episode's last local download also removes it from playlists after confirmation. Deleting local downloads after a successful sync keeps membership because the device copy remains available.

### Add episodes automatically

In Edit, turn on `Automatically add episodes` and select podcasts. Optionally enable `Limit automatically added episodes`. This limit applies across the selected podcasts together, newest first; manually added episodes do not count.

Automatic additions use available episodes and do not download them. Enable automatic downloads separately if needed.

Automatic entries appear after manual entries. Pin an available episode to reorder it and protect it from automatic device cleanup. Removing an automatic entry excludes it from that playlist; adding it manually clears the exclusion.

### Choose the device playlist folder

Connect and select the player. Under `Settings > Device > Device Playlist Folder`, click `Choose Folder…` and select a folder on that device. The app asks before creating a missing folder. Playlists default to the podcast folder unless you choose another location.

Sync writes `.m3u` playlists referencing episodes on the player. Check your player's playlist support and required folder. The app only replaces or removes playlist files it has recorded as its own in that exact folder; it never overwrites an unrelated file with the same name.

Playlist changes appear in the Sync review. The app offers to download unavailable manual entries before review; unavailable entries are omitted from device playlists. If a playlist has no available episodes, its app-managed device file is removed, but its definition stays in the app.

## Limit episodes kept per podcast during Sync

Device cleanup is off by default. Under `Settings > Device > Device Cleanup`, choose `Keep 3 episodes`, `Keep 5 episodes`, `Keep 10 episodes`, or `Keep 20 episodes`, then save.

Sync suggests deleting older existing episodes beyond that limit, accounting for dated episodes being copied. Review each suggestion and uncheck anything you want to keep. For example, five episodes on the player plus two newer downloads makes `Keep 5 episodes` suggest removing the two oldest existing episodes.

Cleanup only suggests recognized podcast MP3s inside the configured podcast folder. It never automatically selects unrelated audio. See [cleanup troubleshooting](#an-episode-beyond-the-limit-was-not-suggested-for-cleanup) for exceptions.

Manual and pinned playlist entries are protected. Older qualifying entries appear under `Older Episodes Kept by Playlists`, unchecked. Selecting one removes its device file and playlist membership. Automatic playlist entries follow the normal cleanup limit.

## Remove episodes from the player

Connect the player and open a podcast. Clear an episode's checked `On MP3 player` box to mark it `Remove on next sync`; select it again to keep it. Use `Older episodes on MP3 player` for episodes no longer in the current RSS feed.

For unrelated audio inside the configured podcast folder, use `Scan for Other Audio…` in the Device section. The scan can be cancelled. Other audio is deleted only after you select and confirm those exact files.

## Settings

Open `Simple Podcast Manager > Settings…` (⌘,). Click `Save` to apply changes or `Cancel` to discard them. Appearance previews immediately and reverts if you cancel.

- **General:** appearance and inactive-podcast indicators.
- **Downloads:** automatic downloads and MP3 metadata.
- **Device:** podcast and playlist folders, and device cleanup. Connect and select a player to change its folders.
- **Advanced:** FFmpeg, HTTP permissions, and app data backups.

Hover over a compact path to see it in full, or right-click and choose `Copy Path`.

### MP3 metadata

Device filenames start with the RSS publication date in `yyyy.MM.dd` format when available. Embedded titles retain the original RSS text. Settings can prefix new MP3 titles with `MM.dd`, such as `08.11 Original Title`.

Under `Settings > Downloads > MP3 Metadata > MP3 Genre`, change the default `Podcast` genre or leave it blank to omit it. Title and genre settings apply only to new downloads.

## Back up, restore, and update

- Back up: `Settings > Advanced > App Data > Back Up…`
- Restore: `Settings > Advanced > App Data > Restore…`
- Check for updates: `Simple Podcast Manager > Check for Updates…`

Backups include podcasts, playlists, device ownership records, settings, and history, but not downloaded audio. Before restoring, the app asks for confirmation and backs up the current data. Afterward, it offers to reveal the backup in Finder.

## Troubleshooting

### The app does not see my player

- Check that the player appears in Finder.
- Check for a top-level `music` folder or another podcast folder selected in Settings.
- Click the refresh button in the Device section.

### The sync does not fit

Download fewer episodes, or select old episodes for deletion and review the plan again.

### An episode beyond the limit was not suggested for cleanup

Cleanup requires a trustworthy publication date in a recognized Simple Podcast Manager filename and a matching current podcast. Undated files do not count. Episodes tied on the date at the limit are all kept. Unrelated audio and files in unrecognized folders must be reviewed manually.

Older episodes being copied are never blocked or deleted to enforce the limit. The player may temporarily exceed it; review those episodes during a later sync.

### Cleanup is off after upgrading

Older age-based cleanup settings are ignored. Choose a per-podcast limit under `Settings > Device > Device Cleanup`.

### A playlist is missing or incomplete on the player

- Check M3U support and the required folder; set it under `Settings > Device > Device Playlist Folder`.
- Run Sync after changing a playlist.
- Check episode availability. Only episodes on the player after sync appear in its playlist; an empty playlist has no device file.
- For a filename collision, choose another playlist name or folder. The app will not overwrite a playlist it does not own.

### Playlists disappeared after restoring an older backup

Backups made before playlist support contain no playlists. Restoring one replaces the playlist library with an empty library.

### A non-MP3 episode does not download

Install [FFmpeg](https://www.ffmpeg.org/download.html) and select its executable under `Settings > Advanced > FFmpeg Path`.
