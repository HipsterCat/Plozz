#!/usr/bin/env python3
"""Bounded subprocess lease inheritance, using only private temporary fixtures."""

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
BOUNDED = ROOT / "tools/run-bounded.py"
WRAPPER = ROOT / "tools/with-apple-build-lease.sh"
HELPER = ROOT / "tools/lib/apple_build_lease.py"
SPEC = importlib.util.spec_from_file_location("run_bounded", BOUNDED)
bounded = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bounded)


class BoundedLeaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bounded-lease-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.policy = self.home / ".config/smart-disk-maintenance"
        self.policy.mkdir(parents=True, mode=0o700)
        sentinel = self.policy / ".apple-build-interlock-test-root"
        sentinel.touch(mode=0o600)
        self.namespace = self.policy / "apple-build-interlock-v1"
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("APPLE_BUILD_LEASE_")}
        self.env.update(
            HOME=str(self.home), APPLE_BUILD_INTERLOCK_TESTING="1",
            APPLE_BUILD_INTERLOCK_TEST_ROOT=str(self.namespace),
            PYTHONDONTWRITEBYTECODE="1",
        )

    def run_chain(self, mode="shared", command=None):
        if mode == "exclusive":
            subprocess.run([sys.executable, str(HELPER), "prepare"], env=self.env, check=True)
            policy = subprocess.check_output(
                [sys.executable, str(HELPER), "required-rollout"], env=self.env
            )
            target = self.namespace / "rollout-policy-v1"
            target.write_bytes(policy)
            target.chmod(0o600)
        flags = ["--exclusive"] if mode == "exclusive" else []
        child = command or [str(WRAPPER), *flags, "test/generation", "--", "/usr/bin/true"]
        result = subprocess.run([
            str(WRAPPER), *flags, "test/lane", "--",
            sys.executable, str(BOUNDED), "10", "synthetic generation", "--", *child,
        ], env=self.env, capture_output=True, text=True, timeout=20)
        if result.returncode == 0:
            for _ in range(100):
                if not list((self.namespace / "leases").glob("*.json")):
                    break
                time.sleep(0.05)
            else:
                self.fail("fixture lease did not finalize")
        return result

    def test_shared_bounded_generation_reenters_lease(self):
        result = self.run_chain()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_exclusive_bounded_generation_preserves_policy_descriptors(self):
        result = self.run_chain(mode="exclusive")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unrelated_descriptor_is_not_forwarded(self):
        result = self.run_chain(command=[
            "/bin/bash", "-c",
            'exec 12>"$HOME/unrelated"; exec "$1" "$2" 10 test -- "$1" -c \''
            'import os; '
            '\ntry: os.fstat(12)'
            '\nexcept OSError: pass'
            '\nelse: raise SystemExit("unrelated fd inherited")'
            "'",
            "_", sys.executable, str(BOUNDED),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_authenticated_dynamic_descriptors_are_forwarded(self):
        result = self.run_chain(command=[
            "/bin/bash", "-c",
            'exec 18>&8 19>&9 8>&- 9>&-; '
            'export APPLE_BUILD_LEASE_PROOF_FD=18 APPLE_BUILD_LEASE_LOCK_FD=19; '
            'exec "$1" "$2" 10 dynamic -- "$3" test/dynamic -- /usr/bin/true',
            "_", sys.executable, str(BOUNDED), str(WRAPPER),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_metadata_refuses_before_spawning(self):
        sentinel = self.home / "must-not-run"
        for metadata in (
            {"APPLE_BUILD_LEASE_ID": "partial"},
            {"APPLE_BUILD_LEASE_PROTOCOL": "1", "APPLE_BUILD_LEASE_MODE": "shared",
             "APPLE_BUILD_LEASE_OWNER": "test/forged", "APPLE_BUILD_LEASE_ID": "bad",
             "APPLE_BUILD_LEASE_TOKEN": "bad", "APPLE_BUILD_LEASE_LOCK_FD": "9",
             "APPLE_BUILD_LEASE_PROOF_FD": "8"},
        ):
            result = subprocess.run([
                sys.executable, str(BOUNDED), "10", "invalid", "--",
                "/usr/bin/touch", str(sentinel),
            ], env={**self.env, **metadata}, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stderr)
            self.assertFalse(sentinel.exists())

    def test_unleased_command_still_works(self):
        result = subprocess.run([
            sys.executable, str(BOUNDED), "10", "plain", "--", "/usr/bin/true",
        ], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_timeout_retains_term_then_kill_semantics_without_signalling(self):
        process = mock.Mock(pid=123456)
        process.wait.side_effect = [
            subprocess.TimeoutExpired("fixture", 2),
            subprocess.TimeoutExpired("fixture", 5), 0,
        ]
        with mock.patch.dict(os.environ, self.env, clear=True), \
             mock.patch.object(sys, "argv", ["run-bounded.py", "2", "fixture", "--", "fixture"]), \
             mock.patch.object(bounded.subprocess, "Popen", return_value=process) as spawn, \
             mock.patch.object(bounded.os, "killpg") as killpg:
            self.assertEqual(bounded.main(), 124)
        self.assertTrue(spawn.call_args.kwargs["start_new_session"])
        self.assertEqual(killpg.call_args_list, [
            mock.call(123456, signal.SIGTERM), mock.call(123456, signal.SIGKILL),
        ])


if __name__ == "__main__":
    unittest.main()
