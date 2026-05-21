// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-2019 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <primitives/block.h>

#include <hash.h>
#include <tinyformat.h>

// BEGIN BLAKECOIN: Block header hash uses 8-round BLAKE-256 (single-pass)
// instead of Bitcoin's double SHA-256. This IS the proof-of-work hash —
// Blakecoin does not have a separate GetPoWHash() because the block hash
// and the PoW hash are the same function. Hashes the 80-byte packed
// header range from nVersion through nNonce (no padding in the struct;
// uint256 uses std::array<uint8_t, 32> with 1-byte alignment, and the
// int32_t/uint32_t fields align within 4 bytes on the relevant platforms).
uint256 CBlockHeader::GetHash() const
{
    return Hashblake(BEGIN(nVersion), END(nNonce));
}
// END BLAKECOIN

std::string CBlock::ToString() const
{
    std::stringstream s;
    s << strprintf("CBlock(hash=%s, ver=0x%08x, hashPrevBlock=%s, hashMerkleRoot=%s, nTime=%u, nBits=%08x, nNonce=%u, vtx=%u)\n",
        GetHash().ToString(),
        nVersion,
        hashPrevBlock.ToString(),
        hashMerkleRoot.ToString(),
        nTime, nBits, nNonce,
        vtx.size());
    for (const auto& tx : vtx) {
        s << "  " << tx->ToString() << "\n";
    }
    return s.str();
}
