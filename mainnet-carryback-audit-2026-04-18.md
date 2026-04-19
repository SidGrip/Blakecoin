# Blakecoin Mainnet Carry-Back Audit — 2026-04-18

## Summary

- Source compared:
  `/home/sid/Blakestream-Installer/repos/Blakecoin-0.15.2-update/src`
- Devnet copy compared:
  `/home/sid/Blakestream-Devnet/coins/Blakecoin/src`
- Result:
  no new Blakecoin core wallet, consensus, or RPC promotion was discovered in the devnet copy. The meaningful carry-back work for this cycle lives in Eloipool and Electrium, not in the Blakecoin core tree.

## Diff Classification

### Devnet-Only Differences

- `src/chainparams.cpp`
- `src/chainparamsbase.cpp`
- `src/chainparamsbase.h`
- `src/qt/guiconstants.h`
- `src/qt/guiutil.cpp`
- `src/qt/networkstyle.cpp`

Reason:
- these files reflect devnet chain selection, local datadir/default-network behavior, or devnet-facing Qt network labeling

### Build Cleanup Only

- generated `Makefile.in` removal in the devnet copy
- `src/secp256k1/Makefile.am` build-tree cleanup

Reason:
- build-tree cleanup does not represent a new Blakecoin protocol, wallet, or RPC change to promote into the mainnet core line

## Carry-Back Decision

- Keep this repo as the canonical Blakecoin mainnet core line.
- Do not port devnet network identity, datadir, or activation shortcuts into this repo.
- Track pool carry-back separately in the mainnet Eloipool repo.
- Track wallet sync/signing carry-back separately in the Electrium repo.
- Track checksum-bridge operations separately in `Blakecoin-0.15.2-update-checksum`.
