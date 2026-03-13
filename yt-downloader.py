#!/usr/bin/env python3
"""yt-downloader — YouTube channel downloader using yt-dlp.

Configuration lives at:
  $XDG_CONFIG_HOME/yt-downloader/yt-downloader.toml
  (default: ~/.config/yt-downloader/yt-downloader.toml)

Usage examples:
  yt-downloader --add-channel "https://www.youtube.com/@CleetusM" --DatedDownloads yes
  yt-downloader --add-channel "https://www.youtube.com/@Chan" --cookies-from-browser chrome
  yt-downloader --download-all
  yt-downloader --download-channel CleetusM
  yt-downloader --list-channels
  yt-downloader --remove-channel
"""

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# TOML support — stdlib tomllib (Python 3.11+) or tomli from PyPI
# ---------------------------------------------------------------------------
try:
    import tomllib  # type: ignore[import]
except ModuleNotFoundError:
    try:
        import tomli as tomllib  # type: ignore[import,no-redef]
    except ModuleNotFoundError:
        sys.exit(
            "yt-downloader requires Python 3.11+ or the 'tomli' package.\n"
            "Install with: pip install tomli"
        )

# ---------------------------------------------------------------------------
# XDG paths
# ---------------------------------------------------------------------------
_XDG_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CONFIG_DIR = _XDG_CONFIG_HOME / "yt-downloader"
CONFIG_FILE = CONFIG_DIR / "yt-downloader.toml"

_TOML_HEADER = """\
# yt-downloader configuration
# Managed by yt-downloader — manual edits are welcome.
#
# Add a channel   : yt-downloader --add-channel URL
# Remove a channel: yt-downloader --remove-channel
# Download all    : yt-downloader --download-all
#
# Fields per channel:
#   url                  - YouTube channel / playlist URL  (required)
#   download_location    - Output directory               (default: ~/Downloads/youTube/NAME)
#   dated_downloads      - Only fetch videos newer than last_download_utc  (default: true)
#   cookies_from_browser - Browser cookie source: chrome, firefox, safari … (optional)
#   last_download_utc    - ISO-8601 UTC timestamp; updated automatically    (optional)
"""


# ---------------------------------------------------------------------------
# TOML serialisation helpers
# ---------------------------------------------------------------------------

def _toml_safe_key(name: str) -> str:
    """Return a TOML dotted-key segment, quoted when the name is not a bare key."""
    if re.fullmatch(r"[A-Za-z0-9_-]+", name):
        return name
    escaped = name.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _toml_str(value: str) -> str:
    """Return a TOML basic-string literal."""
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _config_to_toml(config: dict) -> str:
    lines = [_TOML_HEADER]
    for name, ch in config.get("channels", {}).items():
        key = _toml_safe_key(name)
        lines.append(f"[channels.{key}]")
        lines.append(f"url = {_toml_str(ch['url'])}")
        lines.append(f"download_location = {_toml_str(ch['download_location'])}")
        lines.append(f"dated_downloads = {str(ch.get('dated_downloads', True)).lower()}")
        if ch.get("cookies_from_browser"):
            lines.append(f"cookies_from_browser = {_toml_str(ch['cookies_from_browser'])}")
        if ch.get("last_download_utc"):
            lines.append(f"last_download_utc = {_toml_str(ch['last_download_utc'])}")
        lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Config I/O
# ---------------------------------------------------------------------------

def load_config() -> dict:
    if not CONFIG_FILE.exists():
        return {"channels": {}}
    with open(CONFIG_FILE, "rb") as fh:
        data = tomllib.load(fh)
    data.setdefault("channels", {})
    return data


def save_config(config: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(_config_to_toml(config), encoding="utf-8")


# ---------------------------------------------------------------------------
# Channel name extraction
# ---------------------------------------------------------------------------

def _channel_name_from_url(url: str) -> str:
    """Derive a filesystem-safe channel name from a YouTube URL."""
    for pattern in (r"/@([^/?#]+)", r"/c/([^/?#]+)", r"/user/([^/?#]+)"):
        m = re.search(pattern, url)
        if m:
            return m.group(1)
    # Fallback: last non-empty path segment before any query string
    path = url.rstrip("/").split("/")[-1].split("?")[0]
    return path or "unknown_channel"


# ---------------------------------------------------------------------------
# Interactive picklist
# ---------------------------------------------------------------------------

def _curses_pick(items: list, prompt: str) -> "str | None":
    """Arrow-key navigable terminal picker using curses."""
    import curses

    result: list = [None]

    def _inner(stdscr):
        curses.curs_set(0)
        try:
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_BLACK, curses.COLOR_WHITE)
            highlight = curses.color_pair(1)
        except Exception:
            highlight = curses.A_REVERSE

        pos = 0
        while True:
            stdscr.erase()
            h, w = stdscr.getmaxyx()
            stdscr.addstr(0, 0, prompt[: w - 1])
            stdscr.addstr(1, 0, "Arrow keys / j-k navigate  |  Enter select  |  q / Esc cancel"[:w - 1])
            for i, item in enumerate(items):
                row = i + 3
                if row >= h - 1:
                    break
                label = f"{'>' if i == pos else ' '} {item}"
                if i == pos:
                    stdscr.attron(highlight)
                    stdscr.addstr(row, 1, label[: w - 2])
                    stdscr.attroff(highlight)
                else:
                    stdscr.addstr(row, 1, label[: w - 2])
            stdscr.refresh()
            key = stdscr.getch()
            if key in (curses.KEY_UP, ord("k")) and pos > 0:
                pos -= 1
            elif key in (curses.KEY_DOWN, ord("j")) and pos < len(items) - 1:
                pos += 1
            elif key in (curses.KEY_ENTER, 10, 13):
                result[0] = items[pos]
                break
            elif key in (ord("q"), 27):   # q or ESC
                break

    curses.wrapper(_inner)
    return result[0]


def _simple_pick(items: list, prompt: str) -> "str | None":
    """Numbered-list fallback for non-interactive terminals."""
    print(prompt)
    for i, item in enumerate(items, 1):
        print(f"  {i:>3}. {item}")
    raw = input("Enter number (or 0 to cancel): ").strip()
    try:
        idx = int(raw)
    except ValueError:
        return None
    if idx < 1 or idx > len(items):
        return None
    return items[idx - 1]


def pick_from_list(items: list, prompt: str = "Select:") -> "str | None":
    """Choose the best available picker for the current terminal."""
    if not items:
        return None
    if sys.stdin.isatty() and sys.stdout.isatty():
        try:
            return _curses_pick(items, prompt)
        except Exception:
            pass
    return _simple_pick(items, prompt)


# ---------------------------------------------------------------------------
# yt-dlp command builder
# ---------------------------------------------------------------------------

def _build_ytdlp_cmd(name: str, ch: dict) -> list:
    """Assemble the yt-dlp argument list for one channel entry."""
    location = os.path.expanduser(
        ch.get("download_location") or f"~/Downloads/youTube/{name}"
    )
    output_tmpl = os.path.join(location, "%(title)s.%(ext)s")

    cmd = [
        "yt-dlp",
        "-f", "bv*+ba/b",
        "--merge-output-format", "mkv",
        "--no-overwrites",
        "-o", output_tmpl,
    ]

    if ch.get("cookies_from_browser"):
        cmd += ["--cookies-from-browser", ch["cookies_from_browser"]]

    if ch.get("dated_downloads", True) and ch.get("last_download_utc"):
        try:
            raw = ch["last_download_utc"]
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            cmd += ["--dateafter", dt.strftime("%Y%m%d")]
        except (ValueError, AttributeError) as exc:
            print(f"  Warning: could not parse last_download_utc '{ch.get('last_download_utc')}' ({exc}); skipping date filter.")

    cmd.append(ch["url"])
    return cmd


def _run_channel(name: str, ch: dict) -> int:
    """Execute yt-dlp for one channel. Returns the yt-dlp exit code."""
    location = os.path.expanduser(
        ch.get("download_location") or f"~/Downloads/youTube/{name}"
    )
    Path(location).mkdir(parents=True, exist_ok=True)

    cmd = _build_ytdlp_cmd(name, ch)

    print(f"\n{'=' * 64}")
    print(f"  Channel : {name}")
    print(f"  URL     : {ch['url']}")
    print(f"  Output  : {location}")
    print(f"  Command : {' '.join(cmd)}")
    print(f"{'=' * 64}\n")

    return subprocess.run(cmd).returncode


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_add_channel(args) -> None:
    config = load_config()
    channels: dict = config["channels"]

    url: str = args.add_channel.strip()
    name = _channel_name_from_url(url)

    if name in channels:
        print(f"Channel '{name}' is already in the config ({CONFIG_FILE}).")
        return

    dated = True
    if args.dated_downloads is not None:
        dated = args.dated_downloads.strip().lower() in ("yes", "y", "true", "1")

    location = args.download_location or str(
        Path.home() / "Downloads" / "youTube" / name
    )

    entry: dict = {
        "url": url,
        "download_location": location,
        "dated_downloads": dated,
    }
    if args.cookies_from_browser:
        entry["cookies_from_browser"] = args.cookies_from_browser.strip()

    channels[name] = entry
    save_config(config)

    print(f"Added    : {name}")
    print(f"URL      : {url}")
    print(f"Output   : {location}")
    print(f"Dated    : {dated}")
    if args.cookies_from_browser:
        print(f"Cookies  : {args.cookies_from_browser}")
    print(f"Config   : {CONFIG_FILE}")


def cmd_remove_channel(args) -> None:
    config = load_config()
    channels: dict = config["channels"]

    if not channels:
        print("No channels configured.")
        return

    names = sorted(channels.keys())
    chosen = pick_from_list(names, "Select channel to remove:")
    if chosen is None:
        print("Cancelled.")
        return

    confirm = input(f"\nRemove '{chosen}'? [y/N]: ").strip().lower()
    if confirm in ("y", "yes"):
        del channels[chosen]
        save_config(config)
        print(f"Removed '{chosen}'.")
    else:
        print("Cancelled.")


def cmd_list_channels(args) -> None:
    config = load_config()
    channels: dict = config["channels"]

    if not channels:
        print(f"No channels configured. Config: {CONFIG_FILE}")
        return

    print(f"\nChannels ({len(channels)})  —  config: {CONFIG_FILE}\n")
    for name, ch in channels.items():
        print(f"  {name}")
        print(f"    url              : {ch['url']}")
        print(f"    download_location: {ch.get('download_location', '(default)')}")
        print(f"    dated_downloads  : {ch.get('dated_downloads', True)}")
        if ch.get("cookies_from_browser"):
            print(f"    cookies_from     : {ch['cookies_from_browser']}")
        if ch.get("last_download_utc"):
            print(f"    last_download    : {ch['last_download_utc']}")
        print()


def cmd_download_all(args) -> None:
    config = load_config()
    channels: dict = config["channels"]

    if not channels:
        print("No channels configured. Add one with --add-channel.")
        return

    failed = []
    for name, ch in channels.items():
        if ch.get("dated_downloads", True) and not ch.get("last_download_utc"):
            print(f"\n[{name}] Note: no last_download_utc set — this will attempt to download ALL videos.")

        start = datetime.now(timezone.utc)
        rc = _run_channel(name, ch)

        if rc == 0:
            ch["last_download_utc"] = start.isoformat()
            save_config(config)
            print(f"[{name}] Done — last_download_utc updated to {ch['last_download_utc']}")
        else:
            failed.append(name)
            print(f"[{name}] yt-dlp exited with code {rc} — last_download_utc NOT updated.")

    print("\n" + "=" * 64)
    if failed:
        print(f"Completed with errors: {', '.join(failed)}")
    else:
        print("All channels downloaded successfully.")


def cmd_download_channel(args) -> None:
    config = load_config()
    channels: dict = config["channels"]
    name: str = args.download_channel

    if name not in channels:
        available = ", ".join(sorted(channels)) or "(none)"
        sys.exit(f"Channel '{name}' not found. Available: {available}")

    ch = channels[name]
    if ch.get("dated_downloads", True) and not ch.get("last_download_utc"):
        print(f"Note: no last_download_utc set — this will attempt to download ALL videos for '{name}'.")

    start = datetime.now(timezone.utc)
    rc = _run_channel(name, ch)

    if rc == 0:
        ch["last_download_utc"] = start.isoformat()
        save_config(config)
        print(f"\nDone — last_download_utc updated to {ch['last_download_utc']}")
    else:
        print(f"\nyt-dlp exited with code {rc} — last_download_utc NOT updated.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="yt-downloader",
        description="YouTube channel downloader powered by yt-dlp.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            f"Config file: {CONFIG_FILE}\n\n"
            "Examples:\n"
            '  %(prog)s --add-channel "https://www.youtube.com/@CleetusM" --DatedDownloads yes\n'
            '  %(prog)s --add-channel "https://www.youtube.com/@Chan" --cookies-from-browser chrome\n'
            "  %(prog)s --download-all\n"
            "  %(prog)s --download-channel CleetusM\n"
            "  %(prog)s --list-channels\n"
            "  %(prog)s --remove-channel"
        ),
    )

    # -- add-channel group
    parser.add_argument(
        "--add-channel",
        metavar="URL",
        help="Add a YouTube channel URL to the config.",
    )
    parser.add_argument(
        "--DatedDownloads", "--dated-downloads",
        dest="dated_downloads",
        metavar="YES|NO",
        help="(with --add-channel) Only fetch videos newer than the last run. Default: yes.",
    )
    parser.add_argument(
        "--cookies-from-browser",
        metavar="BROWSER",
        help="(with --add-channel) Browser to source cookies from (chrome, firefox, safari …).",
    )
    parser.add_argument(
        "--download-location",
        metavar="PATH",
        help="(with --add-channel) Override the output directory.",
    )

    # -- management
    parser.add_argument(
        "--remove-channel",
        action="store_true",
        help="Interactively pick and remove a channel from the config.",
    )
    parser.add_argument(
        "--list-channels",
        action="store_true",
        help="Print all configured channels and their settings.",
    )

    # -- download
    parser.add_argument(
        "--download-all",
        action="store_true",
        help="Download new videos for every configured channel.",
    )
    parser.add_argument(
        "--download-channel",
        metavar="NAME",
        help="Download new videos for a single channel by name.",
    )

    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if args.add_channel:
        cmd_add_channel(args)
    elif args.remove_channel:
        cmd_remove_channel(args)
    elif args.download_all:
        cmd_download_all(args)
    elif args.download_channel:
        cmd_download_channel(args)
    elif args.list_channels:
        cmd_list_channels(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
