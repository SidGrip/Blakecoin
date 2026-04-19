# Blakecoin 0.15.2 Clean SegWit Core-Port Source of Truth

## Status

This repository is a clean core-port built from the original `Blakecoin-0.15.2` tree, with `Blakecoin-0.15.2-segwit` used only as a donor reference.

Current intent:

- Keep the original Blakecoin network identities and default network selection behavior.
- Preserve `main` and `test` from the original Blakecoin lineage, and keep the `0.15.2` third network as a Blakecoin-wired `regtest` for local-only development use.
- Port the SegWit, Bech32, wallet, RPC, and Qt address-handling changes required for a clean Core upgrade.
- Keep Lightning documented as a follow-on dependency path, not as native C++ code inside `blakecoind` or `blakecoin-qt`.

## Mainnet Safety Rule

This is a hard operational rule for development, QA, and pre-release validation:

- Do not mine on mainnet while validating this port.
- Do not send transactions on mainnet while validating this port.
- Use `-testnet`, `-regtest`, or isolated environments for active transaction flow testing.
- This is not a runtime block in the code. It is a release-engineering and validation rule to avoid risking a fork.

## Scope Boundaries

In scope:

- SegWit destination plumbing
- Bech32 address encoding and decoding
- Wallet output type selection
- Witness-aware RPC address handling
- Qt receive/send address handling
- Explicit CSV and SegWit activation on preserved `main`, `test`, and `regtest`

Out of scope unless promoted later:

- Devnet-only network additions and policy
- Vendored Electrum trees
- Faucet, explorer, Eloipool, QA harness, and other surrounding infra trees
- `pre-segwit`
- Unrelated chain-policy or portability changes from the donor tree
- A native C++ Lightning implementation inside this repo

## Baseline Repositories

- Base source: `Blakecoin-0.15.2`
- Donor reference: `Blakecoin-0.15.2-segwit`
- Clean update target: `Blakecoin-0.15.2-update`

Historical note:

- The older Blakecoin `0.8.x` line did not have a native `regtest` network. It only switched between mainnet and testnet.
- This port keeps the third network provided by `0.15.2`, but wires it for Blakecoin use instead of leaving inherited Bitcoin defaults in place.

## Network and Address Matrix

The address families must remain network-specific. Mainnet, testnet, and regtest are intentionally different.

| Network | Legacy pubkey prefix | Legacy script prefix | Bech32 HRP | Example native SegWit shape | Notes |
| --- | --- | --- | --- | --- | --- |
| `main` | `26` | `7` | `blc` | `blc1...` | Preserve original mainnet identity |
| `test` | `142` | `170` | `tblc` | `tblc1...` | Preserve original testnet identity |
| `regtest` | `26` | `7` | `rblc` | `rblc1...` | Keep the `0.15.2` third network, but wire it as Blakecoin-local regtest; `0.8.x` had no regtest |

Address families in this port:

- `legacy`
- `p2sh-segwit`
- `bech32`

Important behavior:

- `legacy` and `p2sh-segwit` use network-specific Base58 version bytes.
- `bech32` uses the network-specific human-readable part from `CChainParams::Bech32HRP()`.
- Mainnet and testnet addresses must never be interchangeable.
- `regtest` is retained from `0.15.2` as a local development network and should follow Blakecoin timing, prefixes, and activation behavior rather than inherited Bitcoin defaults.
- `test` should mirror Blakecoin consensus structure where practical: no halving, disabled BIP34/65/66, Blakecoin `powLimit`, 20-block retarget window, and a `15 / 20` activation threshold.
- `regtest` should keep local-testing conveniences from `0.15.2`, but use Blakecoin timing with `nPowTargetTimespan = 20 * 3 * 60` and `nPowTargetSpacing = 3 * 60`.

## Implementation Summary

Completed port areas:

- Added Bech32 encoder and decoder support.
- Expanded `CTxDestination` to carry witness keyhash and witness scripthash destinations.
- Replaced legacy-only address parsing paths with generic `EncodeDestination` and `DecodeDestination` usage.
- Added wallet output-type control for `legacy`, `p2sh-segwit`, and `bech32`.
- Added witness-aware receive address generation in Qt.
- Kept CSV active across preserved networks, while moving Blakecoin mainnet SegWit to a scheduled rollout window that starts one week before the aux coins.
- Preserved Blakecoin-specific Base58 checksum behavior and Blakecoin signing/hash assumptions.

## Port Matrix

### Address Encoding and Destination Plumbing

| Original file(s) | Donor reference file(s) | Change intent | Keep or drop | Acceptance check |
| --- | --- | --- | --- | --- |
| `src/base58.h`, `src/base58.cpp` | same | Add generic destination encode/decode and witness-aware validation | Keep | Legacy, wrapped SegWit, and Bech32 addresses round-trip |
| `src/bech32.h`, `src/bech32.cpp` | same | Add Bech32 primitives | Keep | Bech32 encode/decode works with Blakecoin HRPs |
| `src/script/standard.h`, `src/script/standard.cpp` | same | Add witness destination variants and script extraction/building | Keep | Witness destinations extract from scriptPubKey and re-encode |
| `src/utilstrencodings.h` | same | Add `ConvertBits` helper used by Bech32 | Keep | Witness program conversion compiles and passes round-trip tests |

Notes:

- Preserve Blakecoin Base58 checksum behavior in `src/base58.cpp`.
- Use generic destination helpers instead of legacy-only `CBitcoinAddress` assumptions.

### Wallet and Keystore

| Original file(s) | Donor reference file(s) | Change intent | Keep or drop | Acceptance check |
| --- | --- | --- | --- | --- |
| `src/keystore.h`, `src/keystore.cpp` | same | Learn related witness scripts and resolve keys from generic destinations | Keep | Imported/generated keys map to all valid address forms |
| `src/wallet/wallet.h`, `src/wallet/wallet.cpp` | same | Add `OutputType`, address/change defaults, witness script learning, destination generation | Keep | `-addresstype`, `-changetype`, change selection, and receive generation behave correctly |
| `src/wallet/coincontrol.h` | same | Carry per-send change type | Keep | `fundrawtransaction` and wallet spending can select change format |
| `src/wallet/walletdb.cpp` | same | Decode and store generic destinations in address book / destdata | Keep | Wallet DB loads witness-aware address book entries |
| `src/wallet/rpcdump.cpp` | same | Import/export keys and addresses across all destination forms | Keep | `importprivkey`, `importpubkey`, `dumpprivkey`, `dumpwallet` understand witness-capable keys |

### RPC and CLI

| Original file(s) | Donor reference file(s) | Change intent | Keep or drop | Acceptance check |
| --- | --- | --- | --- | --- |
| `src/wallet/rpcwallet.cpp` | same | Add output-type aware `getnewaddress`, `getrawchangeaddress`, generic address handling, change-type option | Keep | RPCs return requested address family and validate destinations generically |
| `src/rpc/misc.cpp` | same | Make `validateaddress` and multisig helpers witness-aware | Keep | `validateaddress` reports witness destinations correctly |
| `src/rpc/rawtransaction.cpp` | same | Decode generic destinations in raw tx construction and decoding | Keep | `createrawtransaction` and `decodescript` understand witness destinations |
| `src/rpc/mining.cpp` | same | Support generic decoded destination in `generatetoaddress` | Keep | Address parsing accepts witness formats |
| `src/bitcoin-tx.cpp` | same | Support generic destination parsing in CLI transaction mutation | Keep | `bitcoin-tx` can build outputs for witness destinations |
| `src/core_write.cpp` | same | Use generic destination formatter in JSON/script output | Keep | Decoded transaction JSON shows witness-aware addresses |

### Qt

| Original file(s) | Donor reference file(s) | Change intent | Keep or drop | Acceptance check |
| --- | --- | --- | --- | --- |
| `src/qt/walletmodel.h`, `src/qt/walletmodel.cpp` | same | Validate, decode, encode, and expose default output type | Keep | UI uses witness-aware validation and address generation |
| `src/qt/addresstablemodel.h`, `src/qt/addresstablemodel.cpp` | same | Generate receive addresses with requested output type | Keep | New receive entries can be legacy, wrapped SegWit, or Bech32 |
| `src/qt/receivecoinsdialog.cpp`, `src/qt/forms/receivecoinsdialog.ui` | same | Add receive-address type selector | Keep | Receive dialog exposes `Legacy`, `P2SH-SegWit`, `Bech32 (blc1...)` |
| `src/qt/bitcoinaddressvalidator.cpp` | same | Accept witness destination strings and lowercase Bech32 | Keep | UI validation accepts valid Bech32 input |
| `src/qt/paymentserver.cpp`, `src/qt/guiutil.cpp`, `src/qt/sendcoinsdialog.cpp`, `src/qt/transactiondesc.cpp`, `src/qt/transactionrecord.cpp`, `src/qt/coincontroldialog.cpp` | same | Make parsing and display witness-aware | Keep | URIs, send flow, transaction details, and coin control use generic destinations |
| `src/qt/test/wallettests.cpp` | same | Update wallet Qt tests to use generic destinations | Keep | Qt wallet tests compile with destination changes |

### Chain Params and Activation

| Original file(s) | Donor reference file(s) | Change intent | Keep or drop | Acceptance check |
| --- | --- | --- | --- | --- |
| `src/consensus/params.h` | same | Add `ALWAYS_ACTIVE` and `NO_TIMEOUT` constants needed by BIP9-style deployment handling | Keep | Deployments compile and can express both immediate and scheduled activation windows |
| `src/versionbits.cpp` | same | Honor `ALWAYS_ACTIVE` in threshold state logic | Keep | CSV stays active where intended and scheduled deployments transition without state drift |
| `src/chainparams.h`, `src/chainparams.cpp` | same | Add Bech32 HRPs, keep CSV active, schedule Blakecoin mainnet SegWit one week ahead of the aux coins, preserve Blakecoin `main` / `test`, and keep `regtest` from `0.15.2` as a Blakecoin-wired local test network | Keep | Main/test keep Blakecoin identity, regtest keeps local-test behavior but uses Blakecoin timing/prefix assumptions, CSV remains active, and mainnet SegWit follows the documented rollout window |

### Build and Tests

| Original file(s) | Donor reference file(s) | Change intent | Keep or drop | Acceptance check |
| --- | --- | --- | --- | --- |
| `src/Makefile.am` | same | Add Bech32 sources to the build | Keep | `bech32.cpp` and `bech32.h` are compiled and linked |
| `src/Makefile.qt.include`, `src/qt/bitcoin_locale.qrc` | local clean-port fix | Align Qt translation targets with the files actually tracked in this repository | Keep | Qt build no longer fails on missing translation files |
| `src/test/base58_tests.cpp` | same | Add destination round-trip coverage including witness addresses | Keep | Legacy and witness address forms pass focused tests |

Build tooling note:

- `build.sh` in this repo now intentionally reuses the hardened build logic from `Blakecoin-0.15.2-segwit` for macOS container builds, native Windows builds, and temp-tree cleanup.
- The adopted script must stay mainnet-safe: keep mainnet ports, mainnet output names, `~/.blakecoin/blakecoin.conf`, explorer-based peer discovery, and no devnet-only branding or hardcoded devnet peers.
- The macOS Docker path should default to the newer depends + `CONFIG_SITE` flow, while keeping the legacy osxcross fallback switch available for troubleshooting.

Build server validation note:

- On build server `192.168.1.221`, Docker builds for native Linux, Windows, and AppImage completed successfully from `Blakecoin-0.15.2-update`.
- The default macOS depends path failed while building the old Boost `1_64_0` package because the Darwin build ended up invoking plain `g++` with Darwin-only flags such as `-fcoalesce-templates`.
- The legacy macOS osxcross path succeeded on the same server using `MACOS_CROSS_STRATEGY=legacy`.
- Bitcoin Core's current `depends` tree should be treated as the reference for the future macOS cleanup, especially its builder/host split and Darwin clang toolchain handling, but it cannot be dropped into this `0.15.2` tree unchanged because this fork still carries the older Boost/B2-era depends recipes.

## Code Patterns to Preserve

### 1. Generic Destination Formatting

Use generic destination helpers everywhere address strings cross an API boundary:

```cpp
std::string EncodeDestination(const CTxDestination& dest);
CTxDestination DecodeDestination(const std::string& str);
bool IsValidDestinationString(const std::string& str);
```

Reason:

- This cleanly supports `legacy`, `p2sh-segwit`, and `bech32`.
- It removes legacy-only assumptions tied to `CBitcoinAddress`.

### 2. Witness Destination Types in `CTxDestination`

Witness support is represented directly in `CTxDestination`:

```cpp
typedef boost::variant<
    CNoDestination,
    CKeyID,
    CScriptID,
    WitnessV0ScriptHash,
    WitnessV0KeyHash
> CTxDestination;
```

Reason:

- Script extraction, wallet book-keeping, and UI display all share the same destination representation.

### 3. Wallet Output Type

The wallet now carries explicit output type policy:

```cpp
enum OutputType : int
{
    OUTPUT_TYPE_NONE,
    OUTPUT_TYPE_LEGACY,
    OUTPUT_TYPE_P2SH_SEGWIT,
    OUTPUT_TYPE_BECH32,
    OUTPUT_TYPE_DEFAULT = OUTPUT_TYPE_LEGACY,
};
```

Companion helpers:

```cpp
OutputType ParseOutputType(const std::string& str, OutputType default_type);
const std::string& FormatOutputType(OutputType type);
CTxDestination GetDestinationForKey(const CPubKey& key, OutputType type);
```

Reason:

- Receive address creation and change output selection need to be explicit and testable.

### 4. Related Script Learning

When a compressed pubkey is used for SegWit-capable address types, related scripts must be learned:

```cpp
void CWallet::LearnRelatedScripts(const CPubKey& key, OutputType type)
{
    if (key.IsCompressed() && (type == OUTPUT_TYPE_P2SH_SEGWIT || type == OUTPUT_TYPE_BECH32)) {
        CTxDestination witdest = WitnessV0KeyHash(key.GetID());
        CScript witprog = GetScriptForDestination(witdest);
        AddCScript(witprog);
    }
}
```

Reason:

- Wrapped SegWit and native SegWit both depend on wallet knowledge of the witness program.

### 5. Change Type Selection

Change selection must not silently regress to legacy when the transaction is already witness-aware:

```cpp
OutputType CWallet::TransactionChangeType(OutputType change_type, const std::vector<CRecipient>& vecSend)
{
    if (change_type != OUTPUT_TYPE_NONE) return change_type;
    if (g_address_type == OUTPUT_TYPE_LEGACY) return OUTPUT_TYPE_LEGACY;

    for (const CRecipient& recipient : vecSend) {
        int witnessversion = 0;
        std::vector<unsigned char> witnessprogram;
        if (recipient.scriptPubKey.IsWitnessProgram(witnessversion, witnessprogram)) {
            return OUTPUT_TYPE_BECH32;
        }
    }
    return g_address_type;
}
```

Reason:

- Witness spends should prefer witness change unless explicitly overridden.

### 6. RPC Address-Type Handling

`getnewaddress` and `getrawchangeaddress` now accept output-type requests:

```cpp
getnewaddress ( "account" "address_type" )
getrawchangeaddress ( "address_type" )
```

`fundrawtransaction` now supports:

```json
{
  "change_type": "legacy | p2sh-segwit | bech32"
}
```

Reason:

- RPC must expose the same address-policy controls as the wallet and Qt layers.

### 7. Qt Receive Address Type Selector

The receive dialog now exposes explicit address type selection:

- `Legacy`
- `P2SH-SegWit`
- `Bech32 (blc1...)`

Implementation anchor:

```cpp
OutputType AddressTypeForIndex(int index);
ui->addressType->setCurrentIndex(AddressTypeIndex(model->getDefaultAddressType()));
address = model->getAddressTableModel()->addRow(AddressTableModel::Receive, label, "", addressType);
```

Reason:

- Users need visible control over which receive format they create.

### 8. Preserved-Network SegWit Activation

CSV remains active on preserved networks, while Blakecoin mainnet SegWit now uses a staged rollout that begins one week before the aux coins:

```cpp
consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;

// Blakecoin mainnet rollout:
consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = 1777852800; // May 4, 2026 00:00:00 UTC
consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = 1809388800; // May 4, 2027 00:00:00 UTC
```

Network intent:

- `main`: CSV stays active; SegWit starts signaling on May 4, 2026 00:00:00 UTC.
- `testnet`: CSV and SegWit remain immediately usable for testing.
- `regtest`: CSV and SegWit remain immediately usable for local development and QA.
- AuxPoW coin mainnet rollout follows one week later on May 11, 2026 00:00:00 UTC.

HRPs are explicit per network:

```cpp
bech32_hrp = "blc";   // main
bech32_hrp = "tblc";  // testnet
bech32_hrp = "rblc";  // regtest
```

Reason:

- We want a clean port on the original networks, not a devnet-only branch.
- The legacy `0.8.x` source had no regtest, so the `0.15.2` regtest network is kept intentionally and adapted for Blakecoin-specific local testing.

Concrete parameter intent for this port:

- `test`: `nSubsidyHalvingInterval = std::numeric_limits<int>::max()`, `BIP34/65/66 = 100000000`, `BIP34Hash = uint256()`, `powLimit = 000000ffff...`, `nPowTargetTimespan = 20 * 3 * 60`, `nRuleChangeActivationThreshold = 15`, `nMinerConfirmationWindow = 20`
- `regtest`: keep regtest-only test heights and local mining behavior, but set `nPowTargetTimespan = 20 * 3 * 60` and `nPowTargetSpacing = 3 * 60`

## Blakecoin-Specific Requirements

These are not optional:

- Preserve Blakecoin Base58 checksum behavior.
- Preserve Blakecoin transaction/signature hashing expectations where witness-signing logic touches digest code paths.
- Do not pull in donor devnet consensus behavior just because it co-exists with SegWit changes.
- Do not treat regtest as a Bitcoin-default network. In this port it is a retained `0.15.2` local network that must be wired for Blakecoin use.

## Explicit Keep / Drop Decisions

Keep:

- SegWit destination types
- Bech32 encoder/decoder
- Witness-aware wallet address generation
- Witness-aware RPC parsing and formatting
- Qt receive address-type selection
- Explicit CSV activation and scheduled Blakecoin mainnet SegWit rollout on the preserved networks

Drop:

- Extra devnet network and devnet-only activation policy
- Devnet compatibility shims in validation paths
- Donor-side infra directories unrelated to Core porting
- Unrelated donor fixes unless they become required to complete the clean port

## Lightning Follow-On

Lightning is documented here as an external dependency path, not an in-repo C++ feature.

Source-of-truth position:

- This clean port delivers the SegWit and Bech32 support required before Lightning is practical.
- The proven Lightning path remains Electrum-based and external to `blakecoind` and `blakecoin-qt`.
- Do not vendor Electrum or Lightning trees into this clean Core port repository.

## Verification Checklist

Required verification:

- Build `blakecoind`, `blakecoin-cli`, `blakecoin-tx`, Qt, and tests from this repo.
- Confirm Base58 and Bech32 destination round-trips.
- Confirm `getnewaddress`, `getrawchangeaddress`, and `validateaddress` across `legacy`, `p2sh-segwit`, and `bech32`.
- Confirm Qt receive address generation for all three address families.
- Confirm CSV reports active on preserved `main`, `test`, and `regtest`, while Blakecoin mainnet SegWit reports the documented May 4, 2026 to May 4, 2027 deployment window.
- Confirm retained `regtest` behavior is Blakecoin-native for local testing, not left on inherited Bitcoin timing defaults.
- Keep all active send/mining verification off mainnet.

## Remaining Caution

If any future donor diff mixes SegWit work with unrelated behavioral changes, stop and split the change before porting it. This file is the source of truth: clean Core port first, no accidental devnet carry-over, no mainnet activity during validation.

## SegWit Activation Test

- Functional test: `test/functional/segwit-activation-smoke.py`
- Build-server wrapper: `/home/sid/Blakestream-Installer/qa/runtime/run-segwit-activation-suite.sh`
- Direct command used by the wrapper:

```bash
BITCOIND=/path/to/blakecoind BITCOINCLI=/path/to/blakecoin-cli \
python3 ./test/functional/segwit-activation-smoke.py \
  --srcdir="$(pwd)/src" \
  --tmpdir="<artifact_root>/blakecoin/<timestamp>/tmpdir" \
  --nocleanup \
  --loglevel=DEBUG \
  --tracerpc
```

- Expected regtest Bech32 prefix: `rblc1`
- Review artifacts:
  `summary.json`, `state-defined.json`, `state-started.json`, `state-locked_in.json`, `state-active.json`, `address-sanity.json`, `combined-regtest.log`, `tmpdir/test_framework.log`, `tmpdir/node*/regtest/debug.log`
- Successful all-six build-server run:
  `/home/sid/Blakestream-Installer/outputs/segwit-activation/20260412T083423Z/run-summary.md`
- Coin artifact directory:
  `/home/sid/Blakestream-Installer/outputs/segwit-activation/20260412T083423Z/blakecoin`
- Harness note:
  the final witness proposal builder now takes the coinbase amount directly from `getblocktemplate()["coinbasevalue"]`, which keeps the activation proof aligned with each chain's real subsidy rules.
- Safety rule:
  regtest only for activation validation; do not mine or send transactions on mainnet while rollout QA is still in progress.

## AuxPoW Testnet Merged-Mining Verification

- Final successful container-built run:
  `/home/sid/Blakestream-Installer/outputs/auxpow-testnet/20260413T003341Z/run-summary.md`
- Wrapper command:
  `bash /home/sid/Blakestream-Installer/qa/auxpow-testnet/run-auxpow-testnet-suite.sh`
- Scope:
  build-server-only, private isolated `-testnet` harness; Blakecoin acted as the parent chain for BlakeBitcoin, lithium, Photon, UniversalMolecule, and Electron-ELT.
- Verified:
  local-only parent peers, Eloipool upstream on Blakecoin testnet magic, merged-mine proxy health, accepted parent blocks through the pilot, 4-child batch, and full 5-child proof, plus preserved artifacts under the run root above.
- QC note:
  the real child chain IDs required collision-free merged-mining slot sizing of `1` for the single-child pilot, `8` for the 4-child batch, and `16` for the 5-child full proof. The earlier `1/4/8` assumption was too small for these chain IDs under the Namecoin-style merkle-slot formula.
- Safety rule:
  testnet only for merged-mining QA; do not mine or send transactions on mainnet while AuxPoW rollout validation is still in progress.

## Devnet/Testnet Validation Outcomes

- SegWit activation validation passed on isolated regtest. See:
  `/home/sid/Blakestream-Installer/outputs/segwit-activation/20260412T083423Z/blakecoin`
- Blakecoin also acted as the parent chain in the isolated AuxPoW merged-mining proof. See:
  `/home/sid/Blakestream-Installer/outputs/auxpow-testnet/20260413T003341Z/blakecoin`
- Mainnet carry-back audit for the devnet copy lives in:
  `mainnet-carryback-audit-2026-04-18.md`
- Audit result:
  the diff between this clean update repo and the devnet `coins/Blakecoin` copy stayed limited to devnet `chainparams*`, Qt network-labeling files, and build-tree cleanup. No new Blakecoin core wallet, consensus, or RPC carry-back was identified from the devnet copy itself.

## Mainnet Carry-Back Decisions

- This repo remains the canonical mainnet C++ core line for Blakecoin.
- Do not merge devnet ports, message starts, datadir changes, or activation shortcuts back into this repo.
- Pool/runtime carry-back work is tracked in the mainnet Eloipool repo, not here.
- Electrum / Lightning compatibility carry-back work is tracked in the Electrium repo, not here.
- The checksum-bridge remains a separate operational track under `Blakecoin-0.15.2-update-checksum` and is not part of this repo's mainline carry-back set.

## Not Carried Back From Devnet

- `src/chainparams.cpp`, `src/chainparamsbase.cpp`, `src/chainparamsbase.h`
- `src/qt/guiconstants.h`, `src/qt/guiutil.cpp`, `src/qt/networkstyle.cpp`
- Any private-testnet `BIP65Height = 1`, `ALWAYS_ACTIVE`, devnet ports, message starts, datadirs, or local-only harness shortcuts
- Pool UI, merged-mine proxy, Electrium, ElectrumX, and builder/runtime scripts

## Pool / Electrium Dependencies

- Blakecoin remains the parent chain for the shared BlakeStream AuxPoW pool design.
- Mainnet pool promotion work depends on the Eloipool carry-back set, including the mining-key contract and the proven multi-miner aux-child payout path.
- The proven Lightning-adjacent wallet path remains Electrium-based; wallet-side sync and signing carry-back work lives in the Electrium repo, not in this C++ core repo.

## Safety Rule

- Do not mine on mainnet while carry-back staging is in progress.
- Do not send transactions on mainnet while carry-back staging is in progress.
- Use isolated regtest, testnet, or staging environments until rollout QA is complete.

## April 18, 2026 Devnet Validation Snapshot

- Shared BlakeStream devnet run `20260418T195508Z` proved two concurrent mining-key identities in one live pool session:
  `a5d3e00343efe51e81d39884a74124ca060fefdd` and
  `848011948321a4a6f81415568b79860ec242ac3e`.
- Both identities became active in the live dashboard and both solved parent-plus-aux work in the same running session.
- Blakecoin remained the parent chain during this proof. The carry-back value from this run is therefore operational:
  pool/runtime/template freshness, multi-miner identity tracking, and downstream wallet/pool compatibility,
  not new Blakecoin-only C++ consensus changes.

## Mainnet Carry-Back Snapshot

- Ready to carry back from this proof:
  pool-side per-solver mining-key identity plumbing,
  fresher aux-template cache handling in the proxy/runtime path,
  and the per-chain solved-block/share accounting that made the proof auditable.
- Not carried back into this core repo:
  devnet network settings, private-testnet shortcuts, builder/runtime scripts,
  or any pool/UI/Electrium scaffolding.
- The checksum-bridge remains a separate operational track under
  `Blakecoin-0.15.2-update-checksum` and is not part of this repo's mainline carry-back set.

## April 19, 2026 Broader Electrium Staging Closure

- The broader staged packaged-client proof is now green at:
  `/home/sid/Blakestream-Devnet/outputs/electrium-staging/20260419T053030Z/run-summary.md`
- All six packaged Electrium clients connected successfully against the staged
  local ElectrumX backends in that run, including Blakecoin on `127.0.0.1:51001`.
- For Blakecoin, this closes the last wallet-side broader staging dependency in
  the readiness checklist.
- No new Blakecoin-specific C++ consensus or RPC carry-back was identified in
  this pass; the carry-back value remains pool/runtime promotion in Eloipool
  and wallet-side promotion in Electrium/ElectrumX.
