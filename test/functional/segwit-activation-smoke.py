#!/usr/bin/env python3
# Copyright (c) 2026 The BlakeStream developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Regtest SegWit activation smoke test with preserved review artifacts.

This test is intentionally narrow:

- prove versionbits state transitions on regtest using -vbparams
- prove one witness consensus failure before activation
- prove one witness consensus success after activation
- write JSON/text artifacts into the preserved --tmpdir for later review
"""

import importlib.util
import hashlib
import json
import os
import subprocess

from test_framework.util import assert_equal, wait_until


THIS_DIR = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
REPO_NAME = os.path.basename(REPO_ROOT)
P2P_SEGWIT_PATH = os.path.join(THIS_DIR, "p2p-segwit.py")


def load_p2p_segwit_module():
    spec = importlib.util.spec_from_file_location("blakestream_p2p_segwit", P2P_SEGWIT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


p2p_segwit = load_p2p_segwit_module()


EXPECTED_COIN_LABELS = {
    "Blakecoin-0.15.2-update": "Blakecoin",
    "BlakeBitcoin-0.15.2-update": "BlakeBitcoin",
    "Electron-ELT-0.15.2-update": "Electron-ELT",
    "lithium-0.15.2-update": "lithium",
    "Photon-0.15.2-update": "Photon",
    "universalmol-0.15.2-update": "UniversalMolecule",
}

EXPECTED_REGTEST_BECH32_PREFIXES = {
    "Blakecoin-0.15.2-update": "rblc1",
    "BlakeBitcoin-0.15.2-update": "rblb1",
    "Electron-ELT-0.15.2-update": "relt1",
    "lithium-0.15.2-update": "rlit1",
    "Photon-0.15.2-update": "rpho1",
    "universalmol-0.15.2-update": "rumo1",
}

VB_OVERRIDE = "segwit:0:999999999999"
VB_OVERRIDE_LOG_LINE = "Setting version bits activation parameters for segwit to start=0, timeout=999999999999"
REGTEST_WINDOW = 144
REGTEST_THRESHOLD = 108
REGTEST_MAXTRIES = 1000000000
FAST_MINE_TIME_STEP = 600


class SegWitActivationSmoke(p2p_segwit.SegWitTest):
    def set_test_params(self):
        self.setup_clean_chain = True
        self.num_nodes = 3
        common = [
            "-conf=bitcoin.conf",
            "-regtest",
            "-whitelist=127.0.0.1",
            "-vbparams=" + VB_OVERRIDE,
            "-debug=versionbits",
            "-debug=rpc",
            "-debug=net",
            "-debug=mempool",
        ]
        self.extra_args = [
            list(common),
            list(common) + ["-acceptnonstdtxn=0"],
            list(common),
        ]

    def setup_network(self):
        self.setup_nodes()
        self._ensure_network()
        self._sync_network()

    def setup_nodes(self):
        extra_args = self.extra_args if hasattr(self, "extra_args") else None
        self.add_nodes(self.num_nodes, extra_args, timewait=3600)
        self.start_nodes()

    def _has_peer(self, from_index, to_index):
        target = "testnode{}".format(to_index)
        for peer in self.nodes[from_index].getpeerinfo():
            if target in peer.get("subver", ""):
                return True
        return False

    def _ensure_network(self):
        for from_index, to_index in (
            (0, 1),
            (1, 0),
            (0, 2),
            (2, 0),
            (1, 2),
            (2, 1),
        ):
            if not self._has_peer(from_index, to_index):
                p2p_segwit.connect_nodes(self.nodes[from_index], to_index)

    def _sync_network(self, timeout=300):
        self._ensure_network()
        p2p_segwit.sync_blocks(self.nodes, timeout=timeout)
        p2p_segwit.sync_mempools(self.nodes, timeout=timeout)

    def _artifact_path(self, name):
        return os.path.join(self.options.tmpdir, name)

    def _write_json(self, name, payload):
        with open(self._artifact_path(name), "w", encoding="utf8") as fh:
            json.dump(payload, fh, indent=2, sort_keys=True)
            fh.write("\n")

    def _append_summary_line(self, line):
        with open(self._artifact_path("activation-state-summary.txt"), "a", encoding="utf8") as fh:
            fh.write(line + "\n")

    def _read_text(self, path):
        if not os.path.exists(path):
            return ""
        with open(path, "r", encoding="utf8", errors="replace") as fh:
            return fh.read()

    def _node_debug_log(self, node_index):
        return os.path.join(self.options.tmpdir, "node{}".format(node_index), "regtest", "debug.log")

    def _wait_for_override_logs(self):
        for node_index in range(self.num_nodes):
            debug_log = self._node_debug_log(node_index)
            wait_until(lambda: VB_OVERRIDE_LOG_LINE in self._read_text(debug_log), timeout=60)

    def _snapshot_phase(self, phase):
        info = self.nodes[0].getblockchaininfo()
        segwit = p2p_segwit.get_bip9_status(self.nodes[0], "segwit")
        bestblockhash = self.nodes[0].getbestblockhash()
        header = self.nodes[0].getblockheader(bestblockhash)
        start_time = segwit.get("startTime", segwit.get("start_time"))
        timeout = segwit.get("timeout")

        snapshot = {
            "coin": self.coin_label,
            "repo_name": REPO_NAME,
            "phase": phase,
            "chain": info["chain"],
            "blocks": info["blocks"],
            "headers": info.get("headers"),
            "bestblockhash": bestblockhash,
            "time": header["time"],
            "mediantime": header["mediantime"],
            "segwit": segwit,
            "regtest_window": REGTEST_WINDOW,
            "regtest_threshold": REGTEST_THRESHOLD,
            "expected_segwit_bit": 1,
            "vbparams": VB_OVERRIDE,
            "expected_regtest_bech32_prefix": self.expected_bech32_prefix,
            "tmpdir": self.options.tmpdir,
        }
        self.phase_snapshots[phase] = snapshot
        self._write_json("state-{}.json".format(phase), snapshot)
        self._append_summary_line(
            "{} height={} mediantime={} status={} bit={} start={} timeout={}".format(
                phase,
                snapshot["blocks"],
                snapshot["mediantime"],
                segwit["status"],
                segwit.get("bit", 1),
                start_time,
                timeout,
            )
        )
        return snapshot

    def _assert_phase(self, phase, expected_status):
        snapshot = self._snapshot_phase(phase)
        segwit = snapshot["segwit"]
        assert_equal(segwit["status"], expected_status)
        if segwit.get("bit") is not None:
            assert_equal(segwit["bit"], 1)
        assert_equal(snapshot["regtest_window"], 144)
        assert_equal(snapshot["regtest_threshold"], 108)
        assert_equal(segwit.get("startTime", segwit.get("start_time")), 0)
        assert_equal(segwit.get("timeout"), 999999999999)
        return snapshot

    def _write_address_sanity(self):
        legacy_addr = self.nodes[0].getnewaddress("segwit-smoke-legacy", "legacy")
        p2sh_addr = self.nodes[0].getnewaddress("segwit-smoke-p2sh", "p2sh-segwit")
        bech32_addr = self.nodes[0].getnewaddress("segwit-smoke-bech32", "bech32")

        legacy_info = self.nodes[0].validateaddress(legacy_addr)
        p2sh_info = self.nodes[0].validateaddress(p2sh_addr)
        bech32_info = self.nodes[0].validateaddress(bech32_addr)

        assert_equal(legacy_info["isvalid"], True)
        assert_equal(legacy_info["ismine"], True)
        assert_equal(legacy_info.get("iswitness", False), False)

        assert_equal(p2sh_info["isvalid"], True)
        assert_equal(p2sh_info["ismine"], True)

        assert_equal(bech32_info["isvalid"], True)
        assert_equal(bech32_info["ismine"], True)
        assert_equal(bech32_info.get("iswitness"), True)
        assert_equal(bech32_info.get("witness_version"), 0)
        assert bech32_addr.startswith(self.expected_bech32_prefix), bech32_addr

        address_sanity = {
            "coin": self.coin_label,
            "expected_regtest_bech32_prefix": self.expected_bech32_prefix,
            "legacy": {
                "address": legacy_addr,
                "validateaddress": legacy_info,
            },
            "p2sh-segwit": {
                "address": p2sh_addr,
                "validateaddress": p2sh_info,
            },
            "bech32": {
                "address": bech32_addr,
                "validateaddress": bech32_info,
            },
        }
        self._write_json("address-sanity.json", address_sanity)
        return address_sanity

    def _generate_blocks(self, node, count):
        if not hasattr(self, "_mining_addresses"):
            self._mining_addresses = {}

        node_index = self.nodes.index(node)
        if node_index not in self._mining_addresses:
            self._mining_addresses[node_index] = node.getnewaddress(
                "segwit-smoke-mining-{}".format(node_index),
                "legacy",
            )

        start_height = node.getblockcount()
        target_height = start_height + count
        hashes = []

        while node.getblockcount() < target_height:
            self._next_mocktime = max(
                getattr(self, "_next_mocktime", 0) + FAST_MINE_TIME_STEP,
                self.nodes[0].getblockheader(self.nodes[0].getbestblockhash())["time"] + FAST_MINE_TIME_STEP,
            )
            for peer in self.nodes:
                peer.setmocktime(self._next_mocktime)

            generated = node.generatetoaddress(
                1,
                self._mining_addresses[node_index],
                REGTEST_MAXTRIES,
            )
            if not generated:
                raise AssertionError(
                    "generatetoaddress produced no blocks with {} blocks still remaining".format(
                        target_height - node.getblockcount()
                    )
                )
            hashes.extend(generated)

        return hashes

    def _init_summary(self):
        self.coin_label = EXPECTED_COIN_LABELS.get(REPO_NAME, REPO_NAME)
        self.expected_bech32_prefix = EXPECTED_REGTEST_BECH32_PREFIXES[REPO_NAME]
        self.phase_snapshots = {}
        self.summary = {
            "coin": self.coin_label,
            "repo_name": REPO_NAME,
            "repo_root": REPO_ROOT,
            "tmpdir": self.options.tmpdir,
            "pow_solver": os.environ.get("BLAKE_HEADER_SOLVER", "python-test-framework-fallback"),
            "vbparams": VB_OVERRIDE,
            "override_log_line": VB_OVERRIDE_LOG_LINE,
            "expected_regtest_bech32_prefix": self.expected_bech32_prefix,
            "regtest_window": REGTEST_WINDOW,
            "regtest_threshold": REGTEST_THRESHOLD,
            "fast_mine_time_step": FAST_MINE_TIME_STEP,
            "consensus_proof": {},
            "phase_sequence_observed": [],
            "status": "running",
        }

    def _coin_consensus_hash(self, payload):
        return p2p_segwit.uint256_from_str(hashlib.sha256(payload).digest())

    def _coin_txid(self, tx):
        return self._coin_consensus_hash(tx.serialize_without_witness())

    def _coin_merkle_root(self, leaf_hashes):
        if not leaf_hashes:
            return 0

        level = [p2p_segwit.ser_uint256(leaf_hashes[0])]
        for leaf_hash in leaf_hashes[1:]:
            level.append(p2p_segwit.ser_uint256(leaf_hash))

        while len(level) > 1:
            if len(level) % 2 == 1:
                level.append(level[-1])

            next_level = []
            for index in range(0, len(level), 2):
                next_level.append(p2p_segwit.hash256(level[index] + level[index + 1]))
            level = next_level

        return p2p_segwit.uint256_from_str(level[0])

    def _refresh_coin_style_block_merkle_root(self, block):
        block.hashMerkleRoot = self._coin_merkle_root([self._coin_txid(tx) for tx in block.vtx])
        block.rehash()

    def _solve_candidate_block(self, block):
        solver = os.environ.get("BLAKE_HEADER_SOLVER")
        if not solver:
            block.solve()
            return

        header_hex = p2p_segwit.bytes_to_hex_str(block.serialize()[:80])
        output = subprocess.check_output([solver, header_hex], text=True).strip().split()
        if not output:
            raise AssertionError("BLAKE_HEADER_SOLVER returned no nonce")

        block.nNonce = int(output[0], 10)
        block.rehash()

    def _build_witness_commitment_block(self):
        template = self.nodes[0].getblocktemplate({"rules": ["segwit"]})
        block = p2p_segwit.CBlock()
        block.nVersion = template["version"] | (1 << p2p_segwit.VB_WITNESS_BIT)
        block.hashPrevBlock = int(template["previousblockhash"], 16)
        block.nTime = template["curtime"]
        block.nBits = int(template["bits"], 16)
        block.nNonce = 0
        coinbase = p2p_segwit.create_coinbase(int(template["height"]))
        coinbase.vout[0].nValue = int(template["coinbasevalue"])
        coinbase.rehash()
        block.vtx = [coinbase]
        p2p_segwit.add_witness_commitment(block)
        self._refresh_coin_style_block_merkle_root(block)
        self._solve_candidate_block(block)
        return block

    def _propose_block(self, block):
        block_hex = p2p_segwit.bytes_to_hex_str(block.serialize(True))
        proposal_result = self.nodes[0].getblocktemplate({"data": block_hex, "mode": "proposal"})
        return block_hex, proposal_result

    def advance_to_segwit_started(self):
        height = self.nodes[0].getblockcount()
        assert height < REGTEST_WINDOW - 1
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "defined")
        self._generate_blocks(self.nodes[0], REGTEST_WINDOW - height - 1)
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "started")

    def advance_to_segwit_lockin(self):
        height = self.nodes[0].getblockcount()
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "started")
        self._generate_blocks(self.nodes[0], REGTEST_WINDOW - 1)
        height = self.nodes[0].getblockcount()
        assert (height % REGTEST_WINDOW) == REGTEST_WINDOW - 2
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "started")
        self._generate_blocks(self.nodes[0], 1)
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "locked_in")

    def advance_to_segwit_active(self):
        segwit = p2p_segwit.get_bip9_status(self.nodes[0], "segwit")
        assert_equal(segwit["status"], "locked_in")

        # getblockchaininfo reports the versionbits state for the next period
        # boundary. Once locked_in is visible, the "since" height marks the
        # first height of that locked_in period, so we need to mine through the
        # full period before the next status query flips to active.
        height = self.nodes[0].getblockcount()
        target_height = segwit["since"] + REGTEST_WINDOW - 1
        assert target_height > height

        self._generate_blocks(self.nodes[0], target_height - height - 1)
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "locked_in")

        self._generate_blocks(self.nodes[0], 1)
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "active")

    def _assert_pre_activation_witness_rejected(self):
        assert p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"] != "active"
        block = self._build_witness_commitment_block()
        block_hex, proposal_result = self._propose_block(block)
        assert proposal_result is not None

        proof = {
            "result": "rejected-before-activation",
            "proposal_result": proposal_result,
            "bestblock": self.nodes[0].getbestblockhash(),
            "candidate_block_hash": block.hash,
            "candidate_block_height": self.nodes[0].getblockcount() + 1,
            "candidate_block_version": block.nVersion,
            "candidate_block_hex_prefix": block_hex[:128],
        }
        self.summary["consensus_proof"]["pre_activation"] = proof
        return proof

    def _assert_post_activation_witness_accepted(self):
        assert_equal(p2p_segwit.get_bip9_status(self.nodes[0], "segwit")["status"], "active")
        block = self._build_witness_commitment_block()
        block_hex, proposal_result = self._propose_block(block)
        assert_equal(proposal_result, None)

        proof = {
            "result": "accepted-after-activation-in-proposal-mode",
            "proposal_result": proposal_result,
            "bestblock": self.nodes[0].getbestblockhash(),
            "candidate_block_hash": block.hash,
            "candidate_block_height": self.nodes[0].getblockcount() + 1,
            "candidate_block_version": block.nVersion,
            "candidate_block_hex_prefix": block_hex[:128],
        }
        self.summary["consensus_proof"]["post_activation"] = proof
        return proof

    def run_test(self):
        self._init_summary()

        self.log.info("Waiting for regtest versionbits override logs")
        self._wait_for_override_logs()
        self.summary["override_logs"] = {
            "node0": self._node_debug_log(0),
            "node1": self._node_debug_log(1),
            "node2": self._node_debug_log(2),
        }

        self.log.info("Capturing initial defined snapshot")
        self._assert_phase("defined", "defined")

        self.log.info("Leaving initial block download before witness proposal checks")
        self._generate_blocks(self.nodes[0], 1)
        self._sync_network()
        self.summary["ibd_exit_height"] = self.nodes[0].getblockcount()

        self.log.info("Running pre-activation witness rejection proof")
        self._assert_pre_activation_witness_rejected()

        self.log.info("Advancing to SegWit started")
        self.advance_to_segwit_started()
        self._sync_network()
        self._assert_phase("started", "started")

        self.log.info("Advancing to SegWit locked_in")
        self.advance_to_segwit_lockin()
        self._sync_network()
        self._assert_phase("locked_in", "locked_in")

        self.log.info("Advancing to SegWit active")
        self.advance_to_segwit_active()
        self._sync_network()
        self._assert_phase("active", "active")

        self.log.info("Running post-activation witness acceptance proof")
        self._assert_post_activation_witness_accepted()

        self.log.info("Running wallet address sanity checks")
        self.summary["address_sanity"] = self._write_address_sanity()

        self.summary["phase_sequence_observed"] = [
            self.phase_snapshots["defined"]["segwit"]["status"],
            self.phase_snapshots["started"]["segwit"]["status"],
            self.phase_snapshots["locked_in"]["segwit"]["status"],
            self.phase_snapshots["active"]["segwit"]["status"],
        ]
        assert_equal(
            self.summary["phase_sequence_observed"],
            ["defined", "started", "locked_in", "active"],
        )

        self.summary["final_segwit_status"] = self.phase_snapshots["active"]["segwit"]["status"]
        self.summary["artifacts"] = {
            "state_defined": self._artifact_path("state-defined.json"),
            "state_started": self._artifact_path("state-started.json"),
            "state_locked_in": self._artifact_path("state-locked_in.json"),
            "state_active": self._artifact_path("state-active.json"),
            "address_sanity": self._artifact_path("address-sanity.json"),
            "activation_state_summary": self._artifact_path("activation-state-summary.txt"),
        }
        self.summary["status"] = "passed"
        self._write_json("summary.json", self.summary)


if __name__ == "__main__":
    SegWitActivationSmoke().main()
