# Simple Podcast Manager v1.20.0

- Downloads start as soon as a slot is available, with consistent progress and cancellation across manual and automatic downloads.
- Sync failures now show completed work and preserve accurate removal history. Successful sync cleanup keeps local downloads outside the reviewed plan.
- Audio conversion handles large command output without stalling and stops the conversion process when cancelled.
- App data restore waits for active refreshes, downloads, and sync to finish, and reports any problems reloading restored data.
