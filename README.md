# Simple Podcast Manager

Simple Podcast Manager is a native macOS app for one very specific job: subscribe to podcasts with RSS, download episodes, sync them to an MP3 player, and clean old episodes off the device without a bunch of extra ceremony.

I built it after my iPod mini finally died and I replaced it with a Sony Walkman MP3 player. There still are not many simple desktop apps for the "plain RSS feeds + local files + sync to a standalone player" workflow, so this project is focused entirely on that use case.

The goal is:

plug in device -> click sync -> done

## What It Does

- subscribe to podcasts by pasting RSS feed URLs
- fetch feed metadata directly from RSS
- preview recent retained episodes for each show
- download episode audio locally
- convert audio to MP3 with bundled `ffmpeg` when needed
- sync managed episodes to an MP3 player
- delete older episodes from the device when you choose to remove them
- keep a preview-first sync flow so you can inspect changes before running them

## What It Is

- a macOS app
- written in Swift
- built with `SwiftUI`
- intentionally local-first and simple

There is no backend service, no hosted account system, and no dependency on Apple Podcasts or Spotify libraries.

## Safety Rules

The app is conservative on purpose:

- only write inside `[device root]/music`
- only clear `[device root]/.Trashes`
- never touch the Mac's local Trash
- never modify files outside the mounted external device
- abort destructive work when path validation is uncertain

## Current Structure

- `Sources/SimplePodcastManagerCore/`: sync logic, persistence, RSS, safety validation
- `Sources/SimplePodcastManagerUI/`: SwiftUI views and view models
- `Tests/SimplePodcastManagerCoreTests/`: core behavior tests
- `Tests/SimplePodcastManagerUITests/`: UI-facing state tests

Internal package/module names are still:

- `SimplePodcastManagerCore`
- `SimplePodcastManagerUI`
- `SimplePodcastManagerApp`

## Development

Run the test suite with:

```bash
./scripts/swift-test.sh
```

Run the app with:

```bash
swift run "Simple Podcast Manager"
```

Package a local release DMG with:

```bash
FFMPEG_PATH=/path/to/ffmpeg \
FFMPEG_SOURCE_URL=https://example.com/ffmpeg-source-or-build-recipe \
./scripts/build-release.sh
```

For public releases, also set `DEVELOPER_ID_APPLICATION` and `NOTARY_PROFILE` so the generated DMG is signed, notarized, and stapled.

If SwiftPM gets confused after a local folder rename or stale build cache, run:

```bash
swift package clean
```

See [ARCHITECTURE.md](/Users/sneely/code/simple-podcast-manager/ARCHITECTURE.md) for the codebase structure and [docs/IMPLEMENTATION_PLAN.md](/Users/sneely/code/simple-podcast-manager/docs/IMPLEMENTATION_PLAN.md) for the original milestone plan.
