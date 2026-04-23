# AGENTS

## Project Goal

S Podcast Manager should feel extremely simple:

plug in device -> click sync -> everything handled -> done

The codebase should optimize for:

- simplicity over cleverness
- safety over convenience
- low-friction UX over feature breadth
- RSS ownership over platform lock-in

## Critical Safety Rules

These rules override convenience or speed:

- Only write under `[device root]/music`
- Only clear `[device root]/.Trashes`
- Never touch the Mac's local Trash
- Never modify files outside the mounted external device
- Never delete files the app does not clearly own
- Abort destructive work if path validation is uncertain

If a proposed implementation weakens those guarantees, do not take it.

## Architecture Guardrails

- Build the app in Swift using `SwiftUI`
- Keep the sync engine in-process and in Swift
- Treat feed metadata refresh as a separate service from media preparation and sync execution
- Use `ffmpeg` as an external process for conversion
- Prefer Foundation and direct platform APIs before adding packages
- Avoid unnecessary frameworks, services, or abstraction layers
- Keep modules small and explicit
- Keep dry-run and real sync behavior aligned through a shared planner

Do not introduce:

- a Python backend
- a database for v1
- background schedulers
- Spotify-dependent download or subscription workflows
- Apple Podcasts library integration assumptions
- extra documentation systems or process overhead

## Implementation Priorities

Implement in this order:

1. safety model and path validation
2. config and app state
3. device detection
4. RSS subscription flow
5. feed parsing and episode selection
6. download and conversion
7. sync planning
8. sync execution, trash cleanup, eject

Prefer a plan-first sync flow:

- compute the intended actions
- show/report the plan
- execute only validated actions

Dry-run must use the same plan as real sync and must not mutate the device.

## Repo Conventions

Once code exists, use this structure:

- `Sources/SPodcastManagerCore/`: domain types, persistence, validation, future sync services
- `Sources/SPodcastManagerUI/`: SwiftUI screens and view models
- `Tests/SPodcastManagerCoreTests/`: core behavior tests
- `Tests/SPodcastManagerUITests/`: UI-facing state tests

Recommended service boundaries:

- feed metadata should be resolved from RSS and applied to saved subscriptions
- UI code should not contain sync logic
- mutation code should be separate from planning code
- path validation should be reusable and called before every destructive operation

Current package targets:

- `SPodcastManagerCore`
- `SPodcastManagerUI`

## Testing Expectations

Add tests around behavior with the highest risk first:

- valid device detection
- invalid or ambiguous device detection
- dry-run parity with real sync planning
- retention deleting only managed files
- trash cleanup touching only device `.Trashes`
- eject only after successful sync

Prefer small focused tests around planner and safety logic before broader integration coverage.
