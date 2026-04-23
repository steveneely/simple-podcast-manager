# S Podcast Manager Implementation Plan

## Summary

This document is the execution checklist for v1. It is ordered so the highest-risk correctness work happens before convenience features. Each milestone should be complete enough to leave the repo in a coherent state.

## Milestone 1: Domain Model And Safety Rules

Status: complete

Define the core models and the hard safety constraints that all later code must follow.

Deliverables:

- app settings model
- feed subscription model
- episode model
- device info model
- sync action and sync plan models
- sync result model
- centralized safety validator rules

Acceptance criteria:

- the app has explicit types for sync inputs, planned actions, and results
- safety invariants are written into code-facing model and validator design
- destructive actions can only target `[device root]/music` or `[device root]/.Trashes`

Depends on:

- none

## Milestone 2: Config And App State

Status: complete

Create local persistence for feeds and settings and wire basic UI state to it.

Deliverables:

- persisted feed subscriptions
- persisted app settings
- editable feed list UI
- feed add/edit/remove flow
- dry-run and eject-after-sync settings state

Acceptance criteria:

- feeds and settings survive app relaunch
- the main UI can represent an empty state cleanly
- no sync logic is embedded in view code

Depends on:

- milestone 1

## Milestone 3: RSS Subscription Flow

Status: complete

Add a clean RSS subscription flow so the user can add shows by feed URL and have the app resolve metadata automatically.

Deliverables:

- add/edit RSS UI
- feed metadata resolution
- subscription persistence from resolved metadata
- manual RSS entry flow

Acceptance criteria:

- a valid RSS feed URL creates a saved feed subscription
- feed title and artwork are read from the feed
- invalid RSS URLs surface a clear error

Depends on:

- milestone 1
- milestone 2

## Milestone 4: Device Detection And Validation

Status: complete

Build mounted-volume discovery and strict sync target validation.

Deliverables:

- mounted volume inspection
- valid candidate filtering
- device selection behavior
- target path resolution for `[device root]/music`
- trash path resolution for `[device root]/.Trashes`

Acceptance criteria:

- valid device mounted with `music` present is detected
- no valid device mounted results in a blocked sync state
- multiple valid devices require explicit user choice
- destructive work cannot proceed without passing validation

Depends on:

- milestone 1
- milestone 2

## Milestone 5: Feed Reading And Episode Selection

Status: complete

Implement RSS fetch/parsing and choose desired episodes for each enabled feed.

Deliverables:

- feed fetch service
- RSS parsing
- enabled feed filtering
- latest episode selection logic
- retention-policy-aware desired episode set

Acceptance criteria:

- feed fetch success produces structured episodes
- feed fetch failure is surfaced clearly
- selected episodes are deterministic for a given feed response

Depends on:

- milestone 1
- milestone 2

## Milestone 6: Download And MP3 Conversion

Status: complete

Normalize remote media into local files ready for sync.

Deliverables:

- temporary workspace handling
- media download service
- MP3 passthrough behavior
- conversion through `ffmpeg`
- error reporting for missing `ffmpeg` or failed conversion

Acceptance criteria:

- MP3 input can pass through without conversion
- non-MP3 input can be converted to MP3
- conversion and download failures are visible in the UI state

Depends on:

- milestone 5

## Milestone 7: Sync Planning

Status: complete

Create the planning layer that compares desired episodes with the device state and produces executable actions.

Deliverables:

- managed on-device layout under `[device root]/music/<podcast-name>/`
- copy/skip/delete action planning
- retention-based old episode selection
- trash cleanup planning
- optional eject planning
- dry-run reporting

Acceptance criteria:

- dry-run produces the same action plan real sync would execute
- retention deletes only managed files under device `music`
- planned actions are explicit and inspectable

Depends on:

- milestone 4
- milestone 6

## Milestone 8: Execution, Progress, And Eject

Status: next

Execute the validated plan and report results in the UI.

Deliverables:

- copy execution
- scoped delete execution
- device trash cleanup execution
- progress reporting
- final sync summary
- optional device eject after success

Acceptance criteria:

- only validated planned actions are executed
- device `.Trashes` is the only permanent trash cleanup target
- eject is attempted only after a successful run
- the user can understand what happened from the progress and summary output

Depends on:

- milestone 7

## Do Not Build Yet

Out of scope for v1:

- background scheduling
- automatic periodic sync
- a Python backend
- database-backed persistence
- advanced episode filtering rules
- bundled `ffmpeg`
- Apple Podcasts library integration
- Spotify-based download or sync integration
- multi-provider ranking or recommendation engines
- Sony-specific identification beyond mounted-device validation
- broad docs beyond the core repo guidance files
