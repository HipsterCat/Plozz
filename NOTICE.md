# LGPL Compliance — FFmpeg (via AetherEngine / FFmpegBuild)

Plozz's on-device decode engine, **Plozzigen** (the app's branding of the
**AetherEngine** media engine), uses **FFmpeg** to demux and software-decode the
formats `AVPlayer` can't. Plozz does **not** build FFmpeg itself — it is pulled
in transitively, as prebuilt xcframeworks, by AetherEngine via the
**FFmpegBuild** Swift package. This documents FFmpeg's licensing and the LGPL
obligations Plozz must meet to ship it.

## TL;DR

The bundled FFmpeg is a **decode-only, LGPL-2.1-or-later** build — no `--enable-gpl` (so
no GPL-only codecs such as x264/x265) and nothing "nonfree/unredistributable".
It is App-Store-redistributable, subject to the LGPL relink / source-offer /
attribution duties below. FFmpeg's `libav*` libraries ship as xcframeworks
embedded in the app bundle as frameworks (`AetherLibavcodec.framework`,
`AetherLibavformat.framework`, `AetherLibavutil.framework`, `AetherLibswscale.framework`,
`AetherLibavfilter.framework`, `AetherLibswresample.framework`, …).

## What ships, and where it comes from

| Component | Source (pinned) | License |
|---|---|---|
| AetherEngine (media engine; "Plozzigen") | `github.com/brandomoore/AetherEngine` @ `4b7552a06c4cf646bb94eb7eb273946f8b916a70` (7.34.1 + fork fixes) | LGPL-3.0 with Apple Store exception |
| FFmpeg `libav*` (demux / decode / thin HLS-fMP4 mux) | `github.com/superuser404notfound/FFmpegBuild` @ `3.7.0` (FFmpeg **n8.1.3**) | **LGPL-2.1-or-later** |
| dav1d (AV1 software decoder, separate xcframework) | bundled by FFmpegBuild | BSD-2-Clause (permissive) |
| libdovi (Dolby Vision RPU parser) | `github.com/superuser404notfound/LibDovi` @ `2.1.0` | MIT |

Plozz's own `Package.swift` declares **only** AetherEngine for this stack;
FFmpegBuild, LibDovi and LibTrueHD are its transitive dependencies (AetherEngine owns their version
alignment). The concrete pins live in the committed root `Package.resolved`.
`tools/generate-project.sh` copies that canonical lock into generated Xcode
projects at
`Plozz.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Engine linkage and LibTrueHD

The pinned fork exports AetherEngine dynamically to separate its two Rust decoder
runtimes from Plozz's Objective-C/C++ unwind table. Both apps embed and sign
`AetherEngine.framework`; FFmpeg remains in separate dynamic frameworks.

[LibTrueHD 2.2.0](https://github.com/superuser404notfound/LibTrueHD/tree/2.2.0)
is linked into the engine even when its object-audio mode is off. Its C API and
Apple packaging are MIT, copyright Quick104 and Vincent Herbst; the compiled
truehd and oamd crates are Apache-2.0, copyright Rainbaby and contributors.
Both apps ship its unmodified `LICENSE`, `LICENSE-APACHE` and `NOTICE` as
`LibTrueHDLicense.txt`, `LibTrueHDApacheLicense.txt` and `LibTrueHDNotices.txt`.
The shared acknowledgements page credits the library and exact source tag.

## FFmpeg license facts

Upstream FFmpeg `libav*` and FFmpegBuild 3.7.0 are **LGPL-2.1-or-later**.
The build enables neither `--enable-gpl` nor `--enable-version3`; the exact
component licenses and notices live in the release's `LICENSES/` directory.
The build is scoped to demux + decode + a thin HLS-fMP4 mux for
the AVPlayer bridge — **no CLI binaries, no network/protocol stack, and no GPL
or nonfree components** — so there is no GPL/nonfree taint to redistribution.

## LGPL obligations (what Plozz must satisfy to ship)

The bundled LGPL libraries impose **relink**, **source-offer**, and
**attribution** duties:

1. **Dynamic-link / relink ability.** FFmpeg is distributed as xcframeworks
   embedded in the app bundle as frameworks (see the `Copy *.framework` /
   `Signing *.framework` build steps), and the complete corresponding source +
   public build recipe (below) together let a user relink the app against a
   modified FFmpeg. *(Before an App Store submission, confirm the embedded
   frameworks are the relink-eligible artifacts for that release.)*
2. **Source offer.** Publish, or offer in writing, the complete corresponding
   source for the exact FFmpeg version shipped. FFmpegBuild pins FFmpeg
   **n8.1.x** and its build script (`build.sh`) is public at
   `github.com/superuser404notfound/FFmpegBuild`, so the corresponding source is
   fully reproducible from a pinned upstream.
3. **Attribution + license texts.** The in-app **Settings → Acknowledgements**
   screen (`FeatureSettings/IntegrationsDetailView.swift`, `AttributionsDetailView`)
   credits FFmpeg, libdovi, and the other bundled components. Ship FFmpeg's
   LGPL-2.1 license text (and any bundled dependency notices) there and/or in a
   `THIRD_PARTY_LICENSES` file in the bundle.
4. **No GPL/nonfree creep.** Keep the FFmpeg build decode-only: never adopt a
   `--enable-gpl` / `--enable-nonfree` FFmpeg (no x264/x265, etc.). This is owned
   by the FFmpegBuild package, so pin a decode-only LGPL release.

## Verifying the shipped license

FFmpeg compiles its license flags into each framework's `config.h`. To confirm a
build is clean LGPL (no GPL, no nonfree):

```bash
# In the built FFmpeg framework (SwiftPM checkout / DerivedData artifact):
grep -E 'define (FFMPEG_LICENSE|CONFIG_NONFREE|CONFIG_GPL|CONFIG_VERSION3) ' <path>/config.h
# Expect: FFMPEG_LICENSE "LGPL version 2.1 or later", CONFIG_NONFREE 0, CONFIG_GPL 0, CONFIG_VERSION3 0
```

Authoritative build details (FFmpeg version, configure flags, dependency
provenance) live in the FFmpegBuild repository, which produces the binaries.
