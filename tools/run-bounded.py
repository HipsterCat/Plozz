#!/usr/bin/env python3
"""Run one command with a real wall-clock deadline.

Apple tools sometimes ignore their own --timeout while blocked below CoreDevice
or Xcode's destination resolver. This wrapper owns the process group, forwards
stdout/stderr unchanged, and kills the whole tree when the deadline expires.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def inherited_lease_fds() -> tuple[int, ...]:
    fields = (
        "protocol", "mode", "owner", "lease_id", "token",
        "lock_fd", "proof_fd", "policy_lock_fd", "rollout_fd",
    )
    values = {
        field: os.environ.get("APPLE_BUILD_LEASE_" + ("ID" if field == "lease_id" else field.upper()))
        for field in fields
    }
    if not any(value is not None for value in values.values()):
        return ()
    if values["protocol"] != "1" or values["mode"] not in {"shared", "exclusive"}:
        raise ValueError("invalid inherited build lease protocol or mode")
    required = ["owner", "lease_id", "token", "lock_fd", "proof_fd"]
    if values["mode"] == "exclusive":
        required += ["policy_lock_fd", "rollout_fd"]
    elif values["policy_lock_fd"] is not None or values["rollout_fd"] is not None:
        raise ValueError("shared build lease carries unexpected policy descriptors")
    if any(not values[field] for field in required):
        raise ValueError("incomplete inherited build lease identity")
    descriptors = [int(values[field]) for field in required if field.endswith("_fd")]
    if any(fd < 3 for fd in descriptors) or len(set(descriptors)) != len(descriptors):
        raise ValueError("invalid inherited build lease descriptors")

    sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
    import apple_build_lease as lease

    args = argparse.Namespace(**{
        field: int(value) if field.endswith("_fd") and value is not None else value
        for field, value in values.items() if field != "protocol"
    })
    try:
        lease.validate_existing(args)
    except lease.LeaseError as exc:
        raise ValueError(str(exc)) from exc
    return tuple(descriptors)


def main() -> int:
    if len(sys.argv) < 4 or sys.argv[3] != "--":
        print(
            "usage: run-bounded.py <seconds> <stage-label> -- <command> [args...]",
            file=sys.stderr,
        )
        return 2

    try:
        timeout = float(sys.argv[1])
    except ValueError:
        print(f"invalid timeout: {sys.argv[1]}", file=sys.stderr)
        return 2

    label = sys.argv[2]
    command = sys.argv[4:]
    if not command:
        print("missing command", file=sys.stderr)
        return 2

    try:
        lease_fds = inherited_lease_fds()
    except (ValueError, OSError) as exc:
        print(f"apple-build-interlock: {exc}", file=sys.stderr)
        return 75

    started = time.monotonic()
    process = subprocess.Popen(command, start_new_session=True, pass_fds=lease_fds)
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        elapsed = int(time.monotonic() - started)
        print(
            f"✗ {label} exceeded its hard {int(timeout)}s deadline "
            f"(elapsed {elapsed}s); terminating it.",
            file=sys.stderr,
            flush=True,
        )
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
