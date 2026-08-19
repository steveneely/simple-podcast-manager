# Simple Podcast Manager

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Simple Podcast Manager icon" width="128">
</p>

Simple Podcast Manager is a native macOS app for a plain RSS-to-MP3-player workflow:

plug in device -> click sync -> done

It uses podcast RSS feeds directly, downloads episodes to your Mac, and syncs them to a standalone MP3 player.

## Install

Download the DMG from the [Simple Podcast Manager website](https://steveneely.github.io/simple-podcast-manager/), open it, and drag `Simple Podcast Manager.app` to Applications.

Current prerelease builds are not Developer ID signed or notarized yet, so macOS may ask you to approve opening the app manually.

After the first install, enable automatic checks in Settings or use `Simple Podcast Manager > Check for Updates…` for an immediate check.

## What It Does

- Subscribe to podcasts with RSS feed URLs.
- Import or export podcast subscriptions with standard OPML files.
- Download episodes, embed podcast artwork, and optionally convert non-MP3 audio with `ffmpeg`.
- Review the full-device plan before changing your MP3 player.
- Check that a sync will fit before changing your MP3 player.
- Copy managed episodes to the device and delete selected managed episodes from it.
- Remember downloaded and removed episodes.
- Back up and restore your subscriptions, settings, and history.

The app runs locally on your Mac and reads podcasts directly from their RSS feeds.

## Help

New users should start with the [Quick Start](docs/USER_MANUAL.md).

For technical context, see [Architecture](ARCHITECTURE.md).

## Development

Run tests:

```bash
./scripts/swift-test.sh
```

Run from source:

```bash
swift run "Simple Podcast Manager"
```

Build a local DMG:

```bash
./scripts/build-release.sh
```

## License

Simple Podcast Manager is available under the [MIT License](LICENSE). Third-party components are licensed separately; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
