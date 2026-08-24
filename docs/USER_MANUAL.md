# Simple Podcast Manager quick start

Simple Podcast Manager downloads podcast episodes from RSS feeds and syncs them to a standalone MP3 player.

## Install the app

Download the latest DMG from the [Simple Podcast Manager website](https://steveneely.github.io/simple-podcast-manager/), open it, and drag the app to Applications.

The app is not yet Developer ID signed or notarized. If macOS blocks it the first time you open it, allow it in System Settings > Privacy & Security.

## Prepare your MP3 player

Connect the player.

By default, the player needs a `music` folder at its top level. To use a different folder, select the player in Simple Podcast Manager and change the podcast folder in Settings. The app asks before creating a missing folder.

## Add podcasts

1. Click `Add Podcast`, or use the plus button in the Shows list.
2. Paste the podcast's RSS feed URL.
3. Click `Save`.

The show and its latest episodes will appear in the app.

After that first baseline, blue `new` text beside a show's episode count means its feed has new episodes. The app starts without opening a show, so every show can display its new-episode count. Opening a show clears its count. A successful Sync also clears individual new episodes that were copied to the player or confirmed as already there.

By default, an orange `Inactive` label marks a show whose latest dated episode is more than six months old. Its tooltip shows the latest publication date. Choose `Settings > Inactive Shows` to use three months, six months, one year, or turn this indicator off. Disabled shows, feeds without trustworthy dates, and feeds with a current refresh error are not marked inactive.

Select a show to reveal its Refresh, Edit, and Remove controls. Select it again to clear the selection.

To bring subscriptions from another podcast app, use `File > Import Subscriptions…` and choose its OPML export. Review the list before adding it. Existing subscriptions and duplicate entries are skipped.

Use `File > Export Subscriptions…` to create an OPML file for another podcast app.

## Download episodes

1. Select a show.
2. Click the download button beside each episode you want.
3. Wait for the downloads to finish.

If an episode is not already an MP3, the app needs `ffmpeg` to convert it. Choose an `ffmpeg` executable in Settings if prompted.

If episode audio or artwork is available only over unencrypted HTTP, the app warns you first. You can allow that episode once or always allow HTTP podcast downloads in Settings.

When the feed provides a publication date, files copied to the player start with it in `yyyy.MM.dd` format so they sort reliably. Their embedded MP3 titles keep the original feed text, including special characters. Settings can add a shorter `MM.dd` date to new MP3 titles, such as `08.11 Original Title`. Existing downloads are unchanged.

Leave `Settings > Episode Preparation > Automatic Downloads` set to `Off` for manual downloads, or choose `Latest 1`, `Latest 2`, `Latest 3`, or `All new`. The limit applies separately to each included show after feed refreshes. The first successful refresh records existing episodes without downloading them, so subscriptions do not create a backlog.

Edit a show to change `Include in automatic downloads`. Turn off `Feed enabled` to stop refreshing that show. Automatic downloads prepare episodes on the Mac; syncing starts only when you click `Sync`.

## Clean up old episodes during Sync

Device cleanup is optional and is off by default.

1. Open Settings.
2. Under `MP3 Player > Device Cleanup`, choose an `After…` age instead of `Off`.
3. Save the setting.

When you next click `Sync`, the app suggests eligible episodes older than that limit. Every suggested episode appears in the Sync window with its own checkbox. Uncheck anything you want to keep.

Age is based on the episode publication date in the filename. An episode exactly as old as the selected limit is kept; only episodes strictly older than the limit are suggested.

Automatic cleanup is deliberately conservative. It considers only MP3 files that Simple Podcast Manager can associate with a current podcast subscription inside the configured device podcast folder. Files without a trustworthy publication date, unrelated audio, and files from unrecognized podcast folders are never selected automatically. You can still select recognized episodes manually from their show.

## Sync

1. Connect the MP3 player and wait for it to appear in the Device section.
2. Click `Sync`.
3. Review the files that will be copied or deleted and their sizes.
4. If cleanup suggested old episodes, uncheck any episode you want to keep.
5. Choose whether to eject the player or delete local downloads when finished.
6. Click `Sync`.

When cleanup is selected, the Sync window shows how many episodes are older than the configured limit and reminds you that Device Cleanup is configured in Settings. The app checks that the complete, currently selected sync plan will fit before changing the player. Unchecking a deletion can change the space calculation. Deleted files are removed directly from the player rather than moved to Trash.

## Remove episodes from the player

Connect the player, then open a show:

- Episodes already on the player have a checked `On MP3 player` box in their episode row.
- Clear the box to mark the episode `Remove on next sync`. Select it again to keep the episode.
- Use `Older episodes on MP3 player` at the bottom of the list for files no longer included in the current feed. The same checkbox is available there.

Other audio is deleted only when you select and confirm those exact files. The cleanup setting never selects other audio.

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

### An old episode was not suggested for cleanup

Cleanup requires a publication date in a recognized Simple Podcast Manager filename and a matching current podcast subscription. Undated files, unrelated audio, and files in unrecognized folders must be reviewed manually.

### A non-MP3 episode does not download

Open Settings and choose an installed `ffmpeg` executable.
