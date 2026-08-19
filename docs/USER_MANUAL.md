# Simple Podcast Manager Quick Start

Simple Podcast Manager downloads podcast episodes from RSS feeds and syncs them to a standalone MP3 player.

## 1. Install the app

Download the latest DMG from the [Simple Podcast Manager website](https://steveneely.github.io/simple-podcast-manager/), open it, and drag the app to Applications.

If macOS blocks the app the first time you open it, approve it in System Settings > Privacy & Security.

## 2. Prepare your MP3 player

Connect the player.

By default, the player needs a `music` folder at its top level. To use a different folder, select the player in Simple Podcast Manager and change the podcast folder in Settings. The app asks before creating a missing folder.

## 3. Add a podcast

1. Click `Add Podcast`, or use the plus button in the Shows list.
2. Paste the podcast's RSS feed URL.
3. Click `Save`.

The show and its latest episodes will appear in the app.

## 4. Download episodes

1. Select a show.
2. Click the download button beside each episode you want.
3. Wait for the downloads to finish.

If an episode is not already an MP3, the app needs `ffmpeg` to convert it. Choose an `ffmpeg` executable in Settings if prompted.

If episode audio or artwork is available only over unencrypted HTTP, the app warns you first. You can allow that episode once or always allow HTTP podcast downloads in Settings.

Settings can prefix new MP3 titles with the publication date in `MM.dd` format, such as `08.11 Original Title`. Existing downloads are unchanged.

To download new episodes after each feed refresh, choose `Latest 1`, `Latest 2`, `Latest 3`, or `All new` under `Settings > Episode Preparation > Automatic Downloads`. The first refresh records the episodes already in each feed without downloading them, so existing subscriptions do not create a backlog. Edit a show to exclude it from automatic downloads.

## Move Your Podcast Subscriptions

To bring subscriptions from another podcast app, use `File > Import Subscriptions…` and choose its OPML export. Review the list before adding it; feeds already in Simple Podcast Manager and duplicate entries are skipped.

Use `File > Export Subscriptions…` to create a standard OPML file that other podcast apps can import.

For a quick import test, the source checkout includes `SampleData/gpodder-sample-subscriptions.opml`.

## 5. Sync

1. Connect the MP3 player and wait for it to appear in the Device section.
2. Click `Sync`.
3. Review the files that will be copied or deleted and their sizes.
4. Choose whether to eject the player or delete local downloads when finished.
5. Click `Start`.

The app checks that the complete sync will fit before changing the player.

## Remove episodes from the player

Connect the player, then open a show:

- Episodes already on the player have a checked `On MP3 player` box in their episode row.
- Clear the box to mark the episode `Remove on next sync`. Select it again to keep the episode.
- Use `Older episodes on MP3 player` at the bottom of the list for files no longer included in the current feed. The same checkbox is available there.

Other audio is deleted only when you select and confirm those exact files.

## Back up, restore, and update

- Back up app data: `Settings > App Data > Back Up…`
- Restore app data: `Settings > App Data > Restore…`
- Check for updates: `Simple Podcast Manager > Check for Updates…`

Backups include subscriptions, settings, and history, but not downloaded audio files.

## Troubleshooting

### The app does not see my player

- Make sure the player appears in Finder.
- Make sure it has a top-level `music` folder or a different podcast folder selected in Settings.
- Click the refresh button in the Device section.

### The sync does not fit

Download fewer episodes, or select old episodes for deletion and open the sync plan again.

### A non-MP3 episode does not download

Open Settings and choose an installed `ffmpeg` executable.
