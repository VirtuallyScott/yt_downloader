#!/usr/bin/env bash
# install-yt-downloader.sh
#
# Installs yt-downloader into the XDG Base Directory layout on macOS.
# Also installs all yt-dlp dependencies via Homebrew and pip.
#
# Installed layout:
#   ~/.local/bin/yt-downloader                         ← executable
#   $XDG_CONFIG_HOME/yt-downloader/yt-downloader.toml  ← config (created if absent)
#   $XDG_DATA_HOME/yt-downloader/                      ← data directory
#   $XDG_CACHE_HOME/yt-downloader/                     ← cache directory
#
# Usage:
#   bash install-yt-downloader.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# XDG directories
# ---------------------------------------------------------------------------
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
BIN_DIR="$HOME/.local/bin"

APP="yt-downloader"
CONFIG_DIR="$XDG_CONFIG_HOME/$APP"
CONFIG_FILE="$CONFIG_DIR/$APP.toml"
DATA_DIR="$XDG_DATA_HOME/$APP"
CACHE_DIR="$XDG_CACHE_HOME/$APP"

# Directory containing this script (i.e. the repo root)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { printf '  \033[32m✔\033[0m  %s\n' "$*"; }
warn()    { printf '  \033[33m⚠\033[0m  %s\n' "$*"; }
error()   { printf '  \033[31m✖\033[0m  %s\n' "$*" >&2; }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

brew_install() {
    local formula="$1"
    if brew list --formula "$formula" &>/dev/null; then
        info "$formula  (already installed)"
    else
        echo "  → brew install $formula"
        brew install "$formula"
        info "$formula  installed"
    fi
}

# ---------------------------------------------------------------------------
echo ""
printf '\033[1m=== yt-downloader installer ===\033[0m\n'

# ---------------------------------------------------------------------------
section "Checking for Homebrew..."
# ---------------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
    warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for the remainder of this script (Apple Silicon path)
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    info "Homebrew installed"
else
    BREW_VER="$(brew --version | head -1)"
    info "$BREW_VER  ($(command -v brew))"
fi

# ---------------------------------------------------------------------------
section "Checking Python..."
# ---------------------------------------------------------------------------
if ! command -v python3 &>/dev/null; then
    warn "python3 not found — installing via Homebrew..."
    brew install python
fi

PYTHON_VER="$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")"
PYTHON_MAJOR="$(python3 -c "import sys; print(sys.version_info.major)")"
PYTHON_MINOR="$(python3 -c "import sys; print(sys.version_info.minor)")"
info "python3 $PYTHON_VER  ($(command -v python3))"

if [[ "$PYTHON_MAJOR" -lt 3 || ( "$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -lt 11 ) ]]; then
    warn "Python < 3.11 detected — installing 'tomli' for TOML support..."
    python3 -m pip install --user --quiet tomli
    info "tomli installed"
else
    info "tomllib available in stdlib (Python 3.11+)"
fi

# ---------------------------------------------------------------------------
section "Installing yt-dlp and core dependencies via Homebrew..."
# ---------------------------------------------------------------------------
# yt-dlp   — the downloader
# ffmpeg   — required: merges separate video+audio streams, post-processing
# deno     — recommended JS runtime (yt-dlp-ejs, replaces PhantomJS for YouTube)
# aria2    — optional but recommended: faster multi-connection downloads
# atomicparsley — embeds thumbnails into mp4/m4a when ffmpeg/mutagen cannot
brew_install yt-dlp
brew_install ffmpeg
brew_install deno
brew_install aria2
brew_install atomicparsley

# ---------------------------------------------------------------------------
section "Installing Python yt-dlp optional packages..."
# ---------------------------------------------------------------------------
# yt-dlp[default]   — certifi, brotli, websockets, requests, mutagen, pycryptodomex
# curl-cffi         — TLS fingerprint impersonation (Chrome/Edge/Safari) for sites
#                     that block scrapers via TLS fingerprinting
# xattr             — write XDG/Dublin Core metadata to file extended attributes (--xattrs)
echo "  → pip install \"yt-dlp[default,curl-cffi]\" xattr"
python3 -m pip install --user --quiet "yt-dlp[default,curl-cffi]" xattr
info "yt-dlp Python packages installed"

# ---------------------------------------------------------------------------
section "Creating XDG directory structure..."
# ---------------------------------------------------------------------------
mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$CACHE_DIR" "$BIN_DIR"
info "config : $CONFIG_DIR"
info "data   : $DATA_DIR"
info "cache  : $CACHE_DIR"
info "bin    : $BIN_DIR"

# ---------------------------------------------------------------------------
section "Installing yt-downloader script..."
# ---------------------------------------------------------------------------
install -m 755 "$REPO_DIR/yt-downloader.py" "$BIN_DIR/$APP"
info "$BIN_DIR/$APP"

# ---------------------------------------------------------------------------
section "Config file..."
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" << 'TOML_TEMPLATE'
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
#
# Example (uncomment and edit):
# [channels.CleetusM]
# url                  = "https://www.youtube.com/@CleetusM"
# download_location    = "~/Downloads/youTube/CleetusM"
# dated_downloads      = true
# cookies_from_browser = "chrome"
TOML_TEMPLATE
    info "Created config: $CONFIG_FILE"
else
    info "Config already exists (skipped): $CONFIG_FILE"
fi

# ---------------------------------------------------------------------------
section "Checking PATH..."
# ---------------------------------------------------------------------------
if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    info "\$HOME/.local/bin is already in PATH"
else
    ADDED=false
    for rc_file in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.profile"; do
        if [[ -f "$rc_file" ]] && ! grep -qF '.local/bin' "$rc_file"; then
            printf '\n# Added by yt-downloader installer\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc_file"
            info "Added \$HOME/.local/bin to PATH in $rc_file"
            ADDED=true
            break
        fi
    done
    if [[ "$ADDED" == "false" ]]; then
        warn "Could not find a shell rc file to update."
        warn "Add to your shell profile manually:"
        warn '  export PATH="$HOME/.local/bin:$PATH"'
    fi
fi

# ---------------------------------------------------------------------------
section "Verifying installs..."
# ---------------------------------------------------------------------------
_check() {
    local cmd="$1" label="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then
        info "$label  ($(command -v "$cmd"))"
    else
        warn "$label not found in PATH after install — you may need to restart your shell"
    fi
}
_check yt-dlp
_check ffmpeg
_check ffprobe   "ffprobe (bundled with ffmpeg)"
_check deno
_check aria2c    "aria2"
_check AtomicParsley "AtomicParsley"
_check deno

# ---------------------------------------------------------------------------
printf '\n\033[1m========================================\033[0m\n'
printf '\033[1m Installation complete!\033[0m\n'
printf '\033[1m========================================\033[0m\n'
echo ""
echo "  Executable : $BIN_DIR/$APP"
echo "  Config     : $CONFIG_FILE"
echo ""
echo "  Restart your shell (or run: source ~/.zshrc) to refresh PATH."
echo ""
printf '\033[1mDependency summary:\033[0m\n'
echo "  yt-dlp       — downloader binary"
echo "  ffmpeg/probe — video/audio merging and post-processing"
echo "  deno         — JavaScript runtime for YouTube yt-dlp-ejs (replaces PhantomJS)"
echo "  aria2        — multi-connection HTTP downloader (use with --downloader aria2c)"
echo "  AtomicParsley— thumbnail embedding for mp4/m4a"
echo "  curl-cffi    — TLS browser impersonation for fingerprint-protected sites"
echo ""
printf '\033[1mQuick start:\033[0m\n'
echo "  $APP --add-channel \"https://www.youtube.com/@YourChannel\" --DatedDownloads yes"
echo "  $APP --list-channels"
echo "  $APP --download-all"
echo "  $APP --remove-channel"
echo ""
