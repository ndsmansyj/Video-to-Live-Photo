<p align="center">
  <img src="Assets/README/hero.svg" alt="Video to Live Photo" width="100%">
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

# Video to Live Photo

A small native macOS utility for turning DaVinci Resolve video exports into Apple Live Photos and AirDropping them to iPhone.

**Local-only.** No iCloud required. No Photos-library import. No server.

## Why

A normal AirDrop of a matching HEIC + MOV arrives on iPhone as two separate files.

SPP Live Export generates a valid Live Photo pair, wraps it as a macOS-recognized Live Photo bundle, and hands that bundle to AirDrop so the iPhone receives a real Live Photo.

<p align="center">
  <img src="Assets/README/workflow.svg" alt="SPP Live Export workflow" width="100%">
</p>

## Features

- Automatic watch folder for DaVinci Resolve exports
- Manual multi-file import
- MOV / MP4 / M4V → Apple Live Photo
- Passthrough video export whenever possible
- Portrait-first thumbnail gallery
- Date grouping and per-day selection
- Select all and Shift range selection
- Batch AirDrop
- Processing history and Finder reveal
- Configurable input / output folders
- Launch at login
- Compact / standard / large thumbnail modes
- Optional codec / resolution / frame-rate metadata
- No Mac Photos-library dependency
- Source footage is never moved, overwritten, modified, or deleted

## Install

### Download

Open the repository Releases page and download the latest DMG.

The current public build is ad-hoc signed, not notarized with an Apple Developer ID. macOS may show an unidentified-developer warning. If that happens, use **System Settings → Privacy & Security → Open Anyway**, or build from source.

### Build from source

Requirements:

- Apple Silicon Mac
- macOS 13 or later
- Apple Command Line Tools / Swift

Build the app:

```bash
./scripts/build.sh
```

Build the app and a local DMG:

```bash
./scripts/build.sh --dmg
```

Artifacts are written to `dist/`.

## Usage

1. Open **SPP Live Export** (the app name in the current v0.4.0 binary).
2. Point DaVinci Resolve at the configured watch folder, or click **Import Video**.
3. Wait for the Live Photos to appear.
4. Select individual items, a whole date, a Shift range, or all visible items.
5. Click **AirDrop** and choose your iPhone.

The iPhone receives each selected item as a Live Photo.

## Optional metadata

`ffprobe` is optional. If available at `/usr/local/bin/ffprobe` or `/opt/homebrew/bin/ffprobe`, the app shows richer codec / resolution / frame-rate metadata.

Conversion itself does not depend on FFmpeg.

## Project layout

- `Sources/App.swift` — app entry point and page routing
- `Sources/LiveLibrary.swift` — watcher, conversion orchestration, AirDrop packaging, settings
- `Sources/Components.swift` — reusable UI and thumbnail cache
- `Sources/RecentView.swift` — date-grouped gallery and batch selection
- `Sources/HistoryView.swift` — generated-item history
- `Sources/SettingsView.swift` — app settings
- `HelperSources/SPPLiveExport/main.swift` — Live Photo pair generator
- `Assets/Brand/` — app icon source
- `Assets/README/` — project artwork

## Safety

Source media is treated as read-only.

SPP Live Export may create:
- HEIC + MOV outputs
- its own processing markers
- temporary AirDrop bundles in its cache directory

It may remove only:
- its own failed partial exports
- its own AirDrop cache older than 24 hours

It does **not** delete, move, overwrite, or modify original footage.

## Compatibility note

AirDrop preservation currently relies on macOS recognizing the `.pvt` package as `com.apple.private.live-photo-bundle`.

This works in the tested macOS + iPhone workflow, but it is a private Apple bundle type and could change in a future OS release.

## License

MIT
