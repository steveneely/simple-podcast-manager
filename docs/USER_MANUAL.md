# Simple Podcast Manager quick start

Simple Podcast Manager downloads podcast episodes from RSS feeds and syncs them to a standalone MP3 player.

## Install the app

Download the latest DMG from [GitHub Releases](https://github.com/steveneely/simple-podcast-manager/releases/latest), open it, and drag the app to Applications.

The app is not yet Developer ID signed or notarized. If macOS blocks it the first time you open it, follow Apple's guidance for [safely opening apps on your Mac](https://support.apple.com/en-us/102445) and allow it in System Settings > Privacy & Security.

## Prepare your MP3 player

Connect the player.

By default, the player needs a `music` folder at its top level. To use a different folder, select the player in Simple Podcast Manager and change the podcast folder in Settings. The app asks before creating a missing folder.

## Add podcasts

1. Click `Add Podcast` from the empty podcast panel, or use the plus button in the Podcasts list.
2. Search by podcast title or creator, or select `Feed URL` to paste an RSS feed address.
3. Choose the podcast you want and click `Add Podcast`.

The podcast and its latest episodes will appear in the app.

Podcasts already in your library are marked `Added`. If a search fails, click `Try Again` or add the podcast using its RSS feed URL.

After that first baseline, blue `new` text beside a podcast's episode count means its RSS feed has new episodes. Selecting a podcast does not clear the indicator. It clears one episode at a time after that episode downloads successfully, or after a successful Sync copies it to the player or confirms that it is already there.

By default, an orange `Inactive` label marks a podcast whose latest dated episode is more than six months old. Its tooltip shows the latest publication date. Choose `Settings > Inactive Podcasts` to use three months, six months, one year, or turn this indicator off. Disabled podcasts, RSS feeds without trustworthy dates, and podcasts with a current refresh error are not marked inactive.

Select a podcast to reveal its Refresh, Edit, and Remove controls. Select it again to clear the selection.

To bring subscriptions from another podcast app, use `File > Import Subscriptions…` and choose its OPML export. Review the list before adding it. Existing subscriptions and duplicate entries are skipped.

Use `File > Export Subscriptions…` to create an OPML file for another podcast app.

## Download episodes

1. Select a podcast.
2. Click the download button beside each episode you want.
3. Wait for the downloads to finish.

If an episode is not already an MP3, the app needs [FFmpeg](https://www.ffmpeg.org/download.html) to convert it. Install FFmpeg, then choose its `ffmpeg` executable under `Settings > Advanced > ffmpeg Path`.

If episode audio or artwork is available only over unencrypted HTTP, the app warns you first. You can allow that episode once or always allow HTTP podcast downloads in Settings.

When the feed provides a publication date, files copied to the player start with it in `yyyy.MM.dd` format so they sort reliably. Their embedded MP3 titles keep the original feed text, including special characters. Settings can add a shorter `MM.dd` date to new MP3 titles, such as `08.11 Original Title`.

New downloads use `Podcast` in the MP3's ID3 genre field by default. Change `Settings > Episodes > MP3 Genre` to use a different genre on your player, or leave it blank to omit the genre field. Genre and title settings apply only to new downloads; existing downloads are unchanged.

Leave `Settings > Episodes > Automatic Downloads` set to `Off` for manual downloads, or choose `Latest 1`, `Latest 2`, `Latest 3`, or `All new`. The limit applies separately to each included podcast after RSS feed refreshes. The first successful refresh records existing episodes without downloading them, so subscriptions do not create a backlog.

Edit a podcast to change `Include in automatic downloads`. Turn off `Podcast enabled` to stop refreshing that podcast. Automatic downloads prepare episodes on the Mac; syncing starts only when you click `Sync`.

## Limit episodes kept per podcast during Sync

Device cleanup is optional and is off by default.

1. Open Settings.
2. Under `MP3 Player > Device Cleanup`, choose `Keep 3 episodes`, `Keep 5 episodes`, `Keep 10 episodes`, or `Keep 20 episodes` instead of `Off`.
3. Save the setting.

When you next click `Sync`, the app considers both episodes already on the player and dated episodes being copied during that sync. It suggests existing episodes beyond the selected number for each podcast. Every suggested episode appears in the Sync window with its own checkbox. Uncheck anything you want to keep.

For example, if a podcast has five episodes on the player and two newer episodes are being copied, `Keep 5 episodes` suggests deleting the two oldest existing episodes. An older episode being copied is never silently blocked or deleted; the player can temporarily exceed the limit and the episode can be reviewed during a later sync.

Automatic cleanup is deliberately conservative. It considers only MP3 files with trustworthy publication dates that Simple Podcast Manager can associate with a current podcast subscription inside the configured device podcast folder. Undated files do not count toward the limit. If multiple episodes share the date at the keep-limit boundary, all episodes from that date are kept. Unrelated audio and files from unrecognized podcast folders are never selected automatically. You can still select recognized episodes manually from their podcast.

Age-based cleanup settings from earlier versions are ignored, so Device Cleanup starts Off. Choose a per-podcast limit in Settings if you want to use cleanup.

## Sync

1. Connect the MP3 player and wait for it to appear in the Device section.
2. Click `Sync`.
3. Review the files that will be copied or deleted and their sizes.
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

- Back up app data: `Settings > App Data > Back Up…`
- Restore app data: `Settings > App Data > Restore…`
- Check for updates: `Simple Podcast Manager > Check for Updates…`

Backups include subscriptions, settings, and history, but not downloaded audio files. Before restoring, the app asks for confirmation and backs up the current app data. Afterward, it confirms success, shows the backup location, and can reveal it in Finder.

## Troubleshooting

### The app does not see my player

- Make sure the player appears in Finder.
- Make sure it has a top-level `music` folder or a different podcast folder selected in Settings.
- Click the refresh button in the Device section.

### The sync does not fit

Download fewer episodes, or select old episodes for deletion and open the sync plan again.

### An episode beyond the limit was not suggested for cleanup

Cleanup requires a publication date in a recognized Simple Podcast Manager filename and a matching current podcast subscription. Undated files do not count toward the limit. Unrelated audio and files in unrecognized folders must be reviewed manually.

### A non-MP3 episode does not download

Install [FFmpeg](https://www.ffmpeg.org/download.html), then choose its `ffmpeg` executable under `Settings > Advanced > ffmpeg Path`.
