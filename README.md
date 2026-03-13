# yt-downloader

A command-line YouTube channel manager and downloader powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp).

Store dozens of channel URLs in a TOML config file, then run a single command to pull every new video since your last download — no manual date-tracking required.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [One-line online install (curl | bash)](#one-line-online-install)
  - [Local install from this repo](#local-install-from-this-repo)
  - [Manual install](#manual-install)
- [Configuration file](#configuration-file)
- [Usage](#usage)
  - [Add a channel](#add-a-channel)
  - [List channels](#list-channels)
  - [Download all channels](#download-all-channels)
  - [Download a single channel](#download-a-single-channel)
  - [Remove a channel](#remove-a-channel)
- [XDG directory layout](#xdg-directory-layout)
- [Dependencies reference](#dependencies-reference)
- [Updating](#updating)

---

## Features

- **Channel config** — every channel lives as a named entry in `~/.config/yt-downloader/yt-downloader.toml`
- **Dated downloads** — automatically passes `--dateafter` to yt-dlp so only new videos are fetched on each run; `last_download_utc` is updated on success
- **Per-channel cookie source** — optionally specify `--cookies-from-browser` per channel for age-restricted or members-only content
- **Per-channel output directory** — defaults to `~/Downloads/youTube/<ChannelName>/`
- **Interactive remove** — arrow-key (curses) or numbered-list picklist for removing channels
- **XDG compliant** — config, data, and cache all live under the XDG base directories
- **Full yt-dlp dependency stack** — installers set up ffmpeg, deno (JS runtime for YouTube), aria2, AtomicParsley, curl-cffi, and more

---

## Requirements

| Tool | Purpose |
| --- | --- |
| Python 3.10+ | Runtime (3.11+ preferred; 3.10 works with `pip install tomli`) |
| yt-dlp | The actual downloader |
| ffmpeg + ffprobe | Merge separate video/audio streams, post-processing |
| deno | JavaScript runtime for yt-dlp-ejs — required for full YouTube support |
| aria2 | Optional: faster multi-connection downloads |
| AtomicParsley | Optional: thumbnail embedding for mp4/m4a |
| curl-cffi (pip) | Optional: TLS browser impersonation for fingerprint-protected sites |

All of the above are installed automatically by either installer script.

---

## Installation

### One-line online install

> **Before this works** the repository must be on GitHub. Edit the three variables at the top of `install-online.sh` — `GITHUB_USER`, `GITHUB_REPO`, `GITHUB_BRANCH` — to match your repo, then push.

```bash
curl -fsSL https://raw.githubusercontent.com/VirtuallyScott/yt_downloader/main/install-online.sh | bash
```

This will:

1. Install [Homebrew](https://brew.sh) if it is not already present
2. Install all yt-dlp dependencies via `brew` and `pip`
3. Download `yt-downloader.py` from the repo's raw GitHub URL
4. Create the XDG directory tree and write a starter config
5. Install the script to `~/.local/bin/yt-downloader`
6. Patch your shell profile to add `~/.local/bin` to `$PATH` if needed

### Local install from this repo

Clone (or download) this repository, then:

```bash
bash install-yt-downloader.sh
```

Restart your shell (or `source ~/.zshrc`) afterwards.

### Manual install

```bash
# 1. Install dependencies
brew install yt-dlp ffmpeg deno aria2 atomicparsley
pip install --user "yt-dlp[default,curl-cffi]" xattr   # Python < 3.11: also add tomli

# 2. Create XDG directories
mkdir -p ~/.local/bin \
         ~/.config/yt-downloader \
         ~/.local/share/yt-downloader \
         ~/.cache/yt-downloader

# 3. Install the script
install -m 755 yt-downloader.py ~/.local/bin/yt-downloader

# 4. Add ~/.local/bin to PATH (if not already there)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## Configuration file

**Location:** `~/.config/yt-downloader/yt-downloader.toml`

You should never need to edit this by hand — the `--add-channel` and `--remove-channel` commands manage it for you — but the format is straightforward if you want to:

```toml
[channels.CleetusM]
url                  = "https://www.youtube.com/@CleetusM"
download_location    = "~/Downloads/youTube/CleetusM"
dated_downloads      = true
cookies_from_browser = "chrome"
last_download_utc    = "2026-03-01T12:00:00+00:00"

[channels.SomePlaylist]
url               = "https://www.youtube.com/playlist?list=PLxxxxxxxxx"
download_location = "~/Downloads/youTube/SomePlaylist"
dated_downloads   = false
```

### Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `url` | string | **required** | Any URL yt-dlp supports (channel, playlist, video) |
| `download_location` | string | `~/Downloads/youTube/<name>` | Output directory; `~` is expanded |
| `dated_downloads` | bool | `true` | When `true`, pass `--dateafter <last_download_utc>` so only new videos are fetched |
| `cookies_from_browser` | string | *(none)* | Browser to source cookies from: `chrome`, `firefox`, `safari`, `edge`, `brave`, … |
| `last_download_utc` | string | *(none)* | ISO-8601 UTC timestamp written automatically after each successful run; delete to re-download everything |

---

## Usage

### Add a channel

```bash
# Basic — dated downloads on by default
yt-downloader --add-channel "https://www.youtube.com/@CleetusM"

# Explicitly enable dated downloads and use browser cookies
yt-downloader --add-channel "https://www.youtube.com/@CleetusM" \
              --DatedDownloads yes \
              --cookies-from-browser chrome

# Custom output directory
yt-downloader --add-channel "https://www.youtube.com/@CleetusM" \
              --download-location "/Volumes/Media/YouTube/CleetusM"

# Disable dated downloads (always sync full channel)
yt-downloader --add-channel "https://www.youtube.com/@CleetusM" \
              --DatedDownloads no
```

`--DatedDownloads` also accepts `--dated-downloads` (lowercase).

### List channels

```bash
yt-downloader --list-channels
```

Example output:

```text
Channels (2)  —  config: /Users/scott/.config/yt-downloader/yt-downloader.toml

  CleetusM
    url              : https://www.youtube.com/@CleetusM
    download_location: /Users/scott/Downloads/youTube/CleetusM
    dated_downloads  : True
    cookies_from     : chrome
    last_download    : 2026-03-01T12:00:00+00:00

  SomePlaylist
    url              : https://www.youtube.com/playlist?list=PLxxxxxxxxx
    download_location: /Users/scott/Downloads/youTube/SomePlaylist
    dated_downloads  : False
```

### Download all channels

```bash
yt-downloader --download-all
```

For each channel this runs a command equivalent to:

```bash
yt-dlp -f "bv*+ba/b" \
       --merge-output-format mkv \
       --no-overwrites \
       -o "~/Downloads/youTube/CleetusM/%(title)s.%(ext)s" \
       --cookies-from-browser chrome \
       --dateafter 20260301 \
       "https://www.youtube.com/@CleetusM"
```

`last_download_utc` is updated in the config on a successful (exit code 0) run. If yt-dlp exits with an error the timestamp is **not** updated so the next run retries from the same date.

### Download a single channel

```bash
yt-downloader --download-channel CleetusM
```

### Remove a channel

```bash
yt-downloader --remove-channel
```

Opens an arrow-key navigable picker (falls back to a numbered list in non-interactive terminals). Asks for confirmation before deleting.

---

## XDG directory layout

```text
~/.local/bin/yt-downloader                          ← executable script
~/.config/yt-downloader/yt-downloader.toml          ← channel config (live)
~/.local/share/yt-downloader/                       ← data directory (reserved)
~/.cache/yt-downloader/                             ← cache directory (reserved)
```

Override any base directory with the standard XDG environment variables:

```bash
XDG_CONFIG_HOME=/custom/config yt-downloader --list-channels
```

---

## Dependencies reference

| Package | Source | Purpose |
| --- | --- | --- |
| `yt-dlp` | `brew install yt-dlp` | Core downloader |
| `ffmpeg` | `brew install ffmpeg` | Merge video+audio streams, all post-processing |
| `ffprobe` | bundled with ffmpeg | Format inspection |
| `deno` | `brew install deno` | JS runtime for **yt-dlp-ejs** — replaces PhantomJS; required for full YouTube support |
| `aria2` | `brew install aria2` | Faster multi-connection downloads (`--downloader aria2c`) |
| `AtomicParsley` | `brew install atomicparsley` | Thumbnail embedding into mp4/m4a when ffmpeg/mutagen cannot |
| `yt-dlp[default]` | `pip install` | Bundles: certifi, brotli, websockets, requests, mutagen, pycryptodomex |
| `curl-cffi` | `pip install` | TLS browser fingerprint impersonation (Chrome/Edge/Safari) for sites that block bots |
| `xattr` | `pip install` | Write XDG/Dublin Core metadata to file extended attributes (`--xattrs`) |
| `tomli` | `pip install` | TOML parser — only needed on Python < 3.11 |

---

## Updating

**Update yt-dlp:**

```bash
brew upgrade yt-dlp
# or
yt-dlp -U
```

**Update yt-downloader itself:**

```bash
# Local repo
git pull && bash install-yt-downloader.sh

# Or re-run the online installer
  curl -fsSL https://raw.githubusercontent.com/VirtuallyScott/yt_downloader/main/install-online.sh | bash
```

**Update all Homebrew packages at once:**

```bash
brew upgrade yt-dlp ffmpeg deno aria2 atomicparsley
```
