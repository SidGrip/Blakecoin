// Copyright (c) 2017 Pieter Wuille
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#ifndef BITCOIN_BECH32_H
#define BITCOIN_BECH32_H

// Bech32 is a string encoding format used in newer address types.
// The output consists of a human-readable part (alphanumeric), a
// separator character (1), and a base32 data section, the last
// 6 characters of which are a checksum.
//
// For more information, see BIP 173.

#include <stdint.h>

#include <string>
#include <utility>
#include <vector>

namespace bech32
{

std::string Encode(const std::string& hrp, const std::vector<uint8_t>& values);
std::pair<std::string, std::vector<uint8_t> > Decode(const std::string& str);

} // namespace bech32

#endif // BITCOIN_BECH32_H
