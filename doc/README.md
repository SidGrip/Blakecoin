Blakecoin Core
=============

Setup
---------------------
Blakecoin Core is the Blakecoin full node and wallet software. It downloads and, by default, stores the full Blakecoin chain history. Depending on the speed of your computer and network connection, the synchronization process can take time to complete.

To download Blakecoin Core, visit the Blakecoin project repository.

Running
---------------------
The following are some helpful notes on how to run Blakecoin Core on your native platform.

### Unix

Unpack the files into a directory and run:

- `bin/blakecoin-qt` (GUI) or
- `bin/blakecoind` (headless)

### Windows

Unpack the files into a directory, and then run blakecoin-qt.exe.

### macOS

Drag Blakecoin Core to your applications folder, and then run Blakecoin Core.

### Need Help?

* See the Blakecoin project repository for help and more information.

Building
---------------------
The following are developer notes on how to build Blakecoin Core on your native platform. They are not complete guides, but include notes on the necessary libraries, compile flags, etc.

- [Dependencies](dependencies.md)
- [macOS Build Notes](build-osx.md)
- [Unix Build Notes](build-unix.md)
- [Windows Build Notes](build-windows.md)
- [FreeBSD Build Notes](build-freebsd.md)
- [OpenBSD Build Notes](build-openbsd.md)
- [NetBSD Build Notes](build-netbsd.md)
- [Android Build Notes](build-android.md)

Development
---------------------
The Blakecoin repo's [root README](/README.md) contains relevant information on the development process and automated testing.

- [Developer Notes](developer-notes.md)
- [Productivity Notes](productivity.md)
- [Release Process](release-process.md)
- [Source Code Documentation (External Link)](https://doxygen.bitcoincore.org/)
- [Translation Process](translation_process.md)
- [Translation Strings Policy](translation_strings_policy.md)
- [JSON-RPC Interface](JSON-RPC-interface.md)
- [Unauthenticated REST Interface](REST-interface.md)
- [Shared Libraries](shared-libraries.md)
- [BIPS](bips.md)
- [Dnsseed Policy](dnsseed-policy.md)
- [Benchmarking](benchmarking.md)
- [Internal Design Docs](design/)

### Resources
* Discuss project-specific development through the Blakecoin project channels.

### Miscellaneous
- [Assets Attribution](assets-attribution.md)
- [blakecoin.conf Configuration File](blakecoin-conf.md)
- [CJDNS Support](cjdns.md)
- [Files](files.md)
- [Fuzz-testing](fuzzing.md)
- [I2P Support](i2p.md)
- [Init Scripts (systemd/upstart/openrc)](init.md)
- [Managing Wallets](managing-wallets.md)
- [Multisig Tutorial](multisig-tutorial.md)
- [P2P bad ports definition and list](p2p-bad-ports.md)
- [PSBT support](psbt.md)
- [Reduce Memory](reduce-memory.md)
- [Reduce Traffic](reduce-traffic.md)
- [Tor Support](tor.md)
- [Transaction Relay Policy](policy/README.md)
- [ZMQ](zmq.md)

License
---------------------
Distributed under the [MIT software license](/COPYING).
