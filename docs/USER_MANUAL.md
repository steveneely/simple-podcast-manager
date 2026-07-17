# Simple Podcast Manager User Manual

Simple Podcast Manager helps you keep a standalone MP3 player stocked with podcast episodes from RSS feeds.

The basic flow is:

1. Add podcast RSS feeds.
2. Download the episodes you want.
3. Plug in an MP3 player.
4. Review the plan.
5. Start the run.

## Install The App

Download the latest DMG from the [Simple Podcast Manager website](https://steveneely.github.io/simple-podcast-manager/).

Open the DMG and drag `Simple Podcast Manager.app` to Applications.

Current prerelease builds are not Developer ID signed or notarized yet. If macOS blocks the app the first time you open it, use System Settings > Privacy & Security to approve it.

After the app is installed, use `Simple Podcast Manager > Check for Updates…` for an immediate check. You can also enable automatic checks in Settings; when enabled, the app checks each time it opens and shows an update window when a newer version is available. Local development builds do not check for app updates.

## Prepare Your MP3 Player

Simple Podcast Manager looks for removable or external volumes under `/Volumes`.

By default, your device needs a folder named `music` at the top level:

```text
Your Device/
  music/
```

You can change the podcast folder for a selected device in Settings. The app stores that device-specific choice in a small `.spmconfig` file at the device root:

```text
Your Device/
  .spmconfig
  podcasts/
```

For example, `.spmconfig` can tell the app to use a `podcasts` folder instead of `music`:

```ini
[simple-podcast-manager]
podcast-dir: podcasts
```

The app writes only two places on the device:

- `[device root]/.spmconfig`
- the configured podcast folder, such as `[device root]/music` or `[device root]/podcasts`

It will not modify other device-root files or other folders on the device.

If you choose a podcast folder that does not exist yet, the app asks before creating it. Canceling that prompt does not create the folder and does not write `.spmconfig`.

## Add A Podcast

1. Open Simple Podcast Manager.
2. Click `Add Podcast` when the library is empty. After you add your first show, use the plus button in the Shows list to add more.
3. Paste the podcast's RSS feed URL.
4. Leave `Feed enabled` checked if you want the show included in planning.
5. Save the show.

The app reads the podcast title and artwork from the RSS feed.

## Download Episodes

Select a show to see its current feed episodes.

- Click the download button next to one episode to prepare that episode.
- Use the control at the bottom of the episode list to load eight more episodes at a time.

The app can prepare normal MP3 podcast episodes without `ffmpeg`. Choose an `ffmpeg` executable in Settings before downloading non-MP3 episodes.

When the RSS feed provides artwork, newly downloaded episodes include a small copy of that image as MP3 cover art when possible.

## Sync To A Device

1. Plug in your MP3 player.
2. Wait for the Device section to show it as selected.
3. Click `Sync`.
4. Review the planned copies, skips, deletions, and optional eject.
5. Optionally check `Delete downloaded episodes when finished` to remove local downloaded episode files after a successful run.
6. Click `Start`.

The app keeps files organized by show:

```text
Your Device/
  music/
    Podcast Name/
      2026-04-24 Episode Title.mp3
```

If you choose a different device podcast folder in Settings, the same per-show folders are created there instead.

## Delete Episodes From The Device

When a device is selected, each show can display its current on-device files.

- Checked files stay on the device.
- Unchecked files are planned for deletion during the next run.

Deleted files are removed directly from the device. Sync only deletes app-managed podcast files inside the configured podcast folder. Other audio in that folder is never deleted by Sync and can only be removed after you select and confirm the exact files. The app does not delete from other folders on the device.

## Local Download History

The episode list shows whether an episode has already been downloaded locally. When the app knows the date, it shows the last downloaded date.

The episode list also marks episodes that were previously removed from the device.

## Backup And Restore App Data

Use the File menu:

- `File > Export App Data…`
- `File > Import App Data…`

Backups are saved as `.spmbackup` folders and include:

- subscriptions
- settings
- prepared episode metadata
- download history
- removed episode history

Backups do not include downloaded audio files.

When importing, the app validates the backup before writing anything and saves a copy of your current app data first.

## Update The App

Choose `Simple Podcast Manager > Check for Updates…`.

To check automatically whenever the installed app opens, enable `Automatically check for updates` in Settings. A newer version is presented during that launch; automatic checks do not silently download, install, or restart the app. You can change this choice at any time.

If an update is available, the app will show the update details and let you choose when to install and relaunch. The DMG install flow is only needed for first install or manual reinstall.

## Troubleshooting

### The app does not see my device

Check that:

- the device is mounted in Finder
- the device has a top-level `music` folder, or a `.spmconfig` file that points to an existing podcast folder
- the device is removable or external

Click the refresh button in the Device section after making changes.

### Non-MP3 episodes do not download

The app needs `ffmpeg` to convert non-MP3 audio.

Open Settings and choose an installed `ffmpeg` executable.

### I want to move data from a test build to an installed build

In the test build, choose `File > Export App Data…`.

In the installed build, choose `File > Import App Data…` and select the exported `.spmbackup` folder.

### I want to inspect the app data manually

App data lives in:

```text
~/Library/Application Support/SimplePodcastManager/
```

Manual editing is not recommended. Use export/import when possible.
