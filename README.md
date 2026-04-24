# Simple Podcast Manager

Simple Podcast Manager is a native macOS app for people who still want a plain RSS-to-MP3-player workflow.

Paste RSS feeds, download episodes, sync them to a standalone MP3 player, and remove old episodes from the device when you are done with them.

The goal is simple:

plug in device -> click sync -> done

## Install

The easiest way to try the app is to download the DMG from the latest GitHub release:

[GitHub Releases](https://github.com/steveneely/simple-podcast-manager/releases)

Open the DMG, drag `Simple Podcast Manager.app` to Applications, and launch it like a normal Mac app.

Current prerelease builds are for testing. They are not Developer ID signed or notarized yet, so macOS may ask you to approve opening the app manually.

## What It Does

- subscribe to podcasts by pasting RSS feed URLs
- fetch feed metadata directly from RSS
- preview recent retained episodes for each show
- download episode audio locally
- convert audio to MP3 with bundled `ffmpeg` in release builds, or a custom `ffmpeg` path in Settings
- sync managed episodes to an MP3 player
- show a sync preview before changing the device
- let you choose on-device episodes to delete during sync
- optionally delete locally downloaded episodes after a successful sync
- move deleted device files through the device trash and clear it only when needed
- remember removed episodes locally
- show when an episode was previously downloaded or removed
- keep a preview-first sync flow so you can inspect changes before running them
- export and import app data backups for subscriptions, settings, and local history

The app is local-first. There is no backend service, hosted account, Apple Podcasts library integration, or Spotify dependency.

## Backup And Restore

Use the File menu to move app data between builds or machines:

- `File > Export App Data…`
- `File > Import App Data…`

Backups are saved as `.spmbackup` folders and include subscriptions, settings, prepared episode metadata, download history, and removed episode history. They do not include downloaded audio files.

## Development

Run the test suite:

```bash
./scripts/swift-test.sh
```

Run the app from source:

```bash
swift run "Simple Podcast Manager"
```

Package a local release DMG:

```bash
FFMPEG_PATH=/path/to/ffmpeg \
FFMPEG_SOURCE_URL=https://example.com/ffmpeg-source-or-build-recipe \
./scripts/build-release.sh
```

For public releases, also set `DEVELOPER_ID_APPLICATION` and `NOTARY_PROFILE` so the generated DMG is signed, notarized, and stapled.

If SwiftPM gets confused after a local folder rename or stale build cache:

```bash
swift package clean
```

## Project Docs

- [Architecture](ARCHITECTURE.md)
- [User Manual](docs/USER_MANUAL.md)

## License

Simple Podcast Manager is available under the [MIT License](LICENSE). Third-party components are licensed separately; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
