# SPP Live Export

A tiny macOS utility for turning DaVinci Resolve video exports into Apple Live Photos and AirDropping them to iPhone.

## What it does

- Watches a DaVinci Resolve export folder automatically
- Converts MOV, MP4, and M4V clips into Apple Live Photo pairs
- Preserves the original video stream with passthrough export whenever possible
- Groups generated Live Photos by date
- Supports per-day selection, select all, Shift range selection, and batch AirDrop
- Wraps each Live Photo pair as Apple's Private Live Photo Bundle (.pvt) before AirDrop
- Supports manual multi-file import as a fallback
- Does not require iCloud Photos
- Does not write generated media into the Mac Photos library
- Never moves, modifies, or deletes source videos

## Workflow

DaVinci Resolve
→ Watch Folder
→ SPP Live Export
→ HEIC + MOV Live Photo pair
→ Private Live Photo Bundle (.pvt)
→ AirDrop
→ iPhone Photos → Live Photo

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- iPhone with AirDrop enabled
- DaVinci Resolve is optional; manual import also works

## Build

The app is intentionally lightweight. It can be built directly with Swift:

    swiftc -parse-as-library Sources/main.swift \
      -o "SPP Live Export" \
      -framework SwiftUI \
      -framework AppKit \
      -framework Foundation \
      -framework ServiceManagement \
      -framework UniformTypeIdentifiers \
      -target arm64-apple-macosx13.0

The Live Photo exporter helper is built with Swift/AVFoundation and bundled in the app resources.

## Safety

Source media is treated as read-only.

SPP Live Export:
- reads source clips
- creates new output files
- creates temporary AirDrop bundles in its own cache directory
- automatically removes only its own AirDrop cache entries older than 24 hours

It does not delete, move, overwrite, or modify original footage.

## Privacy

No cloud service, analytics, account, or server is required. Conversion and packaging happen locally on the Mac.

## Status

Early public-ready build. The core DaVinci → Live Photo → AirDrop workflow is working on real devices, while the UI and packaging are still being refined.

## License

MIT

## One-command local build

Build the app:

    ./scripts/build.sh

Build the app and a local DMG:

    ./scripts/build.sh --dmg

The resulting artifacts are written to the dist directory.
