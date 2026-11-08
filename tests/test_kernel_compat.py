"""Regression checks for the DKMS adapter; run with python3 -m unittest discover -s tests."""

import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CHECKS = ROOT / "upstream/configure.ac"
HELPER = ROOT / "dkms/kernel-compat.sh"


class KernelCompatTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.source = pathlib.Path(self.tmp.name) / "source"
        self.build = pathlib.Path(self.tmp.name) / "build"
        self.source.mkdir()
        self.build.mkdir()
        (self.source / "Makefile").touch()
        (self.build / "Module.symvers").touch()

    def probe(self, checks=CHECKS):
        return subprocess.run(
            ["sh", str(HELPER), str(self.source), str(self.build), str(checks)],
            capture_output=True, text=True,
        )

    def write_source(self, path, text):
        dest = self.source / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text)

    def flags(self):
        result = self.probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        return set(result.stdout.split())

    def test_absent_features(self):
        self.assertEqual(self.flags(), {
            "-DLINUX_KERNEL_NO_" + commit + "=" for commit in (
                "944bfc1b1c6f", "2cba193628fe", "f3d93817fba3", "f78c75d84fe8",
                "f5f80e32de12", "1c17f4373d4d", "5f60d5f6bbc1", "e3411e326fa4",
                "92ef0fd55ac8", "449f68f8fffa", "e1d001fa5b47", "490a79faf95e",
                "91d0b78c5177", "1651951ebea5", "908a1d775422", "bb663f0f3c39",
            )
        })

    def test_udp_helpers_are_detected_independently_in_source_tree(self):
        self.write_source("include/net/udp_tunnel.h",
                          "void udp_tunnel_sock_release(struct sock *sk);\n")
        flags = self.flags()
        self.assertNotIn("-DLINUX_KERNEL_NO_944bfc1b1c6f=", flags)
        self.assertIn("-DLINUX_KERNEL_NO_2cba193628fe=", flags)
        self.write_source("include/net/udp_tunnel.h",
                          "void setup_udp_tunnel_sock(struct net *net, struct sock *sk);\n")
        flags = self.flags()
        self.assertIn("-DLINUX_KERNEL_NO_944bfc1b1c6f=", flags)
        self.assertNotIn("-DLINUX_KERNEL_NO_2cba193628fe=", flags)

    def test_symbols_come_from_build_tree(self):
        # A source tree may have stale symbol information from another build.
        self.write_source("Module.symvers", "inet6_sock_destruct\n")
        self.assertIn("-DLINUX_KERNEL_NO_1651951ebea5=", self.flags())
        (self.build / "Module.symvers").write_text("inet6_sock_destruct\n")
        self.assertNotIn("-DLINUX_KERNEL_NO_1651951ebea5=", self.flags())

    def test_inverted_check_and_literal_star(self):
        self.write_source("include/net/sock.h", "int *addr_len;\n")
        self.assertIn("-DLINUX_KERNEL_NO_8341c989ac77=", self.flags())
        self.write_source("include/net/sock.h", "int addr_len;\n")
        self.assertNotIn("-DLINUX_KERNEL_NO_8341c989ac77=", self.flags())

    def test_check_list_is_read_from_upstream(self):
        checks = pathlib.Path(self.tmp.name) / "configure.ac"
        checks.write_text("CHECK_KSYMS([new_feature], [include/new.h], [], [abcdef])\n")
        self.assertEqual(self.probe(checks).stdout.strip(), "-DLINUX_KERNEL_NO_abcdef=")
        self.write_source("include/new.h", "new_feature\n")
        self.assertEqual(self.probe(checks).stdout, "")

    def test_missing_check_list_fails(self):
        self.assertNotEqual(self.probe(self.source / "missing").returncode, 0)

    def test_changed_check_syntax_fails(self):
        checks = pathlib.Path(self.tmp.name) / "configure.ac"
        for text in ("# no checks\n", "CHECK_KSYMS([unsupported])\n"):
            checks.write_text(text)
            self.assertNotEqual(self.probe(checks).returncode, 0)

    def test_missing_symbol_table_fails(self):
        (self.build / "Module.symvers").unlink()
        self.assertNotEqual(self.probe().returncode, 0)


if __name__ == "__main__":
    unittest.main()
