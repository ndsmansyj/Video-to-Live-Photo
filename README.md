# SPP Live Export

A small native macOS utility for turning DaVinci Resolve video exports into Apple Live Photos and AirDropping them to iPhone.

## Features

- Watches a DaVinci Resolve export folder automatically
- Supports manual multi-file import
- Converts MOV / MP4 / M4V into Apple Live Photo pairs
- Preserves the original video stream with passthrough export whenever possible
- Shows portrait-first thumbnails grouped by date
- Supports per-day selection, select all, Shift range selection, and batch AirDrop
- Wraps each pair as a system-recognized Private Live Photo Bundle (.pvt) before AirDrop
- Includes processing history, Finder reveal, custom input/output folders, login launch, and thumbnail-size settings
- Does not require iCloud Photos
- Does not write generated media into the Mac Photos library
- Never moves, modifies, overwrites, or deletes source videos

## Workflow

DaVinci Resolve / manual import
→ SPP Live Export
→ HEIC + MOV Live Photo pair
→ Private Live Photo Bundle (.pvt)
→ AirDrop
→ iPhone Photos → Live Photo

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- iPhone with AirDrop enabled
- DaVinci Resolve is optional

ffprobe is optional. If it is available at /usr/local/bin/ffprobe or /opt/homebrew/bin/ffprobe, the app shows richer codec / resolution / frame-rate metadata. Conversion itself does not depend on FFmpeg.

## Build

Build the app:

    ./scripts/build.sh

Build the app and a local DMG:

    ./scripts/build.sh --dmg

Artifacts are written to dist/.

The project intentionally stays lightweight and uses native Swift / SwiftUI / AVFoundation instead of a large dependency stack.

## Source layout

- Sources/App.swift — app entry point and page routing
- Sources/LiveLibrary.swift — watcher, conversion orchestration, AirDrop packaging, settings
- Sources/Components.swift — reusable UI and thumbnail cache
- Sources/RecentView.swift — date-grouped gallery and batch selection
- Sources/HistoryView.swift — generated-item history
- Sources/SettingsView.swift — app settings
- HelperSources/SPPLiveExport/main.swift — Live Photo pair generator
- Assets/IconConcepts/ — SVG icon concepts

## Safety

Source media is treated as read-only.

SPP Live Export may:
- read source clips
- create new output files
- create temporary AirDrop bundles in its own cache directory
- remove only its own failed/temporary generated files and AirDrop cache

It does not delete, move, overwrite, or modify original footage.

## Privacy

No cloud service, analytics, account, or server is required. Conversion and packaging happen locally on the Mac.

## Compatibility note

AirDrop preservation of Live Photo behavior currently relies on macOS recognizing the .pvt package as com.apple.private.live-photo-bundle. This works in the tested macOS/iPhone workflow, but it is a private Apple bundle type and could change in a future OS release.

A locally built or ad-hoc signed DMG is not notarized. Public binary releases may trigger Gatekeeper until the project uses a Developer ID and notarization; building from source avoids that distribution issue.

## Status

0.4.0 — core DaVinci → Live Photo → AirDrop workflow is working on real devices. UI and packaging are still being refined.

## License

MIT
