# AGENTS

## Project Goal

Simple Podcast Manager should feel extremely simple:

plug in device -> click sync -> everything handled -> done

The codebase should optimize for:

- simplicity over cleverness
- safety over convenience
- low-friction UX over feature breadth
- RSS ownership over platform lock-in

## Critical Safety Rules

These rules override convenience or speed:

- Only write `.spmconfig` at `[device root]/.spmconfig` for app-managed device configuration such as the podcast target folder
- Only write podcast media under the configured device podcast directory, defaulting to `[device root]/music` when no target is configured
- Only delete app-managed podcast files automatically under the configured device podcast directory
- The app may delete other audio under the configured device podcast directory only when the user explicitly selects and confirms those exact files
- Never touch the Mac's local Trash
- Never modify files outside the mounted external device
- Never modify other device-root files or other folders on the device
- Never delete files the app does not clearly own without explicit, per-file user selection and confirmation
- Abort destructive work if path validation is uncertain

If a proposed implementation weakens those guarantees, do not take it.

## Working Conventions

- Follow `ARCHITECTURE.md` for system design and technical boundaries; update it when the design changes
- Prefer simple, explicit implementations and avoid unnecessary dependencies or abstraction layers
- Keep user-visible behavior and executed behavior aligned
- Preserve unrelated user changes in a dirty worktree

When adding files, use the existing package layout:

- `Sources/SimplePodcastManagerCore/`: domain types, persistence, validation, and sync services
- `Sources/SimplePodcastManagerUI/`: SwiftUI screens and view models
- `Tests/SimplePodcastManagerCoreTests/`: core behavior tests
- `Tests/SimplePodcastManagerUITests/`: UI-facing state tests

## Release Workflow

- `CFBundleVersion` must be an incrementing integer
- `CFBundleShortVersionString` is the user-visible update version shown by Sparkle; do not leave it unchanged when publishing a user-facing update
- `SPMReleaseTag` must match the GitHub release tag and start with `v<CFBundleShortVersionString>`
- before any release/version bump, ask Steve which user-visible semver bump to use unless he has already specified it in the current request
- use patch bumps, such as `1.3.2`, for small fixes, cleanup, copy changes, and narrow UX improvements
- use minor bumps, such as `1.4.0`, for backward-compatible new workflows, meaningful user-facing capabilities, or larger sync/download/device behavior changes
- use major bumps, such as `2.0.0`, for breaking changes to data compatibility, device behavior, or user workflows
- `SUPublicEDKey` is public and may be committed
- Sparkle private keys, Developer ID credentials, notarization profiles, and appcast signing secrets must never be committed
- run `./scripts/swift-test.sh` and `./scripts/verify-release.sh` before publishing a release
- every release must include clear user-facing notes in `RELEASE_NOTES.md` before building; these notes are embedded in the Sparkle appcast and shown in `Check for Updates…`, but the release-note requirement itself is developer/agent process and should not be surfaced to users
- release notes must mention the exact `SPMReleaseTag` and describe user-visible changes; never ship generic notes like only `Build 32.`
- keep only the currently published release in the Sparkle appcast
- release notes should describe user-visible changes since the previous release; repeat an older change only when it affects compatibility, migration, safety, or requires user action when upgrading across skipped versions
- keep Sparkle release notes concise, generally 3–6 bullets, and omit internal implementation details
- when bumping `CFBundleVersion` or `SPMReleaseTag`, complete the full update path before calling the work done: build the DMG, run `./scripts/verify-release.sh`, upload the exact versioned DMG referenced by the appcast from `dist/updates/SimplePodcastManager-<SPMReleaseTag>.dmg`, publish `gh-pages:appcast.xml`, and verify the live appcast advertises the new Sparkle version
- the GitHub release asset name must match the Sparkle appcast enclosure URL exactly; do not upload only the generic `dist/SimplePodcastManager.dmg` for an update release
- after publishing the release, make a HEAD request or equivalent check against the live appcast enclosure URL and confirm it resolves before calling the release done

Website publishing:

- GitHub Pages serves from the `gh-pages` branch at repository root
- keep the canonical website source in `main` at `docs/index.html`
- when changing the website, copy `docs/index.html` to `gh-pages:index.html` and preserve existing `gh-pages` files such as `appcast.xml` and `.nojekyll`
- Sparkle update publishing also updates `gh-pages:appcast.xml`

## Testing Expectations

Add tests around behavior with the highest risk first:

- valid device detection
- invalid or ambiguous device detection
- user-visible sync plan parity with executed device actions
- config writes touching only `[device root]/.spmconfig`
- automatic copy/delete touching only app-managed files under the configured device podcast directory
- explicit other-audio deletion requiring per-file selection and confirmation inside the configured device podcast directory
- eject only after successful sync

Prefer small focused tests around planner and safety logic before broader integration coverage.
