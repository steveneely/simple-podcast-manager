# Third-Party Notices

Simple Podcast Manager includes third-party software. These components are licensed separately from Simple Podcast Manager.

## FeedKit

FeedKit is used for RSS feed parsing.

- Project: https://github.com/nmdias/FeedKit
- License: MIT
- Copyright: Copyright (c) 2016 - 2025 Nuno Dias

## FFmpeg

Release builds may include an `ffmpeg` executable for audio conversion.

- Project: https://ffmpeg.org/
- License: FFmpeg is licensed under LGPL 2.1+ by default. Some builds can be GPL or non-redistributable depending on configuration.
- Source/build information: release artifacts that bundle FFmpeg must include an `FFMPEG_SOURCE.txt` file in the app resources with the exact source or build recipe URL used for that bundled executable.

Simple Podcast Manager runs FFmpeg as an external process and does not link FFmpeg libraries into the app.
