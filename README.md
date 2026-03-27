# yt-dlp GUI

A native macOS GUI for `yt-dlp`, built in Swift with SwiftUI.

This app is meant to feel like a real Mac utility instead of a thin wrapper around a Terminal command. It supports:

- video and audio downloads powered by `yt-dlp`
- Spotify music downloads powered by `spotDL`
- a local media library rooted in `~/Movies/ytdlp-gui`
- thumbnails, Quick Look, queue/history, and native macOS controls

## Status

This project is currently aimed at personal use / direct distribution on macOS. It is not designed for the Mac App Store.

## Features

- Native macOS app written in Swift
- Download modes for:
  - `Video`
  - `Audio`
  - `Spotify Music`
- Guided toolchain setup for `yt-dlp`, `ffmpeg`, and `spotDL`
- Download queue with progress updates and recent history
- Saved media browser with:
  - list and gallery views
  - Quick Look support
  - thumbnails and music artwork where available
  - metadata display for music files
- Advanced options for playlists, cookies, and format controls

## Requirements

- macOS 14 or newer
- Xcode 16+ recommended
- Swift 6.1 toolchain
- Homebrew

Runtime tools:

- `yt-dlp`
- `ffmpeg`
- `spotDL` for Spotify mode only

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/siasl/ytdlp-gui.git
cd ytdlp-gui
```

### 2. Install the download tools

Install the core tools:

```bash
brew install yt-dlp ffmpeg
```

Install Spotify support:

```bash
brew install pipx
pipx install spotdl
pipx inject spotdl setuptools
```

Why the extra `setuptools` step?

Some `spotDL` environments fail with:

```text
ModuleNotFoundError: No module named 'pkg_resources'
```

Injecting `setuptools` fixes that for the pipx-managed install.

### 3. Open the project

You can run the app in either of these ways.

In Xcode:

```bash
open YTDLPGUI.xcodeproj
```

Then:

- select the `YTDLPGUI` scheme
- press `Cmd-R` to run

Or with SwiftPM:

```bash
swift run YTDLPGUI
```

## First Run

On first launch:

- the app creates `~/Movies/ytdlp-gui` if it does not already exist
- the library view scans that folder for downloaded media
- Spotify downloads default to `~/Movies/ytdlp-gui/Music`

If a tool is missing or unhealthy, open Settings in the app to inspect the toolchain and follow the suggested repair/setup command.

## Running Tests

Swift package tests:

```bash
swift test
```

Build the Xcode project for testing:

```bash
xcodebuild -project YTDLPGUI.xcodeproj -scheme YTDLPGUI -destination 'platform=macOS' -derivedDataPath .build/XcodeDerivedData build-for-testing
```

In Xcode:

- `Cmd-U` runs tests

## Project Structure

```text
Sources/YTDLPGUI/
  Models/        app and library models
  Services/      download engines, toolchain, library, Quick Look, persistence
  ViewModels/    app state and orchestration
  Views/         SwiftUI UI
Tests/
  YTDLPGUITests/     unit/integration-style tests
  YTDLPGUIUITests/   UI automation
```

## Toolchain Notes

### yt-dlp and ffmpeg

The app can install missing `yt-dlp` and `ffmpeg` through Homebrew from Settings.

### spotDL

`spotDL` is intentionally treated as a guided manual setup rather than a fully automatic in-app install. That keeps the app from trying to manage Python packaging edge cases on your machine.

If Spotify downloads are not working:

1. open Settings
2. check the `spotDL` status
3. if the app says `spotDL` needs repair, run the suggested Terminal command
4. click `Re-check Tools`

## Usage Notes

- Some downloads require authentication or cookies depending on the source site.
- Quick Look and thumbnails depend on macOS support for the downloaded file format.
- Music metadata and artwork display only work when the downloaded file actually contains embedded metadata.

## Legal / Terms

Make sure you comply with the terms of service, copyright restrictions, and applicable laws for the sites and media you download.

## License

No license has been added yet. Until one is added, all rights are reserved by default.
