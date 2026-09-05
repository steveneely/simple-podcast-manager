# Simple Podcast Manager

<img src="Packaging/AppIcon.png" alt="Simple Podcast Manager icon" width="96" align="right">

Simple Podcast Manager is a native macOS app that downloads podcast episodes from RSS feeds and syncs them to a standalone MP3 player.

Plug in your player, click Sync, and you're done.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/steveneely/simple-podcast-manager/releases/latest), open it, and drag `Simple Podcast Manager.app` to Applications.

The app is not yet Developer ID signed or notarized. If macOS blocks it the first time you open it, follow Apple's guidance for [safely opening apps on your Mac](https://support.apple.com/en-us/102445) and allow it in System Settings > Privacy & Security.

After the first install, enable automatic update checks in Settings or use `Simple Podcast Manager > Check for Updates…` to check immediately.

## What It Does

- Find podcasts by title or creator, add them with RSS feed URLs, or import subscriptions from OPML.
- Download episodes manually or automatically after feed refreshes, write player-friendly MP3 metadata with a genre that defaults to `Podcast` and can be customized or omitted, add podcast artwork, and convert non-MP3 audio with [FFmpeg](https://www.ffmpeg.org/download.html) when needed.
- Review every copy and deletion before sync and confirm the complete plan will fit.
- Optionally suggest app-managed episodes beyond a chosen per-podcast limit, with per-episode review before deletion.
- Remember download and removal history.
- Export subscriptions or back up the app's settings and history.

The app runs locally on your Mac and reads podcasts directly from their RSS feeds.

## Help

New users should start with the [Quick Start](docs/USER_MANUAL.md).

For technical context, see [Architecture](ARCHITECTURE.md).

## Development

Contributions should follow the UI, UX, terminology, compatibility, and testing standards in [AGENTS.md](AGENTS.md), plus the system boundaries in [ARCHITECTURE.md](ARCHITECTURE.md).

Run tests:

```bash
./scripts/swift-test.sh
```

Run from source:

```bash
swift run "Simple Podcast Manager"
```

Build a local DMG without generating a Sparkle appcast:

```bash
SKIP_SPARKLE_APPCAST=1 ./scripts/build-release.sh
```

## License

Simple Podcast Manager is available under the [MIT License](LICENSE). Third-party components are licensed separately; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
