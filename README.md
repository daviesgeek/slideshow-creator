# slideshow-creator

I was tasked by a family member to build a slideshow and, as one typically does, I decided to vibe code a macOS app instead, built on top of FFmpeg.

This is a small SwiftUI macOS app for turning a folder of photos, an optional folder of soundtrack files, and some lightweight per-photo decisions into an MP4 slideshow.

It is not trying to be Final Cut Pro. It is closer to: "I have a pile of family photos, I need to sort them, skip a few, maybe tag some subsets, add music, and get a video out the other side without hand-writing a giant FFmpeg command."

## What it does

- Loads photos from a folder.
- Loads soundtrack files from a separate folder.
- Lets you reorder photos and soundtracks by dragging.
- Shows photos in either list or grid view.
- Opens a fullscreen preview for quickly reviewing images.
- Lets you exclude photos from the final export.
- Lets you create flags, tag photos, and export only photos matching selected flags.
- Supports `Any` / `All` matching for flag-based exports.
- Supports per-photo timing overrides.
- Supports default and per-photo transition overrides using FFmpeg `xfade` transitions.
- Saves and opens `.slideshowproject` files.
- Tracks missing photos and lets you relink them.
- Encodes to MP4 with an FFmpeg progress window, log output, elapsed time, rough remaining time, and cancellation.

## Supported media

Image formats currently scanned from the photo folder:

- `jpg`
- `jpeg`
- `png`
- `webp`
- `heic`
- `heif`
- `tif`
- `tiff`

Audio formats currently scanned from the soundtrack folder:

- `mp3`
- `m4a`
- `aac`
- `wav`
- `aif`
- `aiff`
- `caf`
- `flac`

## Requirements

- macOS
- Xcode
- FFmpeg

The Xcode project currently has its macOS deployment target set to `26.1`.

FFmpeg is expected to exist somewhere the app can launch it. The default path is:

```sh
/opt/homebrew/bin/ffmpeg
```

The app also checks a few other places, including `/usr/local/bin/ffmpeg`, `~/.homebrew/bin/ffmpeg`, a bundled app executable named `ffmpeg` if one is ever added, and entries from `PATH`.

If you use Homebrew, the usual install is:

```sh
brew install ffmpeg
```

## Running it

Open the project in Xcode:

```sh
open slideshow-creator.xcodeproj
```

Then run the `slideshow-creator` scheme.

Once the app is open, use `Validate FFmpeg` to make sure it can find and launch FFmpeg. You can also edit the FFmpeg path directly in the app.

## Basic workflow

1. Click `Choose Photos Folder`.
2. Optionally click `Choose Soundtrack Folder`.
3. Set the global slideshow defaults: seconds per photo, default transition, transition duration, encode mode, width, height, and FPS.
4. Reorder photos as needed.
5. Exclude photos you do not want in the export.
6. Optionally create flags and tag photos if you only want to export a subset.
7. Optionally override timing or transitions on specific photos.
8. Save the project if you want to come back to it later.
9. Click `Encode...` and choose an MP4 output path.

## Project files

Projects are saved as `.slideshowproject` files.

They are JSON-backed documents that store things like:

- Photo folder and soundtrack folder references.
- Photo and soundtrack ordering.
- Export settings.
- Available flags and selected export flags.
- Excluded photos.
- Per-photo flags.
- Missing/relinked photo information.
- Per-photo timing overrides.
- Per-photo transition overrides.

The app also stores the FFmpeg path globally in user defaults, not in each new project file. There is still legacy loading support for older project files that had an FFmpeg path inside their settings.

## Encoding notes

The actual video work is delegated to FFmpeg.

At a high level, the app builds an FFmpeg command that:

- Loops each still image for its resolved duration.
- Scales and pads images to the target output size.
- Normalizes video to `yuv420p`.
- Applies FFmpeg `xfade` transitions where configured.
- Concatenates hard-cut groups where no transition is configured.
- Concatenates soundtrack files, if present.
- Trims audio to the slideshow duration.
- Outputs H.264 MP4 with `+faststart`.

Encode modes currently map to:

- `Fastest (Hardware)`: `h264_videotoolbox`
- `Fast (Software)`: `libx264` with `ultrafast` / `crf 28`
- `Quality (Slower)`: `libx264` with `medium` / `crf 20`

If hardware encoding fails because `h264_videotoolbox` is unavailable, the app attempts to fall back to the fast software encoder.

## Tests

There are Swift tests for transition planning in `slideshow-creatorTests`.

The current UI test target is still mostly the default Xcode launch/performance template.

From Xcode, run the test suite with `Product > Test`.

From the command line, this should be the general shape:

```sh
xcodebuild test -scheme slideshow-creator -project slideshow-creator.xcodeproj
```

Depending on your local Xcode/macOS setup, you may need to add an explicit destination.

## Current caveats

- This is a personal utility app that happens to be public, not a polished App Store release.
- FFmpeg is required and is not currently bundled in this repo.
- The app is macOS-only.
- The Xcode project still contains the starter SwiftData `Item` model from the template.
- The generated project has user-specific Xcode metadata checked in.
- UI tests are minimal at the moment.

## Why this exists

Because sometimes the shortest path to making a slideshow is not to make a slideshow.

Sometimes it is to build a whole small app around FFmpeg so you can review, sort, tag, filter, and encode the slideshow with fewer repeated manual steps.

That is probably overkill. It also works.
