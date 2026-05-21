#!/usr/bin/env python3
# Copyright (c) 2026 The BlakeStream developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Test Blakecoin SegWit HTLC primitives for atomic swaps.

This is not a DEX protocol test. It is the Core consensus/wallet-facing
building block required before a DEX or Lightning stack can safely depend on
Blakecoin HTLCs:

- P2WSH HTLC funding output
- hashlock claim path
- CLTV absolute refund path
- CSV relative-delay refund path
- Blakecoin witness-v0 BIP143 double-SHA256 signature hashing
"""

import hashlib

from test_framework.messages import (
    COIN,
    COutPoint,
    CTransaction,
    CTxIn,
    CTxInWitness,
    CTxOut,
    SEQUENCE_FINAL,
)
from test_framework.script import (
    CScript,
    OP_CHECKLOCKTIMEVERIFY,
    OP_CHECKSEQUENCEVERIFY,
    OP_CHECKSIG,
    OP_DROP,
    OP_ELSE,
    OP_ENDIF,
    OP_EQUALVERIFY,
    OP_IF,
    OP_SHA256,
    SIGHASH_ALL,
    SegwitV0SignatureHash,
)
from test_framework.script_util import script_to_p2wsh_script
from test_framework.test_framework import BitcoinTestFramework
from test_framework.key import ECKey
from test_framework.util import assert_equal
from test_framework.wallet import MiniWallet


HTLC_AMOUNT = COIN
FEE = 1000
CSV_DELAY = 3


def make_key(secret_int):
    key = ECKey()
    key.set(secret_int.to_bytes(32, "big"), True)
    return key


def make_htlc_script(*, alice_pubkey, bob_pubkey, secret_hash, refund_height):
    return CScript([
        OP_IF,
            OP_SHA256,
            secret_hash,
            OP_EQUALVERIFY,
            bob_pubkey,
            OP_CHECKSIG,
        OP_ELSE,
            refund_height,
            OP_CHECKLOCKTIMEVERIFY,
            OP_DROP,
            CSV_DELAY,
            OP_CHECKSEQUENCEVERIFY,
            OP_DROP,
            alice_pubkey,
            OP_CHECKSIG,
        OP_ENDIF,
    ])


class BlakecoinAtomicSwapHTLCTest(BitcoinTestFramework):
    def add_options(self, parser):
        self.add_wallet_options(parser)

    def set_test_params(self):
        self.num_nodes = 1
        self.setup_clean_chain = True
        self.extra_args = [[
            "-acceptnonstdtxn=0",
            "-testactivationheight=segwit@1",
            "-testactivationheight=cltv@1",
            "-testactivationheight=csv@1",
        ]]

    def skip_test_if_missing_module(self):
        self.skip_if_no_wallet()

    def build_spend(self, *, txid, vout, amount, witness_script, signing_key, sequence, locktime, witness_stack):
        tx = CTransaction()
        tx.nVersion = 2
        tx.nLockTime = locktime
        tx.vin = [CTxIn(COutPoint(int(txid, 16), vout), nSequence=sequence)]
        tx.vout = [CTxOut(amount - FEE, self.wallet.get_scriptPubKey())]
        sighash = SegwitV0SignatureHash(witness_script, tx, 0, SIGHASH_ALL, amount)
        sig = signing_key.sign_ecdsa(sighash) + bytes([SIGHASH_ALL])
        tx.wit.vtxinwit = [CTxInWitness()]
        tx.wit.vtxinwit[0].scriptWitness.stack = [sig] + witness_stack + [witness_script]
        tx.rehash()
        return tx

    def assert_mempool_reject_contains(self, tx, expected):
        result = self.nodes[0].testmempoolaccept([tx.serialize().hex()], maxfeerate=0)[0]
        assert_equal(result["allowed"], False)
        assert expected in result["reject-reason"], result["reject-reason"]

    def fund_htlc(self, *, refund_height):
        secret = b"blakecoin atomic swap preimage"
        secret_hash = hashlib.sha256(secret).digest()
        alice_key = make_key(1)
        bob_key = make_key(2)
        witness_script = make_htlc_script(
            alice_pubkey=alice_key.get_pubkey().get_bytes(),
            bob_pubkey=bob_key.get_pubkey().get_bytes(),
            secret_hash=secret_hash,
            refund_height=refund_height,
        )
        mature_utxo = max(
            self.wallet.get_utxos(include_immature_coinbase=False, mark_as_spent=False),
            key=lambda utxo: utxo["value"],
        )
        funding_tx = self.wallet.create_self_transfer(utxo_to_spend=mature_utxo, fee_rate=0)["tx"]
        assert funding_tx.vout[0].nValue >= HTLC_AMOUNT + FEE
        funding_tx.vout[0].nValue -= HTLC_AMOUNT + FEE
        funding_tx.vout.append(CTxOut(HTLC_AMOUNT, script_to_p2wsh_script(witness_script)))
        funding_tx.rehash()
        txid = self.wallet.sendrawtransaction(from_node=self.nodes[0], tx_hex=funding_tx.serialize().hex(), maxfeerate=0)
        vout = 1
        self.generate(self.wallet, 1)
        return {
            "txid": txid,
            "vout": vout,
            "amount": HTLC_AMOUNT,
            "secret": secret,
            "alice_key": alice_key,
            "bob_key": bob_key,
            "witness_script": witness_script,
        }

    def run_test(self):
        self.wallet = MiniWallet(self.nodes[0])
        self.generate(self.wallet, 121)

        self.log.info("Verify hashlock claim path spends a P2WSH HTLC before refund time")
        current_height = self.nodes[0].getblockcount()
        htlc = self.fund_htlc(refund_height=current_height + 20)
        claim_tx = self.build_spend(
            txid=htlc["txid"],
            vout=htlc["vout"],
            amount=htlc["amount"],
            witness_script=htlc["witness_script"],
            signing_key=htlc["bob_key"],
            sequence=SEQUENCE_FINAL,
            locktime=0,
            witness_stack=[htlc["secret"], b"\x01"],
        )
        assert_equal(self.nodes[0].testmempoolaccept([claim_tx.serialize().hex()], maxfeerate=0)[0]["allowed"], True)
        claim_txid = self.nodes[0].sendrawtransaction(claim_tx.serialize().hex(), maxfeerate=0)
        self.generate(self.wallet, 1)
        assert claim_txid in self.nodes[0].getblock(self.nodes[0].getbestblockhash())["tx"]

        self.log.info("Verify wrong preimage cannot claim the hashlock path")
        current_height = self.nodes[0].getblockcount()
        htlc = self.fund_htlc(refund_height=current_height + 20)
        bad_claim_tx = self.build_spend(
            txid=htlc["txid"],
            vout=htlc["vout"],
            amount=htlc["amount"],
            witness_script=htlc["witness_script"],
            signing_key=htlc["bob_key"],
            sequence=SEQUENCE_FINAL,
            locktime=0,
            witness_stack=[b"wrong preimage", b"\x01"],
        )
        self.assert_mempool_reject_contains(bad_claim_tx, "Script failed an OP_EQUALVERIFY operation")

        self.log.info("Verify refund path is gated by both CLTV and CSV")
        current_height = self.nodes[0].getblockcount()
        refund_height = current_height + 1
        htlc = self.fund_htlc(refund_height=refund_height)

        early_refund_tx = self.build_spend(
            txid=htlc["txid"],
            vout=htlc["vout"],
            amount=htlc["amount"],
            witness_script=htlc["witness_script"],
            signing_key=htlc["alice_key"],
            sequence=CSV_DELAY,
            locktime=refund_height,
            witness_stack=[b""],
        )
        self.assert_mempool_reject_contains(early_refund_tx, "non-BIP68-final")

        self.generate(self.wallet, CSV_DELAY)
        cltv_fail_tx = self.build_spend(
            txid=htlc["txid"],
            vout=htlc["vout"],
            amount=htlc["amount"],
            witness_script=htlc["witness_script"],
            signing_key=htlc["alice_key"],
            sequence=CSV_DELAY,
            locktime=refund_height - 1,
            witness_stack=[b""],
        )
        self.assert_mempool_reject_contains(cltv_fail_tx, "Locktime requirement not satisfied")

        refund_tx = self.build_spend(
            txid=htlc["txid"],
            vout=htlc["vout"],
            amount=htlc["amount"],
            witness_script=htlc["witness_script"],
            signing_key=htlc["alice_key"],
            sequence=CSV_DELAY,
            locktime=refund_height,
            witness_stack=[b""],
        )
        assert_equal(self.nodes[0].testmempoolaccept([refund_tx.serialize().hex()], maxfeerate=0)[0]["allowed"], True)
        refund_txid = self.nodes[0].sendrawtransaction(refund_tx.serialize().hex(), maxfeerate=0)
        self.generate(self.wallet, 1)
        assert refund_txid in self.nodes[0].getblock(self.nodes[0].getbestblockhash())["tx"]


if __name__ == "__main__":
    BlakecoinAtomicSwapHTLCTest().main()
