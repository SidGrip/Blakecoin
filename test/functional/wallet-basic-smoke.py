#!/usr/bin/env python3
# Copyright (c) 2026
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Basic no-send wallet smoke test for Blakecoin Core."""

import os

from decimal import Decimal

from test_framework.test_framework import BitcoinTestFramework
from test_framework.util import (
    assert_equal,
    assert_raises_rpc_error,
    try_rpc,
    wait_until,
)


class WalletBasicSmokeTest(BitcoinTestFramework):
    def set_test_params(self):
        self.setup_clean_chain = True
        self.num_nodes = 3
        # The inherited functional framework writes bitcoin.conf while this
        # daemon defaults to blakecoin.conf, so force the test nodes to read
        # the framework-generated config.
        self.extra_args = [["-conf=bitcoin.conf"] for _ in range(self.num_nodes)]

    def assert_zero_balance(self, node):
        info = node.getwalletinfo()
        assert_equal(info["balance"], Decimal("0"))

    def assert_address_state(self, info, *, isscript, iswitness=False, prefix=None):
        assert_equal(info["isvalid"], True)
        assert_equal(info["ismine"], True)
        assert_equal(info["isscript"], isscript)
        assert_equal(info.get("iswitness", False), iswitness)
        if iswitness:
            assert_equal(info["witness_version"], 0)
        if prefix is not None:
            assert info["address"].startswith(prefix), info["address"]

    def assert_wallet_locked_for_dump(self, node, address):
        assert_raises_rpc_error(
            -13,
            "Please enter the wallet passphrase with walletpassphrase first",
            node.dumpprivkey,
            address,
        )

    def run_test(self):
        source = self.nodes[0]
        import_privkey_target = self.nodes[1]
        import_wallet_target = self.nodes[2]
        dump_file = os.path.join(self.options.tmpdir, "node0", "wallet-basic-smoke.dump")

        self.log.info("Phase 1: baseline wallet state")
        for node in self.nodes:
            self.assert_zero_balance(node)

        self.log.info("Phase 2: address generation and validation")
        addresses = {
            "legacy": source.getnewaddress("legacy-smoke", "legacy"),
            "p2sh-segwit": source.getnewaddress("p2sh-segwit-smoke", "p2sh-segwit"),
            "bech32": source.getnewaddress("bech32-smoke", "bech32"),
        }

        self.assert_address_state(source.validateaddress(addresses["legacy"]), isscript=False)
        self.assert_address_state(source.validateaddress(addresses["p2sh-segwit"]), isscript=True)
        self.assert_address_state(
            source.validateaddress(addresses["bech32"]),
            isscript=False,
            iswitness=True,
            prefix="rblc1",
        )

        self.log.info("Phase 3: dumpprivkey and importprivkey")
        dumped_wifs = {}
        for address_type, address in addresses.items():
            privkey = source.dumpprivkey(address)
            assert privkey
            assert_equal(len(privkey), 52)
            dumped_wifs[address_type] = privkey

        for address_type, privkey in dumped_wifs.items():
            import_privkey_target.importprivkey(privkey, "imported-%s" % address_type, False)

        for address in addresses.values():
            imported = import_privkey_target.validateaddress(address)
            assert_equal(imported["isvalid"], True)
            assert_equal(imported["ismine"], True)
        self.assert_zero_balance(import_privkey_target)

        self.log.info("Phase 4: dumpwallet and importwallet")
        dump_result = source.dumpwallet(dump_file)
        assert_equal(dump_result["filename"], os.path.abspath(dump_file))
        assert os.path.exists(dump_file)

        import_wallet_target.importwallet(dump_file)
        for address in addresses.values():
            imported = import_wallet_target.validateaddress(address)
            assert_equal(imported["isvalid"], True)
            assert_equal(imported["ismine"], True)
        self.assert_zero_balance(import_wallet_target)

        self.log.info("Phase 5: encrypt, unlock, relock, and change passphrase")
        passphrase = "WalletPassphrase"
        passphrase2 = "SecondWalletPassphrase"
        source.node_encrypt_wallet(passphrase)
        self.start_node(0)
        source = self.nodes[0]

        self.assert_zero_balance(source)
        self.assert_wallet_locked_for_dump(source, addresses["legacy"])

        locked_bech32 = source.getnewaddress("locked-bech32-smoke", "bech32")
        self.assert_address_state(
            source.validateaddress(locked_bech32),
            isscript=False,
            iswitness=True,
            prefix="rblc1",
        )

        source.walletpassphrase(passphrase, 2)
        assert_equal(dumped_wifs["legacy"], source.dumpprivkey(addresses["legacy"]))

        wait_until(
            lambda: try_rpc(
                -13,
                "Please enter the wallet passphrase with walletpassphrase first",
                source.dumpprivkey,
                addresses["legacy"],
            ),
            timeout=10,
        )

        source.walletpassphrase(passphrase, 84600)
        assert_equal(dumped_wifs["legacy"], source.dumpprivkey(addresses["legacy"]))
        source.walletlock()
        self.assert_wallet_locked_for_dump(source, addresses["legacy"])

        source.walletpassphrasechange(passphrase, passphrase2)
        assert_raises_rpc_error(
            -14,
            "wallet passphrase entered was incorrect",
            source.walletpassphrase,
            passphrase,
            10,
        )
        source.walletpassphrase(passphrase2, 10)
        assert_equal(dumped_wifs["legacy"], source.dumpprivkey(addresses["legacy"]))


if __name__ == '__main__':
    WalletBasicSmokeTest().main()
