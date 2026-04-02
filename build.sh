#!/bin/bash
# =============================================================================
# Blakecoin 0.15.2 Build Script — All Platforms
#
# Single self-contained script to build Blakecoin daemon and/or Qt wallet
# for Linux, macOS, Windows, and AppImage.
#
# Based on Bitcoin Core 0.15.2 — uses autotools (./configure + make).
# Cross-compilation uses pre-built libraries in each Docker image (same
# images as the 0.8.x coins) — does NOT use the depends/ system.
#
# Usage: ./build.sh [PLATFORM] [TARGET] [OPTIONS]
#   See ./build.sh --help for full usage.
#
# Docker Hub images (prebuilt):
#   sidgrip/native-base:20.04     — Native Linux (Ubuntu 20.04, GCC 9, Boost 1.71)
#   sidgrip/native-base:22.04     — Native Linux (Ubuntu 22.04, GCC 11, Boost 1.74)
#   sidgrip/native-base:24.04     — Native Linux (Ubuntu 24.04, GCC 13, Boost 1.83)
#   sidgrip/appimage-base:22.04   — AppImage builds (Ubuntu 22.04 + appimagetool)
#   sidgrip/mxe-base:latest       — Windows cross-compile (MXE + MinGW)
#   sidgrip/osxcross-base:latest  — macOS cross-compile (osxcross + clang-18)
#
# Repository: https://github.com/BlueDragon747/Blakecoin (branch: 0.15.2)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_BASE="$SCRIPT_DIR/outputs"
COIN_NAME="blakecoin"
COIN_NAME_UPPER="Blakecoin"
DAEMON_NAME="blakecoind"
QT_NAME="blakecoin-qt"
CLI_NAME="blakecoin-cli"
TX_NAME="blakecoin-tx"
VERSION="0.15.2"
REPO_URL="https://github.com/BlueDragon747/Blakecoin.git"
REPO_BRANCH="0.15.2"
QT_LINUX_LAUNCHER_SOURCE="$SCRIPT_DIR/contrib/linux-release/blakecoin-qt-launcher.c"
APPIMAGE_LAUNCHER_SOURCE="$SCRIPT_DIR/contrib/appimage-release/blakecoin-appimage-launcher.c"
APPIMAGE_PUBLIC_NAME="${COIN_NAME_UPPER}-${VERSION}-x86_64.AppImage"
APPIMAGE_PAYLOAD_NAME="${COIN_NAME_UPPER}-${VERSION}-x86_64.AppImage.payload"
APPIMAGE_RELEASE_DIR_NAME="blakecoin-v${VERSION}-appimage-ubuntu-22plus-x86_64"
APPIMAGE_RELEASE_ARCHIVE_NAME="${APPIMAGE_PUBLIC_NAME}.tar.gz"
WINDOWS_RELEASE_ARCHIVE_NAME="blakecoin-v${VERSION}-windows-x86_64.zip"
WINDOWS_ICON_SOURCE_PNG="$SCRIPT_DIR/src/qt/res/icons/bitcoin.png"
WINDOWS_ICON_SOURCE_TESTNET_PNG="$SCRIPT_DIR/src/qt/res/icons/bitcoin_testnet.png"
WINDOWS_EXE_ICON_ICO="$SCRIPT_DIR/src/qt/res/icons/Blakecoin_32.ico"
WINDOWS_EXE_ICON_TESTNET_ICO="$SCRIPT_DIR/src/qt/res/icons/Blakecoin_32_testnet.ico"
WINDOWS_INSTALLER_ICON_ICO="$SCRIPT_DIR/share/pixmaps/Blakecoin.ico"

# Network ports and config
RPC_PORT=8772
P2P_PORT=8773
CHAINZ_CODE="blc"
CONFIG_FILE="${COIN_NAME}.conf"
LISTEN='listen=1'
DAEMON='daemon=1'
SERVER='server=0'
TXINDEX='txindex=0'

# Docker images
DOCKER_NATIVE="sidgrip/native-base:22.04"
DOCKER_APPIMAGE="sidgrip/appimage-base:22.04"
DOCKER_WINDOWS="sidgrip/mxe-base:latest"
DOCKER_MACOS="sidgrip/osxcross-base:latest"

# Cross-compile host triplets
WIN_HOST="x86_64-w64-mingw32.static"
MAC_HOST=""  # Auto-detected from Docker image at build time

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Fix execute permissions after copying source tree (rsync/cp can lose +x bits)
fix_permissions() {
    local dir="$1"
    find "$dir" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
    find "$dir" -name 'config.guess' -o -name 'config.sub' -o -name 'install-sh' \
        -o -name 'missing' -o -name 'compile' -o -name 'depcomp' \
        -o -name 'build_detect_platform' -o -name 'autogen.sh' \
        | xargs chmod +x 2>/dev/null || true
}

# Portable sed -i wrapper (macOS BSD sed requires '' arg, GNU sed does not)
sedi() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

ensure_windows_icon_assets() {
    local missing=()
    local path

    for path in \
        "$WINDOWS_ICON_SOURCE_PNG" \
        "$WINDOWS_ICON_SOURCE_TESTNET_PNG" \
        "$WINDOWS_EXE_ICON_ICO" \
        "$WINDOWS_EXE_ICON_TESTNET_ICO" \
        "$WINDOWS_INSTALLER_ICON_ICO"
    do
        [[ -f "$path" ]] || missing+=("$path")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required Windows icon asset(s):"
        printf '  %s\n' "${missing[@]}"
        exit 1
    fi

    info "Windows branding source (main): $WINDOWS_ICON_SOURCE_PNG"
    info "Windows branding source (testnet): $WINDOWS_ICON_SOURCE_TESTNET_PNG"
    info "Windows embedded exe icon (main): $WINDOWS_EXE_ICON_ICO"
    info "Windows embedded exe icon (testnet): $WINDOWS_EXE_ICON_TESTNET_ICO"
    info "Windows installer icon: $WINDOWS_INSTALLER_ICON_ICO"
}

ensure_macos_brew_env() {
    local brew_bin=""

    if command -v brew &>/dev/null; then
        brew_bin=$(command -v brew)
    else
        for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/homebrew/bin/brew"; do
            [[ -x "$brew_bin" ]] && break
        done
    fi

    if [[ -n "$brew_bin" && -x "$brew_bin" ]]; then
        eval "$("$brew_bin" shellenv)" >/dev/null 2>&1 || true
        export PATH="$(dirname "$brew_bin"):$PATH"
        return 0
    fi

    return 1
}

prime_macos_sudo() {
    if sudo -n true 2>/dev/null; then
        return 0
    fi

    if [[ -n "${MACOS_SUDO_PASS:-}" ]]; then
        printf '%s\n' "$MACOS_SUDO_PASS" | sudo -S -p '' -v
    else
        sudo -v
    fi
}

ensure_macos_homebrew() {
    if ensure_macos_brew_env; then
        return 0
    fi

    info "Homebrew not found — installing it automatically..."
    prime_macos_sudo
    NONINTERACTIVE=1 CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if ! ensure_macos_brew_env; then
        error "Homebrew installation completed but brew is still not available."
        exit 1
    fi
}

usage() {
    cat <<'EOF'
Usage: build.sh [PLATFORM] [TARGET] [OPTIONS]

Platforms:
  --native          Build natively on this machine (Linux, macOS, or Windows)
  --appimage        Build portable Linux AppImage (requires Docker)
  --windows         Cross-compile for Windows from Linux (requires Docker)
  --macos           Cross-compile for macOS from Linux (requires Docker)

Targets:
  --daemon          Build daemon only (blakecoind + blakecoin-cli + blakecoin-tx)
  --qt              Build Qt wallet only (blakecoin-qt)
  --both            Build daemon and Qt wallet (default)

Docker options (for --appimage, --windows, --macos, or --native on Linux):
  --pull-docker     Pull prebuilt Docker images from Docker Hub
  --build-docker    Build Docker images locally from repo Dockerfiles
  --no-docker       For --native on Linux: skip Docker, build directly on host

Other options:
  --jobs N          Parallel make jobs (default: CPU cores - 1)
  -h, --help        Show this help

Examples:
  # Native builds (no Docker needed)
  ./build.sh --native --both                   # Build directly on host
  ./build.sh --native --daemon                 # Daemon only

  # Native Linux with Docker
  ./build.sh --native --both --pull-docker     # Use appimage-base from Docker Hub
  ./build.sh --native --both --build-docker    # Same as --pull-docker (shared images)

  # Cross-compile (Docker required — choose --pull-docker or --build-docker)
  ./build.sh --windows --qt --pull-docker      # Pull mxe-base from Docker Hub
  ./build.sh --macos --qt --pull-docker        # Pull osxcross-base from Docker Hub
  ./build.sh --appimage --pull-docker          # Pull appimage-base from Docker Hub

Docker Hub images (used with --pull-docker):
  sidgrip/native-base:20.04             Native Linux (Ubuntu 20.04, GCC 9)
  sidgrip/native-base:22.04             Native Linux (Ubuntu 22.04, GCC 11) [default]
  sidgrip/native-base:24.04             Native Linux (Ubuntu 24.04, GCC 13)
  sidgrip/appimage-base:22.04           AppImage (Ubuntu 22.04 + appimagetool)
  sidgrip/mxe-base:latest               Windows cross-compile (MXE + MinGW)
  sidgrip/osxcross-base:latest          macOS cross-compile (osxcross + clang-18)
EOF
    exit 0
}

detect_os() {
    if [[ "${MSYSTEM:-}" =~ MINGW|MSYS ]]; then
        echo "windows"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

detect_os_version() {
    local os="$1"
    case "$os" in
        linux)
            if command -v lsb_release &>/dev/null; then
                lsb_release -ds 2>/dev/null
            elif [[ -f /etc/os-release ]]; then
                . /etc/os-release && echo "${PRETTY_NAME:-$NAME $VERSION_ID}"
            else
                echo "Linux $(uname -r)"
            fi
            ;;
        macos)
            echo "macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
            ;;
        windows)
            if [[ -n "${MSYSTEM:-}" ]]; then
                echo "$MSYSTEM / Windows $(uname -r 2>/dev/null || echo 'unknown')"
            else
                echo "Windows"
            fi
            ;;
    esac
}

ensure_windows_native_shell() {
    local target="$1"
    local jobs="$2"
    local msys_root="/c/msys64"
    local msys_bash="$msys_root/usr/bin/bash.exe"
    local msys_env="$msys_root/usr/bin/env.exe"
    local target_flag="--both"
    local reexec_cmd=""

    case "$target" in
        daemon) target_flag="--daemon" ;;
        qt)     target_flag="--qt" ;;
        both)   target_flag="--both" ;;
    esac

    if [[ "${MSYSTEM:-}" == "MINGW64" ]] && command -v pacman &>/dev/null; then
        return 0
    fi

    if ! command -v powershell.exe &>/dev/null; then
        error "PowerShell is required to bootstrap native Windows builds."
        exit 1
    fi

    if [[ ! -x "$msys_bash" || ! -x "$msys_env" ]]; then
        info "MSYS2 not found — installing it automatically..."
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '
            $ErrorActionPreference = "Stop"
            $msysUrl = "https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe"
            $msysExe = "$env:TEMP\msys2-base-x86_64-latest.sfx.exe"
            Invoke-WebRequest -UseBasicParsing -Uri $msysUrl -OutFile $msysExe
            & $msysExe "-y" "-oC:\"
        '
    fi

    if [[ ! -x "$msys_bash" || ! -x "$msys_env" ]]; then
        error "MSYS2 installation did not produce $msys_bash"
        exit 1
    fi

    info "Initializing MSYS2..."
    "$msys_env" MSYSTEM=MINGW64 CHERE_INVOKING=yes MSYS2_PATH_TYPE=inherit \
        "$msys_bash" -lc '
            set +e
            pacman-key --init >/dev/null 2>&1
            pacman-key --populate msys2 >/dev/null 2>&1
            pacman --noconfirm -Sy >/dev/null 2>&1
            pacman --noconfirm -Syuu >/dev/null 2>&1
            pacman --noconfirm -Syuu >/dev/null 2>&1
            exit 0
        '

    printf -v reexec_cmd 'cd %q && ./build.sh --native %s --jobs %q' "$SCRIPT_DIR" "$target_flag" "$jobs"
    info "Re-entering build.sh inside MSYS2 MINGW64..."
    exec "$msys_env" MSYSTEM=MINGW64 CHERE_INVOKING=yes MSYS2_PATH_TYPE=inherit \
        "$msys_bash" -lc "$reexec_cmd"
}

write_build_info() {
    local output_dir="$1"
    local platform="$2"
    local target="$3"
    local os_version="$4"

    mkdir -p "$output_dir"
    cat > "$output_dir/build-info.txt" <<EOF
Coin:       $COIN_NAME_UPPER 0.15.2
Target:     $target
Platform:   $platform
OS:         $os_version
Date:       $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Branch:     $REPO_BRANCH
Script:     build.sh
EOF
}

copy_runtime_libs() {
    local binary="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"
    while IFS= read -r lib; do
        [[ -n "$lib" && -r "$lib" ]] || continue
        case "$(basename "$lib")" in
            ld-linux-*|libc.so.*|libdl.so.*|libm.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libnsl.so.*|libanl.so.*)
                continue
                ;;
        esac
        cp -Lf "$lib" "$dest_dir/"
    done < <(
        ldd "$binary" 2>/dev/null | awk '
            /=> \// {print $3}
            /^\// {print $1}
        ' | sort -u
    )
}

is_macos_system_dylib() {
    case "$1" in
        /System/Library/*|/usr/lib/*)
            return 0
            ;;
    esac
    return 1
}

resolve_macos_bundle_dep_target() {
    local dep="$1"
    local subject="$2"
    local main_exe_dir="$3"
    local frameworks_dir="$4"

    case "$dep" in
        @executable_path/*)
            printf '%s\n' "$main_exe_dir/${dep#@executable_path/}"
            ;;
        @loader_path/*)
            printf '%s\n' "$(dirname "$subject")/${dep#@loader_path/}"
            ;;
        @rpath/*)
            local rel="${dep#@rpath/}"
            if [[ -e "$frameworks_dir/$rel" ]]; then
                printf '%s\n' "$frameworks_dir/$rel"
            else
                printf '%s\n' "$frameworks_dir/$(basename "$dep")"
            fi
            ;;
        *)
            printf '%s\n' "$dep"
            ;;
    esac
}

find_macos_source_dylib() {
    local dylib_name="$1"
    shift

    local search_dir=""
    for search_dir in "$@"; do
        [[ -n "$search_dir" && -d "$search_dir" ]] || continue
        if [[ -f "$search_dir/$dylib_name" ]]; then
            printf '%s\n' "$search_dir/$dylib_name"
            return 0
        fi
    done

    return 1
}

bundle_macos_transitive_dylibs() {
    local app_dir="$1"
    shift

    local frameworks_dir="$app_dir/Contents/Frameworks"
    local main_exe_dir="$app_dir/Contents/MacOS"
    local main_exe="$main_exe_dir/Blakecoin-Qt"
    local search_dirs=("$@")
    local pass=0
    local changed=1

    [[ -f "$main_exe" && -d "$frameworks_dir" ]] || return 0

    while [[ $changed -eq 1 && $pass -lt 10 ]]; do
        changed=0
        pass=$((pass + 1))

        local subject=""
        local dep=""
        local dep_target=""
        local dep_name=""
        local source_lib=""
        local bundled_lib=""
        local new_ref=""
        while IFS= read -r subject; do
            [[ -f "$subject" ]] || continue
            while IFS= read -r dep; do
                [[ -n "$dep" ]] || continue
                if is_macos_system_dylib "$dep"; then
                    continue
                fi

                dep_target=$(resolve_macos_bundle_dep_target "$dep" "$subject" "$main_exe_dir" "$frameworks_dir")
                if [[ -n "$dep_target" && -e "$dep_target" ]]; then
                    continue
                fi

                dep_name=$(basename "$dep")
                source_lib=$(find_macos_source_dylib "$dep_name" "${search_dirs[@]}" || true)
                [[ -n "$source_lib" ]] || continue

                bundled_lib="$frameworks_dir/$dep_name"
                if [[ ! -f "$bundled_lib" ]]; then
                    cp -f "$source_lib" "$bundled_lib"
                    chmod u+w "$bundled_lib" 2>/dev/null || true
                    install_name_tool -id "@executable_path/../Frameworks/$dep_name" "$bundled_lib" 2>/dev/null || true
                    changed=1
                fi

                if [[ "$subject" == "$main_exe" ]]; then
                    new_ref="@executable_path/../Frameworks/$dep_name"
                else
                    new_ref="@loader_path/$dep_name"
                fi
                install_name_tool -change "$dep" "$new_ref" "$subject" 2>/dev/null || true
            done < <(otool -L "$subject" 2>/dev/null | tail -n +2 | awk '{print $1}')
        done < <(
            printf '%s\n' "$main_exe"
            find "$frameworks_dir" -maxdepth 1 -type f -name '*.dylib' | sort
        )
    done
}

compile_linux_qt_launcher() {
    local output_path="$1"

    [[ -f "$QT_LINUX_LAUNCHER_SOURCE" ]] || {
        error "Linux Qt launcher source not found: $QT_LINUX_LAUNCHER_SOURCE"
        exit 1
    }

    # Ubuntu 20's default PIE launcher gets classified as application/x-sharedlib
    # in GNOME, so force a normal executable for release-click behavior.
    gcc -O2 -s -Wall -Wextra -no-pie "$QT_LINUX_LAUNCHER_SOURCE" -o "$output_path"
    chmod +x "$output_path"
}

compile_appimage_launcher() {
    local output_path="$1"

    [[ -f "$APPIMAGE_LAUNCHER_SOURCE" ]] || {
        error "AppImage launcher source not found: $APPIMAGE_LAUNCHER_SOURCE"
        exit 1
    }

    gcc -O2 -s -Wall -Wextra -no-pie "$APPIMAGE_LAUNCHER_SOURCE" -o "$output_path"
    chmod +x "$output_path"
}

write_linux_release_desktop() {
    local desktop_path="$1"

    cat > "$desktop_path" <<EOF
[Desktop Entry]
Type=Application
Name=Blakecoin Qt
Comment=Blakecoin Cryptocurrency Wallet
Exec=blakecoin-qt
Icon=blakecoin-qt
Terminal=false
Categories=Finance;Network;
EOF
}

write_linux_release_readme() {
    local readme_path="$1"
    local ubuntu_ver="$2"

    cat > "$readme_path" <<EOF
# Blakecoin v${VERSION} - Linux x86_64 (Ubuntu ${ubuntu_ver})

## Quick Start

Extract the release folder anywhere you like and run it in place. No system-wide install is required to use the wallet.

### Run the Qt wallet:
\`\`\`bash
./blakecoin-qt
\`\`\`

### Run the daemon:
\`\`\`bash
./blakecoind -daemon
./blakecoin-cli getinfo
\`\`\`

## Installation (optional)

### Copy daemon binaries:
\`\`\`bash
cp blakecoind blakecoin-cli blakecoin-tx ~/.local/bin/
\`\`\`

### Install the Qt wallet:
\`\`\`bash
mkdir -p ~/.local/opt/blakecoin-qt
cp -a blakecoin-qt .runtime ~/.local/opt/blakecoin-qt/
ln -sf ~/.local/opt/blakecoin-qt/blakecoin-qt ~/.local/bin/blakecoin-qt
\`\`\`

The hidden \`.runtime/\` folder must stay next to \`blakecoin-qt\`. The launcher will not start without it.

### Install desktop entry and icon:

This step only adds a Show Apps / application-menu launcher. It does not install the wallet by itself.
Run the Qt wallet install step above first so \`blakecoin-qt\` resolves from \`~/.local/bin/\` and the hidden \`.runtime/\` folder stays beside it.

\`\`\`bash
mkdir -p ~/.local/share/applications
mkdir -p ~/.local/share/icons/hicolor/256x256/apps
cp blakecoin.desktop ~/.local/share/applications/
cp blakecoin-256.png ~/.local/share/icons/hicolor/256x256/apps/blakecoin-qt.png

# Create index.theme if missing
if [ ! -f ~/.local/share/icons/hicolor/index.theme ]; then
    mkdir -p ~/.local/share/icons/hicolor
    echo -e "[Icon Theme]\\nName=Hicolor\\nComment=Fallback Icon Theme\\nDirectories=256x256/apps\\n\\n[256x256/apps]\\nSize=256\\nContext=Applications\\nType=Fixed" > ~/.local/share/icons/hicolor/index.theme
fi

gtk-update-icon-cache ~/.local/share/icons/hicolor/ 2>/dev/null || true
\`\`\`

## Configuration

On first run, a config file will be generated at \`~/.blakecoin/blakecoin.conf\` with random RPC credentials and peer nodes.

- P2P port: 8773
- RPC port: 8772

## Build Info

Built on Ubuntu ${ubuntu_ver}.
EOF
}

write_windows_release_readme() {
    local readme_path="$1"

    cat > "$readme_path" <<EOF
# Blakecoin v${VERSION} - Windows x86_64

## Quick Start

Extract the zip anywhere you like and run the executables in place.

### Run the Qt wallet:
\`\`\`powershell
.\blakecoin-qt-${VERSION}.exe
\`\`\`

### Run the daemon:
\`\`\`powershell
.\blakecoind-${VERSION}.exe -daemon
.\blakecoin-cli-${VERSION}.exe getinfo
\`\`\`

### Other tools:
\`\`\`powershell
.\blakecoin-tx-${VERSION}.exe -help
\`\`\`

## Notes

- These Windows executables are intended to be self-contained.
- No sidecar DLLs or plugin folders are required in the public release.

## Build Info

Built with MXE cross-build on Linux.
EOF
}

write_appimage_release_desktop() {
    local desktop_path="$1"

    cat > "$desktop_path" <<EOF
[Desktop Entry]
Type=Application
Name=Blakecoin Qt AppImage
Comment=Blakecoin Cryptocurrency Wallet (AppImage bundle)
Exec=${APPIMAGE_PUBLIC_NAME}
Icon=blakecoin-qt
Terminal=false
Categories=Finance;Network;
EOF
}

write_appimage_release_readme() {
    local readme_path="$1"

    cat > "$readme_path" <<EOF
# Blakecoin v${VERSION} - AppImage Bundle (Ubuntu 22+)

## Quick Start

Extract the release folder anywhere you like and run it in place.

### Run the wallet:
\`\`\`bash
./${APPIMAGE_PUBLIC_NAME}
\`\`\`

This launcher automatically:
- uses extract-and-run mode so fresh Ubuntu 22.04 and 24.04 installs do not need \`libfuse2\`
- forces XWayland-compatible Qt settings on Wayland sessions when needed
- starts the hidden AppImage payload from the bundled \`.runtime/\` folder

## Important Notes

- This AppImage bundle is intended for Ubuntu 22.04 and newer.
- Ubuntu 20.04 users should use the native Ubuntu 20 release instead.
- The hidden \`.runtime/\` folder must stay next to \`${APPIMAGE_PUBLIC_NAME}\`.

## Optional Desktop Integration

If you want a Show Apps launcher:

\`\`\`bash
mkdir -p ~/.local/opt/blakecoin-appimage
cp -a ${APPIMAGE_PUBLIC_NAME} .runtime ~/.local/opt/blakecoin-appimage/
mkdir -p ~/.local/share/applications
mkdir -p ~/.local/share/icons/hicolor/256x256/apps
cp blakecoin.desktop ~/.local/share/applications/
cp blakecoin-256.png ~/.local/share/icons/hicolor/256x256/apps/blakecoin-qt.png
\`\`\`

The desktop file assumes \`${APPIMAGE_PUBLIC_NAME}\` is on your path or in the same folder used for desktop integration.

## Build Info

Built on Ubuntu 22.04.
EOF
}

package_appimage_release_bundle() {
    local raw_appimage_path="$1"
    local launcher_path="$2"
    local release_root="$OUTPUT_BASE/release"
    local package_name="$APPIMAGE_RELEASE_DIR_NAME"
    local package_dir="$release_root/$package_name"
    local tar_path="$release_root/${APPIMAGE_RELEASE_ARCHIVE_NAME}"
    local legacy_tar_path="$release_root/blakecoin-v${VERSION}-appimage-ubuntu-22plus-x86_64.tar.gz"
    local stale_raw_release_path="$release_root/${APPIMAGE_PUBLIC_NAME}"
    local icon_source="$SCRIPT_DIR/src/qt/res/icons/bitcoin.png"

    [[ -f "$raw_appimage_path" ]] || {
        error "Raw AppImage not found for release bundle: $raw_appimage_path"
        exit 1
    }

    [[ -f "$launcher_path" ]] || {
        error "AppImage launcher not found for release bundle: $launcher_path"
        exit 1
    }

    rm -rf "$package_dir"
    mkdir -p "$package_dir/.runtime"

    cp "$launcher_path" "$package_dir/${APPIMAGE_PUBLIC_NAME}"
    cp "$raw_appimage_path" "$package_dir/.runtime/${APPIMAGE_PAYLOAD_NAME}"

    if [[ -f "$icon_source" ]]; then
        cp "$icon_source" "$package_dir/blakecoin-256.png"
    fi

    write_appimage_release_desktop "$package_dir/blakecoin.desktop"
    write_appimage_release_readme "$package_dir/README.md"

    rm -f "$tar_path" "$legacy_tar_path" "$stale_raw_release_path"
    (
        cd "$release_root"
        tar -czf "$tar_path" "$package_name"
    )

    success "AppImage release folder created: $package_dir"
    success "AppImage release archive created: $tar_path"
}

package_linux_release_from_native() {
    local ubuntu_ver="$1"
    local release_root="$OUTPUT_BASE/release"
    local package_name="blakecoin-v${VERSION}-ubuntu-${ubuntu_ver}-x86_64"
    local package_dir="$release_root/$package_name"
    local tar_path="$release_root/${package_name}.tar.gz"
    local native_daemon_dir="$OUTPUT_BASE/native/daemon"
    local native_qt_dir="$OUTPUT_BASE/native/qt"
    local runtime_source_dir="$native_qt_dir/.runtime"
    local qt_source_binary="$runtime_source_dir/${QT_NAME}-bin-${VERSION}"
    local icon_source="$SCRIPT_DIR/src/qt/res/icons/bitcoin.png"

    if [[ ! -x "$qt_source_binary" ]]; then
        warn "Skipping Linux release packaging: Qt runtime binary not found in $runtime_source_dir"
        return 0
    fi

    for source_file in \
        "$native_daemon_dir/${DAEMON_NAME}-${VERSION}" \
        "$native_daemon_dir/${CLI_NAME}-${VERSION}" \
        "$native_daemon_dir/${TX_NAME}-${VERSION}"; do
        if [[ ! -x "$source_file" ]]; then
            warn "Skipping Linux release packaging: daemon artifact missing ($source_file)"
            return 0
        fi
    done

    mkdir -p "$release_root"
    rm -rf "$package_dir" "$tar_path"
    mkdir -p "$package_dir/.runtime"

    cp "$native_daemon_dir/${DAEMON_NAME}-${VERSION}" "$package_dir/$DAEMON_NAME"
    cp "$native_daemon_dir/${CLI_NAME}-${VERSION}" "$package_dir/$CLI_NAME"
    cp "$native_daemon_dir/${TX_NAME}-${VERSION}" "$package_dir/$TX_NAME"
    cp -a "$runtime_source_dir/." "$package_dir/.runtime/"
    mv "$package_dir/.runtime/${QT_NAME}-bin-${VERSION}" "$package_dir/.runtime/${QT_NAME}-bin"

    compile_linux_qt_launcher "$package_dir/$QT_NAME"

    if [[ -f "$icon_source" ]]; then
        cp "$icon_source" "$package_dir/${COIN_NAME}-256.png"
    else
        warn "Release icon source not found: $icon_source"
    fi

    write_linux_release_desktop "$package_dir/${COIN_NAME}.desktop"
    write_linux_release_readme "$package_dir/README.md" "$ubuntu_ver"

    (
        cd "$package_dir"
        tar -czf "$tar_path" .
    )

    success "Linux release folder created: $package_dir"
    success "Linux release archive created: $tar_path"
}

package_windows_release_from_cross_build() {
    local output_dir="$1"
    local target="$2"
    local release_root="$OUTPUT_BASE/release"
    local zip_path="$release_root/${WINDOWS_RELEASE_ARCHIVE_NAME}"
    local stage_dir=""
    local qt_exe="$output_dir/qt/${QT_NAME}-${VERSION}.exe"
    local daemon_exe="$output_dir/daemon/${DAEMON_NAME}-${VERSION}.exe"
    local cli_exe="$output_dir/daemon/${CLI_NAME}-${VERSION}.exe"
    local tx_exe="$output_dir/daemon/${TX_NAME}-${VERSION}.exe"

    if [[ "$target" != "both" ]]; then
        info "Skipping Windows release archive: only generated for --both builds."
        return 0
    fi

    command -v zip >/dev/null 2>&1 || {
        error "zip command not found. Install zip on the build host to create the Windows release archive."
        exit 1
    }

    for required_file in "$qt_exe" "$daemon_exe" "$cli_exe" "$tx_exe"; do
        [[ -f "$required_file" ]] || {
            error "Windows release packaging requires: $required_file"
            exit 1
        }
    done

    mkdir -p "$release_root"
    stage_dir=$(mktemp -d)

    cp "$qt_exe" "$stage_dir/"
    cp "$daemon_exe" "$stage_dir/"
    cp "$cli_exe" "$stage_dir/"
    cp "$tx_exe" "$stage_dir/"
    write_windows_release_readme "$stage_dir/README.md"
    write_build_info "$stage_dir" "windows" "both" "Docker: $DOCKER_WINDOWS (MXE)"

    rm -f "$zip_path"
    (
        cd "$stage_dir"
        zip -q -r "$zip_path" \
            "README.md" \
            "build-info.txt" \
            "${QT_NAME}-${VERSION}.exe" \
            "${DAEMON_NAME}-${VERSION}.exe" \
            "${CLI_NAME}-${VERSION}.exe" \
            "${TX_NAME}-${VERSION}.exe"
    )

    rm -rf "$stage_dir"
    success "Windows release archive created: $zip_path"
}

bundle_linux_qt_runtime() {
    local qt_output_dir="$1"
    local launcher_path="$qt_output_dir/${QT_NAME}-${VERSION}"
    local runtime_dir="$qt_output_dir/.runtime"
    local binary_path="$runtime_dir/${QT_NAME}-bin-${VERSION}"
    local lib_dir="$runtime_dir/lib"
    local plugin_dir="$runtime_dir/plugins/platforms"
    local qt_plugin_root=""

    [[ -f "$launcher_path" ]] || return 0

    rm -rf "$runtime_dir"
    mkdir -p "$lib_dir" "$plugin_dir"
    mv "$launcher_path" "$binary_path"

    copy_runtime_libs "$binary_path" "$lib_dir"

    if command -v qtpaths >/dev/null 2>&1; then
        qt_plugin_root=$(qtpaths --plugin-dir 2>/dev/null || true)
    fi
    if [[ -z "$qt_plugin_root" ]] && command -v qmake >/dev/null 2>&1; then
        qt_plugin_root=$(qmake -query QT_INSTALL_PLUGINS 2>/dev/null || true)
    fi
    if [[ -z "$qt_plugin_root" ]] && [[ -d /usr/lib/x86_64-linux-gnu/qt5/plugins ]]; then
        qt_plugin_root="/usr/lib/x86_64-linux-gnu/qt5/plugins"
    fi

    if [[ -n "$qt_plugin_root" && -f "$qt_plugin_root/platforms/libqxcb.so" ]]; then
        cp -Lf "$qt_plugin_root/platforms/libqxcb.so" "$plugin_dir/"
        copy_runtime_libs "$plugin_dir/libqxcb.so" "$lib_dir"
    else
        warn "Qt platform plugin libqxcb.so not found; bundled launcher may still rely on system Qt plugins"
    fi

    cat > "$launcher_path" <<EOF
#!/bin/sh
set -e
APPDIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
export LD_LIBRARY_PATH="\$APPDIR/.runtime/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="\$APPDIR/.runtime/plugins\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}"
export QT_QPA_PLATFORM_PLUGIN_PATH="\$APPDIR/.runtime/plugins/platforms"
exec "\$APPDIR/.runtime/${QT_NAME}-bin-${VERSION}" "\$@"
EOF
    chmod +x "$launcher_path"
    info "Bundled Qt runtime libraries into $qt_output_dir/"
}

generate_config() {
    local conf_path="$OUTPUT_BASE/$CONFIG_FILE"
    if [[ -f "$conf_path" ]]; then
        info "Config already exists: $conf_path"
        return
    fi

    info "Generating $CONFIG_FILE..."
    local rpcuser rpcpassword peers=""
    rpcuser="rpcuser=$(LC_ALL=C head -c 100 /dev/urandom | LC_ALL=C tr -cd '[:alnum:]' | head -c 10)"
    rpcpassword="rpcpassword=$(LC_ALL=C head -c 200 /dev/urandom | LC_ALL=C tr -cd '[:alnum:]' | head -c 22)"

    # Fetch active peers from chainz cryptoid
    if command -v curl &>/dev/null; then
        local nodes
        nodes=$(curl -s "https://chainz.cryptoid.info/${CHAINZ_CODE}/api.dws?q=nodes" 2>/dev/null || true)
        if [[ -n "$nodes" ]]; then
            peers=$(grep -Eo '[0-9]{1,3}(\.[0-9]{1,3}){3}' <<< "$nodes" | grep -v '^0\.' | sed 's/^/addnode=/' || true)
        fi
    fi

    mkdir -p "$OUTPUT_BASE"
    cat > "$conf_path" <<EOF
maxconnections=20
$rpcuser
$rpcpassword
rpcallowip=0.0.0.0/0
rpcport=$RPC_PORT
port=$P2P_PORT
gen=0
$LISTEN
$DAEMON
$SERVER
$TXINDEX
$peers
EOF
    success "Config written: $conf_path"

    # Copy config to data directory if not already present
    local data_dir="$HOME/.${COIN_NAME}"
    mkdir -p "$data_dir"
    if [[ ! -f "$data_dir/$CONFIG_FILE" ]]; then
        cp "$conf_path" "$data_dir/$CONFIG_FILE"
        info "Config installed to $data_dir/$CONFIG_FILE"
    else
        info "Config already exists in $data_dir/ — not overwriting"
    fi
}

ensure_docker_image() {
    local image="$1"
    local docker_mode="$2"

    if [[ "$docker_mode" == "build" ]]; then
        # Use cached image if it exists, otherwise build from local Dockerfiles
        if docker image inspect "$image" >/dev/null 2>&1; then
            info "Image $image found locally (built)."
            return 0
        fi
        local docker_dir="$SCRIPT_DIR/docker"
        local dockerfile=""
        case "$image" in
            *native-base:20.04*)  dockerfile="Dockerfile.native-base-20.04" ;;
            *native-base:22.04*)  dockerfile="Dockerfile.native-base-22.04" ;;
            *native-base:24.04*)  dockerfile="Dockerfile.native-base-24.04" ;;
            *native-base*)        dockerfile="Dockerfile.native-base-22.04" ;;
            *appimage-base*)      dockerfile="Dockerfile.appimage-base" ;;
            *mxe-base*)           dockerfile="Dockerfile.mxe-base" ;;
            *osxcross-base*)      dockerfile="Dockerfile.osxcross-base" ;;
            *)
                error "Unknown image: $image"
                exit 1
                ;;
        esac
        if [[ -f "$docker_dir/$dockerfile" ]]; then
            info "Building $image from $dockerfile..."
            if docker build -t "$image" -f "$docker_dir/$dockerfile" "$docker_dir/"; then
                success "Built $image"
            else
                error "Failed to build $image from $dockerfile"
                exit 1
            fi
        else
            error "Dockerfile not found: $docker_dir/$dockerfile"
            error "Ensure docker/ directory contains the Dockerfiles."
            exit 1
        fi
        return 0
    fi

    # Pull mode — check local cache first
    if docker image inspect "$image" >/dev/null 2>&1; then
        info "Image $image found locally."
        return 0
    fi

    if [[ "$docker_mode" == "pull" ]]; then
        info "Pulling $image from Docker Hub..."
        if docker pull "$image"; then
            success "Pulled $image"
        else
            error "Failed to pull $image"
            error "Check https://hub.docker.com/r/${image%%:*}"
            error "Or use --build-docker to build from local Dockerfiles."
            exit 1
        fi
    else
        error "Docker is required for this build. Use --pull-docker or --build-docker"
        error "  --pull-docker   Pull prebuilt image from Docker Hub"
        error "  --build-docker  Build image locally from Dockerfiles in docker/"
        exit 1
    fi
}

# =============================================================================
# WINDOWS CROSS-COMPILE (Docker + MXE + autotools)
# Uses pre-built libs in mxe-base image — skips depends/ entirely
# =============================================================================

build_windows() {
    local target="$1"
    local jobs="$2"
    local docker_mode="$3"
    local container_name="win-${COIN_NAME}-0152-build"
    local output_dir="$OUTPUT_BASE/windows"

    echo ""
    echo "============================================"
    echo "  Windows Cross-Compile: $COIN_NAME_UPPER $VERSION"
    echo "============================================"
    echo "  Image:    $DOCKER_WINDOWS"
    echo "  Strategy: MXE + autotools (pre-built libs)"
    echo ""

    ensure_windows_icon_assets
    ensure_docker_image "$DOCKER_WINDOWS" "$docker_mode"
    mkdir -p "$output_dir/daemon" "$output_dir/qt"
    docker rm -f "$container_name" 2>/dev/null || true

    # Copy source to temp dir for volume-mount
    info "Copying source tree to temp build dir..."
    local tmpdir
    tmpdir=$(mktemp -d)
    cp -a "$SCRIPT_DIR"/. "$tmpdir/"
    rm -rf "$tmpdir/outputs" "$tmpdir/.git"
    fix_permissions "$tmpdir"

    # Build configure flags based on target
    local configure_extra=""
    case "$target" in
        daemon) configure_extra="--without-gui" ;;
        qt)     configure_extra="--with-gui=qt5" ;;
        both)   configure_extra="--with-gui=qt5" ;;
    esac

    docker create \
        --name "$container_name" \
        -v "$tmpdir:/build/$COIN_NAME:rw" \
        "$DOCKER_WINDOWS" \
        /bin/bash -c '
set -e
cd /build/'"$COIN_NAME"'

# MXE cross-compiler setup
export PATH=/opt/mxe/usr/bin:$PATH
HOST='"$WIN_HOST"'
MXE_SYSROOT=/opt/mxe/usr/${HOST}
export PATH="${MXE_SYSROOT}/qt5/bin:$PATH"

# Set pkg-config to find MXE target libraries (Qt5, libevent, protobuf)
export PKG_CONFIG_LIBDIR="${MXE_SYSROOT}/qt5/lib/pkgconfig:${MXE_SYSROOT}/lib/pkgconfig"

echo ">>> MXE environment:"
echo "    HOST=$HOST"
echo "    MXE_SYSROOT=$MXE_SYSROOT"
echo "    PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR"
echo "    Compat libs: /opt/compat/"
which ${HOST}-gcc || { echo "ERROR: Cross-compiler not found"; exit 1; }

# Restore MXE OpenSSL 3.x (Qt5 was compiled against it; compat has 1.1.1 which is incompatible)
echo ">>> Restoring MXE OpenSSL 3.x for Qt5 compatibility..."
rm -f /opt/compat/lib/libssl.a /opt/compat/lib/libcrypto.a
if [ -d ${MXE_SYSROOT}/include/openssl.mxe.bak ]; then
    rm -rf ${MXE_SYSROOT}/include/openssl
    cp -r ${MXE_SYSROOT}/include/openssl.mxe.bak ${MXE_SYSROOT}/include/openssl
fi
cp ${MXE_SYSROOT}/lib/mxe_bak/libssl.a ${MXE_SYSROOT}/lib/libssl.a
cp ${MXE_SYSROOT}/lib/mxe_bak/libcrypto.a ${MXE_SYSROOT}/lib/libcrypto.a

# Verify Qt5 is findable
pkg-config --cflags Qt5Core 2>/dev/null && echo ">>> Qt5Core found via pkg-config" || echo "WARNING: Qt5Core not found"

# Patch sources for Qt 5.15+ and Boost 1.73+ compatibility
echo ">>> Patching sources..."
if [ -f src/qt/trafficgraphwidget.cpp ]; then
    grep -q "#include <QPainterPath>" src/qt/trafficgraphwidget.cpp || \
        sed -i "1i #include <QPainterPath>" src/qt/trafficgraphwidget.cpp
fi
for f in $(grep -rl "boost::bind" src/ 2>/dev/null | grep "\.cpp$"); do
    grep -q "boost/bind.hpp" "$f" || \
        sed -i "1i #include <boost/bind.hpp>" "$f"
done

# Build Qt5 include flags (all module subdirs)
QT5INC="${MXE_SYSROOT}/qt5/include"
QT5_CPPFLAGS="-I${QT5INC}"
for qtmod in QtCore QtGui QtWidgets QtNetwork QtDBus; do
    [ -d "${QT5INC}/${qtmod}" ] && QT5_CPPFLAGS="${QT5_CPPFLAGS} -I${QT5INC}/${qtmod}"
done
echo ">>> Qt5 include flags: $QT5_CPPFLAGS"

# Create Qt5PlatformSupport merged lib (split into multiple libs in Qt 5.14+)
QT5LIBDIR="${MXE_SYSROOT}/qt5/lib"
if [ ! -f "${QT5LIBDIR}/libQt5PlatformSupport.a" ]; then
    echo ">>> Creating merged Qt5PlatformSupport.a from split modules..."
    _qt5ps_save_dir=$(pwd)
    mkdir -p /tmp/qt5ps && cd /tmp/qt5ps
    for lib in EventDispatcherSupport FontDatabaseSupport ThemeSupport AccessibilitySupport WindowsUIAutomationSupport; do
        [ -f "${QT5LIBDIR}/libQt5${lib}.a" ] && ar x "${QT5LIBDIR}/libQt5${lib}.a"
    done
    ar crs "${QT5LIBDIR}/libQt5PlatformSupport.a" *.o 2>/dev/null || ar crs "${QT5LIBDIR}/libQt5PlatformSupport.a"
    cd "$_qt5ps_save_dir" && rm -rf /tmp/qt5ps
    cat > "${QT5LIBDIR}/pkgconfig/Qt5PlatformSupport.pc" <<PCEOF
Name: Qt5PlatformSupport
Description: Merged compat lib for Qt 5.14+ (split into separate modules)
Version: 5.15
Cflags:
Libs: -L${QT5LIBDIR} -lQt5PlatformSupport -lQt5EventDispatcherSupport -lQt5FontDatabaseSupport -lQt5ThemeSupport -lQt5AccessibilitySupport
PCEOF
fi

echo ">>> Running autogen.sh..."
./autogen.sh

# Patch configure to skip static Qt plugin link tests (deps too complex for configure)
# The actual make build handles Qt5 plugin deps correctly via .prl files
echo ">>> Patching configure to skip Qt static plugin link tests..."
sed -i "/as_fn_error.*Could not resolve/s/as_fn_error/true #/" configure

echo ">>> Configuring for Windows ($HOST)..."
./configure --host=$HOST --prefix=/usr/local \
    --disable-tests --disable-bench \
    --with-qt-plugindir=${MXE_SYSROOT}/qt5/plugins \
    --with-boost=/opt/compat \
    --with-boost-libdir=/opt/compat/lib \
    '"$configure_extra"' \
    CXXFLAGS="-O2 -DWIN32 -DMINIUPNP_STATICLIB -DBOOST_BIND_GLOBAL_PLACEHOLDERS" \
    CFLAGS="-O2 -DWIN32" \
    CPPFLAGS="-I/opt/compat/include ${QT5_CPPFLAGS}" \
    LDFLAGS="-L/opt/compat/lib -L${MXE_SYSROOT}/lib -L${MXE_SYSROOT}/qt5/lib -static" \
    BDB_CFLAGS="-I/opt/compat/include" \
    BDB_LIBS="-L/opt/compat/lib -ldb_cxx-4.8 -ldb-4.8" \
    PROTOC=/opt/mxe/usr/x86_64-pc-linux-gnu/bin/protoc

# Fix missing Qt translation files (Blakecoin fork does not include them)
if [ -f src/Makefile ]; then
    sed -i "s/^QT_QM.*=.*/QT_QM =/" src/Makefile
    sed -i "/bitcoin_.*\.qm/d" src/Makefile
    sed -i "/locale\/.*\.qm/d" src/Makefile
fi
mkdir -p src/qt
cat > src/qt/bitcoin_locale.qrc <<QRC_EOF
<!DOCTYPE RCC><RCC version="1.0">
<qresource prefix="/translations">
</qresource>
</RCC>
QRC_EOF

# Fix static link deps: use --start-group to resolve circular Qt5/platform plugin deps
if [ -f src/Makefile ]; then
    echo ">>> Fixing static link dependencies (--start-group for circular deps)..."
    sed -i "s|^LIBS = \(.*\)|LIBS = -Wl,--start-group \1 -L${MXE_SYSROOT}/qt5/plugins/platforms -lqwindows -L${MXE_SYSROOT}/qt5/lib -lQt5Widgets -lQt5Gui -lQt5Network -lQt5Core -lQt5PlatformSupport -lQt5AccessibilitySupport -lQt5WindowsUIAutomationSupport -lQt5EventDispatcherSupport -lQt5FontDatabaseSupport -lQt5ThemeSupport -lharfbuzz -lfreetype -lharfbuzz_too -lfreetype_too -lbz2 -lpng16 -lbrotlidec -lbrotlicommon -lglib-2.0 -lintl -liconv -lpcre2-8 -lpcre2-16 -lzstd -lssl -lcrypto -ld3d11 -ldxgi -ldxguid -luxtheme -ldwmapi -ldnsapi -liphlpapi -lcrypt32 -lmpr -luserenv -lnetapi32 -lversion -lcomdlg32 -loleaut32 -limm32 -lshlwapi -latomic -lz -lws2_32 -lgdi32 -luser32 -lkernel32 -ladvapi32 -lole32 -lshell32 -luuid -lwinmm -lrpcrt4 -lssp -lwinspool -lcomctl32 -lwtsapi32 -lm -Wl,--end-group|" src/Makefile
fi

echo ">>> Building..."
make -j'"$jobs"'

echo ">>> Stripping binaries..."
${HOST}-strip src/blakecoind.exe 2>/dev/null || true
${HOST}-strip src/qt/blakecoin-qt.exe 2>/dev/null || true
${HOST}-strip src/blakecoin-cli.exe 2>/dev/null || true
${HOST}-strip src/blakecoin-tx.exe 2>/dev/null || true

echo ">>> Build complete!"
ls -lh src/blakecoind.exe src/qt/blakecoin-qt.exe src/blakecoin-cli.exe src/blakecoin-tx.exe 2>/dev/null || true
'

    info "Starting build container: $container_name"
    docker start -a "$container_name"

    # Extract binaries
    if [[ "$target" == "daemon" || "$target" == "both" ]]; then
        info "Extracting daemon binaries..."
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoind.exe" "$output_dir/daemon/blakecoind-${VERSION}.exe" 2>/dev/null || true
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoin-cli.exe" "$output_dir/daemon/blakecoin-cli-${VERSION}.exe" 2>/dev/null || true
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoin-tx.exe" "$output_dir/daemon/blakecoin-tx-${VERSION}.exe" 2>/dev/null || true
        write_build_info "$output_dir/daemon" "windows" "daemon" "Docker: $DOCKER_WINDOWS (MXE)"
    fi

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        info "Extracting Qt wallet..."
        docker cp "$container_name:/build/$COIN_NAME/src/qt/blakecoin-qt.exe" "$output_dir/qt/blakecoin-qt-${VERSION}.exe" 2>/dev/null || true
        write_build_info "$output_dir/qt" "windows" "qt" "Docker: $DOCKER_WINDOWS (MXE)"
    fi

    package_windows_release_from_cross_build "$output_dir" "$target"

    docker rm -f "$container_name" 2>/dev/null || true
    docker run --rm -v "$tmpdir:/cleanup" alpine rm -rf /cleanup 2>/dev/null || rm -rf "$tmpdir" 2>/dev/null || true

    echo ""
    echo "============================================"
    echo "  BUILD SUCCESSFUL — Windows"
    echo "  Output: $output_dir/"
    if [[ "$target" == "both" ]]; then
        echo "  Release: $OUTPUT_BASE/release/${WINDOWS_RELEASE_ARCHIVE_NAME}"
    fi
    echo "============================================"
    ls -lh "$output_dir"/daemon/*.exe "$output_dir"/qt/*.exe 2>/dev/null || true
}

# =============================================================================
# macOS CROSS-COMPILE (Docker + osxcross + autotools)
# Uses pre-built libs in osxcross-base image — skips depends/ entirely
# =============================================================================

build_macos_cross() {
    local target="$1"
    local jobs="$2"
    local docker_mode="$3"
    local container_name="mac-${COIN_NAME}-0152-build"
    local output_dir="$OUTPUT_BASE/macos"

    echo ""
    echo "============================================"
    echo "  macOS Cross-Compile: $COIN_NAME_UPPER $VERSION"
    echo "============================================"
    echo "  Image:    $DOCKER_MACOS"
    echo "  Strategy: osxcross + autotools (pre-built libs)"
    echo ""

    ensure_docker_image "$DOCKER_MACOS" "$docker_mode"
    mkdir -p "$output_dir/daemon" "$output_dir/qt"
    docker rm -f "$container_name" 2>/dev/null || true

    # Copy source to temp dir
    info "Copying source tree to temp build dir..."
    local tmpdir
    tmpdir=$(mktemp -d)
    cp -a "$SCRIPT_DIR"/. "$tmpdir/"
    rm -rf "$tmpdir/outputs" "$tmpdir/.git"
    fix_permissions "$tmpdir"

    local configure_extra=""
    case "$target" in
        daemon) configure_extra="--without-gui" ;;
        qt)     configure_extra="--with-gui=qt5" ;;
        both)   configure_extra="--with-gui=qt5" ;;
    esac

    docker create \
        --name "$container_name" \
        -v "$tmpdir:/build/$COIN_NAME:rw" \
        "$DOCKER_MACOS" \
        /bin/bash -c '
set -e
cd /build/'"$COIN_NAME"'

# osxcross toolchain setup
export PATH=/opt/osxcross/target/bin:$PATH
export PREFIX=/opt/osxcross/target/macports/pkgs/opt/local
# Auto-detect darwin version from available toolchain
HOST=$(ls /opt/osxcross/target/bin/ | grep -oP "x86_64-apple-darwin[0-9.]+" | head -1)
if [ -z "$HOST" ]; then echo "ERROR: Could not detect osxcross HOST triplet"; exit 1; fi

echo ">>> osxcross environment:"
echo "    HOST=$HOST"
echo "    PREFIX=$PREFIX"
echo "    CC=${HOST}-clang"
echo "    CXX=${HOST}-clang++"
which ${HOST}-clang++ || { echo "ERROR: Cross-compiler not found"; exit 1; }

# --- Cross-compile libevent (missing from osxcross-base, needed by 0.15.2) ---
echo ">>> Cross-compiling libevent..."
cd /tmp
curl -LO https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz
tar xf libevent-2.1.12-stable.tar.gz
cd libevent-2.1.12-stable
./configure --host=$HOST --prefix=$PREFIX \
    --disable-shared --enable-static \
    --disable-openssl --disable-samples --disable-libevent-regress \
    CC=${HOST}-clang CXX=${HOST}-clang++ \
    CFLAGS="-mmacosx-version-min=11.0" \
    CXXFLAGS="-mmacosx-version-min=11.0"
make -j'"$jobs"'
make install
echo ">>> libevent installed to $PREFIX"

# --- Cross-compile protobuf (needed for Qt/BIP70) ---
echo ">>> Cross-compiling protobuf..."
apt-get update -qq && apt-get install -y -qq protobuf-compiler > /dev/null 2>&1
cd /tmp
curl -LO https://github.com/protocolbuffers/protobuf/releases/download/v3.12.4/protobuf-cpp-3.12.4.tar.gz
tar xf protobuf-cpp-3.12.4.tar.gz
cd protobuf-3.12.4
./configure --host=$HOST --prefix=$PREFIX \
    --disable-shared --enable-static \
    --with-protoc=/usr/bin/protoc \
    CC=${HOST}-clang CXX=${HOST}-clang++ \
    CFLAGS="-mmacosx-version-min=11.0" \
    CXXFLAGS="-stdlib=libc++ -mmacosx-version-min=11.0" \
    LDFLAGS="-stdlib=libc++"
make -j'"$jobs"'
make install
echo ">>> protobuf installed to $PREFIX"

# --- Build Blakecoin ---
cd /build/'"$COIN_NAME"'

# Patch sources for Qt 5.15+ and Boost 1.73+ compatibility
echo ">>> Patching sources..."
if [ -f src/qt/trafficgraphwidget.cpp ]; then
    grep -q "#include <QPainterPath>" src/qt/trafficgraphwidget.cpp || \
        sed -i "1i #include <QPainterPath>" src/qt/trafficgraphwidget.cpp
fi
for f in $(grep -rl "boost::bind" src/ 2>/dev/null | grep "\.cpp$"); do
    grep -q "boost/bind.hpp" "$f" || \
        sed -i "1i #include <boost/bind.hpp>" "$f"
done

# Use system pkg-config instead of osxcross wrapper (which ignores PKG_CONFIG_PATH)
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_LIBDIR="$PREFIX/qt5/lib/pkgconfig:$PREFIX/lib/pkgconfig"
echo ">>> Using system pkg-config with PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR"
pkg-config --cflags Qt5Core 2>/dev/null && echo ">>> Qt5Core found" || echo "WARNING: Qt5Core not found"

# Build Qt5 include flags (all module subdirs)
QT5INC="$PREFIX/qt5/include"
QT5_CPPFLAGS="-I${QT5INC}"
for qtmod in QtCore QtGui QtWidgets QtNetwork QtDBus; do
    [ -d "${QT5INC}/${qtmod}" ] && QT5_CPPFLAGS="${QT5_CPPFLAGS} -I${QT5INC}/${qtmod}"
done
echo ">>> Qt5 include flags: $QT5_CPPFLAGS"

# Create Qt5PlatformSupport merged lib (split into multiple libs in Qt 5.14+)
QT5LIBDIR="$PREFIX/qt5/lib"
if [ ! -f "${QT5LIBDIR}/libQt5PlatformSupport.a" ]; then
    echo ">>> Creating merged Qt5PlatformSupport.a from split modules..."
    _qt5ps_save_dir=$(pwd)
    mkdir -p /tmp/qt5ps && cd /tmp/qt5ps
    for lib in EventDispatcherSupport FontDatabaseSupport ThemeSupport AccessibilitySupport ClipboardSupport GraphicsSupport ServiceSupport; do
        [ -f "${QT5LIBDIR}/libQt5${lib}.a" ] && ar x "${QT5LIBDIR}/libQt5${lib}.a" 2>/dev/null || true
    done
    ar crs "${QT5LIBDIR}/libQt5PlatformSupport.a" *.o 2>/dev/null || true
    cd "$_qt5ps_save_dir" && rm -rf /tmp/qt5ps
    cat > "${QT5LIBDIR}/pkgconfig/Qt5PlatformSupport.pc" <<PCEOF
Name: Qt5PlatformSupport
Description: Merged compat lib for Qt 5.14+ (split into separate modules)
Version: 5.15
Cflags:
Libs: -L${QT5LIBDIR} -lQt5PlatformSupport -lQt5EventDispatcherSupport -lQt5FontDatabaseSupport -lQt5ThemeSupport -lQt5AccessibilitySupport -lQt5ClipboardSupport -lQt5GraphicsSupport
PCEOF
fi

echo ">>> Creating Boost -mt symlinks (configure looks for suffixed versions)..."
for lib in $PREFIX/lib/libboost_*.a; do
    mt="${lib%.a}-mt.a"
    [ ! -f "$mt" ] && ln -sf "$(basename "$lib")" "$mt"
done

echo ">>> Running autogen.sh..."
./autogen.sh

# Patch configure to skip static Qt plugin link tests (deps too complex for configure)
echo ">>> Patching configure to skip Qt static plugin link tests..."
sed -i "/as_fn_error.*Could not resolve/s/as_fn_error/true #/" configure

echo ">>> Configuring for macOS ($HOST)..."
./configure --host=$HOST --prefix=/usr/local \
    --disable-tests --disable-bench --disable-zmq \
    --with-qt-plugindir=$PREFIX/qt5/plugins \
    --with-boost=$PREFIX \
    --with-boost-libdir=$PREFIX/lib \
    '"$configure_extra"' \
    CC=${HOST}-clang \
    CXX=${HOST}-clang++ \
    CXXFLAGS="-stdlib=libc++ -O2 -mmacosx-version-min=11.0 -DBOOST_BIND_GLOBAL_PLACEHOLDERS -DOBJC_OLD_DISPATCH_PROTOTYPES=1" \
    CFLAGS="-O2 -mmacosx-version-min=11.0 -DOBJC_OLD_DISPATCH_PROTOTYPES=1" \
    OBJCXXFLAGS="-stdlib=libc++ -O2 -mmacosx-version-min=11.0 -DOBJC_OLD_DISPATCH_PROTOTYPES=1" \
    OBJCFLAGS="-O2 -mmacosx-version-min=11.0 -DOBJC_OLD_DISPATCH_PROTOTYPES=1" \
    LDFLAGS="-L$PREFIX/lib -L$PREFIX/qt5/lib -stdlib=libc++ -mmacosx-version-min=11.0" \
    CPPFLAGS="-I$PREFIX/include ${QT5_CPPFLAGS}" \
    BDB_CFLAGS="-I$PREFIX/include" \
    BDB_LIBS="-L$PREFIX/lib -ldb_cxx-4.8 -ldb-4.8" \
    PKG_CONFIG=/usr/bin/pkg-config \
    PROTOC=/usr/bin/protoc

# Fix missing Qt translation files (Blakecoin fork does not include them)
if [ -f src/Makefile ]; then
    sed -i "s/^QT_QM.*=.*/QT_QM =/" src/Makefile
    sed -i "/bitcoin_.*\.qm/d" src/Makefile
    sed -i "/locale\/.*\.qm/d" src/Makefile
fi
mkdir -p src/qt
cat > src/qt/bitcoin_locale.qrc <<QRC_EOF
<!DOCTYPE RCC><RCC version="1.0">
<qresource prefix="/translations">
</qresource>
</RCC>
QRC_EOF

# Fix static link deps: Qt5 Cocoa plugin + platform support + bundled Qt libs + macOS frameworks
if [ -f src/Makefile ]; then
    echo ">>> Fixing static link dependencies (frameworks + Qt plugins)..."
    sed -i "s|^LIBS = \(.*\)|LIBS = \1 -L$PREFIX/qt5/plugins/platforms -lqcocoa -L$PREFIX/qt5/lib -lQt5PrintSupport -lQt5Widgets -lQt5Gui -lQt5Network -lQt5Core -lQt5MacExtras -lQt5PlatformSupport -lQt5AccessibilitySupport -lQt5ClipboardSupport -lQt5EventDispatcherSupport -lQt5FontDatabaseSupport -lQt5GraphicsSupport -lQt5ServiceSupport -lQt5ThemeSupport $PREFIX/qt5/lib/libqtfreetype.a $PREFIX/qt5/lib/libqtharfbuzz.a $PREFIX/qt5/lib/libqtlibpng.a $PREFIX/qt5/lib/libqtpcre2.a -lz -lbz2 -lcups -framework SystemConfiguration -framework GSS -framework Carbon -framework IOKit -framework IOSurface -framework CoreVideo -framework Metal -framework QuartzCore -framework Cocoa -framework CoreGraphics -framework CoreText -framework CoreFoundation -framework Security -framework DiskArbitration -framework AppKit -framework ApplicationServices -framework Foundation -framework CoreServices|" src/Makefile
fi

echo ">>> Building..."
make -j'"$jobs"'

echo ">>> Stripping binaries..."
${HOST}-strip src/blakecoind 2>/dev/null || true
${HOST}-strip src/blakecoin-cli 2>/dev/null || true
${HOST}-strip src/blakecoin-tx 2>/dev/null || true
if [[ "'"$target"'" == "qt" || "'"$target"'" == "both" ]]; then
    ${HOST}-strip src/qt/blakecoin-qt 2>/dev/null || true
fi

APP_NAME="Blakecoin-Qt.app"
if [[ "'"$target"'" == "qt" || "'"$target"'" == "both" ]]; then
echo ">>> Creating macOS .app bundle..."
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"
cp src/qt/blakecoin-qt "$APP_NAME/Contents/MacOS/Blakecoin-Qt"

# Generate .icns icon from bitcoin.png
ICONS_DIR="src/qt/res/icons"
if [ -f "$ICONS_DIR/bitcoin.png" ]; then
    echo ">>> Generating macOS icon from bitcoin.png..."
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq python3-pil >/dev/null 2>&1 || true
    python3 -c "
from PIL import Image
img = Image.open('"'"'$ICONS_DIR/bitcoin.png'"'"')
img.save('"'"'$APP_NAME/Contents/Resources/blakecoin.icns'"'"')
print('"'"'    Icon generated'"'"')
" 2>/dev/null || echo "    Warning: Pillow icon conversion failed"
fi

# Create Info.plist
cat > "$APP_NAME/Contents/Info.plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Blakecoin-Qt</string>
    <key>CFBundleIdentifier</key>
    <string>org.blakecoin.Blakecoin-Qt</string>
    <key>CFBundleName</key>
    <string>Blakecoin-Qt</string>
    <key>CFBundleDisplayName</key>
    <string>Blakecoin Core</string>
    <key>CFBundleVersion</key>
    <string>'"$VERSION"'</string>
    <key>CFBundleShortVersionString</key>
    <string>'"$VERSION"'</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>blakecoin</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>10.14</string>
</dict>
</plist>
PLIST_EOF
fi

echo ">>> Build complete!"
ls -lh src/blakecoind src/qt/blakecoin-qt src/blakecoin-cli src/blakecoin-tx 2>/dev/null || true
if [[ "'"$target"'" == "qt" || "'"$target"'" == "both" ]]; then
    ls -lh "$APP_NAME/Contents/MacOS/" 2>/dev/null || true
fi
'

    info "Starting build container: $container_name"
    docker start -a "$container_name"

    # Extract binaries
    if [[ "$target" == "daemon" || "$target" == "both" ]]; then
        info "Extracting daemon binaries..."
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoind" "$output_dir/daemon/blakecoind-${VERSION}" 2>/dev/null || true
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoin-cli" "$output_dir/daemon/blakecoin-cli-${VERSION}" 2>/dev/null || true
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoin-tx" "$output_dir/daemon/blakecoin-tx-${VERSION}" 2>/dev/null || true
        write_build_info "$output_dir/daemon" "macos" "daemon" "Docker: $DOCKER_MACOS (osxcross)"
    fi

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        info "Extracting Qt wallet (.app bundle)..."
        local app_name="Blakecoin-Qt.app"
        rm -rf "$output_dir/qt/$app_name" 2>/dev/null || true
        if docker cp "$container_name:/build/$COIN_NAME/$app_name" "$output_dir/qt/$app_name" 2>/dev/null; then
            # Ensure binary inside .app is executable (docker cp can lose +x)
            find "$output_dir/qt/$app_name" -path "*/Contents/MacOS/*" -type f -exec chmod +x {} + 2>/dev/null || true
            success "macOS app bundle extracted to $output_dir/qt/"
            ls -lh "$output_dir/qt/$app_name/Contents/MacOS/" 2>/dev/null || true
        else
            error "Could not find .app bundle in container"
            docker exec "$container_name" find /build/$COIN_NAME -name "*.app" -type d 2>/dev/null || true
        fi
        # Also copy raw binary for convenience
        docker cp "$container_name:/build/$COIN_NAME/src/qt/blakecoin-qt" "$output_dir/qt/blakecoin-qt-${VERSION}" 2>/dev/null || true
        write_build_info "$output_dir/qt" "macos" "qt" "Docker: $DOCKER_MACOS (osxcross)"
    fi

    docker rm -f "$container_name" 2>/dev/null || true
    docker run --rm -v "$tmpdir:/cleanup" alpine rm -rf /cleanup 2>/dev/null || rm -rf "$tmpdir" 2>/dev/null || true

    echo ""
    echo "============================================"
    echo "  BUILD SUCCESSFUL — macOS"
    echo "  Output: $output_dir/"
    echo "============================================"
    ls -lh "$output_dir"/daemon/* "$output_dir"/qt/* 2>/dev/null || true
}

# =============================================================================
# APPIMAGE BUILD (Docker + autotools + AppDir packaging)
# =============================================================================

build_appimage() {
    local jobs="$1"
    local docker_mode="$2"
    local container_name="appimage-${COIN_NAME}-0152-build"
    local output_dir="$OUTPUT_BASE/linux-appimage/qt"
    local raw_appimage_path="$output_dir/${APPIMAGE_PUBLIC_NAME}"
    local launcher_path="$output_dir/${COIN_NAME}-appimage-launcher"

    echo ""
    echo "============================================"
    echo "  AppImage Build: $COIN_NAME_UPPER 0.15.2"
    echo "============================================"
    echo "  Image:  $DOCKER_APPIMAGE"
    echo ""

    ensure_docker_image "$DOCKER_APPIMAGE" "$docker_mode"
    mkdir -p "$output_dir"
    docker rm -f "$container_name" 2>/dev/null || true

    # Copy source to temp dir
    info "Copying source tree to temp build dir..."
    local tmpdir
    tmpdir=$(mktemp -d)
    cp -a "$SCRIPT_DIR"/. "$tmpdir/"
    rm -rf "$tmpdir/outputs" "$tmpdir/.git"
    fix_permissions "$tmpdir"

    docker create \
        --name "$container_name" \
        -v "$tmpdir:/build/$COIN_NAME:rw" \
        "$DOCKER_APPIMAGE" \
        /bin/bash -c '
set -e
cd /build/'"$COIN_NAME"'

# Patch sources for Qt 5.15+ and Boost 1.73+ compatibility
echo ">>> Patching sources for Ubuntu 22.04 compatibility..."
if [ -f src/qt/trafficgraphwidget.cpp ]; then
    grep -q "#include <QPainterPath>" src/qt/trafficgraphwidget.cpp || \
        sed -i "1i #include <QPainterPath>" src/qt/trafficgraphwidget.cpp
fi
for f in $(grep -rl "boost::bind" src/ 2>/dev/null | grep "\.cpp$"); do
    grep -q "boost/bind.hpp" "$f" || \
        sed -i "1i #include <boost/bind.hpp>" "$f"
done

echo ">>> Building Qt wallet with autotools..."
./autogen.sh
./configure --disable-tests --disable-bench --enable-upnp-default \
    CXXFLAGS="-O2 -DBOOST_BIND_GLOBAL_PLACEHOLDERS" LDFLAGS="-static-libstdc++"

# Fix missing Qt translation files (Blakecoin fork does not include them)
if [ -f src/Makefile ]; then
    sed -i "s/^QT_QM.*=.*/QT_QM =/" src/Makefile
    sed -i "/bitcoin_.*\.qm/d" src/Makefile
    sed -i "/locale\/.*\.qm/d" src/Makefile
fi
mkdir -p src/qt
cat > src/qt/bitcoin_locale.qrc <<QRC_EOF
<!DOCTYPE RCC><RCC version="1.0">
<qresource prefix="/translations">
</qresource>
</RCC>
QRC_EOF

make -j'"$jobs"'

QT_BIN="src/qt/'"$QT_NAME"'"
if [ ! -f "$QT_BIN" ]; then
    echo "ERROR: Could not find built Qt binary at $QT_BIN"
    find src -name "*qt*" -type f 2>/dev/null
    exit 1
fi
strip "$QT_BIN"

echo ">>> Creating AppDir..."
APPDIR=/build/appdir
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/plugins" \
    "$APPDIR/usr/share/glib-2.0/schemas" "$APPDIR/etc"

cp "$QT_BIN" "$APPDIR/usr/bin/'"$QT_NAME"'"

# Bundle Qt plugins
QT_PLUGIN_DIR=""
for p in /usr/lib/x86_64-linux-gnu/qt5/plugins /usr/lib/qt5/plugins /usr/lib64/qt5/plugins; do
    [ -d "$p" ] && QT_PLUGIN_DIR="$p" && break
done
if [ -n "$QT_PLUGIN_DIR" ]; then
    cp -r "$QT_PLUGIN_DIR/platforms" "$APPDIR/usr/plugins/" 2>/dev/null || true
    for plugin_type in platformthemes platforminputcontexts imageformats; do
        if [ -d "$QT_PLUGIN_DIR/$plugin_type" ]; then
            mkdir -p "$APPDIR/usr/plugins/$plugin_type"
            cp -r "$QT_PLUGIN_DIR/$plugin_type/"* "$APPDIR/usr/plugins/$plugin_type/" 2>/dev/null || true
        fi
    done
fi

# Bundle shared libraries (ldd-based)
echo ">>> Bundling shared libraries..."
for bin in "$APPDIR"/usr/bin/*; do
    [ -f "$bin" ] || continue
    ldd "$bin" 2>/dev/null | grep "=>" | awk "{print \$3}" | grep -v "^\$" | while read -r lib; do
        [ -z "$lib" ] || [ ! -f "$lib" ] && continue
        lib_name=$(basename "$lib")
        case "$lib_name" in
            libc.so*|libdl.so*|libpthread.so*|libm.so*|librt.so*|libgcc_s.so*|libstdc++.so*|ld-linux*)
                ;;
            libfontconfig.so*|libfreetype.so*)
                ;;
            *)
                cp -nL "$lib" "$APPDIR/usr/lib/" 2>/dev/null || true
                ;;
        esac
    done
done

# Bundle Qt plugin dependencies
echo ">>> Bundling Qt plugin dependencies..."
find "$APPDIR/usr/plugins" -name "*.so" 2>/dev/null | while read -r plugin; do
    ldd "$plugin" 2>/dev/null | grep "=>" | awk "{print \$3}" | grep -v "^\$" | while read -r plib; do
        [ -z "$plib" ] || [ ! -f "$plib" ] && continue
        plib_name=$(basename "$plib")
        case "$plib_name" in
            libc.so*|libdl.so*|libpthread.so*|libm.so*|librt.so*|libgcc_s.so*|libstdc++.so*|ld-linux*)
                ;;
            libfontconfig.so*|libfreetype.so*)
                ;;
            *)
                cp -nL "$plib" "$APPDIR/usr/lib/" 2>/dev/null || true
                ;;
        esac
    done
done

# Remove GTK3-related libs (segfault with newer host themes)
rm -f "$APPDIR/usr/lib/libgtk-3.so"* "$APPDIR/usr/lib/libgdk-3.so"*
rm -f "$APPDIR/usr/lib/libatk-bridge-2.0.so"* "$APPDIR/usr/lib/libatspi.so"*
rm -f "$APPDIR/usr/lib/libepoxy.so"*
rm -f "$APPDIR/usr/plugins/platformthemes/libqgtk3.so" 2>/dev/null || true

# Create qt.conf
cat > "$APPDIR/usr/bin/qt.conf" << '\''QTCONF'\''
[Paths]
Plugins = ../plugins
QTCONF

# GSettings schema (cross-Ubuntu compatibility)
SCHEMA_DIR="$APPDIR/usr/share/glib-2.0/schemas"
cat > "$SCHEMA_DIR/org.gnome.settings-daemon.plugins.xsettings.gschema.xml" << '\''SCHEMA_EOF'\''
<?xml version="1.0" encoding="UTF-8"?>
<schemalist>
  <enum id="org.gnome.settings-daemon.GsdFontAntialiasingMode">
    <value nick="none" value="0"/>
    <value nick="grayscale" value="1"/>
    <value nick="rgba" value="2"/>
  </enum>
  <enum id="org.gnome.settings-daemon.GsdFontHinting">
    <value nick="none" value="0"/>
    <value nick="slight" value="1"/>
    <value nick="medium" value="2"/>
    <value nick="full" value="3"/>
  </enum>
  <enum id="org.gnome.settings-daemon.GsdFontRgbaOrder">
    <value nick="rgba" value="0"/>
    <value nick="rgb" value="1"/>
    <value nick="bgr" value="2"/>
    <value nick="vrgb" value="3"/>
    <value nick="vbgr" value="4"/>
  </enum>
  <schema gettext-domain="gnome-settings-daemon" id="org.gnome.settings-daemon.plugins.xsettings" path="/org/gnome/settings-daemon/plugins/xsettings/">
    <key name="disabled-gtk-modules" type="as">
      <default>[]</default>
    </key>
    <key name="enabled-gtk-modules" type="as">
      <default>[]</default>
    </key>
    <key type="a{sv}" name="overrides">
      <default>{}</default>
    </key>
    <key name="antialiasing" enum="org.gnome.settings-daemon.GsdFontAntialiasingMode">
      <default>'\''grayscale'\''</default>
    </key>
    <key name="hinting" enum="org.gnome.settings-daemon.GsdFontHinting">
      <default>'\''slight'\''</default>
    </key>
    <key name="rgba-order" enum="org.gnome.settings-daemon.GsdFontRgbaOrder">
      <default>'\''rgb'\''</default>
    </key>
  </schema>
</schemalist>
SCHEMA_EOF
glib-compile-schemas "$SCHEMA_DIR" 2>/dev/null || echo "WARNING: glib-compile-schemas failed"

# Minimal OpenSSL config
mkdir -p "$APPDIR/etc"
cat > "$APPDIR/etc/openssl.cnf" << '\''SSL_EOF'\''
openssl_conf = openssl_init
[openssl_init]
ssl_conf = ssl_sect
[ssl_sect]
system_default = system_default_sect
[system_default_sect]
MinProtocol = TLSv1.2
SSL_EOF

# Desktop file
cat > "$APPDIR/'"$COIN_NAME"'.desktop" << '\''DESKTOP_EOF'\''
[Desktop Entry]
Type=Application
Name='"$COIN_NAME_UPPER"'
Comment='"$COIN_NAME_UPPER"' 0.15.2 Cryptocurrency Wallet
Exec='"$QT_NAME"'
Icon='"$COIN_NAME"'
Categories=Network;Finance;
Terminal=false
StartupWMClass='"$QT_NAME"'
DESKTOP_EOF
mkdir -p "$APPDIR/usr/share/applications"
cp "$APPDIR/'"$COIN_NAME"'.desktop" "$APPDIR/usr/share/applications/"

# Icon
ICON_DIR="$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$ICON_DIR"
if [ -f src/qt/res/icons/bitcoin.png ]; then
    cp src/qt/res/icons/bitcoin.png "$ICON_DIR/'"$COIN_NAME"'.png"
else
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -d > "$ICON_DIR/'"$COIN_NAME"'.png"
fi
ln -sf "usr/share/icons/hicolor/256x256/apps/'"$COIN_NAME"'.png" "$APPDIR/'"$COIN_NAME"'.png"

# AppRun script
cat > "$APPDIR/AppRun" << '\''APPRUN_EOF'\''
#!/bin/bash
APPDIR="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$LD_LIBRARY_PATH"
export PATH="$APPDIR/usr/bin:$PATH"

export GSETTINGS_SCHEMA_DIR="$APPDIR/usr/share/glib-2.0/schemas"
export GSETTINGS_BACKEND=memory
export GIO_MODULE_DIR="$APPDIR/usr/lib/gio/modules"

if [ -d "$APPDIR/usr/plugins" ]; then
    export QT_PLUGIN_PATH="$APPDIR/usr/plugins"
fi

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export QT_STYLE_OVERRIDE=Fusion
export XDG_DATA_DIRS="$APPDIR/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export OPENSSL_CONF="$APPDIR/etc/openssl.cnf"

# Desktop integration
_ICON_NAME="'"$COIN_NAME"'"
_QT_NAME="'"$QT_NAME"'"
_WM_CLASS="'"$COIN_NAME_UPPER"'-Qt"
_COIN_NAME="'"$COIN_NAME_UPPER"'"
_APPIMAGE_PATH="${APPIMAGE:-$0}"
_ICON_SRC="$APPDIR/usr/share/icons/hicolor/256x256/apps/${_ICON_NAME}.png"
_ICON_DST="$HOME/.local/share/icons/hicolor/256x256/apps/${_ICON_NAME}.png"
_DESKTOP_DST="$HOME/.local/share/applications/${_QT_NAME}.desktop"

if [ -f "$_ICON_SRC" ]; then
    mkdir -p "$(dirname "$_ICON_DST")" "$(dirname "$_DESKTOP_DST")" 2>/dev/null
    cp "$_ICON_SRC" "$_ICON_DST" 2>/dev/null
    cat > "$_DESKTOP_DST" <<_DEOF
[Desktop Entry]
Type=Application
Name=$_COIN_NAME
Icon=$_ICON_DST
Exec=$_APPIMAGE_PATH
Terminal=false
Categories=Finance;Network;
StartupWMClass=$_WM_CLASS
_DEOF
    chmod +x "$_DESKTOP_DST" 2>/dev/null
fi

exec "$APPDIR/usr/bin/'"$QT_NAME"'" "$@"
APPRUN_EOF
chmod +x "$APPDIR/AppRun"

echo ">>> Creating AppImage..."
mkdir -p /build/output
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 appimagetool --no-appstream "$APPDIR" \
    "/build/output/'"$COIN_NAME_UPPER"'-0.15.2-x86_64.AppImage"
chmod +x "/build/output/'"$COIN_NAME_UPPER"'-0.15.2-x86_64.AppImage"

echo ">>> Building AppImage launcher..."
gcc -O2 -s -Wall -Wextra -no-pie \
    "/build/'"$COIN_NAME"'/contrib/appimage-release/blakecoin-appimage-launcher.c" \
    -o "/build/output/'"$COIN_NAME"'-appimage-launcher"
chmod +x "/build/output/'"$COIN_NAME"'-appimage-launcher"

echo ">>> AppImage build complete!"
ls -lh /build/output/
'

    info "Starting build container: $container_name"
    docker start -a "$container_name"

    info "Extracting AppImage..."
    if docker cp "$container_name:/build/output/${APPIMAGE_PUBLIC_NAME}" "$raw_appimage_path" 2>/dev/null; then
        success "AppImage extracted to $output_dir/"
        ls -lh "$raw_appimage_path"
    else
        error "Could not find AppImage in container"
        docker rm -f "$container_name" 2>/dev/null || true
        exit 1
    fi

    if docker cp "$container_name:/build/output/${COIN_NAME}-appimage-launcher" "$launcher_path" 2>/dev/null; then
        success "AppImage launcher extracted to $output_dir/"
    else
        error "Could not find AppImage launcher in container"
        docker rm -f "$container_name" 2>/dev/null || true
        exit 1
    fi

    write_build_info "$output_dir" "appimage" "qt" "Docker: $DOCKER_APPIMAGE"
    package_appimage_release_bundle "$raw_appimage_path" "$launcher_path"
    docker rm -f "$container_name" 2>/dev/null || true
    docker run --rm -v "$tmpdir:/cleanup" alpine rm -rf /cleanup 2>/dev/null || rm -rf "$tmpdir" 2>/dev/null || true

    echo ""
    echo "============================================"
    echo "  BUILD SUCCESSFUL — AppImage"
    echo "  Raw Output: $raw_appimage_path"
    echo "  Release: $OUTPUT_BASE/release/${APPIMAGE_RELEASE_ARCHIVE_NAME}"
    echo "============================================"
}

# =============================================================================
# NATIVE BUILD (Docker — runs autotools inside container)
# =============================================================================

build_native_docker() {
    local target="$1"
    local jobs="$2"
    local docker_mode="$3"
    local output_dir="$OUTPUT_BASE/native"

    echo ""
    echo "============================================"
    echo "  Native Docker Build: $COIN_NAME_UPPER 0.15.2"
    echo "============================================"
    echo "  Image:  $DOCKER_NATIVE"
    echo "  Target: $target"
    echo ""

    ensure_docker_image "$DOCKER_NATIVE" "$docker_mode"
    mkdir -p "$output_dir/daemon" "$output_dir/qt"

    # Copy source to temp dir
    info "Copying source tree to temp build dir..."
    local tmpdir
    tmpdir=$(mktemp -d)
    cp -a "$SCRIPT_DIR"/. "$tmpdir/"
    rm -rf "$tmpdir/outputs" "$tmpdir/.git"
    fix_permissions "$tmpdir"

    local configure_extra=""
    case "$target" in
        daemon) configure_extra="--without-gui" ;;
        qt)     configure_extra="--with-gui=qt5" ;;
        both)   configure_extra="--with-gui=qt5" ;;
    esac

    local container_name="native-${COIN_NAME}-0152-build"
    docker rm -f "$container_name" 2>/dev/null || true

    docker create \
        --name "$container_name" \
        -v "$tmpdir:/build/$COIN_NAME:rw" \
        "$DOCKER_NATIVE" \
        /bin/bash -c '
set -e
cd /build/'"$COIN_NAME"'

# Patch sources for Qt 5.15+ and Boost 1.73+ compatibility
echo ">>> Patching sources for Ubuntu 22.04 compatibility..."
# QPainterPath split into separate header in Qt 5.15
if [ -f src/qt/trafficgraphwidget.cpp ]; then
    grep -q "#include <QPainterPath>" src/qt/trafficgraphwidget.cpp || \
        sed -i "1i #include <QPainterPath>" src/qt/trafficgraphwidget.cpp
fi
# Boost 1.73+ moved bind placeholders (_1, _2, etc.) to boost::placeholders namespace
# Files that use boost::bind but include it transitively need an explicit include
# to trigger BOOST_BIND_GLOBAL_PLACEHOLDERS
for f in $(grep -rl "boost::bind" src/ 2>/dev/null | grep "\.cpp$"); do
    grep -q "boost/bind.hpp" "$f" || \
        sed -i "1i #include <boost/bind.hpp>" "$f"
done

echo ">>> Running autogen.sh..."
./autogen.sh

echo ">>> Configuring..."
./configure --disable-tests --disable-bench '"$configure_extra"' \
    CXXFLAGS="-O2 -DBOOST_BIND_GLOBAL_PLACEHOLDERS"

# Fix missing Qt translation files (Blakecoin fork does not include them)
if [ -f src/Makefile ]; then
    sed -i "s/^QT_QM.*=.*/QT_QM =/" src/Makefile
    sed -i "/bitcoin_.*\.qm/d" src/Makefile
    sed -i "/locale\/.*\.qm/d" src/Makefile
fi
mkdir -p src/qt
cat > src/qt/bitcoin_locale.qrc <<QRC_EOF
<!DOCTYPE RCC><RCC version="1.0">
<qresource prefix="/translations">
</qresource>
</RCC>
QRC_EOF

echo ">>> Building..."
make -j'"$jobs"'

echo ">>> Stripping binaries..."
strip src/blakecoind 2>/dev/null || true
strip src/qt/blakecoin-qt 2>/dev/null || true
strip src/blakecoin-cli 2>/dev/null || true
strip src/blakecoin-tx 2>/dev/null || true

echo ">>> Build complete!"
ls -lh src/blakecoind src/qt/blakecoin-qt src/blakecoin-cli src/blakecoin-tx 2>/dev/null || true
'

    info "Starting build container: $container_name"
    docker start -a "$container_name"

    # Extract binaries
    if [[ "$target" == "daemon" || "$target" == "both" ]]; then
        info "Extracting daemon binaries..."
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoind" "$output_dir/daemon/blakecoind-${VERSION}" 2>/dev/null || true
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoin-cli" "$output_dir/daemon/blakecoin-cli-${VERSION}" 2>/dev/null || true
        docker cp "$container_name:/build/$COIN_NAME/src/blakecoin-tx" "$output_dir/daemon/blakecoin-tx-${VERSION}" 2>/dev/null || true
        write_build_info "$output_dir/daemon" "native-docker" "daemon" "Docker: $DOCKER_NATIVE"
        success "Daemon binaries in $output_dir/daemon/"
    fi

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        info "Extracting Qt wallet..."
        docker cp "$container_name:/build/$COIN_NAME/src/qt/blakecoin-qt" "$output_dir/qt/blakecoin-qt-${VERSION}" 2>/dev/null || true
        write_build_info "$output_dir/qt" "native-docker" "qt" "Docker: $DOCKER_NATIVE"
        success "Qt wallet in $output_dir/qt/"
    fi

    docker rm -f "$container_name" 2>/dev/null || true
    docker run --rm -v "$tmpdir:/cleanup" alpine rm -rf /cleanup 2>/dev/null || rm -rf "$tmpdir" 2>/dev/null || true

    echo ""
    echo "============================================"
    echo "  BUILD SUCCESSFUL — Native (Docker)"
    echo "  Output: $output_dir/"
    echo "============================================"
}

# =============================================================================
# NATIVE BUILD (Direct — no Docker)
# =============================================================================

build_native_direct() {
    local target="$1"
    local jobs="$2"

    local os
    os=$(detect_os)

    case "$os" in
        linux)   build_native_linux_direct "$target" "$jobs" ;;
        macos)   build_native_macos "$target" "$jobs" ;;
        windows) build_native_windows "$target" "$jobs" ;;
    esac
}

build_native_linux_direct() {
    local target="$1"
    local jobs="$2"
    local output_dir="$OUTPUT_BASE/native"

    echo ""
    echo "============================================"
    echo "  Native Linux Build: $COIN_NAME_UPPER 0.15.2"
    echo "============================================"
    echo ""

    # Detect Ubuntu version
    local ubuntu_ver=""
    if [[ -f /etc/os-release ]]; then
        ubuntu_ver=$(. /etc/os-release && echo "$VERSION_ID")
    fi
    info "Detected OS: Ubuntu ${ubuntu_ver:-unknown}"

    # Define required packages
    local build_deps="build-essential libtool-bin autotools-dev automake pkg-config curl"

    # BDB: prefer 4.8 for wallet portability, fall back to system version
    local bdb_deps=""
    local bdb48_candidate
    bdb48_candidate=$(apt-cache policy libdb4.8++-dev 2>/dev/null | grep 'Candidate:' | awk '{print $2}')
    if [[ -n "$bdb48_candidate" && "$bdb48_candidate" != "(none)" ]]; then
        bdb_deps="libdb4.8-dev libdb4.8++-dev"
        info "BDB 4.8 available — wallets will be portable"
    else
        bdb_deps="libdb++-dev"
        info "BDB 4.8 not available — using system BDB (--with-incompatible-bdb will be applied)"
    fi

    local lib_deps="libssl-dev libevent-dev $bdb_deps libminiupnpc-dev libprotobuf-dev protobuf-compiler libboost-all-dev"
    local qt_deps=""
    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        qt_deps="qtbase5-dev qttools5-dev qttools5-dev-tools libqrencode-dev"
    fi

    local all_deps="$build_deps $lib_deps $qt_deps"

    # Check and auto-install missing packages
    info "Checking and installing dependencies..."
    local missing_pkgs=()
    for pkg in $all_deps; do
        dpkg -s "$pkg" &>/dev/null 2>&1 || missing_pkgs+=("$pkg")
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        info "Installing missing packages: ${missing_pkgs[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${missing_pkgs[@]}"
    else
        info "All dependencies already installed"
    fi

    mkdir -p "$output_dir/daemon" "$output_dir/qt"

    local configure_extra=""
    case "$target" in
        daemon) configure_extra="--without-gui" ;;
        qt)     configure_extra="--with-gui=qt5" ;;
        both)   configure_extra="--with-gui=qt5" ;;
    esac

    # BDB 4.8 is preferred for portable wallets; use --with-incompatible-bdb for 5.3+
    if ! test -f /usr/include/db4.8/db_cxx.h && ! test -f /usr/lib/libdb_cxx-4.8.so; then
        info "BDB 4.8 not found, using system BDB with --with-incompatible-bdb"
        configure_extra="$configure_extra --with-incompatible-bdb"
    fi

    cd "$SCRIPT_DIR"

    # Patch sources for Qt 5.15+ and Boost 1.73+ compatibility
    if [[ -f src/qt/trafficgraphwidget.cpp ]]; then
        grep -q "#include <QPainterPath>" src/qt/trafficgraphwidget.cpp || \
            sedi '1i #include <QPainterPath>' src/qt/trafficgraphwidget.cpp
    fi

    # MSYS2 Boost 1.90 provides Boost.System as a header-only component,
    # so the legacy AX_BOOST_SYSTEM macro must not hard-fail on a missing
    # libboost_system archive.
    if ! compgen -G "/mingw64/lib/libboost_system*" >/dev/null && [[ -f build-aux/m4/ax_boost_system.m4 ]]; then
        info "MSYS2 Boost.System is header-only — patching AX_BOOST_SYSTEM"
        perl -0pi -e 's/AC_MSG_ERROR\(Could not find a version of the boost_system library!\)/BOOST_SYSTEM_LIB=""; AC_SUBST(BOOST_SYSTEM_LIB); link_system="yes"/g' build-aux/m4/ax_boost_system.m4
    fi

    info "Running autogen.sh..."
    ./autogen.sh

    # Modern MSYS2 ships Boost.System as a header-only component, so there is
    # no libboost_system*.a to locate even though Boost itself is present.
    if ! compgen -G "/mingw64/lib/libboost_system*" >/dev/null; then
        info "MSYS2 Boost.System is header-only — patching AX_BOOST_SYSTEM for no-library mode"
        perl -0pi -e 's/AC_MSG_ERROR\(Could not find a version of the boost_system library!\)/BOOST_SYSTEM_LIB=""; AC_SUBST(BOOST_SYSTEM_LIB); link_system="yes"/g' build-aux/m4/ax_boost_system.m4
    fi

    info "Configuring..."
    ./configure --disable-tests --disable-bench $configure_extra \
        CXXFLAGS="-O2 -DBOOST_BIND_GLOBAL_PLACEHOLDERS"

    # Fix missing Qt translation files (Blakecoin fork does not include them)
    if [[ -f src/Makefile ]]; then
        python3 - <<PY
from pathlib import Path

p = Path("src/Makefile")
text = p.read_text()
text = text.replace("-I/usr/local/include", "-I${boost_prefix}/include")
p.write_text(text)
PY
        sedi 's/^QT_QM.*=.*/QT_QM =/' src/Makefile
        sedi '/bitcoin_.*\.qm/d' src/Makefile
        sedi '/locale\/.*\.qm/d' src/Makefile
    fi
    mkdir -p src/qt
    cat > src/qt/bitcoin_locale.qrc <<'QRC_EOF'
<!DOCTYPE RCC><RCC version="1.0">
<qresource prefix="/translations">
</qresource>
</RCC>
QRC_EOF

    info "Building with $jobs jobs..."
    make -j"$jobs"

    # Copy outputs
    if [[ "$target" == "daemon" || "$target" == "both" ]]; then
        strip src/blakecoind src/blakecoin-cli src/blakecoin-tx 2>/dev/null || true
        cp src/blakecoind "$output_dir/daemon/blakecoind-${VERSION}"
        cp src/blakecoin-cli "$output_dir/daemon/blakecoin-cli-${VERSION}"
        cp src/blakecoin-tx "$output_dir/daemon/blakecoin-tx-${VERSION}"
        write_build_info "$output_dir/daemon" "native-linux" "daemon" "$(detect_os_version linux)"
        success "Daemon binaries in $output_dir/daemon/"
    fi

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        strip src/qt/blakecoin-qt 2>/dev/null || true
        cp src/qt/blakecoin-qt "$output_dir/qt/blakecoin-qt-${VERSION}"
        bundle_linux_qt_runtime "$output_dir/qt"
        write_build_info "$output_dir/qt" "native-linux" "qt" "$(detect_os_version linux)"
        success "Qt wallet in $output_dir/qt/"

        case "$ubuntu_ver" in
            20.04|22.04|24.04)
                package_linux_release_from_native "$ubuntu_ver"
                ;;
        esac

        # Install desktop launcher
        local desktop_dir="$HOME/.local/share/applications"
        local icon_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
        mkdir -p "$desktop_dir" "$icon_dir"
        if [[ -f "src/qt/res/icons/bitcoin.png" ]]; then
            cp "src/qt/res/icons/bitcoin.png" "$icon_dir/${COIN_NAME}.png"
        fi
        cat > "$desktop_dir/${QT_NAME}.desktop" <<DEOF
[Desktop Entry]
Type=Application
Name=$COIN_NAME_UPPER
Icon=$icon_dir/${COIN_NAME}.png
Exec=$output_dir/qt/${QT_NAME}-${VERSION}
Terminal=false
Categories=Finance;Network;
StartupWMClass=${QT_NAME}
DEOF
        chmod +x "$desktop_dir/${QT_NAME}.desktop"
        info "Desktop launcher installed — $COIN_NAME_UPPER will appear in Activities search"
    fi

    echo ""
    echo "============================================"
    echo "  BUILD SUCCESSFUL — Native Linux"
    echo "  Output: $output_dir/"
    echo "============================================"
}

build_native_macos() {
    local target="$1"
    local jobs="$2"
    local output_dir="$OUTPUT_BASE/native"
    local app_name="Blakecoin-Qt.app"
    local native_dep_root="$SCRIPT_DIR/.native-macos-deps"
    local protobuf_version="3.12.4"
    local protobuf_archive="$native_dep_root/src/protobuf-cpp-${protobuf_version}.tar.gz"
    local protobuf_src_dir="$native_dep_root/src/protobuf-${protobuf_version}"
    local protobuf_prefix=""

    echo ""
    echo "============================================"
    echo "  Native macOS Build: $COIN_NAME_UPPER 0.15.2"
    echo "============================================"
    echo ""

    ensure_macos_homebrew

    # Check/install dependencies
    local deps=(openssl@3 boost miniupnpc berkeley-db@4 qt@5 libevent pkg-config automake autoconf libtool curl)
    for dep in "${deps[@]}"; do
        if ! brew list "$dep" &>/dev/null; then
            info "Installing $dep..."
            HOMEBREW_NO_AUTO_UPDATE=1 brew install "$dep"
        fi
    done

    local openssl_prefix boost_prefix bdb_prefix qt5_prefix libevent_prefix miniupnpc_prefix
    openssl_prefix=$(brew --prefix openssl@3)
    boost_prefix=$(brew --prefix boost)
    bdb_prefix=$(brew --prefix berkeley-db@4)
    qt5_prefix=$(brew --prefix qt@5)
    libevent_prefix=$(brew --prefix libevent)
    miniupnpc_prefix=$(brew --prefix miniupnpc)

    mkdir -p "$output_dir/daemon" "$output_dir/qt"
    mkdir -p "$native_dep_root/src"

    local configure_extra=""
    case "$target" in
        daemon) configure_extra="--without-gui" ;;
        qt)     configure_extra="--with-gui=qt5" ;;
        both)   configure_extra="--with-gui=qt5" ;;
    esac

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        protobuf_prefix="$native_dep_root/protobuf-${protobuf_version}"
        if [[ ! -x "$protobuf_prefix/bin/protoc" || ! -f "$protobuf_prefix/lib/pkgconfig/protobuf.pc" ]]; then
            info "Building protobuf ${protobuf_version} for native macOS compatibility..."
            rm -rf "$protobuf_src_dir" "$protobuf_prefix"
            curl -L "https://github.com/protocolbuffers/protobuf/releases/download/v${protobuf_version}/protobuf-cpp-${protobuf_version}.tar.gz" -o "$protobuf_archive"
            tar -xzf "$protobuf_archive" -C "$native_dep_root/src"
            (
                cd "$protobuf_src_dir"
                ./configure --prefix="$protobuf_prefix" --disable-shared --enable-static \
                    CFLAGS="-O2" CXXFLAGS="-O2 -std=c++11"
                make -j"$jobs"
                make install
            )
        fi
        export PATH="$qt5_prefix/bin:$protobuf_prefix/bin:$PATH"
    else
        export PATH="$qt5_prefix/bin:$PATH"
    fi

    local pkg_config_path="$openssl_prefix/lib/pkgconfig:$qt5_prefix/lib/pkgconfig:$libevent_prefix/lib/pkgconfig:$miniupnpc_prefix/lib/pkgconfig"
    local cppflags="-I$bdb_prefix/include -I$boost_prefix/include -I$openssl_prefix/include -I$miniupnpc_prefix/include -I$libevent_prefix/include"
    local ldflags="-L$bdb_prefix/lib -L$boost_prefix/lib -L$openssl_prefix/lib -L$miniupnpc_prefix/lib -L$libevent_prefix/lib"
    local protoc_bin=""
    if [[ -n "$protobuf_prefix" ]]; then
        pkg_config_path="$protobuf_prefix/lib/pkgconfig:$pkg_config_path"
        cppflags="$cppflags -I$protobuf_prefix/include"
        ldflags="$ldflags -L$protobuf_prefix/lib"
        protoc_bin="$protobuf_prefix/bin/protoc"
    fi

    cd "$SCRIPT_DIR"

    # Modern Homebrew Boost can ship Boost.System as a header-only component,
    # so the legacy AX_BOOST_SYSTEM macro must not hard-fail on a missing
    # libboost_system library during native macOS configure.
    if ! compgen -G "$boost_prefix/lib/libboost_system*" >/dev/null && [[ -f build-aux/m4/ax_boost_system.m4 ]]; then
        info "Homebrew Boost.System is header-only — patching AX_BOOST_SYSTEM"
        python3 - <<'PY'
from pathlib import Path

replacement_old = """            if test "x$ax_lib" = "x"; then
                AC_MSG_ERROR(Could not find a version of the boost_system library!)
            fi
\t\t\tif test "x$link_system" = "xno"; then
\t\t\t\tAC_MSG_ERROR(Could not link against $ax_lib !)
\t\t\tfi"""

replacement_new = """            if test "x$ax_lib" = "x"; then
                BOOST_SYSTEM_LIB=""
                AC_SUBST(BOOST_SYSTEM_LIB)
                link_system="yes"
            fi
\t\t\tif test "x$link_system" = "xno" && test "x$ax_lib" != "x"; then
\t\t\t\tAC_MSG_ERROR(Could not link against $ax_lib !)
\t\t\tfi"""

p = Path("build-aux/m4/ax_boost_system.m4")
text = p.read_text()
if replacement_old in text:
    p.write_text(text.replace(replacement_old, replacement_new))
PY
    fi

    info "Running autogen.sh..."
    ./autogen.sh

    # Patch sources for Qt 5.15+ and Boost 1.73+ compatibility
    if [[ -f src/qt/trafficgraphwidget.cpp ]]; then
        grep -q "#include <QPainterPath>" src/qt/trafficgraphwidget.cpp || \
            sedi '1i #include <QPainterPath>' src/qt/trafficgraphwidget.cpp
    fi
    while IFS= read -r boost_bind_file; do
        grep -q "boost/bind.hpp" "$boost_bind_file" || \
            perl -0pi -e 's/\A/#include <boost\/bind.hpp>\n/' "$boost_bind_file"
    done < <(grep -rl "boost::bind" src/ 2>/dev/null | grep '\.cpp$' || true)

    info "Configuring..."
    ./configure --disable-tests --disable-bench --disable-zmq $configure_extra \
        CXXFLAGS="-O2 -DBOOST_BIND_GLOBAL_PLACEHOLDERS" \
        PKG_CONFIG_PATH="$pkg_config_path" \
        CPPFLAGS="$cppflags" \
        LDFLAGS="$ldflags" \
        BDB_CFLAGS="-I$bdb_prefix/include" \
        BDB_LIBS="-L$bdb_prefix/lib -ldb_cxx-4.8 -ldb-4.8" \
        PROTOC="$protoc_bin"

    # Fix missing Qt translation files (Blakecoin fork does not include them)
    if [[ -f src/Makefile ]]; then
        python3 - <<PY
from pathlib import Path

p = Path("src/Makefile")
text = p.read_text()
text = text.replace("-I/usr/local/include", "-I${boost_prefix}/include")
p.write_text(text)
PY
        sedi 's/^QT_QM.*=.*/QT_QM =/' src/Makefile
        sedi '/bitcoin_.*\.qm/d' src/Makefile
        sedi '/locale\/.*\.qm/d' src/Makefile
    fi
    if [[ "$target" == "qt" || "$target" == "both" ]] && command -v protoc &>/dev/null && [[ -f src/qt/paymentrequest.proto ]]; then
        info "Regenerating paymentrequest protobuf sources for native macOS protobuf..."
        (
            cd src/qt
            protoc --cpp_out=. paymentrequest.proto
        )
    fi
    mkdir -p src/qt
    cat > src/qt/bitcoin_locale.qrc <<'QRC_EOF'
<!DOCTYPE RCC><RCC version="1.0">
<qresource prefix="/translations">
</qresource>
</RCC>
QRC_EOF

    info "Building with $jobs jobs..."
    make -j"$jobs"

    if [[ "$target" == "daemon" || "$target" == "both" ]]; then
        strip src/blakecoind src/blakecoin-cli src/blakecoin-tx 2>/dev/null || true
        cp src/blakecoind "$output_dir/daemon/blakecoind-${VERSION}"
        cp src/blakecoin-cli "$output_dir/daemon/blakecoin-cli-${VERSION}"
        cp src/blakecoin-tx "$output_dir/daemon/blakecoin-tx-${VERSION}"
        write_build_info "$output_dir/daemon" "native-macos" "daemon" "$(detect_os_version macos)"
        success "Daemon binaries in $output_dir/daemon/"
    fi

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        strip src/qt/blakecoin-qt 2>/dev/null || true
        cp src/qt/blakecoin-qt "$output_dir/qt/blakecoin-qt-${VERSION}"

        rm -rf "$output_dir/qt/$app_name"
        mkdir -p "$output_dir/qt/$app_name/Contents/MacOS" "$output_dir/qt/$app_name/Contents/Resources"
        cp src/qt/blakecoin-qt "$output_dir/qt/$app_name/Contents/MacOS/Blakecoin-Qt"

        local icons_dir="$SCRIPT_DIR/src/qt/res/icons"
        if [[ -f "$icons_dir/bitcoin.png" ]] && command -v sips &>/dev/null && command -v iconutil &>/dev/null; then
            info "Generating macOS icon from bitcoin.png..."
            local iconset_root iconset_dir size size2
            iconset_root=$(mktemp -d)
            iconset_dir="$iconset_root/blakecoin.iconset"
            mkdir -p "$iconset_dir"
            for size in 16 32 128 256 512; do
                sips -z "$size" "$size" "$icons_dir/bitcoin.png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null 2>&1 || true
                size2=$((size * 2))
                sips -z "$size2" "$size2" "$icons_dir/bitcoin.png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null 2>&1 || true
            done
            iconutil -c icns "$iconset_dir" -o "$output_dir/qt/$app_name/Contents/Resources/blakecoin.icns" 2>/dev/null || true
            rm -rf "$iconset_root"
        fi

        cat > "$output_dir/qt/$app_name/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Blakecoin-Qt</string>
    <key>CFBundleIdentifier</key>
    <string>org.blakecoin.Blakecoin-Qt</string>
    <key>CFBundleName</key>
    <string>Blakecoin-Qt</string>
    <key>CFBundleDisplayName</key>
    <string>Blakecoin Core</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIconFile</key>
    <string>blakecoin</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST_EOF

        if [[ -x "$qt5_prefix/bin/macdeployqt" ]]; then
            info "Bundling Qt frameworks with macdeployqt..."
            "$qt5_prefix/bin/macdeployqt" "$output_dir/qt/$app_name" >/dev/null 2>&1 || warn "macdeployqt failed; leaving native bundle unmodified"
        fi

        info "Resolving transitive dylib dependencies for native macOS bundle..."
        bundle_macos_transitive_dylibs \
            "$output_dir/qt/$app_name" \
            "$boost_prefix/lib" \
            "$openssl_prefix/lib" \
            "$bdb_prefix/lib" \
            "$libevent_prefix/lib" \
            "$miniupnpc_prefix/lib" \
            "$qt5_prefix/lib"

        codesign --force --deep --sign - "$output_dir/qt/$app_name" 2>/dev/null || true
        write_build_info "$output_dir/qt" "native-macos" "qt" "$(detect_os_version macos)"
        success "Qt wallet in $output_dir/qt/"
    fi

    echo ""
    echo "============================================"
    echo "  BUILD SUCCESSFUL — Native macOS"
    echo "  Output: $output_dir/"
    echo "============================================"
}

build_native_windows() {
    local target="$1"
    local jobs="$2"
    local output_dir="$OUTPUT_BASE/windows-native"
    local native_dep_root="$SCRIPT_DIR/.native-windows-deps"
    local protobuf_version="3.12.4"
    local protobuf_archive="$native_dep_root/src/protobuf-cpp-${protobuf_version}.tar.gz"
    local protobuf_src_dir="$native_dep_root/src/protobuf-${protobuf_version}"
    local protobuf_prefix="$native_dep_root/protobuf-${protobuf_version}"
    local msys_packages=(
        autoconf
        automake
        libtool
        make
        pkgconf
        curl
        git
        patch
        perl
        tar
        zip
        unzip
    )
    local mingw_packages=(
        mingw-w64-x86_64-gcc
        mingw-w64-x86_64-pkgconf
        mingw-w64-x86_64-boost
        mingw-w64-x86_64-openssl
        mingw-w64-x86_64-libevent
        mingw-w64-x86_64-miniupnpc
        mingw-w64-x86_64-db
    )

    echo ""
    echo "============================================"
    echo "  Native Windows Build: $COIN_NAME_UPPER 0.15.2"
    echo "============================================"
    echo ""

    ensure_windows_icon_assets
    ensure_windows_native_shell "$target" "$jobs"

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        mingw_packages+=(
            mingw-w64-x86_64-qt5-base
            mingw-w64-x86_64-qt5-tools
            mingw-w64-x86_64-qrencode
        )
    fi

    info "Installing required MSYS2 packages..."
    pacman -S --needed --noconfirm "${msys_packages[@]}" "${mingw_packages[@]}"

    # MSYS2 names the Qt5 tools with a -qt5 suffix.
    if ! command -v qmake &>/dev/null && command -v qmake-qt5 &>/dev/null; then
        ln -sf "$(command -v qmake-qt5)" /mingw64/bin/qmake 2>/dev/null || true
    fi
    if ! command -v lrelease &>/dev/null && command -v lrelease-qt5 &>/dev/null; then
        ln -sf "$(command -v lrelease-qt5)" /mingw64/bin/lrelease 2>/dev/null || true
    fi

    local missing_tools=()
    local tool
    for tool in curl pkg-config make gcc g++ strip ldd autoconf automake libtoolize; do
        command -v "$tool" &>/dev/null || missing_tools+=("$tool")
    done
    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        command -v qmake &>/dev/null || command -v qmake-qt5 &>/dev/null || missing_tools+=("qmake")
        command -v lrelease &>/dev/null || command -v lrelease-qt5 &>/dev/null || missing_tools+=("lrelease")
    fi
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required MSYS2 tools after install: ${missing_tools[*]}"
        exit 1
    fi

    rm -rf "$output_dir"
    mkdir -p "$output_dir/daemon" "$output_dir/qt"

    local configure_extra=""
    case "$target" in
        daemon) configure_extra="--without-gui" ;;
        qt)     configure_extra="--with-gui=qt5" ;;
        both)   configure_extra="--with-gui=qt5" ;;
    esac

    # MSYS2 ships newer Berkeley DB than 4.8, so native builds need the
    # compatibility flag. Cross-build release artifacts still use 4.8.
    configure_extra="$configure_extra --with-incompatible-bdb"

    # Modern MSYS2 uses Boost 1.90 with -mt library names for the compiled
    # components that Blakecoin links against.
    configure_extra="$configure_extra --with-boost=/mingw64 --with-boost-libdir=/mingw64/lib"
    configure_extra="$configure_extra --with-boost-filesystem=boost_filesystem-mt"
    configure_extra="$configure_extra --with-boost-program-options=boost_program_options-mt"
    configure_extra="$configure_extra --with-boost-thread=boost_thread-mt"
    configure_extra="$configure_extra --with-boost-chrono=boost_chrono-mt"

    cd "$SCRIPT_DIR"

    # Patch sources for Qt 5.15+ and Boost 1.73+ compatibility
    if [[ -f src/qt/trafficgraphwidget.cpp ]]; then
        grep -q "#include <QPainterPath>" src/qt/trafficgraphwidget.cpp || \
            sedi '1i #include <QPainterPath>' src/qt/trafficgraphwidget.cpp
    fi

    # Modern MSYS2 ships Boost.System as a header-only component, so there is
    # no libboost_system*.a to locate even though Boost itself is present.
    if ! compgen -G "/mingw64/lib/libboost_system*" >/dev/null; then
        info "MSYS2 Boost.System is header-only — patching legacy boost_system detection"
        python3 - <<'PY'
from pathlib import Path

replacement_old = """            if test "x$ax_lib" = "x"; then
                AC_MSG_ERROR(Could not find a version of the boost_system library!)
            fi
\t\t\tif test "x$link_system" = "xno"; then
\t\t\t\tAC_MSG_ERROR(Could not link against $ax_lib !)
\t\t\tfi"""

replacement_new = """            if test "x$ax_lib" = "x"; then
                BOOST_SYSTEM_LIB=""
                AC_SUBST(BOOST_SYSTEM_LIB)
                link_system="yes"
            fi
\t\t\tif test "x$link_system" = "xno" && test "x$ax_lib" != "x"; then
\t\t\t\tAC_MSG_ERROR(Could not link against $ax_lib !)
\t\t\tfi"""

for rel in ("build-aux/m4/ax_boost_system.m4",):
    p = Path(rel)
    if not p.exists():
        continue
    text = p.read_text()
    if replacement_old in text:
        p.write_text(text.replace(replacement_old, replacement_new))
PY
    fi

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        mkdir -p "$native_dep_root/src"
        if [[ ! -x "$protobuf_prefix/bin/protoc" || ! -f "$protobuf_prefix/lib/pkgconfig/protobuf.pc" ]]; then
            info "Building protobuf ${protobuf_version} for native Windows compatibility..."
            rm -rf "$protobuf_src_dir" "$protobuf_prefix"
            curl -L "https://github.com/protocolbuffers/protobuf/releases/download/v${protobuf_version}/protobuf-cpp-${protobuf_version}.tar.gz" -o "$protobuf_archive"
            tar -xzf "$protobuf_archive" -C "$native_dep_root/src"
            (
                cd "$protobuf_src_dir"
                ./configure --prefix="$protobuf_prefix" --disable-shared --enable-static \
                    CFLAGS="-O2" CXXFLAGS="-O2"
                make -j"$jobs"
                make install
            )
        fi
        export PATH="$protobuf_prefix/bin:$PATH"
        export PKG_CONFIG_PATH="$protobuf_prefix/lib/pkgconfig:/mingw64/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        export QMAKE="$(command -v qmake)"
        export CPPFLAGS="-I$protobuf_prefix/include -I/mingw64/include -I/mingw64/include/QtCore -I/mingw64/include/QtGui -I/mingw64/include/QtWidgets -I/mingw64/include/QtNetwork ${CPPFLAGS:-}"
        export LDFLAGS="-L$protobuf_prefix/lib ${LDFLAGS:-}"
    fi

    info "Running autogen.sh..."
    ./autogen.sh

    if ! compgen -G "/mingw64/lib/libboost_system*" >/dev/null && [[ -f configure ]]; then
        python3 - <<'PY'
from pathlib import Path

p = Path("configure")
text = p.read_text()
old = """            if test "x$ax_lib" = "x"; then
                as_fn_error $? "Could not find a version of the boost_system library!" "$LINENO" 5
            fi
\t\t\tif test "x$link_system" = "xno"; then
\t\t\t\tas_fn_error $? "Could not link against $ax_lib !" "$LINENO" 5
\t\t\tfi"""
new = """            if test "x$ax_lib" = "x"; then
                BOOST_SYSTEM_LIB=""
                link_system="yes"
            fi
\t\t\tif test "x$link_system" = "xno" && test "x$ax_lib" != "x"; then
\t\t\t\tas_fn_error $? "Could not link against $ax_lib !" "$LINENO" 5
\t\t\tfi"""
if old in text:
    p.write_text(text.replace(old, new))
PY
    fi

    info "Configuring..."
    ./configure --disable-tests --disable-bench $configure_extra \
        CXXFLAGS="-O2 -DBOOST_BIND_GLOBAL_PLACEHOLDERS"

    # Blakecoin 0.15.2 does not ship the upstream translation payloads.
    if [[ -f src/Makefile ]]; then
        sedi 's/^QT_QM.*=.*/QT_QM =/' src/Makefile
        sedi '/bitcoin_.*\.qm/d' src/Makefile
        sedi '/locale\/.*\.qm/d' src/Makefile
        # MSYS2 ships DLL import libraries for Qt/qrencode, not fully static
        # archives. Native Windows validation builds should link against those
        # import libs and bundle the resulting DLL dependencies afterward.
        sedi 's/^LIBTOOL_APP_LDFLAGS = .*/LIBTOOL_APP_LDFLAGS =/' src/Makefile
    fi
    mkdir -p src/qt
    if [[ "$target" == "qt" || "$target" == "both" ]] && command -v protoc &>/dev/null && [[ -f src/qt/paymentrequest.proto ]]; then
        info "Regenerating paymentrequest protobuf sources for native Windows protobuf..."
        (
            cd src/qt
            protoc --cpp_out=. paymentrequest.proto
        )
    fi
    cat > src/qt/bitcoin_locale.qrc <<'QRC_EOF'
<!DOCTYPE RCC><RCC version="1.0">
<qresource prefix="/translations">
</qresource>
</RCC>
QRC_EOF

    info "Building with $jobs jobs..."
    make -j"$jobs"

    if [[ "$target" == "daemon" || "$target" == "both" ]]; then
        local daemon_bin="src/blakecoind.exe"
        local cli_bin="src/blakecoin-cli.exe"
        local tx_bin="src/blakecoin-tx.exe"
        [[ -f src/.libs/blakecoind.exe ]] && daemon_bin="src/.libs/blakecoind.exe"
        [[ -f src/.libs/blakecoin-cli.exe ]] && cli_bin="src/.libs/blakecoin-cli.exe"
        [[ -f src/.libs/blakecoin-tx.exe ]] && tx_bin="src/.libs/blakecoin-tx.exe"

        strip "$daemon_bin" "$cli_bin" "$tx_bin" 2>/dev/null || true
        cp "$daemon_bin" "$output_dir/daemon/blakecoind-${VERSION}.exe"
        cp "$cli_bin" "$output_dir/daemon/blakecoin-cli-${VERSION}.exe"
        cp "$tx_bin" "$output_dir/daemon/blakecoin-tx-${VERSION}.exe"

        # Bundle DLLs
        info "Bundling DLL dependencies..."
        for exe in "$output_dir"/daemon/*.exe; do
            ldd "$exe" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read -r dll; do
                local dll_lc
                dll_lc=$(printf '%s' "$dll" | tr '[:upper:]' '[:lower:]')
                case "$dll_lc" in
                    /c/windows/*) ;;
                    *) cp -n "$dll" "$output_dir/daemon/" 2>/dev/null || true ;;
                esac
            done
        done

        write_build_info "$output_dir/daemon" "native-windows" "daemon" "$(detect_os_version windows)"
        success "Daemon binaries in $output_dir/daemon/"
    fi

    if [[ "$target" == "qt" || "$target" == "both" ]]; then
        local qt_bin="src/qt/blakecoin-qt.exe"
        [[ -f src/qt/.libs/blakecoin-qt.exe ]] && qt_bin="src/qt/.libs/blakecoin-qt.exe"

        strip "$qt_bin" 2>/dev/null || true
        cp "$qt_bin" "$output_dir/qt/blakecoin-qt-${VERSION}.exe"

        # Bundle DLLs
        info "Bundling DLL dependencies..."
        ldd "$output_dir/qt/blakecoin-qt-${VERSION}.exe" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read -r dll; do
            local dll_lc
            dll_lc=$(printf '%s' "$dll" | tr '[:upper:]' '[:lower:]')
            case "$dll_lc" in
                /c/windows/*) ;;
                *) cp -n "$dll" "$output_dir/qt/" 2>/dev/null || true ;;
            esac
        done

        # Qt platform plugin
        # Legacy native Windows builds worked because they copied qwindows.dll
        # from the known MSYS2 Qt plugin directory. Keep the qmake query for
        # portability, but fall back to the fixed MSYS2 path so fresh Windows
        # hosts still get a runnable bundle.
        local qt_plugin_dir=""
        local qmake_bin=""
        for qmake_bin in "${QMAKE:-}" "$(command -v qmake 2>/dev/null || true)" "$(command -v qmake-qt5 2>/dev/null || true)" /mingw64/bin/qmake; do
            [[ -z "$qmake_bin" || ! -x "$qmake_bin" ]] && continue
            qt_plugin_dir=$("$qmake_bin" -query QT_INSTALL_PLUGINS 2>/dev/null | tr -d '\r')
            [[ -n "$qt_plugin_dir" && -f "$qt_plugin_dir/platforms/qwindows.dll" ]] && break
            qt_plugin_dir=""
        done
        if [[ -z "$qt_plugin_dir" || ! -f "$qt_plugin_dir/platforms/qwindows.dll" ]]; then
            if [[ -f /mingw64/share/qt5/plugins/platforms/qwindows.dll ]]; then
                qt_plugin_dir="/mingw64/share/qt5/plugins"
            fi
        fi
        if [[ -n "$qt_plugin_dir" && -f "$qt_plugin_dir/platforms/qwindows.dll" ]]; then
            mkdir -p "$output_dir/qt/platforms"
            cp "$qt_plugin_dir/platforms/qwindows.dll" "$output_dir/qt/platforms/" 2>/dev/null || true
            cat > "$output_dir/qt/qt.conf" <<'EOF'
[Paths]
Plugins=.
EOF
        else
            warn "qwindows.dll not found; native Windows Qt wallet may fail to launch"
        fi

        write_build_info "$output_dir/qt" "native-windows" "qt" "$(detect_os_version windows)"
        success "Qt wallet in $output_dir/qt/"
    fi

    echo ""
    echo "============================================"
    echo "  BUILD SUCCESSFUL — Native Windows"
    echo "  Output: $output_dir/"
    echo "============================================"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local platform=""
    local target="both"
    local docker_mode="none"
    local jobs
    local cores
    cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    jobs=$(( cores > 1 ? cores - 1 : 1 ))

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --native)       platform="native" ;;
            --appimage)     platform="appimage" ;;
            --windows)      platform="windows" ;;
            --macos)        platform="macos" ;;
            --daemon)       target="daemon" ;;
            --qt)           target="qt" ;;
            --both)         target="both" ;;
            --pull-docker)  docker_mode="pull" ;;
            --build-docker) docker_mode="build" ;;
            --no-docker)    docker_mode="none" ;;
            --jobs)         shift; jobs="$1" ;;
            -h|--help)      usage ;;
            *)              error "Unknown option: $1"; usage ;;
        esac
        shift
    done

    if [[ -z "$platform" ]]; then
        error "No platform specified. Use --native, --appimage, --windows, or --macos"
        echo ""
        usage
    fi

    # Cross-compile platforms require Docker
    if [[ "$platform" =~ ^(windows|macos|appimage)$ && "$docker_mode" == "none" ]]; then
        error "--$platform requires Docker. Use --pull-docker or --build-docker"
        echo ""
        echo "  --pull-docker   Pull prebuilt image from Docker Hub"
        echo "  --build-docker  Build image locally from repo Dockerfiles"
        echo ""
        exit 1
    fi

    echo ""
    echo "============================================"
    echo "  $COIN_NAME_UPPER 0.15.2 Build System"
    echo "============================================"
    echo "  Platform: $platform"
    echo "  Target:   $target"
    echo "  Docker:   $docker_mode"
    echo "  Jobs:     $jobs"
    echo ""

    case "$platform" in
        native)
            if [[ "$docker_mode" != "none" ]]; then
                build_native_docker "$target" "$jobs" "$docker_mode"
            else
                build_native_direct "$target" "$jobs"
            fi
            ;;
        windows)
            build_windows "$target" "$jobs" "$docker_mode"
            ;;
        macos)
            build_macos_cross "$target" "$jobs" "$docker_mode"
            ;;
        appimage)
            build_appimage "$jobs" "$docker_mode"
            ;;
    esac

    # Generate config file if not already present
    generate_config
}

main "$@"
