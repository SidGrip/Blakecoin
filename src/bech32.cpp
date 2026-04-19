// Copyright (c) 2017 Pieter Wuille
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include "bech32.h"

namespace
{

typedef std::vector<uint8_t> data;

const char* CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

const int8_t CHARSET_REV[128] = {
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    15, -1, 10, 17, 21, 20, 26, 30,  7,  5, -1, -1, -1, -1, -1, -1,
    -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
     1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1,
    -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
     1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1
};

data Cat(data x, const data& y)
{
    x.insert(x.end(), y.begin(), y.end());
    return x;
}

uint32_t PolyMod(const data& v)
{
    uint32_t c = 1;
    for (data::value_type v_i : v) {
        uint8_t c0 = c >> 25;
        c = ((c & 0x1ffffff) << 5) ^ v_i;
        if (c0 & 1)  c ^= 0x3b6a57b2;
        if (c0 & 2)  c ^= 0x26508e6d;
        if (c0 & 4)  c ^= 0x1ea119fa;
        if (c0 & 8)  c ^= 0x3d4233dd;
        if (c0 & 16) c ^= 0x2a1462b3;
    }
    return c;
}

inline unsigned char LowerCase(unsigned char c)
{
    return (c >= 'A' && c <= 'Z') ? (c - 'A') + 'a' : c;
}

data ExpandHRP(const std::string& hrp)
{
    data ret;
    ret.reserve(hrp.size() + 90);
    ret.resize(hrp.size() * 2 + 1);
    for (size_t i = 0; i < hrp.size(); ++i) {
        unsigned char c = hrp[i];
        ret[i] = c >> 5;
        ret[i + hrp.size() + 1] = c & 0x1f;
    }
    ret[hrp.size()] = 0;
    return ret;
}

bool VerifyChecksum(const std::string& hrp, const data& values)
{
    return PolyMod(Cat(ExpandHRP(hrp), values)) == 1;
}

data CreateChecksum(const std::string& hrp, const data& values)
{
    data enc = Cat(ExpandHRP(hrp), values);
    enc.resize(enc.size() + 6);
    uint32_t mod = PolyMod(enc) ^ 1;
    data ret(6);
    for (size_t i = 0; i < 6; ++i) {
        ret[i] = (mod >> (5 * (5 - i))) & 31;
    }
    return ret;
}

} // namespace

namespace bech32
{

std::string Encode(const std::string& hrp, const data& values)
{
    data checksum = CreateChecksum(hrp, values);
    data combined = Cat(values, checksum);
    std::string ret = hrp + '1';
    ret.reserve(ret.size() + combined.size());
    for (data::value_type c : combined) {
        ret += CHARSET[c];
    }
    return ret;
}

std::pair<std::string, data> Decode(const std::string& str)
{
    bool lower = false;
    bool upper = false;
    for (size_t i = 0; i < str.size(); ++i) {
        unsigned char c = str[i];
        if (c < 33 || c > 126) return std::make_pair(std::string(), data());
        if (c >= 'a' && c <= 'z') lower = true;
        if (c >= 'A' && c <= 'Z') upper = true;
    }
    if (upper && lower) return std::make_pair(std::string(), data());
    size_t pos = str.rfind('1');
    if (pos == std::string::npos || pos < 1 || pos + 7 > str.size()) return std::make_pair(std::string(), data());
    data values(str.size() - pos - 1);
    for (size_t i = 0; i < str.size() - pos - 1; ++i) {
        unsigned char c = str[i + pos + 1];
        int8_t rev = c < 0 || c >= 128 ? -1 : CHARSET_REV[c];
        if (rev == -1) return std::make_pair(std::string(), data());
        values[i] = rev;
    }
    std::string hrp;
    hrp.reserve(pos);
    for (size_t i = 0; i < pos; ++i) {
        hrp += LowerCase(str[i]);
    }
    if (!VerifyChecksum(hrp, values)) return std::make_pair(std::string(), data());
    return std::make_pair(hrp, data(values.begin(), values.end() - 6));
}

} // namespace bech32
