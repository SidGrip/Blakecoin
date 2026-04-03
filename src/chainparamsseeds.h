#ifndef BITCOIN_CHAINPARAMSSEEDS_H
#define BITCOIN_CHAINPARAMSSEEDS_H
/**
 * List of fixed seed nodes for the Blakecoin network
 *
 * Empty — peer discovery relies on DNS seeds (seed.blakestream.io, seed.blakecoin.org).
 * If DNS seeds are unavailable, use addnode= or connect= in blakecoin.conf.
 */
static SeedSpec6 pnSeed6_main[] = {};

static SeedSpec6 pnSeed6_test[] = {};
#endif // BITCOIN_CHAINPARAMSSEEDS_H
