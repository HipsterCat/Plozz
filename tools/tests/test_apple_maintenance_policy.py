#!/usr/bin/env python3
"""Policy evidence/locking tests. Every identity and approval is fixture-only."""

import datetime as dt
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/lib"))
import apple_maintenance_policy as policy
import apple_build_lease as lease

CLI = ROOT / "tools/apple-maintenance-policy.py"
WRAPPER = ROOT / "tools/with-apple-build-lease.sh"


class MaintenancePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="apple-policy-tests-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.policy_home = self.home / ".config/smart-disk-maintenance"
        self.policy_home.mkdir(parents=True, mode=0o700)
        (self.policy_home / ".apple-build-interlock-test-root").touch(mode=0o600)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("APPLE_BUILD_LEASE_")}
        self.env.update(
            HOME=str(self.home), PYTHONDONTWRITEBYTECODE="1",
            APPLE_BUILD_INTERLOCK_TESTING="1",
            APPLE_BUILD_INTERLOCK_TEST_ROOT=str(self.policy_home / lease.ROOT_NAME),
        )
        self.patch = mock.patch.dict(os.environ, self.env, clear=True)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        lease.prepare_namespace()
        self.namespace = lease.paths()["root"]
        self.repo = self.home / "repo"
        self.repo.mkdir()
        self.writer = self.repo / "writer.sh"
        self.writer.write_text("#!/bin/sh\nexit 0\n")
        self.writer.chmod(0o644)
        subprocess.run(["git", "init", "--quiet", str(self.repo)], env=self.env, check=True)
        self.manifest = self.home / "manifest.json"
        self.write_json(self.manifest, {
            "schema": 1, "scope": policy.SCOPE,
            "targets": [{"path": str(self.home / "not-deleted"), "evidence": "fixture"}],
        })
        self.evidence = self.home / "owner-evidence.txt"
        self.evidence.write_text("Synthetic fixture owner and human evidence, never production.\n")
        self.evidence.chmod(0o600)
        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
        self.start = now - dt.timedelta(seconds=10)
        self.approved_at = now - dt.timedelta(seconds=1)
        self.package = {
            "schema": 1,
            "host": policy.host_identity(),
            "window": {
                "id": str(uuid.uuid4()), "not_before": self.start.isoformat(),
                "expires_at": (now + dt.timedelta(minutes=30)).isoformat(),
                "scope": policy.SCOPE,
                "manifest_sha256": policy.digest(policy.canonical(
                    policy.document(self.manifest.read_bytes())
                )),
            },
            "cohorts": [
                {"name": name, "roots": [self.root()] if name in (
                    "plozz-current-writers", "global-cleanup-entrypoints",
                    "manual-xcode-writers-disabled-or-wrapped",
                ) else []} for name in policy.COHORTS
            ],
            "registries": [{
                "app": "plozz", "root": str(self.repo),
                "sha256": policy.worktree_snapshot(self.repo)[0],
            }],
        }
        self.request = self.home / "request.json"
        self.approve()

    def write_json(self, path, value):
        path.write_text(json.dumps(value, indent=2) + "\n")
        path.chmod(0o600)
        return {"path": str(path), "sha256": policy.digest(path.read_bytes())}

    def ref(self, path):
        return {"path": str(path), "sha256": policy.digest(path.read_bytes())}

    def root(self):
        return {"identity": policy.identity(self.repo), "writers": [self.ref(self.writer)]}

    def approve(self, overrides=None):
        scope = {key: self.package[key] for key in (
            "schema", "host", "window", "cohorts", "registries",
        )}
        scope_digest = policy.digest(policy.canonical(scope))
        refs = []
        for item in self.package["cohorts"]:
            name = item["name"]
            disposition = ("enhanced" if name == "global-cleanup-entrypoints"
                           else "held" if item["roots"] else "absent")
            att = {
                "schema": 1, "scope_sha256": scope_digest, "cohort": name,
                "owner": "fixture-owner", "session_id": str(uuid.uuid4()),
                "attested_at": self.start.isoformat(), "disposition": disposition,
                "active_queued": "none", "evidence": [self.ref(self.evidence)],
            }
            att.update((overrides or {}).get(name, {}))
            refs.append(self.write_json(self.home / (name + ".json"), att))
        self.package["approval"] = self.write_json(self.home / "approval.json", {
            "schema": 1, "scope_sha256": scope_digest, "approved_by": "fixture-human",
            "approved_at": self.approved_at.isoformat(), "evidence": self.ref(self.evidence),
            "attestations": refs,
        })
        self.write_json(self.request, self.package)

    def install(self, expected="absent"):
        return policy.install(self.request, self.manifest, expected)

    def test_exact_attested_window_installs_without_activation(self):
        marker = self.policy_home / "SUSPENDED"
        marker.write_text("retain")
        marker.chmod(0o600)
        orphan = self.namespace / "leases/retained-evidence"
        orphan.write_bytes(b"unresolved evidence")
        result = self.install()
        self.assertEqual(result["activation"], "unchanged")
        self.assertEqual(marker.read_text(), "retain")
        self.assertEqual(orphan.read_bytes(), b"unresolved evidence")
        self.assertFalse((self.namespace / lease.ROLLOUT_NAME).exists())
        self.assertEqual((self.namespace / policy.POLICY_NAME).read_bytes(), self.request.read_bytes())

    def test_missing_hozz_or_approval_never_creates_policy(self):
        self.package["cohorts"] = self.package["cohorts"][:-1]
        self.approve()
        with self.assertRaisesRegex(lease.LeaseError, "Hozz"):
            self.install()
        self.assertFalse((self.namespace / policy.POLICY_NAME).exists())

    def test_missing_approval_and_invented_attestation_refuse(self):
        (self.home / "approval.json").unlink()
        with self.assertRaises(OSError):
            self.install()
        self.approve({"hozz-current-writers": {"session_id": "unknown-owner"}})
        with self.assertRaisesRegex(lease.LeaseError, "session id"):
            self.install()
        self.assertFalse((self.namespace / policy.POLICY_NAME).exists())

    def test_manifest_digest_binds_evidence_but_ignores_json_whitespace(self):
        parsed = policy.document(self.manifest.read_bytes())
        self.manifest.write_bytes(policy.canonical(parsed))
        self.install()
        parsed["targets"][0]["evidence"] = "different owner release"
        self.write_json(self.manifest, parsed)
        with self.assertRaisesRegex(lease.LeaseError, "manifest differs"):
            policy.validate_package(self.package, self.manifest)

    def test_expired_future_and_overlong_windows_refuse(self):
        now = dt.datetime.now(dt.timezone.utc)
        for start, end in (
            (now - dt.timedelta(hours=1), now - dt.timedelta(seconds=1)),
            (now + dt.timedelta(seconds=10), now + dt.timedelta(minutes=5)),
            (now - dt.timedelta(seconds=1), now + dt.timedelta(hours=3)),
        ):
            self.package["window"].update(not_before=start.isoformat(), expires_at=end.isoformat())
            self.approve()
            with self.assertRaises(lease.LeaseError):
                self.install()

    def test_missing_changed_untrusted_evidence_refuses(self):
        self.evidence.write_text("modified")
        with self.assertRaisesRegex(lease.LeaseError, "changed evidence"):
            self.install()
        self.approve()
        self.evidence.chmod(0o644)
        with self.assertRaisesRegex(lease.LeaseError, "group/world accessible"):
            self.install()

    def test_cross_scope_owner_attestation_refuses(self):
        self.approve({"hozz-current-writers": {"scope_sha256": "0" * 64}})
        with self.assertRaisesRegex(lease.LeaseError, "wrong inventory"):
            self.install()

    def test_unknown_or_queued_unwrapped_owner_refuses(self):
        for status in ("unknown", "protected-by-full-lane-shared-leases"):
            self.approve({"plozz-current-writers": {"active_queued": status}})
            with self.assertRaises(lease.LeaseError):
                self.install()

    def test_legacy_cleanup_cannot_claim_v1_only_wrapping(self):
        self.approve({"global-cleanup-entrypoints": {"disposition": "wrapped"}})
        with self.assertRaisesRegex(lease.LeaseError, "companion window"):
            self.install()

    def test_host_root_and_writer_identity_changes_refuse(self):
        original = self.package["host"]["coordination_inode"]
        self.package["host"]["coordination_inode"] += 1
        self.approve()
        with self.assertRaisesRegex(lease.LeaseError, "different host"):
            self.install()
        self.package["host"]["coordination_inode"] = original
        self.approve()
        self.writer.write_text("changed source")
        with self.assertRaisesRegex(lease.LeaseError, "writer changed"):
            self.install()

    def test_registered_root_or_head_changes_refuse(self):
        self.package["registries"][0]["sha256"] = "0" * 64
        self.approve()
        with self.assertRaisesRegex(lease.LeaseError, "registered roots/HEADs"):
            self.install()

    def test_registry_addition_invalidates_previously_reviewed_package(self):
        subprocess.run(["git", "-C", str(self.repo), "add", "writer.sh"],
                       env=self.env, check=True)
        subprocess.run([
            "git", "-C", str(self.repo), "-c", "user.name=Fixture",
            "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false",
            "commit", "--quiet", "-m", "fixture",
        ], env=self.env, check=True)
        self.package["registries"][0]["sha256"] = policy.worktree_snapshot(self.repo)[0]
        self.approve()
        subprocess.run([
            "git", "-C", str(self.repo), "worktree", "add", "--quiet", "--detach",
            str(self.home / "new-unreviewed-worktree"), "HEAD",
        ], env=self.env, check=True)
        with self.assertRaisesRegex(lease.LeaseError, "registered roots/HEADs"):
            self.install()

    def test_absence_cannot_hide_registered_roots(self):
        for item in self.package["cohorts"]:
            if item["name"] == "plozz-current-writers":
                item["roots"] = []
        self.approve()
        with self.assertRaisesRegex(lease.LeaseError, "outside declared cohort"):
            self.install()

    def test_wrapped_claim_requires_frozen_protocol_bytes(self):
        self.approve({"plozz-current-writers": {"disposition": "wrapped"}})
        with self.assertRaises(OSError):
            self.install()
        for name in policy.PROTOCOL_FILES:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, path)
        self.install()

    def test_policy_shared_holder_blocks_update_nonblocking(self):
        fd = os.open(lease.paths()["policy_lock"], os.O_RDWR)
        try:
            lease.fcntl.flock(fd, lease.fcntl.LOCK_SH)
            with self.assertRaisesRegex(lease.LeaseError, "policy is in use"):
                self.install()
        finally:
            os.close(fd)
        self.install()

    def test_cross_process_policy_updater_conflict(self):
        child = subprocess.Popen([
            "/usr/bin/python3", "-c",
            "import fcntl,sys; f=open(sys.argv[1], 'r+'); "
            "fcntl.flock(f, fcntl.LOCK_EX); print('ready', flush=True); sys.stdin.readline()",
            str(lease.paths()["policy_lock"]),
        ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env=self.env)
        try:
            self.assertEqual(child.stdout.readline().strip(), "ready")
            with self.assertRaisesRegex(lease.LeaseError, "policy is in use"):
                self.install()
        finally:
            child.communicate("\n", timeout=10)
        self.assertEqual(child.returncode, 0)
        self.install()

    def test_compare_and_swap_refuses_lost_update_and_retains_prior_policy(self):
        installed = self.install()
        before = (self.namespace / policy.POLICY_NAME).read_bytes()
        with self.assertRaisesRegex(lease.LeaseError, "compare-and-swap"):
            self.install()
        self.assertEqual((self.namespace / policy.POLICY_NAME).read_bytes(), before)
        self.install(installed["policy_sha256"])

    def test_symlinked_policy_and_outside_fixture_input_refuse(self):
        target = self.namespace / policy.POLICY_NAME
        target.symlink_to(self.request)
        with self.assertRaises(lease.LeaseError):
            self.install()
        with self.assertRaisesRegex(lease.LeaseError, "escapes fixture HOME"):
            policy.read_bytes(ROOT / "tools/run-bounded.py", private=False)

    def test_check_requires_exclusive_lease_and_suspension_stays_closed(self):
        self.install()
        with self.assertRaisesRegex(lease.LeaseError, "exclusive lease"):
            policy.check(self.manifest, self.package["window"]["id"])
        (self.policy_home / "SUSPENDED").touch(mode=0o600)
        with self.assertRaisesRegex(lease.LeaseError, "suspended"):
            policy.check(self.manifest, self.package["window"]["id"])

    def test_companion_check_under_real_exclusive_fixture_lease(self):
        self.install()
        rollout = self.namespace / lease.ROLLOUT_NAME
        rollout.write_text("\n".join(lease.REQUIRED_ROLLOUT) + "\n")
        rollout.chmod(0o600)
        result = subprocess.run([
            str(WRAPPER), "--exclusive", "test/policy-check", "--",
            "/usr/bin/python3", str(CLI), "check", "--manifest", str(self.manifest),
            "--window-id", self.package["window"]["id"],
        ], env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["window_id"], self.package["window"]["id"])
        for _ in range(100):
            if not list((self.namespace / "leases").glob("*.json")):
                break
            time.sleep(0.05)
        else:
            self.fail("fixture finalizer did not finish")

    def test_failed_owner_evidence_blocks_cleanup_and_is_never_resolved(self):
        failed = subprocess.run([
            str(WRAPPER), "test/failed-owner", "--", "/bin/sh", "-c", "exit 3",
        ], env=self.env, capture_output=True, text=True)
        self.assertEqual(failed.returncode, 3)
        records = list((self.namespace / "leases").glob("*.json"))
        self.assertEqual(len(records), 1)
        before = records[0].read_bytes()
        self.install()
        rollout = self.namespace / lease.ROLLOUT_NAME
        rollout.write_text("\n".join(lease.REQUIRED_ROLLOUT) + "\n")
        rollout.chmod(0o600)
        attempt = subprocess.run([
            str(WRAPPER), "--exclusive", "test/cleanup", "--", "/usr/bin/true",
        ], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(attempt.returncode, 0)
        self.assertIn("lease registry is not empty", attempt.stderr)
        self.assertEqual(records[0].read_bytes(), before)

    def test_json_duplicates_and_nonfinite_numbers_refuse(self):
        for value in (
            b'{"schema":1,"schema":1}', b'{"v":NaN}', b'{"v":Infinity}',
            b'{"v":1e400}', b'{"nested":[-1e500]}',
        ):
            with self.assertRaises(lease.LeaseError):
                policy.document(value)
        with self.assertRaises(ValueError):
            policy.canonical({"v": float("nan")})


if __name__ == "__main__":
    unittest.main()
