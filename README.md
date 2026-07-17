# Simple Podcast Manager

<p align="center">
  <img src="Packaging/AppIcon.png" alt="Simple Podcast Manager icon" width="128">
</p>

Simple Podcast Manager is a native macOS app for a plain RSS-to-MP3-player workflow:

plug in device -> click sync -> done

It is built for people who want to own their podcast subscriptions, download normal audio files, and copy MP3s to a standalone player without a hosted account or platform lock-in.

## Install

Download the DMG from the [Simple Podcast Manager website](https://steveneely.github.io/simple-podcast-manager/), open it, and drag `Simple Podcast Manager.app` to Applications.

Current prerelease builds are not Developer ID signed or notarized yet, so macOS may ask you to approve opening the app manually.

After the first install, enable automatic checks in Settings or use `Simple Podcast Manager > Check for Updates…` for an immediate check. Local development builds run with app updates disabled.

## What It Does

- Subscribe to podcasts with RSS feed URLs.
- Download episodes, embed podcast artwork, and optionally convert non-MP3 audio with `ffmpeg`.
- Review the full-device plan before changing your MP3 player.
- Copy managed episodes to the device and delete selected managed episodes from it.
- Store device settings in `[device root]/.spmconfig`, including the podcast target folder.
- Write podcast files only into that configured folder, defaulting to `[device root]/music`.
- Remember downloaded and removed episodes.
- Cache parsed feed data locally for faster startup, then refresh feeds in the background.
- Export and import subscriptions, settings, and local history.
- Check for app updates in place with Sparkle.

The app is local-first: no backend service, hosted account, Spotify dependency, or Apple Podcasts library integration.

## Help

New users should start with the [User Manual](docs/USER_MANUAL.md).

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

Verify the release bundle, DMG, and Sparkle appcast:

```bash
./scripts/verify-release.sh
```

To bundle `ffmpeg` for non-MP3 conversion, set `FFMPEG_PATH` and `FFMPEG_SOURCE_URL` before running the release script. MP3 cover art is written natively and does not require `ffmpeg`.

For public releases, set `DEVELOPER_ID_APPLICATION` and `NOTARY_PROFILE` to sign, notarize, and staple the DMG.

Release builds use Sparkle for in-app updates. Keep `CFBundleVersion` as an incrementing integer, keep `SPMReleaseTag` aligned with the GitHub release tag, never commit Sparkle private keys, and publish the generated `dist/updates/appcast.xml` alongside the release assets.

## License

Simple Podcast Manager is available under the [MIT License](LICENSE). Third-party components are licensed separately; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
