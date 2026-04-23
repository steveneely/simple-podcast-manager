# PodcastSwift

PodcastSwift is a macOS app for getting podcasts onto a Sony MP3 player with as little friction as possible:

plug in device -> click sync -> done

## Product Intent

The app should feel fast, obvious, and safe. It should handle the full happy path for a plugged-in device:

- discover podcasts through in-app search
- subscribe to podcasts by adding their RSS feeds
- read podcast RSS feeds
- download the latest episodes
- convert audio to MP3 with `ffmpeg` when needed
- sync files to the device
- remove older managed episodes based on retention rules
- clear only the device's `.Trashes`
- optionally eject the device after a successful sync

## Technical Direction

PodcastSwift is planned as:

- a native macOS app built with `SwiftUI`
- an in-process sync engine written in Swift
- an RSS-first discovery flow backed by a podcast directory API
- `ffmpeg` invoked as an external command for audio conversion

No Python backend is planned for v1. The project is intentionally native and minimal.

## Safety Guarantees

Safety is the main product requirement, not a nice-to-have.

- Only write inside `[device root]/music`
- Only permanently clear `[device root]/.Trashes`
- Never touch files outside the mounted device root
- Never touch the Mac's local Trash
- Refuse destructive work when path validation is uncertain

## Planned App Shape

The v1 app is a single-window SwiftUI app with:

- podcast discovery search
- a feed list and feed editor
- device connection status
- dry-run and eject-after-sync options
- a single `Sync` action
- progress and result reporting

## Planned Structure

High-level code organization:

- `Sources/PodcastSwiftCore/`: models, persistence, safety validation
- `Sources/PodcastSwiftUI/`: SwiftUI views and view models
- `Tests/PodcastSwiftCoreTests/`: core persistence and safety tests
- `Tests/PodcastSwiftUITests/`: UI-facing state tests

See [ARCHITECTURE.md](/Users/sneely/code/podcastswift/ARCHITECTURE.md) for the implementation source of truth and [docs/IMPLEMENTATION_PLAN.md](/Users/sneely/code/podcastswift/docs/IMPLEMENTATION_PLAN.md) for milestone order.

## Current Status

Implemented so far:

- milestone 1: domain models and safety validator
- milestone 2: JSON-backed configuration store and basic SwiftUI state/editor flow
- milestone 3: Podcast Index-backed discovery flow and subscribe-from-search support
- milestone 4: mounted-device detection, candidate selection, and validation UI state
- milestone 5: RSS feed parsing and retained-episode preview for enabled feeds
- milestone 6: temporary-media preparation with download preview and MP3 conversion decisions

Current package targets:

- `PodcastSwiftCore`
- `PodcastSwiftUI`

Current discovery setup:

- Podcast Index is the implemented search provider
- discovery requires a Podcast Index API key and secret in app settings
- manual RSS entry remains available when discovery is not configured

Current verification command:

```bash
CLANG_MODULE_CACHE_PATH=/Users/sneely/code/podcastswift/.swift-cache/clang-module-cache \
SWIFTPM_CACHE_PATH=/Users/sneely/code/podcastswift/.swift-cache/swiftpm-cache \
swift test
```

Current app launch command:

```bash
CLANG_MODULE_CACHE_PATH=/Users/sneely/code/podcastswift/.swift-cache/clang-module-cache \
SWIFTPM_CACHE_PATH=/Users/sneely/code/podcastswift/.swift-cache/swiftpm-cache \
swift run "Podcast Swift"
```

## Status

This repo now contains the initial Swift package foundation plus planning docs for the remaining milestones.
