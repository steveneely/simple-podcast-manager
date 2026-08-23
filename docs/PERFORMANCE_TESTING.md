# Performance Testing

Performance work is measured at two levels: deterministic persisted-state benchmarks and packaged-app launch milestones.

## Persisted-State Benchmark

Run the two startup-state read benchmarks on an otherwise idle Mac:

```bash
SPM_RUN_PERFORMANCE_TESTS=1 ./scripts/swift-test.sh --filter StartupStateReadPerformanceTests
```

Compare the reported wall-clock averages for `testUnifiedStartupSnapshotRead` and `testPreviousSeparateStartupReads`. Run the command three times and use the median result from each test. These benchmarks use 2,000 prepared, downloaded, and removed records.

Measure repeated episode-list lookup with 50 feeds and 5,000 cached episodes:

```bash
SPM_RUN_PERFORMANCE_TESTS=1 ./scripts/swift-test.sh --filter indexedEpisodeLookupPerformanceComparison
```

The test prints the previous repeated-filter duration and the indexed lookup duration while verifying that both paths return identical counts.

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
