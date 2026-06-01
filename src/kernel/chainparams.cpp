// Copyright (c) 2010 Satoshi Nakamoto
// Copyright (c) 2009-2021 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <kernel/chainparams.h>

#include <chainparamsseeds.h>
#include <consensus/amount.h>
#include <consensus/merkle.h>
#include <consensus/params.h>
#include <hash.h>
#include <chainparamsbase.h>
#include <logging.h>
#include <primitives/block.h>
#include <primitives/transaction.h>
#include <script/interpreter.h>
#include <script/script.h>
#include <uint256.h>
#include <util/strencodings.h>

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <limits>
#include <type_traits>

static CBlock CreateGenesisBlock(const char* pszTimestamp, const CScript& genesisOutputScript, uint32_t nTime, uint32_t nNonce, uint32_t nBits, int32_t nVersion, const CAmount& genesisReward)
{
    CMutableTransaction txNew;
    txNew.nVersion = 1;
    txNew.vin.resize(1);
    txNew.vout.resize(1);
    txNew.vin[0].scriptSig = CScript() << 486604799 << CScriptNum(4) << std::vector<unsigned char>((const unsigned char*)pszTimestamp, (const unsigned char*)pszTimestamp + strlen(pszTimestamp));
    txNew.vout[0].nValue = genesisReward;
    txNew.vout[0].scriptPubKey = genesisOutputScript;

    CBlock genesis;
    genesis.nTime    = nTime;
    genesis.nBits    = nBits;
    genesis.nNonce   = nNonce;
    genesis.nVersion = nVersion;
    genesis.vtx.push_back(MakeTransactionRef(std::move(txNew)));
    genesis.hashPrevBlock.SetNull();
    genesis.hashMerkleRoot = BlockMerkleRoot(genesis);
    return genesis;
}

/**
 * Build the genesis block. Note that the output of its generation
 * transaction cannot be spent since it did not originally exist in the
 * database.
 *
 * CBlock(hash=000000000019d6, ver=1, hashPrevBlock=00000000000000, hashMerkleRoot=4a5e1e, nTime=1231006505, nBits=1d00ffff, nNonce=2083236893, vtx=1)
 *   CTransaction(hash=4a5e1e, ver=1, vin.size=1, vout.size=1, nLockTime=0)
 *     CTxIn(COutPoint(000000, -1), coinbase 04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73)
 *     CTxOut(nValue=50.00000000, scriptPubKey=0x5F1DF16B2B704C8A578D0B)
 *   vMerkleTree: 4a5e1e
 */
static CBlock CreateGenesisBlock(uint32_t nTime, uint32_t nNonce, uint32_t nBits, int32_t nVersion, const CAmount& genesisReward)
{
    const char* pszTimestamp = "The Times 03/Jan/2009 Chancellor on brink of second bailout for banks";
    const CScript genesisOutputScript = CScript() << ParseHex("04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f") << OP_CHECKSIG;
    return CreateGenesisBlock(pszTimestamp, genesisOutputScript, nTime, nNonce, nBits, nVersion, genesisReward);
}

static CBlock CreateBlakecoinGenesisBlock(uint32_t nTime, uint32_t nNonce, uint32_t nBits, int32_t nVersion, const CAmount& genesisReward)
{
    const char* pszTimestamp = "US forces target leading al-Shabaab militant in Somalian coastal raid";
    const CScript genesisOutputScript = CScript() << ParseHex("04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f") << OP_CHECKSIG;
    return CreateGenesisBlock(pszTimestamp, genesisOutputScript, nTime, nNonce, nBits, nVersion, genesisReward);
}

/**
 * Main network on which people trade goods and services.
 */
class CMainParams : public CChainParams {
public:
    CMainParams() {
        strNetworkID = CBaseChainParams::MAIN;
        consensus.signet_blocks = false;
        consensus.signet_challenge.clear();
        consensus.nSubsidyHalvingInterval = std::numeric_limits<int>::max();
        // Blakecoin 0.25.2 inherits SegWit as buried history from the 0.15.21
        // mainnet activation at height 1978980, then stages the first cleanup
        // group (BIP34/BIP65/BIP66) at height 2002950 and the Taproot BIP9
        // window after that. These are Blakecoin mainnet values only.
        consensus.BIP34Height = 2002950;
        consensus.BIP34Hash = uint256{};
        consensus.BIP65Height = 2002950;
        consensus.BIP66Height = 2002950;
        // TODO(blakestream-25.2-activation): CSV (BIP68/112/113) — atomic-swap timeout
        // primitive. Already ALWAYS_ACTIVE from genesis on the Blakestream family per
        // coin-source-of-truth.md "Common rules" line "CSV (BIP68/112/113) deployment
        // = ALWAYS_ACTIVE from genesis". CSVHeight = 1 means active from height 1.
        // Do NOT change.
        consensus.CSVHeight = 1;
        // SegWit is buried, not re-signaled, in 0.25.2.
        consensus.SegwitHeight = 1978980;
        // Ignore historical bit-1 SegWit signaling before the buried activation
        // height. Unknown-versionbit warnings remain enabled after this point.
        consensus.MinBIP9WarningHeight = 1978980;
        consensus.powLimit = uint256S("000000ffff000000000000000000000000000000000000000000000000000000");
        consensus.nPowTargetTimespan = 20 * 3 * 60;
        consensus.nPowTargetSpacing = 3 * 60;
        consensus.fPowAllowMinDifficultyBlocks = false;
        consensus.fPowNoRetargeting = false;
        consensus.nRuleChangeActivationThreshold = 19;
        consensus.nMinerConfirmationWindow = 20;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 1199145601;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = 1230767999;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0;
        // Taproot bundle BIP340/BIP341/BIP342. Start is 2026-07-01 02:00 UTC,
        // timeout is 2027-07-01 02:00 UTC, and min_activation_height is 2006310.
        // Regtest/signet remain separately configured for immediate test coverage.
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = 1782871200;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = 1814407200;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 2006310;

        consensus.nMinimumChainWork = uint256S("0x0000000000000000000000000000000000000000000000b1f8784ae8e3178c81");
        consensus.defaultAssumeValid = uint256S("0x0000000000009808e40f3b6fcaa1256c9ec0690a6d9ca99edfd9341a2859ce5b");

        /**
         * The message start string is designed to be unlikely to occur in normal data.
         * The characters are rarely used upper ASCII, not valid as UTF-8, and produce
         * a large 32-bit integer with any alignment.
         */
        pchMessageStart[0] = 0xf9;
        pchMessageStart[1] = 0xbe;
        pchMessageStart[2] = 0xb4;
        pchMessageStart[3] = 0xd2;
        nDefaultPort = 8773;
        nPruneAfterHeight = 100000;
        m_assumed_blockchain_size = 3;
        m_assumed_chain_state_size = 1;

        genesis = CreateBlakecoinGenesisBlock(1381036817, 127057407, 503382015, 112, 5 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be"));
        assert(genesis.hashMerkleRoot == uint256S("0x9e4654d5bb91c723c3dbbaee57761d06ed10ac17f4d8841746aeec7ff8206ddc"));

        vSeeds.emplace_back("seed.blakestream.io");
        vSeeds.emplace_back("seed.blakecoin.org");

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,26);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,7);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,128);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};

        bech32_hrp = "blc";
        vFixedSeeds.clear();

        fDefaultConsistencyChecks = false;
        fRequireStandard = true;
        m_is_test_chain = false;
        m_is_mockable_chain = false;

        checkpointData = {
            {
                {0, uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be")},
                {2499, uint256S("0x00000000040fcdd50c1bd5ad140039b6d8f4e7f3ad497115314c0b2c0569b285")},
                {19797, uint256S("0x000000000093b59ec621c8d8bcee44a7644e40d236e5cd126619e292e8b22a78")},
                {39253, uint256S("0x00000000000fe223ac905ab8902695a52e6c1829809a5cbbf4fdbbad5d11758c")},
                {143000, uint256S("0x000000000000178e824cad2eb1e0bd499539750c3b71b3f1c4015f1962de1062")},
                {217000, uint256S("0x000000000001d0c2645df7f149081f03e9f5612c6b44b2116b1b84c4781989e2")},
                {297313, uint256S("0x00000000000264e992d35a4775d3b4e16e807221401ebbee87ab8cd6505335b1")},
                {350620, uint256S("0x00000000000132bbab473392bec2230eccc1dcc27af3c4b088c15067734e610a")},
                {1322950, uint256S("0x0000000000003205ddd0fb453c229a5e976cccd1516a64b5893d9d41cb11b2ff")},
                {1967676, uint256S("0x00000000000037aece1cceecd449f9abf11d7f207aebd1445983b9cb61c2bbc0")},
                {1978980, uint256S("0x000000000000b1c7b12f008aac514c68fdc2911e618b64522633e0ffcd8f6054")},
                {1980000, uint256S("0x0000000000002fd870c585741727a1e8bbb0a79c7b3d2c03ef077336caf82641")},
                {1985000, uint256S("0x000000000000dd6743ea01f6d41e2b28df7632cb8a9554ad3d1b2c08984852ee")},
                {1987500, uint256S("0x0000000000009808e40f3b6fcaa1256c9ec0690a6d9ca99edfd9341a2859ce5b")},
            }
        };

        m_assumeutxo_data = MapAssumeutxo{
            {
                1987888,
                {
                    AssumeutxoHash{uint256S("0x38c4d9036604784a891b7632c5948120760bf4750c24bf407862411845fb9f61")},
                    2878384,
                },
            },
        };

        chainTxData = ChainTxData{
            .nTime    = 1779626441,
            .nTxCount = 2878265,
            .dTxRate  = 0.00580105607453496,
        };
    }
};

/**
 * Testnet (v3): public test network which is reset from time to time.
 */
class CTestNetParams : public CChainParams {
public:
    CTestNetParams() {
        strNetworkID = CBaseChainParams::TESTNET;
        consensus.signet_blocks = false;
        consensus.signet_challenge.clear();
        consensus.nSubsidyHalvingInterval = std::numeric_limits<int>::max();
        // Blakecoin 25.2 testnet is a feature-test/reset network: keep SegWit,
        // CLTV, strict-DER, BIP34 coinbase height, and Taproot available from
        // height 1 so atomic-swap and Taproot QA are valid on default testnet.
        // If an old 0.15.21 testnet history must be preserved, replace these
        // height-1 values with explicit future testnet activation heights.
        consensus.BIP34Height = 1;
        consensus.BIP34Hash = uint256{};
        consensus.BIP65Height = 1;
        consensus.BIP66Height = 1;
        // TODO(blakestream-25.2-activation): CSV (BIP68/112/113) ALWAYS_ACTIVE on
        // Blakestream family — atomic-swap timeout primitive. Do NOT change.
        consensus.CSVHeight = 1;
        // TODO(blakestream-25.2-activation): testnet SegWit ALWAYS_ACTIVE from height
        // 1 so testnet AuxPoW + atomic-swap regression coverage works without
        // waiting on the 0.15.21 mainnet activation. Do NOT change.
        consensus.SegwitHeight = 1;
        consensus.MinBIP9WarningHeight = 0;
        // Private 25.2 feature-testnet uses regtest-style PoW so local CPU
        // pool tests can advance blocks quickly while mainnet stays unchanged.
        consensus.powLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 20 * 3 * 60;
        consensus.nPowTargetSpacing = 3 * 60;
        consensus.fPowAllowMinDifficultyBlocks = true;
        consensus.fPowNoRetargeting = true;
        consensus.nRuleChangeActivationThreshold = 15;
        consensus.nMinerConfirmationWindow = 20;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 1199145601;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = 1230767999;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 0;

        consensus.nMinimumChainWork = uint256{};
        consensus.defaultAssumeValid = uint256{};

        pchMessageStart[0] = 0x0b;
        pchMessageStart[1] = 0x11;
        pchMessageStart[2] = 0x09;
        pchMessageStart[3] = 0x07;
        nDefaultPort = 18773;
        nPruneAfterHeight = 1000;
        m_assumed_blockchain_size = 0;
        m_assumed_chain_state_size = 0;

        genesis = CreateBlakecoinGenesisBlock(1381033532, 120396719, 503382015, 112, 5 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x0000006a6b8058247f5b0edb1b34df7d34ae6c963c49da21b62a4b6558ac94dc"));
        assert(genesis.hashMerkleRoot == uint256S("0x9e4654d5bb91c723c3dbbaee57761d06ed10ac17f4d8841746aeec7ff8206ddc"));

        vFixedSeeds.clear();
        vSeeds.clear();

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,142);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,170);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,239);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x35, 0x87, 0xCF};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x35, 0x83, 0x94};

        bech32_hrp = "tblc";

        fDefaultConsistencyChecks = false;
        fRequireStandard = false;
        m_is_test_chain = true;
        m_is_mockable_chain = false;

        checkpointData = {
            {
                {0, uint256S("0x0000006a6b8058247f5b0edb1b34df7d34ae6c963c49da21b62a4b6558ac94dc")},
            }
        };

        m_assumeutxo_data = MapAssumeutxo{
            // TODO to be specified in a future patch.
        };

        chainTxData = ChainTxData{
            .nTime    = 1381033532,
            .nTxCount = 1,
            .dTxRate  = 0.01,
        };
    }
};

/**
 * Signet: test network with an additional consensus parameter (see BIP325).
 */
class SigNetParams : public CChainParams {
public:
    explicit SigNetParams(const SigNetOptions& options)
    {
        std::vector<uint8_t> bin;
        vSeeds.clear();

        if (!options.challenge) {
            // Blakecoin signet defaults to a local/private developer network.
            // Keep the default challenge trivial and ship no global seeds,
            // assumevalid, or chainwork so we do not point at Bitcoin signet.
            bin = ParseHex("51");
            consensus.nMinimumChainWork = uint256{};
            consensus.defaultAssumeValid = uint256{};
            m_assumed_blockchain_size = 0;
            m_assumed_chain_state_size = 0;
            chainTxData = ChainTxData{0, 0, 0};
        } else {
            bin = *options.challenge;
            consensus.nMinimumChainWork = uint256{};
            consensus.defaultAssumeValid = uint256{};
            m_assumed_blockchain_size = 0;
            m_assumed_chain_state_size = 0;
            chainTxData = ChainTxData{
                0,
                0,
                0,
            };
            LogPrintf("Signet with challenge %s\n", HexStr(bin));
        }

        if (options.seeds) {
            vSeeds = *options.seeds;
        }

        strNetworkID = CBaseChainParams::SIGNET;
        consensus.signet_blocks = true;
        consensus.signet_challenge.assign(bin.begin(), bin.end());
        consensus.nSubsidyHalvingInterval = std::numeric_limits<int>::max();
        consensus.BIP34Height = 1;
        consensus.BIP34Hash = uint256{};
        consensus.BIP65Height = 1;
        consensus.BIP66Height = 1;
        consensus.CSVHeight = 1;
        consensus.SegwitHeight = 1;
        consensus.nPowTargetTimespan = 20 * 3 * 60;
        consensus.nPowTargetSpacing = 3 * 60;
        consensus.fPowAllowMinDifficultyBlocks = false;
        consensus.fPowNoRetargeting = false;
        consensus.nRuleChangeActivationThreshold = 19;
        consensus.nMinerConfirmationWindow = 20;
        consensus.MinBIP9WarningHeight = 0;
        consensus.powLimit = uint256S("00000377ae000000000000000000000000000000000000000000000000000000");
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = Consensus::BIP9Deployment::NEVER_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0; // No activation delay

        // Keep Taproot always active on signet so developer coverage matches
        // regtest/testnet, while mainnet activation policy waits on 0.15.21.
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 0; // No activation delay

        // message start is defined as the first 4 bytes of the sha256d of the block script
        HashWriter h{};
        h << consensus.signet_challenge;
        uint256 hash = h.GetHash();
        memcpy(pchMessageStart, hash.begin(), 4);

        nDefaultPort = 38733;
        nPruneAfterHeight = 1000;

        genesis = CreateBlakecoinGenesisBlock(1381036817, 127057407, 503382015, 112, 5 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be"));
        assert(genesis.hashMerkleRoot == uint256S("0x9e4654d5bb91c723c3dbbaee57761d06ed10ac17f4d8841746aeec7ff8206ddc"));

        vFixedSeeds.clear();

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,142);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,170);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,239);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x35, 0x87, 0xCF};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x35, 0x83, 0x94};

        bech32_hrp = "tblc";

        fDefaultConsistencyChecks = false;
        fRequireStandard = true;
        m_is_test_chain = true;
        m_is_mockable_chain = false;
    }
};

/**
 * Regression test: intended for private networks only. Has minimal difficulty to ensure that
 * blocks can be found instantly.
 */
class CRegTestParams : public CChainParams
{
public:
    explicit CRegTestParams(const RegTestOptions& opts)
    {
        strNetworkID =  CBaseChainParams::REGTEST;
        consensus.signet_blocks = false;
        consensus.signet_challenge.clear();
        consensus.nSubsidyHalvingInterval = 150;
        consensus.BIP34Height = 100000000;
        consensus.BIP34Hash = uint256{};
        consensus.BIP65Height = 1351;
        consensus.BIP66Height = 1251;
        consensus.CSVHeight = 1;
        consensus.SegwitHeight = 0;
        consensus.MinBIP9WarningHeight = 0;
        consensus.powLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 20 * 3 * 60;
        consensus.nPowTargetSpacing = 3 * 60;
        consensus.fPowAllowMinDifficultyBlocks = true;
        consensus.fPowNoRetargeting = true;
        consensus.nRuleChangeActivationThreshold = 108;
        consensus.nMinerConfirmationWindow = 144;

        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].min_activation_height = 0; // No activation delay

        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].bit = 2;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nStartTime = Consensus::BIP9Deployment::ALWAYS_ACTIVE;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].nTimeout = Consensus::BIP9Deployment::NO_TIMEOUT;
        consensus.vDeployments[Consensus::DEPLOYMENT_TAPROOT].min_activation_height = 0; // No activation delay

        consensus.nMinimumChainWork = uint256{};
        consensus.defaultAssumeValid = uint256{};

        pchMessageStart[0] = 0xfa;
        pchMessageStart[1] = 0xbf;
        pchMessageStart[2] = 0xb5;
        pchMessageStart[3] = 0xda;
        nDefaultPort = 18444;
        nPruneAfterHeight = opts.fastprune ? 100 : 1000;
        m_assumed_blockchain_size = 0;
        m_assumed_chain_state_size = 0;

        for (const auto& [dep, height] : opts.activation_heights) {
            switch (dep) {
            case Consensus::BuriedDeployment::DEPLOYMENT_SEGWIT:
                consensus.SegwitHeight = int{height};
                break;
            case Consensus::BuriedDeployment::DEPLOYMENT_HEIGHTINCB:
                consensus.BIP34Height = int{height};
                break;
            case Consensus::BuriedDeployment::DEPLOYMENT_DERSIG:
                consensus.BIP66Height = int{height};
                break;
            case Consensus::BuriedDeployment::DEPLOYMENT_CLTV:
                consensus.BIP65Height = int{height};
                break;
            case Consensus::BuriedDeployment::DEPLOYMENT_CSV:
                consensus.CSVHeight = int{height};
                break;
            }
        }

        for (const auto& [deployment_pos, version_bits_params] : opts.version_bits_parameters) {
            consensus.vDeployments[deployment_pos].nStartTime = version_bits_params.start_time;
            consensus.vDeployments[deployment_pos].nTimeout = version_bits_params.timeout;
            consensus.vDeployments[deployment_pos].min_activation_height = version_bits_params.min_activation_height;
        }

        genesis = CreateBlakecoinGenesisBlock(1381036817, 127057407, 503382015, 112, 5 * COIN);
        consensus.hashGenesisBlock = genesis.GetHash();
        assert(consensus.hashGenesisBlock == uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be"));
        assert(genesis.hashMerkleRoot == uint256S("0x9e4654d5bb91c723c3dbbaee57761d06ed10ac17f4d8841746aeec7ff8206ddc"));

        vFixedSeeds.clear(); //!< Regtest mode doesn't have any fixed seeds.
        vSeeds.clear();
        vSeeds.emplace_back("dummySeed.invalid.");

        fDefaultConsistencyChecks = true;
        fRequireStandard = false;
        m_is_test_chain = true;
        m_is_mockable_chain = true;

        checkpointData = {
            {
                {0, uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be")},
            }
        };

        m_assumeutxo_data = MapAssumeutxo{
            {
                130,
                {
                    AssumeutxoHash{uint256S("0x2b0d14d4029d47cd977ebadd28c37c9aa569218a7b7c20426f8a1e505f66a5d2")},
                    131,
                },
            },
        };

        chainTxData = ChainTxData{
            0,
            0,
            0
        };

        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,26);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,7);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,128);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};

        bech32_hrp = "rblc";
    }
};

std::unique_ptr<const CChainParams> CChainParams::SigNet(const SigNetOptions& options)
{
    return std::make_unique<const SigNetParams>(options);
}

std::unique_ptr<const CChainParams> CChainParams::RegTest(const RegTestOptions& options)
{
    return std::make_unique<const CRegTestParams>(options);
}

std::unique_ptr<const CChainParams> CChainParams::Main()
{
    return std::make_unique<const CMainParams>();
}

std::unique_ptr<const CChainParams> CChainParams::TestNet()
{
    return std::make_unique<const CTestNetParams>();
}
