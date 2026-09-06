# Live TV prototype

A native, Debug-only harness for iterating on a physical Apple TV, iPhone and
iPad. It browses real public channels and plays their HLS streams through
Plozz's existing `NativeVideoEngine`. Production onboarding and navigation
are unchanged.

## Run

Generate the project using the normal wrapper:

```sh
export GIT_CONFIG_PARAMETERS="'safe.bareRepository=all'"
tools/generate-project.sh
```

Open `Plozz.xcodeproj` and run **Plozz Live TV Prototype** on Apple TV or
**PlozziOS Live TV Prototype** on iPhone/iPad. These schemes pass
`--live-tv-prototype` to the existing app target. Device installation must be
explicitly authorized; a build alone does not install anything.

For isolated physical-TV iteration, build a branded Debug app using the existing
per-branch build configuration. It has its own bundle ID, preferences and data;
normal Plozz remains installed and untouched. Cloud sync and Top Shelf are not
enabled for branded builds. Once installed, launch that bundle explicitly:

```sh
xcrun devicectl device process launch --device <device-id> \
  <branded-bundle-id> --live-tv-prototype --live-tv-prototype-remember
```

`--live-tv-prototype-remember` is an explicit Debug-only opt-in: opening the app
again from the TV home screen returns to Live TV. Launch with
`--live-tv-prototype-off` to clear it and return to normal onboarding.
`--live-tv-prototype` alone remains transient and changes no preference.

Additional launch arguments:

- `--live-tv-guide`: start on Guide.
- `--live-tv-5000`: repeat the real catalog into 5,000 clearly labeled rows for
  scrolling tests. These are copies, not 5,000 distinct stations.

The entry route, live host, UI and public test catalog are compiled out of
Release builds.

## Try

**Preview options** switches between the real catalog and the 5,000-row scrolling
test. Favorites and filters are in-memory; restarting the process resets them.

- Browse, search names/numbers/categories/sources, filter and sort.
- Favorite channels through the context menu or iPad channel inspector.
- On Apple TV, move Right from a channel to Search; Left returns to that channel.
  Back to top scrolls and requests focus on the first result.
- Guide honestly shows that no guide is connected. Synthetic schedule scenarios
  remain model-test fixtures only; real channels cannot acquire those programs.
- iPhone and narrow iPad windows use compact channel lists. At wider widths,
  iPad adds channel artwork, details, Favorite and Watch controls.
- Select a channel to watch real video. The live host exposes real buffering,
  failure/retry and live transport state rather than a fabricated VOD timeline.
  Next/Previous follows the currently filtered channel list.
- Back closes playback and releases its engine. Browsing does not leave a hidden
  stream decoding in the background.

## Real inputs and artwork

`LiveTVPrototypeCatalog` contains nine public HLS test inputs: DW English,
Spanish and Arabic, NHK WORLD-JAPAN, TRT World, NBC News NOW, Scripps News,
Red Bull TV and Tastemade. Channel logos come from their corresponding
`tvg-logo` metadata in the [iptv-org catalog](https://github.com/iptv-org/iptv).
Artwork uses the existing decoded-image cache, logo-sized downsampling and
aspect-fit rendering. Light/dark plates preserve the original wordmarks;
failed/missing artwork retains a fixed-size text fallback.

DW/TRT streams were located through official live pages; NHK uses its public
broadcaster HLS host. Other locators were selected from the user-supplied
[US playlist](https://iptv-org.github.io/iptv/countries/us.m3u). Availability and
regional restrictions may change. These are developer test inputs, not a
Plozz-provided channel service, broadcaster endorsement, or permission to
rebroadcast, record or redistribute content. No third-party image binaries
are committed.

The supplied ABC News Live candidate returned 404 during the September 6, 2026
probe and was excluded. A reachable master alone is not sufficient: inspect its
media playlist and segments, then exercise actual device playback.

## Boundaries

Playlist import, XMLTV ingestion/mapping, Plex/Jellyfin/Emby tuner adapters,
generated library channels, profile persistence/sync, PiP, AirPlay integration,
parental policy and recording management remain planned.

The harness does not construct production account/profile models. The small
`FeaturePlayback.LiveChannelPlayerView` hosts the existing real engine without
constructing the VOD `PlayerViewModel`, media-provider reporting sessions, resume
writers or trackers. This avoids incorrectly treating an endless channel as a
movie while leaving ordinary library playback unchanged. App targets inject the
player into `FeatureLiveTV`; UI feature modules do not import one another.

The paired `FeatureLiveTV` / `FeatureLiveTVCore` types are explicitly named
`LiveTVPrototype*`; they are not a final provider API. The core's synthetic
30-channel fixture catalog remains for deterministic guide/filter/state tests,
separate from the real catalog used by the app.

Run the focused model tests through the existing simulator runner:

```sh
tools/run-tests.sh FeatureLiveTVCoreTests
```
