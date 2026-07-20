# Simple Podcast Manager Quick Start

Simple Podcast Manager downloads podcast episodes from RSS feeds and syncs them to a standalone MP3 player.

## 1. Install The App

Download the latest DMG from the [Simple Podcast Manager website](https://steveneely.github.io/simple-podcast-manager/), open it, and drag the app to Applications.

If macOS blocks the app the first time you open it, approve it in System Settings > Privacy & Security.

## 2. Prepare Your MP3 Player

Connect the player and make sure it appears in Finder.

By default, the player needs a `music` folder at its top level. To use a different folder, select the player in Simple Podcast Manager and change the podcast folder in Settings. The app asks before creating a missing folder.

## 3. Add A Podcast

1. Click `Add Podcast`, or use the plus button in the Shows list.
2. Paste the podcast's RSS feed URL.
3. Click `Save`.

The show and its latest episodes will appear in the app.

## 4. Download Episodes

1. Select a show.
2. Click the download button beside each episode you want.
3. Wait for the downloads to finish.

If an episode is not already an MP3, the app needs `ffmpeg` to convert it. Choose an `ffmpeg` executable in Settings if prompted.

## 5. Sync

1. Connect the MP3 player and wait for it to appear in the Device section.
2. Click `Sync`.
3. Review the files that will be copied or deleted and their sizes.
4. Choose whether to eject the player or delete local downloads when finished.
5. Click `Start`.

The app checks that the complete sync will fit before changing the player.

## Remove Episodes From The Player

Open a show and find its files under `On Device`:

- Checked files stay on the player.
- Unchecked files are deleted during the next sync.

Other audio is deleted only when you select and confirm those exact files.

## Backup, Restore, And Update

- Back up app data: `File > Export App Data…`
- Restore app data: `File > Import App Data…`
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
