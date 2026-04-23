// Copyright (c) 2013-2016 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "consensus/tx_verify.h"
#include "consensus/validation.h"
#include "data/sighash.json.h"
#include "hash.h"
#include "script/interpreter.h"
#include "script/script.h"
#include "serialize.h"
#include "streams.h"
#include "test/test_bitcoin.h"
#include "util.h"
#include "utilstrencodings.h"
#include "version.h"

#include <iostream>

#include <boost/test/unit_test.hpp>

#include <univalue.h>

extern UniValue read_json(const std::string& jsondata);

// Old script.cpp SignatureHash function
uint256 static SignatureHashOld(CScript scriptCode, const CTransaction& txTo, unsigned int nIn, int nHashType)
{
    static const uint256 one(uint256S("0000000000000000000000000000000000000000000000000000000000000001"));
    if (nIn >= txTo.vin.size())
    {
        return one;
    }
    CMutableTransaction txTmp(txTo);

    // In case concatenating two scripts ends up with two codeseparators,
    // or an extra one at the end, this prevents all those possible incompatibilities.
    scriptCode.FindAndDelete(CScript(OP_CODESEPARATOR));

    // Blank out other inputs' signatures
    for (unsigned int i = 0; i < txTmp.vin.size(); i++)
        txTmp.vin[i].scriptSig = CScript();
    txTmp.vin[nIn].scriptSig = scriptCode;

    // Blank out some of the outputs
    if ((nHashType & 0x1f) == SIGHASH_NONE)
    {
        // Wildcard payee
        txTmp.vout.clear();

        // Let the others update at will
        for (unsigned int i = 0; i < txTmp.vin.size(); i++)
            if (i != nIn)
                txTmp.vin[i].nSequence = 0;
    }
    else if ((nHashType & 0x1f) == SIGHASH_SINGLE)
    {
        // Only lock-in the txout payee at same index as txin
        unsigned int nOut = nIn;
        if (nOut >= txTmp.vout.size())
        {
            return one;
        }
        txTmp.vout.resize(nOut+1);
        for (unsigned int i = 0; i < nOut; i++)
            txTmp.vout[i].SetNull();

        // Let the others update at will
        for (unsigned int i = 0; i < txTmp.vin.size(); i++)
            if (i != nIn)
                txTmp.vin[i].nSequence = 0;
    }

    // Blank out other inputs completely, not recommended for open transactions
    if (nHashType & SIGHASH_ANYONECANPAY)
    {
        txTmp.vin[0] = txTmp.vin[nIn];
        txTmp.vin.resize(1);
    }

    // Serialize and hash
    CHashWriter ss(SER_GETHASH, SERIALIZE_TRANSACTION_NO_WITNESS);
    ss << txTmp << nHashType;
    return ss.GetHash();
}

void static RandomScript(CScript &script) {
    static const opcodetype oplist[] = {OP_FALSE, OP_1, OP_2, OP_3, OP_CHECKSIG, OP_IF, OP_VERIF, OP_RETURN, OP_CODESEPARATOR};
    script = CScript();
    int ops = (InsecureRandRange(10));
    for (int i=0; i<ops; i++)
        script << oplist[InsecureRandRange(sizeof(oplist)/sizeof(oplist[0]))];
}

void static RandomTransaction(CMutableTransaction &tx, bool fSingle) {
    tx.nVersion = InsecureRand32();
    tx.vin.clear();
    tx.vout.clear();
    tx.nLockTime = (InsecureRandBool()) ? InsecureRand32() : 0;
    int ins = (InsecureRandBits(2)) + 1;
    int outs = fSingle ? ins : (InsecureRandBits(2)) + 1;
    for (int in = 0; in < ins; in++) {
        tx.vin.push_back(CTxIn());
        CTxIn &txin = tx.vin.back();
        txin.prevout.hash = InsecureRand256();
        txin.prevout.n = InsecureRandBits(2);
        RandomScript(txin.scriptSig);
        txin.nSequence = (InsecureRandBool()) ? InsecureRand32() : (unsigned int)-1;
    }
    for (int out = 0; out < outs; out++) {
        tx.vout.push_back(CTxOut());
        CTxOut &txout = tx.vout.back();
        txout.nValue = InsecureRandRange(100000000);
        RandomScript(txout.scriptPubKey);
    }
}

BOOST_FIXTURE_TEST_SUITE(sighash_tests, BasicTestingSetup)

BOOST_AUTO_TEST_CASE(sighash_test)
{
    SeedInsecureRand(false);

    #if defined(PRINT_SIGHASH_JSON)
    std::cout << "[\n";
    std::cout << "\t[\"raw_transaction, script, input_index, hashType, signature_hash (result)\"],\n";
    #endif
    int nRandomTests = 50000;

    #if defined(PRINT_SIGHASH_JSON)
    nRandomTests = 500;
    #endif
    for (int i=0; i<nRandomTests; i++) {
        int nHashType = InsecureRand32();
        CMutableTransaction txTo;
        RandomTransaction(txTo, (nHashType & 0x1f) == SIGHASH_SINGLE);
        CScript scriptCode;
        RandomScript(scriptCode);
        int nIn = InsecureRandRange(txTo.vin.size());

        uint256 sh, sho;
        sho = SignatureHashOld(scriptCode, txTo, nIn, nHashType);
        sh = SignatureHash(scriptCode, txTo, nIn, nHashType, 0, SIGVERSION_BASE);
        #if defined(PRINT_SIGHASH_JSON)
        CDataStream ss(SER_NETWORK, PROTOCOL_VERSION);
        ss << txTo;

        std::cout << "\t[\"" ;
        std::cout << HexStr(ss.begin(), ss.end()) << "\", \"";
        std::cout << HexStr(scriptCode) << "\", ";
        std::cout << nIn << ", ";
        std::cout << nHashType << ", \"";
        std::cout << sho.GetHex() << "\"]";
        if (i+1 != nRandomTests) {
          std::cout << ",";
        }
        std::cout << "\n";
        #endif
        BOOST_CHECK(sh == sho);
    }
    #if defined(PRINT_SIGHASH_JSON)
    std::cout << "]\n";
    #endif
}

BOOST_AUTO_TEST_CASE(bip143_witness_sighash_uses_double_sha256)
{
    CMutableTransaction mtx;
    mtx.nVersion = 2;
    mtx.nLockTime = 42;
    mtx.vin.resize(2);
    mtx.vin[0].prevout = COutPoint(uint256S("57f7e6c0f7f3a749731f9f3341bd7bf14bb1e8ff6937dc60d92a71feeb2d1f20"), 1);
    mtx.vin[0].nSequence = 0xfffffffe;
    mtx.vin[1].prevout = COutPoint(uint256S("06c4cf49a7c2ca6d7c86f82a1f4f1d0bce6bb7ef6544fbc5f1ec7e66e92bc93d"), 0);
    mtx.vin[1].nSequence = 0xfffffffd;
    mtx.vout.push_back(CTxOut(1111, CScript() << OP_1));
    mtx.vout.push_back(CTxOut(2222, CScript() << OP_2));
    const CTransaction txTo(mtx);

    uint256 hashPrevouts;
    uint256 hashSequence;
    uint256 hashOutputs;
    {
        CBIP143HashWriter ss(SER_GETHASH, 0);
        for (const auto& txin : txTo.vin) {
            ss << txin.prevout;
        }
        hashPrevouts = ss.GetHash();
    }
    {
        CBIP143HashWriter ss(SER_GETHASH, 0);
        for (const auto& txin : txTo.vin) {
            ss << txin.nSequence;
        }
        hashSequence = ss.GetHash();
    }
    {
        CBIP143HashWriter ss(SER_GETHASH, 0);
        for (const auto& txout : txTo.vout) {
            ss << txout;
        }
        hashOutputs = ss.GetHash();
    }

    const CScript scriptCode = CScript() << OP_DUP << OP_HASH160 << ParseHex("00112233445566778899aabbccddeeff00112233") << OP_EQUALVERIFY << OP_CHECKSIG;
    const CAmount amount = 987654321;
    const int nHashType = SIGHASH_ALL;

    CBIP143HashWriter double_writer(SER_GETHASH, 0);
    double_writer << txTo.nVersion;
    double_writer << hashPrevouts;
    double_writer << hashSequence;
    double_writer << txTo.vin[0].prevout;
    double_writer << scriptCode;
    double_writer << amount;
    double_writer << txTo.vin[0].nSequence;
    double_writer << hashOutputs;
    double_writer << txTo.nLockTime;
    double_writer << nHashType;
    const uint256 expected_double_sha256 = double_writer.GetHash();

    CHashWriter single_writer(SER_GETHASH, 0);
    single_writer << txTo.nVersion;
    single_writer << hashPrevouts;
    single_writer << hashSequence;
    single_writer << txTo.vin[0].prevout;
    single_writer << scriptCode;
    single_writer << amount;
    single_writer << txTo.vin[0].nSequence;
    single_writer << hashOutputs;
    single_writer << txTo.nLockTime;
    single_writer << nHashType;
    const uint256 single_sha256 = single_writer.GetHash();

    const uint256 actual = SignatureHash(scriptCode, txTo, 0, nHashType, amount, SIGVERSION_WITNESS_V0);
    BOOST_CHECK(actual == expected_double_sha256);
    BOOST_CHECK(actual != single_sha256);
}

// Goal: check that SignatureHash generates correct hash
BOOST_AUTO_TEST_CASE(sighash_from_data)
{
    UniValue tests = read_json(std::string(json_tests::sighash, json_tests::sighash + sizeof(json_tests::sighash)));

    for (unsigned int idx = 0; idx < tests.size(); idx++) {
        UniValue test = tests[idx];
        std::string strTest = test.write();
        if (test.size() < 1) // Allow for extra stuff (useful for comments)
        {
            BOOST_ERROR("Bad test: " << strTest);
            continue;
        }
        if (test.size() == 1) continue; // comment

        std::string raw_tx, raw_script, sigHashHex;
        int nIn, nHashType;
        uint256 sh;
        CTransactionRef tx;
        CScript scriptCode = CScript();

        try {
          // deserialize test data
          raw_tx = test[0].get_str();
          raw_script = test[1].get_str();
          nIn = test[2].get_int();
          nHashType = test[3].get_int();
          sigHashHex = test[4].get_str();

          CDataStream stream(ParseHex(raw_tx), SER_NETWORK, PROTOCOL_VERSION);
          stream >> tx;

          CValidationState state;
          BOOST_CHECK_MESSAGE(CheckTransaction(*tx, state), strTest);
          BOOST_CHECK(state.IsValid());

          std::vector<unsigned char> raw = ParseHex(raw_script);
          scriptCode.insert(scriptCode.end(), raw.begin(), raw.end());
        } catch (...) {
          BOOST_ERROR("Bad test, couldn't deserialize data: " << strTest);
          continue;
        }

        sh = SignatureHash(scriptCode, *tx, nIn, nHashType, 0, SIGVERSION_BASE);
        BOOST_CHECK_MESSAGE(sh.GetHex() == sigHashHex, strTest);
    }
}
BOOST_AUTO_TEST_SUITE_END()
