#!/usr/bin/env python3
"""Attested maintenance windows layered over the unchanged v1 build lease.

This tool never writes rollout-policy-v1, clears SUSPENDED, resolves lease
records, or deletes build resources. Same-user owner attestations are operational
evidence reviewed by the approving human, not cryptographic proof of a person's
identity or a way to prevent an uncooperative writer from starting.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import json
import math
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import apple_build_lease as lease

POLICY_NAME = "maintenance-window-v1.json"
SCOPE = "apple-owner-released-build-outputs-only"
MAX_WINDOW_SECONDS = 7200
MAX_DOCUMENT_BYTES = 4 * 1024 * 1024
COHORTS = tuple(lease.REQUIRED_ROLLOUT[1:]) + (
    "hozz-current-writers",
    "hozz-legacy-writers",
)
PROTOCOL_COMMIT = "b1d24c0def3e980a9487d9042420a149298db867"
PROTOCOL_FILES = {
    "tools/lib/apple_build_lease.py": "56a54b71f9a642ddd5e10a51128bc59610cbe6e3f9600cc7f6799c3b196bdca2",
    "tools/lib/apple-build-lease.sh": "bcb0a687d32ffa740953a687c812515d2516bd0ba90ea824c01c21fc6303c705",
    "tools/lib/apple_build_lease.rb": "c7726eaf3470da9dacbacbdf65d86ce353770f47da15882624be4455b7008372",
    "tools/with-apple-build-lease.sh": "dc3d932b08b8056704bd37920694952effca451abb155cce1cf8e356752f1b99",
}
HEX = re.compile(r"^[0-9a-f]{64}$")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False,
    ).encode()


def exact(value: Any, keys: set[str], label: str) -> dict:
    if not isinstance(value, dict) or set(value) != keys:
        lease.fail(f"{label}: expected exactly {sorted(keys)}")
    return value


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        lease.fail(f"{label}: nonempty text required")
    return value


def sha(value: Any) -> str:
    if not isinstance(value, str) or not HEX.fullmatch(value):
        lease.fail("expected a lowercase SHA-256 digest")
    return value


def timestamp(value: Any) -> dt.datetime:
    value = text(value, "timestamp")
    try:
        result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        lease.fail(f"invalid timestamp: {value}")
    if result.tzinfo is None or result.utcoffset() != dt.timedelta(0):
        lease.fail("timestamps must explicitly use UTC")
    return result


def physical_path(value: Any) -> Path:
    path = Path(text(value, "path"))
    if not path.is_absolute() or path != path.resolve(strict=True):
        lease.fail(f"path must be absolute and physical, without symlink aliases: {path}")
    if os.environ.get("APPLE_BUILD_INTERLOCK_TESTING") == "1":
        home = lease.paths()["home"]
        if path != home and home not in path.parents:
            lease.fail(f"test policy input escapes fixture HOME: {path}")
    return path


def read_bytes(path: Path, *, private: bool) -> bytes:
    path = physical_path(str(path))
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        before = lease.validate_fd_path(fd, path, private=private)
        data = bytearray()
        while len(data) <= MAX_DOCUMENT_BYTES:
            chunk = os.read(fd, min(65536, MAX_DOCUMENT_BYTES + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        after = lease.validate_fd_path(fd, path, private=private)
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
            after.st_size, after.st_mtime_ns, after.st_ctime_ns
        ):
            lease.fail(f"input changed while being read: {path}")
        if len(data) > MAX_DOCUMENT_BYTES:
            lease.fail(f"policy input exceeds {MAX_DOCUMENT_BYTES} bytes: {path}")
        return bytes(data)
    finally:
        os.close(fd)


def no_duplicates(pairs: list[tuple[str, Any]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            lease.fail(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def document(data: bytes) -> dict:
    def invalid_constant(value: str) -> None:
        lease.fail(f"nonfinite JSON number: {value}")

    def finite_float(value: str) -> float:
        number = float(value)
        if not math.isfinite(number):
            lease.fail(f"nonfinite JSON number: {value}")
        return number

    value = json.loads(
        data, object_pairs_hook=no_duplicates, parse_constant=invalid_constant,
        parse_float=finite_float,
    )
    if not isinstance(value, dict):
        lease.fail("policy document must be a JSON object")
    return value


def reference(value: Any) -> bytes:
    exact(value, {"path", "sha256"}, "evidence reference")
    data = read_bytes(Path(value["path"]), private=True)
    if not data or digest(data) != sha(value["sha256"]):
        lease.fail(f"missing or changed evidence: {value['path']}")
    return data


def identity(path: Path) -> dict:
    path = physical_path(str(path))
    st = path.stat()
    lease._check_owned(st, str(path))
    if not stat.S_ISDIR(st.st_mode):
        lease.fail(f"writer root must be a directory: {path}")
    return {"path": str(path), "device": st.st_dev, "inode": st.st_ino}


def host_identity() -> dict:
    p = lease.paths()
    lease.ensure_secure_directory(p["root"], create=False)
    fd = lease._open_regular_file(p["lock"], os.O_RDONLY)
    try:
        st = lease.validate_fd_path(fd, p["lock"], private=True)
        return {
            "uid": lease.EFFECTIVE_UID,
            "home": identity(p["home"]),
            "namespace": identity(p["root"]),
            "coordination_device": st.st_dev,
            "coordination_inode": st.st_ino,
        }
    finally:
        os.close(fd)


def validate_root(root: Any, disposition: str) -> None:
    exact(root, {"identity", "writers"}, "writer root")
    expected = exact(root["identity"], {"path", "device", "inode"}, "root identity")
    path = physical_path(expected["path"])
    if identity(path) != expected:
        lease.fail(f"writer root identity changed: {path}")
    writers = root["writers"]
    if not isinstance(writers, list) or not writers:
        lease.fail(f"explicit writer fingerprints required: {path}")
    seen = set()
    for writer in writers:
        exact(writer, {"path", "sha256"}, "writer fingerprint")
        file = physical_path(writer["path"])
        if path not in file.parents or str(file) in seen:
            lease.fail(f"duplicate writer or writer outside its root: {file}")
        seen.add(str(file))
        if digest(read_bytes(file, private=False)) != sha(writer["sha256"]):
            lease.fail(f"writer changed since owner review: {file}")
    if disposition == "wrapped":
        for relative, expected_digest in PROTOCOL_FILES.items():
            if digest(read_bytes(path / relative, private=False)) != expected_digest:
                lease.fail(f"wrapped root does not contain frozen v1 protocol: {path / relative}")


def worktree_snapshot(root: Path) -> tuple[str, set[str]]:
    root = physical_path(str(root))
    result = subprocess.run(
        ["git", "-C", str(root), "worktree", "list", "--porcelain", "-z"],
        env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"},
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if result.returncode:
        lease.fail(f"cannot enumerate registered worktrees at {root}: {result.stderr.decode(errors='replace')}")
    roots = {
        field[len("worktree "):] for field in result.stdout.decode().split("\0")
        if field.startswith("worktree ")
    }
    if not roots or str(root) not in roots:
        lease.fail(f"unexpected worktree registry at {root}")
    return digest(result.stdout), roots


def validate_registries(registries: Any, cohorts: list[dict]) -> None:
    if not isinstance(registries, list):
        lease.fail("explicit repository registries required")
    observed: dict[str, set[str]] = {app: set() for app in ("plozz", "mozz", "twozz", "hozz")}
    declared = {
        app: {
            root["identity"]["path"]
            for cohort in cohorts if cohort["name"] in {f"{app}-current-writers", f"{app}-legacy-writers"}
            for root in cohort["roots"]
        } for app in observed
    }
    seen = set()
    for registry in registries:
        exact(registry, {"app", "root", "sha256"}, "repository registry")
        app, root = registry["app"], registry["root"]
        if app not in observed or root not in declared[app] or (app, root) in seen:
            lease.fail("unknown or duplicate registry, or registry root outside declared cohort")
        seen.add((app, root))
        actual, roots = worktree_snapshot(Path(root))
        if actual != sha(registry["sha256"]):
            lease.fail(f"registered roots/HEADs changed since owner review: {root}")
        observed[app].update(roots)
    if observed != declared:
        lease.fail("every registered worktree must be inventoried; no unknown roots or unattested repositories")


def validate_package(package: Any, manifest: Path) -> dict:
    exact(package, {"schema", "host", "window", "cohorts", "registries", "approval"}, "window package")
    if type(package["schema"]) is not int or package["schema"] != 1:
        lease.fail("unsupported maintenance window schema")
    if package["host"] != host_identity():
        lease.fail("maintenance window belongs to a different host/UID/lock identity")
    window = exact(package["window"], {
        "id", "not_before", "expires_at", "scope", "manifest_sha256",
    }, "window")
    lease.validate_uuid(window["id"], "maintenance window id")
    start, end = timestamp(window["not_before"]), timestamp(window["expires_at"])
    now = dt.datetime.now(dt.timezone.utc)
    if not 0 < (end - start).total_seconds() <= MAX_WINDOW_SECONDS:
        lease.fail("maintenance window must be positive and at most two hours")
    if not start <= now < end:
        lease.fail("maintenance window is not yet open or has expired")
    if window["scope"] != SCOPE:
        lease.fail("only exact owner-released Apple build-output manifests are supported")
    manifest_doc = document(read_bytes(manifest, private=True))
    if (
        type(manifest_doc.get("schema")) is not int
        or manifest_doc["schema"] != 1
        or manifest_doc.get("scope") != SCOPE
        or not isinstance(manifest_doc.get("targets"), list)
        or not manifest_doc["targets"]
    ):
        lease.fail("expected a nonempty version-1 Apple owner-released manifest")
    if digest(canonical(manifest_doc)) != sha(window["manifest_sha256"]):
        lease.fail("deletion manifest differs from approved window")

    cohorts = package["cohorts"]
    if not isinstance(cohorts, list):
        lease.fail("cohorts must be an explicit inventory")
    for item in cohorts:
        exact(item, {"name", "roots"}, "cohort")
    if sorted(item["name"] for item in cohorts) != sorted(COHORTS):
        lease.fail("exact cohort inventory required, including Hozz current and legacy writers")
    scope_digest = digest(canonical({key: package[key] for key in (
        "schema", "host", "window", "cohorts", "registries",
    )}))
    approval = document(reference(package["approval"]))
    exact(approval, {
        "schema", "scope_sha256", "approved_by", "approved_at", "evidence", "attestations",
    }, "human approval")
    if type(approval["schema"]) is not int or approval["schema"] != 1 or approval["scope_sha256"] != scope_digest:
        lease.fail("human approval is not bound to this exact inventory/window/manifest")
    text(approval["approved_by"], "approver identity")
    approved_at = timestamp(approval["approved_at"])
    if not start <= approved_at <= now:
        lease.fail("human approval must be issued inside this window, not in the future")
    reference(approval["evidence"])
    refs = approval["attestations"]
    if not isinstance(refs, list) or len(refs) != len(COHORTS):
        lease.fail("one reviewed owner attestation per cohort is required")
    attestations = {}
    for ref in refs:
        att = document(reference(ref))
        exact(att, {
            "schema", "scope_sha256", "cohort", "owner", "session_id", "attested_at",
            "disposition", "active_queued", "evidence",
        }, "owner attestation")
        if type(att["schema"]) is not int or att["schema"] != 1 or att["scope_sha256"] != scope_digest:
            lease.fail("owner attestation has the wrong inventory/window/manifest scope")
        if att["cohort"] not in COHORTS or att["cohort"] in attestations:
            lease.fail("duplicate or unknown attestation cohort")
        text(att["owner"], "owner identity")
        lease.validate_uuid(att["session_id"], "owner session id")
        if not start <= timestamp(att["attested_at"]) <= approved_at:
            lease.fail("owner attestation is outside this window or newer than approval")
        if att["disposition"] not in {"wrapped", "held", "disabled", "absent", "enhanced"}:
            lease.fail("unknown/unreviewed writer disposition")
        if att["active_queued"] not in {"none", "protected-by-full-lane-shared-leases"}:
            lease.fail("unknown active or queued owners prevent maintenance")
        if att["disposition"] != "wrapped" and att["active_queued"] != "none":
            lease.fail("unwrapped active or queued work must remain protected; no hold inferred")
        evidence = att["evidence"]
        if not isinstance(evidence, list) or not evidence:
            lease.fail("owner attestation requires durable evidence")
        for entry in evidence:
            reference(entry)
        attestations[att["cohort"]] = att
    for item in cohorts:
        att = attestations[item["name"]]
        disposition = att["disposition"]
        roots = item["roots"]
        if not isinstance(roots, list):
            lease.fail("cohort roots must be a list")
        if disposition == "absent":
            if roots or item["name"] in {
                "global-cleanup-entrypoints", "manual-xcode-writers-disabled-or-wrapped",
            }:
                lease.fail("absence attestation cannot hide existing roots or global/manual writers")
        elif not roots:
            lease.fail("non-absent cohort requires exact root inventory")
        if item["name"] == "global-cleanup-entrypoints" and disposition != "enhanced":
            lease.fail("every cleanup entrypoint must enforce the companion window, not v1 alone")
        if item["name"] != "global-cleanup-entrypoints" and disposition == "enhanced":
            lease.fail("enhanced disposition is reserved for cleanup entrypoints")
        seen = set()
        for root in roots:
            validate_root(root, disposition)
            name = root["identity"]["path"]
            if name in seen:
                lease.fail(f"duplicate root in cohort: {name}")
            seen.add(name)
    validate_registries(package["registries"], cohorts)
    if dt.datetime.now(dt.timezone.utc) >= end:
        lease.fail("maintenance window expired during evidence inspection")
    return {"window_id": window["id"], "scope_sha256": scope_digest, "expires_at": window["expires_at"]}


@contextlib.contextmanager
def policy_update_lock():
    p = lease.paths()
    lease.ensure_secure_directory(p["root"], create=False)
    fd = lease._open_regular_file(p["policy_lock"], os.O_RDWR)
    try:
        try:
            lease.fcntl.flock(fd, lease.fcntl.LOCK_EX | lease.fcntl.LOCK_NB)
        except BlockingIOError:
            lease.fail("policy is in use by maintenance or another updater; update refused")
        lease.validate_fd_path(fd, p["policy_lock"], private=True)
        yield
        lease.validate_fd_path(fd, p["policy_lock"], private=True)
    finally:
        os.close(fd)


def install(package_path: Path, manifest: Path, expected: str) -> dict:
    if expected != "absent":
        sha(expected)
    with policy_update_lock():
        # Read and validate under the conflicting lock, not before acquiring it.
        data = read_bytes(package_path, private=True)
        result = validate_package(document(data), manifest)
        target = lease.paths()["root"] / POLICY_NAME
        if target.exists() or target.is_symlink():
            current = digest(read_bytes(target, private=True))
        else:
            current = "absent"
        if current != expected:
            lease.fail("companion policy changed since review; compare-and-swap refused")
        fd, temporary = tempfile.mkstemp(prefix=".maintenance-window-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, target)
            lease.fsync_directory(target.parent)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        return {**result, "policy_sha256": digest(data), "activation": "unchanged"}


def inherited_exclusive() -> argparse.Namespace:
    fields = ("owner", "lease_id", "token", "lock_fd", "proof_fd", "policy_lock_fd", "rollout_fd")
    if os.environ.get("APPLE_BUILD_LEASE_PROTOCOL") != "1" or os.environ.get("APPLE_BUILD_LEASE_MODE") != "exclusive":
        lease.fail("companion check requires an inherited, authenticated v1 exclusive lease")
    values: dict[str, Any] = {"mode": "exclusive"}
    for field in fields:
        value = os.environ.get("APPLE_BUILD_LEASE_" + ("ID" if field == "lease_id" else field.upper()))
        if not value:
            lease.fail(f"missing exclusive lease identity: {field}")
        values[field] = int(value) if field.endswith("_fd") else value
    args = argparse.Namespace(**values)
    lease.validate_existing(args)
    return args


def check(manifest: Path, window_id: str) -> dict:
    lease.ensure_not_suspended()
    args = inherited_exclusive()
    target = lease.paths()["root"] / POLICY_NAME
    data = read_bytes(target, private=True)
    result = validate_package(document(data), manifest)
    if result["window_id"] != window_id:
        lease.fail("maintenance window id differs from caller's approved window")
    # Re-check lease and suspension after potentially slow evidence inspection.
    lease.validate_existing(args)
    lease.ensure_not_suspended()
    package = document(data)
    if dt.datetime.now(dt.timezone.utc) >= timestamp(package["window"]["expires_at"]):
        lease.fail("maintenance window expired during evidence inspection")
    return {**result, "policy_sha256": digest(data)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("host")
    commands.add_parser("protocol")
    snapshot_parser = commands.add_parser("worktree-snapshot")
    snapshot_parser.add_argument("root", type=Path)
    for name in ("validate", "install", "check"):
        cmd = commands.add_parser(name)
        cmd.add_argument("--manifest", type=Path, required=True)
        if name == "check":
            cmd.add_argument("--window-id", required=True)
        else:
            cmd.add_argument("--request", type=Path, required=True)
        if name == "install":
            cmd.add_argument("--expect-current", required=True)
    args = parser.parse_args()
    try:
        if args.command == "host":
            result = host_identity()
        elif args.command == "protocol":
            result = {"protocol": 1, "commit": PROTOCOL_COMMIT, "files": PROTOCOL_FILES, "cohorts": COHORTS}
        elif args.command == "worktree-snapshot":
            checksum, roots = worktree_snapshot(args.root)
            result = {"root": str(args.root), "sha256": checksum, "registered_roots": sorted(roots)}
        elif args.command == "install":
            result = install(args.request, args.manifest, args.expect_current)
        elif args.command == "check":
            result = check(args.manifest, args.window_id)
        else:
            result = validate_package(document(read_bytes(args.request, private=True)), args.manifest)
        print(json.dumps(result, sort_keys=True, indent=2))
        return 0
    except (lease.LeaseError, OSError, ValueError, TypeError, KeyError) as exc:
        print(f"apple-maintenance-policy: {exc}", file=sys.stderr)
        return 75


if __name__ == "__main__":
    sys.exit(main())
