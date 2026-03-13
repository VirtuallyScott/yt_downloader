#!/usr/bin/env bash
# install-online.sh — one-line online installer for yt-downloader
#
# Usage (once this repo is on GitHub, substitute your actual user/repo):
#
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/install-online.sh | bash
#
# What this does:
#   1. Installs Homebrew (if absent)
#   2. Installs all yt-dlp dependencies via Homebrew + pip
#   3. Downloads yt-downloader.py from this repo's GitHub raw URL
#   4. Creates the XDG directory structure
#   5. Installs yt-downloader to ~/.local/bin and patches PATH

set -euo pipefail

# ---------------------------------------------------------------------------
# ★  Edit these to match your GitHub repository before publishing  ★
# ---------------------------------------------------------------------------
GITHUB_USER="VirtuallyScott"
GITHUB_REPO="yt_downloader"
GITHUB_BRANCH="main"
# ---------------------------------------------------------------------------

SCRIPT_RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/yt-downloader.py"

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
INSTALL_TARGET="$BIN_DIR/$APP"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { printf '  \033[32m✔\033[0m  %s\n' "$*"; }
warn()    { printf '  \033[33m⚠\033[0m  %s\n' "$*"; }
error()   { printf '  \033[31m✖\033[0m  %s\n' "$*" >&2; }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

brew_install() {
    local formula="$1"
    if brew list --formula "$formula" &>/dev/null 2>&1; then
        info "$formula  (already installed)"
    else
        echo "  → brew install $formula"
        brew install "$formula"
        info "$formula  installed"
    fi
}

# ---------------------------------------------------------------------------
echo ""
printf '\033[1m=== yt-downloader online installer ===\033[0m\n'
echo ""
echo "  Source : $SCRIPT_RAW_URL"
echo ""

# Abort early if the placeholder URL has not been updated

# ---------------------------------------------------------------------------
section "Checking for Homebrew..."
# ---------------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
    warn "Homebrew not found — installing now..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    info "Homebrew installed"
else
    info "Homebrew  ($(command -v brew))"
fi

# ---------------------------------------------------------------------------
section "Checking Python..."
# ---------------------------------------------------------------------------
if ! command -v python3 &>/dev/null; then
    warn "python3 not found — installing via Homebrew..."
    brew install python
fi

PYTHON_MAJOR="$(python3 -c "import sys; print(sys.version_info.major)")"
PYTHON_MINOR="$(python3 -c "import sys; print(sys.version_info.minor)")"
PYTHON_VER="${PYTHON_MAJOR}.${PYTHON_MINOR}"
info "python3 $PYTHON_VER  ($(command -v python3))"

if [[ "$PYTHON_MAJOR" -lt 3 || ( "$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -lt 11 ) ]]; then
    warn "Python < 3.11 — installing 'tomli' for TOML support..."
    python3 -m pip install --user --quiet tomli
    info "tomli installed"
else
    info "tomllib available in stdlib (Python 3.11+)"
fi

# ---------------------------------------------------------------------------
section "Installing yt-dlp and core dependencies via Homebrew..."
# ---------------------------------------------------------------------------
# yt-dlp         — the downloader
# ffmpeg         — merges video+audio streams, post-processing (includes ffprobe)
# deno           — recommended JS runtime for yt-dlp-ejs (full YouTube support;
#                  this is the modern replacement for PhantomJS)
# aria2          — faster multi-connection downloads (use with --downloader aria2c)
# atomicparsley  — thumbnail embedding for mp4/m4a files
brew_install yt-dlp
brew_install ffmpeg
brew_install deno
brew_install aria2
brew_install atomicparsley

# ---------------------------------------------------------------------------
section "Installing Python yt-dlp optional packages..."
# ---------------------------------------------------------------------------
# yt-dlp[default] — certifi, brotli, websockets, requests, mutagen, pycryptodomex
#   certifi       — Mozilla root certificate bundle (SSL)
#   brotli        — Brotli content-encoding support
#   websockets    — live stream / websocket downloads
#   requests      — HTTPS proxy and persistent connections
#   mutagen       — embed thumbnails in certain container formats
#   pycryptodomex — decrypt AES-128 HLS streams
# curl-cffi       — TLS browser impersonation (Chrome/Edge/Safari fingerprinting bypass)
# xattr           — write XDG/Dublin Core metadata to file extended attributes
echo "  → pip install \"yt-dlp[default,curl-cffi]\" xattr"
python3 -m pip install --user --quiet "yt-dlp[default,curl-cffi]" xattr
info "yt-dlp Python packages installed"

# ---------------------------------------------------------------------------
section "Downloading yt-downloader.py..."
# ---------------------------------------------------------------------------
TMPFILE="$(mktemp /tmp/yt-downloader.XXXXXX.py)"
trap 'rm -f "$TMPFILE"' EXIT

if command -v curl &>/dev/null; then
    curl -fsSL "$SCRIPT_RAW_URL" -o "$TMPFILE"
elif command -v wget &>/dev/null; then
    wget -qO "$TMPFILE" "$SCRIPT_RAW_URL"
else
    error "Neither curl nor wget found — cannot download installer."
    exit 1
fi

# Basic sanity check: the file should look like a Python script
if ! head -1 "$TMPFILE" | grep -q 'python'; then
    error "Downloaded file does not appear to be a Python script."
    error "Check that the URL is correct: $SCRIPT_RAW_URL"
    exit 1
fi

info "Downloaded yt-downloader.py ($( wc -c < "$TMPFILE" | tr -d ' ') bytes)"

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
install -m 755 "$TMPFILE" "$INSTALL_TARGET"
info "$INSTALL_TARGET"

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
        warn "$label not found in PATH — you may need to restart your shell"
    fi
}
_check yt-dlp
_check ffmpeg
_check ffprobe   "ffprobe (bundled with ffmpeg)"
_check deno
_check aria2c    "aria2"
_check AtomicParsley "AtomicParsley"

# ---------------------------------------------------------------------------
printf '\n\033[1m========================================\033[0m\n'
printf '\033[1m Installation complete!\033[0m\n'
printf '\033[1m========================================\033[0m\n'
echo ""
echo "  Executable : $INSTALL_TARGET"
echo "  Config     : $CONFIG_FILE"
echo ""
echo "  Restart your shell (or run: source ~/.zshrc) to refresh PATH."
echo ""
printf '\033[1mDependency summary:\033[0m\n'
echo "  yt-dlp        — downloader binary"
echo "  ffmpeg/probe  — video/audio merging and post-processing"
echo "  deno          — JS runtime for YouTube yt-dlp-ejs (replaces PhantomJS)"
echo "  aria2         — multi-connection HTTP downloader (--downloader aria2c)"
echo "  AtomicParsley — thumbnail embedding for mp4/m4a"
echo "  curl-cffi     — TLS browser impersonation for fingerprint-protected sites"
echo "  mutagen       — thumbnail embedding for additional formats"
echo "  pycryptodomex — AES-128 HLS stream decryption"
echo ""
printf '\033[1mQuick start:\033[0m\n'
echo "  $APP --add-channel \"https://www.youtube.com/@YourChannel\" --DatedDownloads yes"
echo "  $APP --list-channels"
echo "  $APP --download-all"
echo "  $APP --remove-channel"
echo ""
printf '\033[1mTo update yt-downloader later:\033[0m\n'
echo "  curl -fsSL https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}/install-online.sh | bash"
echo ""
