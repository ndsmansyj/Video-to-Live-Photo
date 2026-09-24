<p align="center">
  <img src="Assets/README/hero.svg" alt="Video to Live Turbo" width="100%">
</p>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

# Video to Live Turbo

A native macOS utility that **turns ordinary videos into iPhone Live Photos.**

**Video → Live Photo → iPhone**

Everything runs locally. No iCloud, Photos-library import, or server is required, and source videos are never moved, overwritten, modified, or deleted.

## Features

- Creates a ~3-second Live Photo by default, with duration adjustable up to the full source video
- Starts the key photo at the beginning of the selected range; dragging it beyond the range makes the range follow automatically
- Lets you keep or remove source-video audio before manual generation
- Supports MOV / MP4 / M4V, batch import, batch generation, and batch AirDrop
- Optionally auto-converts new videos from any chosen folder
- Organizes history by date with re-AirDrop, readjustment, and Finder reveal
- Exposes the conversion core through a CLI for Agents and scripts

> WeChat Moments supports 3-second Live Photos; the app defaults to 3 seconds.

<p align="center">
  <img src="Assets/README/workflow.svg" alt="Video to Live Turbo workflow" width="100%">
</p>

## Manual workflow

1. Open **Video to Live Turbo**.
2. Import one or more videos. They enter **Pending** first; no output is created yet.
3. Click a preview to adjust the clip, key photo, and duration, then choose whether to keep audio.
4. Click **Generate Live Photo** to create the paired HEIC + MOV output.
5. Select results under **Generated This Session** and AirDrop them to your iPhone.

## Auto-convert folder

Enable **Auto-convert new videos in folder** under Settings and choose a folder.

The app scans the folder on launch and continues watching it while running. It is not tied to any editor: use a camera-ingest folder, Downloads, or an export folder from DaVinci Resolve, Final Cut Pro, Premiere Pro, or another app.

## Agent / CLI

The conversion core can be called without the App UI, which makes it suitable for Agents, shell scripts, and local automation:

```bash
spp-live-export [--cover seconds] [--start seconds] [--duration seconds] [--mute] <video> [output_dir]
```

The CLI controls the conversion core. App UI state such as Pending and History does not currently expose a separate HTTP API.

## Install

Download the latest:

**Video to Live Turbo 1.0.0.dmg**

Version 1.0.0 is ad-hoc signed and is not notarized with an Apple Developer ID. On first launch, macOS may require:

**System Settings → Privacy & Security → Open Anyway**

Requirements:

- Apple Silicon Mac
- macOS 13 or later

Build from source:

```bash
./scripts/build.sh
./scripts/build.sh --dmg
```

Artifacts are written to `dist/`.

## Source-media safety

Video to Live Turbo follows a non-destructive media workflow. It may read source videos and create new HEIC / MOV outputs, processing markers, and temporary AirDrop bundles, but it does not delete, move, overwrite, or modify source videos.

Automatic cleanup is limited to failed partial outputs and the app's own AirDrop cache.

## Compatibility

Live Photo preservation over AirDrop currently relies on macOS recognizing the `.pvt` package as `com.apple.private.live-photo-bundle`.

The current Mac + iPhone workflow has been verified end to end: received items play normally as Live Photos on iPhone. This package type is a private Apple implementation and may change in a future OS release.

`ffprobe` is optional. If available at `/usr/local/bin/ffprobe` or `/opt/homebrew/bin/ffprobe`, the app displays richer codec, resolution, and frame-rate details.

## License

MIT
