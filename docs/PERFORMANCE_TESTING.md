# Performance Testing

Performance work is measured at two levels: deterministic persisted-state benchmarks and packaged-app launch milestones.

## SQLite Store Performance and Scale

Run the opt-in SQLite store tests on an otherwise idle Mac:

```bash
SPM_RUN_PERFORMANCE_TESTS=1 ./scripts/swift-test.sh --filter SQLiteEpisodeStorePerformanceTests
```

`testUnifiedStartupSnapshotRead` reports the wall-clock average for reading 2,000 prepared, downloaded, and removed records in one startup snapshot. Run the command three times and use the median result.

The same opt-in run also checks two realistic large-state round trips without slowing routine development:

- automatic-download state containing 40 podcasts and 16,000 observed episode IDs
- download history containing 20,000 records followed by a one-record merge

The normal test suite explicitly reports these tests as skipped unless `SPM_RUN_PERFORMANCE_TESTS=1` is set.

## Packaged-App Startup Milestones

Build the same packaged app used for manual device testing:

```bash
SKIP_SPARKLE_APPCAST=1 ./scripts/build-release.sh
```

In one Terminal window, stream the app's startup milestone log:

```bash
log stream --style compact --predicate 'subsystem == "com.steveneely.simple-podcast-manager" AND category == "StartupPerformance"'
```

Quit every running copy, then launch the packaged app from another Terminal window:

```bash
open -n "dist/build/Simple Podcast Manager.app"
```

Record these elapsed times:

- configuration loaded
- cached episodes visible
- persisted episode state ready
- devices discovered
- network feeds refreshed
- background startup work complete

Measure at least five fresh-process launches and compare medians. Keep the same subscriptions, network, mounted volumes, and app data for before/after comparisons. Treat network refresh completion separately from interactive/cache-visible time because internet latency is not controlled by the app.

For deeper diagnosis, record the packaged app with Instruments using the App Launch, Time Profiler, SwiftUI, and File Activity templates. Check that the main thread is not performing mounted-volume discovery, recursive device inventory, SQLite reads, or feed-cache file reads.

## Manual Disk-Image Device Test

Use only the disposable FAT image described in `AGENTS.md`. With the image mounted, verify that the window remains responsive while the device is detected and inventoried, cached episodes appear without waiting for device work, and device status eventually changes to `Ready: SPMTEST`.
