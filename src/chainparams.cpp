// Copyright (c) 2010 Satoshi Nakamoto
// Copyright (c) 2009-2016 The Bitcoin Core developers
// Copyright (c) 2013-2026 The Blakecoin Developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "chainparams.h"
#include "consensus/merkle.h"

#include "tinyformat.h"
#include "util.h"
#include "utilstrencodings.h"

#include <assert.h>
#include <limits>

#include "chainparamsseeds.h"

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
 * Blakecoin Genesis Block:
 * CBlock(hash=0000000f14c5..., ver=1, hashPrevBlock=00000000000000, hashMerkleRoot=4a5e1e, nTime=1372066561, nBits=1d00ffff, nNonce=421575, vtx=1)
 *   CTransaction(hash=4a5e1e, ver=1, vin.size=1, vout.size=1, nLockTime=0)
 *     CTxIn(COutPoint(000000, -1), coinbase 04ffff001d010445...)
 *     CTxOut(nValue=50.00000000, scriptPubKey=...)
 *   vMerkleTree: 4a5e1e
 */
static CBlock CreateGenesisBlock(uint32_t nTime, uint32_t nNonce, uint32_t nBits, int32_t nVersion, const CAmount& genesisReward)
{
    // Blakecoin genesis block parameters
    const char* pszTimestamp = "US forces target leading al-Shabaab militant in Somalian coastal raid";
    const CScript genesisOutputScript = CScript() << ParseHex("04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f") << OP_CHECKSIG;
    return CreateGenesisBlock(pszTimestamp, genesisOutputScript, nTime, nNonce, nBits, nVersion, genesisReward);
}

void CChainParams::UpdateVersionBitsParameters(Consensus::DeploymentPos d, int64_t nStartTime, int64_t nTimeout)
{
    consensus.vDeployments[d].nStartTime = nStartTime;
    consensus.vDeployments[d].nTimeout = nTimeout;
}

/**
 * Main network
 */
/**
 * What makes a good checkpoint block?
 * + Is surrounded by blocks with reasonable timestamps
 *   (no blocks before with a timestamp after, none after with
 *    timestamp before)
 * + Contains no strange transactions
 */

class CMainParams : public CChainParams {
public:
    CMainParams() {
        strNetworkID = "main";
        // BEGIN BLAKECOIN: Blakecoin uses dynamic subsidy, not halving
        // Subsidy formula: 25 + sqrt(difficulty * height) BLC
        consensus.nSubsidyHalvingInterval = std::numeric_limits<int>::max(); // No halving
        // END BLAKECOIN
        // BEGIN BLAKECOIN: Set BIP heights to disable version checks for historical blocks
        // Blakecoin uses different block versioning - disable these checks
        consensus.BIP34Height = 100000000; // Disabled - far in future
        consensus.BIP34Hash = uint256S("0x000000000000024b89b42a942fe0d9fea3bb44ab7bd1b19115dd6a759c0808b8");
        consensus.BIP65Height = 100000000; // Disabled - far in future
        consensus.BIP66Height = 100000000; // Disabled - far in future
        // END BLAKECOIN
        // BEGIN BLAKECOIN: Proof of work limit: difficulty 1 target from nBits 0x1e00ffff
        // Target = 0x00ffff * 256^27 = 000000ffff000000000000000000000000000000000000000000000000000000
        consensus.powLimit = uint256S("000000ffff000000000000000000000000000000000000000000000000000000");
        // Difficulty adjustment: every 20 blocks (1 hour with 3-minute blocks)
        consensus.nPowTargetTimespan = 20 * 3 * 60;       // 1 hour (20 blocks * 3 minutes)
        consensus.nPowTargetSpacing = 3 * 60;             // 3 minutes (Blakecoin)
        // END BLAKECOIN
        consensus.fPowAllowMinDifficultyBlocks = false;
        consensus.fPowNoRetargeting = false;
        // BEGIN BLAKECOIN: Rule change threshold for 20-block interval
        consensus.nRuleChangeActivationThreshold = 19; // 95% of 20
        consensus.nMinerConfirmationWindow = 20; // nPowTargetTimespan / nPowTargetSpacing
        // END BLAKECOIN
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 1199145601; // January 1, 2008
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = 1230767999; // December 31, 2008

        // Deployment of BIP68, BIP112, and BIP113.
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].bit = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = 1462060800; // May 1st, 2016
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = 1493596800; // May 1st, 2017

        // Deployment of SegWit (BIP141, BIP143, and BIP147)
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].bit = 1;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = 1479168000; // November 15th, 2016.
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = 1510704000; // November 15th, 2017.

        // The best chain should have at least this much work.
        consensus.nMinimumChainWork = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");

        // By default assume that the signatures in ancestors of this block are valid.
        consensus.defaultAssumeValid = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");

        /**
         * The message start string is designed to be unlikely to occur in normal data.
         * The characters are rarely used upper ASCII, not valid as UTF-8, and produce
         * a large 32-bit integer with any alignment.
         */
        // BEGIN BLAKECOIN: Message start bytes (same as Bitcoin mainnet)
        pchMessageStart[0] = 0xf9;
        pchMessageStart[1] = 0xbe;
        pchMessageStart[2] = 0xb4;
        pchMessageStart[3] = 0xd2;
        // END BLAKECOIN
        nDefaultPort = 8773;
        nPruneAfterHeight = 100000;

        // Blakecoin genesis block: Oct 6, 2013 17:20:17 UTC
        // pszTimestamp: "US forces target leading al-Shabaab militant in Somalian coastal raid"
        genesis = CreateGenesisBlock(1381036817, 127057407, 503382015, 112, 5 * COIN);
        // IMPORTANT: The genesis hash is a historical PoW hash found through mining.
        // We hardcode it as a constant for blockchain compatibility.
        consensus.hashGenesisBlock = uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be");
        // Merkle root is COMPUTED and must match (validates our transaction/merkle implementation)
        assert(genesis.hashMerkleRoot == uint256S("0x9e4654d5bb91c723c3dbbaee57761d06ed10ac17f4d8841746aeec7ff8206ddc"));

        // Blakecoin DNS seeds — resolve to 0.15.2 node IPs on port 8773
        // supportsServiceBitsFiltering = false: these are plain A records, not
        // Bitcoin-style DNS seeders that support x<servicebits>. prefix filtering
        vSeeds.emplace_back("blakestream.io", "seed.blakestream.io", false);
        vSeeds.emplace_back("blakecoin.org", "seed.blakecoin.org", false);

        // BEGIN BLAKECOIN: Blakecoin address prefixes from v0.8.6
        // PUBKEY_ADDRESS = 26 (addresses starting with 'B')
        // SCRIPT_ADDRESS = 7 (addresses starting with '3')
        // SECRET_KEY = 128 (private keys starting with 'K' or 'L')
        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,26);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,7);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,128);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};
        // END BLAKECOIN

        vFixedSeeds = std::vector<SeedSpec6>(pnSeed6_main, pnSeed6_main + ARRAYLEN(pnSeed6_main));

        fMiningRequiresPeers = true;
        fDefaultConsistencyChecks = false;
        fRequireStandard = true;
        fMineBlocksOnDemand = false;

        checkpointData = (CCheckpointData) {
            {
                {0,       uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be")},
                {2499,    uint256S("0x00000000040fcdd50c1bd5ad140039b6d8f4e7f3ad497115314c0b2c0569b285")},
                {19797,   uint256S("0x000000000093b59ec621c8d8bcee44a7644e40d236e5cd126619e292e8b22a78")},
                {39253,   uint256S("0x00000000000fe223ac905ab8902695a52e6c1829809a5cbbf4fdbbad5d11758c")},
                {143000,  uint256S("0x000000000000178e824cad2eb1e0bd499539750c3b71b3f1c4015f1962de1062")},
                {217000,  uint256S("0x000000000001d0c2645df7f149081f03e9f5612c6b44b2116b1b84c4781989e2")},
                {297313,  uint256S("0x00000000000264e992d35a4775d3b4e16e807221401ebbee87ab8cd6505335b1")},
                {350620,  uint256S("0x00000000000132bbab473392bec2230eccc1dcc27af3c4b088c15067734e610a")},
                {1322950, uint256S("0x0000000000003205ddd0fb453c229a5e976cccd1516a64b5893d9d41cb11b2ff")},
            }
        };

        chainTxData = ChainTxData{
            // Data as of block 1322950 (last checkpoint, March 2022)
            1646526399, // * UNIX timestamp of last checkpoint block
            2106015,    // * total number of transactions between genesis and last checkpoint
            2000.0 / (24 * 60 * 60) // * ~2000 tx/day expressed as tx/sec
        };
    }
};

/**
 * Testnet (v3)
 */
class CTestNetParams : public CChainParams {
public:
    CTestNetParams() {
        strNetworkID = "test";
        consensus.nSubsidyHalvingInterval = 210000;
        consensus.BIP34Height = 21111;
        consensus.BIP34Hash = uint256S("0x0000000023b3a96d3484e5abb3755c413e7d41500f8e2a5c3f0dd01299cd8ef8");
        consensus.BIP65Height = 581885; // 00000000007f6655f22f98e72ed80d8b06dc761d5da09df0fa1dc4be4f861eb6
        consensus.BIP66Height = 330776; // 000000002104c8c45e99a8853285a3b592602a3ccde2b832481da85e9e4ba182
        consensus.powLimit = uint256S("00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 14 * 24 * 60 * 60; // two weeks
        consensus.nPowTargetSpacing = 3 * 60;             // 3 minutes (Blakecoin)
        consensus.fPowAllowMinDifficultyBlocks = true;
        consensus.fPowNoRetargeting = false;
        consensus.nRuleChangeActivationThreshold = 1512; // 75% for testchains
        consensus.nMinerConfirmationWindow = 2016; // nPowTargetTimespan / nPowTargetSpacing
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 1199145601; // January 1, 2008
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = 1230767999; // December 31, 2008

        // Deployment of BIP68, BIP112, and BIP113.
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].bit = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = 1456790400; // March 1st, 2016
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = 1493596800; // May 1st, 2017

        // Deployment of SegWit (BIP141, BIP143, and BIP147)
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].bit = 1;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = 1462060800; // May 1st 2016
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = 1493596800; // May 1st 2017

        // The best chain should have at least this much work.
        consensus.nMinimumChainWork = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");

        // By default assume that the signatures in ancestors of this block are valid.
        consensus.defaultAssumeValid = uint256S("0x0000000000000000000000000000000000000000000000000000000000000000");

        pchMessageStart[0] = 0xfc;
        pchMessageStart[1] = 0xc1;
        pchMessageStart[2] = 0xb7;
        pchMessageStart[3] = 0xdc;
        nDefaultPort = 18777;
        nPruneAfterHeight = 1000;

        // BEGIN BLAKECOIN: Testnet genesis block
        // Testnet uses same genesis as mainnet for simplicity, or create a new one
        genesis = CreateGenesisBlock(1381036817, 127057407, 503382015, 112, 5 * COIN);
        consensus.hashGenesisBlock = uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be");
        assert(genesis.hashMerkleRoot == uint256S("0x9e4654d5bb91c723c3dbbaee57761d06ed10ac17f4d8841746aeec7ff8206ddc"));
        // END BLAKECOIN

        vFixedSeeds.clear();
        vSeeds.clear();
        // Testnet seeds to be added when available

        // BEGIN BLAKECOIN: Testnet address prefixes from v0.8.6
        // PUBKEY_ADDRESS_TEST = 142, SCRIPT_ADDRESS_TEST = 170, SECRET_KEY_TEST = 239
        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,142);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,170);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,239);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x35, 0x87, 0xCF};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x35, 0x83, 0x94};
        // END BLAKECOIN

        vFixedSeeds = std::vector<SeedSpec6>(pnSeed6_test, pnSeed6_test + ARRAYLEN(pnSeed6_test));

        fMiningRequiresPeers = true;
        fDefaultConsistencyChecks = false;
        fRequireStandard = false;
        fMineBlocksOnDemand = false;

        // BEGIN BLAKECOIN: Testnet checkpoints
        checkpointData = (CCheckpointData) {
            {
                {0, uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be")},
            }
        };
        // END BLAKECOIN

        chainTxData = ChainTxData{
            // Data as of testnet genesis
            1372066562,
            1,
            0.01
        };

    }
};

/**
 * Regression test
 */
class CRegTestParams : public CChainParams {
public:
    CRegTestParams() {
        strNetworkID = "regtest";
        consensus.nSubsidyHalvingInterval = 150;
        consensus.BIP34Height = 100000000; // BIP34 has not activated on regtest (far in the future so block v1 are not rejected in tests)
        consensus.BIP34Hash = uint256();
        consensus.BIP65Height = 1351; // BIP65 activated on regtest (Used in rpc activation tests)
        consensus.BIP66Height = 1251; // BIP66 activated on regtest (Used in rpc activation tests)
        consensus.powLimit = uint256S("7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
        consensus.nPowTargetTimespan = 14 * 24 * 60 * 60; // two weeks
        consensus.nPowTargetSpacing = 10 * 60;
        consensus.fPowAllowMinDifficultyBlocks = true;
        consensus.fPowNoRetargeting = true;
        consensus.nRuleChangeActivationThreshold = 108; // 75% for testchains
        consensus.nMinerConfirmationWindow = 144; // Faster than normal for regtest (144 instead of 2016)
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].bit = 28;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nStartTime = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_TESTDUMMY].nTimeout = 999999999999ULL;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].bit = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nStartTime = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_CSV].nTimeout = 999999999999ULL;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].bit = 1;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nStartTime = 0;
        consensus.vDeployments[Consensus::DEPLOYMENT_SEGWIT].nTimeout = 999999999999ULL;

        // The best chain should have at least this much work.
        consensus.nMinimumChainWork = uint256S("0x00");

        // By default assume that the signatures in ancestors of this block are valid.
        consensus.defaultAssumeValid = uint256S("0x00");

        pchMessageStart[0] = 0xfa;
        pchMessageStart[1] = 0xbf;
        pchMessageStart[2] = 0xb5;
        pchMessageStart[3] = 0xda;
        nDefaultPort = 18444;
        nPruneAfterHeight = 1000;

        // BEGIN BLAKECOIN: Regtest genesis - using mainnet genesis for consistency
        genesis = CreateGenesisBlock(1381036817, 127057407, 503382015, 112, 5 * COIN);
        consensus.hashGenesisBlock = uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be");
        assert(genesis.hashMerkleRoot == uint256S("0x9e4654d5bb91c723c3dbbaee57761d06ed10ac17f4d8841746aeec7ff8206ddc"));
        // END BLAKECOIN

        vFixedSeeds.clear(); //!< Regtest mode doesn't have any fixed seeds.
        vSeeds.clear();      //!< Regtest mode doesn't have any DNS seeds.

        fMiningRequiresPeers = false;
        fDefaultConsistencyChecks = true;
        fRequireStandard = false;
        fMineBlocksOnDemand = true;

        // BEGIN BLAKECOIN: Regtest checkpoint
        checkpointData = (CCheckpointData){
            {
                {0, uint256S("0x000000ba5cae4648b1a2b823f84cc3424e5d96d7234b39c6bb42800b2c7639be")}
            }
        };
        // END BLAKECOIN

        chainTxData = ChainTxData{
            0,
            0,
            0
        };

        // BEGIN BLAKECOIN: Regtest address prefixes - using mainnet values
        base58Prefixes[PUBKEY_ADDRESS] = std::vector<unsigned char>(1,26);
        base58Prefixes[SCRIPT_ADDRESS] = std::vector<unsigned char>(1,7);
        base58Prefixes[SECRET_KEY] =     std::vector<unsigned char>(1,128);
        base58Prefixes[EXT_PUBLIC_KEY] = {0x04, 0x88, 0xB2, 0x1E};
        base58Prefixes[EXT_SECRET_KEY] = {0x04, 0x88, 0xAD, 0xE4};
        // END BLAKECOIN
    }
};

static std::unique_ptr<CChainParams> globalChainParams;

const CChainParams &Params() {
    assert(globalChainParams);
    return *globalChainParams;
}

std::unique_ptr<CChainParams> CreateChainParams(const std::string& chain)
{
    if (chain == CBaseChainParams::MAIN)
        return std::unique_ptr<CChainParams>(new CMainParams());
    else if (chain == CBaseChainParams::TESTNET)
        return std::unique_ptr<CChainParams>(new CTestNetParams());
    else if (chain == CBaseChainParams::REGTEST)
        return std::unique_ptr<CChainParams>(new CRegTestParams());
    throw std::runtime_error(strprintf("%s: Unknown chain %s.", __func__, chain));
}

void SelectParams(const std::string& network)
{
    SelectBaseParams(network);
    globalChainParams = CreateChainParams(network);
}

void UpdateVersionBitsParameters(Consensus::DeploymentPos d, int64_t nStartTime, int64_t nTimeout)
{
    globalChainParams->UpdateVersionBitsParameters(d, nStartTime, nTimeout);
}
