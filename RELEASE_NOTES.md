# Simple Podcast Manager v1.1.4

- Checks multiple podcast feeds at the same time, making startup and full-library refreshes faster while retaining feed-cache and not-modified optimizations.
- Inventories a connected player once per refresh or plan instead of repeatedly scanning it for every podcast.
- Keeps the interface responsive while inspecting slower external players and building the Sync plan.
- Avoids unnecessary feed and device refresh work after a successful Sync.
- Includes internal interface cleanup that preserves the existing workflow while making future changes easier to maintain.
