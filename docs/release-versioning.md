# Release identity and delivery

Plozz has three distinct version values:

| Value | Example | Purpose |
| --- | --- | --- |
| Public release `version` | `2026.9.29.2` | About, update history, tester notes, and GitHub release title |
| Apple `marketingVersion` | `2026.9.25` | `CFBundleShortVersionString` and App Store Connect's version series |
| `build` | `45` | `CFBundleVersion`, assigned above the highest TestFlight build on either platform |

Keep Apple's existing version series unless deliberately starting a new one.
Apple says later external-testing builds of the same version **might not** need
full review; this is not a guarantee. The beta lane still submits required review.
See [Apple's external-testing guidance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).
An App Store release may require a new Apple version even when a TestFlight
update does not.

## Prepare an explicitly selected release

`App/Resources/ReleaseNotes.json` owns release identity and approved notes.
Historical three-part `version` entries remain unchanged and also supply their
Apple version. New entries use `YYYY.M.D.revision` and an explicit three-part
`marketingVersion`. The date matches `releasedAt`; the positive revision is unique
within that day and orders numerically (`.10` follows `.9`).

```sh
# Read-only proposal; never consumes a revision or modifies the catalog.
python3 tools/release-notes.py next-version

# Inspect the stable local Apple version; public release fields are empty.
python3 tools/release-notes.py identity

# After authoring/reviewing and committing the actual release entry:
python3 tools/release-notes.py identity --release-id release/045 --build 45
python3 tools/release-notes.py validate --release-id release/045 --version 2026.9.25 --build 45
python3 tools/release-notes.py render --release-id release/045 --platform tvOS
python3 tools/release-notes.py render --release-id release/045 --platform iOS
```

The example ID/build above is illustrative, not an existing approved release.
Establish the actual assigned build from App Store Connect before preparing it.
Each intended distribution gets its own entry, notes, and public version. Retries
reuse that exact identity; Git pushes and local builds do not allocate revisions.
Do not add a new entry merely to compile or merge code.

Platform-specific notes use `{"text": "...", "platforms": ["tvOS"]}` or `["iOS"]`;
plain strings apply to both. New-format rendered notes begin with the public
Plozz version so testers can identify the release even while TestFlight's Apple
version is unchanged. For an empty platform, review the beta lane's exact fallback:

```sh
python3 tools/release-notes.py render --release-id release/045 --platform iOS \
  --empty-text "No changes for this platform in this build."
```

## Build and distribute

Use the documented local signing/API configuration; never commit credentials.
Builds retain a shared Apple build lease and platform-private package workspaces.

```sh
# Local archive only; not upload permission.
fastlane build --env fastlane

# Only after explicit distribution permission and release-note approval:
PLOZZ_RELEASE_ID=release/045 fastlane beta --env fastlane

# Separate App Store upload; does not automatically submit App Store review.
PLOZZ_RELEASE_ID=release/045 fastlane release --env fastlane
```

`PLOZZ_MARKETING_VERSION` is an intentional Apple-version override, not the public
release label. With a selected release it must match the catalog's Apple version.
Never put the four-part public label in that override. Both platforms and Top
Shelf share the Apple version/build; apps additionally bake `PlozzReleaseVersion`
and `PlozzReleaseID`. About uses the public label; diagnostic reports retain the
Apple version/build too. Crash-report and protocol version fields retain Apple's
version identity.

Without `PLOZZ_RELEASE_ID`, generation clears the custom release label and keeps
the latest catalog entry's Apple version. Local builds continue to use the Git
commit count and dirty-tree suffix and display that Apple version/build, rather
than claiming to be a newly distributed release.

Before uploading, both distribution lanes check both exported IPAs' platform, identifier,
Apple version/build, and public release version/ID. A mismatch stops both uploads.
After delivery, tags remain `release/<zero-padded-build>`; GitHub release titles
use the public version. Inspect `.build/testflight-uploads/` and both platforms'
actual App Store Connect availability before reporting success. After partial
success, never blindly rerun `beta`, increment the build, or reupload: reconcile
the recorded per-platform outcomes first.
