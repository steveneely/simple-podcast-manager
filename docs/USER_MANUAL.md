# Simple Podcast Manager User Manual

Simple Podcast Manager helps you keep a standalone MP3 player stocked with podcast episodes from RSS feeds.

The basic flow is:

1. Add podcast RSS feeds.
2. Download the episodes you want.
3. Plug in an MP3 player with a `music` folder.
4. Preview the sync.
5. Run the sync.

## Install The App

Download the latest DMG from GitHub Releases:

https://github.com/steveneely/simple-podcast-manager/releases

Open the DMG and drag `Simple Podcast Manager.app` to Applications.

Current prerelease builds are not Developer ID signed or notarized yet. If macOS blocks the app the first time you open it, use System Settings > Privacy & Security to approve it.

## Prepare Your MP3 Player

Simple Podcast Manager looks for removable or external volumes under `/Volumes`.

Your device needs a folder named `music` at the top level:

```text
Your Device/
  music/
```

The app only writes podcast files inside that `music` folder. It will not write elsewhere on the device.

## Add A Podcast

1. Open Simple Podcast Manager.
2. Click the plus button in the Shows list.
3. Paste the podcast's RSS feed URL.
4. Choose how many recent episodes to keep.
5. Save the show.

The app reads the podcast title and artwork from the RSS feed.

## Download Episodes

Select a show to see its retained episodes.

- Click the download button next to one episode to prepare that episode.
- Click `Download All` to prepare all currently selected episodes for that show.

Release builds can include bundled `ffmpeg` for converting non-MP3 audio. If your build does not include bundled `ffmpeg`, set an `ffmpeg` path in Settings before downloading non-MP3 episodes.

## Sync To A Device

1. Plug in your MP3 player.
2. Wait for the Device section to show it as selected.
3. Click `Preview Sync`.
4. Review the planned copies, skips, deletions, trash cleanup, and optional eject.
5. Leave `Preview only (dry run)` checked to test without changing the device.
6. Uncheck `Preview only (dry run)` when you are ready to sync for real.
7. Click `Start Sync`.

The app keeps files organized by show:

```text
Your Device/
  music/
    Podcast Name/
      2026-04-24 Episode Title.mp3
```

## Delete Episodes From The Device

When a device is selected, each show can display its current on-device files.

- Checked files stay on the device.
- Unchecked files are planned for deletion during the next real sync.

Deleted files are moved through the device's trash and the app only clears the device trash when deletions actually happened.

## Backup And Restore App Data

Use the File menu:

- `File > Export App Data…`
- `File > Import App Data…`

Backups are saved as `.spmbackup` folders and include:

- subscriptions
- settings
- prepared episode metadata
- removed episode history

Backups do not include downloaded audio files.

When importing, the app validates the backup before writing anything and saves a copy of your current app data first.

## Troubleshooting

### The app does not see my device

Check that:

- the device is mounted in Finder
- the device has a top-level `music` folder
- the device is removable or external

Click the refresh button in the Device section after making changes.

### Non-MP3 episodes do not download

The app needs `ffmpeg` to convert non-MP3 audio.

Use a release build with bundled `ffmpeg`, or open Settings and set the full path to an installed `ffmpeg` executable.

### I want to move data from a test build to an installed build

In the test build, choose `File > Export App Data…`.

In the installed build, choose `File > Import App Data…` and select the exported `.spmbackup` folder.

### I want to inspect the app data manually

App data lives in:

```text
~/Library/Application Support/SimplePodcastManager/
```

Manual editing is not recommended. Use export/import when possible.
