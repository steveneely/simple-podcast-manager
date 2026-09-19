# Simple Podcast Manager

Simple Podcast Manager is a native macOS app that downloads podcast episodes from RSS feeds and syncs them to a standalone MP3 player.

Plug in your player, click Sync, and you're done.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/steveneely/simple-podcast-manager/releases/latest), open it, and drag `Simple Podcast Manager.app` to Applications.

The app is not yet Developer ID signed or notarized. If macOS blocks it the first time you open it, allow it in System Settings > Privacy & Security.

After the first install, enable automatic updates in Settings or use `Simple Podcast Manager > Check for Updates…` to check immediately.

## What It Does

- Find podcasts by title or creator, add them with RSS feed URLs, or import subscriptions from an OPML file—a standard format for transferring lists of podcast RSS feed URLs between apps.
- Download episodes manually or automatically after feed refreshes, write player-friendly MP3 metadata with a genre that defaults to `Podcast` and can be customized or omitted, add podcast artwork, and convert non-MP3 audio with a separately installed [FFmpeg](https://www.ffmpeg.org/download.html) executable when needed.
- Create playlists with manually ordered episodes or automatic additions from selected podcasts, then sync M3U files to a configurable device playlist folder. See [Playlists](docs/USER_MANUAL.md#playlists).
- Review every copy, deletion, and playlist update before sync and confirm the complete plan will fit.
- Optionally suggest app-managed episodes beyond a chosen per-podcast limit, with per-episode review before deletion.
- Remember download and removal history.
- Export subscriptions or back up podcasts, playlists, settings, and history.

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
swift run --build-system native "Simple Podcast Manager"
```

Build an isolated local development app:

```bash
./scripts/build-dev.sh
open -n "$PWD/dist/dev/Simple Podcast Manager Dev.app"
```

Development runs use `.dev-data/SimplePodcastManager` inside their own checkout. Packaged dev apps have a separate app identity and disable updates. Never use installed app data or launch release artifacts for testing.

## License

Simple Podcast Manager is available under the [MIT License](LICENSE). Third-party components are licensed separately; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
