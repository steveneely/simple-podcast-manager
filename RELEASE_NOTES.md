# Simple Podcast Manager v1.4.0

- Shows the size of every MP3 being copied or deleted in the sync plan, plus total copied and deleted sizes when the sync finishes.
- Checks whether the complete selection fits before changing the device. Available-space messages now compare the full sync size with usable device space, including space recovered by selected deletions.
- Runs selected deletions before copies, keeping sync behavior predictable and making room before new episodes are transferred.
- Keeps capacity errors in the sync dialog, clears stale plans while recalculating, and prevents a sync from starting when the plan cannot fit.
- Uses generic MP3-player wording instead of assuming the connected device is a Walkman.
- Adds and edits RSS subscriptions with one feed request, reducing duplicate network work.
- Cleans up failed downloads and conversion intermediates from the app's local media workspace.
- Writes episode and podcast names from the RSS feed into every prepared MP3, replacing missing, stale, or placeholder publisher metadata on offline players.
- Uses one consistent metadata and artwork preparation path for original and converted MP3 files.
- Reports failed copies clearly, including when a partial file may remain on the device, and flags same-name files whose size suggests an interrupted earlier copy.
- Adds an Appearance setting with System, Light, and Dark modes. Changes preview immediately, and the chosen mode is remembered after saving.
- Automatic update checks now show the available update window during the same app launch, while staying quiet when you already have the latest version.
- New installs now show an Add Podcast button immediately, so you can subscribe to your first RSS feed without needing the Shows sidebar first.
- Clarifies the onboarding guidance for adding your first podcast and subsequent shows.
