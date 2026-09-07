# Live TV prototype

A native, Debug-only harness for iterating on a physical Apple TV, iPhone and
iPad. It browses real public channels and plays their HLS streams through
Plozz's existing AetherEngine (`PlozzigenVideoEngine`) integration. Production onboarding and navigation
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

The preview loads the complete supplied US playlist, then the enabled XMLTV guides.
Channels become available before guide loading finishes. **Channels / Guide**
switches presentation of the same catalog; **Favorites** is an independent filter.
Search, categories, sorting and Favorites carry across both views and refreshes.
Favorites, filters and guide-source selections are still in-memory; restarting
the process resets them.

- Browse, search names/numbers/categories/sources, filter and sort.
- Favorite channels through the context menu or iPad channel inspector.
- On Apple TV, move Right from a channel (or past its guide programs) to Search.
  Sources lives in that same persistent controls rail, below Sort, rather than
  in an unreachable header corner. Left returns to the channel/program.
  Back to top works in both presentations.
- **Sources** reports playlist entries, skipped entries, guide matches, listings,
  coverage dates and per-feed failures. Its toggles enable or disable the five
  preset guides; disabling one immediately removes its contribution. Results
  appear incrementally, and a failed feed does not block the remaining feeds.
  **Show channels with guide listings** opens Guide
  with the corresponding filter, making the populated rows easy to find.
- Guide retains all channels, even if none has a schedule. Unknown intervals
  remain honest gaps; they do not hide channels or shift later programs under
  the wrong time. Channel buttons still tune live without guide data.
  Empty cells distinguish loading, disabled sources, a failed relevant source,
  an unmatched station and an identified station with no listings for that time.
  Program details identify the selected guide source.
- Guide dates and now-playing labels advance with the wall clock. Earlier/Later
  pages from one day back through seven days ahead, subject to source coverage.
- iPhone and narrow iPad windows use compact channel lists. At wider widths,
  iPad adds channel artwork, details, Favorite and Watch controls.
- Select a channel to watch real video. The live host exposes real buffering,
  failure/retry and live transport state rather than a fabricated VOD timeline.
  Next/Previous follows the currently filtered channel list.
- Back closes playback and releases its engine. Browsing does not leave a hidden
  stream decoding in the background.

## Real inputs and artwork

The default inputs are:

- Playlist: `https://iptv-org.github.io/iptv/countries/us.m3u`
- Pluto TV US: `https://i.mjh.nz/PlutoTV/us.xml.gz`
- Samsung TV Plus US: `https://i.mjh.nz/SamsungTVPlus/us.xml.gz`
- Plex US: `https://i.mjh.nz/Plex/us.xml.gz`
- EPGShare US2: `https://epgshare01.online/epgshare01/epg_ripper_US2.xml.gz`
- EPGShare Plex: `https://epgshare01.online/epgshare01/epg_ripper_PLEX1.xml.gz`

The September 6, 2026 source snapshots import 1,468 stream entries across 28
primary categories, with 1,443 logo URLs. The multi-feed import provides listings
for 253 streams, compared with 70 in the original US2-only build. Evaluated at
2026-09-07 03:04 UTC, all 253 had current listings, with 11,257 programs retained.
The selected sources supply 185 Pluto, two Samsung, three Plex and 63 US2
schedules; EPGShare Plex supplies overlapping fallback data, not extra channels.
These counts describe those snapshots, not guaranteed availability or coverage.
The remaining 1,215 streams stay available without invented program information.

Playlist entries are not necessarily distinct stations: feeds can include
alternate resolutions and stream providers. Stable stream identities preserve
variants without duplicate row IDs. Channel logos come from `tvg-logo` metadata
in the [iptv-org catalog](https://github.com/iptv-org/iptv).
Artwork uses the existing decoded-image cache, logo-sized downsampling and
aspect-fit rendering. Light/dark plates preserve the original wordmarks;
failed/missing artwork retains a fixed-size text fallback.

The original nine-channel `LiveTVPrototypeCatalog` remains a small regression
fixture, not the app's default catalog or a channel limit.

Availability and regional restrictions may change. These are developer test inputs, not a
Plozz-provided channel service, broadcaster endorsement, or permission to
rebroadcast, record or redistribute content. No third-party image binaries
are committed.

Import does not certify that every stream plays. A reachable master alone is
not sufficient: inspect its media playlist and segments, then exercise actual
device playback. Playlist request headers pass through the live host to Aether,
including retries and automatic source resets.

Guide loading and parsing run outside the main actor. Listings are associated
with imported channel identities, not synthetic layout scenarios. Unknown or
ambiguous matches receive no schedule. Guide failure does not remove a working
playlist; failed refreshes preserve the last successfully imported data that
still belongs to current channels.

Matching first uses exact native Pluto IDs from recognized stream URLs, then
explicit guide IDs, verified aliases and unique display names. Provider guides
only use name matching for streams identified as that provider; similarly named
streams from unknown or different providers are not silently assigned a FAST
schedule. Explicit foreign Samsung stream origins are excluded from the US
guide even when the playlist's station ID ends in `.us`. Country, affiliate
and time-shift conflicts continue to prevent name-based matches. An unmatched
native Pluto ID is not replaced with a guessed same-name station.

Each stream receives one whole schedule, never interleaved programs from
different feeds. Stronger identity evidence wins. Equal-confidence matches
prefer a schedule with upcoming listings, then the source order shown above.
An unavailable refresh retains that source's last good data for current channels.
Source changes fence late network/parse results before reloading.

Compressed input, expanded XML, retained text and program counts are bounded.
The combined in-memory guide cache is also capped at 250,000 programs and
32 MiB of program title/subtitle text. Sequential feed loading limits transient
memory. Two streaming XML passes discover channel metadata before retaining
matched programs, supporting feeds that interleave channel declarations and
listings without keeping all unmatched programs in memory. Plain XML and gzip
are accepted. Normal external XMLTV DOCTYPE headers are accepted without
retrieving the DTD; entity declarations remain rejected.
Custom-source onboarding and persistent guide caching are not exposed.

## Boundaries

General source onboarding, manual guide mapping, Plex/Jellyfin/Emby tuner
adapters, generated library channels, profile persistence/sync, PiP, AirPlay
integration, parental policy and recording management remain planned. This
iteration connects selectable public guide presets, not a finished multi-source
account manager. Many streams still lack a confidently identified schedule;
more name guesses are not a substitute for accurate provider/region mapping.

The harness does not construct production account/profile models. The small
`FeaturePlayback.LiveChannelPlayerView` hosts the existing real engine without
constructing the VOD `PlayerViewModel`, media-provider reporting sessions, resume
writers or trackers. This avoids incorrectly treating an endless channel as a
movie while leaving ordinary library playback unchanged. App targets inject the
player into `FeatureLiveTV`; UI feature modules do not import one another.
The app also injects the `LiveChannelEngine` implementation into the host, so
`FeaturePlayback` does not depend back on `EnginePlozzigen`. Engine initialization
failures are visible; the prototype never silently substitutes direct AVPlayer.

The paired `FeatureLiveTV` / `FeatureLiveTVCore` types are explicitly named
`LiveTVPrototype*`; they are not a final provider API. The core's synthetic
30-channel fixture catalog remains for deterministic guide/filter/state tests,
separate from the real catalog used by the app.

## Live activity and diagnostics

The centered activity indicator is owned by `LiveChannelPlayerModel` and driven
by AetherEngine's typed `playbackPhase`, gated on
`hasFirstFrameReadyForDisplay` for initial video. Connecting, buffering, seeking
and reconnecting are distinct. The host no longer reconstructs engine state
from AVPlayer transport hints or a second playback-clock classifier.

TV controls keep one stable set of focus targets. Native glass supplies its own
focus appearance: button styles must not switch in response to `FocusState`,
which replaces the focused control and can stall focus/layout resolution.
Close receives focus when controls mount, without waiting for the stream load.
The connecting indicator does not intercept input. On-device regression checks
must include video rendering and Back/Close while a channel is still connecting;
the headless package test runner has no window scene to exercise TV focus.

Live loads use `isLive: true`, the stable `.standard` join profile and native
remote HLS with Aether's compatibility fallback. A native HLS route still uses
AVPlayer internally; Aether owns route selection, engine state and recovery.
The host uses actual live seekable ranges and Aether's Go Live API, never a
fabricated movie timeline or a guessed seek target.
Native HLS uses the origin's actual sliding window; no local DVR duration is
invented. If compatibility recovery switches to ingest without a DVR window,
timeshift controls disable rather than promising unavailable rewind.

The host subscribes to `liveSourceReset` before loading. A fixed public channel
reopens the same URL, with one automatic retune in flight, at least 20 seconds
between automatic attempts and at most three per channel-viewing session.
Duplicate signals coalesce, pause/inactivity defers recovery, and exhaustion is
visible. Two manual retries remain available; they do not replenish automatic
recovery's budget. Startup is bounded at 30 seconds and sustained activity/stall
at 60 seconds, leaving room for Aether's own recovery before failing visibly.

This prototype is foreground-only. Inactivity pauses; actual background entry
stops its engine, and foreground return opens a fresh live session. A user-paused
channel stays paused until explicitly resumed. Stop, failure, backgrounding and
replacement invalidate outstanding loads and seeks. Ordinary VOD playback and
its lifecycle remain unchanged.

Debug diagnostics use the existing `HandoffDiagnostics` bounded playback journal
and `PlozzLog` recent-log ring, tagged `LIVE_TV` with `engine=AetherEngine`.
Snapshots include typed playback phase, actual video route, first-frame readiness,
playback/buffered positions, behind-live time and seekable bounds. Changes are coalesced to at most one
snapshot per second; steady playback emits a heartbeat every ten seconds.
Lifecycle and classified failure events are also recorded. Correlation uses a
random session ID, not a channel name, locator or credential. Error text and
raw URLs are never included in these new events.

The journal is `Library/Caches/Plozz/playback-trace.log` (64 KiB limit).
Use existing in-app diagnostics export when available. Do not copy the active
tvOS app container, attach a debugger, or relaunch with `--console` during
someone's viewing without authorization: these can interrupt playback.
The existing `PlozzigenVideoEngine` log mirror is reused; the live host installs
no competing `EngineLog.handler`.

Run the focused model tests through the existing simulator runner:

```sh
tools/run-tests.sh FeatureLiveTVCoreTests
tools/run-tests.sh FeaturePlaybackTests EnginePlozzigenTests
```
