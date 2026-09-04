# Third-Party Notices

Simple Podcast Manager includes third-party software. These components are licensed separately from Simple Podcast Manager.

## FeedKit

FeedKit is used for RSS feed parsing.

- Project: https://github.com/nmdias/FeedKit
- License: MIT
- Copyright: Copyright (c) 2016 - 2025 Nuno Dias

## Sparkle

Sparkle is used for in-app updates in installed macOS builds.

- Project: https://sparkle-project.org/
- Source: https://github.com/sparkle-project/Sparkle
- License: MIT

## GRDB

GRDB provides the Swift interface to the SQLite library included with macOS.

- Project: https://github.com/groue/GRDB.swift
- License: MIT
- Copyright: Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## FFmpeg

Release builds may include an `ffmpeg` executable for audio conversion.

- Project: https://ffmpeg.org/
- License: FFmpeg is licensed under LGPL 2.1+ by default. Some builds can be GPL or non-redistributable depending on configuration.
- Source/build information: release artifacts that bundle FFmpeg must include an `FFMPEG_SOURCE.txt` file in the app resources with the exact source or build recipe URL used for that bundled executable.

Simple Podcast Manager runs FFmpeg as an external process and does not link FFmpeg libraries into the app.
