<p align="center">
  <img src="doc/blakecoin_logo.png" alt="Blakecoin" width="95">
</p>

# Blakecoin Core 0.25.2

Blakecoin Core 0.25.2 is the Blakecoin port of upstream Core v25.2. It keeps
Blakecoin's chain identity and hash policy while adding the Taproot-era Core
codebase, descriptor-wallet support, SQLite wallet support, ZMQ, and Linux USDT
tracepoints for hardened release builds.

## Mainnet Consensus Changes In 0.25.2

Blakecoin 0.25.2 is intended to follow the 0.15.21 SegWit mainnet activation
and then activate the next upstream-compatible script rule sets in a staged
order. Miners should use the daemon-provided block template version; do not
manually rewrite version bits.

| Rule set | Mainnet policy in Blakecoin 0.25.2 |
|---|---|
| SegWit (`BIP141` / `BIP143` / `BIP147`) | Already active from 0.15.21; buried at height `1978980`. No new SegWit signaling window in 0.25.2. |
| Coinbase maturity restore | Historical replay uses the accidental 0.15.21 `100`-confirmation rule before height `1996240`; from height `1996240`, 0.25.2 restores Blakecoin's original 0.8 `120`-confirmation rule. |
| `BIP34` coinbase height | Height activation at `2002950`; `BIP34Hash = uint256{}`. |
| `BIP65` / CLTV | Height activation at `2002950`; required for standard CLTV atomic-swap refunds. |
| `BIP66` / strict DER | Height activation at `2002950`. |
| Taproot (`BIP340` / `BIP341` / `BIP342`) | BIP9 deployment bit `2`, start `1782871200` (`2026-07-01 02:00:00 UTC`), timeout `1814407200` (`2027-07-01 02:00:00 UTC`), minimum activation height `2006310`. |

Only Taproot is a future BIP9-signaled deployment in 0.25.2. `BIP34`,
`BIP65`, `BIP66`, and buried SegWit are height rules. Pools and solo miners
should request templates with `getblocktemplate`; Blakecoin Core computes the
correct top bits and Taproot bit `2` during the BIP9 `started` and `locked_in`
states.

## About Blakecoin

Blakecoin is the original Blake-256 coin and the parent chain for Photon,
BlakeBitcoin, Electron-ELT, UniversalMolecule, and Lithium. It is a peer-to-peer
digital currency with no central authority.

- Uses the Blake-256 hashing algorithm, 8 rounds
- Based on upstream Core v25.2
- Uses the autotools build system (`./autogen.sh`, `./configure`, `make`)
- Supports legacy Berkeley DB wallets and descriptor SQLite wallets from one
  maintained `blakecoin-25.2-dualwallet` code branch
- Keeps Blakecoin txids on single SHA-256
- Uses HASH256/double SHA-256 for witness-v0 BIP143 signing
- Keeps BIP340/BIP341/BIP342 Taproot tagged hashes byte-compatible with upstream Taproot
- Website: https://blakecoin.org

| Network Info | Value |
|---|---|
| Algorithm | Blake-256, 8 rounds |
| Block time | 3 minutes |
| Block reward | 50 BLC flat |
| Difficulty retarget | Every 20 blocks |
| Coinbase maturity | 100 blocks through historical 15.21 replay; 120 blocks from height 1,996,240 |
| Default P2P port | 8773 |
| RPC port | 8772 |
| Max money sanity range | `21000000 * COIN` legacy transaction money-range consensus limit |
| Max supply policy | 7,000,000,000 BLC target supply policy |
| Mainnet genesis | `000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be` |
| Mainnet Bech32 HRP | `blc` |
| Testnet Bech32 HRP | `tblc` |
| Regtest Bech32 HRP | `rblc` |

## Network Activation Notes

The SegWit activation block is height `1978980`, hash
`000000000000b1c7b12f008aac514c68fdc2911e618b64522633e0ffcd8f6054`.

Testnet is treated as a 0.25.2 feature-test/reset network. SegWit, BIP34,
BIP65/CLTV, BIP66, and Taproot are active from height `1` on testnet so
wallet, atomic-swap, Lightning, and Taproot behavior can be tested without
waiting on mainnet-style activation windows.

## Quick Start

```bash
git clone https://github.com/BlueDragon747/Blakecoin.git
cd Blakecoin
git checkout 0.25.2
./build.sh --help
```

For most users, downloading a tested release artifact from GitHub Releases is
the simplest path. Use `build.sh` to build release artifacts locally.

## UPnP / miniupnpc Build Profiles

UPnP is only for desktop or home-router nodes that need automatic inbound P2P
port mapping. Nodes still sync normally through outbound peers without UPnP.

Pool, explorer, server, and Docker daemon builds should disable UPnP with
`--without-miniupnpc` so the binary has no `libminiupnpc.so.*` runtime
dependency.

UPnP-enabled Ubuntu builds need `libminiupnpc-dev` at build time and the matching
`libminiupnpc` runtime package on the target host.

## Upgrade Notes

Before starting Blakecoin Core 0.25.2 on an existing data directory, close the
older wallet cleanly and back up any wallet files first.

`peers.dat` is only the cached P2P address database. It is safe to remove or
rename when moving between major releases, and Blakecoin will rebuild it on the
next start. If startup fails with `Invalid or corrupt peers.dat`, remove or
rename this file:

- Windows: `%APPDATA%\Blakecoin\peers.dat`
- Linux: `~/.blakecoin/peers.dat`
- macOS: `~/Library/Application Support/Blakecoin/peers.dat`

Windows PowerShell example:

```powershell
Rename-Item "$env:APPDATA\Blakecoin\peers.dat" "peers.dat.bak"
```

Linux example:

```bash
mv ~/.blakecoin/peers.dat ~/.blakecoin/peers.dat.bak
```

macOS example:

```bash
mv "$HOME/Library/Application Support/Blakecoin/peers.dat" \
   "$HOME/Library/Application Support/Blakecoin/peers.dat.bak"
```

If the block index or chainstate database cannot be reused after an upgrade,
restart once with `-reindex` to rebuild the local block database from the stored
block files:

```bash
blakecoind -reindex
```

Pruning is disabled by default (`-prune=0`), so a normal Blakecoin Core node
keeps full block data. Only enable pruning deliberately with `-prune=<MiB>`.
Public release nodes, explorers, pools, and bridge/watch services should run
unpruned unless they have a specific reason to discard old block data.

For first-run testing of a new 0.25.2 build, use an isolated data directory so
the test does not touch an existing 0.15.21 wallet or chainstate:

```bash
blakecoin-qt -datadir=/path/to/blakecoin-25.2-test
```

## Build Options

```bash
./build.sh [PLATFORM] [TARGET] [OPTIONS]

Platforms:
  --native          Build natively on this machine (Linux, macOS, or Windows)
  --appimage        Build portable Linux AppImage (requires Docker)
  --windows         Cross-compile for Windows from Linux (requires Docker)
  --macos           Cross-compile for macOS from Linux (requires Docker)

Targets:
  --daemon          Build daemon only (blakecoind + blakecoin-cli + blakecoin-tx)
  --qt              Build Qt wallet only (blakecoin-qt)
  --both            Build daemon and Qt wallet (default)

Docker options:
  --pull-docker     Pull prebuilt Docker images from Docker Hub
  --build-docker    Build Docker images locally from repo Dockerfiles
  --no-docker       For --native on Linux: build directly on the host

Other options:
  --hardened-release
                   Native Linux release profile: enable SQLite, ZMQ, and USDT
                   and fail the build if configure disables any of them
  --jobs N          Parallel make jobs
```


<!-- BEGIN electrium-build -->
### Electrium Wallet

Build the Blakecoin ([Electrium](https://github.com/BlueDragon747/Blakestream-Electrum)) wallet by
choosing a target (linux/windows build in an **amd64** container, so any amd64 Docker host — Linux,
Windows, or an Intel Mac — can build either; only the macOS app needs a Mac):

```bash
./build-electrum.sh linux      # Linux AppImage    (amd64 Docker host)
./build-electrum.sh windows    # Windows .exe      (amd64 Docker host)
./build-electrum.sh macos      # macOS .dmg/.app   (on a Mac)
./build-electrum.sh all        # everything buildable on this host
```

Artifacts land in `outputs/Electrium/BLC/`, named `Electrium-BLC-<version>`.

The wallet builder is the shared multicoin repo
**[BlueDragon747/Blakestream-Electrum](https://github.com/BlueDragon747/Blakestream-Electrum)** — it also builds
all six BlakeStream wallets at once (`build-single-wallets.sh`) and the ElectrumX **server** Docker
image (`build-electrumx.sh`). `build-electrum.sh` auto-clones it when no local checkout is found.
<!-- END electrium-build -->

## Platform Build Instructions

### Native Linux

```bash
./build.sh --native --both --no-docker
```

- Supported validation lanes: Ubuntu 20.04, 22.04, 24.04, 25.10, and 26.04
- Public Linux release lane: Ubuntu 26.04
- Ubuntu 20.04 remains a test/compatibility lane and is not planned as a public
  prebuilt release artifact for 0.25.2
- Native Linux outputs are written under `outputs/Ubuntu-XX/`
- Berkeley DB 4.8 is bootstrapped into the repo cache for legacy wallet
  compatibility
- Dual-wallet builds enable both Berkeley DB and SQLite

Recommended hardened Ubuntu 26 release build:

```bash
DOCKER_NATIVE=sidgrip/native-base:26.04 \
  ./build.sh --native --both --build-docker --hardened-release --jobs 5
```

The hardened Linux release profile requires:

- `USE_BDB=true`
- `USE_SQLITE=true`
- `ENABLE_ZMQ=true`
- `ENABLE_USDT_TRACEPOINTS=true`

### AppImage

```bash
./build.sh --appimage --pull-docker
```

- Uses `sidgrip/appimage-base:22.04`
- Produces a portable Linux AppImage under `outputs/AppImage/`
- Intended for Ubuntu 22.04 and newer
- If the host lacks FUSE support, launch with `--appimage-extract-and-run`

### Windows

```bash
./build.sh --windows --both --pull-docker
```

- Windows release artifacts come from the MXE cross-compile container
- Uses `sidgrip/mxe-base:latest`
- Outputs are written under `outputs/Windows/`
- Native Windows builds are diagnostic only and are not the release lane because
  they do not package the same bundled DLL/runtime layout

### macOS

There are two macOS build paths:

#### Native macOS release build

```bash
./build.sh --native --both
```

- Uses Homebrew on the Mac host
- Public macOS releases should come from the native Mac build lane
- Outputs are written under `outputs/Macosx/`

#### osxcross container validation build

```bash
./build.sh --macos --both --pull-docker
```

- Uses `sidgrip/osxcross-base:sdk-26.2`
- Keeps a builder-side macOS cross-build lane available for validation and
  backup release engineering
- Outputs are written under `outputs/Macosx/`

## Output Structure

```text
outputs/
├── AppImage/
│   ├── Blakecoin-0.25.2-x86_64.AppImage
│   ├── README.md
│   └── build-info.txt
├── Macosx/
│   ├── Blakecoin-Qt.app
│   ├── blakecoin-cli-0.25.2
│   ├── blakecoin-qt-0.25.2
│   ├── blakecoin-tx-0.25.2
│   ├── blakecoin-wallet-0.25.2
│   ├── blakecoin-util-0.25.2
│   ├── blakecoind-0.25.2
│   └── build-info.txt
├── Ubuntu-20/
├── Ubuntu-22/
├── Ubuntu-24/
├── Ubuntu-25/
├── Ubuntu-26/
└── Windows/
    ├── blakecoin-cli-0.25.2.exe
    ├── blakecoin-qt-0.25.2.exe
    ├── blakecoin-tx-0.25.2.exe
    ├── blakecoin-wallet-0.25.2.exe
    ├── blakecoin-util-0.25.2.exe
    ├── blakecoind-0.25.2.exe
    └── build-info.txt
```

Each Ubuntu output folder includes runtime notes and dependency helpers for that
lane. Windows output includes the cross-built executables plus the runtime DLLs
and Qt assets needed by the release bundle.

## Docker Images

When using `--pull-docker`, the build script uses these prebuilt images:

| Image | Purpose |
|---|---|
| `sidgrip/native-base:20.04` | Native Linux Ubuntu 20.04 compatibility build |
| `sidgrip/native-base:22.04` | Native Linux Ubuntu 22.04 compatibility build |
| `sidgrip/native-base:24.04` | Native Linux Ubuntu 24.04 compatibility build |
| `sidgrip/native-base:26.04` | Native Linux Ubuntu 26.04 public release lane |
| `sidgrip/appimage-base:22.04` | Ubuntu 22+ AppImage build |
| `sidgrip/mxe-base:latest` | Windows MXE cross-compile |
| `sidgrip/osxcross-base:sdk-26.2` | macOS osxcross validation build |

## Testing

Recommended validation commands:

```bash
./build.sh --native --both --no-docker --hardened-release --jobs 5
src/test/test_bitcoin
python3 test/functional/feature_atomic_swap_htlc.py --descriptors
python3 test/functional/feature_cltv.py
python3 test/functional/feature_csv_activation.py
python3 test/functional/feature_segwit.py --descriptors
python3 test/functional/feature_segwit.py --legacy-wallet
python3 test/functional/feature_taproot.py
python3 test/functional/wallet_taproot.py --descriptors
```

For final public release, repeat the relevant artifact builds for each supported
platform, verify daemon/CLI/wallet/Qt runtime smoke tests, verify ZMQ and Linux
USDT where supported, then produce checksums and signed release artifacts.

## License

Blakecoin Core is released under the terms of the MIT license. See
[COPYING](COPYING) for details.
