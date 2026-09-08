# Attested Apple maintenance windows

These tools do not authorize or activate storage reclamation. The policy tool
does not delete resources; the separate cleanup adapter's explicit `apply`
command requires an already authorized window and inherited exclusive lease.
Neither tool removes `SUSPENDED`, writes `rollout-policy-v1`, resolves lease
records, changes schedules, or stops writers. A feature merge does not enable
global cleanup.

## Compatibility and rollout

Build clients use the unchanged v1 namespace and lease protocol from commit
`b1d24c0def3e980a9487d9042420a149298db867`. Vendor these four paths byte-for-byte,
preserving relative layout:

| File | SHA-256 |
| --- | --- |
| `tools/lib/apple_build_lease.py` | `56a54b71f9a642ddd5e10a51128bc59610cbe6e3f9600cc7f6799c3b196bdca2` |
| `tools/lib/apple-build-lease.sh` | `bcb0a687d32ffa740953a687c812515d2516bd0ba90ea824c01c21fc6303c705` |
| `tools/lib/apple_build_lease.rb` | `c7726eaf3470da9dacbacbdf65d86ce353770f47da15882624be4455b7008372` |
| `tools/with-apple-build-lease.sh` | `dc3d932b08b8056704bd37920694952effca451abb155cce1cf8e356752f1b99` |

`tools/apple-maintenance-policy.py protocol` reports the same manifest. New
policy tooling additionally needs `tools/apple-maintenance-policy.py` and
`tools/lib/apple_maintenance_policy.py` from the reviewed policy feature commit.
The two companion files must travel together.

Public build entrypoint:

```bash
tools/with-apple-build-lease.sh app/whole-release-lane -- command arguments
```

The wrapper changes working directory to its bundle's repository root. Use an
absolute command or explicitly change directory *inside* the protected command.
It must wrap the whole lane, including generation, package resolution, signing,
both platform builds, upload/processing/distribution, tagging, and queued gaps.
Wrapping each command separately does not protect the gaps between agent turns.
Python launchers must authenticate and explicitly pass the lease descriptors;
see `tools/run-bounded.py`. Never use `close_fds=False`.

The frozen `rollout-policy-v1` has no Hozz tokens. Adding tokens would break its
exact-match old readers, so this feature does **not** modify that schema. Instead,
enhanced global cleanup must require the companion
`apple-build-interlock-v1/maintenance-window-v1.json` as well as the existing v1
exclusive lease. Every old v1-only or broad cleanup entrypoint must be disabled
or upgraded before any activation. Otherwise an old reader could ignore Hozz,
expiry, owner holds, and target scope. Installing the companion alone does not
close this bypass.

## Operator workflow

1. Inventory every registered root, unregistered clone, raw/manual writer, and
   cleanup entrypoint on this machine. Include current **and** legacy Plozz,
   Mozz, Twozz, and Hozz. Account for active and queued work, not just processes.
2. Obtain actual owner attestations and durable evidence for that exact scope.
   Unwrapped owners may explicitly hold their work for a bounded window; this
   tool does not request such holds or manufacture agreement.
3. Obtain explicit human approval of the complete window package and the exact
   owner-released manifest, including provenance/evidence. Approval must be
   issued during the window, after its owner attestations.
4. Validate, then install the companion using compare-and-swap. This does not
   activate cleanup. Separately approved activation of existing suspension and
   legacy gates still requires their conflicting policy lock.
5. Enhanced cleanup acquires the v1 exclusive lease, checks the companion before
   each destructive step, and also enforces target eligibility, per-path open-use
   checks, process safety checks, age, and release evidence. All remain required.

There are no `--all-clear`, owner-generation, auto-approval, resume, or
stale-record-resolution options.

```bash
# Read-only identity aids. Namespace must already exist.
/usr/bin/python3 tools/apple-maintenance-policy.py host
/usr/bin/python3 tools/apple-maintenance-policy.py worktree-snapshot /physical/repo

# Review a supplied package without installing it.
/usr/bin/python3 tools/apple-maintenance-policy.py validate \
  --request /private/window-request.json --manifest /private/manifest.json

# Future explicitly authorized companion installation, NOT performed by this change.
/usr/bin/python3 tools/apple-maintenance-policy.py install \
  --request /private/window-request.json --manifest /private/manifest.json \
  --expect-current absent
```

For replacement, `--expect-current` is the current companion's raw SHA-256, not
`absent`. Install takes `policy.lock` exclusively and nonblocking **before**
reading/validating its request. Concurrent maintenance or an updater denies the
operation. Publication is mode-0600, fsynced, atomic, and compare-and-swap guarded.
A failure never fabricates a successful approval. A failed fsync may leave the
new companion present; it still does not activate anything. Inspect before retry.

Runtime contract, called by the installed adapter with inherited exclusive FDs:

```bash
/usr/bin/python3 /reviewed/bundle/tools/apple-maintenance-policy.py check \
  --manifest /private/manifest.json --window-id 00000000-0000-0000-0000-000000000000
```

The UUID above is a placeholder, not an approval. Exit 0 returns `window_id`,
`scope_sha256`, `expires_at` (UTC/RFC3339), and `policy_sha256`. Exit 75 refuses.
Missing, stale, malformed, forged, or closed inherited capabilities never fall
back to a new lease. The frozen protocol authenticates the capabilities and
retains the policy's shared lock throughout maintenance. Companion checks repeat
lease/suspension validation after evidence inspection.

Adapters must check the deadline before **every unlink**, not just each root.
Expiry/cancellation stops further deletion without signalling another process.
A partly processed target or quarantine and its journal remain protected for
owner review, not automatic resumption. A filesystem operation already in
progress at the deadline cannot be undone or forcibly interrupted safely.

## Document contract (schema 1)

All paths are absolute physical paths: no symlink aliases. Evidence, manifests,
requests, approvals, attestations, and installed companion files must be owned
by the effective UID and mode 0600 (or stricter). Writer sources may be readable
by others, but not writable by others. JSON duplicate fields and nonfinite
numbers fail closed.

Manifest top-level contract:

```json
{
  "schema": 1,
  "scope": "apple-owner-released-build-outputs-only",
  "targets": ["ADAPTER-VALIDATED EXACT TARGET RECORDS"]
}
```

This illustrative placeholder is **not** a valid adapter deletion target. The
adapter owns the target schema/validator: exact physical path and kind
(`worktree-apple-build` or `xcode-derived-data`), owner worktree/session, root
device/inode, release evidence, timestamps, whole-tree age of at least 72 hours,
and an inode-aware tree digest. This companion checks the nonempty schema/scope
and approval binding, not destructive eligibility. It must never be used alone
as a deletion implementation.

## Exact-manifest cleanup adapter

`tools/apple-build-cleanup.py` and `tools/lib/apple_build_cleanup.py` implement
inventory, non-destructive validation, and separately authorized application.
There is no default deletion, automatic discovery/sweep, installation, owner
record generation, or automatic resume. Only paths named by supplied owner
release records are inspected. Inventory reads metadata, not target file
contents, and writes only stdout unless an explicit new output file is requested.

```bash
/usr/bin/python3 -B tools/apple-build-cleanup.py inventory \
  --release-record /physical/private/owner-release.json \
  --output /physical/private/manifest.json
/usr/bin/python3 -B tools/apple-build-cleanup.py validate \
  --manifest /physical/private/manifest.json
```

`--release-record` can be repeated. All inputs must already exist, be physical
and owned by the effective UID, and meet the existing private evidence rules.
Use the executable's `-B` shebang or the explicit `python3 -B` invocations above:
setting a flag inside Python is too late to prevent interpreter-startup bytecode
cache writes. The CLI also suppresses bytecode writes in its descendants.

Output/journal parents must already exist and be private, outside owner
worktrees, targets, protected resources and the maintenance configuration/lease
namespace. Existing output files are never overwritten. `validate` does not
acquire a lease, install a policy,
write a journal, or delete anything; it is not an authorization check.

Owner release schema (exact keys; this is documentation, not an attestation):

```json
{
  "schema": 1,
  "scope": "apple-owner-released-build-outputs-only",
  "owner": "<responsible owner>",
  "session_id": "<owner session UUID>",
  "released_at": "<UTC time of actual release>",
  "worktree": {"path": "<physical Git worktree>", "device": 1, "inode": 2},
  "evidence": [{"path": "<private durable owner evidence>", "sha256": "<digest>"}],
  "targets": [{
    "kind": "worktree-apple-build",
    "identity": {"path": "<exact released output>", "device": 1, "inode": 3}
  }]
}
```

The owner evidence must establish that these exact outputs are retired,
reconstructable, not active/queued or still-needed warm resources, and contain
no required evidence or protected data. An idle process or an old file does not
establish that. A file's inode must match the owner's release record before
inventory; a later replacement cannot inherit the old owner's release.

Eligibility is deliberately narrower than an entire cache:

- `worktree-apple-build`: a file or directory at/below that owner's `.build`.
  Git-tracked entries are refused, even if they have generated-looking names.
- `xcode-derived-data`: a file or subtree in a direct app root of the canonical
  `~/Library/Developer/Xcode/DerivedData`. That root's existing `info.plist`
  must identify a workspace within the declared owner worktree. Top-level shared
  `.noindex` roots, aliases and alternate cache-root overrides are not supported.
- Regular files must have a recognized compiler-output suffix: `.o`, `.pcm`,
  `.swiftmodule`, `.swiftdoc`, `.swiftsourceinfo`, `.swiftdeps`,
  `.swiftconstvalues`, `.dia`, or `.hmap`. Unknown files, including ambiguous
  `.d`/`.pch` source/header files, are refused rather than guessed disposable.
- Any protected path component or suffix refuses the whole nominated tree:
  source/Git, package stores/checkouts/artifacts, logs/evidence,
  archives/IPAs/dSYMs/xcresults, credentials/signing, SDKs/toolchains, simulators,
  VMs, Trash, and shared dependency stores. Symlinks, hard-linked files, special
  files, cross-filesystem descendants and group/world-writable entries also
  refuse. No automatic carving around exclusions occurs.
- The actual owner release and **every** entry must be at least 72 hours old.
  Entry age uses the youngest of mtime, ctime and birthtime, not the root's
  mtime alone. `--minimum-age-hours` can increase, never reduce, that minimum.
  Nested/overlapping targets and evidence within any target are rejected.

Consequently a normal `.build` containing `SourcePackages`, logs or release
outputs is **not** an eligible target. Its owner can instead release precise
retired compiler files or clean compiler-only subtrees. This adapter does not
solve shared dependency retention, absent-owner/orphan recovery, or release
artifact retention by widening the deletion policy.

### Supported limits and scaling

The adapter deliberately accepts only **256 exact targets** per manifest or
owner release record, at most 256 supplied release records, and **4,096 total
filesystem entries** (including directories) across a manifest. The existing
**4 MiB per-document** limit remains unchanged for manifests, releases and
companion/evidence inputs. These are refusal ceilings, not measured capacity
or a promise to finish within a maintenance window. There are no override or
automatic splitting/batching options; an oversized request must be narrowed
and reviewed rather than silently turned into new approvals.

Manifest target/advertised-entry bounds are checked before tree inspection.
Inventory also enforces the actual aggregate entry budget while traversing,
with bounded directory enumeration rather than materializing an unlimited
directory listing. An incrementally encoded manifest must fit the document
limit before stdout or an output file receives it. An 85,000-file request is
**not supported**, even if bundled into a small number of manifest targets.

Overlap checks use sorted component paths and adjacent-prefix checks; evidence
containment uses a binary-search index and unique reference paths. Each owner
release is parsed/indexed once per inspection, not once per nominated file.
All collected reference bytes are freshly SHA-validated at the inspection
boundary, so a late change cannot hide behind the parsed snapshot. Directory
child lists are indexed once rather than rescanning the entire target's entry
map for every directory.

During apply, each removal revalidates the **current target's** eligibility and
owner identity, rather than running Git and eligibility checks for every other
target. Structural membership/protected-reference checks are reused only while
the manifest is pinned and the exact companion digest is freshly verified.
This is not a cache of mutable authorization: the existing full `policy.check`
still runs at both per-removal guard points, rereading current approval,
attestation, evidence, writer fingerprints, root identities and Git registries.
Every unique target-release/evidence reference is also reread and SHA-checked
at each guard, including references for future or already processed targets.
Thus changed evidence for another target still stops the current operation.

**Residual cost is intentionally explicit.** For `R` removals and `T` targets,
there are `2R + 2` full companion checks (including construction/start) and
`2R + T` full open-file scans. Each companion check still rereads/canonicalizes
the complete bounded manifest and inspects all approved writer/registry
inputs; each guard rereads all unique release/evidence bytes. Therefore runtime
still includes work proportional to removals times those global input sizes.
Only the redundant all-target eligibility/Git traversal, release reparsing,
containment and child-list loops have been removed. This does **not** claim
linear total wall time as the authorization package grows.

Removing that remaining global cost safely would require a separately reviewed
authorization/invalidation design with equivalent detection of mutable
evidence, registry and open-use changes. Neither a metadata-only freshness
guess, a timed cache, nor omission of global checks is adopted here. Keep
manifests small and preserve per-unlink expiry/partial-journal behavior;
substantial landscape-scale reclamation still needs separate design and
performance work, as does historical-owner support for deleted worktrees.

Each manifest target has exactly `kind`, `path`, `owner`, `session_id`,
`worktree`, `released_at`, `release_record`, `release_evidence`, `observed_at`,
`retention`, `root`, and `tree`. `release_record` and `release_evidence` are
private SHA-bound references; worktree identity is path/device/inode.
`retention` contains `minimum_seconds` and `youngest_entry_at`.
`root` contains device/inode.
`tree` contains `sha256`, `entries`, `allocated_bytes`, and `apparent_bytes`.
Its digest binds sorted relative entries, type, UID/mode, device/inode, link
count, size/blocks, and modification/change/birth timestamps. These are metadata
identities, not content hashes. Renames, edits, additions and replacements
invalidate the approved inventory.

Sizes are sums of `st_size` and `st_blocks * 512`, **not** uniquely owned APFS
extents or a promise of physical free space. APFS clones and snapshots can
retain blocks after unlink. Neither inventory nor committing this tool reclaims
bytes; a future authorized cleanup must report actual filesystem free-space
changes separately, with concurrent-writer attribution limits.

Only in a later, separately approved and fully covered window:

```bash
/reviewed/bundle/tools/with-apple-build-lease.sh --exclusive cleanup/exact-manifest -- \
  /usr/bin/python3 -B /reviewed/bundle/tools/apple-build-cleanup.py apply \
  --manifest /physical/private/manifest.json \
  --window-id 00000000-0000-0000-0000-000000000000 \
  --journal /physical/private/new-window-journal.jsonl
```

The zero UUID is illustrative; a real call must use its approved window ID.

The global-cleanup cohort must fingerprint the executing CLI/module,
`apple_maintenance_policy.py`, `apple-build-guard.sh`, and all four frozen lease
files in that same reviewed bundle. The target owner worktrees must appear in
the approved app cohorts/registries. These extra checks prevent merely
fingerprinting an unrelated cleanup script. They do not automatically discover
unregistered/raw/manual writers.

Apply repeats the existing full companion/lease validation, exact registry
inspection, owner evidence hashes, bundle/coverage checks and existing build
process defense before each removal. New unresolved records, changed evidence,
missing inherited capabilities, an unlocked coordination file, suspension,
window drift/expiry or backward clock movement stop it. Open paths **and**
device/inode aliases are refreshed during each step; incomplete `lsof` output
refuses. Only its own known directory descriptors are excluded from that scan.
Elapsed-time and UTC deadlines are checked immediately before every
descriptor-relative unlink/rmdir. Directories are opened without following
links and their ancestor identities are rechecked; arbitrary path-recursive
deletion is never used.

A private, create-new JSONL journal is outside all targets. It contains the
manifest and authorization digests, a complete manifest snapshot, and durable
per-entry intent/outcome records. Intent is fsynced (including `F_FULLFSYNC` on
macOS) before unlink; parent directories and outcomes are synced afterward.
Short writes are completed; write/fsync failures are surfaced. A crash can leave
an intent without an outcome, which means **possibly removed**, not untouched.
SIGINT/SIGHUP/SIGTERM stop subsequent removals and preserve a stopped record when
the journal remains writable. The wrapper retains failed lease evidence.
There is no rollback, automatic retry/resume, or automatic journal deletion.
Partial trees and journals require owner review and a newly approved manifest.

This is a cooperative, same-UID operational boundary, not protection against a
malicious process that ignores the approved hold. No portable pathname unlink
can atomically assert an inode while excluding arbitrary uncooperative writers.
Descriptor-relative traversal and repeated checks detect observed drift; the
whole-lane interlock and verified writer coverage are mandatory. Per-entry
inspection intentionally prioritizes refusal over throughput: use bounded
manifests, not a two-hour promise to drain an entire machine.

### Remaining rollout gates

Keep production suspension, both broad schedules, installed scripts, warm
roots, leases and evidence unchanged until separately authorized:

1. Review/land this adapter and install an exact fingerprinted bundle outside
   shipping. Retire or enhance **every** machine-wide cleanup entrypoint; the
   repository legacy scripts' refusal does not update installed copies.
2. Inventory all writers, including unattended update jobs and raw Xcode/MCP
   paths. Complete whole-lane wrapping or obtain actual bounded owner holds.
   Account for active and queued work and all current/legacy cohorts.
3. Investigate retained lease records with their actual owners and durable lane
   evidence. Any exact owner-approved record resolution is a separate operation;
   this adapter neither performs it nor treats records as stale.
4. Obtain genuine exact-target releases, wait the full retention period, inspect
   the inventory, and obtain cohort attestations followed by human approval of
   that exact manifest/window. Install its companion with the existing CAS tool.
5. Only a separately approved policy-lock activation may open the existing
   suspension/rollout gates. A first bounded cleanup requires the exclusive
   lease, complete runtime checks and retained journal. Recurrence requires new
   eligible owner releases and approved windows, not an age-based unattended
   sweep or blanket standing deletion permission.

## Canonical digests and window documents

The manifest digest includes **all** parsed fields, including provenance and
release evidence, using:

```python
hashlib.sha256(json.dumps(
    manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False
).encode("utf-8")).hexdigest()
```

The same canonical encoding is used for `scope_sha256`. Other document
references use SHA-256 of their exact file bytes. A reference is exactly
`{"path": "/physical/private/file", "sha256": "<64 lowercase hex>"}`.

Window request fields (exact, no unknown fields):

| Field | Value |
| --- | --- |
| `schema` | Integer `1` |
| `host` | Exact `host` command result: effective UID, physical home/namespace identities, coordination device/inode |
| `window` | `id` UUID, UTC `not_before`/`expires_at`, exact `scope` above, canonical `manifest_sha256` |
| `cohorts` | One `{"name": "...", "roots": [...]}` for each required cohort |
| `registries` | `{"app": "plozz\|mozz\|twozz\|hozz", "root": "/physical/repo", "sha256": "..."}` entries |
| `approval` | Private SHA-bound reference to a supplied human approval document |

The window must be open now, positive, and no longer than two hours. Each root
is `{"identity": {"path": "...", "device": 1, "inode": 2}, "writers": [...]}`.
`writers` is a nonempty list of path/SHA-256 references covering the actual
entrypoints reviewed by its owner. Paths must be inside that root. These are
not proof that every entrypoint was discovered; owner review must provide that.

Required cohorts (exact set):

```text
global-cleanup-entrypoints
manual-xcode-writers-disabled-or-wrapped
mozz-current-writers
mozz-legacy-writers
plozz-current-writers
plozz-legacy-writers
twozz-current-writers
twozz-legacy-writers
hozz-current-writers
hozz-legacy-writers
```

Registry digests cover the exact bytes of
`git -C ROOT worktree list --porcelain -z`. The read-only `worktree-snapshot`
command supplies them. Every registered root must appear in that app's combined
current/legacy inventories; every declared app root must be registered. New
roots, removed roots, or HEAD/branch changes require renewed review and approval.
Multiple repositories/clones may be listed per app. Unregistered/unrecognized
repositories are **not** magically discovered: exhaustive host inventory remains
an explicit owner/human responsibility, including raw writers outside Git.

Compute `scope_sha256` over the request with just `approval` omitted. Each
supplied owner attestation has exactly:

```json
{
  "schema": 1,
  "scope_sha256": "<canonical scope digest>",
  "cohort": "<one required cohort>",
  "owner": "<real responsible owner>",
  "session_id": "<actual owner session UUID>",
  "attested_at": "<UTC within the window>",
  "disposition": "<wrapped|held|disabled|absent|enhanced>",
  "active_queued": "<none|protected-by-full-lane-shared-leases>",
  "evidence": [{"path": "<actual durable evidence>", "sha256": "<exact digest>"}]
}
```

`wrapped` requires the frozen four protocol files in every root, in addition to
owner-reviewed writer fingerprints. It permits active/queued work only when
protected by a **whole-lane** shared lease. `held` and `disabled` require explicit
owner evidence covering the entire approved window and no active/queued work;
neither can be inferred from an empty `ps`. `absent` is allowed only for an empty
app cohort, with owner evidence, never for manual/global writers. `enhanced` is
required only for the cleanup cohort: its evidence must confirm every path uses
the companion or has been disabled. A self-labelled v1-only wrapper is rejected.

The human approval document has exactly:

```json
{
  "schema": 1,
  "scope_sha256": "<same exact scope digest>",
  "approved_by": "<actual human approver>",
  "approved_at": "<UTC within window, after every owner attestation>",
  "evidence": {"path": "<actual approval evidence>", "sha256": "<exact digest>"},
  "attestations": ["ONE SHA-BOUND DOCUMENT REFERENCE PER COHORT"]
}
```

Again, placeholders are not real approvals. SHA-bound files prove consistency
with the reviewed package; they do not authenticate a human against another
process running as the same UID. The responsible operator must verify identity,
authority, inventory completeness, and the meaning of approval evidence. A
script cannot police a manual/raw writer that ignores an agreed hold. If those
conditions cannot be established, cleanup remains blocked.

## Evidence retention and tests

Install never inspects away, clears, or resolves failed lease records. Runtime
cleanup still refuses every unresolved record through v1. Owner attestation for
a finished failed lane must name the exact record ID and durable lane evidence;
it is input to a **later separately authorized** resolution, not permission for
this tool to delete it. Archives, IPAs, dSYMs, xcresults, session/release evidence,
Git/worktrees/source, shared dependencies, SDKs, simulators, VMs, Cargo/npm
resources, and Trash remain ineligible regardless of window approval.

Fixture-only validation, no app build:

```bash
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest \
  tools.tests.test_apple_build_cleanup tools.tests.test_apple_maintenance_policy
```

Tests create synthetic attestations exclusively under private temporary HOME
fixtures; no production owner assertions are generated. They cover missing
Hozz, scope/manifest/evidence/identity changes, expiry, raw queued owners,
wrapped-client bytes, registered-root snapshots, exclusive policy-update races,
compare-and-swap, real inherited exclusive checking, suspension, orphan evidence
retention, fixture confinement, and malformed JSON. Cleanup fixtures additionally
exercise no-follow traversal, changed ancestors/files, refreshed open-inode
checks, late evidence/lease drift, unlocked capabilities, protected source and
dependency data, per-removal expiry, short writes, sync/journal failures,
interruptions, partial-progress evidence, and non-activating legacy refusals.
