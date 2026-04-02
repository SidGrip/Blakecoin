<p align="center">
  <img src="src/qt/res/icons/bitcoin.png" alt="Blakecoin" width="95">
</p>

# Blakecoin 0.15.2

## About Blakecoin

Blakecoin is the original Blake-256 coin and parent chain for [Photon](https://github.com/BlueDragon747/photon), [BlakeBitcoin](https://github.com/BlakeBitcoin/BlakeBitcoin), [Electron](https://github.com/BlueDragon747/Electron-ELT), [Universal Molecule](https://github.com/BlueDragon747/universalmol), and [Lithium](https://github.com/BlueDragon747/lithium). It is a digital currency using peer-to-peer technology with no central authority.

- Uses the **Blake-256** hashing algorithm
- Based on **Bitcoin Core 0.15.2**
- Uses the autotools build system (`./configure` + `make`)
- Ships release packages for Ubuntu 20.04, 22.04, 24.04, 25.10, Windows, macOS, and Ubuntu 22+ AppImage
- Website: https://blakecoin.org

| Network Info | |
|---|---|
| Algorithm | Blake-256 (8 rounds) |
| Block time | 3 minutes |
| Block reward | 50 BLC |
| Difficulty retarget | Every 20 blocks |
| Default port | 8773 |
| RPC port | 8772 |
| Max supply | 7,000,000,000 BLC |

---

## Quick Start

```bash
git clone https://github.com/BlueDragon747/Blakecoin.git
cd Blakecoin
bash ./build.sh --help
```

For most users, downloading a prebuilt release from GitHub Releases is the simplest path.
Use `build.sh` to build the release artifacts locally.

---

## Build Options

```bash
bash ./build.sh [PLATFORM] [TARGET] [OPTIONS]

Platforms:
  --native          Build natively on this machine (Linux, macOS, or Windows)
  --appimage        Build portable Linux AppImage (requires Docker)
  --windows         Cross-compile for Windows from Linux (requires Docker)
  --macos           Cross-compile for macOS from Linux (requires Docker)

Targets:
  --daemon          Build daemon only
  --qt              Build Qt wallet only
  --both            Build daemon and Qt wallet (default)

Docker options:
  --pull-docker     Pull prebuilt Docker images from Docker Hub
  --build-docker    Build Docker images locally from repo Dockerfiles
  --no-docker       For --native on Linux: build directly on the host

Other options:
  --jobs N          Parallel make jobs
```

---

## Platform Build Instructions

### Native Linux

```bash
bash ./build.sh --native --both
```

- On supported Ubuntu hosts, `build.sh` auto-detects the OS version and installs missing packages automatically
- Native Linux release packaging targets Ubuntu `20.04`, `22.04`, `24.04`, and `25.10`
- Native Linux builds write raw outputs to `outputs/native/` and release artifacts to `outputs/release/`

### Linux (Docker)

Use `--pull-docker` to pull prebuilt images from Docker Hub, or `--build-docker` to build them locally from the Dockerfiles in `docker/`.

```bash
bash ./build.sh --native --both --pull-docker
bash ./build.sh --native --qt --pull-docker
bash ./build.sh --native --daemon --pull-docker
bash ./build.sh --native --both --build-docker
```

### AppImage

```bash
bash ./build.sh --appimage --pull-docker
```

- Uses `sidgrip/appimage-base:22.04`
- Produces the raw payload in `outputs/linux-appimage/qt/`
- Produces the public release bundle in `outputs/release/Blakecoin-0.15.2-x86_64.AppImage.tar.gz`
- Intended for Ubuntu `22.04+`

### Windows

There are two Windows paths in this repo:

#### Windows release build

```bash
bash ./build.sh --windows --both --pull-docker
```

- Runs on Linux with Docker using `sidgrip/mxe-base:latest`
- Produces the public release zip in `outputs/release/blakecoin-v0.15.2-windows-x86_64.zip`
- This is the main Windows release path

#### Native Windows validation build

```bash
C:\msys64\usr\bin\bash.exe -lc "cd /c/path/to/Blakecoin-0.15.2 && ./build.sh --native --both --jobs 8"
```

- Requires MSYS2 `bash` to exist before the script starts
- After launch, `build.sh` installs the required MSYS2 / MINGW64 packages automatically
- Writes validation outputs to `outputs/windows-native/`

### macOS

There are two macOS paths in this repo:

#### Cross-build from Linux

```bash
bash ./build.sh --macos --both --pull-docker
```

- Runs on Linux with Docker using `sidgrip/osxcross-base:latest`
- Produces artifacts in `outputs/macos/`
- Produces the public release archive in `outputs/release/blakecoin-v0.15.2-macos-x86_64.tar.gz`

#### Native build on macOS

```bash
bash ./build.sh --native --both
```

- Uses Homebrew on the Mac host
- `build.sh` installs missing Homebrew dependencies automatically
- Native macOS builds write to `outputs/native/`

---

## Releases

### Linux

- `blakecoin-v0.15.2-ubuntu-20.04-x86_64.tar.gz`
- `blakecoin-v0.15.2-ubuntu-22.04-x86_64.tar.gz`
- `blakecoin-v0.15.2-ubuntu-24.04-x86_64.tar.gz`
- `blakecoin-v0.15.2-ubuntu-25.10-x86_64.tar.gz`

These tarballs extract into a single top-level folder. Open that folder and run `./blakecoin-qt` for the GUI wallet, or use `./blakecoind`, `./blakecoin-cli`, and `./blakecoin-tx` for daemon-side tools.

### AppImage

- `Blakecoin-0.15.2-x86_64.AppImage.tar.gz`

This is the portable Linux AppImage bundle for **Ubuntu 22.04 and newer**. Extract the tarball and run `./Blakecoin-0.15.2-x86_64.AppImage`.

Ubuntu 20.04 users should use the native Ubuntu 20.04 tarball instead of the AppImage.

### Windows

- `blakecoin-v0.15.2-windows-x86_64.zip`

The Windows release zip contains:

- `blakecoin-qt-0.15.2.exe`
- `blakecoind-0.15.2.exe`
- `blakecoin-cli-0.15.2.exe`
- `blakecoin-tx-0.15.2.exe`
- `README.md`
- `build-info.txt`

The public Windows release is self-contained and does not ship sidecar DLL or plugin folders.

### macOS

- `blakecoin-v0.15.2-macos-x86_64.tar.gz`

The macOS archive extracts the Qt app bundle plus the daemon, CLI, and tx binaries. Open `Blakecoin-Qt.app` for the GUI wallet.

---

## Output Structure

```text
outputs/
├── blakecoin.conf
├── native/
│   ├── daemon/
│   └── qt/
├── linux-appimage/
│   └── qt/
├── windows/
│   ├── daemon/
│   └── qt/
├── windows-native/
│   ├── daemon/
│   └── qt/
├── macos/
│   ├── daemon/
│   └── qt/
└── release/
    ├── blakecoin-v0.15.2-ubuntu-20.04-x86_64.tar.gz
    ├── blakecoin-v0.15.2-ubuntu-22.04-x86_64.tar.gz
    ├── blakecoin-v0.15.2-ubuntu-24.04-x86_64.tar.gz
    ├── blakecoin-v0.15.2-ubuntu-25.10-x86_64.tar.gz
    ├── Blakecoin-0.15.2-x86_64.AppImage.tar.gz
    ├── blakecoin-v0.15.2-windows-x86_64.zip
    └── blakecoin-v0.15.2-macos-x86_64.tar.gz
```

`outputs/blakecoin.conf` is auto-generated with RPC credentials and default network settings during builds that need it.

---

## Docker Images

When using `--pull-docker`, the build script uses these prebuilt images:

| Image | Purpose |
|---|---|
| `sidgrip/native-base:20.04` | Native Linux Ubuntu 20.04 release build |
| `sidgrip/native-base:22.04` | Native Linux Ubuntu 22.04 release build |
| `sidgrip/native-base:24.04` | Native Linux Ubuntu 24.04 release build |
| `sidgrip/appimage-base:22.04` | Ubuntu 22+ AppImage build |
| `sidgrip/mxe-base:latest` | Windows cross-compile |
| `sidgrip/osxcross-base:latest` | macOS cross-compile |

---

## Multi-Coin Builder

For building wallets for all Blake-family coins [Blakecoin](https://github.com/BlueDragon747/Blakecoin), [Photon](https://github.com/BlueDragon747/photon), [BlakeBitcoin](https://github.com/BlakeBitcoin/BlakeBitcoin), [Electron](https://github.com/BlueDragon747/Electron-ELT), [Universal Molecule](https://github.com/BlueDragon747/universalmol), and [Lithium](https://github.com/BlueDragon747/lithium), see the [Blakestream Installer](https://github.com/SidGrip/Blakestream-Installer).

## License

Blakecoin is released under the terms of the MIT license. See `COPYING` for more information.
