# AGENTS

## Project Goal

Simple Podcast Manager should feel extremely simple:

plug in device, click sync, done

## Engineering Standards

Code should be:

- clear and readable, with descriptive names and explicit control flow
- simple to change and maintain
- divided into small, focused components with clear responsibilities
- reusable where behavior is genuinely shared, without premature abstraction
- testable through explicit inputs, outputs, and dependency boundaries
- consistent with established project patterns
- covered by focused tests, especially around sync and device safety

Remove duplication when doing so improves clarity. Do not apply DRY mechanically when a shared abstraction would make the code harder to understand.

## Critical Safety Rules

These rules override convenience or speed:

- Only write `.spmconfig` at `[device root]/.spmconfig` for app-managed device configuration such as the podcast target folder
- Only write podcast media under the configured device podcast directory, defaulting to `[device root]/music` when no target is configured
- Only delete app-managed podcast files selected by the user under the configured device podcast directory
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

### Versioning

Before changing release metadata, ask Steve which user-visible semver bump to use unless he already specified it in the current request.

- use a patch bump, such as `1.3.2`, for a small fix, cleanup, copy change, or narrow UX improvement
- use a minor bump, such as `1.4.0`, for a backward-compatible workflow, meaningful capability, or larger sync/download/device behavior change
- use a major bump, such as `2.0.0`, for a breaking change to data compatibility, device behavior, or user workflows

Keep the release identifiers aligned:

- increment the integer `CFBundleVersion`
- update `CFBundleShortVersionString` for every user-facing release
- set `SPMReleaseTag` to the GitHub tag, beginning with `v<CFBundleShortVersionString>`

### Release Notes

Write `RELEASE_NOTES.md` before building because its contents are embedded in the Sparkle appcast.

- mention the exact `SPMReleaseTag`
- describe user-visible changes since the previous release
- keep the notes concise, generally 1 to 4 bullets
- omit internal implementation details
- repeat an older change only when it affects compatibility, migration, safety, or requires user action across skipped versions
- never publish generic notes such as only `Build 32.`

### Credentials

- `SUPublicEDKey` is public and may be committed
- never commit Sparkle private keys, Developer ID credentials, notarization profiles, or appcast signing secrets

### Publish Checklist

Complete every step before calling a release finished:

1. Update the version identifiers and `RELEASE_NOTES.md`.
2. Run `./scripts/swift-test.sh`.
3. Build the DMG and Sparkle appcast with `./scripts/build-release.sh`.
4. Run `./scripts/verify-release.sh`.
5. Commit and push the exact source and release metadata used for the build. Rebuild if any tracked release input changes afterward.
6. Create the GitHub release from that commit and upload `dist/updates/SimplePodcastManager-<SPMReleaseTag>.dmg`. The asset name must exactly match the appcast enclosure URL; the generic `dist/SimplePodcastManager.dmg` is not sufficient.
7. Keep only the current release in the appcast, publish it as `gh-pages:appcast.xml`, and preserve other `gh-pages` files.
8. Verify the live appcast advertises the new Sparkle version and exact release asset URL.
9. Make a HEAD request, or an equivalent check, and confirm the live enclosure URL resolves successfully.

### Website Publishing

- GitHub Pages serves from the `gh-pages` branch at repository root
- keep the canonical website source in `main` at `docs/index.html`
- when changing the website, copy `docs/index.html` to `gh-pages:index.html` and preserve existing `gh-pages` files such as `appcast.xml` and `.nojekyll`

## Testing Expectations

Use `swift run "Simple Podcast Manager"` for routine local development and UI checks. Test with a packaged local `.app` when behavior depends on the application bundle, including App Transport Security, Sparkle, `Info.plist`, bundled resources, code signing, or installer behavior:

```bash
SKIP_SPARKLE_APPCAST=1 ./scripts/build-release.sh
open -n "dist/build/Simple Podcast Manager.app"
```

Quit any other running copy first so the packaged local build is the instance under test.

### Manual Disk-Image Device Test

Use a disposable FAT disk image to manually test device detection, sync behavior, and device UI without a physical MP3 player. When handing off a device or sync change for manual verification, suggest this workflow to Steve.

Create and mount the test device:

```bash
SPM_TEST_IMAGE=/tmp/SimplePodcastManager-Safety-Test.dmg

hdiutil create \
  -size 512m \
  -fs MS-DOS \
  -volname SPMTEST \
  "$SPM_TEST_IMAGE"

hdiutil attach "$SPM_TEST_IMAGE"
mkdir -p /Volumes/SPMTEST/music
```

The mounted test device is available at `/Volumes/SPMTEST`, with its default podcast directory at `/Volumes/SPMTEST/music`.

After testing, quit the app, detach the test device, and remove the disposable image:

```bash
hdiutil detach /Volumes/SPMTEST
rm -f /tmp/SimplePodcastManager-Safety-Test.dmg
unset SPM_TEST_IMAGE
```

Never substitute a real device or another mounted volume into destructive test commands.

For every behavior change:

- test observable behavior rather than implementation details
- cover the successful path, relevant failure paths, and important boundaries
- add a regression test when fixing a bug
- keep tests deterministic and independent of real devices, network services, clocks, or user data
- use focused fakes and temporary directories instead of broad integration setup when possible
- place domain and service tests in `SimplePodcastManagerCoreTests`; use `SimplePodcastManagerUITests` for view-model and presentation behavior
- run `./scripts/swift-test.sh` before handing off code changes
- never weaken or remove a valid assertion merely to make a test pass

Prioritize coverage where mistakes carry the most risk:

- valid, invalid, and ambiguous device detection
- path validation before every device mutation
- user-visible sync plan parity with executed device actions
- complete-plan capacity math, including space recovered by selected deletions
- config writes touching only `[device root]/.spmconfig`
- app-managed copies and selected deletions touching only the configured device podcast directory
- explicit other-audio deletion requiring per-file selection and confirmation inside the configured device podcast directory
- failed-copy and incomplete-existing-file reporting
- eject only after successful sync

Prefer small, focused tests around planner and safety behavior before broader integration coverage.
