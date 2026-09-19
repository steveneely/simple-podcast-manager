# Simple Podcast Manager quick start

Simple Podcast Manager downloads podcast episodes from RSS feeds and syncs them to a standalone MP3 player.

## Install the app

Download the latest DMG from [GitHub Releases](https://github.com/steveneely/simple-podcast-manager/releases/latest), open it, and drag the app to Applications.

The app is not yet Developer ID signed or notarized. If macOS blocks it the first time you open it, follow Apple's guidance for [safely opening apps on your Mac](https://support.apple.com/en-us/102445) and allow it in System Settings > Privacy & Security.

## Settings

Open `Simple Podcast Manager > Settings…` (⌘,). Use the sidebar to choose General, Downloads, Device, or Advanced. Changes stay in the draft as you switch pages; click `Save` to apply them or `Cancel` to discard them. Appearance previews immediately and returns to its saved setting if you cancel.

Downloads groups title and genre options under `MP3 Metadata`. Choose `Advanced` in the sidebar for FFmpeg, HTTP download permissions, and app data backup and restore. Device keeps both folder settings together; connect a player to change them.

## Prepare your MP3 player

Connect the player.

By default, the player needs a `music` folder at its top level. To use a different folder, select the player in Simple Podcast Manager and change the podcast folder in Settings. The app asks before creating a missing folder.

## Add podcasts

1. Click `Add Podcast` from the empty podcast panel, or use the plus button in the Podcasts list.
2. Search by podcast title or creator, or select `Feed URL` to paste an RSS feed address.
3. Choose the podcast you want and click `Add Podcast`.

The podcast and its latest episodes will appear in the app.

Podcasts already in your library are marked `Added`. If a search fails, click `Try Again` or add the podcast using its RSS feed URL.

After that first baseline, blue `new` text beside a podcast's episode count means its RSS feed has episodes that still need attention. Selecting a podcast does not clear the indicator. During a refresh, new indicators wait until automatic downloads finish so they do not flash briefly for episodes the app is already handling. The indicator clears one episode at a time after that episode downloads successfully, or after a successful Sync copies it to the player or confirms that it is already there.

The lower-left corner of the Podcasts list reports library refresh progress, including how many podcasts have been checked. When the refresh finishes, compact counters show episodes that are still new, completed downloads, and anything needing attention. The counters use short labels when space allows and automatically collapse to icons and numbers in a narrow window. A successful manual download immediately moves that episode from blue `new` to green `downloaded`. Click the counters to review the checked and found totals, downloaded episodes, episodes that are still new, and refresh or download problems. Orange marks items needing attention. When there is nothing to review, the footer simply says `Up to date`.

The compact sort control beside `Podcasts` shows `Name` or `Updated` for the current sort field. Click that label to switch fields, or click its arrow to reverse the order. The app remembers both choices.

By default, an orange `Inactive` label marks a podcast whose latest dated episode is more than six months old. Its tooltip shows the latest publication date. Choose `Settings > General > Inactive Podcasts` to use three months, six months, one year, or turn this indicator off. Disabled podcasts, RSS feeds without trustworthy dates, and podcasts with a current refresh error are not marked inactive.

Select a podcast to reveal its Refresh, Edit, and Remove controls. Select it again to clear the selection.

To bring subscriptions from another podcast app, use `File > Import Podcasts…` and choose its OPML export. OPML is a standard format for transferring lists of podcast RSS feed URLs between apps. Review the list before adding it. Existing subscriptions and duplicate entries are skipped.

Use `File > Export Podcasts…` to create an OPML file for another podcast app.

## Download episodes

1. Select a podcast.
2. Click the download button beside each episode you want.
3. Wait for the downloads to finish.

The app does not include FFmpeg. If an episode is not already an MP3, install [FFmpeg](https://www.ffmpeg.org/download.html), then choose its `ffmpeg` executable under `Settings > Advanced > FFmpeg Path` so the app can convert it.

If episode audio or artwork is available only over unencrypted HTTP, the app warns you first. You can allow that episode once or always allow HTTP podcast downloads in Settings.

When the feed provides a publication date, files copied to the player start with it in `yyyy.MM.dd` format so they sort reliably. Their embedded MP3 titles keep the original feed text, including special characters. Settings can add a shorter `MM.dd` date to new MP3 titles, such as `08.11 Original Title`.

New downloads use `Podcast` in the MP3's ID3 genre field by default. Change `Settings > Downloads > MP3 Metadata > MP3 Genre` to use a different genre on your player, or leave it blank to omit the genre field. Genre and title settings apply only to new downloads; existing downloads are unchanged.

Leave `Settings > Downloads > Automatic Downloads` set to `Off` for manual downloads, or choose `Latest 1`, `Latest 2`, `Latest 3`, or `All new`. The limit applies separately to each included podcast after RSS feed refreshes. The first successful refresh records existing episodes without downloading them, so subscriptions do not create a backlog.

Edit a podcast to change `Include in automatic downloads`. Turn off `Podcast enabled` to stop refreshing that podcast. Automatic downloads prepare episodes on the Mac; syncing starts only when you click `Sync`.

While downloads are active, the progress beside the Device section reports only the current file preparation work. It disappears when that work finishes; use the persistent refresh summary in the lower-left corner to review the completed result.

## Playlists

Playlists are available without enabling a setting. Use the library selector above the podcast list to switch between `Podcasts` and `Playlists`, or press ⌘1 and ⌘2.

### Create and edit a playlist

1. Choose `File > Add Playlist…` (⇧⌘N), or click the plus button in the Playlists list.
2. Enter a unique name, choose an icon, and click `Save`.
3. Return to `Podcasts`, open the playlist menu beside an episode, and choose your playlist. If the episode is not downloaded or on the connected player, the app offers to download it before adding it.
4. Open the playlist and drag manually added episodes into your preferred order.

Select a playlist to reveal its Edit and Delete controls. Use Edit to change its name, icon, or automatic additions. Removing an episode from a playlist does not delete its audio. Deleting a playlist removes its definition from the app; its app-managed device playlist file is removed on the next successful sync.

Deleting the last available local download also removes that episode from playlists after confirmation. Deleting local downloads after a successful sync keeps playlist membership because the device copy remains available.

### Add episodes automatically

In the playlist editor, turn on `Automatically add episodes` and select one or more podcasts. Optionally turn on `Limit automatically added episodes` and choose a count. The limit applies across the selected podcasts together, with newest episodes first; manually added episodes do not count toward it.

Automatic additions use available episodes and do not start downloads. Use the separate `Settings > Downloads > Automatic Downloads` setting if you also want new episodes downloaded automatically.

Automatically added episodes appear after manually added episodes. Pin an available episode to make it manually added so you can reorder it and protect it from automatic device cleanup. Remove an automatic entry to keep it out of that playlist; adding it manually again clears that exclusion.

### Choose the device playlist folder

Connect and select your player, then open `Settings > Device > Device Playlist Folder`. Click `Choose Folder…` and select a folder on that device. The app asks before creating a missing folder. This setting is separate from `Device Podcast Folder` and defaults to the podcast folder until you choose another location.

Sync writes `.m3u` playlists that reference episodes on the player. Check your player's playlist support and required folder location. The app only replaces or removes playlist files it has recorded as its own in that exact folder; an unrelated file with the same name is not overwritten.

Playlist updates and removals appear in the Sync review. Unavailable episodes are omitted from the device playlist. For unavailable manually added episodes, the app offers a download before opening the review. If no episodes are available for a playlist, its app-managed device file is removed while its definition stays in the app for a later sync.

## Limit episodes kept per podcast during Sync

Device cleanup is optional and is off by default.

1. Open Settings.
2. Under `Device > Device Cleanup`, choose `Keep 3 episodes`, `Keep 5 episodes`, `Keep 10 episodes`, or `Keep 20 episodes` instead of `Off`.
3. Save the setting.

When you next click `Sync`, the app considers both episodes already on the player and dated episodes being copied during that sync. It suggests existing episodes beyond the selected number for each podcast. Every suggested episode appears in the Sync window with its own checkbox. Uncheck anything you want to keep.

For example, if a podcast has five episodes on the player and two newer episodes are being copied, `Keep 5 episodes` suggests deleting the two oldest existing episodes. An older episode being copied is never silently blocked or deleted; the player can temporarily exceed the limit and the episode can be reviewed during a later sync.

Automatic cleanup is deliberately conservative. It considers only MP3 files with trustworthy publication dates that Simple Podcast Manager can associate with a current podcast subscription inside the configured device podcast folder. Undated files do not count toward the limit. If multiple episodes share the date at the keep-limit boundary, all episodes from that date are kept. Unrelated audio and files from unrecognized podcast folders are never selected automatically. You can still select recognized episodes manually from their podcast.

Manually added or pinned playlist episodes are protected from automatic cleanup. The Sync review lists qualifying older episodes under `Older Episodes Kept by Playlists`, unselected by default. Select one only if you want to remove its device file and playlist membership. Automatically added episodes are subject to the normal cleanup limit.

Age-based cleanup settings from earlier versions are ignored, so Device Cleanup starts Off. Choose a per-podcast limit in Settings if you want to use cleanup.

## Sync

1. Connect the MP3 player and wait for it to appear in the Device section.
2. Click `Sync`.
3. Review episode copies and deletions, their sizes, and playlist updates or removals.
4. If cleanup suggested episodes beyond the per-podcast limit, uncheck any episode you want to keep.
5. Choose whether to eject the player or delete local downloads when finished.
6. Click `Sync`.

When cleanup is selected, the Sync window names the configured per-podcast limit and shows how many older episodes are selected. The app checks that the complete, currently selected sync plan will fit before changing the player. Unchecking a deletion can change the space calculation. Deleted files are removed directly from the player rather than moved to Trash.

## Remove episodes from the player

Connect the player, then open a podcast:

- Episodes already on the player have a checked `On MP3 player` box in their episode row.
- Clear the box to mark the episode `Remove on next sync`. Select it again to keep the episode.
- Use `Older episodes on MP3 player` at the bottom of the list for files no longer included in the current feed. The same checkbox is available there.

When Simple Podcast Manager detects unrelated audio inside the configured podcast folder, the device section shows `Scan for Other Audio…`. Click it to open the review window and enumerate those files. The scan runs in the background and can be cancelled. Other audio is deleted only when you select and confirm those exact files; the cleanup setting never selects it.

## Back up, restore, and update

- Back up app data: `Settings > Advanced > App Data > Back Up…`
- Restore app data: `Settings > Advanced > App Data > Restore…`
- Check for updates: `Simple Podcast Manager > Check for Updates…`

Backups include podcasts, playlist definitions and device ownership records, settings, and history, but not downloaded audio files. OPML exports contain only podcast subscriptions, not playlists. Restoring an older backup made before playlist support replaces the playlist library with an empty library. Before restoring, the app asks for confirmation and backs up the current app data. Afterward, it confirms success, shows the backup location, and can reveal it in Finder.

## Troubleshooting

### The app does not see my player

- Make sure the player appears in Finder.
- Make sure it has a top-level `music` folder or a different podcast folder selected in Settings.
- Click the refresh button in the Device section.

### The sync does not fit

Download fewer episodes, or select old episodes for deletion and open the sync plan again.

### An episode beyond the limit was not suggested for cleanup

Cleanup requires a publication date in a recognized Simple Podcast Manager filename and a matching current podcast subscription. Undated files do not count toward the limit. Unrelated audio and files in unrecognized folders must be reviewed manually.

### A playlist is missing or incomplete on the player

- Confirm the player supports M3U playlists and check its required playlist folder. Set that location under `Settings > Device > Device Playlist Folder`.
- Run Sync after creating or changing a playlist; saving it in the app alone does not update the player.
- Check for unavailable episodes. Only episodes present on the player after sync appear in its playlist. A playlist with no available episodes has no device file.
- Review any filename collision error. The app will not overwrite a playlist it does not own; choose a different playlist name or folder.

### A non-MP3 episode does not download

Install [FFmpeg](https://www.ffmpeg.org/download.html), then choose its `ffmpeg` executable under `Settings > Advanced > FFmpeg Path`.
